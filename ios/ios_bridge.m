#import "ios_bridge.h"
#import "ac_pal_bridge.h"
#include <string.h>
#include <math.h>
#include <stdatomic.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>

/* Exported by the Rust staticlib (ac-ios-runtime). */
extern void ac_ios_core_lap_state(void *session, ACIosLapState *out);

static NSString *gContentRoot = @"";
static ACIosInputState gInput = {0};
static CAMetalLayer *gMetalLayer = nil;
static float gRpm = 0.0f;
static float gLoad = 0.0f;

void ac_ios_set_content_root(NSString *path) {
    gContentRoot = path ? [path copy] : @"";
}

void ac_ios_set_metal_layer(void *layer) {
    gMetalLayer = (__bridge CAMetalLayer *)layer;
}

void ac_ios_set_input(ACIosInputState state) {
    gInput = state;
}

int ac_ios_content_root(char *buf, size_t cap) {
    if (!buf || cap == 0) return -1;
    const char *utf8 = [gContentRoot UTF8String];
    size_t len = strlen(utf8);
    if (len + 1 > cap) return -2;
    memcpy(buf, utf8, len + 1);
    return (int)len;
}

int ac_ios_input_state(ACIosInputState *out) {
    if (!out) return -1;
    *out = gInput;
    return 0;
}

#pragma mark - Diagnostic synthesized audio

/*
 * The user's AC install contains per-car FMOD .bank files, but no FMOD iOS SDK
 * is available in this project. We therefore do NOT claim original AC audio.
 * This is an explicitly diagnostic synthesizer: a small AVAudioSourceNode whose
 * render callback reads atomically published REAL GameSim telemetry (rpm,
 * throttle, brake, speed, gear) and produces engine + road/wind sound. No file
 * I/O, no allocation and no locks in the real-time callback.
 */
typedef struct {
    _Atomic float rpm;
    _Atomic float throttle;
    _Atomic float brake;
    _Atomic float speed;
    _Atomic float gear;
    _Atomic float master;
    _Atomic float engine;
    _Atomic float effects;
    _Atomic int muted;
    _Atomic int initialized;
    _Atomic int running;
    _Atomic int failures;
} AcAudioState;

static AcAudioState gAudio;
static AVAudioEngine *gAudioEngine = nil;
static AVAudioSourceNode *gAudioSource = nil;
static double gAudioRate = 48000.0;
static double gEnginePhase = 0.0;
static double gHarmonicPhase = 0.0;
static uint32_t gNoiseLcg = 0x13572468u;
static BOOL gAudioObserversInstalled = NO;

static inline float aclampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

static void ac_audio_interruption(NSNotification *note) {
    NSDictionary *info = note.userInfo;
    NSNumber *type = info[AVAudioSessionInterruptionTypeKey];
    if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) {
        [gAudioEngine pause];
        atomic_store(&gAudio.running, 0);
        NSLog(@"ac_ios_audio: interruption began — engine paused");
    } else {
        NSNumber *options = info[AVAudioSessionInterruptionOptionKey];
        if (options.unsignedIntegerValue & AVAudioSessionInterruptionOptionShouldResume) {
            NSError *e = nil;
            [gAudioEngine startAndReturnError:&e];
            atomic_store(&gAudio.running, e == nil);
            if (e) atomic_fetch_add(&gAudio.failures, 1);
            NSLog(@"ac_ios_audio: interruption ended — resume %@", e ? e.localizedDescription : @"ok");
        }
    }
}

static void ac_audio_route_change(NSNotification *note) {
    NSLog(@"ac_ios_audio: route change reason=%@ — engine kept running",
          note.userInfo[AVAudioSessionRouteChangeReasonKey]);
}

int ac_ios_audio_init(char *err, size_t cap) {
    if (atomic_load(&gAudio.initialized)) return 0;
    if (!gAudioObserversInstalled) {
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *n) { ac_audio_interruption(n); }];
        [nc addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *n) { ac_audio_route_change(n); }];
        gAudioObserversInstalled = YES;
    }

    NSError *error = nil;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    // MixWithOthers: do not silence music or other apps unexpectedly.
    BOOL ok = [session setCategory:AVAudioSessionCategoryPlayback
                              mode:AVAudioSessionModeDefault
                           options:AVAudioSessionCategoryOptionMixWithOthers
                             error:&error];
    if (!ok) {
        NSString *msg = error.localizedDescription ?: @"audio session category failed";
        NSLog(@"ac_ios_audio: session category FAILED: %@", msg);
        if (err && cap) strncpy(err, msg.UTF8String, cap - 1);
        atomic_fetch_add(&gAudio.failures, 1);
        return -1;
    }
    ok = [session setActive:YES error:&error];
    if (!ok) {
        NSString *msg = error.localizedDescription ?: @"audio session activation failed";
        NSLog(@"ac_ios_audio: activation FAILED: %@", msg);
        if (err && cap) strncpy(err, msg.UTF8String, cap - 1);
        atomic_fetch_add(&gAudio.failures, 1);
        return -2;
    }

    AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                            sampleRate:48000.0
                                                              channels:1
                                                           interleaved:NO];
    gAudioRate = format.sampleRate;
    AVAudioSourceNode *source = [[AVAudioSourceNode alloc] initWithRenderBlock:
        ^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp,
                  AVAudioFrameCount frameCount, AudioBufferList *outputData) {
        (void)timestamp;
        float *out = (float *)outputData->mBuffers[0].mData;
        if (!out) return noErr;
        float rpm = aclampf(atomic_load(&gAudio.rpm), 0.0f, 9000.0f);
        float throttle = aclampf(atomic_load(&gAudio.throttle), 0.0f, 1.0f);
        float brake = aclampf(atomic_load(&gAudio.brake), 0.0f, 1.0f);
        float speed = aclampf(atomic_load(&gAudio.speed), 0.0f, 340.0f);
        float master = aclampf(atomic_load(&gAudio.master), 0.0f, 1.0f);
        float eng = aclampf(atomic_load(&gAudio.engine), 0.0f, 1.0f);
        float fx = aclampf(atomic_load(&gAudio.effects), 0.0f, 1.0f);
        float mute = atomic_load(&gAudio.muted) ? 0.0f : 1.0f;
        // Four-cylinder firing order: rpm/30 Hz. Idle is quiet, full rpm loud.
        double freq = (double)rpm / 30.0;
        double step = 2.0 * M_PI * freq / gAudioRate;
        double step2 = step * 2.02;
        float gain = eng * master * mute * (rpm > 50.0f ? (0.10f + 0.36f * throttle + rpm / 9000.0f * 0.18f) : 0.0f);
        float road = fx * master * mute * (speed / 340.0f) * 0.16f;
        float brakeGain = fx * master * mute * brake * 0.07f;
        for (AVAudioFrameCount i = 0; i < frameCount; i++) {
            gEnginePhase += step;
            gHarmonicPhase += step2;
            if (gEnginePhase > 2.0 * M_PI) gEnginePhase -= 2.0 * M_PI;
            if (gHarmonicPhase > 2.0 * M_PI) gHarmonicPhase -= 2.0 * M_PI;
            gNoiseLcg = gNoiseLcg * 1664525u + 1013904223u;
            float noise = ((float)(gNoiseLcg >> 8) / 8388608.0f) - 1.0f;
            float tone = (float)(sin(gEnginePhase) * 0.75 + sin(gHarmonicPhase) * 0.25);
            float v = tone * gain + noise * (road + brakeGain);
            // Soft clip without allocation; keeps overlapping voices from clipping.
            out[i] = v / (1.0f + fabsf(v));
        }
        *isSilence = (master <= 0.0f || mute <= 0.0f);
        return noErr;
    }];

    gAudioEngine = [[AVAudioEngine alloc] init];
    gAudioSource = source;
    [gAudioEngine attachNode:source];
    [gAudioEngine connect:source to:gAudioEngine.mainMixerNode format:format];
    [gAudioEngine prepare];
    [gAudioEngine startAndReturnError:&error];
    if (error) {
        NSString *msg = error.localizedDescription ?: @"audio engine start failed";
        NSLog(@"ac_ios_audio: engine FAILED: %@", msg);
        if (err && cap) strncpy(err, msg.UTF8String, cap - 1);
        atomic_fetch_add(&gAudio.failures, 1);
        return -3;
    }
    atomic_store(&gAudio.master, 0.80f);
    atomic_store(&gAudio.engine, 0.90f);
    atomic_store(&gAudio.effects, 0.70f);
    atomic_store(&gAudio.muted, 0);
    atomic_store(&gAudio.initialized, 1);
    atomic_store(&gAudio.running, 1);
    NSLog(@"ac_ios_audio: ready (diagnostic synthesizer, NOT original AC banks)");
    return 0;
}

void ac_ios_audio_shutdown(void) {
    if (gAudioEngine) {
        [gAudioEngine stop];
        [gAudioEngine detachNode:gAudioSource];
    }
    gAudioSource = nil;
    gAudioEngine = nil;
    atomic_store(&gAudio.running, 0);
    atomic_store(&gAudio.initialized, 0);
    NSError *e = nil;
    [AVAudioSession.sharedInstance setActive:NO error:&e];
}

void ac_ios_audio_set_state(float rpm, float throttle, float brake, float speed, float gear) {
    atomic_store(&gAudio.rpm, rpm);
    atomic_store(&gAudio.throttle, throttle);
    atomic_store(&gAudio.brake, brake);
    atomic_store(&gAudio.speed, speed);
    atomic_store(&gAudio.gear, gear);
}

void ac_ios_audio_set_volumes(float master, float engine, float effects) {
    atomic_store(&gAudio.master, aclampf(master, 0.0f, 1.0f));
    atomic_store(&gAudio.engine, aclampf(engine, 0.0f, 1.0f));
    atomic_store(&gAudio.effects, aclampf(effects, 0.0f, 1.0f));
}

void ac_ios_audio_set_mute(int muted) { atomic_store(&gAudio.muted, muted ? 1 : 0); }

int ac_ios_audio_status(char *buf, size_t cap) {
    if (!buf || cap == 0) return -1;
    snprintf(buf, cap,
             "init=%d running=%d failures=%d rpm=%.0f throttle=%.2f brake=%.2f speed=%.1f "
             "master=%.2f engine=%.2f fx=%.2f mute=%d source=diagnostic-synth",
             atomic_load(&gAudio.initialized), atomic_load(&gAudio.running),
             atomic_load(&gAudio.failures),
             atomic_load(&gAudio.rpm), atomic_load(&gAudio.throttle), atomic_load(&gAudio.brake),
             atomic_load(&gAudio.speed), atomic_load(&gAudio.master), atomic_load(&gAudio.engine),
             atomic_load(&gAudio.effects), atomic_load(&gAudio.muted));
    return 0;
}

int ac_ios_audio_set(float rpm, float load) {
    gRpm = rpm;
    gLoad = load;
    ac_ios_audio_set_state(rpm, load, 0.0f, 0.0f, 0.0f);
    return 0;
}

void ac_ios_audio_suspend(void) {
    if (gAudioEngine && atomic_load(&gAudio.running)) {
        [gAudioEngine pause];
        atomic_store(&gAudio.running, 0);
    }
}

void ac_ios_audio_resume(void) {
    if (gAudioEngine && atomic_load(&gAudio.initialized) && !atomic_load(&gAudio.running)) {
        NSError *e = nil;
        [gAudioEngine startAndReturnError:&e];
        if (e) {
            atomic_fetch_add(&gAudio.failures, 1);
            NSLog(@"ac_ios_audio: resume FAILED: %@", e.localizedDescription);
        } else {
            atomic_store(&gAudio.running, 1);
        }
    }
}

void *ac_ios_metal_layer(void) {
    return (__bridge void *)gMetalLayer;
}

int ac_ios_lap_state(ACIosLapState *out) {
    if (!out) return -1;
    memset(out, 0, sizeof(*out));
    void *session = ac_pal_bridge_session();
    if (!session) return -1;
    ac_ios_core_lap_state(session, out);
    return 0;
}

uint64_t ac_ios_memory_footprint(void) {
    // mach_task_basic_info has no phys_footprint on the iOS SDK. task_vm_info
    // is the public API that reports the same Jetsam footprint (see Rust
    // meminfo.rs, which uses TASK_VM_INFO_REV5).
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    memset(&info, 0, sizeof(info));
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) {
        return 0;
    }
    return (uint64_t)info.phys_footprint;
}

int ac_ios_install_core_vtable(void) {
    AcCoreVTable vtable = {0};
    if (ac_ios_boot(&vtable) != 0) return -1;
    return ac_pal_bridge_init(&vtable);
}

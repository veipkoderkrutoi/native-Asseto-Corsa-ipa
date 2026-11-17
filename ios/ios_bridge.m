#import "ios_bridge.h"
#import "ac_pal_bridge.h"
#include <string.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

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

int ac_ios_audio_set(float rpm, float load) {
    // CoreAudio engine wiring is pending: rustyAC's FMOD backend is
    // Windows/WASM-only today. We record state instead of faking sound.
    gRpm = rpm;
    gLoad = load;
    return 0;
}

void ac_ios_audio_suspend(void) { /* TODO: AudioEngine pause */ }
void ac_ios_audio_resume(void)  { /* TODO: AudioEngine resume */ }

void *ac_ios_metal_layer(void) {
    return (__bridge void *)gMetalLayer;
}

int ac_ios_install_core_vtable(void) {
    AcCoreVTable vtable = {0};
    if (ac_ios_boot(&vtable) != 0) return -1;
    return ac_pal_bridge_init(&vtable);
}

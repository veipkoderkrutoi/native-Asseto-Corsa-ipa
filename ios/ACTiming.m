#import "ACTiming.h"
#import <mach/mach_time.h>

static double ac_monotonic_seconds(void) {
    static mach_timebase_info_data_t info;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&info); });
    uint64_t t = mach_absolute_time();
    return (double)t * (double)info.numer / (double)info.denom / 1e9;
}

@interface ACTiming ()
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) uint32_t lapCount;
@property (nonatomic, assign) uint32_t lastLapMs;
@property (nonatomic, assign) uint32_t bestLapMs;
@property (nonatomic, assign) int32_t cuts;
@property (nonatomic, assign) BOOL valid;
@property (nonatomic, assign) double lapStart;
@property (nonatomic, assign) double pausedAt;
@property (nonatomic, assign) double pausedTotal;
@property (nonatomic, assign) uint32_t baselineLaps;
@end

@implementation ACTiming

+ (NSString *)formatMs:(uint32_t)ms {
    char buf[32] = {0};
    if (ac_ios_format_lap_ms(ms, buf, sizeof(buf)) > 0) {
        return [NSString stringWithUTF8String:buf];
    }
    return @"--:--.---";
}

- (void)startWithBest:(uint32_t)bestMs {
    self.running = YES;
    self.paused = NO;
    self.lapStart = ac_monotonic_seconds();
    self.pausedAt = 0;
    self.pausedTotal = 0;
    self.baselineLaps = 0;
    self.lapCount = 0;
    self.lastLapMs = 0;
    self.bestLapMs = bestMs;
    self.cuts = 0;
    self.valid = YES;
}

- (void)pause {
    if (!self.running || self.paused) return;
    self.paused = YES;
    self.pausedAt = ac_monotonic_seconds();
}

- (void)resume {
    if (!self.running || !self.paused) return;
    self.pausedTotal += ac_monotonic_seconds() - self.pausedAt;
    self.paused = NO;
}

- (void)stop {
    self.running = NO;
    self.paused = NO;
}

- (uint32_t)currentMs {
    if (!self.running) return 0;
    double now = self.paused ? self.pausedAt : ac_monotonic_seconds();
    double elapsed = now - self.lapStart - self.pausedTotal;
    if (elapsed < 0) elapsed = 0;
    return (uint32_t)(elapsed * 1000.0);
}

- (void)updateWithLap:(ACIosLapState)lap {
    if (!self.running || !lap.on_track) return;
    self.cuts = lap.cuts;
    self.valid = lap.valid != 0;

    if (self.baselineLaps == 0 && lap.laps > 0) {
        self.baselineLaps = lap.laps;
    }

    uint32_t completed = lap.laps > self.baselineLaps ? lap.laps - self.baselineLaps : 0;
    if (completed > self.lapCount) {
        self.lapCount = completed;
        // AC's own lap time is authoritative; the monotonic clock is a fallback.
        uint32_t finished = lap.last_ms > 0 ? lap.last_ms : [self currentMs];
        self.lastLapMs = finished;
        if (ac_ios_should_accept_pb(finished, lap.last_valid, lap.cuts, self.bestLapMs)) {
            self.bestLapMs = finished;
            if (self.onLap) self.onLap(finished, YES, lap.cuts);
        } else if (self.onLap) {
            self.onLap(finished, NO, lap.cuts);
        }
        self.lapStart = ac_monotonic_seconds();
        self.pausedTotal = 0;
        if (self.paused) self.pausedAt = self.lapStart;
    }
}

@end

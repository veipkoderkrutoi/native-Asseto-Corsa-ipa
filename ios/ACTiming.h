#import <Foundation/Foundation.h>
#import "ios_bridge.h"

/// Time Attack state machine. Current lap time uses a MONOTONIC clock; lap
/// completion and the official lap time come from the real AC GameSim lap timer
/// (ACIosLapState), never from guessed coordinates or wall-clock time.
@interface ACTiming : NSObject

@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) BOOL paused;
@property (nonatomic, readonly) uint32_t currentMs;
@property (nonatomic, readonly) uint32_t lapCount;
@property (nonatomic, readonly) uint32_t lastLapMs;
@property (nonatomic, readonly) uint32_t bestLapMs;
@property (nonatomic, readonly) int32_t cuts;
@property (nonatomic, readonly) BOOL valid;
@property (nonatomic, copy, nullable) void (^onLap)(uint32_t ms, BOOL personalBest, int32_t cuts);

- (void)startWithBest:(uint32_t)bestMs;
- (void)pause;
- (void)resume;
- (void)stop;
- (void)updateWithLap:(ACIosLapState)lap;

+ (NSString *)formatMs:(uint32_t)ms;

@end

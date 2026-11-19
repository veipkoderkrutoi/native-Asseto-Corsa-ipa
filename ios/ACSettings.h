#import <Foundation/Foundation.h>

/// Persistent user preferences and local Personal Best records.
/// Small settings live in NSUserDefaults; records are a dictionary keyed by
/// `car|track`, so different cars/tracks can never share a lap record.
@interface ACSettings : NSObject

+ (instancetype)shared;

// Index into the Rust FPS_CAPS table: 0 Auto, 1=30, 2=40, 3=45, 4=60.
@property (nonatomic, assign) NSInteger fpsCapIndex;
@property (nonatomic, assign) float masterVolume;
@property (nonatomic, assign) float engineVolume;
@property (nonatomic, assign) float effectsVolume;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) float steerSensitivity;
@property (nonatomic, assign) float steerDeadzone;
@property (nonatomic, assign) BOOL hudVisible;
@property (nonatomic, assign) BOOL diagnosticsEnabled;
@property (nonatomic, assign) BOOL autoShifter;
@property (nonatomic, assign) NSInteger gameMode;   // 0 practice, 1 time attack, 2 hotlap, 3 free drive
@property (nonatomic, assign) NSInteger units;      // 0 metric, 1 imperial
@property (nonatomic, assign) NSInteger pedalLayout; // 0 default, 1 compact
@property (nonatomic, assign) CGFloat buttonScale;
@property (nonatomic, copy, nonnull) NSString *selectedCar;
@property (nonatomic, copy, nonnull) NSString *selectedTrack;

- (void)save;

- (uint32_t)bestMsForCar:(NSString *)car track:(NSString *)track;
- (uint32_t)lastMsForCar:(NSString *)car track:(NSString *)track;
- (uint32_t)lapCountForCar:(NSString *)car track:(NSString *)track;
- (NSDate * _Nullable)recordDateForCar:(NSString *)car track:(NSString *)track;
/// Uses the tested Rust PB rule through FFI. Returns YES when a new PB was set.
- (BOOL)submitLapMs:(uint32_t)ms car:(NSString *)car track:(NSString *)track
              valid:(BOOL)valid cuts:(int32_t)cuts;
- (void)resetLayout;

@end

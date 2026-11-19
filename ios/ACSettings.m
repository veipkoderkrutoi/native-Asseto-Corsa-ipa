#import "ACSettings.h"
#import "ios_bridge.h"

static NSString *const kACPrefsKey = @"ac-ios-port.settings.v1";

@interface ACSettings ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) NSMutableDictionary *records;
@end

@implementation ACSettings

+ (instancetype)shared {
    static ACSettings *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[ACSettings alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaults = NSUserDefaults.standardUserDefaults;
        [self load];
    }
    return self;
}

static float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

- (void)load {
    NSDictionary *p = [self.defaults dictionaryForKey:kACPrefsKey] ?: @{};
    NSNumber *n = nil;
    _fpsCapIndex       = (n = p[@"fpsCapIndex"]) ? clampf(n.integerValue, 0, 4) : 4;
    _masterVolume      = (n = p[@"masterVolume"]) ? clampf(n.floatValue, 0, 1) : 0.8f;
    _engineVolume      = (n = p[@"engineVolume"]) ? clampf(n.floatValue, 0, 1) : 0.9f;
    _effectsVolume     = (n = p[@"effectsVolume"]) ? clampf(n.floatValue, 0, 1) : 0.7f;
    _muted             = (n = p[@"muted"]) ? n.boolValue : NO;
    _steerSensitivity  = (n = p[@"steerSensitivity"]) ? clampf(n.floatValue, 0.5f, 2.0f) : 1.0f;
    _steerDeadzone     = (n = p[@"steerDeadzone"]) ? clampf(n.floatValue, 0.0f, 0.3f) : 0.02f;
    _hudVisible        = (n = p[@"hudVisible"]) ? n.boolValue : YES;
    _diagnosticsEnabled= (n = p[@"diagnosticsEnabled"]) ? n.boolValue : NO;
    _autoShifter       = (n = p[@"autoShifter"]) ? n.boolValue : YES;
    _gameMode          = (n = p[@"gameMode"]) ? clampf(n.integerValue, 0, 3) : 1;
    _units             = (n = p[@"units"]) ? clampf(n.integerValue, 0, 1) : 0;
    _pedalLayout       = (n = p[@"pedalLayout"]) ? clampf(n.integerValue, 0, 1) : 0;
    _buttonScale       = (n = p[@"buttonScale"]) ? clampf(n.floatValue, 0.85f, 1.3f) : 1.0f;
    _selectedCar       = p[@"selectedCar"] ?: @"";
    _selectedTrack     = p[@"selectedTrack"] ?: @"";

    NSDictionary *stored = p[@"records"];
    _records = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)save {
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    p[@"fpsCapIndex"] = @(_fpsCapIndex);
    p[@"masterVolume"] = @(_masterVolume);
    p[@"engineVolume"] = @(_engineVolume);
    p[@"effectsVolume"] = @(_effectsVolume);
    p[@"muted"] = @(_muted);
    p[@"steerSensitivity"] = @(_steerSensitivity);
    p[@"steerDeadzone"] = @(_steerDeadzone);
    p[@"hudVisible"] = @(_hudVisible);
    p[@"diagnosticsEnabled"] = @(_diagnosticsEnabled);
    p[@"autoShifter"] = @(_autoShifter);
    p[@"gameMode"] = @(_gameMode);
    p[@"units"] = @(_units);
    p[@"pedalLayout"] = @(_pedalLayout);
    p[@"buttonScale"] = @(_buttonScale);
    p[@"selectedCar"] = _selectedCar ?: @"";
    p[@"selectedTrack"] = _selectedTrack ?: @"";
    p[@"records"] = _records;
    [self.defaults setObject:p forKey:kACPrefsKey];
}

- (NSString *)keyForCar:(NSString *)car track:(NSString *)track {
    return [NSString stringWithFormat:@"%@|%@", car ?: @"", track ?: @""];
}

- (NSDictionary *)recordForCar:(NSString *)car track:(NSString *)track {
    NSDictionary *r = [self.records objectForKey:[self keyForCar:car track:track]];
    return [r isKindOfClass:NSDictionary.class] ? r : @{};
}

- (uint32_t)bestMsForCar:(NSString *)car track:(NSString *)track {
    return (uint32_t)[[self recordForCar:car track:track][@"best"] unsignedIntegerValue];
}

- (uint32_t)lastMsForCar:(NSString *)car track:(NSString *)track {
    return (uint32_t)[[self recordForCar:car track:track][@"last"] unsignedIntegerValue];
}

- (uint32_t)lapCountForCar:(NSString *)car track:(NSString *)track {
    return (uint32_t)[[self recordForCar:car track:track][@"laps"] unsignedIntegerValue];
}

- (NSDate *)recordDateForCar:(NSString *)car track:(NSString *)track {
    id value = [self recordForCar:car track:track][@"date"];
    return [value isKindOfClass:NSDate.class] ? value : nil;
}

- (BOOL)submitLapMs:(uint32_t)ms car:(NSString *)car track:(NSString *)track
              valid:(BOOL)valid cuts:(int32_t)cuts {
    uint32_t best = [self bestMsForCar:car track:track];
    if (!ac_ios_should_accept_pb(ms, valid ? 1 : 0, cuts, best)) {
        // Still keep the last lap and count, but never overwrite a clean best.
        NSMutableDictionary *r = [[self recordForCar:car track:track] mutableCopy];
        if (!r) r = [NSMutableDictionary dictionary];
        if (ms > 0) r[@"last"] = @(ms);
        r[@"laps"] = @([self lapCountForCar:car track:track] + 1);
        self.records[[self keyForCar:car track:track]] = r;
        [self save];
        return NO;
    }
    self.records[[self keyForCar:car track:track]] = @{
        @"best": @(ms), @"last": @(ms), @"laps": @([self lapCountForCar:car track:track] + 1),
        @"date": NSDate.date
    };
    [self save];
    return YES;
}

- (void)resetLayout {
    _pedalLayout = 0;
    _buttonScale = 1.0f;
    _steerSensitivity = 1.0f;
    _steerDeadzone = 0.02f;
    [self save];
}

@end

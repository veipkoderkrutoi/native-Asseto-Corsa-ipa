//
//  GameViewController.m — UIKit/MetalKit host for the real rustyAC engine.
//  Phase 11: Assetto Corsa inspired mobile shell (menu, garage, tracks,
//  game modes, settings), Time Attack on the real AC lap timer, FPS limiter.
//  The renderer, physics, content import and audio subsystems are unchanged.
//

#import "GameViewController.h"
#import "AppDelegate.h"
#import "ios_bridge.h"
#import "ac_pal_bridge.h"
#import "ACSettings.h"
#import "ACTiming.h"
#import "ACImportPopup.h"
#import "ACContentValidator.h"
#import <math.h>
#import <QuartzCore/QuartzCore.h>

#import <MetalKit/MetalKit.h>
#import <GameController/GameController.h>

#pragma mark - styled controls

@interface ACButton : UIButton
- (instancetype)initWithTitle:(NSString *)title accent:(BOOL)accent;
@end

@implementation ACButton
- (instancetype)initWithTitle:(NSString *)title accent:(BOOL)accent {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        [self setTitle:title forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
        [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [self setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0] forState:UIControlStateHighlighted];
        [self setTitleColor:[UIColor colorWithWhite:0.45 alpha:1.0] forState:UIControlStateDisabled];
        self.backgroundColor = accent
            ? [UIColor colorWithRed:0.78 green:0.10 blue:0.10 alpha:0.95]
            : [UIColor colorWithWhite:0.13 alpha:0.94];
        self.layer.cornerRadius = 4.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.13].CGColor;
    }
    return self;
}
@end

@interface ACPanel : UIView
@end
@implementation ACPanel
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.075 alpha:0.94];
        self.layer.cornerRadius = 6.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    }
    return self;
}
@end

/// Steering wheel face; drawn once and only rotated by the control.
@interface ACWheelRotor : UIView
@end
@implementation ACWheelRotor
- (void)drawRect:(CGRect)rect {
    CGRect r = CGRectInset(self.bounds, 8.0, 8.0);
    CGPoint c = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    CGFloat radius = MIN(r.size.width, r.size.height) * 0.5;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 9.0);
    [[UIColor colorWithWhite:0.92 alpha:0.95] setStroke];
    CGContextStrokeEllipseInRect(ctx, r);
    CGContextSetLineWidth(ctx, 7.0);
    [[UIColor colorWithWhite:0.80 alpha:0.92] setStroke];
    for (int i = 0; i < 3; i++) {
        CGFloat a = i * (2.0 * M_PI / 3.0) - M_PI_2;
        CGContextMoveToPoint(ctx, c.x, c.y);
        CGContextAddLineToPoint(ctx, c.x + cosf(a) * radius * 0.86,
                                c.y + sinf(a) * radius * 0.86);
    }
    CGContextStrokePath(ctx);
    [[UIColor colorWithWhite:0.16 alpha:1.0] setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - radius * 0.22, c.y - radius * 0.22,
                                               radius * 0.44, radius * 0.44));
}
@end

/// Relative-drag analogue wheel. Value -1 (left) .. +1 (right), matching
/// rustyAC's CarControls convention (rustyac-physics/car/feed.rs:43).
@interface ACWheelControl : UIView
@property (nonatomic, assign) float value;
@property (nonatomic, assign) float sensitivity;
@property (nonatomic, assign) float deadzone;
@property (nonatomic, assign) BOOL autoCentre;
- (void)setToNeutral;
@end
@implementation ACWheelControl {
    ACWheelRotor *_rotor;
    UITouch *_trackingTouch;
    CGPoint _startPoint;
    float _startValue;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.34];
        self.layer.cornerRadius = MIN(frame.size.width, frame.size.height) * 0.5;
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [UIColor colorWithRed:0.78 green:0.10 blue:0.10 alpha:0.6].CGColor;
        self.multipleTouchEnabled = NO;
        _sensitivity = 1.0f; _deadzone = 0.02f; _autoCentre = YES;
        _rotor = [[ACWheelRotor alloc] initWithFrame:CGRectInset(self.bounds, 6, 6)];
        _rotor.backgroundColor = UIColor.clearColor;
        [self addSubview:_rotor];
        UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, frame.size.height - 20, frame.size.width, 14)];
        hint.text = @"STEER"; hint.textAlignment = NSTextAlignmentCenter;
        hint.font = [UIFont boldSystemFontOfSize:10];
        hint.textColor = [UIColor colorWithWhite:0.85 alpha:0.8];
        [self addSubview:hint];
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; _rotor.frame = CGRectInset(self.bounds, 6, 6); }
- (void)setValue:(float)value {
    if (isnan(value)) value = 0;
    value = MAX(-1, MIN(1, value));
    if (fabsf(value) < _deadzone) value = 0;
    if (_value == value) return;
    _value = value;
    _rotor.transform = CGAffineTransformMakeRotation(value * 2.6f);
}
- (void)setToNeutral { _trackingTouch = nil; [self setValue:0]; }
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_trackingTouch) return;
    UITouch *t = [touches anyObject];
    if (!t) return;
    _trackingTouch = t;
    _startPoint = [t locationInView:self];
    _startValue = self.value;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *t in touches) {
        if (t != _trackingTouch) continue;
        CGPoint p = [t locationInView:self];
        CGFloat span = MAX(60, self.bounds.size.width * 0.62 / MAX(0.5f, _sensitivity));
        [self setValue:_startValue + (float)((p.x - _startPoint.x) / span)];
        return;
    }
}
- (void)finishTouch:(NSSet<UITouch *> *)touches {
    for (UITouch *t in touches) {
        if (t == _trackingTouch) {
            _trackingTouch = nil;
            if (_autoCentre) [self setValue:0];
            return;
        }
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self finishTouch:touches]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self setToNeutral]; }
@end

/// Large analogue pedal with a visible fill and guaranteed zero on release.
@interface ACPedalControl : UIView
@property (nonatomic, assign) float value;
- (instancetype)initWithFrame:(CGRect)frame title:(NSString *)title color:(UIColor *)color;
- (void)setToNeutral;
@end
@implementation ACPedalControl {
    UIView *_fill;
    UILabel *_title;
}
- (instancetype)initWithFrame:(CGRect)frame title:(NSString *)title color:(UIColor *)color {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.42];
        self.layer.cornerRadius = 8.0;
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [color colorWithAlphaComponent:0.85].CGColor;
        self.multipleTouchEnabled = YES;
        _fill = [[UIView alloc] initWithFrame:CGRectZero];
        _fill.backgroundColor = [color colorWithAlphaComponent:0.55];
        _fill.layer.cornerRadius = 6.0;
        [self addSubview:_fill];
        _title = [[UILabel alloc] initWithFrame:CGRectZero];
        _title.text = title; _title.textAlignment = NSTextAlignmentCenter;
        _title.font = [UIFont boldSystemFontOfSize:12];
        _title.textColor = UIColor.whiteColor;
        [self addSubview:_title];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height;
    _fill.frame = CGRectMake(2, h * (1 - self.value), self.bounds.size.width - 4, h * self.value);
    _title.frame = CGRectMake(0, h - 26, self.bounds.size.width, 20);
}
- (void)setValue:(float)value {
    if (isnan(value)) value = 0;
    value = MAX(0, MIN(1, value));
    if (_value == value) return;
    _value = value;
    [self layoutSubviews];
}
- (void)setToNeutral { [self setValue:0]; }
- (void)updateFromEvent:(UIEvent *)event {
    float best = 0;
    for (UITouch *t in event.allTouches) {
        if (t.view != self || t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled) continue;
        CGPoint p = [t locationInView:self];
        best = MAX(best, (float)((CGRectGetMaxY(self.bounds) - p.y) / MAX(1, self.bounds.size.height)));
    }
    [self setValue:best];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self updateFromEvent:event]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self updateFromEvent:event]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self updateFromEvent:event]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self setToNeutral]; }
@end

#pragma mark - View controller

@interface GameViewController () <MTKViewDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) ACSettings *settings;
@property (nonatomic, strong) ACTiming *timing;
@property (nonatomic, strong) ACImportPopup *importPopup;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *thumbnailCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *displayNameCache;

// Screens
@property (nonatomic, strong) UIView *menuContainer;
@property (nonatomic, strong) UIView *homeView;
@property (nonatomic, strong) UIView *garageView;
@property (nonatomic, strong) UIView *tracksView;
@property (nonatomic, strong) UIView *modesView;
@property (nonatomic, strong) UIView *settingsView;
@property (nonatomic, strong) UIScrollView *settingsScroll;
@property (nonatomic, strong) UITableView *carsTable;
@property (nonatomic, strong) UITableView *tracksTable;
@property (nonatomic, strong) UITableView *modesTable;
@property (nonatomic, strong) NSArray<NSString *> *cars;
@property (nonatomic, strong) NSArray<NSString *> *tracks;

// Home
@property (nonatomic, strong) UILabel *homeCar;
@property (nonatomic, strong) UILabel *homeTrack;
@property (nonatomic, strong) UILabel *homeBest;
@property (nonatomic, strong) UILabel *homeMode;
@property (nonatomic, strong) ACButton *driveButton;

// Settings controls
@property (nonatomic, strong) ACButton *fpsButton;
@property (nonatomic, strong) ACButton *gameModeButton;
@property (nonatomic, strong) ACButton *unitsButton;
@property (nonatomic, strong) ACButton *hudButton;
@property (nonatomic, strong) ACButton *diagButton;
@property (nonatomic, strong) ACButton *autoShiftButton;
@property (nonatomic, strong) ACButton *pedalLayoutButton;
@property (nonatomic, strong) ACButton *muteButton;
@property (nonatomic, strong) UISlider *masterSlider;
@property (nonatomic, strong) UISlider *engineSlider;
@property (nonatomic, strong) UISlider *effectsSlider;
@property (nonatomic, strong) UISlider *sensitivitySlider;
@property (nonatomic, strong) UISlider *deadzoneSlider;
@property (nonatomic, strong) UISlider *buttonScaleSlider;

// Driving UI
@property (nonatomic, strong) ACWheelControl *wheel;
@property (nonatomic, strong) ACPedalControl *gasPedal;
@property (nonatomic, strong) ACPedalControl *brakePedal;
@property (nonatomic, strong) ACButton *gearUpButton;
@property (nonatomic, strong) ACButton *gearDownButton;
@property (nonatomic, strong) ACButton *handbrakeButton;
@property (nonatomic, strong) ACButton *cameraButton;
@property (nonatomic, strong) ACButton *menuButton;
@property (nonatomic, strong) ACButton *gearboxButton;
@property (nonatomic, strong) UIView *hudPanel;
@property (nonatomic, strong) UILabel *hudSpeed;
@property (nonatomic, strong) UILabel *hudRpm;
@property (nonatomic, strong) UILabel *hudGear;
@property (nonatomic, strong) UIView *timingPanel;
@property (nonatomic, strong) UILabel *timingCurrent;
@property (nonatomic, strong) UILabel *timingBest;
@property (nonatomic, strong) UILabel *timingLast;
@property (nonatomic, strong) UILabel *timingLaps;
@property (nonatomic, strong) UILabel *debugLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *messageCloseButton;
@property (nonatomic, strong) UIView *validationPanel;
@property (nonatomic, strong) UILabel *validationTitle;
@property (nonatomic, strong) UILabel *validationCount;
@property (nonatomic, strong) UITextView *validationText;
@property (nonatomic, strong) UIButton *validationClose;

// Session state
@property (nonatomic, assign) BOOL sessionOpen;
@property (nonatomic, assign) BOOL renderReady;
@property (nonatomic, assign) BOOL driving;
@property (nonatomic, assign) BOOL touchHandbrake;
@property (nonatomic, assign) BOOL gearUpPending;
@property (nonatomic, assign) BOOL gearDownPending;
@property (nonatomic, assign) BOOL cameraPending;
@property (nonatomic, assign) BOOL lastGamepadGearUp;
@property (nonatomic, assign) BOOL lastGamepadGearDown;
@property (nonatomic, assign) BOOL lastGamepadCamera;
@property (nonatomic, assign) NSUInteger telemetryFrame;
@property (nonatomic, assign) CFAbsoluteTime lastFrameTime;
@property (nonatomic, assign) float smoothedFps;
@property (nonatomic, assign) double lastPhysicsMs;
@property (nonatomic, assign) NSInteger thermalState;
@property (nonatomic, assign) unsigned long long metalFeatures;
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1.0];
    self.settings = ACSettings.shared;
    self.timing = [[ACTiming alloc] init];
    self.thumbnailCache = [NSMutableDictionary dictionary];
    self.displayNameCache = [NSMutableDictionary dictionary];
    self.thermalState = NSProcessInfo.processInfo.thermalState;

    self.metalView = [[MTKView alloc] initWithFrame:CGRectZero device:MTLCreateSystemDefaultDevice()];
    self.metalView.translatesAutoresizingMaskIntoConstraints = NO;
    self.metalView.delegate = self;
    self.metalView.preferredFramesPerSecond = 60;
    self.metalView.clearColor = MTLClearColorMake(0.02, 0.025, 0.03, 1.0);
    [self.view addSubview:self.metalView];
    [NSLayoutConstraint activateConstraints:@[
        [self.metalView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.metalView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.metalView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.metalView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    ac_ios_set_metal_layer((__bridge void *)self.metalView.layer);

    [self buildMenuScreens];
    [self buildDrivingControls];
    [self scanContent];
    [self applySettingsToUI];
    [self showHome];

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(acRootChanged:) name:ACiOSRootDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(gamepadChanged:) name:GCControllerDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(gamepadChanged:) name:GCControllerDidDisconnectNotification object:nil];
    [nc addObserver:self selector:@selector(appWillResign:) name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(thermalChanged:) name:NSProcessInfoThermalStateDidChangeNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.timing stop];
    ac_ios_audio_shutdown();
    ac_ios_render_destroy();
    ac_ios_metal_destroy();
    ac_pal_bridge_shutdown();
    ac_ios_set_metal_layer(NULL);
}

#pragma mark - Screen construction

- (void)buildMenuScreens {
    self.menuContainer = [[UIView alloc] initWithFrame:CGRectZero];
    self.menuContainer.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.97];
    [self.view addSubview:self.menuContainer];

    self.homeView = [[UIView alloc] initWithFrame:CGRectZero];
    self.garageView = [[UIView alloc] initWithFrame:CGRectZero];
    self.tracksView = [[UIView alloc] initWithFrame:CGRectZero];
    self.modesView = [[UIView alloc] initWithFrame:CGRectZero];
    self.settingsView = [[UIView alloc] initWithFrame:CGRectZero];
    for (UIView *v in @[self.homeView, self.garageView, self.tracksView, self.modesView, self.settingsView]) {
        v.backgroundColor = UIColor.clearColor;
        [self.menuContainer addSubview:v];
    }

    // --- Home ---
    UILabel *brand = [[UILabel alloc] initWithFrame:CGRectZero];
    brand.text = @"ASSETTO CORSA";
    brand.textColor = [UIColor colorWithRed:0.85 green:0.12 blue:0.12 alpha:1.0];
    brand.font = [UIFont boldSystemFontOfSize:30];
    brand.textAlignment = NSTextAlignmentCenter;
    brand.tag = 1;
    [self.homeView addSubview:brand];
    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectZero];
    sub.text = @"M O B I L E";
    sub.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    sub.font = [UIFont boldSystemFontOfSize:12];
    sub.textAlignment = NSTextAlignmentCenter;
    sub.tag = 2;
    [self.homeView addSubview:sub];

    ACPanel *carCard = [[ACPanel alloc] initWithFrame:CGRectZero];
    carCard.tag = 3; [self.homeView addSubview:carCard];
    self.homeCar = [[UILabel alloc] initWithFrame:CGRectZero];
    self.homeCar.font = [UIFont boldSystemFontOfSize:26];
    self.homeCar.textColor = UIColor.whiteColor;
    self.homeCar.textAlignment = NSTextAlignmentCenter;
    self.homeCar.adjustsFontSizeToFitWidth = YES;
    [carCard addSubview:self.homeCar];
    self.homeBest = [[UILabel alloc] initWithFrame:CGRectZero];
    self.homeBest.font = [UIFont systemFontOfSize:12];
    self.homeBest.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    self.homeBest.textAlignment = NSTextAlignmentCenter;
    [carCard addSubview:self.homeBest];

    ACPanel *trackCard = [[ACPanel alloc] initWithFrame:CGRectZero];
    trackCard.tag = 4; [self.homeView addSubview:trackCard];
    self.homeTrack = [[UILabel alloc] initWithFrame:CGRectZero];
    self.homeTrack.font = [UIFont boldSystemFontOfSize:16];
    self.homeTrack.textColor = UIColor.whiteColor;
    self.homeTrack.textAlignment = NSTextAlignmentCenter;
    [trackCard addSubview:self.homeTrack];
    self.homeMode = [[UILabel alloc] initWithFrame:CGRectZero];
    self.homeMode.font = [UIFont systemFontOfSize:11];
    self.homeMode.textColor = [UIColor colorWithRed:0.85 green:0.12 blue:0.12 alpha:1.0];
    self.homeMode.textAlignment = NSTextAlignmentCenter;
    [self.homeView addSubview:self.homeMode];

    self.driveButton = [[ACButton alloc] initWithTitle:@"DRIVE" accent:YES];
    self.driveButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [self.driveButton addTarget:self action:@selector(driveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.homeView addSubview:self.driveButton];

    NSArray *titles = @[@"GARAGE", @"TRACKS", @"GAME MODES", @"SETTINGS", @"CONTENT"];
    NSArray *actions = @[@"showGarage", @"showTracks", @"showModes", @"showSettings", @"chooseFolderTapped"];
    NSMutableArray *rowButtons = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        ACButton *b = [[ACButton alloc] initWithTitle:titles[i] accent:NO];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [b addTarget:self action:NSSelectorFromString(actions[i]) forControlEvents:UIControlEventTouchUpInside];
        [self.homeView addSubview:b];
        [rowButtons addObject:b];
    }

    // --- Garage / Tracks / Modes ---
    self.carsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tracksTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.modesTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    for (UITableView *t in @[self.carsTable, self.tracksTable, self.modesTable]) {
        t.dataSource = self; t.delegate = self;
        t.backgroundColor = UIColor.clearColor;
        t.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
        [t registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
    }
    [self.garageView addSubview:self.carsTable];
    [self.tracksView addSubview:self.tracksTable];
    [self.modesView addSubview:self.modesTable];

    NSArray *screenViews = @[self.garageView, self.tracksView, self.modesView];
    NSArray *backActions = @[@"showHome", @"showHome", @"showHome"];
    for (NSUInteger i = 0; i < screenViews.count; i++) {
        ACButton *back = [[ACButton alloc] initWithTitle:@"‹ BACK" accent:NO];
        back.tag = 10;
        [back addTarget:self action:NSSelectorFromString(backActions[i]) forControlEvents:UIControlEventTouchUpInside];
        [screenViews[i] addSubview:back];
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
        title.tag = 11;
        title.font = [UIFont boldSystemFontOfSize:18];
        title.textColor = UIColor.whiteColor;
        title.textAlignment = NSTextAlignmentCenter;
        title.text = @[@"GARAGE", @"TRACKS", @"GAME MODES"][i];
        [screenViews[i] addSubview:title];
    }
    ACButton *confirmCars = [[ACButton alloc] initWithTitle:@"SELECT VEHICLE" accent:YES];
    confirmCars.tag = 12;
    [confirmCars addTarget:self action:@selector(confirmCar) forControlEvents:UIControlEventTouchUpInside];
    [self.garageView addSubview:confirmCars];
    ACButton *confirmTracks = [[ACButton alloc] initWithTitle:@"SELECT TRACK" accent:YES];
    confirmTracks.tag = 12;
    [confirmTracks addTarget:self action:@selector(confirmTrack) forControlEvents:UIControlEventTouchUpInside];
    [self.tracksView addSubview:confirmTracks];
    ACButton *confirmModes = [[ACButton alloc] initWithTitle:@"SELECT MODE" accent:YES];
    confirmModes.tag = 12;
    [confirmModes addTarget:self action:@selector(confirmMode) forControlEvents:UIControlEventTouchUpInside];
    [self.modesView addSubview:confirmModes];

    // --- Settings ---
    self.settingsScroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    [self.settingsView addSubview:self.settingsScroll];
    ACButton *settingsBack = [[ACButton alloc] initWithTitle:@"‹ BACK" accent:NO];
    [settingsBack addTarget:self action:@selector(showHome) forControlEvents:UIControlEventTouchUpInside];
    settingsBack.tag = 20;
    [self.settingsView addSubview:settingsBack];

    self.fpsButton = [[ACButton alloc] initWithTitle:@"FPS LIMIT: 60" accent:NO];
    [self.fpsButton addTarget:self action:@selector(cycleFps) forControlEvents:UIControlEventTouchUpInside];
    self.gameModeButton = [[ACButton alloc] initWithTitle:@"MODE: TIME ATTACK" accent:NO];
    [self.gameModeButton addTarget:self action:@selector(cycleGameMode) forControlEvents:UIControlEventTouchUpInside];
    self.unitsButton = [[ACButton alloc] initWithTitle:@"UNITS: KM/H" accent:NO];
    [self.unitsButton addTarget:self action:@selector(toggleUnits) forControlEvents:UIControlEventTouchUpInside];
    self.hudButton = [[ACButton alloc] initWithTitle:@"HUD: ON" accent:NO];
    [self.hudButton addTarget:self action:@selector(toggleHud) forControlEvents:UIControlEventTouchUpInside];
    self.diagButton = [[ACButton alloc] initWithTitle:@"DIAGNOSTICS: OFF" accent:NO];
    [self.diagButton addTarget:self action:@selector(toggleDiagnostics) forControlEvents:UIControlEventTouchUpInside];
    self.autoShiftButton = [[ACButton alloc] initWithTitle:@"GEARBOX: AUTO" accent:NO];
    [self.autoShiftButton addTarget:self action:@selector(toggleAutoShifter) forControlEvents:UIControlEventTouchUpInside];
    self.pedalLayoutButton = [[ACButton alloc] initWithTitle:@"PEDALS: DEFAULT" accent:NO];
    [self.pedalLayoutButton addTarget:self action:@selector(togglePedalLayout) forControlEvents:UIControlEventTouchUpInside];
    self.muteButton = [[ACButton alloc] initWithTitle:@"AUDIO: ON" accent:NO];
    [self.muteButton addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];

    self.masterSlider = [self makeSlider:@selector(volumeChanged:)];
    self.engineSlider = [self makeSlider:@selector(volumeChanged:)];
    self.effectsSlider = [self makeSlider:@selector(volumeChanged:)];
    self.sensitivitySlider = [self makeSlider:@selector(controlChanged:)];
    self.deadzoneSlider = [self makeSlider:@selector(controlChanged:)];
    self.buttonScaleSlider = [self makeSlider:@selector(controlChanged:)];

    ACButton *resetLayout = [[ACButton alloc] initWithTitle:@"RESET CONTROLS LAYOUT" accent:NO];
    [resetLayout addTarget:self action:@selector(resetLayout) forControlEvents:UIControlEventTouchUpInside];
    [resetLayout setTag:30];
    [self.settingsScroll addSubview:resetLayout];

    NSArray *settingViews = @[self.fpsButton, self.gameModeButton, self.unitsButton, self.hudButton,
                              self.diagButton, self.autoShiftButton, self.pedalLayoutButton,
                              self.muteButton, self.masterSlider, self.engineSlider,
                              self.effectsSlider, self.sensitivitySlider, self.deadzoneSlider,
                              self.buttonScaleSlider, resetLayout];
    for (UIView *v in settingViews) [self.settingsScroll addSubview:v];
    NSArray *labels = @[@"GRAPHICS", @"AUDIO", @"CONTROLS", @"GAMEPLAY"];
    for (NSString *text in labels) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
        l.text = text; l.textColor = [UIColor colorWithRed:0.85 green:0.12 blue:0.12 alpha:1.0];
        l.font = [UIFont boldSystemFontOfSize:11];
        l.tag = 40;
        [self.settingsScroll addSubview:l];
    }
}

- (UISlider *)makeSlider:(SEL)action {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectZero];
    s.minimumValue = 0; s.maximumValue = 1;
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

- (void)buildDrivingControls {
    self.wheel = [[ACWheelControl alloc] initWithFrame:CGRectZero];
    self.gasPedal = [[ACPedalControl alloc] initWithFrame:CGRectZero title:@"GAS"
        color:[UIColor colorWithRed:0.25 green:0.82 blue:0.35 alpha:1]];
    self.brakePedal = [[ACPedalControl alloc] initWithFrame:CGRectZero title:@"BRAKE"
        color:[UIColor colorWithRed:0.94 green:0.28 blue:0.24 alpha:1]];
    for (UIView *v in @[self.wheel, self.brakePedal, self.gasPedal]) [self.view addSubview:v];

    self.gearDownButton = [[ACButton alloc] initWithTitle:@"GEAR -" accent:NO];
    [self.gearDownButton addTarget:self action:@selector(gearDownTapped) forControlEvents:UIControlEventTouchDown];
    self.gearUpButton = [[ACButton alloc] initWithTitle:@"GEAR +" accent:NO];
    [self.gearUpButton addTarget:self action:@selector(gearUpTapped) forControlEvents:UIControlEventTouchDown];
    self.handbrakeButton = [[ACButton alloc] initWithTitle:@"HANDBRAKE" accent:NO];
    [self.handbrakeButton addTarget:self action:@selector(handbrakeDown) forControlEvents:UIControlEventTouchDown];
    [self.handbrakeButton addTarget:self action:@selector(handbrakeUp)
                   forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    self.cameraButton = [[ACButton alloc] initWithTitle:@"CAMERA" accent:NO];
    [self.cameraButton addTarget:self action:@selector(cameraTapped) forControlEvents:UIControlEventTouchUpInside];
    self.menuButton = [[ACButton alloc] initWithTitle:@"MENU" accent:NO];
    [self.menuButton addTarget:self action:@selector(menuButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.gearboxButton = [[ACButton alloc] initWithTitle:@"AUTO" accent:NO];
    [self.gearboxButton addTarget:self action:@selector(toggleAutoShifter) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *v in @[self.gearDownButton, self.gearUpButton, self.handbrakeButton,
                        self.cameraButton, self.menuButton, self.gearboxButton]) [self.view addSubview:v];

    self.hudPanel = [[ACPanel alloc] initWithFrame:CGRectZero];
    self.hudSpeed = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hudSpeed.font = [UIFont boldSystemFontOfSize:32];
    self.hudSpeed.textColor = UIColor.whiteColor;
    self.hudRpm = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hudRpm.font = [UIFont boldSystemFontOfSize:12];
    self.hudRpm.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    self.hudGear = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hudGear.font = [UIFont boldSystemFontOfSize:20];
    self.hudGear.textAlignment = NSTextAlignmentCenter;
    self.hudGear.textColor = [UIColor colorWithRed:0.85 green:0.12 blue:0.12 alpha:1];
    [self.hudPanel addSubview:self.hudSpeed];
    [self.hudPanel addSubview:self.hudRpm];
    [self.hudPanel addSubview:self.hudGear];
    [self.view addSubview:self.hudPanel];

    self.timingPanel = [[ACPanel alloc] initWithFrame:CGRectZero];
    self.timingCurrent = [[UILabel alloc] initWithFrame:CGRectZero];
    self.timingCurrent.font = [UIFont boldSystemFontOfSize:17];
    self.timingCurrent.textColor = UIColor.whiteColor;
    self.timingBest = [[UILabel alloc] initWithFrame:CGRectZero];
    self.timingBest.font = [UIFont systemFontOfSize:10];
    self.timingBest.textColor = [UIColor colorWithRed:0.9 green:0.35 blue:0.25 alpha:1];
    self.timingLast = [[UILabel alloc] initWithFrame:CGRectZero];
    self.timingLast.font = [UIFont systemFontOfSize:10];
    self.timingLast.textColor = [UIColor colorWithWhite:0.75 alpha:1];
    self.timingLaps = [[UILabel alloc] initWithFrame:CGRectZero];
    self.timingLaps.font = [UIFont systemFontOfSize:10];
    self.timingLaps.textColor = [UIColor colorWithWhite:0.75 alpha:1];
    [self.timingPanel addSubview:self.timingCurrent];
    [self.timingPanel addSubview:self.timingBest];
    [self.timingPanel addSubview:self.timingLast];
    [self.timingPanel addSubview:self.timingLaps];
    [self.view addSubview:self.timingPanel];

    self.debugLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.debugLabel.numberOfLines = 0;
    self.debugLabel.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    self.debugLabel.textColor = [UIColor colorWithWhite:0.78 alpha:0.9];
    self.debugLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    self.debugLabel.layer.cornerRadius = 4;
    [self.view addSubview:self.debugLabel];

    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.font = [UIFont boldSystemFontOfSize:14];
    self.messageLabel.textColor = [UIColor colorWithRed:1 green:0.55 blue:0.35 alpha:1];
    self.messageLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    self.messageLabel.layer.cornerRadius = 6;
    self.messageLabel.userInteractionEnabled = YES;
    [self.view addSubview:self.messageLabel];

    self.messageCloseButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.messageCloseButton setTitle:@"✕" forState:UIControlStateNormal];
    [self.messageCloseButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.messageCloseButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.messageCloseButton addTarget:self action:@selector(dismissMessage)
                      forControlEvents:UIControlEventTouchUpInside];
    [self.messageLabel addSubview:self.messageCloseButton];

    self.validationPanel = [[ACPanel alloc] initWithFrame:CGRectZero];
    self.validationPanel.hidden = YES;
    [self.view addSubview:self.validationPanel];
    self.validationTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    self.validationTitle.text = @"CONTENT VALIDATION FAILED";
    self.validationTitle.textColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.15 alpha:1];
    self.validationTitle.font = [UIFont boldSystemFontOfSize:15];
    [self.validationPanel addSubview:self.validationTitle];
    self.validationCount = [[UILabel alloc] initWithFrame:CGRectZero];
    self.validationCount.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    self.validationCount.font = [UIFont systemFontOfSize:11];
    [self.validationPanel addSubview:self.validationCount];
    self.validationText = [[UITextView alloc] initWithFrame:CGRectZero];
    self.validationText.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    self.validationText.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    self.validationText.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    self.validationText.editable = NO;
    [self.validationPanel addSubview:self.validationText];
    self.validationClose = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.validationClose setTitle:@"CLOSE" forState:UIControlStateNormal];
    self.validationClose.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self.validationClose setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.validationClose.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    self.validationClose.layer.cornerRadius = 4;
    [self.validationClose addTarget:self action:@selector(closeValidationPanel)
                   forControlEvents:UIControlEventTouchUpInside];
    [self.validationPanel addSubview:self.validationClose];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    self.menuContainer.frame = self.view.bounds;
    // Critical: every screen container must have a real frame. With a zero
    // frame UIKit draws subviews but hit-testing rejects every touch, so all
    // menu buttons appeared clickable but did nothing.
    CGRect screenFrame = self.menuContainer.bounds;
    self.homeView.frame = screenFrame;
    self.garageView.frame = screenFrame;
    self.tracksView.frame = screenFrame;
    self.modesView.frame = screenFrame;
    self.settingsView.frame = screenFrame;

    // Home
    CGFloat cx = w / 2;
    UIView *brand = [self.homeView viewWithTag:1];
    UIView *sub = [self.homeView viewWithTag:2];
    brand.frame = CGRectMake(0, safe.top + 10, w, 36);
    sub.frame = CGRectMake(0, safe.top + 46, w, 18);
    UIView *carCard = [self.homeView viewWithTag:3];
    UIView *trackCard = [self.homeView viewWithTag:4];
    carCard.frame = CGRectMake(cx - 170, safe.top + 76, 340, 96);
    self.homeCar.frame = CGRectMake(10, 12, 320, 40);
    self.homeBest.frame = CGRectMake(10, 56, 320, 26);
    trackCard.frame = CGRectMake(cx - 170, safe.top + 182, 340, 46);
    self.homeTrack.frame = CGRectMake(10, 4, 320, 24);
    self.homeMode.frame = CGRectMake(cx - 130, safe.top + 236, 260, 20);
    self.driveButton.frame = CGRectMake(cx - 90, safe.top + 262, 180, 54);

    CGFloat rowY = h - safe.bottom - 54;
    CGFloat bw = (w - safe.left - safe.right - 40) / 5;
    NSUInteger i = 0;
    for (UIView *v in self.homeView.subviews) {
        if ([v isKindOfClass:ACButton.class] && v != self.driveButton) {
            v.frame = CGRectMake(safe.left + 8 + i * (bw + 6), rowY, bw, 40);
            i++;
        }
    }

    // Lists
    for (UIView *screen in @[self.garageView, self.tracksView, self.modesView]) {
        UIView *back = [screen viewWithTag:10];
        UIView *title = [screen viewWithTag:11];
        UIView *confirm = [screen viewWithTag:12];
        back.frame = CGRectMake(safe.left + 10, safe.top + 10, 90, 36);
        title.frame = CGRectMake(cx - 100, safe.top + 10, 200, 36);
        confirm.frame = CGRectMake(cx - 110, h - safe.bottom - 52, 220, 42);
        CGFloat tableTop = safe.top + 58;
        CGFloat tableH = h - safe.top - safe.bottom - 118;
        UITableView *table = nil;
        if (screen == self.garageView) table = self.carsTable;
        else if (screen == self.tracksView) table = self.tracksTable;
        else table = self.modesTable;
        table.frame = CGRectMake(cx - 230, tableTop, 460, tableH);
    }

    // Settings
    ACButton *settingsBack = [self.settingsView viewWithTag:20];
    settingsBack.frame = CGRectMake(safe.left + 10, safe.top + 8, 90, 34);
    self.settingsScroll.frame = CGRectMake(safe.left + 8, safe.top + 50,
                                           w - safe.left - safe.right - 16,
                                           h - safe.top - safe.bottom - 58);
    CGFloat sw = self.settingsScroll.bounds.size.width - 40;
    CGFloat sx = 20;
    // Explicit order: section headers must stay above their controls.
    NSMutableArray *sectionLabels = [NSMutableArray array];
    for (UIView *v in self.settingsScroll.subviews) if (v.tag == 40) [sectionLabels addObject:v];
    [sectionLabels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        NSArray *order = @[@"GRAPHICS", @"AUDIO", @"CONTROLS", @"GAMEPLAY"];
        return [@([order indexOfObject:a.text]) compare:@([order indexOfObject:b.text])];
    }];
    CGFloat y = 8;
    for (UILabel *label in sectionLabels) {
        label.frame = CGRectMake(sx, y, sw, 18);
        y += 22;
        if ([label.text isEqualToString:@"GRAPHICS"]) {
            self.fpsButton.frame = CGRectMake(sx, y, sw, 34); y += 40;
            self.gameModeButton.frame = CGRectMake(sx, y, sw, 34); y += 40;
            self.unitsButton.frame = CGRectMake(sx, y, sw, 34); y += 40;
        } else if ([label.text isEqualToString:@"AUDIO"]) {
            self.masterSlider.frame = CGRectMake(sx, y, sw, 26); y += 34;
            self.engineSlider.frame = CGRectMake(sx, y, sw, 26); y += 34;
            self.effectsSlider.frame = CGRectMake(sx, y, sw, 26); y += 34;
            self.muteButton.frame = CGRectMake(sx, y, sw, 34); y += 40;
        } else if ([label.text isEqualToString:@"CONTROLS"]) {
            self.sensitivitySlider.frame = CGRectMake(sx, y, sw, 26); y += 34;
            self.deadzoneSlider.frame = CGRectMake(sx, y, sw, 26); y += 34;
            self.buttonScaleSlider.frame = CGRectMake(sx, y, sw, 26); y += 34;
            self.pedalLayoutButton.frame = CGRectMake(sx, y, sw, 34); y += 40;
            self.hudButton.frame = CGRectMake(sx, y, sw, 34); y += 40;
            self.diagButton.frame = CGRectMake(sx, y, sw, 34); y += 40;
        } else {
            self.autoShiftButton.frame = CGRectMake(sx, y, sw, 34); y += 40;
            UIView *reset = [self.settingsScroll viewWithTag:30];
            reset.frame = CGRectMake(sx, y, sw, 34); y += 42;
        }
        y += 8;
    }
    self.settingsScroll.contentSize = CGSizeMake(sw + 40, y + 20);

    // Driving controls
    CGFloat scale = MAX(0.85f, MIN(1.3f, self.settings.buttonScale));
    CGFloat wheelSize = MIN(158, h * 0.40) * scale;
    self.wheel.frame = CGRectMake(safe.left + 14, h - safe.bottom - 14 - wheelSize, wheelSize, wheelSize);
    self.wheel.sensitivity = self.settings.steerSensitivity;
    self.wheel.deadzone = self.settings.steerDeadzone;

    CGFloat pedalW = 64 * scale;
    CGFloat pedalH = MIN(126, h * 0.32) * scale;
    CGFloat pedalY = h - safe.bottom - 14 - pedalH;
    CGFloat gasX = w - safe.right - 14 - pedalW;
    CGFloat brakeX = self.settings.pedalLayout == 0 ? gasX - pedalW - 8 : gasX - pedalW - 8;
    self.gasPedal.frame = CGRectMake(gasX, pedalY, pedalW, pedalH);
    self.brakePedal.frame = CGRectMake(brakeX, pedalY, pedalW, pedalH);
    self.gearDownButton.frame = CGRectMake(brakeX, pedalY - 42, pedalW, 34);
    self.gearUpButton.frame = CGRectMake(gasX, pedalY - 42, pedalW, 34);
    self.handbrakeButton.frame = CGRectMake(CGRectGetMaxX(self.wheel.frame) + 14,
                                            h - safe.bottom - 14 - 52 * scale, 104 * scale, 52 * scale);
    self.gearboxButton.frame = CGRectMake(CGRectGetMinX(self.handbrakeButton.frame),
                                          CGRectGetMinY(self.handbrakeButton.frame) - 40, 118, 34);
    self.cameraButton.frame = CGRectMake(w - safe.right - 10 - 68, safe.top + 8, 68, 32);
    self.menuButton.frame = CGRectMake(CGRectGetMinX(self.cameraButton.frame) - 8 - 62, safe.top + 8, 62, 32);

    CGFloat hw = 190;
    self.hudPanel.frame = CGRectMake((w - hw) / 2, safe.top + 8, hw, 48);
    self.hudSpeed.frame = CGRectMake(8, 2, 80, 44);
    self.hudRpm.frame = CGRectMake(88, 3, 58, 21);
    self.hudGear.frame = CGRectMake(146, 3, 38, 21);
    self.timingPanel.frame = CGRectMake((w - hw) / 2, safe.top + 64, hw, 72);
    self.timingCurrent.frame = CGRectMake(10, 4, hw - 20, 24);
    self.timingBest.frame = CGRectMake(10, 30, hw - 20, 14);
    self.timingLast.frame = CGRectMake(10, 46, hw - 20, 14);
    self.timingLaps.frame = CGRectMake(10, 60, hw - 20, 12);

    self.debugLabel.frame = CGRectMake(safe.left + 12, safe.top + 144, MIN(310, w * 0.34), 170);
    self.messageLabel.frame = CGRectMake((w - 520) / 2, (h - 80) / 2, 520, 80);
    self.messageCloseButton.frame = CGRectMake(492, 4, 24, 24);
    CGFloat vw = MIN(560, w - 40);
    CGFloat vh = MIN(320, h - 60);
    self.validationPanel.frame = CGRectMake((w - vw) / 2, (h - vh) / 2, vw, vh);
    self.validationTitle.frame = CGRectMake(14, 10, vw - 28, 22);
    self.validationCount.frame = CGRectMake(14, 34, vw - 28, 18);
    self.validationText.frame = CGRectMake(14, 58, vw - 28, vh - 108);
    self.validationClose.frame = CGRectMake(vw - 104, vh - 42, 90, 32);
}

#pragma mark - Navigation

- (void)showHome {
    self.driving = NO;
    self.menuContainer.hidden = NO;
    for (UIView *v in @[self.homeView, self.garageView, self.tracksView, self.modesView, self.settingsView]) v.hidden = YES;
    self.homeView.hidden = NO;
    [self.view bringSubviewToFront:self.menuContainer];
    [self updateHome];
    [self hideDrivingUI:YES];
}
- (void)showGarage { [self showScreen:self.garageView]; [self.carsTable reloadData]; }
- (void)showTracks { [self showScreen:self.tracksView]; [self.tracksTable reloadData]; }
- (void)showModes  { [self showScreen:self.modesView]; [self.modesTable reloadData]; }
- (void)showSettings { [self showScreen:self.settingsView]; [self applySettingsToUI]; }

- (void)showScreen:(UIView *)screen {
    self.menuContainer.hidden = NO;
    for (UIView *v in @[self.homeView, self.garageView, self.tracksView, self.modesView, self.settingsView]) v.hidden = (v != screen);
    [self.view bringSubviewToFront:self.menuContainer];
}

- (void)hideDrivingUI:(BOOL)hidden {
    for (UIView *v in @[self.wheel, self.gasPedal, self.brakePedal, self.gearUpButton,
                        self.gearDownButton, self.handbrakeButton, self.cameraButton,
                        self.menuButton, self.gearboxButton, self.hudPanel, self.timingPanel,
                        self.debugLabel, self.messageLabel, self.messageCloseButton,
                        self.validationPanel]) v.hidden = hidden;
}

- (void)menuButtonTapped {
    if (!self.driving) return;
    [self.timing pause];
    [self resetTransientInput];
    self.driving = NO;
    self.menuContainer.hidden = NO;
    [self showHome];
}

- (void)updateHome {
    self.homeCar.text = self.settings.selectedCar.length ? [self displayNameForCar:self.settings.selectedCar] : @"—";
    self.homeTrack.text = self.settings.selectedTrack.length ? [self displayNameForTrack:self.settings.selectedTrack] : @"—";
    uint32_t best = [self.settings bestMsForCar:self.settings.selectedCar track:self.settings.selectedTrack];
    self.homeBest.text = best ? [NSString stringWithFormat:@"BEST  %@", [ACTiming formatMs:best]] : @"BEST  --:--.---";
    NSArray *modeNames = @[@"PRACTICE", @"TIME ATTACK", @"HOTLAP", @"FREE DRIVE"];
    NSInteger idx = MAX(0, MIN(3, self.settings.gameMode));
    self.homeMode.text = [NSString stringWithFormat:@"MODE  %@", modeNames[idx]];
}

- (void)applySettingsToUI {
    uint32_t cap = ac_ios_fps_cap_for_index((int)self.settings.fpsCapIndex);
    [self.fpsButton setTitle:[NSString stringWithFormat:@"FPS LIMIT: %@", cap ? @(cap).stringValue : @"AUTO"]
                    forState:UIControlStateNormal];
    NSArray *modes = @[@"PRACTICE", @"TIME ATTACK", @"HOTLAP", @"FREE DRIVE"];
    [self.gameModeButton setTitle:[NSString stringWithFormat:@"MODE: %@", modes[MAX(0, MIN(3, self.settings.gameMode))]]
                         forState:UIControlStateNormal];
    [self.unitsButton setTitle:(self.settings.units ? @"UNITS: MPH" : @"UNITS: KM/H") forState:UIControlStateNormal];
    [self.hudButton setTitle:(self.settings.hudVisible ? @"HUD: ON" : @"HUD: OFF") forState:UIControlStateNormal];
    [self.diagButton setTitle:(self.settings.diagnosticsEnabled ? @"DIAGNOSTICS: ON" : @"DIAGNOSTICS: OFF") forState:UIControlStateNormal];
    [self.autoShiftButton setTitle:(self.settings.autoShifter ? @"GEARBOX: AUTO" : @"GEARBOX: MANUAL") forState:UIControlStateNormal];
    [self.gearboxButton setTitle:(self.settings.autoShifter ? @"AUTO" : @"MANUAL") forState:UIControlStateNormal];
    [self.pedalLayoutButton setTitle:(self.settings.pedalLayout ? @"PEDALS: COMPACT" : @"PEDALS: DEFAULT") forState:UIControlStateNormal];
    [self.muteButton setTitle:(self.settings.muted ? @"AUDIO: OFF" : @"AUDIO: ON") forState:UIControlStateNormal];
    self.masterSlider.value = self.settings.masterVolume;
    self.engineSlider.value = self.settings.engineVolume;
    self.effectsSlider.value = self.settings.effectsVolume;
    self.sensitivitySlider.value = (self.settings.steerSensitivity - 0.5f) / 1.5f;
    self.deadzoneSlider.value = self.settings.steerDeadzone / 0.3f;
    self.buttonScaleSlider.value = (self.settings.buttonScale - 0.85f) / 0.45f;
    [self applyFpsCap];
}

- (void)applyFpsCap {
    uint32_t cap = ac_ios_fps_cap_for_index((int)self.settings.fpsCapIndex);
    cap = ac_ios_thermal_cap(cap, (int)self.thermalState);
    if (cap == 0) cap = 60; // Auto: stable system refresh, never 120 by default
    self.metalView.preferredFramesPerSecond = (NSInteger)cap;
}

- (void)thermalChanged:(NSNotification *)note {
    self.thermalState = NSProcessInfo.processInfo.thermalState;
    [self applyFpsCap];
}

#pragma mark - Settings actions

- (void)cycleFps {
    self.settings.fpsCapIndex = (self.settings.fpsCapIndex + 1) % 5;
    [self.settings save];
    [self applySettingsToUI];
}
- (void)cycleGameMode {
    self.settings.gameMode = (self.settings.gameMode + 1) % 4;
    [self.settings save]; [self applySettingsToUI]; [self updateHome];
}
- (void)toggleUnits { self.settings.units = !self.settings.units; [self.settings save]; [self applySettingsToUI]; }
- (void)toggleHud { self.settings.hudVisible = !self.settings.hudVisible; [self.settings save]; [self applySettingsToUI]; }
- (void)toggleDiagnostics { self.settings.diagnosticsEnabled = !self.settings.diagnosticsEnabled; [self.settings save]; [self applySettingsToUI]; }
- (void)toggleAutoShifter { self.settings.autoShifter = !self.settings.autoShifter; [self.settings save]; [self applySettingsToUI]; }
- (void)togglePedalLayout { self.settings.pedalLayout = !self.settings.pedalLayout; [self.settings save]; [self applySettingsToUI]; }
- (void)toggleMute {
    self.settings.muted = !self.settings.muted;
    ac_ios_audio_set_mute(self.settings.muted ? 1 : 0);
    [self.settings save]; [self applySettingsToUI];
}
- (void)volumeChanged:(UISlider *)sender {
    self.settings.masterVolume = self.masterSlider.value;
    self.settings.engineVolume = self.engineSlider.value;
    self.settings.effectsVolume = self.effectsSlider.value;
    ac_ios_audio_set_volumes(self.settings.masterVolume, self.settings.engineVolume, self.settings.effectsVolume);
    [self.settings save];
}
- (void)controlChanged:(UISlider *)sender {
    self.settings.steerSensitivity = 0.5f + self.sensitivitySlider.value * 1.5f;
    self.settings.steerDeadzone = self.deadzoneSlider.value * 0.3f;
    self.settings.buttonScale = 0.85f + self.buttonScaleSlider.value * 0.45f;
    self.wheel.sensitivity = self.settings.steerSensitivity;
    self.wheel.deadzone = self.settings.steerDeadzone;
    [self.settings save];
    [self viewDidLayoutSubviews];
}
- (void)resetLayout { [self.settings resetLayout]; [self applySettingsToUI]; [self viewDidLayoutSubviews]; }

#pragma mark - Content / selection

- (void)scanContent {
    NSString *root = self.acRootURL.path ?: @"";
    ac_ios_set_content_root(root);
    NSFileManager *fm = NSFileManager.defaultManager;
    self.cars = [[fm contentsOfDirectoryAtPath:[root stringByAppendingPathComponent:@"content/cars"] error:NULL] ?: @[]
        sortedArrayUsingSelector:@selector(compare:)];
    self.tracks = [[fm contentsOfDirectoryAtPath:[root stringByAppendingPathComponent:@"content/tracks"] error:NULL] ?: @[]
        sortedArrayUsingSelector:@selector(compare:)];
    if (![self.cars containsObject:self.settings.selectedCar ?: @""]) self.settings.selectedCar = self.cars.firstObject ?: @"";
    if (![self.tracks containsObject:self.settings.selectedTrack ?: @""]) self.settings.selectedTrack = self.tracks.firstObject ?: @"";
    [self.settings save];
    [self.carsTable reloadData]; [self.tracksTable reloadData]; [self updateHome];
}

- (void)acRootChanged:(NSNotification *)note {
    self.acRootURL = note.object;
    [self.thumbnailCache removeAllObjects];
    [self.displayNameCache removeAllObjects];
    [self scanContent];
    [self showMessage:@"AC folder changed — press DRIVE for a new session"];
}

- (void)chooseFolderTapped {
    if (self.importPopup) return;
    __weak typeof(self) weakSelf = self;
    self.importPopup = [[ACImportPopup alloc] initWithPresenter:self
        completion:^(NSURL *root, NSUInteger cars, NSUInteger tracks, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (error || !root) {
                if (error) [self showMessage:error.localizedDescription];
            } else {
                self.acRootURL = root;
                AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
                app.acRootURL = root;
                [self.thumbnailCache removeAllObjects];
                [self.displayNameCache removeAllObjects];
                [self scanContent];
                [self showMessage:[NSString stringWithFormat:@"Imported %lu cars / %lu tracks",
                                   (unsigned long)cars, (unsigned long)tracks]];
            }
            self.importPopup = nil;
        }];
    [self.importPopup showInView:self.view];
}

- (void)confirmCar { [self showHome]; }
- (void)confirmTrack { [self showHome]; }
- (void)confirmMode { [self showHome]; }

#pragma mark - Drive lifecycle

- (void)driveTapped {
    if (!self.acRootURL) { [self showMessage:@"Import your Assetto Corsa folder first"]; return; }
    [self showMessage:@"Validating content dependencies…"];
    __weak typeof(self) weakSelf = self;
    [[ACContentValidator shared] validateRoot:self.acRootURL
                                          car:self.settings.selectedCar
                                        track:self.settings.selectedTrack
                                   completion:^(NSArray<NSString *> *missingRequired,
                                                NSArray<NSString *> *missingOptional,
                                                NSUInteger checked) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self dismissMessage];
        if (missingRequired.count > 0) {
            [self showValidationFailed:missingRequired optional:missingOptional checked:checked];
            return;
        }
        [self startDriveSession];
    }];
}

- (void)startDriveSession {
    if (!self.acRootURL) { [self showMessage:@"Import your Assetto Corsa folder first"]; return; }
    self.lastFrameTime = 0;
    ac_ios_render_destroy();
    ac_ios_metal_destroy();
    self.renderReady = NO;
    [self resetTransientInput];

    ac_ios_set_auto_shifter(self.settings.autoShifter ? 1 : 0);
    if (ac_ios_install_core_vtable() != 0) { [self showMessage:@"Native core bridge failed"]; return; }
    const char *root = self.acRootURL.path.UTF8String ?: "";
    const char *car = self.settings.selectedCar.UTF8String ?: "";
    const char *track = self.settings.selectedTrack.UTF8String ?: "";
    self.sessionOpen = (ac_pal_bridge_open_session(root, car, track) == 0);
    if (!self.sessionOpen) { [self showMessage:@"Real rustyAC session failed — see app log"]; return; }

    CGFloat scale = self.metalView.contentScaleFactor;
    uint32_t width = (uint32_t)(self.metalView.bounds.size.width * scale);
    uint32_t height = (uint32_t)(self.metalView.bounds.size.height * scale);
    char err[512] = {0};
    if (ac_ios_metal_init(ac_ios_metal_layer(), width, height, err, sizeof(err)) != 0) {
        [self showMessage:[NSString stringWithFormat:@"Metal chain FAILED: %s", err]]; return;
    }
    uint64_t features[4] = {0};
    ac_ios_metal_device_info(features);
    self.metalFeatures = (unsigned long long)features[0];

    // Content diagnostics (no private container UUID or username in logs).
    NSString *rootPath = self.acRootURL.path ?: @"";
    NSString *displayRoot = rootPath;
    NSRange docsRange = [rootPath rangeOfString:@"/Documents/"];
    if (docsRange.location != NSNotFound) {
        displayRoot = [@"~" stringByAppendingString:[rootPath substringFromIndex:docsRange.location]];
    }
    NSString *driverDir = [rootPath stringByAppendingPathComponent:@"content/driver"];
    NSString *driverFile = [driverDir stringByAppendingPathComponent:@"driver_no_HANS.kn5"];
    NSFileManager *contentFM = NSFileManager.defaultManager;
    BOOL isDir = NO;
    BOOL driverDirExists = [contentFM fileExistsAtPath:driverDir isDirectory:&isDir] && isDir;
    BOOL driverFileExists = [contentFM fileExistsAtPath:driverFile];
    unsigned long long driverSize = driverFileExists
        ? [[contentFM attributesOfItemAtPath:driverFile error:nil][NSFileSize] unsignedLongLongValue] : 0;
    NSLog(@"[CONTENT] Content root: %@", displayRoot);
    NSLog(@"[CONTENT] Driver directory: %@ (exists: %@)",
          [displayRoot stringByAppendingPathComponent:@"content/driver"], driverDirExists ? @"true" : @"false");
    NSLog(@"[CONTENT] Requested driver: resolved by renderer from the car's driver3d.ini; verifying driver_no_HANS.kn5");
    NSLog(@"[CONTENT] Driver file exists: %@", driverFileExists ? @"true" : @"false");
    NSLog(@"[CONTENT] Driver file size: %llu", driverSize);
    if (!driverDirExists) {
        [self showMessage:@"Content pack is missing content/driver. Re-import the full Content Pack "
                           "(the renderer needs real AC driver models)."];
        return;
    }
    int renderResult = ac_ios_render_init(ac_pal_bridge_session(), width, height, err, sizeof(err));
    if (renderResult != 0) {
        NSLog(@"[RENDERER] Driver asset load result: FAILED — %s", err);
        [self showMessage:[NSString stringWithFormat:@"Real AC renderer FAILED: %s", err]]; return;
    }
    NSLog(@"[RENDERER] Driver asset load result: OK — real AC scene initialized");
    self.renderReady = YES;

    char audioErr[256] = {0};
    if (ac_ios_audio_init(audioErr, sizeof(audioErr)) == 0) {
        ac_ios_audio_set_volumes(self.settings.masterVolume, self.settings.engineVolume,
                                 self.settings.effectsVolume);
        ac_ios_audio_set_mute(self.settings.muted ? 1 : 0);
    } else {
        NSLog(@"ac_ios_audio: init failed (game continues): %s", audioErr);
    }

    // Time Attack / Hotlap use the REAL AC lap timer.
    [self.timing stop];
    __weak typeof(self) weakSelf = self;
    self.timing.onLap = ^(uint32_t ms, BOOL pb, int32_t cuts) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self.settings submitLapMs:ms car:self.settings.selectedCar track:self.settings.selectedTrack
                             valid:(cuts == 0) cuts:cuts];
        if (pb) [self showMessage:[NSString stringWithFormat:@"NEW PB  %@", [ACTiming formatMs:ms]]];
    };
    uint32_t best = [self.settings bestMsForCar:self.settings.selectedCar track:self.settings.selectedTrack];
    if (self.settings.gameMode == 1 || self.settings.gameMode == 2) [self.timing startWithBest:best];

    [self applyFpsCap];
    self.driving = YES;
    self.menuContainer.hidden = YES;
    [self hideDrivingUI:NO];
    self.messageLabel.hidden = YES;
    self.messageCloseButton.hidden = YES;
    self.debugLabel.hidden = !self.settings.diagnosticsEnabled;
    self.hudPanel.hidden = !self.settings.hudVisible;
    self.timingPanel.hidden = (self.settings.gameMode != 1 && self.settings.gameMode != 2);
}

#pragma mark - Input lifetime

- (void)resetTransientInput {
    [self.wheel setToNeutral];
    [self.gasPedal setToNeutral];
    [self.brakePedal setToNeutral];
    self.touchHandbrake = NO;
    self.gearUpPending = self.gearDownPending = self.cameraPending = NO;
    self.lastGamepadGearUp = self.lastGamepadGearDown = self.lastGamepadCamera = NO;
    self.lastFrameTime = 0;
}
- (void)gamepadChanged:(NSNotification *)note { [self resetTransientInput]; }
- (void)appWillResign:(NSNotification *)note { [self resetTransientInput]; [self.timing pause]; ac_ios_audio_suspend(); }
- (void)appDidBecomeActive:(NSNotification *)note { [self resetTransientInput]; ac_ios_audio_resume(); }

- (void)gearUpTapped { self.gearUpPending = YES; }
- (void)gearDownTapped { self.gearDownPending = YES; }
- (void)cameraTapped { self.cameraPending = YES; }
- (void)handbrakeDown { self.touchHandbrake = YES; }
- (void)handbrakeUp { self.touchHandbrake = NO; }

- (ACIosInputState)pollInput {
    ACIosInputState state = {0};
    GCController *pad = GCController.controllers.firstObject;
    BOOL padUp = NO, padDown = NO, padCamera = NO;
    if (pad.extendedGamepad) {
        GCExtendedGamepad *gp = pad.extendedGamepad;
        state.steer = gp.leftThumbstick.xAxis.value;
        state.throttle = gp.rightTrigger.value;
        state.brake = gp.leftTrigger.value;
        state.handbrake = gp.buttonB.isPressed ? 1 : 0;
        padUp = gp.buttonA.isPressed; padDown = gp.buttonX.isPressed; padCamera = gp.buttonY.isPressed;
    } else if (pad.microGamepad) {
        GCMicroGamepad *gp = pad.microGamepad;
        state.steer = gp.dpad.xAxis.value;
        state.throttle = gp.buttonA.isPressed ? 1 : 0;
        state.brake = gp.buttonX.isPressed ? 1 : 0;
        padUp = gp.buttonA.isPressed && gp.buttonX.isPressed;
    } else {
        state.steer = self.wheel.value;
        state.throttle = self.gasPedal.value;
        state.brake = self.brakePedal.value;
        state.handbrake = self.touchHandbrake ? 1 : 0;
    }
    if (!self.driving) {
        state.steer = state.throttle = state.brake = 0; state.handbrake = 0;
    }
    state.gear_up = (padUp && !self.lastGamepadGearUp) || self.gearUpPending;
    state.gear_down = (padDown && !self.lastGamepadGearDown) || self.gearDownPending;
    state.camera_request = (padCamera && !self.lastGamepadCamera) || self.cameraPending;
    self.lastGamepadGearUp = padUp; self.lastGamepadGearDown = padDown; self.lastGamepadCamera = padCamera;
    self.gearUpPending = self.gearDownPending = self.cameraPending = NO;
    return state;
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    if (ac_ios_metal_is_ready()) {
        CGFloat scale = view.contentScaleFactor;
        uint32_t w = (uint32_t)(size.width * scale), h = (uint32_t)(size.height * scale);
        if (ac_ios_metal_resize(w, h) == 0 && self.renderReady) ac_ios_render_resize(w, h);
    }
}

- (void)drawInMTKView:(MTKView *)view {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double delta = self.lastFrameTime > 0 ? (now - self.lastFrameTime) : 1.0 / 60.0;
    self.lastFrameTime = now;
    if (delta > 0.1) delta = 0.1;
    if (delta > 0) {
        float instant = (float)(1.0 / delta);
        self.smoothedFps = self.smoothedFps > 0 ? self.smoothedFps * 0.9f + instant * 0.1f : instant;
    }

    ACIosInputState input = [self pollInput];
    ac_ios_set_input(input);
    CFAbsoluteTime physicsStart = CFAbsoluteTimeGetCurrent();
    ac_pal_bridge_set_controls(input.steer, input.throttle, input.brake,
                               input.handbrake ? 1 : 0,
                               input.gear_up, input.gear_down, input.camera_request);
    ac_pal_bridge_run_frame(delta);
    self.lastPhysicsMs = (CFAbsoluteTimeGetCurrent() - physicsStart) * 1000.0;

    float s[16] = {0};
    ac_pal_bridge_snapshot(s);
    ac_ios_audio_set_state(s[1], s[3], s[4], s[0], s[2]);

    if (self.driving && (self.settings.gameMode == 1 || self.settings.gameMode == 2)) {
        ACIosLapState lap = {0};
        if (ac_ios_lap_state(&lap) == 0) [self.timing updateWithLap:lap];
    }

    if (++self.telemetryFrame % 6 == 0) {
        if (self.settings.hudVisible) {
            self.hudSpeed.text = [NSString stringWithFormat:@"%.0f", s[0]];
            self.hudRpm.text = [NSString stringWithFormat:@"%.0f rpm", s[1]];
            self.hudGear.text = s[2] < 0.5 ? @"N" : [NSString stringWithFormat:@"%.0f", s[2]];
        }
        if (!self.timingPanel.hidden) {
            self.timingCurrent.text = [ACTiming formatMs:self.timing.currentMs];
            self.timingBest.text = [NSString stringWithFormat:@"BEST  %@",
                self.timing.bestLapMs ? [ACTiming formatMs:self.timing.bestLapMs] : @"--:--.---"];
            self.timingLast.text = [NSString stringWithFormat:@"LAST  %@",
                self.timing.lastLapMs ? [ACTiming formatMs:self.timing.lastLapMs] : @"--:--.---"];
            self.timingLaps.text = [NSString stringWithFormat:@"LAP %u", self.timing.lapCount + 1];
        }
        if (self.settings.diagnosticsEnabled && self.driving) {
            char audioStatus[256] = {0};
            ac_ios_audio_status(audioStatus, sizeof(audioStatus));
            uint64_t texOk = 0, texErr = 0, texCpu = 0;
            ac_ios_texture_stats(&texOk, &texErr, &texCpu);
            uint32_t cap = ac_ios_thermal_cap(ac_ios_fps_cap_for_index((int)self.settings.fpsCapIndex),
                                              (int)self.thermalState);
            self.debugLabel.text = [NSString stringWithFormat:
                @"FPS %.1f | cap %u | thermal %ld\n"
                "frame %.1f ms | physics %.2f ms\n"
                "render %.2f ms | mem %.0f MB\n"
                "tex %llu/%llu/%llu | metal 0x%llx\n"
                "audio %s",
                self.smoothedFps, cap, (long)self.thermalState,
                delta * 1000.0, self.lastPhysicsMs,
                ac_ios_render_last_draw_ms(),
                ac_ios_memory_footprint() / (1024.0 * 1024.0),
                (unsigned long long)texOk, (unsigned long long)texErr,
                (unsigned long long)texCpu, self.metalFeatures, audioStatus];
        }
    }

    if (self.driving && self.renderReady) {
        if (ac_ios_render_frame(ac_pal_bridge_session()) != 0) {
            self.renderReady = NO;
            [self showMessage:@"Real renderer frame failed — see app log"];
        }
    }
}

- (void)showMessage:(NSString *)text {
    self.messageLabel.text = text;
    self.messageLabel.hidden = NO;
    self.messageCloseButton.hidden = NO;
    [self.view bringSubviewToFront:self.messageLabel];
}

- (void)dismissMessage {
    self.messageLabel.hidden = YES;
    self.messageCloseButton.hidden = YES;
}

- (void)showValidationFailed:(NSArray<NSString *> *)required
                    optional:(NSArray<NSString *> *)optional
                     checked:(NSUInteger)checked {
    self.validationCount.text = [NSString stringWithFormat:@"Missing %lu required of %lu checked resources",
                                 (unsigned long)required.count, (unsigned long)checked];
    NSMutableString *details = [NSMutableString string];
    [details appendString:@"Missing required resources:\n"];
    for (NSString *path in required) [details appendFormat:@"- %@\n", path];
    if (optional.count) {
        [details appendFormat:@"\nOptional (renderer will continue without them): %lu\n", (unsigned long)optional.count];
        for (NSString *path in optional) [details appendFormat:@"- %@\n", path];
    }
    self.validationText.text = details;
    self.validationPanel.hidden = NO;
    [self.view bringSubviewToFront:self.validationPanel];
}

- (void)closeValidationPanel {
    self.validationPanel.hidden = YES;
}

#pragma mark - Content metadata / thumbnails

/// AC's ui_car.json contains raw newlines inside strings, so strict JSON
/// parsing fails. A bounded regex over the small text file gets real values.
- (NSString *)valueForKey:(NSString *)key inJSONAtPath:(NSString *)path fallback:(NSString *)fallback {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text) return fallback;
    NSString *pattern = [NSString stringWithFormat:@"\"%@\"\\s*:\\s*\"([^\"]+)\"", key];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (m && m.numberOfRanges > 1) {
        return [text substringWithRange:[m rangeAtIndex:1]];
    }
    return fallback;
}

- (NSString *)displayNameForCar:(NSString *)folder {
    NSString *cached = self.displayNameCache[folder];
    if (cached) return cached;
    NSString *json = [self.acRootURL.path stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"content/cars/%@/ui/ui_car.json", folder]];
    NSString *name = [self valueForKey:@"name" inJSONAtPath:json fallback:folder];
    self.displayNameCache[folder] = name;
    return name;
}

- (NSString *)displayNameForTrack:(NSString *)folder {
    NSString *cached = self.displayNameCache[folder];
    if (cached) return cached;
    NSString *json = [self.acRootURL.path stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"content/tracks/%@/ui/ui_track.json", folder]];
    NSString *name = [self valueForKey:@"name" inJSONAtPath:json fallback:folder];
    if ([folder isEqualToString:@"trento-bondone"]) {
        name = [name stringByAppendingString:@" (Hill Climb)"];
    }
    self.displayNameCache[folder] = name;
    return name;
}

- (UIImage *)thumbnailAtPath:(NSString *)path {
    UIImage *full = [UIImage imageWithContentsOfFile:path];
    if (!full) return nil;
    CGSize target = CGSizeMake(84, 48);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [full drawInRect:CGRectMake(0, 0, target.width, target.height)];
    }];
}

- (UIImage *)thumbnailForCar:(NSString *)folder {
    UIImage *cached = self.thumbnailCache[folder];
    if (cached) return cached;
    NSArray *names = @[@"ui/dlc_preview.png", @"ui/preview.png", @"ui/logo.png", @"logo.png"];
    for (NSString *rel in names) {
        NSString *path = [self.acRootURL.path stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"content/cars/%@/%@", folder, rel]];
        UIImage *img = [self thumbnailAtPath:path];
        if (img) { self.thumbnailCache[folder] = img; return img; }
    }
    return nil;
}

- (UIImage *)thumbnailForTrack:(NSString *)folder {
    UIImage *cached = self.thumbnailCache[folder];
    if (cached) return cached;
    NSArray *names = @[@"ui/preview.png", @"ui/trento-bondone.png", @"map.png", @"ui/outline.png"];
    for (NSString *rel in names) {
        NSString *path = [self.acRootURL.path stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"content/tracks/%@/%@", folder, rel]];
        UIImage *img = [self thumbnailAtPath:path];
        if (img) { self.thumbnailCache[folder] = img; return img; }
    }
    return nil;
}

#pragma mark - Tables

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return tv == self.modesTable ? 1 : 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (tv == self.carsTable) return self.cars.count;
    if (tv == self.tracksTable) return self.tracks.count;
    return 5; // practice, time attack, hotlap, free drive, race (coming later)
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    cell.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    NSString *name = nil;
    BOOL selected = NO;
    cell.imageView.image = nil;
    cell.textLabel.textColor = UIColor.whiteColor;
    if (tv == self.carsTable) {
        NSString *folder = self.cars[ip.row];
        name = [self displayNameForCar:folder];
        cell.imageView.image = [self thumbnailForCar:folder];
        selected = [folder isEqualToString:self.settings.selectedCar];
    } else if (tv == self.tracksTable) {
        NSString *folder = self.tracks[ip.row];
        name = [self displayNameForTrack:folder];
        cell.imageView.image = [self thumbnailForTrack:folder];
        selected = [folder isEqualToString:self.settings.selectedTrack];
    } else {
        NSArray *modes = @[@"PRACTICE", @"TIME ATTACK", @"HOTLAP", @"FREE DRIVE", @"RACE — COMING LATER"];
        name = modes[ip.row];
        selected = ip.row == self.settings.gameMode;
        cell.textLabel.textColor = ip.row == 4 ? [UIColor colorWithWhite:0.45 alpha:1] : UIColor.whiteColor;
    }
    cell.textLabel.text = name;
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (tv == self.carsTable) self.settings.selectedCar = self.cars[ip.row];
    else if (tv == self.tracksTable) self.settings.selectedTrack = self.tracks[ip.row];
    else if (tv == self.modesTable && ip.row < 4) self.settings.gameMode = ip.row;
    [self.settings save];
    [tv reloadData];
    [self updateHome];
}

@end

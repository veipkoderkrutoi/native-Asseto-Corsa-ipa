//
//  GameViewController.m — UIKit/MetalKit host for the real rustyAC engine.
//  Requires macOS + Xcode + iOS SDK. NOT compiled on the research host.
//
//  Scope: UIKit/MetalKit host for the real AC scene. The game-facing layer is
//  a mobile UI: virtual wheel + analog pedals, compact menu and a clean HUD.
//  All telemetry comes from the live GameSim; no invented values or scenes.
//

#import "GameViewController.h"
#import "AppDelegate.h"
#import "ios_bridge.h"
#import "ac_pal_bridge.h"
#import <math.h>
#import <QuartzCore/QuartzCore.h>

#import <MetalKit/MetalKit.h>
#import <GameController/GameController.h>

#pragma mark - Small UI pieces

/// The wheel face. Drawn once, then only rotated by the control (no per-frame
/// GPU work, no allocation in the render loop).
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
    CGContextAddEllipseInRect(ctx, r);
    CGContextStrokeEllipseInRect(ctx, r);

    // Three spokes make the rotation readable at a glance.
    CGContextSetLineWidth(ctx, 7.0);
    [[UIColor colorWithWhite:0.80 alpha:0.92] setStroke];
    for (int i = 0; i < 3; i++) {
        CGFloat a = i * (2.0 * M_PI / 3.0) - M_PI_2;
        CGContextMoveToPoint(ctx, c.x, c.y);
        CGContextAddLineToPoint(ctx, c.x + cosf(a) * radius * 0.86,
                                c.y + sinf(a) * radius * 0.86);
    }
    CGContextStrokePath(ctx);

    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.16 alpha:1.0].CGColor);
    CGContextAddEllipseInRect(ctx, CGRectMake(c.x - radius * 0.22, c.y - radius * 0.22,
                                              radius * 0.44, radius * 0.44));
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - radius * 0.22, c.y - radius * 0.22,
                                              radius * 0.44, radius * 0.44));
}
@end

/// Analogue steering wheel. Relative drag from the touch-down point; lifting
/// the finger returns to neutral. value is -1 (left) .. +1 (right), which is
/// exactly rustyAC's CarControls convention (rustyac-physics/car/feed.rs:43:
/// "steer, -1..1, positive = right").
@interface ACWheelControl : UIView
@property (nonatomic, assign) float value;
@property (nonatomic, copy) void (^valueChanged)(float value);
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
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
        self.multipleTouchEnabled = NO;

        _rotor = [[ACWheelRotor alloc] initWithFrame:CGRectInset(self.bounds, 6.0, 6.0)];
        _rotor.backgroundColor = UIColor.clearColor;
        _rotor.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_rotor];

        UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, frame.size.height - 20.0,
                                                                  frame.size.width, 14.0)];
        hint.text = @"STEER";
        hint.textAlignment = NSTextAlignmentCenter;
        hint.font = [UIFont boldSystemFontOfSize:10.0];
        hint.textColor = [UIColor colorWithWhite:0.85 alpha:0.8];
        hint.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
        [self addSubview:hint];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _rotor.frame = CGRectInset(self.bounds, 6.0, 6.0);
}

- (void)setValue:(float)value {
    if (isnan(value)) value = 0.0f;
    value = MAX(-1.0f, MIN(1.0f, value));
    if (_value == value) return;
    _value = value;
    // ~150 degrees of visible wheel rotation at full lock.
    _rotor.transform = CGAffineTransformMakeRotation(value * 2.6f);
    if (self.valueChanged) self.valueChanged(value);
}

- (void)setToNeutral {
    _trackingTouch = nil;
    [self setValue:0.0f];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_trackingTouch) return;
    UITouch *touch = [touches anyObject];
    if (!touch) return;
    _trackingTouch = touch;
    _startPoint = [touch locationInView:self];
    _startValue = self.value;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        if (touch != _trackingTouch) continue;
        CGPoint p = [touch locationInView:self];
        CGFloat span = MAX(60.0, self.bounds.size.width * 0.62);
        [self setValue:_startValue + (float)((p.x - _startPoint.x) / span)];
        return;
    }
}

- (void)finishTouch:(NSSet<UITouch *> *)touches {
    for (UITouch *touch in touches) {
        if (touch == _trackingTouch) {
            [self setToNeutral];
            return;
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self finishTouch:touches]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self finishTouch:touches]; }
@end

/// Analogue pedal. The value is the vertical position of the finger inside
/// the pedal (top = 1, bottom = 0). Every release path zeroes it.
@interface ACPedalControl : UIView
@property (nonatomic, assign) float value;
@property (nonatomic, copy) void (^valueChanged)(float value);
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
        self.layer.cornerRadius = 12.0;
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [color colorWithAlphaComponent:0.85].CGColor;
        self.multipleTouchEnabled = YES;

        _fill = [[UIView alloc] initWithFrame:CGRectMake(2, frame.size.height, frame.size.width - 4, 0)];
        _fill.backgroundColor = [color colorWithAlphaComponent:0.55];
        _fill.layer.cornerRadius = 10.0;
        _fill.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_fill];

        _title = [[UILabel alloc] initWithFrame:CGRectMake(0, frame.size.height - 26.0,
                                                            frame.size.width, 20.0)];
        _title.text = title;
        _title.textAlignment = NSTextAlignmentCenter;
        _title.font = [UIFont boldSystemFontOfSize:12.0];
        _title.textColor = UIColor.whiteColor;
        _title.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
        [self addSubview:_title];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height;
    _fill.frame = CGRectMake(2, h * (1.0 - self.value), self.bounds.size.width - 4, h * self.value);
    _title.frame = CGRectMake(0, h - 26.0, self.bounds.size.width, 20.0);
}

- (void)setValue:(float)value {
    if (isnan(value)) value = 0.0f;
    value = MAX(0.0f, MIN(1.0f, value));
    if (_value == value) return;
    _value = value;
    [self layoutSubviews];
    if (self.valueChanged) self.valueChanged(value);
}

- (void)setToNeutral { [self setValue:0.0f]; }

- (void)updateFromEvent:(UIEvent *)event {
    float best = 0.0f;
    for (UITouch *touch in event.allTouches) {
        if (touch.view != self) continue;
        if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) continue;
        CGPoint p = [touch locationInView:self];
        float v = (float)((CGRectGetMaxY(self.bounds) - p.y) / MAX(1.0, self.bounds.size.height));
        best = MAX(best, v);
    }
    [self setValue:best];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self updateFromEvent:event]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self updateFromEvent:event]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self updateFromEvent:event]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self setToNeutral]; }
@end

@interface ACRoundButton : UIButton
- (instancetype)initWithTitle:(NSString *)title accent:(BOOL)accent;
@end

@implementation ACRoundButton
- (instancetype)initWithTitle:(NSString *)title accent:(BOOL)accent {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        [self setTitle:title forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [self setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.45] forState:UIControlStateHighlighted];
        self.backgroundColor = accent
            ? [[UIColor colorWithRed:0.85 green:0.30 blue:0.12 alpha:1.0] colorWithAlphaComponent:0.92]
            : [[UIColor colorWithWhite:0.16 alpha:1.0] colorWithAlphaComponent:0.86];
        self.layer.cornerRadius = 9.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    }
    return self;
}
@end

#pragma mark - View controller

@interface GameViewController () <MTKViewDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) MTKView *metalView;

// Menu
@property (nonatomic, strong) UIView *menuPanel;
@property (nonatomic, strong) UITableView *menuTable;
@property (nonatomic, strong) UILabel *menuInfo;
@property (nonatomic, strong) UIButton *debugToggleButton;
@property (nonatomic, strong) UIButton *centerToggleButton;
@property (nonatomic, assign) BOOL showCarsInMenu;
@property (nonatomic, assign) BOOL debugEnabled;
@property (nonatomic, assign) BOOL returnToCenter;

// Driving controls
@property (nonatomic, strong) ACWheelControl *wheel;
@property (nonatomic, strong) ACPedalControl *gasPedal;
@property (nonatomic, strong) ACPedalControl *brakePedal;
@property (nonatomic, strong) ACRoundButton *gearUpButton;
@property (nonatomic, strong) ACRoundButton *gearDownButton;
@property (nonatomic, strong) ACRoundButton *handbrakeButton;
@property (nonatomic, strong) ACRoundButton *cameraButton;
@property (nonatomic, strong) ACRoundButton *menuButton;
@property (nonatomic, strong) ACRoundButton *gearboxButton;
@property (nonatomic, strong) ACRoundButton *folderButton;
@property (nonatomic, strong) ACRoundButton *driveButton;
@property (nonatomic, strong) ACRoundButton *controlsButton;
@property (nonatomic, strong) ACRoundButton *settingsButton;

// HUD / diagnostics
@property (nonatomic, strong) UIView *hudPanel;
@property (nonatomic, strong) UILabel *hudSpeed;
@property (nonatomic, strong) UILabel *hudRpm;
@property (nonatomic, strong) UILabel *hudGear;
@property (nonatomic, strong) UILabel *debugLabel;
@property (nonatomic, strong) UILabel *messageLabel;

// Session / content
@property (nonatomic, strong) NSArray<NSString *> *cars;
@property (nonatomic, strong) NSArray<NSString *> *tracks;
@property (nonatomic, copy) NSString *selectedCar;
@property (nonatomic, copy) NSString *selectedTrack;
@property (nonatomic, assign) BOOL sessionOpen;
@property (nonatomic, assign) BOOL renderReady;

// Input state
@property (nonatomic, assign) BOOL touchHandbrake;
@property (nonatomic, assign) BOOL gearUpPending;
@property (nonatomic, assign) BOOL gearDownPending;
@property (nonatomic, assign) BOOL cameraPending;
@property (nonatomic, assign) BOOL lastGamepadGearUp;
@property (nonatomic, assign) BOOL lastGamepadGearDown;
@property (nonatomic, assign) BOOL lastGamepadCamera;
@property (nonatomic, assign) BOOL autoShifter;

// Timing
@property (nonatomic, assign) NSUInteger telemetryFrame;
@property (nonatomic, assign) CFAbsoluteTime lastFrameTime;
@property (nonatomic, assign) float smoothedFps;
@property (nonatomic, assign) unsigned long long metalFeatures;
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.returnToCenter = YES;
    self.debugEnabled = NO;

    self.metalView = [[MTKView alloc] initWithFrame:CGRectZero device:MTLCreateSystemDefaultDevice()];
    self.metalView.translatesAutoresizingMaskIntoConstraints = NO;
    self.metalView.delegate = self;
    self.metalView.preferredFramesPerSecond = 60;
    self.metalView.clearColor = MTLClearColorMake(0.04, 0.05, 0.07, 1.0);
    [self.view addSubview:self.metalView];
    [NSLayoutConstraint activateConstraints:@[
        [self.metalView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.metalView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.metalView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.metalView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    ac_ios_set_metal_layer((__bridge void *)self.metalView.layer);

    [self buildMenu];
    [self buildHUD];
    [self buildDrivingControls];
    [self scanContent];

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(acRootChanged:)
               name:ACiOSRootDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(gamepadChanged:)
               name:GCControllerDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(gamepadChanged:)
               name:GCControllerDidDisconnectNotification object:nil];
    [nc addObserver:self selector:@selector(appWillResign:)
               name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appDidBecomeActive:)
               name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // Compact menu panel: <= 32% of landscape width.
    CGFloat pw = MIN(300.0, w * 0.32);
    CGFloat px = safe.left + 10.0;
    CGFloat py = safe.top + 10.0;
    CGFloat ph = h - safe.top - safe.bottom - 20.0;
    self.menuPanel.frame = CGRectMake(px, py, pw, ph);

    CGFloat x = 10.0, y = 6.0;
    self.folderButton.frame = CGRectMake(x, y, pw - 20.0, 30.0); y += 36.0;
    self.controlsButton.frame = CGRectMake(x, y, (pw - 26.0) / 2.0, 30.0);
    self.settingsButton.frame = CGRectMake(x + (pw - 26.0) / 2.0 + 6.0, y,
                                           (pw - 26.0) / 2.0, 30.0); y += 36.0;
    self.driveButton.frame = CGRectMake(x, y, pw - 20.0, 40.0); y += 48.0;

    CGFloat listY = y;
    CGFloat listH = MAX(40.0, ph - listY - 12.0);
    self.menuTable.frame = CGRectMake(x, listY, pw - 20.0, listH);
    self.menuInfo.frame = self.menuTable.frame;
    self.debugToggleButton.frame = CGRectMake(x, listY + 4.0, pw - 20.0, 30.0);
    self.centerToggleButton.frame = CGRectMake(x, listY + 40.0, pw - 20.0, 30.0);

    // HUD at the top centre: clear of the left menu and the right buttons.
    CGFloat hw = 190.0;
    self.hudPanel.frame = CGRectMake((w - hw) / 2.0, safe.top + 8.0, hw, 48.0);
    self.hudSpeed.frame = CGRectMake(8.0, 2.0, 80.0, 44.0);
    self.hudRpm.frame = CGRectMake(88.0, 3.0, 58.0, 21.0);
    self.hudGear.frame = CGRectMake(146.0, 3.0, 38.0, 21.0);

    // Right-hand camera / menu buttons.
    self.menuButton.frame = CGRectMake(w - safe.right - 10.0 - 62.0, safe.top + 8.0, 62.0, 32.0);
    self.cameraButton.frame = CGRectMake(CGRectGetMinX(self.menuButton.frame) - 8.0 - 68.0,
                                         safe.top + 8.0, 68.0, 32.0);

    // Left thumb: wheel. Right thumb: brake (inner) + gas (outer).
    CGFloat wheelSize = MIN(158.0, h * 0.40);
    self.wheel.frame = CGRectMake(safe.left + 14.0, h - safe.bottom - 14.0 - wheelSize,
                                  wheelSize, wheelSize);

    CGFloat pedalW = 64.0, pedalH = MIN(126.0, h * 0.32);
    CGFloat pedalY = h - safe.bottom - 14.0 - pedalH;
    CGFloat gasX = w - safe.right - 14.0 - pedalW;
    CGFloat brakeX = gasX - pedalW - 8.0;
    self.gasPedal.frame = CGRectMake(gasX, pedalY, pedalW, pedalH);
    self.brakePedal.frame = CGRectMake(brakeX, pedalY, pedalW, pedalH);

    self.gearDownButton.frame = CGRectMake(brakeX, pedalY - 42.0, pedalW, 34.0);
    self.gearUpButton.frame = CGRectMake(gasX, pedalY - 42.0, pedalW, 34.0);

    // Handbrake between the wheel and the pedals.
    self.handbrakeButton.frame = CGRectMake(CGRectGetMaxX(self.wheel.frame) + 14.0,
                                            h - safe.bottom - 14.0 - 52.0, 104.0, 52.0);
    self.gearboxButton.frame = CGRectMake(CGRectGetMinX(self.handbrakeButton.frame),
                                          CGRectGetMinY(self.handbrakeButton.frame) - 40.0,
                                          118.0, 34.0);

    self.debugLabel.frame = CGRectMake(safe.left + 12.0, safe.top + 64.0,
                                       MIN(300.0, w * 0.32), 150.0);
    self.messageLabel.frame = CGRectMake((w - 520.0) / 2.0, (h - 80.0) / 2.0, 520.0, 80.0);
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    ac_ios_render_destroy();
    ac_ios_metal_destroy();
    ac_pal_bridge_shutdown();
    ac_ios_set_metal_layer(NULL);
}

#pragma mark - Build UI

- (void)buildMenu {
    self.menuPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.menuPanel.backgroundColor = [[UIColor colorWithWhite:0.06 alpha:1.0] colorWithAlphaComponent:0.88];
    self.menuPanel.layer.cornerRadius = 14.0;
    self.menuPanel.layer.borderWidth = 1.0;
    self.menuPanel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    [self.view addSubview:self.menuPanel];

    self.folderButton = [[ACRoundButton alloc] initWithTitle:@"Import AC folder" accent:NO];
    [self.folderButton addTarget:self action:@selector(chooseFolderTapped)
                forControlEvents:UIControlEventTouchUpInside];
    [self.menuPanel addSubview:self.folderButton];

    self.controlsButton = [[ACRoundButton alloc] initWithTitle:@"Controls" accent:NO];
    [self.controlsButton addTarget:self action:@selector(controlsTapped)
                  forControlEvents:UIControlEventTouchUpInside];
    [self.menuPanel addSubview:self.controlsButton];

    self.settingsButton = [[ACRoundButton alloc] initWithTitle:@"Settings" accent:NO];
    [self.settingsButton addTarget:self action:@selector(settingsTapped)
                  forControlEvents:UIControlEventTouchUpInside];
    [self.menuPanel addSubview:self.settingsButton];

    self.driveButton = [[ACRoundButton alloc] initWithTitle:@"DRIVE" accent:YES];
    [self.driveButton addTarget:self action:@selector(driveTapped)
               forControlEvents:UIControlEventTouchUpInside];
    [self.menuPanel addSubview:self.driveButton];

    self.menuTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.menuTable.dataSource = self;
    self.menuTable.delegate = self;
    self.menuTable.backgroundColor = UIColor.clearColor;
    self.menuTable.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    [self.menuTable registerClass:UITableViewCell.class forCellReuseIdentifier:@"content"];
    [self.menuPanel addSubview:self.menuTable];

    self.menuInfo = [[UILabel alloc] initWithFrame:CGRectZero];
    self.menuInfo.numberOfLines = 0;
    self.menuInfo.font = [UIFont systemFontOfSize:11.0];
    self.menuInfo.textColor = [UIColor colorWithWhite:0.88 alpha:1.0];
    self.menuInfo.hidden = YES;
    [self.menuPanel addSubview:self.menuInfo];

    self.debugToggleButton = [[ACRoundButton alloc] initWithTitle:@"Diagnostics: OFF" accent:NO];
    [self.debugToggleButton addTarget:self action:@selector(debugToggled)
                     forControlEvents:UIControlEventTouchUpInside];
    self.debugToggleButton.hidden = YES;
    [self.menuPanel addSubview:self.debugToggleButton];

    self.centerToggleButton = [[ACRoundButton alloc] initWithTitle:@"Wheel auto-centre: ON" accent:NO];
    [self.centerToggleButton addTarget:self action:@selector(centerToggled)
                      forControlEvents:UIControlEventTouchUpInside];
    self.centerToggleButton.hidden = YES;
    [self.menuPanel addSubview:self.centerToggleButton];
}

- (void)buildHUD {
    self.hudPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.hudPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.48];
    self.hudPanel.layer.cornerRadius = 10.0;
    [self.view addSubview:self.hudPanel];

    self.hudSpeed = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hudSpeed.font = [UIFont boldSystemFontOfSize:34.0];
    self.hudSpeed.textColor = UIColor.whiteColor;
    self.hudSpeed.text = @"0";
    [self.hudPanel addSubview:self.hudSpeed];

    self.hudRpm = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hudRpm.font = [UIFont boldSystemFontOfSize:12.0];
    self.hudRpm.textColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    self.hudRpm.text = @"0 rpm";
    [self.hudPanel addSubview:self.hudRpm];

    self.hudGear = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hudGear.font = [UIFont boldSystemFontOfSize:20.0];
    self.hudGear.textAlignment = NSTextAlignmentCenter;
    self.hudGear.textColor = [UIColor colorWithRed:1.0 green:0.72 blue:0.25 alpha:1.0];
    self.hudGear.text = @"N";
    [self.hudPanel addSubview:self.hudGear];

    self.debugLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.debugLabel.numberOfLines = 0;
    self.debugLabel.font = [UIFont fontWithName:@"Menlo" size:10.0] ?: [UIFont systemFontOfSize:10.0];
    self.debugLabel.textColor = [UIColor colorWithWhite:0.75 alpha:0.9];
    self.debugLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    self.debugLabel.layer.cornerRadius = 6.0;
    self.debugLabel.hidden = YES;
    [self.view addSubview:self.debugLabel];

    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.font = [UIFont boldSystemFontOfSize:14.0];
    self.messageLabel.textColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.35 alpha:1.0];
    self.messageLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
    self.messageLabel.layer.cornerRadius = 10.0;
    self.messageLabel.hidden = YES;
    [self.view addSubview:self.messageLabel];
}

- (void)buildDrivingControls {
    // The wheel publishes its value through ACWheelControl.value; the render
    // loop reads it directly. No block capture -> no retain cycle per frame.
    self.wheel = [[ACWheelControl alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.wheel];

    self.gasPedal = [[ACPedalControl alloc] initWithFrame:CGRectZero
                                                    title:@"GAS"
                                                    color:[UIColor colorWithRed:0.25 green:0.82 blue:0.35 alpha:1.0]];
    self.brakePedal = [[ACPedalControl alloc] initWithFrame:CGRectZero
                                                      title:@"BRAKE"
                                                      color:[UIColor colorWithRed:0.94 green:0.28 blue:0.24 alpha:1.0]];
    [self.view addSubview:self.brakePedal];
    [self.view addSubview:self.gasPedal];

    self.gearDownButton = [[ACRoundButton alloc] initWithTitle:@"GEAR -" accent:NO];
    [self.gearDownButton addTarget:self action:@selector(gearDownTapped)
                  forControlEvents:UIControlEventTouchDown];
    self.gearUpButton = [[ACRoundButton alloc] initWithTitle:@"GEAR +" accent:NO];
    [self.gearUpButton addTarget:self action:@selector(gearUpTapped)
                forControlEvents:UIControlEventTouchDown];
    self.handbrakeButton = [[ACRoundButton alloc] initWithTitle:@"HANDBRAKE" accent:NO];
    [self.handbrakeButton addTarget:self action:@selector(handbrakeDown)
                   forControlEvents:UIControlEventTouchDown];
    [self.handbrakeButton addTarget:self action:@selector(handbrakeUp)
                   forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                                    UIControlEventTouchCancel];
    self.cameraButton = [[ACRoundButton alloc] initWithTitle:@"CAMERA" accent:NO];
    [self.cameraButton addTarget:self action:@selector(cameraTapped)
                forControlEvents:UIControlEventTouchUpInside];
    self.menuButton = [[ACRoundButton alloc] initWithTitle:@"MENU" accent:NO];
    [self.menuButton addTarget:self action:@selector(menuTapped)
              forControlEvents:UIControlEventTouchUpInside];
    self.gearboxButton = [[ACRoundButton alloc] initWithTitle:@"AUTO" accent:NO];
    [self.gearboxButton addTarget:self action:@selector(gearboxToggled)
                 forControlEvents:UIControlEventTouchUpInside];

    for (UIView *v in @[self.gearDownButton, self.gearUpButton, self.handbrakeButton,
                        self.cameraButton, self.menuButton, self.gearboxButton]) {
        [self.view addSubview:v];
    }
}

#pragma mark - Menu actions

- (void)chooseFolderTapped {
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    [app chooseACRootFrom:self];
}

- (void)menuTapped {
    self.menuPanel.hidden = !self.menuPanel.hidden;
    if (!self.menuPanel.hidden) {
        // Opening the menu must not keep the car accelerating.
        [self.wheel setToNeutral];
        [self.gasPedal setToNeutral];
        [self.brakePedal setToNeutral];
        self.touchHandbrake = NO;
    }
}

- (void)controlsTapped {
    self.menuTable.hidden = YES;
    self.menuInfo.hidden = NO;
    self.debugToggleButton.hidden = YES;
    self.centerToggleButton.hidden = YES;
    self.menuInfo.text =
        @"DRIVING\n"
        "Wheel — drag left/right to steer, release to centre.\n"
        "GAS / BRAKE — slide thumb up for analogue pressure.\n"
        "GEAR +/- — paddles. HANDBRAKE — hold.\n"
        "CAMERA — cycle AC's own views.\n\n"
        "GAMEPAD\n"
        "Left stick steer, RT gas, LT brake,\n"
        "A gear up, X gear down, B handbrake, Y camera.\n\n"
        "MENU pauses inputs without resetting the session.";
}

- (void)settingsTapped {
    self.menuTable.hidden = YES;
    self.menuInfo.hidden = YES;
    self.debugToggleButton.hidden = NO;
    self.centerToggleButton.hidden = NO;
}

- (void)debugToggled {
    self.debugEnabled = !self.debugEnabled;
    self.debugLabel.hidden = !self.debugEnabled;
    [self.debugToggleButton setTitle:(self.debugEnabled ? @"Diagnostics: ON" : @"Diagnostics: OFF")
                            forState:UIControlStateNormal];
}

- (void)centerToggled {
    self.returnToCenter = !self.returnToCenter;
    [self.centerToggleButton setTitle:(self.returnToCenter ? @"Wheel auto-centre: ON" : @"Wheel auto-centre: OFF")
                             forState:UIControlStateNormal];
}

- (void)gearUpTapped { self.gearUpPending = YES; }
- (void)gearDownTapped { self.gearDownPending = YES; }
- (void)cameraTapped { self.cameraPending = YES; }
- (void)handbrakeDown { self.touchHandbrake = YES; }
- (void)handbrakeUp { self.touchHandbrake = NO; }
- (void)gearboxToggled {
    self.autoShifter = !self.autoShifter;
    [self.gearboxButton setTitle:(self.autoShifter ? @"AUTO" : @"MANUAL")
                        forState:UIControlStateNormal];
}

#pragma mark - Session lifecycle

- (void)showMessage:(NSString *)text {
    self.messageLabel.text = text;
    self.messageLabel.hidden = NO;
    [self.view bringSubviewToFront:self.messageLabel];
}

- (void)scanContent {
    NSString *root = self.acRootURL.path ?: @"";
    ac_ios_set_content_root(root);
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *carsPath = [root stringByAppendingPathComponent:@"content/cars"];
    NSString *tracksPath = [root stringByAppendingPathComponent:@"content/tracks"];
    self.cars = [[fm contentsOfDirectoryAtPath:carsPath error:NULL] ?: @[] sortedArrayUsingSelector:@selector(compare:)];
    self.tracks = [[fm contentsOfDirectoryAtPath:tracksPath error:NULL] ?: @[] sortedArrayUsingSelector:@selector(compare:)];

    // Preserve an existing choice if the same content is still installed.
    BOOL carStillThere = [self.cars containsObject:self.selectedCar ?: @""];
    BOOL trackStillThere = [self.tracks containsObject:self.selectedTrack ?: @""];
    if (!carStillThere) self.selectedCar = self.cars.firstObject;
    if (!trackStillThere) self.selectedTrack = self.tracks.firstObject;
    self.showCarsInMenu = YES;
    [self.menuTable reloadData];
}

- (void)acRootChanged:(NSNotification *)note {
    self.acRootURL = note.object;
    [self scanContent];
    [self showMessage:@"AC folder changed — press DRIVE for a new real session"];
}

- (void)driveTapped {
    self.lastFrameTime = 0;
    if (!self.acRootURL) {
        [self showMessage:@"Import your Assetto Corsa folder first"];
        return;
    }
    // Re-driving with a different car/track must not reuse a renderer loaded
    // for the previous session: tear down both GPU layers first.
    ac_ios_render_destroy();
    ac_ios_metal_destroy();
    self.renderReady = NO;
    [self resetTransientInput];

    ac_ios_set_auto_shifter(self.autoShifter ? 1 : 0);
    if (ac_ios_install_core_vtable() != 0) {
        [self showMessage:@"Failed to initialise the native core bridge"];
        return;
    }
    const char *root = self.acRootURL.path.UTF8String ?: "";
    const char *car = self.selectedCar.UTF8String ?: "";
    const char *track = self.selectedTrack.UTF8String ?: "";
    self.sessionOpen = (ac_pal_bridge_open_session(root, car, track) == 0);
    if (!self.sessionOpen) {
        [self showMessage:@"Real rustyAC session failed — see the app log"];
        return;
    }

    CGFloat scale = self.metalView.contentScaleFactor;
    uint32_t width  = (uint32_t)(self.metalView.bounds.size.width  * scale);
    uint32_t height = (uint32_t)(self.metalView.bounds.size.height * scale);
    char err[512] = {0};
    int metalResult = ac_ios_metal_init(ac_ios_metal_layer(), width, height, err, sizeof(err));
    if (metalResult != 0) {
        [self showMessage:[NSString stringWithFormat:@"Metal chain FAILED: %s", err]];
        return;
    }
    uint64_t features[4] = {0};
    ac_ios_metal_device_info(features);
    self.metalFeatures = (unsigned long long)features[0];

    int renderResult = ac_ios_render_init(ac_pal_bridge_session(), width, height, err, sizeof(err));
    if (renderResult != 0) {
        [self showMessage:[NSString stringWithFormat:@"Real AC renderer FAILED: %s", err]];
        return;
    }
    self.renderReady = YES;
    self.messageLabel.hidden = YES;
    // Drive closes the menu; MENU reopens it without touching the session.
    self.menuPanel.hidden = YES;
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
- (void)appWillResign:(NSNotification *)note { [self resetTransientInput]; }
- (void)appDidBecomeActive:(NSNotification *)note { [self resetTransientInput]; }

/// Touch values are already analogue from the two UIControl objects. There is
/// deliberately no sign flip here: rustyAC's CarControls is positive = right
/// and a right drag on ACWheelControl produces +value.
- (ACIosInputState)pollInput {
    ACIosInputState state = {0};
    GCController *pad = GCController.controllers.firstObject;
    BOOL padGearUp = NO, padGearDown = NO, padCamera = NO;

    if (pad.extendedGamepad) {
        GCExtendedGamepad *gp = pad.extendedGamepad;
        state.steer = gp.leftThumbstick.xAxis.value;
        state.throttle = gp.rightTrigger.value;
        state.brake = gp.leftTrigger.value;
        state.handbrake = gp.buttonB.isPressed ? 1 : 0;
        padGearUp = gp.buttonA.isPressed;
        padGearDown = gp.buttonX.isPressed;
        padCamera = gp.buttonY.isPressed;
    } else if (pad.microGamepad) {
        GCMicroGamepad *gp = pad.microGamepad;
        state.steer = gp.dpad.xAxis.value;
        state.throttle = gp.buttonA.isPressed ? 1.0f : 0.0f;
        state.brake = gp.buttonX.isPressed ? 1.0f : 0.0f;
        padGearUp = gp.buttonA.isPressed && gp.buttonX.isPressed;
    } else {
        state.steer = self.wheel.value;
        state.throttle = self.gasPedal.value;
        state.brake = self.brakePedal.value;
        state.handbrake = self.touchHandbrake ? 1 : 0;
    }

    // An open menu must never leave the car driving itself.
    if (!self.menuPanel.hidden) {
        state.steer = 0.0f;
        state.throttle = 0.0f;
        state.brake = 0.0f;
        state.handbrake = 0;
    }

    state.gear_up = (padGearUp && !self.lastGamepadGearUp) || self.gearUpPending;
    state.gear_down = (padGearDown && !self.lastGamepadGearDown) || self.gearDownPending;
    state.camera_request = (padCamera && !self.lastGamepadCamera) || self.cameraPending;
    self.lastGamepadGearUp = padGearUp;
    self.lastGamepadGearDown = padGearDown;
    self.lastGamepadCamera = padCamera;
    self.gearUpPending = self.gearDownPending = self.cameraPending = NO;
    return state;
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    if (ac_ios_metal_is_ready()) {
        CGFloat scale = view.contentScaleFactor;
        uint32_t w = (uint32_t)(size.width * scale);
        uint32_t h = (uint32_t)(size.height * scale);
        if (ac_ios_metal_resize(w, h) == 0 && self.renderReady) {
            ac_ios_render_resize(w, h);
        }
    }
}

- (void)drawInMTKView:(MTKView *)view {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double delta = self.lastFrameTime > 0 ? (now - self.lastFrameTime) : 1.0 / 60.0;
    self.lastFrameTime = now;
    if (delta > 0.1) delta = 0.1;
    if (delta > 0.0) {
        float instant = (float)(1.0 / delta);
        self.smoothedFps = self.smoothedFps > 0.0f
            ? self.smoothedFps * 0.9f + instant * 0.1f : instant;
    }

    ACIosInputState input = [self pollInput];
    ac_ios_set_input(input);
    ac_pal_bridge_set_controls(input.steer, input.throttle, input.brake,
                               input.handbrake ? 1.0f : 0.0f,
                               input.gear_up, input.gear_down, input.camera_request);
    ac_pal_bridge_run_frame(delta);

    float snapshot[16] = {0};
    ac_pal_bridge_snapshot(snapshot);
    float speed = snapshot[0];
    float rpm = snapshot[1];
    float gear = snapshot[2];
    float gas = snapshot[3];
    float brake = snapshot[4];
    float steer = snapshot[5];
    float steps = snapshot[6];
    float trackLoaded = snapshot[7];
    ac_ios_audio_set(rpm, gas);

    // HUD: only three small labels, throttled to 10 Hz to avoid allocations.
    if (++self.telemetryFrame % 6 == 0) {
        self.hudSpeed.text = [NSString stringWithFormat:@"%.0f", speed];
        self.hudRpm.text = [NSString stringWithFormat:@"%.0f rpm", rpm];
        self.hudGear.text = gear < 0.5f ? @"N" : [NSString stringWithFormat:@"%.0f", gear];
        if (self.debugEnabled) {
            self.debugLabel.text = [NSString stringWithFormat:
                @"REAL AC SESSION: %@\n"
                "Scene: %@\n"
                "Track: %@\n"
                "Physics steps: %.0f\n"
                "FPS: %.1f\n"
                "Render: %.2f ms\n"
                "Metal features: 0x%llx\n"
                "gas %.2f brake %.2f\n"
                "steer %.2f (%@)",
                self.sessionOpen ? @"yes" : @"NO",
                self.renderReady ? @"loaded" : @"none",
                trackLoaded > 0.5 ? @"loaded" : @"none",
                steps, self.smoothedFps,
                ac_ios_render_last_draw_ms(),
                self.metalFeatures,
                gas, brake, steer,
                steer > 0.02f ? @"right" : (steer < -0.02f ? @"left" : @"centre")];
        }
    }

    if (self.renderReady) {
        if (ac_ios_render_frame(ac_pal_bridge_session()) != 0) {
            self.renderReady = NO;
            [self showMessage:@"Real renderer frame failed — see app log"];
        }
    }
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.cars.count : self.tracks.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Cars (your install)" : @"Tracks (your install)";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"content" forIndexPath:indexPath];
    cell.textLabel.text = indexPath.section == 0 ? self.cars[indexPath.row] : self.tracks[indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:13.0];
    cell.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.accessoryType = ([cell.textLabel.text isEqualToString:self.selectedCar] ||
                          [cell.textLabel.text isEqualToString:self.selectedTrack])
                         ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) self.selectedCar = self.cars[indexPath.row];
    else self.selectedTrack = self.tracks[indexPath.row];
    [tableView reloadData];
}

@end

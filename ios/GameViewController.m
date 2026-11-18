//
//  GameViewController.m — UIKit/MetalKit host for the AC iOS prototype.
//  Requires macOS + Xcode + iOS SDK. NOT compiled on the research host.
//
//  Scope: UIKit/MetalKit host for the real rustyAC engine. It presents the
//  real AC scene (AcRenderer) using the live GameSim for car pose/wheels and
//  routes touch + GameController input into the simulation. No game assets
//  are bundled; the user imports a legal AC install.
//
#import "GameViewController.h"
#import "AppDelegate.h"
#import "ios_bridge.h"
#import "ac_pal_bridge.h"
#include <math.h>

#import <MetalKit/MetalKit.h>
#import <GameController/GameController.h>

@interface GameViewController () <MTKViewDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) UITableView *menu;
@property (nonatomic, strong) UIButton *driveButton;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) NSArray<NSString *> *cars;
@property (nonatomic, strong) NSArray<NSString *> *tracks;
@property (nonatomic, copy) NSString *selectedCar;
@property (nonatomic, copy) NSString *selectedTrack;
@property (nonatomic, assign) BOOL sessionOpen;
@property (nonatomic, assign) float touchSteer;
@property (nonatomic, assign) float touchThrottle;
@property (nonatomic, assign) float touchBrake;
@property (nonatomic, assign) BOOL touchHandbrake;
@property (nonatomic, assign) BOOL gearUpPending;
@property (nonatomic, assign) BOOL gearDownPending;
@property (nonatomic, assign) BOOL cameraPending;
@property (nonatomic, assign) BOOL lastGamepadGearUp;
@property (nonatomic, assign) BOOL lastGamepadGearDown;
@property (nonatomic, assign) BOOL lastGamepadCamera;
@property (nonatomic, assign) NSInteger cameraIndex;
@property (nonatomic, strong) UIButton *chooseFolderButton;
@property (nonatomic, strong) UIButton *gearUpButton;
@property (nonatomic, strong) UIButton *gearDownButton;
@property (nonatomic, strong) UIButton *handbrakeButton;
@property (nonatomic, strong) UIButton *cameraButton;
@property (nonatomic, strong) UIButton *gearboxButton;
@property (nonatomic, assign) BOOL autoShifter;
@property (nonatomic, assign) NSUInteger telemetryFrame;
@property (nonatomic, assign) BOOL renderReady;
@property (nonatomic, assign) CFAbsoluteTime lastFrameTime;
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    // Metal surface. wgpu (on macOS build) will request a Metal-backed device
    // from this layer and pass it to rustyAC via Kgl::give_device().
    self.metalView = [[MTKView alloc] initWithFrame:CGRectZero device:MTLCreateSystemDefaultDevice()];
    self.metalView.translatesAutoresizingMaskIntoConstraints = NO;
    self.metalView.delegate = self;
    self.metalView.preferredFramesPerSecond = 60;
    self.metalView.clearColor = MTLClearColorMake(0.04, 0.05, 0.07, 1.0);
    [self.view addSubview:self.metalView];
    ac_ios_set_metal_layer((__bridge void *)self.metalView.layer);

    [self buildMenu];
    [self scanContent];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(acRootChanged:)
                                                 name:ACiOSRootDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gamepadChanged:)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gamepadChanged:)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillResign:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [self updateStatus:self.acRootURL.path ?: @"No AC folder selected"];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    ac_ios_render_destroy();
    ac_ios_metal_destroy();
    ac_pal_bridge_shutdown();
    ac_ios_set_metal_layer(NULL);
}

- (void)acRootChanged:(NSNotification *)note {
    self.acRootURL = note.object;
    [self scanContent];
    [self updateStatus:@"AC folder changed — press Drive to make a new real session"];
}

/// A pad may disappear mid-session: clear latched button edges and all touch
/// state so the next frame cannot keep a gear or throttle request alive.
- (void)gamepadChanged:(NSNotification *)note {
    self.lastGamepadGearUp = self.lastGamepadGearDown = self.lastGamepadCamera = NO;
    self.gearUpPending = self.gearDownPending = self.cameraPending = NO;
    self.touchSteer = self.touchThrottle = self.touchBrake = 0.0f;
    self.touchHandbrake = NO;
}

- (void)resetTransientInput {
    self.touchSteer = self.touchThrottle = self.touchBrake = 0.0f;
    self.touchHandbrake = NO;
    self.gearUpPending = self.gearDownPending = self.cameraPending = NO;
    self.lastGamepadGearUp = self.lastGamepadGearDown = self.lastGamepadCamera = NO;
    self.lastFrameTime = 0;
}

- (void)appWillResign:(NSNotification *)note {
    [self resetTransientInput];
}

- (void)appDidBecomeActive:(NSNotification *)note {
    [self resetTransientInput];
}

- (UIButton *)makeControlButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
    button.layer.cornerRadius = 8;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:button];
    return button;
}

- (void)gearUpTapped { self.gearUpPending = YES; }
- (void)gearDownTapped { self.gearDownPending = YES; }
- (void)cameraTapped { self.cameraPending = YES; }
- (void)gearboxToggled {
    self.autoShifter = !self.autoShifter;
    [self.gearboxButton setTitle:(self.autoShifter ? @"Gearbox: AUTO" : @"Gearbox: MANUAL")
                        forState:UIControlStateNormal];
}
- (void)handbrakeDown { self.touchHandbrake = YES; }
- (void)handbrakeUp { self.touchHandbrake = NO; }

- (void)buildMenu {
    self.menu = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.menu.translatesAutoresizingMaskIntoConstraints = NO;
    self.menu.dataSource = self;
    self.menu.delegate = self;
    [self.menu registerClass:UITableViewCell.class forCellReuseIdentifier:@"content"];
    [self.view addSubview:self.menu];

    self.chooseFolderButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.chooseFolderButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.chooseFolderButton setTitle:@"Choose AC folder" forState:UIControlStateNormal];
    [self.chooseFolderButton addTarget:self action:@selector(chooseFolderTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.chooseFolderButton];

    self.gearUpButton = [self makeControlButton:@"Gear +" action:@selector(gearUpTapped)];
    self.gearDownButton = [self makeControlButton:@"Gear -" action:@selector(gearDownTapped)];
    self.cameraButton = [self makeControlButton:@"Camera" action:@selector(cameraTapped)];
    self.handbrakeButton = [self makeControlButton:@"Handbrake" action:@selector(handbrakeDown)];
    self.autoShifter = YES;
    self.gearboxButton = [self makeControlButton:@"Gearbox: AUTO" action:@selector(gearboxToggled)];
    [self.handbrakeButton addTarget:self action:@selector(handbrakeUp)
                   forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                                    UIControlEventTouchCancel];

    self.driveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.driveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.driveButton setTitle:@"Drive" forState:UIControlStateNormal];
    [self.driveButton addTarget:self action:@selector(driveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.driveButton];

    self.status = [[UILabel alloc] init];
    self.status.translatesAutoresizingMaskIntoConstraints = NO;
    self.status.numberOfLines = 0;
    self.status.textColor = UIColor.systemYellowColor;
    self.status.font = [UIFont systemFontOfSize:12.0];
    [self.view addSubview:self.status];

    [NSLayoutConstraint activateConstraints:@[
        [self.metalView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.metalView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.metalView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.metalView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.menu.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.menu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.menu.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.45],
        [self.menu.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:0.5],
        [self.driveButton.topAnchor constraintEqualToAnchor:self.menu.bottomAnchor constant:8],
        [self.driveButton.leadingAnchor constraintEqualToAnchor:self.menu.leadingAnchor],
        [self.chooseFolderButton.topAnchor constraintEqualToAnchor:self.driveButton.bottomAnchor constant:8],
        [self.chooseFolderButton.leadingAnchor constraintEqualToAnchor:self.menu.leadingAnchor],
        [self.gearUpButton.topAnchor constraintEqualToAnchor:self.chooseFolderButton.bottomAnchor constant:8],
        [self.gearUpButton.leadingAnchor constraintEqualToAnchor:self.menu.leadingAnchor],
        [self.gearUpButton.widthAnchor constraintEqualToConstant:70],
        [self.gearDownButton.topAnchor constraintEqualToAnchor:self.gearUpButton.topAnchor],
        [self.gearDownButton.leadingAnchor constraintEqualToAnchor:self.gearUpButton.trailingAnchor constant:6],
        [self.gearDownButton.widthAnchor constraintEqualToConstant:70],
        [self.cameraButton.topAnchor constraintEqualToAnchor:self.gearUpButton.bottomAnchor constant:6],
        [self.cameraButton.leadingAnchor constraintEqualToAnchor:self.menu.leadingAnchor],
        [self.cameraButton.widthAnchor constraintEqualToConstant:146],
        [self.handbrakeButton.topAnchor constraintEqualToAnchor:self.cameraButton.bottomAnchor constant:6],
        [self.handbrakeButton.leadingAnchor constraintEqualToAnchor:self.menu.leadingAnchor],
        [self.handbrakeButton.widthAnchor constraintEqualToConstant:146],
        [self.gearboxButton.topAnchor constraintEqualToAnchor:self.handbrakeButton.bottomAnchor constant:6],
        [self.gearboxButton.leadingAnchor constraintEqualToAnchor:self.menu.leadingAnchor],
        [self.gearboxButton.widthAnchor constraintEqualToConstant:146],
        [self.status.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.status.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-12],
        [self.status.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
    ]];
}

- (void)scanContent {
    NSString *root = self.acRootURL.path ?: @"";
    ac_ios_set_content_root(root);
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *carsPath = [root stringByAppendingPathComponent:@"content/cars"];
    NSString *tracksPath = [root stringByAppendingPathComponent:@"content/tracks"];
    self.cars = [[fm contentsOfDirectoryAtPath:carsPath error:NULL] ?: @[] sortedArrayUsingSelector:@selector(compare:)];
    self.tracks = [[fm contentsOfDirectoryAtPath:tracksPath error:NULL] ?: @[] sortedArrayUsingSelector:@selector(compare:)];
    self.selectedCar = self.cars.firstObject;
    self.selectedTrack = self.tracks.firstObject;
    [self.menu reloadData];
}

- (void)chooseFolderTapped {
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    [app chooseACRootFrom:self];
}

- (void)driveTapped {
    self.lastFrameTime = 0;
    if (!self.acRootURL) {
        [self updateStatus:@"Choose your Assetto Corsa folder first"];
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
        [self updateStatus:@"Failed to initialise the native core bridge"];
        return;
    }
    const char *root = self.acRootURL.path.UTF8String ?: "";
    const char *car = self.selectedCar.UTF8String ?: "";
    const char *track = self.selectedTrack.UTF8String ?: "";
    self.sessionOpen = (ac_pal_bridge_open_session(root, car, track) == 0);
    if (!self.sessionOpen) {
        [self updateStatus:@"Real rustyAC session failed — see the app log for the upstream error"];
        return;
    }

    // Build the REAL wgpu Metal chain from the MTKView's CAMetalLayer and
    // hand the Metal device to rustyAC's kgl layer before the first frame.
    CGFloat scale = self.metalView.contentScaleFactor;
    uint32_t width  = (uint32_t)(self.metalView.bounds.size.width  * scale);
    uint32_t height = (uint32_t)(self.metalView.bounds.size.height * scale);
    char err[512] = {0};
    int metalResult = ac_ios_metal_init(ac_ios_metal_layer(), width, height, err, sizeof(err));
    if (metalResult != 0) {
        [self updateStatus:[NSString stringWithFormat:
            @"Real physics session OK, Metal chain FAILED: %s", err]];
        return;
    }
    uint64_t features[4] = {0};
    ac_ios_metal_device_info(features);

    // Load the REAL KN5 track and car into AC's own renderer using the Metal
    // device handed to kgl above, reading the live GameSim for both models.
    int renderResult = ac_ios_render_init(ac_pal_bridge_session(), width, height, err, sizeof(err));
    if (renderResult != 0) {
        [self updateStatus:[NSString stringWithFormat:
            @"Metal OK, real AC renderer FAILED: %s", err]];
        return;
    }
    self.renderReady = YES;
    [self updateStatus:[NSString stringWithFormat:
        @"REAL AC scene: %@ @ %@ | Metal features 0x%llx",
        self.selectedCar, self.selectedTrack, (unsigned long long)features[0]]];
}

- (void)updateStatus:(NSString *)text {
    self.status.text = [text stringByAppendingString:
        @"\nTouch: steer / pedals · Camera button cycles views"
         "\nImport: copy the AC-iOS folder into this app via iTunes/Finder File Sharing, or tap 'Choose AC folder'"];
}

#pragma mark - Input

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self recomputeTouchControls:event];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self recomputeTouchControls:event];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self recomputeTouchControls:event];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self recomputeTouchControls:event];
}

/// Recomputes ALL touch controls from the live touch set. Resetting first is
/// what guarantees a lifted finger releases throttle/brake/steer instead of
/// leaving the car accelerating forever.
- (void)recomputeTouchControls:(UIEvent *)event {
    self.touchSteer = 0.0f;
    self.touchThrottle = 0.0f;
    self.touchBrake = 0.0f;

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            continue;
        }
        CGPoint p = [touch locationInView:self.view];
        if (p.x < w * 0.5) {
            self.touchSteer = (float)((p.x / (w * 0.5)) * 2.0 - 1.0);
        } else if (p.y < h * 0.5) {
            self.touchBrake = MAX(self.touchBrake,
                (float)(1.0 - fabs(p.y - h * 0.25) / (h * 0.25)));
        } else {
            self.touchThrottle = MAX(self.touchThrottle,
                (float)(1.0 - fabs(p.y - h * 0.75) / (h * 0.25)));
        }
    }
}

- (ACIosInputState)pollInput {
    ACIosInputState state = {0};
    GCController *pad = GCController.controllers.firstObject;
    BOOL padGearUp = NO, padGearDown = NO, padCamera = NO;

    if (pad.extendedGamepad) {
        // Matches Assetto Corsa's own XInput layout from controls.ini:
        // left stick steer, RT gas, LT brake, A gear up, X gear down, B handbrake.
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
        // Micro gamepads have no Y button; camera is handled by the touch button.
    } else {
        state.steer = self.touchSteer;
        state.throttle = self.touchThrottle;
        state.brake = self.touchBrake;
        state.handbrake = self.touchHandbrake ? 1 : 0;
    }

    // Edge detection: a held pad button must not request a shift every frame.
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
    // Real frame delta drives the fixed-step accumulator; on app resume we
    // clamp here and the bridge clamps again, so no simulation debt builds up.
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double delta = self.lastFrameTime > 0 ? (now - self.lastFrameTime) : 1.0 / 60.0;
    self.lastFrameTime = now;
    if (delta > 0.1) delta = 0.1;

    ACIosInputState input = [self pollInput];
    ac_ios_set_input(input);
    ac_pal_bridge_set_controls(input.steer, input.throttle, input.brake,
                               input.handbrake ? 1.0f : 0.0f,
                               input.gear_up, input.gear_down, input.camera_request);
    ac_pal_bridge_run_frame(delta);

    // This page is produced by CarView::capture after real rustyAC steps.
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

    // Visualise the REAL simulation state (not invented telemetry).
    if (++self.telemetryFrame % 30 == 0) {
        self.status.text = [NSString stringWithFormat:
            @"%@ | %@\n%.1f km/h | %.0f rpm | gear %.0f\n%.0f physics steps | track %@\nrender %.1f ms/frame\ngas %.2f brake %.2f steer %.2f",
            self.sessionOpen ? @"rustyAC REAL SESSION" : @"NO SESSION",
            self.renderReady ? @"REAL AC SCENE" : @"no scene",
            speed, rpm, gear, steps,
            trackLoaded > 0.5 ? @"loaded" : @"none",
            ac_ios_render_last_draw_ms(),
            gas, brake, steer];
    }

    // Present the REAL AC scene through the Metal surface, using the pose
    // produced by the live GameSim this frame.
    if (self.renderReady) {
        if (ac_ios_render_frame(ac_pal_bridge_session()) != 0) {
            self.renderReady = NO;
            [self updateStatus:@"Real renderer frame failed — see app log"];
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

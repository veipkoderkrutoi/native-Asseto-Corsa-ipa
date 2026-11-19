// SPDX-License-Identifier: GPL-3.0-or-later
//! C ABI between the UIKit shell / native PAL bridge and the REAL rustyAC engine.
//!
//! There is no mock core here. `session_create` sets the user's AC root, resolves
//! the car and track from that legal install, builds a real `GameSim` and steps
//! real `rustyac-physics` ticks. State written into the snapshot comes from
//! `CarView::capture` after the last real step.
//!
//! If content or the engine cannot be loaded, `session_create` returns null and
//! logs the exact upstream error. It never invents a session or telemetry.
//!
//! On iOS only, `metal` supplies the real CAMetalLayer -> wgpu -> kgl chain.

#[cfg(target_os = "ios")]
mod meminfo;
#[cfg(target_os = "ios")]
mod metal;
#[cfg(target_os = "ios")]
mod render;
/// Phase 11 UI helpers (lap formatting, FPS caps, PB rules). Pure and tested.
pub mod phase11;

/// Real AC lap-timer state for the Time Attack UI. Mirrors `ACIosLapState` in
/// `ios/ios_bridge.h`; only fixed-width C fields, no padding-sensitive bools.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct AcIosLapState {
    pub current_ms: u32,
    pub last_ms: u32,
    pub best_ms: u32,
    pub laps: u32,
    pub on_track: u32,
    pub valid: u32,
    pub last_valid: u32,
    pub cuts: i32,
    pub position: f32,
}

/// Reads the REAL AC lap timer from the live GameSim (never a wall-clock guess).
///
/// # Safety
/// `session` must be a live handle from `ac_ios_core_session_create`; `out` must
/// point to a writable `AcIosLapState`.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_core_lap_state(session: *mut c_void, out: *mut AcIosLapState) {
    if out.is_null() { return; }
    std::ptr::write_bytes(out, 0, 1);
    let Some(session) = as_session(session) else { return };
    let Ok(guard) = session.session.lock() else { return };
    let Some(real) = guard.as_ref() else { return };
    let lap = rustyac_game::view::CarView::capture(&real.sim, 0.0).lap;
    *out = AcIosLapState {
        current_ms: lap.current_ms,
        last_ms: lap.last_ms,
        best_ms: lap.best_ms,
        laps: lap.laps,
        on_track: lap.on_track as u32,
        valid: lap.valid as u32,
        last_valid: lap.last_valid as u32,
        cuts: lap.cuts,
        position: lap.position,
    };
}

use std::ffi::CStr;
use std::os::raw::{c_char, c_double, c_int, c_void};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

/// AC's automatic-gearbox aid. Touch users keep it on by default; a manual
/// toggle (or the native test) can disable it so gear paddles reach the car.
static AUTO_SHIFTER: AtomicBool = AtomicBool::new(true);

/// Sets the automatic gearbox aid BEFORE `ac_ios_core_session_create`.
#[no_mangle]
pub extern "C" fn ac_ios_set_auto_shifter(enabled: c_int) {
    AUTO_SHIFTER.store(enabled != 0, Ordering::Relaxed);
}

use rustyac_game::input_file::SimSetup;
use rustyac_game::sim::{find_car_data, find_track, GameSim, SpawnSequence};
use rustyac_game::view::CarView;
use rustyac_physics::car::{CarControls, CarControlsInput};
use rustyac_game::sim::DriverSource;

/// Must stay byte-for-byte compatible with `AcCoreVTable` in
/// `core/ac_pal_bridge.h`.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AcCoreVTable {
    pub session_create: Option<
        unsafe extern "C" fn(*const c_char, *const c_char, *const c_char) -> *mut c_void,
    >,
    pub session_destroy: Option<unsafe extern "C" fn(*mut c_void)>,
    pub session_set_input: Option<unsafe extern "C" fn(*mut c_void, f32, f32, f32)>,
    pub session_set_ext_input: Option<
        unsafe extern "C" fn(*mut c_void, f32, c_int, c_int, c_int),
    >,
    pub session_step: Option<unsafe extern "C" fn(*mut c_void, c_double)>,
    pub session_snapshot: Option<unsafe extern "C" fn(*mut c_void, *mut f32)>,
}

/// A real rustyAC session plus the control values the native bridge writes.
pub(crate) struct RealSession {
    pub(crate) sim: GameSim,
    pub(crate) controls: Arc<Mutex<CarControls>>,
    pub(crate) car: String,
    pub(crate) track: String,
}

/// Gives the iOS renderer mutable access to the live simulation of a session.
/// The pointer must be one returned by `ac_ios_core_session_create`.
pub(crate) fn with_session<R>(session: *mut c_void, f: impl FnOnce(&mut RealSession) -> R) -> Option<R> {
    let session = unsafe { as_session(session) }?;
    let mut guard = session.session.lock().ok()?;
    guard.as_mut().map(f)
}

/// `DriverSource` that feeds the controls coming from the C bridge into AC's
/// own `Car::controls` on every physics step (AC's `acquireControls` hook).
struct BridgeSource {
    controls: Arc<Mutex<CarControls>>,
}

impl DriverSource for BridgeSource {
    fn acquire(&mut self, controls: &mut CarControls, _dt: f32, _input: &CarControlsInput) {
        if let Ok(shared) = self.controls.lock() {
            *controls = *shared;
        }
    }
}

#[repr(C)]
struct AcSession {
    magic: u32,
    session: Mutex<Option<RealSession>>,
}

const SESSION_MAGIC: u32 = 0x4143_494F; // "ACIO"

unsafe fn as_session(ptr: *mut c_void) -> Option<&'static AcSession> {
    if ptr.is_null() {
        return None;
    }
    let session = &*(ptr as *const AcSession);
    (session.magic == SESSION_MAGIC).then_some(session)
}

fn read_cstr(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr) }.to_str().ok().map(str::to_owned)
}

/// Fills `out` with the vtable the C bridge should install.
///
/// # Safety
/// `out` must point to a writable `AcCoreVTable`.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_boot(out: *mut AcCoreVTable) -> c_int {
    if out.is_null() {
        return -1;
    }
    *out = AcCoreVTable {
        session_create: Some(ac_ios_core_session_create),
        session_destroy: Some(ac_ios_core_session_destroy),
        session_set_input: Some(ac_ios_core_session_set_input),
        session_set_ext_input: Some(ac_ios_core_session_set_ext_input),
        session_step: Some(ac_ios_core_session_step),
        session_snapshot: Some(ac_ios_core_session_snapshot),
    };
    0
}

/// Builds a real physics session from the user's installed Assetto Corsa.
///
/// # Safety
/// All string pointers must be valid NUL-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_core_session_create(
    root: *const c_char,
    car: *const c_char,
    track: *const c_char,
) -> *mut c_void {
    let (root, car, track) = match (read_cstr(root), read_cstr(car), read_cstr(track)) {
        (Some(r), Some(c), Some(t)) => (r, c, t),
        _ => return std::ptr::null_mut(),
    };

    // Point rustyAC's portable content layer at the user's own legal install.
    rustyac_content::install::set_ac_root(Some(PathBuf::from(&root)));

    if let Err(error) = find_car_data(&car) {
        eprintln!("ac_ios: car {car:?} not found: {error}");
        return std::ptr::null_mut();
    }
    if let Err(error) = find_track(&track) {
        eprintln!("ac_ios: track {track:?} not found: {error}");
        return std::ptr::null_mut();
    }

    let mut setup = SimSetup::default();
    setup.car = car.clone();
    setup.track = track.clone();
    setup.spawn = "hotlap".to_string();
    setup.auto_clutch = true;
    setup.auto_shifter = AUTO_SHIFTER.load(Ordering::Relaxed);
    // We are a native app, not the desktop debug window: controls must be live
    // from the first step (upstream's `esc_start` holds the car in the ESC menu).
    setup.esc_start = false;

    let controls = Arc::new(Mutex::new(CarControls {
        clutch: 1.0, // pedal up = engaged, per rustyac-physics CarControls
        ..CarControls::default()
    }));
    let source = BridgeSource { controls: Arc::clone(&controls) };

    let sim = match GameSim::new(setup, Box::new(SpawnSequence::new(source, true))) {
        Ok(sim) => sim,
        Err(error) => {
            eprintln!("ac_ios: rustyAC GameSim::new failed: {error}");
            return std::ptr::null_mut();
        }
    };
    eprintln!(
        "ac_ios: real session ready: {} @ {} (track loaded: {})",
        car,
        track,
        sim.track.is_some()
    );

    let session = Box::new(AcSession {
        magic: SESSION_MAGIC,
        session: Mutex::new(Some(RealSession { sim, controls, car, track })),
    });
    Box::into_raw(session) as *mut c_void
}

/// # Safety
/// `session` must come from `ac_ios_core_session_create` and not be freed yet.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_core_session_destroy(session: *mut c_void) {
    if session.is_null() {
        return;
    }
    let session = &mut *(session as *mut AcSession);
    if session.magic == SESSION_MAGIC {
        session.magic = 0;
        drop(Box::from_raw(session));
    }
}

/// Writes the bridge's controls into the real car's input for the next step.
///
/// # Safety
/// `session` must be a live handle from this crate.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_core_session_set_input(
    session: *mut c_void,
    steer: f32,
    throttle: f32,
    brake: f32,
) {
    let Some(session) = as_session(session) else { return };
    let Ok(mut guard) = session.session.lock() else { return };
    let Some(real) = guard.as_mut() else { return };
    if let Ok(mut controls) = real.controls.lock() {
        controls.steer = steer.clamp(-1.0, 1.0);
        controls.gas = throttle.clamp(0.0, 1.0);
        controls.brake = brake.clamp(0.0, 1.0);
        controls.clutch = 1.0;
    };
}

/// Applies handbrake, one-shot gear paddles and camera requests to the real
/// car. These values are consumed by `GameSim::step` through `BridgeSource`.
///
/// # Safety
/// `session` must be a live handle from this crate.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_core_session_set_ext_input(
    session: *mut c_void,
    handbrake: f32,
    gear_up: c_int,
    gear_down: c_int,
    camera_next: c_int,
) {
    let Some(session) = as_session(session) else { return };
    let Ok(mut guard) = session.session.lock() else { return };
    let Some(real) = guard.as_mut() else { return };
    if let Ok(mut controls) = real.controls.lock() {
        controls.hand_brake = handbrake.clamp(0.0, 1.0);
        controls.gear_up = gear_up != 0;
        controls.gear_dn = gear_down != 0;
    }
    if camera_next != 0 {
        #[cfg(target_os = "ios")]
        crate::render::camera_next();
        #[cfg(not(target_os = "ios"))]
        {
            let _ = camera_next;
        }
    }
}

/// Advances the simulation by exactly one real rustyAC physics tick
/// (`rustyac_game::sim::DT` = 0.003 s). The `dt` argument is informational:
/// `GameSim::step` owns its own fixed clock, like the original game.
///
/// # Safety
/// `session` must be a live handle from this crate.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_core_session_step(session: *mut c_void, _dt: c_double) {
    let Some(session) = as_session(session) else { return };
    let Ok(mut guard) = session.session.lock() else { return };
    let Some(real) = guard.as_mut() else { return };
    if let Err(error) = real.sim.step() {
        eprintln!("ac_ios: rustyAC step failed: {error}");
    }
}

/// Copies REAL post-step simulation state into the 16-float visualization page.
///
/// Layout: [0] speed_kmh, [1] rpm, [2] gear, [3] gas, [4] brake, [5] steer,
/// [6] completed steps, [7] track loaded (0/1), [8] rpm limit,
/// [9..11] body position (x,y,z), [12] mean wheel angular speed (rad/s),
/// [13] steering angle (deg), rest reserved.
///
/// # Safety
/// `out` must point to at least 16 writable floats.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_core_session_snapshot(session: *mut c_void, out: *mut f32) {
    if out.is_null() {
        return;
    }
    std::ptr::write_bytes(out, 0, 16);
    let Some(session) = as_session(session) else { return };
    let Ok(guard) = session.session.lock() else { return };
    let Some(real) = guard.as_ref() else { return };

    // AC's own view of the car after the last step — not invented telemetry.
    let view = CarView::capture(&real.sim, 0.0);
    *out = view.speed_kmh;
    *out.add(1) = view.rpm;
    *out.add(2) = view.gear as f32;
    *out.add(3) = view.gas;
    *out.add(4) = view.brake;
    *out.add(5) = view.steer;
    *out.add(6) = real.sim.steps as f32;
    *out.add(7) = if real.sim.track.is_some() { 1.0 } else { 0.0 };
    *out.add(8) = view.rpm_limit;
    *out.add(9) = view.body[3][0];
    *out.add(10) = view.body[3][1];
    *out.add(11) = view.body[3][2];
    let spin: f32 = view.wheel_angular_speed.iter().sum::<f32>() / 4.0;
    *out.add(12) = spin;
    *out.add(13) = view.steer_deg;
}

/// Writes `car@track` into `buf` for the diagnostic HUD.
///
/// # Safety
/// `buf` must point to at least `cap` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_core_session_describe(
    session: *mut c_void,
    buf: *mut c_char,
    cap: usize,
) -> c_int {
    if buf.is_null() || cap == 0 {
        return -1;
    }
    let Some(session) = as_session(session) else { return -2 };
    let Ok(guard) = session.session.lock() else { return -3 };
    let Some(real) = guard.as_ref() else { return -4 };
    let text = format!("{}@{}", real.car, real.track);
    let bytes = text.as_bytes();
    if bytes.len() + 1 > cap {
        return -5;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf as *mut u8, bytes.len());
    *buf.add(bytes.len()) = 0;
    bytes.len() as c_int
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    use std::path::Path;

    fn empty_vtable() -> AcCoreVTable {
        AcCoreVTable {
            session_create: None,
            session_destroy: None,
            session_set_input: None,
            session_set_ext_input: None,
            session_step: None,
            session_snapshot: None,
        }
    }

    #[test]
    fn vtable_layout_matches_c_header() {
        assert_eq!(std::mem::size_of::<AcCoreVTable>(), 6 * std::mem::size_of::<usize>());
    }

    #[test]
    fn boot_fills_all_callbacks() {
        let mut vt = empty_vtable();
        assert_eq!(unsafe { ac_ios_boot(&mut vt) }, 0);
        assert!(vt.session_create.is_some());
        assert!(vt.session_destroy.is_some());
        assert!(vt.session_set_input.is_some());
        assert!(vt.session_set_ext_input.is_some());
        assert!(vt.session_step.is_some());
        assert!(vt.session_snapshot.is_some());
    }

    #[test]
    fn invalid_arguments_are_rejected() {
        let mut vt = empty_vtable();
        assert_eq!(unsafe { ac_ios_boot(std::ptr::null_mut()) }, -1);
        assert_eq!(unsafe { ac_ios_boot(&mut vt) }, 0);
        assert!(unsafe {
            vt.session_create.unwrap()(std::ptr::null(), std::ptr::null(), std::ptr::null())
        }
        .is_null());
    }

    /// The decisive test: REAL rustyAC engine + REAL Assetto Corsa content.
    /// Skips only when no legal AC install is available at AC_ROOT.
    #[test]
    fn real_session_loads_ac_content_and_moves_the_car() {
        let root = std::env::var("AC_ROOT").unwrap_or_else(|_| {
            if Path::new("D:\\Games\\assettocorsa").is_dir() {
                "D:\\Games\\assettocorsa".to_string()
            } else {
                String::new()
            }
        });
        if root.is_empty() || !Path::new(&root).is_dir() {
            eprintln!("SKIP: no AC_ROOT install available");
            return;
        }

        let mut vt = empty_vtable();
        assert_eq!(unsafe { ac_ios_boot(&mut vt) }, 0);
        let root = CString::new(root).unwrap();
        let car = CString::new("lotus_elise_sc").unwrap();
        let track = CString::new("magione").unwrap();

        let session = unsafe { vt.session_create.unwrap()(root.as_ptr(), car.as_ptr(), track.as_ptr()) };
        assert!(!session.is_null(), "real GameSim::new failed");

        let mut before = [0f32; 16];
        unsafe { vt.session_snapshot.unwrap()(session, before.as_mut_ptr()) };
        assert_eq!(before[7], 1.0, "real track must be loaded");
        eprintln!(
            "ac_ios: BEFORE speed_kmh={:.3} rpm={:.1} gear={:.0} steps={:.0}",
            before[0], before[1], before[2], before[6]
        );

        // 900 real ticks = 2.7 simulated seconds with full throttle.
        unsafe { vt.session_set_input.unwrap()(session, 0.0, 1.0, 0.0) };
        let mut steering = [0f32; 16];
        for step in 0..900 {
            // A short steering input makes the wheels visibly turn, so the
            // renderer's wheel animation is proven to follow physics.
            // SpawnSequence ignores devices for its first 470 ticks (real AC
            // settling); steer only after the driver actually takes control.
            if (520..640).contains(&step) {
                unsafe { vt.session_set_input.unwrap()(session, 0.35, 1.0, 0.0) };
            } else if step == 640 {
                unsafe { vt.session_set_input.unwrap()(session, 0.0, 1.0, 0.0) };
            }
            unsafe { vt.session_step.unwrap()(session, rustyac_game::sim::DT as c_double) };
            if step == 580 {
                unsafe { vt.session_snapshot.unwrap()(session, steering.as_mut_ptr()) };
            }
        }

        let mut after = [0f32; 16];
        unsafe { vt.session_snapshot.unwrap()(session, after.as_mut_ptr()) };
        eprintln!(
            "ac_ios: AFTER  speed_kmh={:.3} rpm={:.1} gear={:.0} steps={:.0}",
            after[0], after[1], after[2], after[6]
        );
        eprintln!(
            "ac_ios: POSE before=({:.3},{:.3},{:.3}) after=({:.3},{:.3},{:.3})",
            before[9], before[10], before[11], after[9], after[10], after[11]
        );
        eprintln!(
            "ac_ios: WHEELS mean spin {:.3} -> {:.3} rad/s, steer_deg {:.3} -> {:.3}",
            before[12], after[12], before[13], after[13]
        );
        assert!(after[6] >= 900.0, "steps must advance, got {}", after[6]);
        assert!(after[0] > 1.0, "car must really move, speed_kmh={}", after[0]);
        assert!(after[1] > 0.0, "real engine rpm must be non-zero");
        let moved = ((after[9] - before[9]).powi(2)
            + (after[10] - before[10]).powi(2)
            + (after[11] - before[11]).powi(2))
            .sqrt();
        assert!(moved > 1.0, "real body position must change, delta={moved}");
        assert!(after[12] > 1.0, "real wheels must rotate, spin={}", after[12]);
        eprintln!(
            "ac_ios: STEER snapshot at step 580: steer_control={:.3} steer_deg={:.3} speed={:.3}",
            steering[5], steering[13], steering[0]
        );
        assert!(steering[13].abs() > 5.0, "steering must turn the real wheels, deg={}", steering[13]);
        eprintln!("ac_ios: STEER mid-drive steer_deg={:.3}", steering[13]);

        // BRAKING: a deterministic brake sequence must reduce real speed.
        unsafe { vt.session_set_input.unwrap()(session, 0.0, 0.0, 1.0) };
        for _ in 0..300 {
            unsafe { vt.session_step.unwrap()(session, rustyac_game::sim::DT as c_double) };
        }
        let mut braked = [0f32; 16];
        unsafe { vt.session_snapshot.unwrap()(session, braked.as_mut_ptr()) };
        eprintln!("ac_ios: BRAKE speed {:.3} -> {:.3} km/h", after[0], braked[0]);
        assert!(braked[0] < after[0], "brakes must reduce real speed");

        let mut description = [0i8; 64];
        let written = unsafe {
            ac_ios_core_session_describe(session, description.as_mut_ptr(), description.len())
        };
        assert!(written > 0);
        assert_eq!(
            unsafe { CStr::from_ptr(description.as_ptr()) }.to_str().unwrap(),
            "lotus_elise_sc@magione"
        );

        unsafe { vt.session_destroy.unwrap()(session) };

        // MANUAL GEAR: with the automatic gearbox aid off, a real gear-up
        // request must change the transmission's gear.
        unsafe { ac_ios_set_auto_shifter(0) };
        let manual = unsafe { vt.session_create.unwrap()(root.as_ptr(), car.as_ptr(), track.as_ptr()) };
        assert!(!manual.is_null());
        let mut gear_before = [0f32; 16];
        unsafe { vt.session_snapshot.unwrap()(manual, gear_before.as_mut_ptr()) };
        unsafe { vt.session_set_input.unwrap()(manual, 0.0, 1.0, 0.0) };
        for step in 0..900 {
            if step == 520 {
                unsafe { vt.session_set_ext_input.unwrap()(manual, 0.0, 1, 0, 0) };
            }
            unsafe { vt.session_step.unwrap()(manual, rustyac_game::sim::DT as c_double) };
        }
        let mut gear_after = [0f32; 16];
        unsafe { vt.session_snapshot.unwrap()(manual, gear_after.as_mut_ptr()) };
        eprintln!(
            "ac_ios: GEAR manual gear {:.0} -> {:.0}, speed {:.3} km/h",
            gear_before[2], gear_after[2], gear_after[0]
        );
        assert!(gear_after[2] > gear_before[2], "gear-up must change the real transmission");
        unsafe { vt.session_destroy.unwrap()(manual) };
        unsafe { ac_ios_set_auto_shifter(1) };
    }
}

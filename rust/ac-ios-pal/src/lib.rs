//! Platform abstraction layer (PAL) for the Assetto Corsa native iOS port.
//!
//! The simulation itself is rustyAC (`rustyac-physics`, `rustyac-ode`,
//! `rustyac-game`). This crate only defines the narrow interfaces the port
//! must supply on iOS, plus host-side test doubles so those interfaces can be
//! verified without an Apple SDK.
//!
//! Nothing here loads or redistributes protected game assets. Paths are
//! resolved at runtime against a user-provided, legally owned AC install.

use std::path::{Path, PathBuf};

/// Driver controls after platform-specific shaping (deadzone/expo already
/// applied by the native bridge). Values are clamped to their legal ranges.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ControlState {
    pub steer: f32,
    pub throttle: f32,
    pub brake: f32,
    pub handbrake: bool,
    /// Camera request: -1 previous, 0 none, +1 next.
    pub camera: i8,
}

impl ControlState {
    pub fn sanitized(&self) -> Self {
        let clamp = |v: f32| v.clamp(-1.0, 1.0);
        Self {
            steer: clamp(self.steer),
            throttle: self.throttle.clamp(0.0, 1.0),
            brake: self.brake.clamp(0.0, 1.0),
            handbrake: self.handbrake,
            camera: self.camera.clamp(-1, 1),
        }
    }
}

impl Default for ControlState {
    fn default() -> Self {
        Self { steer: 0.0, throttle: 0.0, brake: 0.0, handbrake: false, camera: 0 }
    }
}

/// A source of driver input (touch overlay and/or MFi/GameController pad).
pub trait InputSource {
    fn poll(&mut self) -> ControlState;
}

/// Locates content inside the user's legal Assetto Corsa installation.
///
/// On iOS the root is a user-selected directory imported through the Files
/// app and persisted as a security-scoped bookmark; the app ships no content.
pub trait ContentLocator {
    fn ac_root(&self) -> &Path;
    fn car_dir(&self, car_id: &str) -> PathBuf {
        self.ac_root().join("content").join("cars").join(car_id)
    }
    fn track_dir(&self, track_id: &str) -> PathBuf {
        self.ac_root().join("content").join("tracks").join(track_id)
    }
    fn car_kn5(&self, car_id: &str) -> Option<PathBuf> {
        let dir = self.car_dir(car_id);
        let file = dir.join(format!("{car_id}.kn5"));
        file.exists().then_some(file)
    }
    fn track_models(&self, track_id: &str) -> Option<PathBuf> {
        let file = self.track_dir(track_id).join("models.ini");
        file.exists().then_some(file)
    }
}

/// The presentation surface. On iOS this owns a `CAMetalLayer` and hands a
/// Metal-backed wgpu device to `rustyac_render::kgl::Kgl::give_device`.
pub trait RenderHost {
    fn begin_frame(&mut self);
    fn end_frame(&mut self);
}

/// Audio output. rustyAC's FMOD port is desktop/browser-only today; on iOS
/// this sink is backed by CoreAudio and consumes the engine state produced by
/// the portable DSP in `rustyac-audio`.
pub trait AudioSink {
    fn set_engine_state(&mut self, rpm: f32, load: f32);
    fn suspend(&mut self);
    fn resume(&mut self);
}

/// Aggregated platform contract consumed by the app runtime.
pub trait Platform {
    type Input: InputSource;
    type Content: ContentLocator;
    type Renderer: RenderHost;
    type Audio: AudioSink;

    fn input(&mut self) -> &mut Self::Input;
    fn content(&self) -> &Self::Content;
    fn renderer(&mut self) -> &mut Self::Renderer;
    fn audio(&mut self) -> &mut Self::Audio;
}

// ---------------------------------------------------------------------------
// Host test doubles (compiled and exercised on Windows/Linux/macOS today).
// ---------------------------------------------------------------------------

/// Deterministic input source used by host tests.
#[derive(Debug, Clone)]
pub struct ScriptedInput {
    pub states: Vec<ControlState>,
    index: usize,
}

impl ScriptedInput {
    pub fn new(states: Vec<ControlState>) -> Self {
        Self { states, index: 0 }
    }
}

impl InputSource for ScriptedInput {
    fn poll(&mut self) -> ControlState {
        let state = self.states.get(self.index).copied().unwrap_or_default();
        self.index = self.index.saturating_add(1);
        state.sanitized()
    }
}

/// Content locator that points at any directory, used for local verification.
#[derive(Debug, Clone)]
pub struct DiskContentLocator {
    root: PathBuf,
}

impl DiskContentLocator {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }
}

impl ContentLocator for DiskContentLocator {
    fn ac_root(&self) -> &Path {
        &self.root
    }
}

/// Counts frames; no GPU work.
#[derive(Debug, Default)]
pub struct NullRenderHost {
    pub frames: u32,
}

impl RenderHost for NullRenderHost {
    fn begin_frame(&mut self) {}
    fn end_frame(&mut self) {
        self.frames += 1;
    }
}

/// Records the last engine state instead of producing sound.
#[derive(Debug, Default)]
pub struct RecordingAudioSink {
    pub last_rpm: f32,
    pub last_load: f32,
    pub suspended: bool,
}

impl AudioSink for RecordingAudioSink {
    fn set_engine_state(&mut self, rpm: f32, load: f32) {
        self.last_rpm = rpm;
        self.last_load = load;
    }
    fn suspend(&mut self) {
        self.suspended = true;
    }
    fn resume(&mut self) {
        self.suspended = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn control_state_is_clamped() {
        let state = ControlState {
            steer: 4.0,
            throttle: -2.0,
            brake: 9.0,
            handbrake: true,
            camera: 12,
        }
        .sanitized();
        assert_eq!(state.steer, 1.0);
        assert_eq!(state.throttle, 0.0);
        assert_eq!(state.brake, 1.0);
        assert_eq!(state.camera, 1);
    }

    #[test]
    fn scripted_input_is_deterministic_and_bounded() {
        let mut input = ScriptedInput::new(vec![
            ControlState { steer: 0.5, throttle: 1.0, brake: 0.0, ..Default::default() },
            ControlState { steer: -9.0, throttle: 0.0, brake: 0.5, ..Default::default() },
        ]);
        assert_eq!(input.poll().steer, 0.5);
        assert_eq!(input.poll().steer, -1.0);
        assert_eq!(input.poll(), ControlState::default());
    }

    #[test]
    fn content_paths_follow_ac_layout() {
        let locator = DiskContentLocator::new("/legal/AC");
        assert_eq!(locator.car_dir("bmw_m3_e30"), Path::new("/legal/AC/content/cars/bmw_m3_e30"));
        assert_eq!(locator.track_dir("drift"), Path::new("/legal/AC/content/tracks/drift"));
    }

    #[test]
    fn sinks_record_calls() {
        let mut renderer = NullRenderHost::default();
        renderer.begin_frame();
        renderer.end_frame();
        assert_eq!(renderer.frames, 1);

        let mut audio = RecordingAudioSink::default();
        audio.set_engine_state(7000.0, 0.4);
        audio.suspend();
        assert_eq!(audio.last_rpm, 7000.0);
        assert!(audio.suspended);
    }
}

/// Raw C ABI implemented by `ios/ios_bridge.m`. Declaring the entry points
/// here avoids any third-party Objective-C binding crate and keeps the host
/// build dependency-free. These symbols are only linked in an iOS build.
#[cfg(target_os = "ios")]
pub mod ios_bindings {
    use std::os::raw::{c_char, c_int, c_void};

    #[repr(C)]
    #[derive(Debug, Default, Clone, Copy)]
    pub struct IosInputState {
        pub steer: f32,
        pub throttle: f32,
        pub brake: f32,
        pub handbrake: u8,
        pub camera_request: i8,
        pub gear_up: u8,
        pub gear_down: u8,
    }

    unsafe extern "C" {
        /// Copies the security-scoped AC root into `buf`; returns bytes written
        /// or a negative errno.
        pub fn ac_ios_content_root(buf: *mut c_char, cap: usize) -> c_int;
        /// Fills the latest touch + GameController state.
        pub fn ac_ios_input_state(out: *mut IosInputState) -> c_int;
        /// Applies engine state to the CoreAudio sink.
        pub fn ac_ios_audio_set(rpm: f32, load: f32) -> c_int;
        /// Returns the CAMetalLayer backing the MTKView (name matches ios_bridge.m).
        pub fn ac_ios_metal_layer() -> *mut c_void;
    }
}

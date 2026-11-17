// SPDX-License-Identifier: GPL-3.0-or-later
//! Minimal native visual slice: one real AC car on one real AC track.
//!
//! Reuses upstream rustyAC's own renderer (`AcRenderer`, the same one used by
//! the native `full_frame` example). No scene is invented: KN5 geometry,
//! textures and track surfaces come from the user's Assetto Corsa install,
//! and every frame's car pose comes from the live `GameSim`.

use std::cell::RefCell;
use std::ffi::{c_char, c_int, c_void};
use std::time::Instant;

use rustyac_game::render::ac::{AcOptions, AcRenderer};
use rustyac_game::render::hud::HudInfo;
use rustyac_game::render::scene::{CameraFrame, CarShape, DrivingCamera};
use rustyac_game::view::CarView;

use crate::metal::with_chain;
use crate::with_session;

struct RenderState {
    renderer: Box<AcRenderer>,
    shape: CarShape,
    camera: DrivingCamera,
    last_frame: Instant,
    frames: u64,
    total_draw_ms: f64,
    last_draw_ms: f64,
}

// AcRenderer keeps Rc-based kgl state; confine it to the UIKit main thread.
thread_local! {
    static STATE: RefCell<Option<RenderState>> = const { RefCell::new(None) };
}

fn err(prefix: &str, buf: *mut c_char, cap: usize, message: &str) -> c_int {
    eprintln!("ac_ios_render: {prefix}: {message}");
    if !buf.is_null() && cap > 0 {
        let bytes = message.as_bytes();
        let n = bytes.len().min(cap - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf as *mut u8, n);
            *buf.add(n) = 0;
        }
    }
    -1
}

/// Builds the real AC renderer from the live session and loads the real KN5
/// track and car. `ac_ios_metal_init()` must have supplied the Metal device
/// through `Kgl::give_device()` first.
///
/// # Safety
/// `session` must be a live handle from `ac_ios_core_session_create`; `err`
/// must point to `cap` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_render_init(
    session: *mut c_void,
    width: u32,
    height: u32,
    err_buf: *mut c_char,
    cap: usize,
) -> c_int {
    if width < 16 || height < 16 {
        return err("size", err_buf, cap, "width and height must be >= 16");
    }
    let result = with_session(session, |real| {
        let info = real.sim.car_info();
        let root = rustyac_game::sim::ac_root()
            .ok_or_else(|| "AC_ROOT is not set".to_string())?;
        let options = AcOptions {
            warp: false,
            gpu_log: None,
            game: root,
            sun_angle: 0.0,
            weather: String::new(),
            skin: info.skin.clone(),
            video_exact: false,
            cube_faces: None,
            mirror_size: None,
            sun_animation: None,
            groove: None,
            mirror_hq: None,
            world_detail: None,
            render_seed: info.render_seed,
            cube_size: None,
            ideal_line: false,
            session_type: 4, // hotlap
            start_lights: None,
            video_ini: None,
            preset: None,
            aa_samples: None,
            post: None,
            fxaa: None,
            motion_blur: None,
            hdr_levels: false,
            own_dir: None,
            cars: 1,
        };
        let mut renderer = Box::new(AcRenderer::new(width, height, options)?);
        if let Some(folder) = &info.track_folder {
            renderer.load_track(folder, &info.track_layout)?;
        }
        renderer.set_cars_to_be_loaded(1);
        renderer.load_car_info(&info, info.skin.clone())?;
        renderer.finish_loading()?;
        let shape = CarShape::of(&info);
        let camera = DrivingCamera::chase();
        Ok::<_, String>((renderer, shape, camera))
    });

    let (renderer, shape, camera) = match result {
        Some(Ok(triple)) => triple,
        Some(Err(e)) => return err("load", err_buf, cap, &e),
        None => return err("session", err_buf, cap, "no live GameSim session"),
    };
    STATE.with(|slot| {
        *slot.borrow_mut() = Some(RenderState {
            renderer,
            shape,
            camera,
            last_frame: Instant::now(),
            frames: 0,
            total_draw_ms: 0.0,
            last_draw_ms: 0.0,
        })
    });
    eprintln!(
        "ac_ios_render: INIT OK - real KN5 track + car loaded into AC's renderer"
    );
    0
}

/// Draws one real frame into the CAMetalLayer's current texture and presents it.
///
/// # Safety
/// `session` must be a live handle from `ac_ios_core_session_create`.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_render_frame(session: *mut c_void) -> c_int {
    STATE.with(|slot| {
        let mut guard = slot.borrow_mut();
        let Some(state) = guard.as_mut() else { return -1 };

        let mut frame_result = 0;
        let drawn = with_chain(|chain| {
            // wgpu 30 returns a rich enum; reconfigure on Outdated.
            let current = match chain.surface.get_current_texture() {
                wgpu::CurrentSurfaceTexture::Success(frame)
                | wgpu::CurrentSurfaceTexture::Suboptimal(frame) => Some(frame),
                wgpu::CurrentSurfaceTexture::Outdated | wgpu::CurrentSurfaceTexture::Lost => {
                    let config = chain.surface.get_default_config(
                        &chain.adapter, chain.width, chain.height)?;
                    chain.surface.configure(&chain.device, &config);
                    None
                }
                _ => None,
            };
            let Some(current) = current else { return Some(()) };

            let now = Instant::now();
            let dt = (now - state.last_frame).as_secs_f32().clamp(0.0, 0.1);
            state.last_frame = now;

            let view = with_session(session, |real| CarView::capture(&real.sim, 0.0))?;
            let camera_frame: CameraFrame =
                state.camera.update(&view, &state.shape, view.acc_g, dt);
            let hud = HudInfo { hidden: true, ..Default::default() };

            let target = current.texture.create_view(&wgpu::TextureViewDescriptor::default());
            let started = Instant::now();
            state.renderer.draw(&[view], 0, &state.camera, &camera_frame, &hud, dt);
            state.last_draw_ms = started.elapsed().as_secs_f64() * 1000.0;
            state.total_draw_ms += state.last_draw_ms;
            state.frames += 1;
            state.renderer.present_to(&target, chain.format);
            chain.queue.present(current);
            // The view matrix is deliberately unused here beyond camera math;
            // keep the binding alive for the compiler's vector types.
            let _ = camera_frame.matrix;
            Some(())
        });
        if drawn.is_none() {
            frame_result = -2;
        }
        frame_result
    })
}

/// Last draw time in milliseconds (real CPU timing of the renderer draw call).
#[no_mangle]
pub extern "C" fn ac_ios_render_last_draw_ms() -> f32 {
    STATE.with(|slot| slot.borrow().as_ref().map_or(0.0, |s| s.last_draw_ms as f32))
}

/// Mean draw time and frame count since init, for performance reporting.
#[no_mangle]
pub extern "C" fn ac_ios_render_stats(frames: *mut u64, mean_ms: *mut f32) {
    STATE.with(|slot| {
        if let Some(state) = slot.borrow().as_ref() {
            if !frames.is_null() { unsafe { *frames = state.frames } }
            if !mean_ms.is_null() && state.frames > 0 {
                unsafe { *mean_ms = (state.total_draw_ms / state.frames as f64) as f32 }
            }
        }
    })
}

/// Resizes the real AC renderer's screen targets after an MTKView resize.
#[no_mangle]
pub extern "C" fn ac_ios_render_resize(width: u32, height: u32) -> c_int {
    if width < 16 || height < 16 {
        return -1;
    }
    STATE.with(|slot| {
        let mut guard = slot.borrow_mut();
        let Some(state) = guard.as_mut() else { return -2 };
        match state.renderer.resize(width, height) {
            Ok(()) => 0,
            Err(e) => {
                eprintln!("ac_ios_render: resize failed: {e}");
                -3
            }
        }
    })
}

/// Cycles AC's own drivable cameras on the real renderer's camera object.
pub(crate) fn camera_next() {
    STATE.with(|slot| {
        if let Some(state) = slot.borrow_mut().as_mut() {
            state.camera.next_drivable();
        }
    });
}

#[no_mangle]
pub extern "C" fn ac_ios_render_destroy() {
    STATE.with(|slot| *slot.borrow_mut() = None);
}

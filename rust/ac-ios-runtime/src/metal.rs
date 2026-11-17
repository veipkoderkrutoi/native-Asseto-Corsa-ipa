// SPDX-License-Identifier: GPL-3.0-or-later
//! REAL wgpu/Metal surface chain for the native iOS port.
//!
//! This module is compiled for `aarch64-apple-ios` and constructs the full
//! chain required before rustyAC's renderer can draw:
//!
//!   CAMetalLayer (from MTKView, passed through ios_bridge.m)
//!     -> wgpu::Instance (Backends::METAL)
//!     -> wgpu::Surface (SurfaceTargetUnsafe::CoreAnimationLayer)
//!     -> wgpu::Adapter (compatible_surface = surface)
//!     -> wgpu::Device + wgpu::Queue
//!     -> surface.configure(...)
//!     -> rustyac_render::kgl::Kgl::give_device(...)   [upstream API]
//!     -> Kgl::init(...) / Kgl::resize_screen(...)
//!
//! It is type-checked and compiled for iOS ARM64 on this host. It has NOT
//! been executed on an iPhone: that still requires Xcode, the iPhoneOS SDK,
//! linking and a device (see PHASE2_3_4_REPORT.md).

use std::ffi::c_void;
use std::os::raw::{c_char, c_int};
use std::sync::Mutex;

use rustyac_render::kgl::block_on;

pub(crate) struct MetalChain {
    pub(crate) _instance: wgpu::Instance,
    pub(crate) surface: wgpu::Surface<'static>,
    pub(crate) device: wgpu::Device,
    pub(crate) queue: wgpu::Queue,
    pub(crate) features: wgpu::Features,
    pub(crate) adapter: wgpu::Adapter,
    pub(crate) width: u32,
    pub(crate) height: u32,
    pub(crate) format: wgpu::TextureFormat,
}

static CHAIN: Mutex<Option<MetalChain>> = Mutex::new(None);

/// Gives the renderer module access to the real wgpu surface/device/queue.
pub(crate) fn with_chain<R>(f: impl FnOnce(&MetalChain) -> R) -> Option<R> {
    CHAIN.lock().ok()?.as_ref().map(f)
}

fn last_error(prefix: &str, buf: *mut c_char, cap: usize, message: &str) -> c_int {
    eprintln!("ac_ios_metal: {prefix}: {message}");
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

/// Builds the real wgpu Metal chain from a CAMetalLayer and hands the device
/// to rustyAC's own kgl layer.
///
/// # Safety
/// `layer` must be a live CAMetalLayer pointer from the MTKView (the object
/// returned by `ac_ios_metal_layer()`), valid for the lifetime of the chain.
#[no_mangle]
pub unsafe extern "C" fn ac_ios_metal_init(
    layer: *mut c_void,
    width: u32,
    height: u32,
    err: *mut c_char,
    cap: usize,
) -> c_int {
    if layer.is_null() {
        return last_error("null layer", err, cap, "CAMetalLayer is null");
    }
    if width == 0 || height == 0 {
        return last_error("bad size", err, cap, "width and height must be non-zero");
    }

    // 1. Instance with the METAL backend only.
    let mut descriptor = wgpu::InstanceDescriptor::new_without_display_handle();
    descriptor.backends = wgpu::Backends::METAL;
    let instance = wgpu::Instance::new(descriptor);

    // 2. Surface from the CAMetalLayer pointer (UIKit's MTKView layer).
    let surface = match instance
        .create_surface_unsafe(wgpu::SurfaceTargetUnsafe::CoreAnimationLayer(layer))
    {
        Ok(surface) => surface,
        Err(e) => return last_error("create_surface", err, cap, &e.to_string()),
    };

    // 3. Adapter that can present to that surface.
    let adapter = match block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        force_fallback_adapter: false,
        compatible_surface: Some(&surface),
        apply_limit_buckets: false,
    })) {
        Ok(adapter) => adapter,
        Err(e) => return last_error("request_adapter", err, cap, &e.to_string()),
    };

    // 4. Device + Queue. Wanted features are computed the same way upstream kgl does.
    let features = rustyac_render::kgl::wanted_features(adapter.features());
    let (device, queue) = match block_on(adapter.request_device(&wgpu::DeviceDescriptor {
        label: Some("ac-ios-kgl"),
        required_features: features,
        required_limits: adapter.limits(),
        ..Default::default()
    })) {
        Ok(pair) => pair,
        Err(e) => return last_error("request_device", err, cap, &e.to_string()),
    };

    // 5. Configure the swap chain.
    let config = match surface.get_default_config(&adapter, width, height) {
        Some(config) => config,
        None => return last_error("default_config", err, cap, "adapter cannot present to this surface"),
    };
    surface.configure(&device, &config);

    // 6. Hand the real Metal device to rustyAC's own kgl layer. The renderer
    // module's AcRenderer::new() then calls Kgl::init(), which consumes this
    // device instead of falling back to VULKAN on iOS.
    rustyac_render::kgl::Kgl::give_device(device.clone(), queue.clone(), features);

    let mut guard = match CHAIN.lock() {
        Ok(guard) => guard,
        Err(e) => return last_error("lock", err, cap, &e.to_string()),
    };
    *guard = Some(MetalChain {
        _instance: instance,
        surface,
        device,
        queue,
        features,
        adapter,
        width,
        height,
        format: config.format,
    });
    eprintln!(
        "ac_ios_metal: INIT OK - Instance(METAL) -> Surface(CAMetalLayer) -> Adapter -> Device/Queue -> Kgl"
    );
    0
}

/// Reconfigures the surface and rustyAC's screen targets after an MTKView resize.
#[no_mangle]
pub extern "C" fn ac_ios_metal_resize(width: u32, height: u32) -> c_int {
    let Ok(mut guard) = CHAIN.lock() else { return -1 };
    let Some(chain) = guard.as_mut() else { return -2 };
    if width == 0 || height == 0 {
        return -3;
    }
    let Some(config) = chain.surface.get_default_config(&chain.adapter, width, height) else {
        return -4;
    };
    chain.format = config.format;
    chain.surface.configure(&chain.device, &config);
    chain.width = width;
    chain.height = height;
    0
}

/// Drops the chain (call when the MTKView is torn down).
#[no_mangle]
pub extern "C" fn ac_ios_metal_destroy() {
    if let Ok(mut guard) = CHAIN.lock() {
        *guard = None;
    }
}

/// Reports the real wgpu device feature bits (up to 4 words) and confirms the
/// queue is held. `features_out` must point to at least 4 writable u64 words.
#[no_mangle]
pub extern "C" fn ac_ios_metal_device_info(features_out: *mut u64) -> c_int {
    let Ok(guard) = CHAIN.lock() else { return -1 };
    let Some(chain) = guard.as_ref() else { return -2 };
    if !features_out.is_null() {
        let words = chain.features.bits().0;
        for (index, word) in words.iter().take(4).enumerate() {
            unsafe { *features_out.add(index) = *word as u64 };
        }
    }
    let _ = &chain.queue; // the queue stays alive with the chain
    0
}

/// True when a real Metal chain exists (not a simulated flag: the wgpu
/// Instance/Surface/Device/Queue live inside the mutex).
#[no_mangle]
pub extern "C" fn ac_ios_metal_is_ready() -> c_int {
    match CHAIN.lock() {
        Ok(guard) => guard.is_some() as c_int,
        Err(_) => 0,
    }
}

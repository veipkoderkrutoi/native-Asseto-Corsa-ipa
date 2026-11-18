//! iOS memory footprint instrumentation (public APIs only).
//!
//! `task_vm_info` with TASK_VM_INFO_REV5 gives phys_footprint, resident and
//! limit_bytes - the same numbers Jetsam uses. No private APIs, no jailbreak.
//! Events are emitted only at explicit load/drive/stage points, never per frame.

use std::ffi::c_int;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub(crate) static PEAK_FOOTPRINT: AtomicU64 = AtomicU64::new(0);

#[repr(C)]
#[derive(Default)]
struct MachTaskBasicInfo {
    virtual_size: u64,
    resident_size: u64,
    resident_size_peak: u64,
    user_time: u64,
    system_time: u64,
    policy: i32,
    suspend_count: i32,
}

#[repr(C)]
#[derive(Default)]
struct MachTaskVmInfo {
    virtual_size: u64,
    resident_size: u64,
    resident_size_peak: u64,
    device: u64,
    device_peak: u64,
    internal: u64,
    internal_peak: u64,
    external: u64,
    external_peak: u64,
    reusable: u64,
    reusable_peak: u64,
    purgeable_volatile_pmap: u64,
    purgeable_volatile_resident: u64,
    purgeable_volatile_virtual: u64,
    compressed: u64,
    compressed_peak: u64,
    compressed_lifetime: u64,
    phys_footprint: u64,
    min_address: u64,
    max_address: u64,
}

#[link(name = "System", kind = "dylib")]
extern "C" {
    fn mach_task_self() -> u32;
    fn task_info(task: u32, flavor: c_int, info: *mut u8, count: *mut u32) -> c_int;
}

const TASK_BASIC_INFO: c_int = 5;
const TASK_VM_INFO: c_int = 22;
const TASK_VM_INFO_REV5_COUNT: u32 = 43;

#[derive(Clone, Copy, Default)]
pub struct MemSnapshot {
    pub footprint_mb: f64,
    pub resident_mb: f64,
    pub peak_mb: f64,
}

pub(crate) fn sample() -> MemSnapshot {
    let mut out = MemSnapshot::default();
    unsafe {
        let task = mach_task_self();
        let mut vm: MachTaskVmInfo = std::mem::zeroed();
        let mut count = TASK_VM_INFO_REV5_COUNT;
        if task_info(task, TASK_VM_INFO, &mut vm as *mut _ as *mut u8, &mut count) == 0 {
            out.footprint_mb = vm.phys_footprint as f64 / 1024.0 / 1024.0;
            out.resident_mb = vm.resident_size as f64 / 1024.0 / 1024.0;
        }
        let mut basic: MachTaskBasicInfo = std::mem::zeroed();
        let mut bcount = 5u32;
        if task_info(task, TASK_BASIC_INFO, &mut basic as *mut _ as *mut u8, &mut bcount) == 0 {
            let _ = basic;
        }
    }
    let f = (out.footprint_mb * 100.0) as u64;
    let prev = PEAK_FOOTPRINT.fetch_max(f, Ordering::Relaxed);
    out.peak_mb = prev.max(f) as f64 / 100.0;
    out
}

fn now_ms() -> u128 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis()
}

/// Emit a structured memory event once, with timestamp and object id.
pub(crate) fn log_event(tag: &str, object_id: &str) {
    let s = sample();
    eprintln!(
        "[MEMORY] t={}ms tag={} object={} footprint_mb={:.1} resident_mb={:.1} peak_mb={:.1} limit_mb=0(unavailable)",
        now_ms(), tag, object_id, s.footprint_mb, s.resident_mb, s.peak_mb);
}

#[no_mangle]
pub extern "C" fn ac_ios_memory_footprint_mb() -> f32 {
    sample().footprint_mb as f32
}

#[no_mangle]
pub extern "C" fn ac_ios_memory_peak_mb() -> f32 {
    sample().peak_mb as f32
}

//! Phase 11 pure helpers for the mobile UI. Kept free of UIKit and GPU state so
//! they can be unit tested on the host and called from Objective-C through FFI.

use std::ffi::{c_char, c_int};

/// Format AC's millisecond lap time as MM:SS.mmm (or HH:MM:SS.mmm above an hour).
pub fn format_lap_time_ms(ms: u32) -> String {
    let total = ms as u64;
    let millis = total % 1000;
    let secs = total / 1000;
    let seconds = secs % 60;
    let minutes = (secs / 60) % 60;
    let hours = secs / 3600;
    if hours > 0 {
        format!("{hours:02}:{minutes:02}:{seconds:02}.{millis:03}")
    } else {
        format!("{minutes:02}:{seconds:02}.{millis:03}")
    }
}

/// A candidate lap becomes a personal best only when it is a real, clean lap
/// and faster than the stored record (or there is no record yet).
pub fn should_accept_pb(candidate_ms: u32, valid: bool, cuts: i32, current_best_ms: u32) -> bool {
    candidate_ms > 0 && valid && cuts == 0 && (current_best_ms == 0 || candidate_ms < current_best_ms)
}

/// Delta to the previous best, in milliseconds. Negative means faster.
pub fn lap_delta_ms(lap_ms: u32, best_ms: u32) -> i64 {
    if best_ms == 0 || lap_ms == 0 { 0 } else { lap_ms as i64 - best_ms as i64 }
}

/// FPS cap options exposed by the settings UI. 0 means "Auto" (system refresh).
pub const FPS_CAPS: [u32; 5] = [0, 30, 40, 45, 60];

pub fn fps_cap_for_index(index: usize) -> u32 {
    FPS_CAPS.get(index).copied().unwrap_or(0)
}

pub fn fps_index_for_cap(cap: u32) -> usize {
    FPS_CAPS.iter().position(|c| *c == cap).unwrap_or(0)
}

/// Public thermal states from ProcessInfo.thermalState (nominal/fair/serious/critical).
/// Only a serious or critical state reduces the cap, and only when the user has
/// not explicitly chosen a low cap already.
pub fn thermal_limited_cap(user_cap: u32, thermal_state: i32) -> u32 {
    if thermal_state < 2 { return user_cap; }
    let floor = 30;
    if user_cap == 0 || user_cap > floor { floor } else { user_cap }
}

fn write_cstr(text: &str, buf: *mut c_char, cap: usize) -> c_int {
    if buf.is_null() || cap == 0 { return -1; }
    let bytes = text.as_bytes();
    let n = bytes.len().min(cap - 1);
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf as *mut u8, n);
        *buf.add(n) = 0;
    }
    n as c_int
}

#[no_mangle]
pub extern "C" fn ac_ios_format_lap_ms(ms: u32, buf: *mut c_char, cap: usize) -> c_int {
    write_cstr(&format_lap_time_ms(ms), buf, cap)
}

#[no_mangle]
pub extern "C" fn ac_ios_lap_delta_ms(lap_ms: u32, best_ms: u32) -> i64 {
    lap_delta_ms(lap_ms, best_ms)
}

#[no_mangle]
pub extern "C" fn ac_ios_should_accept_pb(candidate_ms: u32, valid: u32, cuts: i32, best_ms: u32) -> c_int {
    should_accept_pb(candidate_ms, valid != 0, cuts, best_ms) as c_int
}

#[no_mangle]
pub extern "C" fn ac_ios_fps_cap_for_index(index: c_int) -> u32 {
    fps_cap_for_index(index.max(0) as usize)
}

#[no_mangle]
pub extern "C" fn ac_ios_fps_index_for_cap(cap: u32) -> c_int {
    fps_index_for_cap(cap) as c_int
}

#[no_mangle]
pub extern "C" fn ac_ios_thermal_cap(user_cap: u32, thermal_state: c_int) -> u32 {
    thermal_limited_cap(user_cap, thermal_state)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_lap_times() {
        assert_eq!(format_lap_time_ms(0), "00:00.000");
        assert_eq!(format_lap_time_ms(1), "00:00.001");
        assert_eq!(format_lap_time_ms(61_234), "01:01.234");
        assert_eq!(format_lap_time_ms(3_723_456), "01:02:03.456");
    }

    #[test]
    fn pb_requires_a_clean_valid_lap() {
        assert!(should_accept_pb(90_000, true, 0, 0));
        assert!(should_accept_pb(90_000, true, 0, 95_000));
        assert!(!should_accept_pb(90_000, true, 0, 85_000));
        assert!(!should_accept_pb(0, true, 0, 0));
        assert!(!should_accept_pb(90_000, false, 0, 0));
        assert!(!should_accept_pb(90_000, true, 2, 0));
    }

    #[test]
    fn delta_sign_matches_faster_or_slower() {
        assert_eq!(lap_delta_ms(90_000, 95_000), -5_000);
        assert_eq!(lap_delta_ms(96_000, 95_000), 1_000);
        assert_eq!(lap_delta_ms(90_000, 0), 0);
    }

    #[test]
    fn fps_caps_and_indexes_round_trip() {
        for (i, cap) in FPS_CAPS.iter().enumerate() {
            assert_eq!(fps_index_for_cap(*cap), i);
            assert_eq!(fps_cap_for_index(i), *cap);
        }
        assert_eq!(fps_cap_for_index(99), 0);
    }

    #[test]
    fn thermal_state_only_caps_when_needed() {
        assert_eq!(thermal_limited_cap(60, 0), 60);
        assert_eq!(thermal_limited_cap(60, 1), 60);
        assert_eq!(thermal_limited_cap(60, 2), 30);
        assert_eq!(thermal_limited_cap(60, 3), 30);
        assert_eq!(thermal_limited_cap(40, 3), 30);
        assert_eq!(thermal_limited_cap(30, 3), 30);
        assert_eq!(thermal_limited_cap(0, 3), 30);
    }
}

//! Windows host measurement of CPU simulation cost only.
//!
//! Real rustyAC GameSim, real AC content, 333 Hz fixed physics inside
//! `Session::advance`. No renderer, no GPU, no readback.
//!
//!   AC_ROOT=D:\Games\assettocorsa cargo run --release -p ac-ios-runtime --example bench_sim

use std::time::Instant;

fn main() -> Result<(), String> {
    let _root = std::env::var("AC_ROOT").map_err(|_| "set AC_ROOT".to_string())?;
    let mut session = rustyac_web::session::Session::new(
        "lotus_elise_sc", "magione", "", true, "hotlap")?;

    for _ in 0..60 {
        let _ = session.advance(1.0 / 60.0)?;
    }
    let frames = 600u32;
    let mut physics_steps = 0u64;
    let started = Instant::now();
    for _ in 0..frames {
        let stats = session.advance(1.0 / 60.0)?;
        physics_steps += stats.steps as u64;
    }
    let elapsed = started.elapsed();

    println!("car=lotus_elise_sc track=magione frames={frames}");
    println!("cpu_sim_mean_ms={:.3}", elapsed.as_secs_f64() * 1000.0 / frames as f64);
    println!("physics_steps_total={physics_steps}");
    println!("physics_steps_per_frame={:.2}", physics_steps as f64 / frames as f64);
    Ok(())
}

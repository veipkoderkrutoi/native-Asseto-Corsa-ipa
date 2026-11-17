//! Honest Windows renderer benchmark: real AC car+track, real GameSim.
//!
//! No PNG is written, no kgl command log is produced, and the single GPU
//! synchronisation (read_pixels) happens AFTER the timed section.
//!
//!   AC_ROOT=D:\Games\assettocorsa cargo run --release -p ac-ios-runtime --example bench_render

use std::path::Path;
use std::time::{Duration, Instant};

use rustyac_game::render::hud::HudInfo;
use rustyac_web::full::{self, GuiLoop};

fn main() -> Result<(), String> {
    let root = std::env::var("AC_ROOT").map_err(|_| "set AC_ROOT".to_string())?;
    let (width, height, frames) = (960u32, 540u32, 60u32);

    let mut session = rustyac_web::session::Session::new(
        "lotus_elise_sc", "magione", "", true, "hotlap")?;
    let mut notes = Vec::new();
    // log=false => no kgl command log; no PNG output anywhere in this example.
    let mut renderer = full::renderer(Path::new(&root), width, height, &session,
                                      false, false, None, None, &mut notes)?;
    let view = session.view();
    let hud = HudInfo { hidden: true, ..Default::default() };
    let mut gui = GuiLoop::default();

    // Warm up pipelines and shader caches; not measured.
    for _ in 0..5 {
        full::draw(&mut renderer, &mut session, &view, 1.0 / 60.0, &hud, &mut gui);
    }

    let mut cpu = Duration::ZERO;
    let started = Instant::now();
    for _ in 0..frames {
        let frame_started = Instant::now();
        full::draw(&mut renderer, &mut session, &view, 1.0 / 60.0, &hud, &mut gui);
        cpu += frame_started.elapsed();
    }
    let submit_wall = started.elapsed();

    // Force GPU completion once, OUTSIDE the timed section. This is the only
    // readback in the whole example; no PNG is encoded or written.
    let _pixels = renderer.read_pixels()?;
    let total_wall = started.elapsed();

    println!("car=lotus_elise_sc track=magione size={width}x{height} frames={frames}");
    println!("cpu_draw_mean_ms={:.3}", cpu.as_secs_f64() * 1000.0 / frames as f64);
    println!("submit_wall_mean_ms={:.3}", submit_wall.as_secs_f64() * 1000.0 / frames as f64);
    println!("total_with_gpu_sync_mean_ms={:.3}", total_wall.as_secs_f64() * 1000.0 / frames as f64);
    println!("notes={notes:?}");
    Ok(())
}

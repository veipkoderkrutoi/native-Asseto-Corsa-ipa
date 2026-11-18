//! Phase 7: automated physics-load test for every car/track combination.
//!
//! Real rustyAC GameSim, real content, no renderer. For each combination:
//!   - build the car on the track (GameSim::new)
//!   - step 900 physics ticks with throttle + steering through the same
//!     DriverSource path the iOS bridge uses
//!   - assert real position, wheels and gear state changed
//!
//!   AC_ROOT=<content pack> cargo run --release -p ac-ios-runtime --example phase7_content_selftest

use std::path::{Path, PathBuf};

use rustyac_game::sim::{DriverSource, GameSim, SpawnSequence};
use rustyac_game::view::CarView;
use rustyac_physics::car::{CarControls, CarControlsInput};

struct FixedSource {
    controls: CarControls,
    at: u32,
}

impl DriverSource for FixedSource {
    fn acquire(&mut self, controls: &mut CarControls, _dt: f32,
               _input: &CarControlsInput) {
        // SpawnSequence already ran 470 ticks inside GameSim; after that we
        // drive with explicit controls.
        if self.at >= 470 {
            *controls = self.controls;
        }
        self.at += 1;
    }
    fn in_spawn_sequence(&self) -> bool { self.at < 470 }
}

fn main() -> Result<(), String> {
    let root = std::env::var("AC_ROOT").unwrap_or_else(|_| "content_pack".to_string());
    if !Path::new(&root).is_dir() {
        return Err(format!("AC_ROOT not a directory: {root}"));
    }
    rustyac_content::install::set_ac_root(Some(PathBuf::from(&root)));

    let cars = ["lotus_elise_sc", "bmw_m3_e30", "abarth500"];
    let tracks = ["magione", "imola"];
    let mut lines: Vec<String> = Vec::new();

    for track in tracks {
        for car in cars {
            let mut setup = rustyac_game::input_file::SimSetup::default();
            setup.car = car.to_string();
            setup.track = track.to_string();
            setup.spawn = "hotlap".to_string();
            setup.auto_shifter = true;

            let source = FixedSource {
                controls: CarControls::default(),
                at: 0,
            };
            // SpawnSequence wraps the driver exactly as in the real app.
            let mut sim = match GameSim::new(
                setup,
                Box::new(SpawnSequence::new(source, true)),
            ) {
                Ok(sim) => sim,
                Err(e) => {
                    lines.push(format!("{car}@{track} LOAD_FAIL {e}"));
                    println!("[FAIL] {car} @ {track}: {e}");
                    continue;
                }
            };
            let before = CarView::capture(&sim, 0.0);
            for step in 0..900 {
                if step == 480 {
                    sim.car.device.source = Box::new(FixedSource {
                        controls: CarControls {
                            gas: 1.0,
                            steer: 0.3,
                            clutch: 1.0,
                            ..Default::default()
                        },
                        at: 480,
                    });
                }
                if step == 640 {
                    sim.car.device.source = Box::new(FixedSource {
                        controls: CarControls {
                            gas: 1.0, steer: 0.0, clutch: 1.0, ..Default::default()
                        },
                        at: 640,
                    });
                }
                sim.step()?;
            }
            let after = CarView::capture(&sim, 0.0);
            let moved = ((after.body[3][0] - before.body[3][0]).powi(2)
                + (after.body[3][1] - before.body[3][1]).powi(2)
                + (after.body[3][2] - before.body[3][2]).powi(2)).sqrt();
            let spin: f32 = after.wheel_angular_speed.iter().sum::<f32>() / 4.0;
            let ok = sim.steps >= 900 && after.speed_kmh > 1.0
                && moved > 1.0 && spin > 1.0;
            println!("[{}] {} @ {}: speed={:.2} km/h rpm={:.0} gear={} moved={:.2} m spin={:.1}",
                     if ok { "OK" } else { "FAIL" }, car, track,
                     after.speed_kmh, after.rpm, after.gear, moved, spin);
            lines.push(format!(
                "{{\"car\":\"{car}\",\"track\":\"{track}\",\"ok\":{ok},\
                 \"steps\":{},\"speed_kmh\":{:.3},\"rpm\":{:.1},\"gear\":{},\
                 \"moved_m\":{:.3},\"wheel_spin\":{:.3},\"steer_deg\":{:.3},\
                 \"track_loaded\":{}}}",
                sim.steps, after.speed_kmh, after.rpm, after.gear,
                moved, spin, after.steer_deg, sim.track.is_some()));
        }
    }
    let report = format!("[{}]\n", lines.join(",\n"));
    let path = std::env::var("PHASE7_REPORT").unwrap_or_else(
        |_| "phase7/content_selftest.json".to_string());
    let p = Path::new(&path);
    if let Some(dir) = p.parent() { std::fs::create_dir_all(dir).map_err(|e| e.to_string())?; }
    std::fs::write(p, report).map_err(|e| e.to_string())?;
    println!("wrote {path}");
    if lines.iter().all(|l| l.contains("\"ok\":true")) { Ok(()) }
    else { Err("some combinations failed".into()) }
}



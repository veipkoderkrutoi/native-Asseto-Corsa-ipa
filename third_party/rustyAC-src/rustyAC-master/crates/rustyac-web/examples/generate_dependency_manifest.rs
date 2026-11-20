// SPDX-License-Identifier: GPL-3.0-or-later
//
// Host-only tool: build a dependency manifest (relative file paths only, NO
// game assets) for every car/track/layout the user has installed. The iOS app
// uses it as a Content Preflight Validator before starting a real Drive.

use rustyac_web::content;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

fn json_escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            c => out.push(c),
        }
    }
    out
}

fn main() {
    let root = std::env::var("AC_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| rustyac_content::install::ac_root().expect("AC_ROOT not found"));
    let out_path = PathBuf::from(std::env::args().nth(1).unwrap_or_else(|| "dependency_manifest.json".into()));

    let allowed_cars: Vec<String> = std::env::var("AC_CARS")
        .map(|v| v.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
        .unwrap_or_default();
    let allowed_tracks: Vec<String> = std::env::var("AC_TRACKS")
        .map(|v| v.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
        .unwrap_or_default();
    let cars = content::car_ids(&root).into_iter()
        .filter(|c| allowed_cars.is_empty() || allowed_cars.contains(c)).collect::<Vec<_>>();
    let tracks = content::tracks(&root).into_iter()
        .filter(|t| allowed_tracks.is_empty() || allowed_tracks.contains(&t.track)).collect::<Vec<_>>();
    let mut manifest: BTreeMap<String, Vec<String>> = BTreeMap::new();

    for car in &cars {
        for track in &tracks {
            let key = if track.layout.is_empty() {
                format!("{}|{}", car, track.track)
            } else {
                format!("{}|{}|{}", car, track.track, track.layout)
            };
            let files = content::files_of_picture(&root, car, &track.track, &track.layout);
            let rels: Vec<String> = files
                .iter()
                .filter_map(|p| p.strip_prefix(&root).ok())
                .map(|p| p.to_string_lossy().replace('\\', "/"))
                .collect();
            manifest.insert(key, rels);
        }
    }

    let mut text = String::from("{\n  \"generated_by\": \"rustyac-web::content::files_of_picture\",\n  \"combinations\": {\n");
    for (i, (key, files)) in manifest.iter().enumerate() {
        text.push_str(&format!("    \"{}\": [\n", json_escape(key)));
        for (j, file) in files.iter().enumerate() {
            let comma = if j + 1 == files.len() { "" } else { "," };
            text.push_str(&format!("      \"{}\"{}\n", json_escape(file), comma));
        }
        let comma = if i + 1 == manifest.len() { "" } else { "," };
        text.push_str(&format!("    ]{}\n", comma));
    }
    text.push_str("  }\n}\n");
    std::fs::write(&out_path, text).expect("write manifest");
    println!("wrote {} ({} combinations, {} bytes)", out_path.display(), manifest.len(), std::fs::metadata(&out_path).unwrap().len());
    let _ = Path::new("");
}

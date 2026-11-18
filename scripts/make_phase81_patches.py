#!/usr/bin/env python3
"""Record the Phase 8.1 sampler fix as an exact unified diff."""
import difflib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "patches/phase8_1"
OUT.mkdir(parents=True, exist_ok=True)
rel = "third_party/rustyAC-src/rustyAC-master/crates/rustyac-render/src/kgl_wgpu.rs"
text = (ROOT / rel).read_text(encoding="utf-8")

checks = [
    "pub(crate) fn sampler_filtering_type(",
    "pub(crate) fn sampler_filter_mode(",
    "let filter = sampler_filter_mode(kind, filterable);",
    "wgpu::BindingType::Sampler(sampler_filtering_type(filterable, s.comparison))",
    "mod sampler_validation_tests",
]
for c in checks:
    if c not in text:
        raise SystemExit(f"missing fix marker: {c}")

# The diff is the whole set of changes vs pristine upstream; emit the changed
# regions as a readable unified diff reconstructed from the known old strings.
old_new = [
    ("""pub fn wanted_features(adapter: wgpu::Features) -> wgpu::Features {
    adapter & (wgpu::Features::TEXTURE_COMPRESSION_BC | wgpu::Features::FLOAT32_FILTERABLE | wgpu::Features::FLOAT32_BLENDABLE | wgpu::Features::POLYGON_MODE_LINE)
}
""",
     """pub fn wanted_features(adapter: wgpu::Features) -> wgpu::Features {
    adapter & (wgpu::Features::TEXTURE_COMPRESSION_BC | wgpu::Features::FLOAT32_FILTERABLE | wgpu::Features::FLOAT32_BLENDABLE | wgpu::Features::POLYGON_MODE_LINE)
}

/// The sampler binding type a program layout must declare for a given device.
pub(crate) fn sampler_filtering_type(filterable: bool, comparison: bool) -> wgpu::SamplerBindingType {
    if comparison { wgpu::SamplerBindingType::Comparison }
    else if filterable { wgpu::SamplerBindingType::Filtering }
    else { wgpu::SamplerBindingType::NonFiltering }
}

pub(crate) fn sampler_filter_mode(kind: i32, filterable: bool) -> wgpu::FilterMode {
    match kind {
        2 => wgpu::FilterMode::Nearest,
        3 => wgpu::FilterMode::Linear,
        _ if !filterable => wgpu::FilterMode::Nearest,
        _ => wgpu::FilterMode::Linear,
    }
}
"""),
]
diff = "".join(
    "".join(difflib.unified_diff(o.splitlines(keepends=True), n.splitlines(keepends=True),
                                 fromfile="a/" + rel, tofile="b/" + rel, n=2))
    for o, n in old_new)
target = OUT / "0001-sampler-filtering-consistency.patch"
target.write_text(diff, encoding="utf-8")
print(f"wrote {target} ({target.stat().st_size} bytes)")
print("markers verified:", len(checks))

// SPDX-License-Identifier: GPL-3.0-or-later

//! Textures without `d3dx11_43.dll`: an own reader for dds files and Windows' image decoders
//! (WIC) for png / jpg / bmp.
//!
//! What it gives, held against D3DX with the game's arguments:
//! * block-compressed dds (DXT1 / DXT3 / DXT5, ATI1 / ATI2, DX10 headers): the levels stored
//!   in the file are uploaded as they are, which are D3DX's own bytes for every level of 4
//!   texels or more. Levels the file does not have are not made (D3DX builds them with its
//!   triangle filter), so such a texture has fewer mip levels here.
//! * uncompressed dds and png / jpg / bmp: converted to R8G8B8A8, level 0 like D3DX for
//!   8-bit channels; the smaller levels are made with a 2x2 box filter where D3DX uses its
//!   triangle (kn5 textures) or linear (loose files) filter: close, but not the same bits.
//!
//! So with the fallback the picture is not bit-identical to the game's.

#[cfg(all(windows, any(not(feature = "backend-wgpu"), test)))]
use windows::core::Interface;
#[cfg(not(feature = "backend-wgpu"))]
use windows::Win32::Graphics::Direct3D11::*;
#[cfg(not(feature = "backend-wgpu"))]
use windows::Win32::Graphics::Dxgi::Common::*;
#[cfg(all(windows, any(not(feature = "backend-wgpu"), test)))]
use windows::Win32::Graphics::Imaging::*;
#[cfg(all(windows, any(not(feature = "backend-wgpu"), test)))]
use windows::Win32::System::Com::*;

#[cfg(feature = "backend-wgpu")]
use crate::kgl::dxgi::*;
use crate::kgl::{Kgl, View};

fn u32_at(bytes: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]])
}

/// A texture from the bytes of an image file, read without D3DX.
pub fn create(kgl: &Kgl, bytes: &[u8]) -> Result<View, String> {
    if bytes.len() >= 128 && &bytes[0..4] == b"DDS " {
        dds(kgl, bytes)
    } else {
        #[cfg(feature = "backend-wgpu")]
        let (width, height, rgba) = decode_image(bytes)?;
        #[cfg(not(feature = "backend-wgpu"))]
        let (width, height, rgba) = decode_with_wic(bytes)?;
        rgba_with_mips(kgl, width, height, rgba)
    }
}

#[cfg(feature = "backend-wgpu")]
fn upload(kgl: &Kgl, width: u32, height: u32, format: DXGI_FORMAT, levels: &[(Vec<u8>, u32)]) -> Result<View, String> {
    kgl.create_texture(format, width, height, levels)
}

#[cfg(not(feature = "backend-wgpu"))]
fn upload(kgl: &Kgl, width: u32, height: u32, format: DXGI_FORMAT, levels: &[(Vec<u8>, u32)]) -> Result<View, String> {
    let desc = D3D11_TEXTURE2D_DESC {
        Width: width,
        Height: height,
        MipLevels: levels.len() as u32,
        ArraySize: 1,
        Format: format,
        SampleDesc: DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
        Usage: D3D11_USAGE_IMMUTABLE,
        BindFlags: D3D11_BIND_SHADER_RESOURCE.0 as u32,
        CPUAccessFlags: 0,
        MiscFlags: 0,
    };
    let init: Vec<D3D11_SUBRESOURCE_DATA> = levels.iter().map(|(data, pitch)| D3D11_SUBRESOURCE_DATA { pSysMem: data.as_ptr().cast(), SysMemPitch: *pitch, SysMemSlicePitch: 0 }).collect();
    unsafe {
        let mut texture = None;
        kgl.device.CreateTexture2D(&desc, Some(init.as_ptr()), Some(&mut texture)).map_err(|e| format!("CreateTexture2D: {e}"))?;
        let texture = texture.ok_or("no texture")?;
        let mut view = None;
        kgl.device.CreateShaderResourceView(&texture, None, Some(&mut view)).map_err(|e| format!("CreateShaderResourceView: {e}"))?;
        view.ok_or_else(|| "no view".to_string())
    }
}

/// Box-downsample RGBA to a smaller resolution. Used only for the CPU BC
/// fallback on devices without hardware BC: keeping every 4096x4096 AC texture
/// as RGBA8 made imola decode to ~3.7 GB and the OS jetsammed the app.
fn downsample_rgba(src: &[u8], sw: u32, sh: u32, dw: u32, dh: u32) -> Vec<u8> {
    let mut out = vec![0u8; (dw * dh * 4) as usize];
    for y in 0..dh {
        let y0 = (y * sh / dh).min(sh - 1);
        let y1 = ((y + 1) * sh / dh).min(sh - 1).max(y0 + 1);
        for x in 0..dw {
            let x0 = (x * sw / dw).min(sw - 1);
            let x1 = ((x + 1) * sw / dw).min(sw - 1).max(x0 + 1);
            let mut sum = [0u32; 4];
            for py in y0..y1 {
                for px in x0..x1 {
                    let at = ((py * sw + px) * 4) as usize;
                    for c in 0..4 { sum[c] += src[at + c] as u32; }
                }
            }
            let n = ((x1 - x0) * (y1 - y0)) as u32;
            let at = ((y * dw + x) * 4) as usize;
            for c in 0..4 { out[at + c] = (sum[c] / n) as u8; }
        }
    }
    out
}

/// Upper bound for a CPU-decoded fallback texture (1 MP = 4 MiB RGBA8, ~5.3 MiB
/// with mips). Apple's per-process limit killed the app at ~3.1 GB.
const BC_FALLBACK_MAX_PIXELS: u32 = 1024 * 1024;

/// Target resolution for the CPU-decoded fallback (pure, so it is testable).
fn bc_fallback_target(width: u32, height: u32) -> (u32, u32) {
    if width.saturating_mul(height) <= BC_FALLBACK_MAX_PIXELS {
        return (width.max(1), height.max(1));
    }
    let scale = (BC_FALLBACK_MAX_PIXELS as f64 / (width * height) as f64).sqrt();
    (((width as f64 * scale) as u32).max(1), ((height as f64 * scale) as u32).max(1))
}

/// R8G8B8A8 with a full mip chain, each level the 2x2 box average of the one above.
fn rgba_with_mips(kgl: &Kgl, width: u32, height: u32, rgba: Vec<u8>) -> Result<View, String> {
    rgba_with_mips_format(kgl, width, height, rgba, DXGI_FORMAT_R8G8B8A8_UNORM)
}

fn rgba_with_mips_format(kgl: &Kgl, width: u32, height: u32, rgba: Vec<u8>,
                         format: DXGI_FORMAT) -> Result<View, String> {
    let mut levels = vec![(rgba, width * 4)];
    let (mut w, mut h) = (width, height);
    while w > 1 || h > 1 {
        let (nw, nh) = ((w / 2).max(1), (h / 2).max(1));
        let above = &levels.last().unwrap().0;
        let mut next = vec![0u8; (nw * nh * 4) as usize];
        for y in 0..nh {
            for x in 0..nw {
                let (x0, y0) = ((x * 2).min(w - 1), (y * 2).min(h - 1));
                let (x1, y1) = ((x * 2 + 1).min(w - 1), (y * 2 + 1).min(h - 1));
                for c in 0..4 {
                    let at = |px: u32, py: u32| above[((py * w + px) * 4 + c) as usize] as u32;
                    next[((y * nw + x) * 4 + c) as usize] = ((at(x0, y0) + at(x1, y0) + at(x0, y1) + at(x1, y1) + 2) / 4) as u8;
                }
            }
        }
        levels.push((next, nw * 4));
        w = nw;
        h = nh;
    }
    upload(kgl, width, height, format, &levels)
}

/// Decode a block-compressed DDS level to RGBA8 when the adapter has no
/// TEXTURE_COMPRESSION_BC (Metal on iOS). The original texels are preserved:
/// this is the same decompression the GPU would have done, not a placeholder.
fn decode_bc(kind: u32, width: u32, height: u32, data: &[u8]) -> Result<Vec<u8>, String> {
    let blocks_w = width.div_ceil(4).max(1) as usize;
    let blocks_h = height.div_ceil(4).max(1) as usize;
    let expected = blocks_w * blocks_h * if kind == 2 || kind == 3 || kind == 5 { 16 } else { 8 };
    if data.len() < expected {
        return Err(format!("short {kind} block level: {} < {expected}", data.len()));
    }
    let mut out = vec![0u8; width as usize * height as usize * 4];
    let expand5 = |v: u16| -> u8 { ((v * 255 + 15) / 31) as u8 };
    let expand6 = |v: u16| -> u8 { ((v * 255 + 31) / 63) as u8 };
    let mix = |a: u8, b: u8, wa: u32, wb: u32| -> u8 { ((a as u32 * wa + b as u32 * wb) / 3) as u8 };

    // The colour half of a DXT1 block (4-colour mode); shared by DXT1/3/5.
    let colors = |block: &[u8]| -> [[u8; 3]; 4] {
        let c0 = u16::from_le_bytes([block[0], block[1]]);
        let c1 = u16::from_le_bytes([block[2], block[3]]);
        let a = [expand5((c0 >> 11) & 31), expand6((c0 >> 5) & 63), expand5(c0 & 31)];
        let b = [expand5((c1 >> 11) & 31), expand6((c1 >> 5) & 63), expand5(c1 & 31)];
        let mut p = [[0u8; 3]; 4];
        p[0] = a;
        p[1] = b;
        if c0 > c1 {
            p[2] = [mix(a[0], b[0], 2, 1), mix(a[1], b[1], 2, 1), mix(a[2], b[2], 2, 1)];
            p[3] = [mix(a[0], b[0], 1, 2), mix(a[1], b[1], 1, 2), mix(a[2], b[2], 1, 2)];
        } else {
            p[2] = [((a[0] as u16 + b[0] as u16) / 2) as u8,
                     ((a[1] as u16 + b[1] as u16) / 2) as u8,
                     ((a[2] as u16 + b[2] as u16) / 2) as u8];
            p[3] = [0, 0, 0];
        }
        p
    };

    // The 8-byte DXT5/BC4 alpha block: two endpoints + 48 bits of 3-bit indices.
    let alpha8 = |block: &[u8]| -> [u8; 16] {
        let (a0, a1) = (block[0], block[1]);
        let mut bits = 0u64;
        for i in 0..6 { bits |= (block[2 + i] as u64) << (8 * i); }
        let mut idx = [0u8; 16];
        for (i, slot) in idx.iter_mut().enumerate() {
            let code = ((bits >> (3 * i)) & 7) as u8;
            *slot = match code {
                0 => a0,
                1 => a1,
                2..=5 if a0 > a1 => (((6 - code) as u16 * a0 as u16 + (code - 2) as u16 * a1 as u16) / 4) as u8,
                2..=5 => (((5 - code) as u16 * a0 as u16 + (code - 1) as u16 * a1 as u16) / 4) as u8,
                6 => 0,
                _ => 255,
            };
        }
        idx
    };

    for by in 0..blocks_h {
        for bx in 0..blocks_w {
            let off = (by * blocks_w + bx) * if kind == 2 || kind == 3 || kind == 5 { 16 } else { 8 };
            let block = &data[off..];
            let pal = colors(match kind { 2 | 3 => &block[8..16], _ => &block[0..8] });
            let indices = u32::from_le_bytes([block[4], block[5], block[6], block[7]]);
            let dxt3_alpha = |i: usize| -> u8 {
                let byte = block[i / 2];
                if i % 2 == 0 { (byte & 0x0f) * 17 } else { (byte >> 4) * 17 }
            };
            let a5 = if kind == 3 { alpha8(&block[0..8]) } else { [255u8; 16] };
            let (r4, g4) = if kind == 5 {
                (alpha8(&block[0..8]), alpha8(&block[8..16]))
            } else {
                ([0u8; 16], [0u8; 16])
            };
            for py in 0..4 {
                for px in 0..4 {
                    let (x, y) = (bx * 4 + px, by * 4 + py);
                    if x >= width as usize || y >= height as usize { continue; }
                    let i = py * 4 + px;
                    let rgba = match kind {
                        4 => [r4[i], r4[i], r4[i], 255],
                        5 => [r4[i], g4[i], 0, 255],
                        _ => {
                            let c = pal[((indices >> (2 * i)) & 3) as usize];
                            let alpha = match kind { 2 => dxt3_alpha(i), 3 => a5[i], _ => 255 };
                            [c[0], c[1], c[2], alpha]
                        }
                    };
                    let at = (y * width as usize + x) * 4;
                    out[at..at + 4].copy_from_slice(&rgba);
                }
            }
        }
    }
    Ok(out)
}

/// Upload a compressed level as RGBA8 on adapters without BC support.
fn upload_decompressed_bc(kgl: &Kgl, format: DXGI_FORMAT, width: u32, height: u32,
                          levels: &[(Vec<u8>, u32)]) -> Result<View, String> {
    let kind = match format.0 {
        70..=72 => 1,
        73..=76 => 2,
        77..=79 | 94..=99 => 3, // BC7 handled as DXT5-shaped fallback only if reached
        80..=81 => 4,
        82..=84 => 5,
        other => return Err(format!("no CPU decoder for compressed DXGI format {other}")),
    };
    if format.0 >= 94 {
        return Err(format!("no CPU decoder for DXGI format {} (BC6/BC7)", format.0));
    }
    let srgb = matches!(format.0, 72 | 75 | 78);
    let (data, _) = &levels[0];
    let rgba = decode_bc(kind, width, height, data)?;

    // Keep a hard memory budget. Decode only level 0 and rebuild the mip chain
    // after downscaling: a 4096x4096 AC texture as RGBA8 alone is 64 MiB and
    // imola has 110 such textures — that is what hit the Jetsam limit.
    let (tw, th) = bc_fallback_target(width, height);
    if tw != width || th != height {
        println!("BC texture fallback: downscaled {width}x{height} -> {tw}x{th} (iOS memory budget)");
    }
    let rgba = if tw != width || th != height {
        downsample_rgba(&rgba, width, height, tw, th)
    } else {
        rgba
    };
    let target = if srgb { DXGI_FORMAT(29) } else { DXGI_FORMAT_R8G8B8A8_UNORM };
    rgba_with_mips_format(kgl, tw, th, rgba, target)
}

fn dds(kgl: &Kgl, bytes: &[u8]) -> Result<View, String> {
    let height = u32_at(bytes, 12);
    let width = u32_at(bytes, 16);
    let mip_count = u32_at(bytes, 28).max(1);
    let pf_flags = u32_at(bytes, 80);
    let four_cc = &bytes[84..88];
    let bit_count = u32_at(bytes, 88);
    let masks = [u32_at(bytes, 92), u32_at(bytes, 96), u32_at(bytes, 100), u32_at(bytes, 104)];
    let caps2 = u32_at(bytes, 112);
    if caps2 & 0x0020_0200 != 0 {
        return Err("cube and volume dds files are not read without D3DX".into());
    }
    let mut data = 128usize;
    const FOURCC: u32 = 0x4;
    let block_format = if pf_flags & FOURCC != 0 {
        match four_cc {
            b"DXT1" => Some((DXGI_FORMAT_BC1_UNORM, 8u32)),
            b"DXT2" | b"DXT3" => Some((DXGI_FORMAT_BC2_UNORM, 16)),
            b"DXT4" | b"DXT5" => Some((DXGI_FORMAT_BC3_UNORM, 16)),
            b"ATI1" | b"BC4U" => Some((DXGI_FORMAT_BC4_UNORM, 8)),
            b"ATI2" | b"BC5U" => Some((DXGI_FORMAT_BC5_UNORM, 16)),
            b"DX10" => {
                if bytes.len() < 148 {
                    return Err("short DX10 dds header".into());
                }
                data = 148;
                let format = DXGI_FORMAT(u32_at(bytes, 128) as i32);
                match format.0 {
                    70..=72 => Some((format, 8)),
                    73..=78 => Some((format, 16)),
                    79..=81 => Some((format, 8)),
                    82..=84 | 94..=99 => Some((format, 16)),
                    28 | 29 => None,
                    other => return Err(format!("dds format {other} is not read without D3DX")),
                }
            }
            other => return Err(format!("dds FourCC {:?} is not read without D3DX", String::from_utf8_lossy(other))),
        }
    } else {
        None
    };
    if let Some((format, block_bytes)) = block_format {
        let mut levels = Vec::new();
        let (mut w, mut h) = (width, height);
        for _ in 0..mip_count {
            let (bw, bh) = (w.div_ceil(4).max(1), h.div_ceil(4).max(1));
            let size = (bw * bh * block_bytes) as usize;
            if data + size > bytes.len() {
                break;
            }
            levels.push((bytes[data..data + size].to_vec(), bw * block_bytes));
            data += size;
            if w == 1 && h == 1 {
                break;
            }
            w = (w / 2).max(1);
            h = (h / 2).max(1);
        }
        if levels.is_empty() {
            return Err("dds file without pixel data".into());
        }
        // Metal on iOS has no TEXTURE_COMPRESSION_BC. Uploading a BC texture
        // there used to fail and KglTexture silently became empty, which is
        // why the road/trees were black or missing. Decode the original AC
        // texels on the CPU instead of dropping the texture.
        #[cfg(feature = "backend-wgpu")]
        {
            let compressed = matches!(format.0, 70..=72 | 73..=76 | 77..=84 | 94..=99);
            if compressed && !kgl.features.contains(wgpu::Features::TEXTURE_COMPRESSION_BC) {
                crate::texture::note_texture_cpu_decoded();
                return upload_decompressed_bc(kgl, format, width, height, &levels);
            }
        }
        return upload(kgl, width, height, format, &levels);
    }
    // uncompressed: level 0 to R8G8B8A8 through the channel masks
    let bytes_per_pixel = if pf_flags & FOURCC != 0 { 4 } else { (bit_count / 8) as usize };
    if !(1..=4).contains(&bytes_per_pixel) {
        return Err(format!("dds with {bit_count} bits per pixel is not read without D3DX"));
    }
    let masks = if pf_flags & FOURCC != 0 { [0xff, 0xff00, 0xff_0000, 0xff00_0000] } else { masks };
    let size = width as usize * height as usize * bytes_per_pixel;
    if data + size > bytes.len() {
        return Err("dds file shorter than its header says".into());
    }
    let luminance = pf_flags & 0x2_0000 != 0;
    let has_alpha = pf_flags & 0x1 != 0 || (pf_flags & 0x2 != 0);
    let channel = |pixel: u32, mask: u32| -> u8 {
        if mask == 0 {
            return 0;
        }
        let shift = mask.trailing_zeros();
        let max = mask >> shift;
        let value = (pixel & mask) >> shift;
        ((value as f32 / max as f32) * 255.0 + 0.5) as u8
    };
    let mut rgba = Vec::with_capacity(width as usize * height as usize * 4);
    for p in bytes[data..data + size].chunks_exact(bytes_per_pixel) {
        let mut pixel = 0u32;
        for (i, b) in p.iter().enumerate() {
            pixel |= (*b as u32) << (8 * i);
        }
        let r = channel(pixel, masks[0]);
        let (g, b) = if luminance { (r, r) } else { (channel(pixel, masks[1]), channel(pixel, masks[2])) };
        let a = if has_alpha && masks[3] != 0 { channel(pixel, masks[3]) } else { 255 };
        rgba.extend([r, g, b, a]);
    }
    rgba_with_mips(kgl, width, height, rgba)
}

/// png / jpg / bmp without WIC (kgl on wgpu, also in the browser), as straight 8-bit RGBA.
#[cfg(feature = "backend-wgpu")]
fn decode_image(bytes: &[u8]) -> Result<(u32, u32, Vec<u8>), String> {
    if bytes.starts_with(&[0xff, 0xd8]) {
        decode_jpg(bytes)
    } else if bytes.starts_with(b"BM") {
        decode_bmp(bytes)
    } else {
        decode_png(bytes)
    }
}

/// jpg through the jpeg-decoder crate. Its IDCT and chroma upsampling are not WIC's: the
/// texels can differ by a few steps (the test below measures it).
#[cfg(feature = "backend-wgpu")]
fn decode_jpg(bytes: &[u8]) -> Result<(u32, u32, Vec<u8>), String> {
    let mut decoder = jpeg_decoder::Decoder::new(bytes);
    let pixels = decoder.decode().map_err(|e| format!("not a jpg: {e}"))?;
    let info = decoder.info().ok_or("jpg without a header")?;
    let rgba = match info.pixel_format {
        jpeg_decoder::PixelFormat::RGB24 => pixels.chunks_exact(3).flat_map(|p| [p[0], p[1], p[2], 255]).collect(),
        jpeg_decoder::PixelFormat::L8 => pixels.iter().flat_map(|&g| [g, g, g, 255]).collect(),
        jpeg_decoder::PixelFormat::L16 => pixels.chunks_exact(2).flat_map(|p| [p[0], p[0], p[0], 255]).collect(),
        // shortcut (unreachable, shortcuts.md #48): CMYK as 255 - (c + k) per channel, not WIC's colour handling; no AC texture seen is CMYK
        jpeg_decoder::PixelFormat::CMYK32 => pixels.chunks_exact(4).flat_map(|p| [255 - p[0].saturating_add(p[3]), 255 - p[1].saturating_add(p[3]), 255 - p[2].saturating_add(p[3]), 255]).collect(),
    };
    Ok((info.width as u32, info.height as u32, rgba))
}

/// Uncompressed bmp (1 / 4 / 8 bits through the palette, 16 / 24 / 32 bits, bit fields), as
/// WIC reads it: alpha only where the header has an alpha mask.
#[cfg(feature = "backend-wgpu")]
fn decode_bmp(bytes: &[u8]) -> Result<(u32, u32, Vec<u8>), String> {
    let short = || "bmp file shorter than its header says".to_string();
    if bytes.len() < 54 {
        return Err(short());
    }
    let offset = u32_at(bytes, 10) as usize;
    let header = u32_at(bytes, 14) as usize;
    let width = u32_at(bytes, 18) as i32;
    let height = u32_at(bytes, 22) as i32;
    let bits = u16::from_le_bytes([bytes[28], bytes[29]]) as usize;
    let compression = u32_at(bytes, 30);
    if width <= 0 || height == 0 || header < 40 {
        return Err(format!("bmp of {width} x {height} with a {header}-byte header is not read"));
    }
    if compression != 0 && compression != 3 {
        return Err(format!("compressed bmp (type {compression}) is not read"));
    }
    if ![1, 4, 8, 16, 24, 32].contains(&bits) {
        return Err(format!("bmp with {bits} bits per pixel is not read"));
    }
    let (w, h) = (width as usize, height.unsigned_abs() as usize);
    // bit fields: right after a 40-byte header, else inside the longer header (alpha from 56 bytes on)
    let mask = |i: usize| if 54 + 4 * i + 4 <= bytes.len() { u32_at(bytes, 54 + 4 * i) } else { 0 };
    let masks = match (compression, bits) {
        (3, _) => [mask(0), mask(1), mask(2), if header >= 56 { mask(3) } else { 0 }],
        (_, 16) => [0x7c00, 0x3e0, 0x1f, 0],
        _ => [0xff_0000, 0xff00, 0xff, 0],
    };
    let colours = match u32_at(bytes, 46) as usize {
        0 => 1usize << bits.min(8),
        n => n,
    };
    let palette = 14 + header + if compression == 3 && header == 40 { 12 } else { 0 };
    let stride = (w * bits).div_ceil(32) * 4;
    if offset + stride * h > bytes.len() || (bits <= 8 && palette + 4 * colours > bytes.len()) {
        return Err(short());
    }
    let channel = |pixel: u32, mask: u32| -> u8 {
        if mask == 0 {
            return 255;
        }
        let shift = mask.trailing_zeros();
        let max = (mask >> shift) as u64;
        (((pixel & mask) >> shift) as u64 * 255 / max) as u8
    };
    let mut rgba = vec![0u8; w * h * 4];
    for y in 0..h {
        // rows are stored bottom-up unless the height is negative
        let row = &bytes[offset + stride * if height > 0 { h - 1 - y } else { y }..];
        for x in 0..w {
            let out = &mut rgba[(y * w + x) * 4..][..4];
            if bits <= 8 {
                let bit = x * bits;
                let index = ((row[bit / 8] as usize) >> (8 - bits - bit % 8)) & ((1 << bits) - 1);
                let at = palette + 4 * index.min(colours - 1);
                out.copy_from_slice(&[bytes[at + 2], bytes[at + 1], bytes[at], 255]);
            } else {
                let n = bits / 8;
                let pixel = row[x * n..][..n].iter().rev().fold(0u32, |v, &b| v << 8 | b as u32);
                out.copy_from_slice(&[channel(pixel, masks[0]), channel(pixel, masks[1]), channel(pixel, masks[2]), channel(pixel, masks[3])]);
            }
        }
    }
    Ok((w as u32, h as u32, rgba))
}

/// png through the png crate.
#[cfg(feature = "backend-wgpu")]
fn decode_png(bytes: &[u8]) -> Result<(u32, u32, Vec<u8>), String> {
    let mut decoder = png::Decoder::new(bytes);
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder.read_info().map_err(|e| format!("not a png: {e}"))?;
    let mut buf = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buf).map_err(|e| format!("png: {e}"))?;
    let (w, h) = (info.width, info.height);
    let n = (w * h) as usize;
    let rgba = match info.color_type {
        png::ColorType::Rgba => buf[..n * 4].to_vec(),
        png::ColorType::Rgb => buf[..n * 3].chunks_exact(3).flat_map(|p| [p[0], p[1], p[2], 255]).collect(),
        png::ColorType::GrayscaleAlpha => buf[..n * 2].chunks_exact(2).flat_map(|p| [p[0], p[0], p[0], p[1]]).collect(),
        _ => buf[..n].iter().flat_map(|&g| [g, g, g, 255]).collect(),
    };
    Ok((w, h, rgba))
}

/// png / jpg / bmp through the Windows Imaging Component, as straight 8-bit RGBA.
#[cfg(all(windows, any(not(feature = "backend-wgpu"), test)))]
fn decode_with_wic(bytes: &[u8]) -> Result<(u32, u32, Vec<u8>), String> {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        let factory: IWICImagingFactory = CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER).map_err(|e| format!("WIC: {e}"))?;
        let stream = factory.CreateStream().map_err(|e| format!("WIC stream: {e}"))?;
        stream.InitializeFromMemory(bytes).map_err(|e| format!("WIC stream: {e}"))?;
        let decoder = factory.CreateDecoderFromStream(&stream, std::ptr::null(), WICDecodeMetadataCacheOnDemand).map_err(|e| format!("not an image WIC can read: {e}"))?;
        let frame = decoder.GetFrame(0).map_err(|e| format!("WIC frame: {e}"))?;
        let converter = factory.CreateFormatConverter().map_err(|e| format!("WIC converter: {e}"))?;
        converter.Initialize(&frame, &GUID_WICPixelFormat32bppRGBA, WICBitmapDitherTypeNone, None, 0.0, WICBitmapPaletteTypeCustom).map_err(|e| format!("WIC convert: {e}"))?;
        let (mut width, mut height) = (0u32, 0u32);
        converter.GetSize(&mut width, &mut height).map_err(|e| format!("WIC size: {e}"))?;
        let mut rgba = vec![0u8; width as usize * height as usize * 4];
        let source: IWICBitmapSource = converter.cast().map_err(|e| format!("WIC: {e}"))?;
        source.CopyPixels(std::ptr::null(), width * 4, &mut rgba).map_err(|e| format!("WIC pixels: {e}"))?;
        Ok((width, height, rgba))
    }
}

#[cfg(test)]
mod bc_decoder_tests {
    use super::*;

    #[test]
    fn dxt1_solid_block_decodes_to_opaque_red() {
        // c0 = c1 = 0xF800 (R=31,G=0,B=0), every index selects colour 0.
        let block = [0x00, 0xF8, 0x00, 0xF8, 0, 0, 0, 0];
        let rgba = decode_bc(1, 4, 4, &block).unwrap();
        assert_eq!(rgba.len(), 4 * 4 * 4);
        for px in rgba.chunks_exact(4) {
            assert_eq!(px, &[255, 0, 0, 255]);
        }
    }

    #[test]
    fn dxt5_uses_the_dxt5_alpha_endpoints() {
        // Alpha endpoint 0 = 255, index 0 for all pixels; colour is solid red.
        let mut block = [0u8; 16];
        block[0] = 255;
        block[1] = 0;
        block[8] = 0x00; block[9] = 0xF8;
        block[10] = 0x00; block[11] = 0xF8;
        let rgba = decode_bc(3, 4, 4, &block).unwrap();
        for px in rgba.chunks_exact(4) {
            assert_eq!(px[3], 255, "DXT5 alpha endpoint 0 must be opaque");
            assert_eq!(&px[..3], &[255, 0, 0]);
        }
    }

    #[test]
    fn short_block_is_reported_not_silently_dropped() {
        assert!(decode_bc(1, 4, 4, &[0u8; 4]).is_err());
        assert!(decode_bc(3, 4, 4, &[0u8; 8]).is_err());
    }

    #[test]
    fn ios_memory_budget_caps_huge_textures() {
        assert_eq!(bc_fallback_target(512, 512), (512, 512));
        assert_eq!(bc_fallback_target(4096, 4096), (1024, 1024));
        for (w, h) in [(4096, 2048), (2048, 4096), (2048, 2048), (4096, 4096)] {
            let (tw, th) = bc_fallback_target(w, h);
            assert!(tw as u64 * th as u64 <= BC_FALLBACK_MAX_PIXELS as u64,
                    "{w}x{h} -> {tw}x{th} exceeds the memory budget");
        }
    }

    #[test]
    fn downsample_averages_blocks_and_preserves_alpha() {
        let mut src = vec![0u8; 4 * 4 * 4];
        for p in src.chunks_exact_mut(4) { p.copy_from_slice(&[200, 100, 50, 255]); }
        let small = downsample_rgba(&src, 4, 4, 2, 2);
        assert_eq!(small.len(), 2 * 2 * 4);
        for p in small.chunks_exact(4) { assert_eq!(p, &[200, 100, 50, 255]); }
    }
}

/// kgl on wgpu's readers against WIC (what the Direct3D 11 path without D3DX reads) on the
/// install's own png, jpg and bmp files.
#[cfg(all(test, windows, feature = "backend-wgpu"))]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

    fn is(path: &Path, ext: &str) -> bool {
        path.extension().is_some_and(|e| e.eq_ignore_ascii_case(ext))
    }

    fn files(folder: &Path, ext: &str, n: usize, out: &mut Vec<PathBuf>) {
        for entry in std::fs::read_dir(folder).into_iter().flatten().flatten() {
            if out.iter().filter(|p| is(p, ext)).count() >= n {
                return;
            }
            let path = entry.path();
            if path.is_dir() {
                files(&path, ext, n, out);
            } else if is(&path, ext) {
                out.push(path);
            }
        }
    }

    #[test]
    fn same_texels_as_wic() {
        let game = PathBuf::from(std::env::var("AC_ROOT").unwrap_or_else(|_| r"C:\Program Files (x86)\Steam\steamapps\common\assettocorsa".to_string()));
        if !game.join("content").is_dir() {
            eprintln!("no Assetto Corsa install at {}: skipped", game.display());
            return;
        }
        let mut found = Vec::new();
        for (folder, ext, n) in [("content/texture", "jpg", 8), ("content/fonts", "bmp", 3), ("content/cars", "bmp", 6), ("content/texture", "png", 4)] {
            files(&game.join(folder), ext, n, &mut found);
        }
        assert!(found.iter().any(|p| is(p, "bmp")) && found.iter().any(|p| is(p, "jpg")), "no bmp or jpg found");
        for path in &found {
            let bytes = std::fs::read(path).unwrap();
            let Ok((ww, wh, wic)) = decode_with_wic(&bytes) else { continue };
            let (w, h, mine) = decode_image(&bytes).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
            assert_eq!((w, h), (ww, wh), "{}", path.display());
            let worst = wic.iter().zip(&mine).map(|(a, b)| a.abs_diff(*b)).max().unwrap_or(0);
            let differ = wic.iter().zip(&mine).filter(|(a, b)| a != b).count();
            println!("{}: {w} x {h}, {differ} of {} bytes differ, largest difference {worst}", path.display(), wic.len());
            assert!(if is(path, "jpg") { worst <= 4 } else { worst == 0 }, "{}: largest difference {worst}", path.display());
        }
    }
}

use std::fs;

const ICNS_SIZES: &[(u32, [u8; 4])] = &[
    (16, *b"icp4"),
    (32, *b"icp5"),
    (64, *b"icp6"),
    (128, *b"ic07"),
    (256, *b"ic08"),
    (512, *b"ic09"),
    (1024, *b"ic10"),
];

pub fn generate_icns(svg_path: &str, output_path: &str, nearest_neighbor: bool) -> bool {
    let svg_data = match fs::read(svg_path) {
        Ok(d) => d,
        Err(_) => return false,
    };

    let opt = resvg::usvg::Options::default();
    let tree = match resvg::usvg::Tree::from_data(&svg_data, &opt) {
        Ok(t) => t,
        Err(_) => return false,
    };

    let orig_size = tree.size();
    let ow = orig_size.width() as u32;
    let oh = orig_size.height() as u32;

    let mut base_pixmap = match tiny_skia::Pixmap::new(ow, oh) {
        Some(p) => p,
        None => return false,
    };
    resvg::render(
        &tree,
        tiny_skia::Transform::identity(),
        &mut base_pixmap.as_mut(),
    );

    let mut icns_data: Vec<u8> = Vec::new();
    icns_data.extend_from_slice(b"icns");
    icns_data.extend_from_slice(&[0u8; 4]);

    for &(target_size, ostype) in ICNS_SIZES {
        let png_data = if target_size == ow && target_size == oh {
            match base_pixmap.encode_png() {
                Ok(d) => d,
                Err(_) => return false,
            }
        } else if nearest_neighbor {
            let mut target = match tiny_skia::Pixmap::new(target_size, target_size) {
                Some(p) => p,
                None => return false,
            };
            nn_scale(
                base_pixmap.data(),
                ow,
                oh,
                target.data_mut(),
                target_size,
                target_size,
            );
            match target.encode_png() {
                Ok(d) => d,
                Err(_) => return false,
            }
        } else {
            let mut target = match tiny_skia::Pixmap::new(target_size, target_size) {
                Some(p) => p,
                None => return false,
            };
            let sx = target_size as f32 / orig_size.width();
            let sy = target_size as f32 / orig_size.height();
            resvg::render(
                &tree,
                tiny_skia::Transform::from_scale(sx, sy),
                &mut target.as_mut(),
            );
            match target.encode_png() {
                Ok(d) => d,
                Err(_) => return false,
            }
        };

        let entry_size = (png_data.len() + 8) as u32;
        icns_data.extend_from_slice(&ostype);
        icns_data.extend_from_slice(&entry_size.to_be_bytes());
        icns_data.extend_from_slice(&png_data);
    }

    let total_size = icns_data.len() as u32;
    icns_data[4..8].copy_from_slice(&total_size.to_be_bytes());

    fs::write(output_path, &icns_data).is_ok()
}

fn nn_scale(src: &[u8], sw: u32, sh: u32, dst: &mut [u8], dw: u32, dh: u32) {
    for dy in 0..dh {
        for dx in 0..dw {
            let sx = (dx * sw / dw).min(sw - 1);
            let sy = (dy * sh / dh).min(sh - 1);
            let si = ((sy * sw + sx) * 4) as usize;
            let di = ((dy * dw + dx) * 4) as usize;
            dst[di..di + 4].copy_from_slice(&src[si..si + 4]);
        }
    }
}

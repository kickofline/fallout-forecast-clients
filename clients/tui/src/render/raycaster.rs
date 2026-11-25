use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};

use crate::game::data::{BoxObstacle, CylObstacle, MapData, SolidKind};
use crate::game::state::GameApp;

const SHADE_RAMP: &[u8] = b" .:-=+*#%@";

#[derive(Clone, Copy)]
struct Cell {
    ch: char,
    fg: Color,
    bg: Color,
    bold: bool,
}

impl Default for Cell {
    fn default() -> Self {
        Self {
            ch: ' ',
            fg: Color::Gray,
            bg: Color::Reset,
            bold: false,
        }
    }
}

pub struct AsciiCanvas {
    pub width: usize,
    pub height: usize,
    cells: Vec<Cell>,
}

impl AsciiCanvas {
    pub fn new(width: usize, height: usize) -> Self {
        Self {
            width,
            height,
            cells: vec![Cell::default(); width * height],
        }
    }

    #[inline]
    pub fn set(&mut self, x: usize, y: usize, ch: char, fg: Color, bg: Color, bold: bool) {
        if x < self.width && y < self.height {
            self.cells[y * self.width + x] = Cell { ch, fg, bg, bold };
        }
    }

    #[inline]
    pub fn set_fg(&mut self, x: usize, y: usize, ch: char, fg: Color, bold: bool) {
        if x < self.width && y < self.height {
            let c = &mut self.cells[y * self.width + x];
            c.ch = ch;
            c.fg = fg;
            c.bold = bold;
        }
    }

    pub fn draw_text(&mut self, x: isize, y: isize, text: &str, fg: Color, bold: bool) {
        if y < 0 || y >= self.height as isize {
            return;
        }
        let uy = y as usize;
        for (i, ch) in text.chars().enumerate() {
            let cx = x + i as isize;
            if cx >= 0 && cx < self.width as isize {
                self.set_fg(cx as usize, uy, ch, fg, bold);
            }
        }
    }

    pub fn blit(&self, area: Rect, buf: &mut Buffer) {
        let max_w = self.width.min(area.width as usize);
        let max_h = self.height.min(area.height as usize);
        for y in 0..max_h {
            for x in 0..max_w {
                let c = self.cells[y * self.width + x];
                let cell = &mut buf[(area.x + x as u16, area.y + y as u16)];
                cell.set_char(c.ch);
                let mut style = Style::default().fg(c.fg);
                if c.bg != Color::Reset {
                    style = style.bg(c.bg);
                }
                if c.bold {
                    style = style.add_modifier(Modifier::BOLD);
                }
                cell.set_style(style);
            }
        }
    }
}

pub fn render_fps_viewport(app: &GameApp, area: Rect, buf: &mut Buffer, time_secs: f32) {
    let w = area.width as usize;
    let h = area.height as usize;
    if w < 8 || h < 6 {
        return;
    }

    let mut canvas = AsciiCanvas::new(w, h);
    let mut z_buf = vec![120.0f32; w];

    let eye = app.my_eye_pos();
    let yaw = app.my_yaw;
    let pitch = app.my_pitch;
    let fov_deg: f32 = if app.input.ads { 48.0 } else { 74.0 };
    let fov = fov_deg.to_radians();
    let half_tan = (fov * 0.5).tan();

    // Terminal characters are roughly 2:1 tall-to-wide, so vertical projection scales by ~0.55
    let proj_y = (h as f32) / (2.0 * half_tan) * 1.15;
    let horizon = ((h as f32) * 0.5 + pitch.tan() * proj_y * 0.55)
        .clamp(-(h as f32) * 0.4, (h as f32) * 1.4);

    let storm = app.storm_intensity.clamp(0.0, 1.0);
    let acid_mode = storm >= 0.85 || app.wave >= 5 && app.phase == 3;
    let flash = app.lightning_flash.clamp(0.0, 1.0);
    let max_vis = (85.0 - storm * 48.0).max(26.0);

    let env = app.current_map.as_ref().map(|m| &m.env);
    let sky_top = env.map(|e| e.sky_top).unwrap_or((28, 22, 56));
    let sky_hor = env.map(|e| e.sky_horizon).unwrap_or((217, 88, 107));
    let gnd_hor = env.map(|e| e.ground_horizon).unwrap_or((80, 56, 74));
    let gnd_bot = env.map(|e| e.ground_bottom).unwrap_or((24, 22, 34));
    let fog_rgb = if acid_mode {
        (46, 98, 36)
    } else if storm > 0.2 {
        lerp_rgb(
            env.map(|e| e.fog_calm).unwrap_or((90, 90, 110)),
            (72, 102, 74),
            storm * 0.5,
        )
    } else {
        env.map(|e| e.fog_calm).unwrap_or((100, 94, 128))
    };

    // 1. Sky & Ground pass
    for y in 0..h {
        let yf = y as f32;
        if yf < horizon {
            let t = (yf / horizon.max(1.0)).clamp(0.0, 1.0);
            let mut rgb = lerp_rgb(sky_top, sky_hor, t.powf(1.5));
            rgb = lerp_rgb(rgb, fog_rgb, storm * 0.65);
            if flash > 0.01 {
                rgb = lerp_rgb(rgb, (245, 250, 255), flash * 0.8);
            }
            let bg = Color::Rgb(rgb.0 / 3, rgb.1 / 3, rgb.2 / 3);
            let fg = Color::Rgb(rgb.0, rgb.1, rgb.2);
            for x in 0..w {
                let cloud_wave = ((x as f32 * 0.13 + yaw * 8.0 + time_secs * 0.4).sin()
                    + (y as f32 * 0.45).cos())
                    * 0.5;
                let ch = if flash > 0.45 {
                    ':'
                } else if t > 0.82 && storm > 0.25 {
                    '-'
                } else if cloud_wave > (0.62 - storm * 0.35) && t < 0.78 {
                    if storm > 0.5 { '=' } else { '~' }
                } else if ((x * 31 + y * 17) % 53) == 0 && storm < 0.2 && t < 0.45 {
                    '.'
                } else {
                    ' '
                };
                canvas.set(x, y, ch, fg, bg, false);
            }
        } else {
            let dy = (yf - horizon).max(0.5);
            let row_dist = (eye[1] * proj_y / dy).clamp(0.4, max_vis * 1.4);
            let t = (dy / (h as f32 - horizon).max(1.0)).clamp(0.0, 1.0);
            let mut rgb = lerp_rgb(gnd_hor, gnd_bot, t.powf(0.7));
            let fog_t = (row_dist / max_vis).clamp(0.0, 1.0);
            rgb = lerp_rgb(rgb, fog_rgb, fog_t * 0.75);
            if flash > 0.01 {
                rgb = lerp_rgb(rgb, (210, 225, 235), flash * 0.4);
            }
            let fg = Color::Rgb(
                rgb.0.saturating_add(28),
                rgb.1.saturating_add(28),
                rgb.2.saturating_add(28),
            );
            let bg = Color::Rgb(rgb.0 / 3, rgb.1 / 3, rgb.2 / 3);
            let ch = if fog_t > 0.75 {
                '.'
            } else if t > 0.65 {
                ','
            } else if t > 0.35 {
                '.'
            } else {
                ':'
            };
            for x in 0..w {
                canvas.set(x, y, ch, fg, bg, false);
            }
        }
    }

    // Lightning bolt silhouette in sky
    if let Some(bolt_ang) = app.lightning_bolt_col {
        let mut a = bolt_ang;
        while a > std::f32::consts::PI {
            a -= std::f32::consts::TAU;
        }
        while a < -std::f32::consts::PI {
            a += std::f32::consts::TAU;
        }
        if a.abs() < fov * 0.65 && flash > 0.15 {
            let bx = ((0.5 - (a.tan() / (2.0 * half_tan))) * w as f32) as isize;
            let bot = (horizon as usize).min(h);
            for y in 0..bot {
                let jitter = if y % 3 == 0 { 1 } else if y % 3 == 1 { -1 } else { 0 };
                let ch = if jitter > 0 { '\\' } else if jitter < 0 { '/' } else { '|' };
                let cx = bx + jitter;
                if cx >= 0 && cx < w as isize {
                    canvas.set_fg(cx as usize, y, ch, Color::Rgb(245, 255, 255), true);
                }
            }
        }
    }

    // 2. Analytic 3D column raycast against MapData boxes, cylinders, roofs & ground puddles
    if let Some(map) = &app.current_map {
        cast_map_columns(
            app,
            map,
            &mut canvas,
            &mut z_buf,
            eye,
            yaw,
            fov,
            half_tan,
            proj_y,
            horizon,
            max_vis,
            fog_rgb,
            flash,
            time_secs,
        );
    }

    // 3. Depth-sorted 3D billboards (enemies, boss, teammates, pickups, vending, decon, effects, tracers)
    render_billboards(
        app,
        &mut canvas,
        &z_buf,
        eye,
        yaw,
        fov,
        half_tan,
        proj_y,
        horizon,
        max_vis,
        time_secs,
    );

    // 4. Dynamic acid rain streaks overlay
    if app.is_raining() {
        let density = (storm * 0.12).clamp(0.015, 0.14);
        let rain_color = if acid_mode {
            Color::Rgb(140, 255, 64)
        } else {
            Color::Rgb(120, 225, 165)
        };
        let frame_seed = (time_secs * 18.0) as usize;
        for y in 0..h {
            for x in 0..w {
                // Keep immediate overhead clearer when sheltered
                if app.is_sheltered && y < h / 3 && x > w / 5 && x < (w * 4) / 5 {
                    continue;
                }
                let hash = (x.wrapping_add(frame_seed.wrapping_mul(2)).wrapping_mul(73_856_093))
                    ^ (y.wrapping_sub(frame_seed.wrapping_mul(3)).wrapping_mul(19_349_663));
                let bucket = (hash % 1000) as f32 / 1000.0;
                if bucket < density {
                    let ch = if acid_mode {
                        if hash % 3 == 0 { '/' } else { '|' }
                    } else if hash % 2 == 0 {
                        '/'
                    } else {
                        '\''
                    };
                    canvas.set_fg(x, y, ch, rain_color, acid_mode);
                }
            }
        }
    }

    // 5. Center crosshair & hit markers
    draw_crosshair(app, &mut canvas);

    // 6. First-person ASCII weapon viewmodel + recoil + muzzle flash
    draw_weapon_viewmodel(app, &mut canvas);

    // 7. Damage / Acid edge flash border inside viewport (only on significant hits/heavy acid)
    if app.hurt_flash_ttl > 0.0 || app.acid_flash_ttl > 0.0 {
        let color = if app.hurt_flash_ttl >= app.acid_flash_ttl {
            Color::Rgb(255, 65, 65)
        } else {
            Color::Rgb(150, 255, 50)
        };
        let corner = 6.min(w / 4);
        for x in 0..corner {
            canvas.set_fg(x, 0, '▓', color, true);
            canvas.set_fg(w - 1 - x, 0, '▓', color, true);
            canvas.set_fg(x, h - 1, '▓', color, true);
            canvas.set_fg(w - 1 - x, h - 1, '▓', color, true);
        }
        for y in 0..3.min(h / 3) {
            canvas.set_fg(0, y, '▓', color, true);
            canvas.set_fg(w - 1, y, '▓', color, true);
            canvas.set_fg(0, h - 1 - y, '▓', color, true);
            canvas.set_fg(w - 1, h - 1 - y, '▓', color, true);
        }
    }

    canvas.blit(area, buf);
}

struct RayHit {
    dist: f32,
    y_min: f32,
    y_max: f32,
    shade: f32,
    u_tex: f32,
    kind: SolidKind,
    rgb: (u8, u8, u8),
}

#[allow(clippy::too_many_arguments)]
fn cast_map_columns(
    app: &GameApp,
    map: &MapData,
    canvas: &mut AsciiCanvas,
    z_buf: &mut [f32],
    eye: [f32; 3],
    yaw: f32,
    fov: f32,
    half_tan: f32,
    proj_y: f32,
    horizon: f32,
    max_vis: f32,
    fog_rgb: (u8, u8, u8),
    flash: f32,
    time_secs: f32,
) {
    let w = canvas.width;
    let h = canvas.height;
    let _ = fov;

    // Collect active puddles for floorcasting
    let active_puddles: Vec<([f32; 2], f32)> = map
        .puddles
        .iter()
        .filter_map(|p| {
            let g = app.puddle_growth.get(&p.sync_key).copied().unwrap_or(0.0);
            let r = p.max_radius * g;
            if r > 0.25 {
                Some(([p.pos[0], p.pos[2]], r))
            } else {
                None
            }
        })
        .collect();

    for x in 0..w {
        let ndc_x = ((x as f32 + 0.5) / w as f32) * 2.0 - 1.0; // -1 left .. +1 right
        let rel_angle = (ndc_x * half_tan).atan();
        let ray_yaw = yaw - rel_angle;
        let rdx = -ray_yaw.sin();
        let rdz = -ray_yaw.cos();
        let cos_corr = rel_angle.cos().max(0.2);

        let mut best: Option<RayHit> = None;

        for b in &map.boxes {
            if let Some(hit) = intersect_box_xz(eye[0], eye[2], rdx, rdz, b) {
                if hit.dist < max_vis && best.as_ref().map(|cur| hit.dist < cur.dist).unwrap_or(true)
                {
                    best = Some(hit);
                }
            }
        }
        for c in &map.cylinders {
            if let Some(hit) = intersect_cyl_xz(eye[0], eye[2], rdx, rdz, c) {
                if hit.dist < max_vis && best.as_ref().map(|cur| hit.dist < cur.dist).unwrap_or(true)
                {
                    best = Some(hit);
                }
            }
        }

        let mut wall_top_i = h as isize;
        let mut wall_bot_i = 0isize;

        if let Some(hit) = best {
            let perp = (hit.dist * cos_corr).max(0.15);
            z_buf[x] = perp;

            let top_f = horizon - (hit.y_max - eye[1]) * proj_y / perp;
            let bot_f = horizon - (hit.y_min - eye[1]) * proj_y / perp;
            wall_top_i = (top_f.floor() as isize).clamp(0, h as isize);
            wall_bot_i = (bot_f.ceil() as isize).clamp(0, h as isize);

            let fog_t = (perp / max_vis).clamp(0.0, 1.0);
            let mut brightness = (1.0 - fog_t * 0.85) * hit.shade;
            if flash > 0.01 {
                brightness = (brightness + flash * 0.35).min(1.0);
            }
            let base_rgb = lerp_rgb(hit.rgb, fog_rgb, fog_t * 0.72);
            let lit_rgb = (
                (base_rgb.0 as f32 * (0.45 + 0.55 * brightness)) as u8,
                (base_rgb.1 as f32 * (0.45 + 0.55 * brightness)) as u8,
                (base_rgb.2 as f32 * (0.45 + 0.55 * brightness)) as u8,
            );
            let fg = Color::Rgb(lit_rgb.0, lit_rgb.1, lit_rgb.2);
            let bg = Color::Rgb(lit_rgb.0 / 5, lit_rgb.1 / 5, lit_rgb.2 / 5);

            let span = (bot_f - top_f).max(1.0);
            let ramp_idx = ((brightness * (SHADE_RAMP.len() - 1) as f32).round() as usize)
                .clamp(1, SHADE_RAMP.len() - 1);
            let base_ch = SHADE_RAMP[ramp_idx] as char;

            for y in (wall_top_i as usize)..(wall_bot_i as usize) {
                let v_tex = ((y as f32 - top_f) / span).clamp(0.0, 1.0);
                let (ch, cell_fg) = match hit.kind {
                    SolidKind::BuildingWall => {
                        // Storefront windows & roofline cornice
                        if y == wall_top_i as usize {
                            ('_', Color::Rgb(210, 200, 220))
                        } else if v_tex > 0.32 && v_tex < 0.68 && (hit.u_tex * 4.0).fract() > 0.25 && (hit.u_tex * 4.0).fract() < 0.75 && perp < 38.0 {
                            ('[', Color::Rgb(90, 205, 220))
                        } else if ((v_tex * 8.0) as usize) % 2 == 0 && (hit.u_tex * 6.0).fract() < 0.08 {
                            ('|', fg)
                        } else {
                            (base_ch, fg)
                        }
                    }
                    SolidKind::ShelterPillar => ('|', fg),
                    SolidKind::TreeTrunk => {
                        if v_tex < 0.35 {
                            ('%', Color::Rgb(62, 148, 78))
                        } else {
                            ('|', fg)
                        }
                    }
                    SolidKind::Fence => {
                        if (y + x) % 2 == 0 {
                            ('#', fg)
                        } else {
                            ('+', fg)
                        }
                    }
                    SolidKind::VendingCabinet => {
                        if v_tex > 0.2 && v_tex < 0.55 {
                            ('$', Color::Rgb(255, 235, 110))
                        } else {
                            ('#', fg)
                        }
                    }
                    SolidKind::DeconBooth => ('H', Color::Rgb(100, 250, 240)),
                };
                canvas.set(x, y, ch, cell_fg, bg, matches!(hit.kind, SolidKind::VendingCabinet | SolidKind::DeconBooth));
            }
        }

        // Overhead shelter canopies / tree foliage (sampled on upper sky rows)
        let roof_limit = (wall_top_i as usize).min(horizon.max(0.0) as usize).min(h);
        if !map.roofs.is_empty() && roof_limit > 0 {
            for y in 0..roof_limit {
                let dy = horizon - y as f32;
                if dy < 1.5 {
                    continue;
                }
                for roof in &map.roofs {
                    if roof.y_height <= eye[1] + 0.1 {
                        continue;
                    }
                    let perp = (roof.y_height - eye[1]) * proj_y / dy;
                    let dist = perp / cos_corr;
                    if dist <= 0.4 || dist > 32.0 || perp >= z_buf[x] {
                        continue;
                    }
                    let wx = eye[0] + rdx * dist;
                    let wz = eye[2] + rdz * dist;
                    let dx = wx - roof.center_xz[0];
                    let dz = wz - roof.center_xz[1];
                    let c = roof.yaw.cos();
                    let s = roof.yaw.sin();
                    let lx = dx * c - dz * s;
                    let lz = dx * s + dz * c;
                    if lx.abs() <= roof.half_xz[0] && lz.abs() <= roof.half_xz[1] {
                        let fog_t = (perp / max_vis).clamp(0.0, 1.0);
                        let col = lerp_rgb(roof.rgb, fog_rgb, fog_t * 0.7);
                        let ch = if roof.is_foliage {
                            if (x + y) % 3 == 0 { '&' } else { '*' }
                        } else if (x + y) % 4 == 0 {
                            '='
                        } else {
                            '-'
                        };
                        canvas.set(
                            x,
                            y,
                            ch,
                            Color::Rgb(col.0, col.1, col.2),
                            Color::Rgb(col.0 / 4, col.1 / 4, col.2 / 4),
                            false,
                        );
                        break;
                    }
                }
            }
        }

        // Floor puddle projection (below wall bottom)
        if !active_puddles.is_empty() {
            let start_y = (wall_bot_i as usize).max(horizon.ceil().max(0.0) as usize).min(h);
            for y in start_y..h {
                let dy = (y as f32 - horizon).max(0.5);
                let perp = eye[1] * proj_y / dy;
                let dist = perp / cos_corr;
                if dist > 42.0 {
                    continue;
                }
                let wx = eye[0] + rdx * dist;
                let wz = eye[2] + rdz * dist;
                for (pc, r) in &active_puddles {
                    let dx = wx - pc[0];
                    let dz = wz - pc[1];
                    if dx * dx + dz * dz <= r * r {
                        let ripple = ((wx * 2.0 + time_secs * 3.0).sin() + (wz * 2.0).cos()) > 0.2;
                        let ch = if ripple { '~' } else { '=' };
                        canvas.set(
                            x,
                            y,
                            ch,
                            Color::Rgb(150, 255, 70),
                            Color::Rgb(28, 66, 22),
                            false,
                        );
                        break;
                    }
                }
            }
        }
    }
}

fn intersect_box_xz(ox: f32, oz: f32, dx: f32, dz: f32, b: &BoxObstacle) -> Option<RayHit> {
    // Transform ray into box local XZ frame
    let rx = ox - b.center[0];
    let rz = oz - b.center[2];
    let c = b.yaw.cos();
    let s = b.yaw.sin();
    let lox = rx * c - rz * s;
    let loz = rx * s + rz * c;
    let ldx = dx * c - dz * s;
    let ldz = dx * s + dz * c;

    let hx = b.half_size[0];
    let hz = b.half_size[2];

    let (tx1, tx2) = if ldx.abs() > 1e-6 {
        let a = (-hx - lox) / ldx;
        let b_t = (hx - lox) / ldx;
        (a.min(b_t), a.max(b_t))
    } else if lox.abs() <= hx {
        (f32::NEG_INFINITY, f32::INFINITY)
    } else {
        return None;
    };

    let (tz1, tz2) = if ldz.abs() > 1e-6 {
        let a = (-hz - loz) / ldz;
        let b_t = (hz - loz) / ldz;
        (a.min(b_t), a.max(b_t))
    } else if loz.abs() <= hz {
        (f32::NEG_INFINITY, f32::INFINITY)
    } else {
        return None;
    };

    let t_enter = tx1.max(tz1);
    let t_exit = tx2.min(tz2);
    if t_exit < 0.0 || t_enter > t_exit || t_enter < 0.15 {
        return None;
    }

    let hit_x = lox + ldx * t_enter;
    let hit_z = loz + ldz * t_enter;
    let (shade, u_tex) = if tx1 > tz1 {
        // Hit X face
        (0.78, (hit_z + hz) / (2.0 * hz).max(0.01))
    } else {
        // Hit Z face
        (1.0, (hit_x + hx) / (2.0 * hx).max(0.01))
    };

    Some(RayHit {
        dist: t_enter,
        y_min: b.center[1] - b.half_size[1],
        y_max: b.center[1] + b.half_size[1],
        shade,
        u_tex,
        kind: b.kind,
        rgb: b.rgb,
    })
}

fn intersect_cyl_xz(ox: f32, oz: f32, dx: f32, dz: f32, cyl: &CylObstacle) -> Option<RayHit> {
    let rx = ox - cyl.center[0];
    let rz = oz - cyl.center[2];
    let b = rx * dx + rz * dz;
    let c = rx * rx + rz * rz - cyl.radius * cyl.radius;
    let disc = b * b - c;
    if disc < 0.0 {
        return None;
    }
    let t = -b - disc.sqrt();
    if t < 0.15 {
        return None;
    }
    let hx = rx + dx * t;
    let hz = rz + dz * t;
    let nx = hx / cyl.radius.max(0.01);
    let nz = hz / cyl.radius.max(0.01);
    let sun = (nx * 0.6 + nz * -0.5).clamp(-0.5, 1.0);
    let shade = 0.62 + 0.38 * ((sun + 0.5) / 1.5);
    let u_tex = (hz.atan2(hx) / std::f32::consts::TAU + 0.5).fract();
    Some(RayHit {
        dist: t,
        y_min: cyl.y_min,
        y_max: cyl.y_max,
        shade,
        u_tex,
        kind: cyl.kind,
        rgb: cyl.rgb,
    })
}

struct Billboard {
    pos: [f32; 3],
    depth: f32,
    height_m: f32,
    sprite: Vec<&'static str>,
    color: Color,
    label: Option<String>,
    hp_frac: Option<f32>,
    bold: bool,
}

#[allow(clippy::too_many_arguments)]
fn render_billboards(
    app: &GameApp,
    canvas: &mut AsciiCanvas,
    z_buf: &[f32],
    eye: [f32; 3],
    yaw: f32,
    _fov: f32,
    half_tan: f32,
    proj_y: f32,
    horizon: f32,
    max_vis: f32,
    time_secs: f32,
) {
    let fwd = [-yaw.sin(), -yaw.cos()];
    let right = [yaw.cos(), -yaw.sin()];

    let mut list: Vec<Billboard> = Vec::new();

    // Enemies
    for e in app.enemies.values() {
        let dx = e.pos[0] - eye[0];
        let dz = e.pos[2] - eye[2];
        let depth = dx * fwd[0] + dz * fwd[1];
        if depth <= 0.4 || depth > max_vis + 8.0 {
            continue;
        }
        let (mut sprite, mut color, mut h_m, tag) = enemy_visual(e.kind, e.miniboss_wave);
        if e.small {
            h_m *= 0.65;
        }
        if e.elite {
            h_m *= 1.15;
            sprite = vec![
                "  \\*/  ",
                " /@@@\\ ",
                " |O O| ",
                " /|#|\\ ",
                "  / \\  ",
            ];
        }
        if e.hit_flash > 0.0 {
            color = Color::White;
        } else if e.tell_timer > 0.0 && ((time_secs * 12.0) as i32) % 2 == 0 {
            color = Color::Rgb(255, 90, 90);
        }
        let hp_frac = match (e.hp, e.max_hp) {
            (Some(hp), Some(m)) if m > 0.0 => Some((hp / m).clamp(0.0, 1.0)),
            _ => None,
        };
        let label = if depth < 24.0 || e.miniboss_wave > 0 || e.elite {
            Some(if e.elite {
                format!("*{}*", tag)
            } else {
                tag.to_string()
            })
        } else {
            None
        };
        list.push(Billboard {
            pos: e.pos,
            depth,
            height_m: h_m,
            sprite,
            color,
            label,
            hp_frac,
            bold: e.hit_flash > 0.0 || e.miniboss_wave > 0 || e.elite,
        });
    }

    // Boss Cumulus
    if let Some(boss) = &app.boss {
        let dx = boss.pos[0] - eye[0];
        let dz = boss.pos[2] - eye[2];
        let depth = dx * fwd[0] + dz * fwd[1];
        if depth > 0.8 && depth < 120.0 {
            let total_hp: f32 = boss.parts.iter().sum();
            let sprite = vec![
                "    .-~===~-.    ",
                "  .(@@@@@@@@@).  ",
                " (@@ (O)(O)(O) @)",
                "  `\\##[CORE]##/' ",
                "    `| | | |'    ",
            ];
            list.push(Billboard {
                pos: [boss.pos[0], boss.pos[1] - 2.5, boss.pos[2]],
                depth,
                height_m: 6.5,
                sprite,
                color: Color::Rgb(235, 95, 255),
                label: Some(format!("CUMULUS ({} SACS)", boss.sacs)),
                hp_frac: Some((total_hp / 600.0).clamp(0.0, 1.0)),
                bold: true,
            });
        }
    }

    // Remote teammates
    for (&pid, p) in &app.players {
        if pid == app.you || p.state == "out" {
            continue;
        }
        let dx = p.pos[0] - eye[0];
        let dz = p.pos[2] - eye[2];
        let depth = dx * fwd[0] + dz * fwd[1];
        if depth <= 0.4 || depth > max_vis + 10.0 {
            continue;
        }
        let rgb = app.catalog.color_rgb(p.color);
        let color = if p.state == "turned" {
            Color::Rgb(255, 70, 70)
        } else {
            Color::Rgb(rgb.0, rgb.1, rgb.2)
        };
        let sprite = if p.state == "downed" {
            vec!["  _o_  ", " /===\\ "]
        } else if p.tarp {
            vec!["/=====\\", "  [O]  ", " /|#|\\ ", "  / \\  "]
        } else {
            vec!["  [O]  ", " /|#|\\ ", "  | |  ", "  / \\  "]
        };
        let tag = if p.state == "downed" {
            format!("!DOWN! {}", p.name)
        } else if p.state == "turned" {
            format!("TURNED {}", p.name)
        } else {
            p.name.clone()
        };
        list.push(Billboard {
            pos: p.pos,
            depth,
            height_m: if p.state == "downed" { 0.8 } else { 1.8 },
            sprite,
            color,
            label: Some(tag),
            hp_frac: Some((p.hp / p.max_hp.max(1.0)).clamp(0.0, 1.0)),
            bold: true,
        });
    }

    // World pickups & supplies
    for p in app.pickups.values() {
        let dx = p.pos[0] - eye[0];
        let dz = p.pos[2] - eye[2];
        let depth = dx * fwd[0] + dz * fwd[1];
        if depth <= 0.3 || depth > 35.0 {
            continue;
        }
        let (glyph, color) = match p.flavor.as_str() {
            "health" => ("[+]", Color::Rgb(255, 105, 130)),
            "suit" | "decon" => ("[S]", Color::Rgb(90, 235, 250)),
            "scrap" | "scrap_large" => ("[$]", Color::Rgb(255, 215, 75)),
            "ammo" | "ammo_box" | "supply" => ("[A]", Color::Rgb(245, 175, 85)),
            "tarp" => ("[T]", Color::Rgb(160, 210, 255)),
            _ => ("[W]", Color::Rgb(160, 255, 145)),
        };
        list.push(Billboard {
            pos: [p.pos[0], p.pos[1] + 0.25, p.pos[2]],
            depth,
            height_m: 0.7,
            sprite: vec![glyph],
            color,
            label: None,
            hp_frac: None,
            bold: true,
        });
    }

    // Airdrop
    if let Some(ad) = &app.airdrop {
        let dx = ad.pos[0] - eye[0];
        let dz = ad.pos[2] - eye[2];
        let depth = dx * fwd[0] + dz * fwd[1];
        if depth > 0.5 && depth < 70.0 {
            let y = ad.pos[1] + ad.descent_left * 5.0;
            list.push(Billboard {
                pos: [ad.pos[0], y, ad.pos[2]],
                depth,
                height_m: 1.8,
                sprite: vec![" /^^^\\ ", " [===] ", " [DRP] "],
                color: Color::Rgb(255, 215, 105),
                label: Some("AIRDROP".into()),
                hp_frac: None,
                bold: true,
            });
        }
    }

    // Projectiles / deployables (Shield dome, grenades, sandbags, rods)
    for eff in app.effects.values() {
        let dx = eff.pos[0] - eye[0];
        let dz = eff.pos[2] - eye[2];
        let depth = dx * fwd[0] + dz * fwd[1];
        if depth <= 0.3 || depth > 55.0 {
            continue;
        }
        let (sprite, color, h_m) = if eff.id == "shield_dome" && eff.deployed {
            (
                vec!["  .-~~~-.  ", " /  ___  \\ ", "|  (DOM)  |", " \\_______/ "],
                Color::Rgb(90, 245, 255),
                3.2,
            )
        } else if eff.id == "frag" {
            (vec!["(*)"], Color::Rgb(255, 150, 60), 0.5)
        } else {
            (vec!["[o]"], Color::Rgb(190, 230, 130), 0.8)
        };
        list.push(Billboard {
            pos: eff.pos,
            depth,
            height_m: h_m,
            sprite,
            color,
            label: None,
            hp_frac: None,
            bold: true,
        });
    }

    // Blasts
    for b in &app.blasts {
        let dx = b.pos[0] - eye[0];
        let dz = b.pos[2] - eye[2];
        let depth = dx * fwd[0] + dz * fwd[1];
        if depth > 0.3 && depth < 60.0 {
            list.push(Billboard {
                pos: b.pos,
                depth,
                height_m: b.size * 0.7,
                sprite: vec![" \\ | / ", "- *#* -", " / | \\ "],
                color: Color::Rgb(b.rgb.0, b.rgb.1, b.rgb.2),
                label: None,
                hp_frac: None,
                bold: true,
            });
        }
    }

    // Squad Pings
    for ping in &app.pings {
        let dx = ping.pos[0] - eye[0];
        let dz = ping.pos[2] - eye[2];
        let depth = dx * fwd[0] + dz * fwd[1];
        if depth > 0.5 && depth < 90.0 {
            list.push(Billboard {
                pos: [ping.pos[0], ping.pos[1] + 1.2, ping.pos[2]],
                depth,
                height_m: 1.2,
                sprite: vec![" <V> "],
                color: Color::Rgb(255, 230, 90),
                label: Some(ping.kind.to_uppercase()),
                hp_frac: None,
                bold: true,
            });
        }
    }

    // Sort far -> near
    list.sort_by(|a, b| b.depth.partial_cmp(&a.depth).unwrap_or(std::cmp::Ordering::Equal));

    let w = canvas.width;
    let h = canvas.height;

    for bb in list {
        let dx = bb.pos[0] - eye[0];
        let dz = bb.pos[2] - eye[2];
        let rx = dx * right[0] + dz * right[1];
        let ndc_x = (rx / bb.depth) / half_tan;
        if ndc_x.abs() > 1.35 {
            continue;
        }
        let cx = ((ndc_x * 0.5 + 0.5) * w as f32) as isize;
        let bot_y = (horizon - (bb.pos[1] - eye[1]) * proj_y / bb.depth) as isize;
        let top_y = (horizon - (bb.pos[1] + bb.height_m - eye[1]) * proj_y / bb.depth) as isize;
        let span_h = (bot_y - top_y).max(1) as usize;

        if span_h <= 2 {
            // Distant compact glyph
            let col = cx.clamp(0, (w as isize) - 1) as usize;
            if bb.depth < z_buf[col] {
                let ch = bb
                    .sprite
                    .first()
                    .and_then(|r| r.trim().chars().next())
                    .unwrap_or('o');
                let y = bot_y.clamp(0, (h as isize) - 1) as usize;
                canvas.set_fg(col, y, ch, bb.color, bb.bold);
            }
            continue;
        }

        let src_h = bb.sprite.len().max(1);
        let src_w = bb.sprite.iter().map(|s| s.len()).max().unwrap_or(1);
        let draw_w = ((span_h as f32) * (src_w as f32 / src_h as f32) * 1.15)
            .round()
            .clamp(1.0, (w as f32) * 0.55) as usize;
        let left_x = cx - (draw_w as isize) / 2;

        for sy in 0..span_h {
            let py = top_y + sy as isize;
            if py < 0 || py >= h as isize {
                continue;
            }
            let src_row = (sy * src_h / span_h).min(src_h - 1);
            let row_str = bb.sprite[src_row];
            let row_bytes = row_str.as_bytes();
            for sx in 0..draw_w {
                let px = left_x + sx as isize;
                if px < 0 || px >= w as isize {
                    continue;
                }
                if bb.depth >= z_buf[px as usize] {
                    continue;
                }
                let src_col = (sx * row_bytes.len() / draw_w).min(row_bytes.len().saturating_sub(1));
                let ch = row_bytes.get(src_col).copied().unwrap_or(b' ') as char;
                if ch != ' ' {
                    canvas.set_fg(px as usize, py as usize, ch, bb.color, bb.bold);
                }
            }
        }

        // Label & HP bar above sprite
        let center_col = cx.clamp(0, (w as isize) - 1) as usize;
        if bb.depth < z_buf[center_col] {
            if let Some(hp) = bb.hp_frac {
                let bar_w = 6usize;
                let filled = ((hp * bar_w as f32).round() as usize).min(bar_w);
                let bar = format!("[{}{}]", "=".repeat(filled), "-".repeat(bar_w - filled));
                let bx = cx - (bar.len() as isize) / 2;
                canvas.draw_text(bx, top_y - 1, &bar, Color::Rgb(255, 110, 110), true);
            }
            if let Some(lbl) = &bb.label {
                let lx = cx - (lbl.len() as isize) / 2;
                let ly = if bb.hp_frac.is_some() { top_y - 2 } else { top_y - 1 };
                canvas.draw_text(lx, ly, lbl, bb.color, true);
            }
        }
    }

    // Shot tracers (project endpoints and draw short glowing streak)
    for tr in &app.tracers {
        let mid = [
            (tr.origin[0] + tr.end[0]) * 0.5,
            (tr.origin[1] + tr.end[1]) * 0.5,
            (tr.origin[2] + tr.end[2]) * 0.5,
        ];
        for pt in [mid, tr.end] {
            let dx = pt[0] - eye[0];
            let dz = pt[2] - eye[2];
            let depth = dx * fwd[0] + dz * fwd[1];
            if depth <= 0.4 || depth > max_vis {
                continue;
            }
            let rx = dx * right[0] + dz * right[1];
            let ndc_x = (rx / depth) / half_tan;
            if ndc_x.abs() > 1.0 {
                continue;
            }
            let px = ((ndc_x * 0.5 + 0.5) * w as f32) as usize;
            let py = (horizon - (pt[1] - eye[1]) * proj_y / depth) as isize;
            if px < w && py >= 0 && py < h as isize && depth < z_buf[px] + 0.5 {
                let (ch, col) = if tr.impact == 2 {
                    ('*', Color::Rgb(255, 220, 80))
                } else {
                    ('-', Color::Rgb(255, 240, 160))
                };
                canvas.set_fg(px, py as usize, ch, col, true);
            }
        }
    }
}

fn enemy_visual(kind: i32, miniboss_wave: i32) -> (Vec<&'static str>, Color, f32, &'static str) {
    if miniboss_wave > 0 {
        return (
            vec![
                "   \\^/   ",
                "  /@@@\\  ",
                " |@O O@| ",
                " /|###|\\ ",
                "  || ||  ",
            ],
            Color::Rgb(255, 110, 230),
            2.7,
            "CLOUDBURST",
        );
    }
    match kind {
        0 => (
            // Drip
            vec!["  (o)  ", " /|#|\\ ", "  | |  ", "  / \\  "],
            Color::Rgb(155, 235, 95),
            1.75,
            "DRIP",
        ),
        1 => (
            // Gutter (crouching hunter)
            vec!["  /\"\\  ", " <o_o> ", " /===\\ ", " /   \\ "],
            Color::Rgb(255, 168, 72),
            1.35,
            "GUTTER",
        ),
        2 => (
            // Mister (bloated spore thrower)
            vec!["  (O)  ", " (###) ", "/(@#@)\\", "  / \\  "],
            Color::Rgb(86, 228, 195),
            1.95,
            "MISTER",
        ),
        3 => (
            // Sleet (fast slim runner)
            vec!["  ^o^  ", " /| |\\ ", "  / \\  "],
            Color::Rgb(135, 235, 255),
            1.4,
            "SLEET",
        ),
        4 => (
            // Hailstone (armored heavy)
            vec![
                "  [===]  ",
                " /|O O|\\ ",
                "||#####||",
                " ||   || ",
            ],
            Color::Rgb(185, 210, 245),
            2.3,
            "HAILSTONE",
        ),
        5 => (
            // Undertow
            vec!["  ~O~  ", " ~|#|~ ", " /~~~\\ ", " ~ / \\ ~"],
            Color::Rgb(80, 165, 255),
            1.85,
            "UNDERTOW",
        ),
        6 => (
            // Static
            vec!["  \\Z/  ", " /|*|\\ ", "  /Z\\  "],
            Color::Rgb(255, 242, 95),
            1.75,
            "STATIC",
        ),
        7 => (
            // Smog
            vec!["  .~.  ", " (@@@) ", " /|#|\\ ", "  | |  "],
            Color::Rgb(180, 155, 220),
            2.05,
            "SMOG",
        ),
        8 => (
            // Thunderhead
            vec![
                " \\\\=// ",
                " (O_O) ",
                " /|Z|\\ ",
                "  / \\  ",
            ],
            Color::Rgb(205, 130, 255),
            2.15,
            "THUNDER",
        ),
        _ => (vec![" (o) ", " /|\\ ", " / \\ "], Color::Rgb(200, 220, 120), 1.7, "INFECTED"),
    }
}

fn draw_crosshair(app: &GameApp, canvas: &mut AsciiCanvas) {
    let cx = canvas.width / 2;
    let cy = canvas.height / 2;
    if app.hit_marker_ttl > 0.0 {
        let col = if app.hit_marker_crit {
            Color::Rgb(255, 220, 60)
        } else {
            Color::Rgb(255, 75, 75)
        };
        if cx > 0 && cy > 0 {
            canvas.set_fg(cx - 1, cy - 1, '\\', col, true);
            canvas.set_fg(cx + 1, cy - 1, '/', col, true);
            canvas.set_fg(cx - 1, cy + 1, '/', col, true);
            canvas.set_fg(cx + 1, cy + 1, '\\', col, true);
        }
        canvas.set_fg(cx, cy, 'X', col, true);
    } else if app.input.ads {
        if cx > 1 {
            canvas.set_fg(cx - 1, cy, '[', Color::Rgb(110, 255, 225), true);
            canvas.set_fg(cx + 1, cy, ']', Color::Rgb(110, 255, 225), true);
        }
        canvas.set_fg(cx, cy, '+', Color::Rgb(255, 255, 255), true);
    } else {
        canvas.set_fg(cx, cy, '+', Color::Rgb(235, 255, 235), true);
    }
}

fn draw_weapon_viewmodel(app: &GameApp, canvas: &mut AsciiCanvas) {
    if canvas.width < 36 || canvas.height < 12 {
        return;
    }

    let held_id = if !app.inventory.selected_pouch.is_empty() {
        app.inventory.selected_pouch.as_str()
    } else {
        app.inventory
            .held_item()
            .map(|i| i.id.as_str())
            .unwrap_or("")
    };

    let (art, col): (&[&str], Color) = match held_id {
        "pump_shotgun" | "rock_salt" => (
            &[
                "      _____     ",
                "  ___/=====\\___ ",
                " /===[PUMP ]===\\",
                "   \\__________/ ",
            ],
            Color::Rgb(210, 200, 185),
        ),
        "nail_driver" | "leaky_nailgun" => (
            &[
                "    .-------.   ",
                "  __|NAIL===|=> ",
                " /==|_______|   ",
                "    //  ||      ",
            ],
            Color::Rgb(245, 190, 95),
        ),
        "service_revolver" | "lucky_penny_revolver" => (
            &[
                "     .====--    ",
                "   _(o)===\\     ",
                "  /___/         ",
            ],
            Color::Rgb(220, 225, 235),
        ),
        "spray_rifle" | "hunting_rifle" | "disruptor" => (
            &[
                "   __[===]____  ",
                " _/===========\\=",
                "/___/  ||  \\__\\ ",
            ],
            Color::Rgb(185, 215, 225),
        ),
        "frag" => (
            &[
                "    _._   ",
                "   (###)  ",
                "    `-'   ",
            ],
            Color::Rgb(255, 165, 80),
        ),
        "shield_dome" => (
            &[
                "   .~~~.  ",
                "  (DOME ) ",
                "   `---'  ",
            ],
            Color::Rgb(95, 245, 255),
        ),
        "" => (
            &[
                "   ___    ",
                "  /   \\   ",
            ],
            Color::Rgb(165, 175, 185),
        ),
        _ => (
            &[
                "   .=======.    ",
                "  /|=======|=>  ",
                " /_/   ||       ",
            ],
            Color::Rgb(195, 225, 195),
        ),
    };

    let bob_x = (app.walk_phase.cos() * 1.4).round() as isize;
    let bob_y = (app.walk_phase.sin().abs() * 1.1).round() as isize;
    let recoil_y = (app.view_recoil * 2.2).round() as isize;

    let base_x = (canvas.width as isize) - 22 + bob_x;
    let base_y = (canvas.height as isize) - (art.len() as isize) + bob_y + recoil_y - 1;

    // Muzzle flash just above-left of barrel
    if app.muzzle_flash_ttl > 0.0 {
        let fx = base_x - 2;
        let fy = base_y - 2;
        canvas.draw_text(fx, fy, " \\|/ ", Color::Rgb(255, 245, 120), true);
        canvas.draw_text(fx, fy + 1, "-*#*-", Color::Rgb(255, 195, 65), true);
        canvas.draw_text(fx, fy + 2, " /|\\ ", Color::Rgb(255, 140, 45), true);
    }

    for (row_i, line) in art.iter().enumerate() {
        let py = base_y + row_i as isize;
        if py < 0 || py >= canvas.height as isize {
            continue;
        }
        // Find first and last non-space char so interior spaces occlude walls/rain behind the gun
        let first_non_space = line.find(|c| c != ' ');
        let last_non_space = line.rfind(|c| c != ' ');
        for (col_i, ch) in line.chars().enumerate() {
            let inside = match (first_non_space, last_non_space) {
                (Some(a), Some(b)) => col_i >= a && col_i <= b,
                _ => false,
            };
            if !inside {
                continue;
            }
            let px = base_x + col_i as isize;
            if px >= 0 && px < canvas.width as isize {
                canvas.set(
                    px as usize,
                    py as usize,
                    ch,
                    col,
                    Color::Rgb(16, 18, 24),
                    true,
                );
            }
        }
    }
}

fn lerp_rgb(a: (u8, u8, u8), b: (u8, u8, u8), t: f32) -> (u8, u8, u8) {
    let t = t.clamp(0.0, 1.0);
    (
        (a.0 as f32 + (b.0 as f32 - a.0 as f32) * t) as u8,
        (a.1 as f32 + (b.1 as f32 - a.1 as f32) * t) as u8,
        (a.2 as f32 + (b.2 as f32 - a.2 as f32) * t) as u8,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::game::state::{ConnectConfig, EnemyEntity};
    use crate::protocol::frame::Encoding;

    #[test]
    fn raycaster_renders_pinecrest_nonempty() {
        let cfg = ConnectConfig {
            use_tcp: false,
            ws_url: "ws://127.0.0.1:7780/".into(),
            tcp_addr: "127.0.0.1:7781".into(),
            enc: Encoding::Json,
            name: "Test".into(),
            code: String::new(),
            color: 0,
            skin: 0,
        };
        let mut app = GameApp::new(cfg);
        app.current_map = app.catalog.map_data.get("pinecrest").cloned();
        app.my_pos = [-2.0, 0.0, 0.5];
        app.my_yaw = std::f32::consts::PI; // face South toward Block A/B awnings & storefronts
        app.storm_intensity = 0.5;
        app.phase = 2;
        app.enemies.insert(
            1,
            EnemyEntity {
                net_id: 1,
                kind: 0,
                pos: [-2.0, 0.0, 7.0],
                target_pos: [-2.0, 0.0, 7.0],
                yaw: 0.0,
                small: false,
                elite: false,
                miniboss_wave: 0,
                hp: Some(60.0),
                max_hp: Some(60.0),
                hit_flash: 0.0,
                tell_timer: 0.0,
            },
        );
        let area = Rect::new(0, 0, 80, 24);
        let mut buf = Buffer::empty(area);
        render_fps_viewport(&app, area, &mut buf, 1.0);
        let non_space = buf
            .content()
            .iter()
            .filter(|c| c.symbol() != " ")
            .count();
        assert!(non_space > 200, "expected rich ASCII viewport, got {} chars", non_space);
    }
}

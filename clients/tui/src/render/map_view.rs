use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};
use ratatui::widgets::{Block, Borders, Widget};

use crate::game::data::{ShelterShape, SolidKind};
use crate::game::state::GameApp;

pub fn render_topdown_map(app: &GameApp, area: Rect, buf: &mut Buffer) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Rgb(95, 200, 195)))
        .title(format!(
            " TACTICAL MAP: {}  [N ↑]  POS ({:.1}, {:.1}) ",
            app.current_map
                .as_ref()
                .map(|m| m.name.as_str())
                .unwrap_or("UNKNOWN"),
            app.my_pos[0],
            app.my_pos[2]
        ));
    let inner = block.inner(area);
    block.render(area, buf);

    if inner.width < 10 || inner.height < 6 {
        return;
    }
    let Some(map) = &app.current_map else {
        return;
    };

    let world_min_x = map.play_min[0];
    let world_max_x = map.play_max[0];
    let world_min_z = map.play_min[1];
    let world_max_z = map.play_max[1];
    let span_x = (world_max_x - world_min_x).max(1.0);
    let span_z = (world_max_z - world_min_z).max(1.0);

    let to_screen = |wx: f32, wz: f32| -> Option<(u16, u16)> {
        let nx = (wx - world_min_x) / span_x;
        let nz = (wz - world_min_z) / span_z;
        if !(0.0..=1.0).contains(&nx) || !(0.0..=1.0).contains(&nz) {
            return None;
        }
        let sx = inner.x + (nx * (inner.width.saturating_sub(1)) as f32).round() as u16;
        let sy = inner.y + (nz * (inner.height.saturating_sub(1)) as f32).round() as u16;
        Some((sx, sy))
    };

    // Subtle grid background
    for y in inner.y..inner.y + inner.height {
        for x in inner.x..inner.x + inner.width {
            let ch = if (x - inner.x) % 8 == 0 && (y - inner.y) % 4 == 0 {
                '+'
            } else {
                '·'
            };
            buf[(x, y)]
                .set_char(ch)
                .set_style(Style::default().fg(Color::Rgb(42, 48, 60)));
        }
    }

    // Solid building footprints
    for b in &map.boxes {
        if b.kind != SolidKind::BuildingWall {
            continue;
        }
        let x0 = b.center[0] - b.half_size[0];
        let x1 = b.center[0] + b.half_size[0];
        let z0 = b.center[2] - b.half_size[2];
        let z1 = b.center[2] + b.half_size[2];
        if let (Some((sx0, sy0)), Some((sx1, sy1))) = (to_screen(x0, z0), to_screen(x1, z1)) {
            for y in sy0..=sy1 {
                for x in sx0..=sx1 {
                    buf[(x, y)]
                        .set_char('#')
                        .set_style(Style::default().fg(Color::Rgb(130, 120, 145)));
                }
            }
        }
    }

    // Shelter dry zones (boxes & tree canopies)
    for sh in &map.shelters {
        match sh.shape {
            ShelterShape::Box { size } => {
                let x0 = sh.pos[0] - size[0] * 0.5;
                let x1 = sh.pos[0] + size[0] * 0.5;
                let z0 = sh.pos[2] - size[2] * 0.5;
                let z1 = sh.pos[2] + size[2] * 0.5;
                if let (Some((sx0, sy0)), Some((sx1, sy1))) = (to_screen(x0, z0), to_screen(x1, z1))
                {
                    for y in sy0..=sy1 {
                        for x in sx0..=sx1 {
                            buf[(x, y)].set_char('=').set_style(
                                Style::default()
                                    .fg(Color::Rgb(95, 225, 210))
                                    .bg(Color::Rgb(18, 46, 48)),
                            );
                        }
                    }
                }
            }
            ShelterShape::Cylinder { .. } => {
                if let Some((sx, sy)) = to_screen(sh.pos[0], sh.pos[2]) {
                    let (ch, col) = if sh.is_tree_canopy {
                        ('T', Color::Rgb(70, 175, 92))
                    } else {
                        ('O', Color::Rgb(100, 215, 225))
                    };
                    buf[(sx, sy)].set_char(ch).set_style(Style::default().fg(col));
                }
            }
        }
    }

    // Active puddles
    for p in &map.puddles {
        let growth = app.puddle_growth.get(&p.sync_key).copied().unwrap_or(0.0);
        let r = p.max_radius * growth;
        let active = r > 0.25;
        let draw_r = if active { r } else { p.max_radius * 0.3 };
        let steps = 4;
        for iz in -steps..=steps {
            for ix in -steps..=steps {
                let fx = (ix as f32 / steps as f32) * draw_r;
                let fz = (iz as f32 / steps as f32) * draw_r;
                if fx * fx + fz * fz <= draw_r * draw_r {
                    if let Some((sx, sy)) = to_screen(p.pos[0] + fx, p.pos[2] + fz) {
                        if active {
                            buf[(sx, sy)].set_char('~').set_style(
                                Style::default()
                                    .fg(Color::Rgb(155, 255, 70))
                                    .bg(Color::Rgb(28, 60, 20)),
                            );
                        } else {
                            buf[(sx, sy)]
                                .set_char('~')
                                .set_style(Style::default().fg(Color::Rgb(65, 95, 75)));
                        }
                    }
                }
            }
        }
    }

    // Vending stations & Decon showers
    for v in &map.vending_stations {
        if let Some((sx, sy)) = to_screen(v.pos[0], v.pos[2]) {
            buf[(sx, sy)].set_char('V').set_style(
                Style::default()
                    .fg(Color::Rgb(255, 215, 75))
                    .add_modifier(Modifier::BOLD),
            );
        }
    }
    for d in &map.decon_showers {
        if let Some((sx, sy)) = to_screen(d.pos[0], d.pos[2]) {
            buf[(sx, sy)].set_char('D').set_style(
                Style::default()
                    .fg(Color::Rgb(90, 245, 245))
                    .add_modifier(Modifier::BOLD),
            );
        }
    }

    // Pickups & Airdrop
    for p in app.pickups.values() {
        if let Some((sx, sy)) = to_screen(p.pos[0], p.pos[2]) {
            let ch = if p.flavor == "scrap" || p.flavor == "scrap_large" {
                '$'
            } else if p.flavor == "health" {
                '+'
            } else {
                '*'
            };
            buf[(sx, sy)]
                .set_char(ch)
                .set_style(Style::default().fg(Color::Rgb(240, 220, 120)));
        }
    }
    if let Some(ad) = &app.airdrop {
        if let Some((sx, sy)) = to_screen(ad.pos[0], ad.pos[2]) {
            buf[(sx, sy)].set_char('A').set_style(
                Style::default()
                    .fg(Color::Rgb(255, 200, 60))
                    .add_modifier(Modifier::BOLD),
            );
        }
    }

    // Enemies & Boss
    for e in app.enemies.values() {
        if let Some((sx, sy)) = to_screen(e.pos[0], e.pos[2]) {
            let ch = if e.miniboss_wave > 0 {
                'C'
            } else {
                match e.kind {
                    0 => 'd',
                    1 => 'g',
                    2 => 'm',
                    3 => 's',
                    4 => 'H',
                    5 => 'u',
                    6 => 'z',
                    7 => 'o',
                    8 => 'T',
                    _ => 'e',
                }
            };
            buf[(sx, sy)].set_char(ch).set_style(
                Style::default()
                    .fg(Color::Rgb(255, 85, 85))
                    .add_modifier(Modifier::BOLD),
            );
        }
    }
    if let Some(boss) = &app.boss {
        if let Some((sx, sy)) = to_screen(boss.pos[0], boss.pos[2]) {
            buf[(sx, sy)].set_char('@').set_style(
                Style::default()
                    .fg(Color::Rgb(245, 95, 255))
                    .add_modifier(Modifier::BOLD),
            );
        }
    }

    // Teammates
    for (&pid, p) in &app.players {
        if pid == app.you || p.state == "out" {
            continue;
        }
        if let Some((sx, sy)) = to_screen(p.pos[0], p.pos[2]) {
            let rgb = app.catalog.color_rgb(p.color);
            buf[(sx, sy)].set_char('P').set_style(
                Style::default()
                    .fg(Color::Rgb(rgb.0, rgb.1, rgb.2))
                    .add_modifier(Modifier::BOLD),
            );
        }
    }

    // FOV cone lines from local player
    for step in 1..=6 {
        let dist = step as f32 * 3.0;
        for offset in [-0.45f32, 0.45f32] {
            let ang = app.my_yaw + offset;
            let px = app.my_pos[0] - ang.sin() * dist;
            let pz = app.my_pos[2] - ang.cos() * dist;
            if let Some((sx, sy)) = to_screen(px, pz) {
                buf[(sx, sy)]
                    .set_char('.')
                    .set_style(Style::default().fg(Color::Rgb(255, 255, 160)));
            }
        }
    }

    // Local player directional arrow
    if let Some((sx, sy)) = to_screen(app.my_pos[0], app.my_pos[2]) {
        let arrow = yaw_to_arrow(app.my_yaw);
        buf[(sx, sy)].set_char(arrow).set_style(
            Style::default()
                .fg(Color::Rgb(255, 255, 90))
                .bg(Color::Rgb(40, 40, 15))
                .add_modifier(Modifier::BOLD),
        );
    }

    // Legend bar at bottom inside map
    let legend = " [=]Shelter [T]Tree [~]Puddle [V]Vend [D]Decon [d/g/H/@]Hostiles [P]Ally [^]You ";
    let ly = inner.y + inner.height.saturating_sub(1);
    for (i, ch) in legend.chars().enumerate() {
        if inner.x + (i as u16) < inner.x + inner.width {
            buf[(inner.x + i as u16, ly)].set_char(ch).set_style(
                Style::default()
                    .fg(Color::Rgb(210, 225, 230))
                    .bg(Color::Rgb(22, 26, 36)),
            );
        }
    }
}

/// Compact radar overlay drawn in top-right corner of the 3D FPS viewport.
pub fn render_corner_minimap(app: &GameApp, viewport: Rect, buf: &mut Buffer) {
    if viewport.width < 52 || viewport.height < 14 {
        return;
    }
    let mw = 24u16;
    let mh = 11u16;
    let rect = Rect::new(viewport.x + viewport.width - mw - 1, viewport.y + 1, mw, mh);

    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Rgb(95, 195, 190)))
        .style(Style::default().bg(Color::Rgb(14, 18, 24)))
        .title(" RADAR N↑ ");
    let inner = block.inner(rect);
    block.render(rect, buf);

    for y in inner.y..inner.y + inner.height {
        for x in inner.x..inner.x + inner.width {
            buf[(x, y)]
                .set_char(' ')
                .set_style(Style::default().bg(Color::Rgb(14, 18, 24)));
        }
    }

    let range_m = 34.0f32;
    let cx = inner.x as f32 + (inner.width as f32 - 1.0) * 0.5;
    let cy = inner.y as f32 + (inner.height as f32 - 1.0) * 0.5;
    let scale_x = (inner.width as f32 * 0.5) / range_m;
    let scale_z = (inner.height as f32 * 0.5) / range_m;

    let map_pt = |wx: f32, wz: f32| -> Option<(u16, u16)> {
        let dx = wx - app.my_pos[0];
        let dz = wz - app.my_pos[2];
        let sx = (cx + dx * scale_x).round() as i32;
        let sy = (cy + dz * scale_z).round() as i32;
        if sx >= inner.x as i32
            && sx < (inner.x + inner.width) as i32
            && sy >= inner.y as i32
            && sy < (inner.y + inner.height) as i32
        {
            Some((sx as u16, sy as u16))
        } else {
            None
        }
    };

    if let Some(map) = &app.current_map {
        for sh in &map.shelters {
            if let Some((sx, sy)) = map_pt(sh.pos[0], sh.pos[2]) {
                let (ch, col) = if sh.is_tree_canopy {
                    ('t', Color::Rgb(60, 145, 78))
                } else {
                    ('=', Color::Rgb(85, 200, 195))
                };
                buf[(sx, sy)].set_char(ch).set_style(Style::default().fg(col).bg(Color::Rgb(14, 18, 24)));
            }
        }
        for p in &map.puddles {
            let g = app.puddle_growth.get(&p.sync_key).copied().unwrap_or(0.0);
            if p.max_radius * g > 0.25 {
                if let Some((sx, sy)) = map_pt(p.pos[0], p.pos[2]) {
                    buf[(sx, sy)].set_char('~').set_style(
                        Style::default()
                            .fg(Color::Rgb(145, 255, 75))
                            .bg(Color::Rgb(14, 18, 24)),
                    );
                }
            }
        }
        for v in &map.vending_stations {
            if let Some((sx, sy)) = map_pt(v.pos[0], v.pos[2]) {
                buf[(sx, sy)].set_char('V').set_style(
                    Style::default()
                        .fg(Color::Rgb(255, 215, 75))
                        .bg(Color::Rgb(14, 18, 24)),
                );
            }
        }
        for d in &map.decon_showers {
            if let Some((sx, sy)) = map_pt(d.pos[0], d.pos[2]) {
                buf[(sx, sy)].set_char('D').set_style(
                    Style::default()
                        .fg(Color::Rgb(90, 245, 245))
                        .bg(Color::Rgb(14, 18, 24)),
                );
            }
        }
    }

    for e in app.enemies.values() {
        if let Some((sx, sy)) = map_pt(e.pos[0], e.pos[2]) {
            buf[(sx, sy)].set_char('!').set_style(
                Style::default()
                    .fg(Color::Rgb(255, 80, 80))
                    .bg(Color::Rgb(14, 18, 24))
                    .add_modifier(Modifier::BOLD),
            );
        }
    }
    if let Some(boss) = &app.boss {
        if let Some((sx, sy)) = map_pt(boss.pos[0], boss.pos[2]) {
            buf[(sx, sy)].set_char('@').set_style(
                Style::default()
                    .fg(Color::Rgb(245, 95, 255))
                    .bg(Color::Rgb(14, 18, 24))
                    .add_modifier(Modifier::BOLD),
            );
        }
    }
    for (&pid, p) in &app.players {
        if pid == app.you || p.state == "out" {
            continue;
        }
        if let Some((sx, sy)) = map_pt(p.pos[0], p.pos[2]) {
            let rgb = app.catalog.color_rgb(p.color);
            buf[(sx, sy)].set_char('P').set_style(
                Style::default()
                    .fg(Color::Rgb(rgb.0, rgb.1, rgb.2))
                    .bg(Color::Rgb(14, 18, 24))
                    .add_modifier(Modifier::BOLD),
            );
        }
    }

    let px = cx.round() as u16;
    let py = cy.round() as u16;
    buf[(px, py)].set_char(yaw_to_arrow(app.my_yaw)).set_style(
        Style::default()
            .fg(Color::Rgb(255, 255, 95))
            .bg(Color::Rgb(14, 18, 24))
            .add_modifier(Modifier::BOLD),
    );
}

fn yaw_to_arrow(yaw: f32) -> char {
    // Godot: yaw=0 -> -Z (North, up on screen), yaw=+PI/2 -> -X (West, left)
    let mut deg = (-yaw.to_degrees()).rem_euclid(360.0);
    if deg < 0.0 {
        deg += 360.0;
    }
    match deg as u32 {
        315..=360 | 0..=44 => '^',
        45..=134 => '>',
        135..=224 => 'v',
        _ => '<',
    }
}

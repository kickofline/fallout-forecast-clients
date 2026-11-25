use ratatui::layout::{Alignment, Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, Gauge, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::game::state::{GameApp, Screen, ViewMode};
use crate::render::map_view::{render_corner_minimap, render_topdown_map};
use crate::render::raycaster::render_fps_viewport;

pub fn draw(frame: &mut Frame, app: &GameApp, time_secs: f32) {
    match app.screen {
        Screen::Title => draw_title(frame, app),
        Screen::Connecting => draw_connecting(frame, app),
        Screen::Lobby => draw_lobby(frame, app),
        Screen::Loading => draw_loading(frame, app),
        Screen::InRun => draw_in_run(frame, app, time_secs),
        Screen::Results => draw_results(frame, app),
        Screen::Disconnected => draw_disconnected(frame, app),
    }

    if app.show_help {
        draw_help_overlay(frame);
    }
}

fn draw_title(frame: &mut Frame, app: &GameApp) {
    let area = frame.area();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(8),
            Constraint::Min(14),
            Constraint::Length(3),
        ])
        .split(area);

    let logo = vec![
        Line::from(Span::styled(
            "  _____ _   _    _    ___  _   _ _____   _____ ___  ___ ___ ___   _   ___ _____ ",
            Style::default().fg(Color::Rgb(115, 240, 210)).add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(
            " |  ___/_\\ | |  | |  / _ \\| | | |_   _| |  ___/ _ \\| _ \\ __/ __| /_\\ / __|_   _|",
            Style::default().fg(Color::Rgb(150, 245, 160)).add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(
            " | |_ / _ \\| |__| |_| (_) | |_| | | |   | |_ | (_) |   / _| (__ / _ \\\\__ \\ | |  ",
            Style::default().fg(Color::Rgb(245, 220, 95)).add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(
            " |_| /_/ \\_\\____|____\\___/ \\___/  |_|   |_|   \\___/|_|_\\___\\___/_/ \\_\\___/ |_|  ",
            Style::default().fg(Color::Rgb(255, 130, 105)).add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(Span::styled(
            "   OPEN PROTOCOL v1 · FULL-TIER RUST ASCII CLIENT (GAME PROTOCOL 19)",
            Style::default().fg(Color::Rgb(170, 195, 215)),
        )),
    ];
    let header = Paragraph::new(logo)
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::BOTTOM).border_style(Style::default().fg(Color::DarkGray)));
    frame.render_widget(header, chunks[0]);

    let form_area = centered_rect(72, 85, chunks[1]);
    let color_rgb = app.catalog.color_rgb(app.config.color);
    let fields: Vec<(&str, String)> = vec![
        (
            "Transport ",
            if app.config.use_tcp {
                "< Raw TCP (length-prefixed) >".into()
            } else {
                "< WebSocket (ws/wss) >".into()
            },
        ),
        (
            "Endpoint  ",
            if app.config.use_tcp {
                app.config.tcp_addr.clone()
            } else {
                app.config.ws_url.clone()
            },
        ),
        (
            "Encoding  ",
            format!("< {} >", app.config.enc.as_str().to_uppercase()),
        ),
        ("Callsign  ", app.config.name.clone()),
        ("Join Code ", app.config.code.clone()),
        (
            "Suit Color",
            format!(
                "< {} [{}] >",
                app.catalog.color_name(app.config.color),
                app.config.color
            ),
        ),
        (
            "Suit Skin ",
            format!(
                "< {} [{}] >",
                app.catalog.skin_name(app.config.skin),
                app.config.skin
            ),
        ),
    ];

    let items: Vec<ListItem> = fields
        .iter()
        .enumerate()
        .map(|(i, (label, val))| {
            let focused = i == app.title_field;
            let prefix = if focused { "▶ " } else { "  " };
            let val_style = if i == 5 {
                Style::default()
                    .fg(Color::Rgb(color_rgb.0, color_rgb.1, color_rgb.2))
                    .add_modifier(Modifier::BOLD)
            } else if focused {
                Style::default()
                    .fg(Color::Rgb(255, 240, 120))
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };
            let cursor = if focused && matches!(i, 1 | 3 | 4) { "▌" } else { "" };
            ListItem::new(Line::from(vec![
                Span::styled(
                    format!("{}{}: ", prefix, label),
                    if focused {
                        Style::default().fg(Color::Rgb(115, 240, 210)).add_modifier(Modifier::BOLD)
                    } else {
                        Style::default().fg(Color::Gray)
                    },
                ),
                Span::styled(format!("{}{}", val, cursor), val_style),
            ]))
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(110, 220, 200)))
            .title(" CONNECTION SETUP "),
    );
    frame.render_widget(list, form_area);

    let footer = Paragraph::new(
        " [↑/↓/Tab] Select Field   [←/→] Cycle Mode/Color/Skin   [Type/Backspace] Edit   [Enter] CONNECT   [Esc/Ctrl+C] Quit ",
    )
    .alignment(Alignment::Center)
    .style(Style::default().fg(Color::Rgb(160, 210, 205)))
    .block(Block::default().borders(Borders::TOP).border_style(Style::default().fg(Color::DarkGray)));
    frame.render_widget(footer, chunks[2]);
}

fn draw_connecting(frame: &mut Frame, app: &GameApp) {
    let box_area = centered_rect(64, 30, frame.area());
    let p = Paragraph::new(vec![
        Line::from(""),
        Line::from(Span::styled(
            "ESTABLISHING OPEN PROTOCOL SESSION...",
            Style::default().fg(Color::Rgb(115, 240, 210)).add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(app.status_line.as_str()),
        Line::from(""),
        Line::from(Span::styled("Press [Esc] to cancel", Style::default().fg(Color::DarkGray))),
    ])
    .alignment(Alignment::Center)
    .block(Block::default().borders(Borders::ALL).title(" CONNECTING "));
    frame.render_widget(p, box_area);
}

fn draw_lobby(frame: &mut Frame, app: &GameApp) {
    let area = frame.area();
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(12),
            Constraint::Length(9),
            Constraint::Length(3),
        ])
        .split(area);

    // Header bar
    let hdr = Paragraph::new(Line::from(vec![
        Span::styled(" FALLOUT FORECAST LOBBY ", Style::default().fg(Color::Black).bg(Color::Rgb(110, 235, 210)).add_modifier(Modifier::BOLD)),
        Span::raw("  "),
        Span::styled(app.config.endpoint().display(), Style::default().fg(Color::White)),
        Span::raw("  |  "),
        Span::styled(format!("ENC: {}", app.config.enc.as_str().to_uppercase()), Style::default().fg(Color::Rgb(255, 220, 95))),
        Span::raw("  |  "),
        Span::styled(format!("PEER #{}", app.you), Style::default().fg(Color::Rgb(150, 215, 255))),
        Span::raw("  |  "),
        Span::styled(format!("RTT {:.0}ms", app.rtt_ms), Style::default().fg(Color::Rgb(140, 245, 145))),
    ]))
    .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Rgb(85, 175, 170))));
    frame.render_widget(hdr, rows[0]);

    // Middle split: Left = Squad Roster, Right = Map Voting
    let cols = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(48), Constraint::Percentage(52)])
        .split(rows[1]);

    let mut roster_items: Vec<ListItem> = app
        .roster
        .iter()
        .map(|r| {
            let rgb = app.catalog.color_rgb(r.color);
            let you_tag = if r.peer_id == app.you { " (YOU)" } else { "" };
            let badge = if r.ready {
                Span::styled(" [READY] ", Style::default().fg(Color::Black).bg(Color::Rgb(120, 245, 125)).add_modifier(Modifier::BOLD))
            } else {
                Span::styled(" [WAIT ] ", Style::default().fg(Color::DarkGray))
            };
            ListItem::new(Line::from(vec![
                Span::styled("██ ", Style::default().fg(Color::Rgb(rgb.0, rgb.1, rgb.2))),
                Span::styled(
                    format!("{:<18}", format!("{}{}", r.name, you_tag)),
                    Style::default().fg(Color::White).add_modifier(Modifier::BOLD),
                ),
                Span::styled(
                    format!("{:<12} ", app.catalog.skin_name(r.skin)),
                    Style::default().fg(Color::Gray),
                ),
                badge,
            ]))
        })
        .collect();

    while roster_items.len() < 4 {
        roster_items.push(ListItem::new(Line::from(Span::styled(
            "   -- OPEN SQUAD SLOT --",
            Style::default().fg(Color::DarkGray),
        ))));
    }

    let roster_box = List::new(roster_items).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(115, 220, 200)))
            .title(format!(" SQUAD ROSTER ({}/4) ", app.roster.len())),
    );
    frame.render_widget(roster_box, cols[0]);

    // Map vote cards
    let mut map_lines: Vec<Line> = Vec::new();
    for (idx, m) in app.server_maps.iter().enumerate() {
        let votes = app.vote_counts.get(&m.id).copied().unwrap_or(0);
        let chosen = app.my_vote == m.id;
        let blurb = app
            .catalog
            .maps
            .get(&m.id)
            .map(|s| s.blurb.as_str())
            .unwrap_or("");
        let accent = app
            .catalog
            .maps
            .get(&m.id)
            .map(|s| Color::Rgb(s.accent.0, s.accent.1, s.accent.2))
            .unwrap_or(Color::Cyan);
        map_lines.push(Line::from(vec![
            Span::styled(
                format!(" [{}] {:<14} ", idx + 1, m.name),
                Style::default().fg(accent).add_modifier(Modifier::BOLD),
            ),
            Span::styled(
                format!("Votes: {} ", votes),
                Style::default().fg(Color::Rgb(255, 230, 110)),
            ),
            if chosen {
                Span::styled("◀ YOUR VOTE", Style::default().fg(Color::Rgb(125, 250, 130)).add_modifier(Modifier::BOLD))
            } else {
                Span::raw("")
            },
        ]));
        if !blurb.is_empty() {
            map_lines.push(Line::from(Span::styled(
                format!("     {}", blurb),
                Style::default().fg(Color::Gray),
            )));
        }
    }
    let rand_votes = app.vote_counts.get("random").copied().unwrap_or(0);
    map_lines.push(Line::from(vec![
        Span::styled(
            format!(" [{}] {:<14} ", app.server_maps.len() + 1, "RANDOM"),
            Style::default().fg(Color::Rgb(215, 175, 255)).add_modifier(Modifier::BOLD),
        ),
        Span::styled(format!("Votes: {} ", rand_votes), Style::default().fg(Color::Rgb(255, 230, 110))),
        if app.my_vote == "random" {
            Span::styled("◀ YOUR VOTE", Style::default().fg(Color::Rgb(125, 250, 130)).add_modifier(Modifier::BOLD))
        } else {
            Span::raw("")
        },
    ]));

    let map_box = Paragraph::new(map_lines).wrap(Wrap { trim: false }).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(245, 200, 95)))
            .title(format!(" MAP VOTE (Default: {}) ", app.default_map.to_uppercase())),
    );
    frame.render_widget(map_box, cols[1]);

    // Lobby chat
    let mut chat_lines: Vec<Line> = app
        .chat_log
        .iter()
        .rev()
        .take(5)
        .rev()
        .map(|c| {
            Line::from(vec![
                Span::styled(format!("{}: ", c.sender), Style::default().fg(Color::Rgb(120, 235, 215)).add_modifier(Modifier::BOLD)),
                Span::raw(c.text.clone()),
            ])
        })
        .collect();
    if app.chat_input_active {
        chat_lines.push(Line::from(vec![
            Span::styled("SAY> ", Style::default().fg(Color::Rgb(255, 230, 100)).add_modifier(Modifier::BOLD)),
            Span::styled(format!("{}▌", app.chat_draft), Style::default().fg(Color::White)),
        ]));
    }
    let chat_box = Paragraph::new(chat_lines).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(if app.chat_input_active {
                Style::default().fg(Color::Rgb(255, 230, 100))
            } else {
                Style::default().fg(Color::DarkGray)
            })
            .title(if app.chat_input_active {
                " LOBBY CHAT (Enter to send, Esc to cancel) "
            } else {
                " LOBBY CHAT (Press [C] to chat) "
            }),
    );
    frame.render_widget(chat_box, rows[2]);

    // Footer controls
    let ctrl = Paragraph::new(
        " [R] Toggle Ready   [F] Force Start   [1-4] Vote Map   [C] Chat   [H] Help   [Q/Esc] Leave ",
    )
    .alignment(Alignment::Center)
    .style(Style::default().fg(Color::Rgb(175, 225, 220)))
    .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::DarkGray)));
    frame.render_widget(ctrl, rows[3]);
}

fn draw_loading(frame: &mut Frame, app: &GameApp) {
    let box_area = centered_rect(64, 34, frame.area());
    let map_name = app
        .current_map
        .as_ref()
        .map(|m| m.name.as_str())
        .unwrap_or(&app.current_map_id);
    let blurb = app
        .catalog
        .maps
        .get(&app.current_map_id)
        .map(|s| s.blurb.as_str())
        .unwrap_or("Syncing world catch-up state from dedicated server...");

    let p = Paragraph::new(vec![
        Line::from(""),
        Line::from(Span::styled(
            format!("DEPLOYING TO {}", map_name.to_uppercase()),
            Style::default().fg(Color::Rgb(120, 245, 215)).add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(Span::styled(blurb, Style::default().fg(Color::Gray))),
        Line::from(""),
        Line::from(Span::styled(
            "Awaiting Net._confirm_run_ready & catch-up burst...",
            Style::default().fg(Color::Rgb(255, 220, 95)),
        )),
    ])
    .alignment(Alignment::Center)
    .block(Block::default().borders(Borders::ALL).title(" LOADING RUN "));
    frame.render_widget(p, box_area);
}

fn draw_in_run(frame: &mut Frame, app: &GameApp, time_secs: f32) {
    let area = frame.area();
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Top compass & forecast strip
            Constraint::Min(10),   // Main 3D FPS or Top-Down viewport
            Constraint::Length(6), // Bottom vitals, hotbar, prompt & feed
        ])
        .split(area);

    // 1. Top Bar: Compass + Wave/Weather + Exposure + RTT
    let compass = build_compass_strip(app.my_yaw, 29);
    let phase_color = match app.phase {
        0 => Color::Rgb(115, 235, 215),
        2 => Color::Rgb(150, 235, 130),
        3 => Color::Rgb(255, 115, 85),
        4 => Color::Rgb(175, 225, 255),
        _ => Color::White,
    };
    let exposure_span = if app.is_in_puddle {
        Span::styled(" [ACID PUDDLE!] ", Style::default().fg(Color::Black).bg(Color::Rgb(165, 255, 60)).add_modifier(Modifier::BOLD))
    } else if app.is_sheltered {
        Span::styled(" [SHELTERED] ", Style::default().fg(Color::Black).bg(Color::Rgb(95, 235, 175)).add_modifier(Modifier::BOLD))
    } else {
        Span::styled(" [EXPOSED] ", Style::default().fg(Color::White).bg(Color::Rgb(195, 55, 55)).add_modifier(Modifier::BOLD))
    };

    let mins = (app.phase_time_left as u32) / 60;
    let secs = (app.phase_time_left as u32) % 60;
    let top_line = Line::from(vec![
        Span::styled(
            format!(" W{} {} ", app.wave, app.phase_label()),
            Style::default().fg(Color::Black).bg(phase_color).add_modifier(Modifier::BOLD),
        ),
        Span::styled(format!(" {}:{:02} ", mins, secs), Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
        Span::styled(format!("[{}] ", app.forecast_modifier()), Style::default().fg(Color::Rgb(255, 210, 110))),
        Span::styled(format!("HOSTILES:{}/{} ", app.enemies_left, app.enemies_total), Style::default().fg(Color::Rgb(255, 135, 135))),
        Span::raw(" | "),
        Span::styled(compass, Style::default().fg(Color::Rgb(190, 235, 240))),
        Span::raw(" | "),
        exposure_span,
        Span::styled(format!(" {:.0}ms [M:{}]", app.rtt_ms, app.view_mode.label()), Style::default().fg(Color::Gray)),
    ]);

    let top_block = Paragraph::new(top_line).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(75, 145, 150))),
    );
    frame.render_widget(top_block, rows[0]);

    // 2. Main Viewport
    let vp = rows[1];
    match app.view_mode {
        ViewMode::FpsWithMinimap => {
            render_fps_viewport(app, vp, frame.buffer_mut(), time_secs);
            render_corner_minimap(app, vp, frame.buffer_mut());
        }
        ViewMode::FullFps => {
            render_fps_viewport(app, vp, frame.buffer_mut(), time_secs);
        }
        ViewMode::TopDownMap => {
            render_topdown_map(app, vp, frame.buffer_mut());
        }
    }

    // Center Banner overlay inside viewport
    if let Some(banner) = app.banners.front() {
        let bw = (banner.text.len() as u16 + 8).min(vp.width.saturating_sub(4));
        let rect = Rect::new(vp.x + (vp.width.saturating_sub(bw)) / 2, vp.y + 2, bw, 3);
        frame.render_widget(Clear, rect);
        let bp = Paragraph::new(banner.text.as_str())
            .alignment(Alignment::Center)
            .style(
                Style::default()
                    .fg(Color::Rgb(banner.rgb.0, banner.rgb.1, banner.rgb.2))
                    .add_modifier(Modifier::BOLD),
            )
            .block(Block::default().borders(Borders::ALL));
        frame.render_widget(bp, rect);
    }

    // Boss HP Bar
    if let Some(boss) = &app.boss {
        let total: f32 = boss.parts.iter().sum();
        let ratio = (total / 600.0).clamp(0.0, 1.0) as f64;
        let rect = Rect::new(vp.x + 8, vp.y + 1, vp.width.saturating_sub(16).max(20), 3);
        let g = Gauge::default()
            .block(Block::default().borders(Borders::ALL).title(format!(" BOSS: CUMULUS ({} SACS) ", boss.sacs)))
            .gauge_style(Style::default().fg(Color::Rgb(235, 90, 255)))
            .ratio(ratio);
        frame.render_widget(Clear, rect);
        frame.render_widget(g, rect);
    }

    // Context interact prompt floating near bottom-center of viewport
    if let Some(prompt) = app.nearby_interact_prompt() {
        let pw = (prompt.len() as u16 + 4).min(vp.width.saturating_sub(2));
        let rect = Rect::new(
            vp.x + (vp.width.saturating_sub(pw)) / 2,
            vp.y + vp.height.saturating_sub(2),
            pw,
            1,
        );
        let pp = Paragraph::new(prompt)
            .alignment(Alignment::Center)
            .style(
                Style::default()
                    .fg(Color::Black)
                    .bg(Color::Rgb(255, 230, 105))
                    .add_modifier(Modifier::BOLD),
            );
        frame.render_widget(pp, rect);
    }

    // 3. Bottom HUD: Left = HP/Suit/Scrap, Center = Hotbar/Ammo/Pouches, Right = Event Feed
    let hud_cols = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Length(30),
            Constraint::Min(38),
            Constraint::Length(32),
        ])
        .split(rows[2]);

    let (hp, max_hp, suit, state_str) = app
        .my_player()
        .map(|p| (p.hp, p.max_hp, p.suit, p.state.as_str()))
        .unwrap_or((100.0, 100.0, 100.0, "ok"));

    let hp_bar = ascii_bar(hp / max_hp.max(1.0), 14);
    let suit_bar = ascii_bar(suit / 100.0, 14);
    let vitals_lines = vec![
        Line::from(vec![
            Span::styled("HP  ", Style::default().fg(Color::Rgb(255, 115, 115)).add_modifier(Modifier::BOLD)),
            Span::styled(hp_bar, Style::default().fg(if hp > 45.0 { Color::Rgb(115, 240, 130) } else { Color::Rgb(255, 85, 85) })),
            Span::raw(format!(" {:3.0}/{:.0}", hp, max_hp)),
        ]),
        Line::from(vec![
            Span::styled("SUIT", Style::default().fg(Color::Rgb(105, 230, 245)).add_modifier(Modifier::BOLD)),
            Span::styled(suit_bar, Style::default().fg(if suit > 35.0 { Color::Rgb(105, 230, 245) } else { Color::Rgb(255, 200, 70) })),
            Span::raw(format!(" {:3.0}%", suit)),
        ]),
        Line::from(vec![
            Span::styled(format!("SCRAP:{} ", app.inventory.scrap), Style::default().fg(Color::Rgb(255, 220, 85)).add_modifier(Modifier::BOLD)),
            Span::styled(format!("DECON:{} ", app.decon_charges), Style::default().fg(Color::Rgb(100, 245, 235))),
            Span::styled(format!("[{}]", state_str.to_uppercase()), Style::default().fg(Color::White)),
        ]),
        Line::from(Span::styled(
            format!("RAIN:{:2.0}%  SCORE:{}", app.storm_intensity * 100.0, app.endless_score),
            Style::default().fg(Color::Gray),
        )),
    ];
    let vitals_box = Paragraph::new(vitals_lines).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(95, 185, 175)))
            .title(" VITALS "),
    );
    frame.render_widget(vitals_box, hud_cols[0]);

    // Hotbar + Weapon Ammo + Pouches + Mutations
    let mut slot_spans: Vec<Span> = Vec::new();
    for i in 0..5 {
        let active = i == app.inventory.selected_slot && app.inventory.selected_pouch.is_empty();
        let label = match &app.inventory.slots[i] {
            Some(item) => {
                let short = short_item_name(app.catalog.item_name(&item.id));
                format!("[{}:{} ({})]", i + 1, short, item.count)
            }
            None => format!("[{}:---]", i + 1),
        };
        slot_spans.push(Span::styled(
            format!("{} ", label),
            if active {
                Style::default()
                    .fg(Color::Black)
                    .bg(Color::Rgb(255, 230, 105))
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::Gray)
            },
        ));
    }

    let ammo_line = if let Some(held) = app.inventory.held_item() {
        let def = app.catalog.items.get(&held.id);
        let name = def.map(|d| d.name.as_str()).unwrap_or(&held.id);
        let reserve = def
            .and_then(|d| app.inventory.stash.get(&d.ammo_type).copied())
            .unwrap_or(0);
        let status = if app.inventory.reload_left > 0.05 {
            format!("RELOADING {:.1}s", app.inventory.reload_left)
        } else if app.inventory.jam_left > 0.05 {
            format!("JAMMED {:.1}s", app.inventory.jam_left)
        } else {
            format!("MAG {} / RES {}", held.count, reserve)
        };
        Line::from(vec![
            Span::styled(format!("{}  ", name), Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
            Span::styled(status, Style::default().fg(Color::Rgb(255, 220, 95)).add_modifier(Modifier::BOLD)),
            Span::raw("   "),
            Span::styled(format!("[Q]Frag:{} ", app.inventory.frags), Style::default().fg(Color::Rgb(255, 165, 85))),
            Span::styled(format!("[F]Dome:{}", app.inventory.shield_domes), Style::default().fg(Color::Rgb(95, 245, 255))),
        ])
    } else {
        Line::from(Span::styled(
            "EMPTY HANDS — Press [1-3] for Starter Kit or scavenge gear",
            Style::default().fg(Color::DarkGray),
        ))
    };

    let mut_text = if app.active_player_mutations.is_empty() {
        "WASD Move | Arrows/IJKL Look | Space/Enter Fire | R Reload | E Interact | P Ping | M View | H Help".to_string()
    } else {
        format!("MUTATIONS: {}", app.active_player_mutations.join(", "))
    };

    let hotbar_box = Paragraph::new(vec![
        Line::from(slot_spans),
        ammo_line,
        Line::from(Span::styled(mut_text, Style::default().fg(Color::Rgb(150, 200, 195)))),
    ])
    .block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(115, 190, 210)))
            .title(" LOADOUT & CONTROLS "),
    );
    frame.render_widget(hotbar_box, hud_cols[1]);

    // Kill / Event Feed
    let feed_lines: Vec<Line> = app
        .feed
        .iter()
        .rev()
        .take(4)
        .rev()
        .map(|s| Line::from(Span::styled(s.clone(), Style::default().fg(Color::Rgb(215, 225, 230)))))
        .collect();
    let feed_box = Paragraph::new(feed_lines).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::DarkGray))
            .title(" RADIO FEED "),
    );
    frame.render_widget(feed_box, hud_cols[2]);

    // Modal Overlays
    if app.show_starter_picker {
        draw_starter_picker(frame);
    } else if app.draft.is_some() {
        draw_mutation_draft(frame, app);
    } else if app.tape_choice_pending {
        draw_tape_choice(frame, app);
    }
}

fn draw_starter_picker(frame: &mut Frame) {
    let rect = centered_rect(64, 42, frame.area());
    frame.render_widget(Clear, rect);
    let lines = vec![
        Line::from(""),
        Line::from(Span::styled(
            "CHOOSE YOUR STARTER KIT",
            Style::default().fg(Color::Rgb(255, 230, 105)).add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(vec![
            Span::styled(" [1] PUMP SHOTGUN     ", Style::default().fg(Color::Rgb(255, 190, 90)).add_modifier(Modifier::BOLD)),
            Span::raw("8 pellets · High knockback · Shell-by-shell reload"),
        ]),
        Line::from(vec![
            Span::styled(" [2] NAIL DRIVER      ", Style::default().fg(Color::Rgb(130, 240, 205)).add_modifier(Modifier::BOLD)),
            Span::raw("Full-auto · 24 mag · Rapid suppression"),
        ]),
        Line::from(vec![
            Span::styled(" [3] SERVICE REVOLVER ", Style::default().fg(Color::Rgb(185, 215, 255)).add_modifier(Modifier::BOLD)),
            Span::raw("High accuracy · 38 dmg/shot · Long reach"),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            "Includes reserve ammo, 2x Frag Grenades, and 1x Shield Dome.",
            Style::default().fg(Color::Gray),
        )),
    ];
    let p = Paragraph::new(lines)
        .alignment(Alignment::Center)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Rgb(255, 225, 95)))
                .title(" STARTER LOADOUT "),
        );
    frame.render_widget(p, rect);
}

fn draw_mutation_draft(frame: &mut Frame, app: &GameApp) {
    let Some(draft) = &app.draft else { return };
    let rect = centered_rect(72, 52, frame.area());
    frame.render_widget(Clear, rect);

    let mut lines = vec![
        Line::from(Span::styled(
            "SQUAD MUTATION DRAFT — VOTE [1] [2] [3]",
            Style::default().fg(Color::Rgb(145, 255, 115)).add_modifier(Modifier::BOLD),
        )),
    ];
    if !draft.enemy_mutation.is_empty() {
        let ename = app
            .catalog
            .enemy_mutations
            .get(&draft.enemy_mutation)
            .map(|m| format!("{} — {}", m.name, m.desc))
            .unwrap_or_else(|| draft.enemy_mutation.clone());
        lines.push(Line::from(Span::styled(
            format!("INCOMING INFECTED MUTATION: {}", ename),
            Style::default().fg(Color::Rgb(255, 110, 95)).add_modifier(Modifier::BOLD),
        )));
    }
    lines.push(Line::from(""));

    for (i, mid) in draft.dealt.iter().enumerate() {
        let votes = draft.votes.get(i).copied().unwrap_or(0);
        let picked = draft.my_vote == Some(i);
        let (name, desc, col) = app
            .catalog
            .player_mutations
            .get(mid)
            .map(|m| (m.name.as_str(), m.desc.as_str(), Color::Rgb(m.color.0, m.color.1, m.color.2)))
            .unwrap_or((mid.as_str(), "", Color::Cyan));
        lines.push(Line::from(vec![
            Span::styled(
                format!(" [{}] {:<18} ", i + 1, name),
                Style::default().fg(col).add_modifier(Modifier::BOLD),
            ),
            Span::styled(format!("Votes: {} ", votes), Style::default().fg(Color::Rgb(255, 230, 105))),
            if picked {
                Span::styled("◀ VOTED", Style::default().fg(Color::Green).add_modifier(Modifier::BOLD))
            } else {
                Span::raw("")
            },
        ]));
        lines.push(Line::from(Span::styled(
            format!("     {}", desc),
            Style::default().fg(Color::Gray),
        )));
    }

    let p = Paragraph::new(lines).wrap(Wrap { trim: false }).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(145, 255, 115)))
            .title(" MUTATION ROLL "),
    );
    frame.render_widget(p, rect);
}

fn draw_tape_choice(frame: &mut Frame, app: &GameApp) {
    let rect = centered_rect(60, 36, frame.area());
    frame.render_widget(Clear, rect);
    let leader = app.is_first_roster_peer();
    let lines = vec![
        Line::from(""),
        Line::from(Span::styled(
            "CAMPAIGN VICTORY — CUMULUS DEFEATED!",
            Style::default().fg(Color::Rgb(130, 255, 150)).add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        if leader {
            Line::from(Span::styled(
                "[C] CONTINUE INTO ENDLESS WAVES   |   [E] END TAPE (VICTORY)",
                Style::default().fg(Color::Rgb(255, 230, 105)).add_modifier(Modifier::BOLD),
            ))
        } else {
            Line::from(Span::styled(
                "Waiting for squad leader to choose CONTINUE or END TAPE...",
                Style::default().fg(Color::Gray),
            ))
        },
    ];
    let p = Paragraph::new(lines)
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::ALL).title(" ENDLESS TAPE CHOICE "));
    frame.render_widget(p, rect);
}

fn draw_results(frame: &mut Frame, app: &GameApp) {
    let area = centered_rect(76, 72, frame.area());
    let mut lines = Vec::new();
    if let Some(res) = &app.results {
        let title = if res.won {
            "★ RUN COMPLETE — VICTORY! ★"
        } else {
            "✖ SQUAD WIPED — RUN ENDED ✖"
        };
        let col = if res.won {
            Color::Rgb(120, 250, 140)
        } else {
            Color::Rgb(255, 95, 95)
        };
        lines.push(Line::from(Span::styled(title, Style::default().fg(col).add_modifier(Modifier::BOLD))));
        lines.push(Line::from(""));
        lines.push(Line::from(format!(
            "Map: {}   Waves Cleared: {} (Reached {})   Duration: {}m {:02}s   Endless Score: {}",
            res.map_id.to_uppercase(),
            res.waves,
            res.wave_reached,
            res.seconds / 60,
            res.seconds % 60,
            res.endless_score
        )));
        if !res.squad_mutations.is_empty() {
            lines.push(Line::from(format!(
                "Squad Mutations: {}",
                res.squad_mutations.join(", ")
            )));
        }
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            format!("{:<20} {:<20} {:>6} {:>8}", "CALLSIGN", "WEAPON", "KILLS", "REVIVES"),
            Style::default().fg(Color::Rgb(255, 225, 105)).add_modifier(Modifier::BOLD),
        )));
        for p in &res.players {
            lines.push(Line::from(format!(
                "{:<20} {:<20} {:>6} {:>8}",
                p.name, p.weapon, p.kills, p.revives
            )));
        }
    }
    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled(
        "[L] Return to Lobby   [R] Ready Up for Next Run   [Q] Quit",
        Style::default().fg(Color::Rgb(120, 235, 215)).add_modifier(Modifier::BOLD),
    )));

    let p = Paragraph::new(lines).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(120, 225, 210)))
            .title(" AFTER-ACTION REPORT "),
    );
    frame.render_widget(p, area);
}

fn draw_disconnected(frame: &mut Frame, app: &GameApp) {
    let rect = centered_rect(64, 34, frame.area());
    let p = Paragraph::new(vec![
        Line::from(""),
        Line::from(Span::styled(
            "DISCONNECTED",
            Style::default().fg(Color::Rgb(255, 100, 100)).add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(app.disconnect_reason.as_str()),
        Line::from(""),
        Line::from(Span::styled(
            "[Enter] Back to Title   [R] Reconnect   [Q] Quit",
            Style::default().fg(Color::Rgb(130, 235, 215)),
        )),
    ])
    .alignment(Alignment::Center)
    .block(Block::default().borders(Borders::ALL).title(" CONNECTION CLOSED "));
    frame.render_widget(p, rect);
}

fn draw_help_overlay(frame: &mut Frame) {
    let rect = centered_rect(68, 66, frame.area());
    frame.render_widget(Clear, rect);
    let lines = vec![
        Line::from(Span::styled("IN-RUN CONTROLS", Style::default().fg(Color::Rgb(255, 230, 105)).add_modifier(Modifier::BOLD))),
        Line::from("  W A S D        Move / Strafe        Shift   Toggle Sprint"),
        Line::from("  Arrows / IJKL  Turn & Look          C       Toggle Crouch"),
        Line::from("  Space / Enter  Fire / Use Held      Z       Toggle ADS Zoom"),
        Line::from("  X              Jump                 R       Reload"),
        Line::from("  1 - 5          Select Hotbar Slot   G       Skip Calm / Ready"),
        Line::from("  Q / F          Throw Frag / Dome    T       Toggle Shelter Tarp"),
        Line::from("  E              Interact (Pickup / Decon / Revive / Vending)"),
        Line::from("  P              Context Squad Ping   B       Drop Held Item"),
        Line::from("  M              Cycle View: 3D+Radar / Full 3D / Top-Down Map"),
        Line::from("  H / ?          Toggle This Help     Esc     Leave Match / Quit"),
    ];
    let p = Paragraph::new(lines).block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(120, 235, 215)))
            .title(" HELP (Press H or Esc to close) "),
    );
    frame.render_widget(p, rect);
}

fn build_compass_strip(yaw: f32, width: usize) -> String {
    // 0 deg = N (-Z), 90 = E (+X), 180 = S (+Z), 270 = W (-X)
    let heading_deg = (-yaw.to_degrees()).rem_euclid(360.0);
    let half = (width / 2) as i32;
    let mut out = String::with_capacity(width);
    for i in -half..=half {
        let deg = ((heading_deg + (i as f32) * 5.0).rem_euclid(360.0)).round() as i32 % 360;
        let bucket = ((deg + 2) / 5) % 72; // 72 buckets of 5 deg each
        let ch = match bucket {
            0 => 'N',
            9 => '↗',
            18 => 'E',
            27 => '↘',
            36 => 'S',
            45 => '↙',
            54 => 'W',
            63 => '↖',
            b if b % 3 == 0 => '|',
            _ => '·',
        };
        out.push(ch);
    }
    out
}

fn ascii_bar(frac: f32, width: usize) -> String {
    let filled = ((frac.clamp(0.0, 1.0) * width as f32).round() as usize).min(width);
    format!("[{}{}]", "█".repeat(filled), "░".repeat(width - filled))
}

fn short_item_name(name: &str) -> String {
    let words: Vec<&str> = name.split_whitespace().collect();
    if words.len() >= 2 {
        format!("{}{}", &words[0][..words[0].len().min(4)], &words[1][..words[1].len().min(3)])
    } else {
        name.chars().take(7).collect()
    }
}

fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let v = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(r);
    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(v[1])[1]
}

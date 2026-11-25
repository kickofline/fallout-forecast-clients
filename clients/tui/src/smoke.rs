use std::fs;
use std::path::Path;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use ratatui::backend::TestBackend;
use ratatui::Terminal;

use crate::game::state::{ConnectConfig, GameApp, Screen, ViewMode};
use crate::render::ui;

pub async fn run_smoke_test(
    config: ConnectConfig,
    dump_dir: Option<&Path>,
    observe_secs: f32,
) -> Result<()> {
    let tag = format!(
        "{}_{}",
        if config.use_tcp { "tcp" } else { "ws" },
        config.enc.as_str()
    );
    if let Some(dir) = dump_dir {
        fs::create_dir_all(dir)
            .with_context(|| format!("Creating dump directory {}", dir.display()))?;
    }

    let mut app = GameApp::new(config);
    app.connect();

    let start = Instant::now();
    let deadline = start + Duration::from_secs_f32((observe_secs + 25.0).max(38.0));

    let mut voted = false;
    let mut lobby_dumped = false;
    let mut ready_sent_at: Option<Instant> = None;
    let mut force_sent = false;
    let mut starter_sent = false;
    let mut calm_skip_sent = false;
    let mut run_started_at: Option<Instant> = None;
    let mut last_shot = Instant::now() - Duration::from_secs(5);
    let mut reload_sent = false;

    let mut last_tick = Instant::now();

    loop {
        let now = Instant::now();
        let dt = now.duration_since(last_tick).as_secs_f32().clamp(0.005, 0.05);
        last_tick = now;

        app.tick(dt);

        if app.screen == Screen::Disconnected {
            bail!(
                "Smoke test disconnected unexpectedly: {}",
                app.disconnect_reason
            );
        }

        if now > deadline {
            bail!(
                "Smoke test timed out in screen {:?} (welcome={}, roster={}, run_ready={}, enemies={})",
                app.screen,
                app.smoke.welcome_ok,
                app.smoke.roster_ok,
                app.smoke.run_ready_ok,
                app.smoke.enemies_spawned
            );
        }

        match app.screen {
            Screen::Lobby => {
                if !voted && app.smoke.roster_ok {
                    voted = true;
                    app.send_map_vote("pinecrest");
                    app.send_chat("fallout-tui smoke online");
                    ready_sent_at = Some(Instant::now());
                } else if let Some(t) = ready_sent_at {
                    if !lobby_dumped && t.elapsed() >= Duration::from_millis(400) {
                        lobby_dumped = true;
                        if let Some(dir) = dump_dir {
                            dump_ascii_frame(&app, dir, &format!("{}_lobby.txt", tag), start.elapsed().as_secs_f32())?;
                        }
                        app.send_lobby_ready(true);
                    }
                    if !force_sent && t.elapsed() >= Duration::from_millis(1800) {
                        force_sent = true;
                        app.send_force_start();
                    }
                }
            }
            Screen::InRun => {
                if run_started_at.is_none() {
                    run_started_at = Some(now);
                    // Face south-east down Main Street & toward storefronts
                    app.my_yaw = std::f32::consts::PI * 0.85;
                }
                let run_elapsed = run_started_at.unwrap().elapsed().as_secs_f32();

                if !starter_sent && app.run_ready && app.run_id > 0 {
                    starter_sent = true;
                    app.pick_starter(0); // pump_shotgun
                }
                if !calm_skip_sent && app.smoke.starter_accepted {
                    calm_skip_sent = true;
                    app.send_calm_ready();
                }

                // Scripted movement: walk toward Block B Awning (z ~ 8) to exercise shelter exposure,
                // then step back into Main Street and face approaching enemies!
                app.input.forward = false;
                app.input.back = false;
                app.input.left = false;
                app.input.right = false;
                app.input.turn_left = false;
                app.input.turn_right = false;

                if run_elapsed < 2.2 {
                    // Face south (+Z -> yaw = PI) and walk under Block A/B awning
                    app.my_yaw = std::f32::consts::PI;
                    app.input.forward = true;
                } else if run_elapsed < 3.4 {
                    // Step back out onto Main Street
                    app.my_yaw = 0.0;
                    app.input.forward = true;
                } else {
                    // Aim toward nearest live enemy if any, else look down Main Street toward storefronts & east spawn
                    if let Some(target) = app
                        .enemies
                        .values()
                        .min_by(|a, b| {
                            let da = (a.pos[0] - app.my_pos[0]).powi(2) + (a.pos[2] - app.my_pos[2]).powi(2);
                            let db = (b.pos[0] - app.my_pos[0]).powi(2) + (b.pos[2] - app.my_pos[2]).powi(2);
                            da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
                        })
                    {
                        let dx = target.pos[0] - app.my_pos[0];
                        let dz = target.pos[2] - app.my_pos[2];
                        let dist = (dx * dx + dz * dz).sqrt();
                        // Godot forward = (-sin yaw, -cos yaw) => yaw = atan2(-dx, -dz)
                        app.my_yaw = (-dx).atan2(-dz);
                        app.my_pitch = ((target.pos[1] + 1.0 - app.my_eye_pos()[1]) / dist.max(1.0))
                            .atan()
                            .clamp(-0.35, 0.35);
                        if dist > 20.0 && app.my_pos[2].abs() < 6.0 {
                            app.input.forward = true;
                        }
                    } else {
                        // Look toward storefronts & awning pillars so the scene is rich
                        app.my_yaw = std::f32::consts::PI * 0.82;
                        app.my_pitch = 0.0;
                    }

                    // Fire shots once starter is equipped
                    if app.smoke.starter_accepted
                        && app.smoke.shots_sent < 3
                        && last_shot.elapsed() >= Duration::from_millis(950)
                    {
                        last_shot = Instant::now();
                        app.fire_or_use();
                    }

                    if !reload_sent && app.smoke.shots_sent >= 2 && last_shot.elapsed() >= Duration::from_millis(400) {
                        reload_sent = true;
                        app.reload_weapon();
                    }
                }

                // Wait until we have enemies synced + shots + vitals + enough observation time
                let core_ready = app.smoke.starter_accepted
                    && app.smoke.transforms_sent >= 25
                    && app.smoke.shot_fx_received >= 1
                    && app.smoke.enemies_spawned >= 1
                    && app.smoke.enemy_syncs >= 2
                    && app.smoke.vitals_received >= 2
                    && app.smoke.phases_received >= 1;

                if core_ready && run_elapsed >= observe_secs {
                    if let Some(dir) = dump_dir {
                        // Capture 3D FPS + Radar
                        app.view_mode = ViewMode::FpsWithMinimap;
                        dump_ascii_frame(&app, dir, &format!("{}_fps_run.txt", tag), start.elapsed().as_secs_f32())?;
                        // Capture Full 3D FPS
                        app.view_mode = ViewMode::FullFps;
                        dump_ascii_frame(&app, dir, &format!("{}_fps_full.txt", tag), start.elapsed().as_secs_f32())?;
                        // Capture Full Top-Down Tactical Map
                        app.view_mode = ViewMode::TopDownMap;
                        dump_ascii_frame(&app, dir, &format!("{}_topdown_map.txt", tag), start.elapsed().as_secs_f32())?;
                    }
                    break;
                }
            }
            _ => {}
        }

        tokio::time::sleep(Duration::from_millis(20)).await;
    }

    // Graceful leave
    app.disconnect_gracefully();
    tokio::time::sleep(Duration::from_millis(250)).await;

    // Validate all smoke assertions
    let s = &app.smoke;
    let mut failures = Vec::new();
    if !s.welcome_ok {
        failures.push("welcome handshake missing".to_string());
    }
    if !s.pong_ok {
        failures.push("control ping/pong missing".to_string());
    }
    if !s.roster_ok {
        failures.push("Net._push_roster missing own peer id".to_string());
    }
    if !s.start_run_ok {
        failures.push("Net._start_run not received".to_string());
    }
    if !s.run_ready_ok {
        failures.push("Net._confirm_run_ready not received".to_string());
    }
    if !s.starter_accepted {
        failures.push("Main/RunLoot._starter_accepted not received".to_string());
    }
    if s.transforms_sent < 20 {
        failures.push(format!("expected >=20 transforms sent, got {}", s.transforms_sent));
    }
    if s.exposure_reports < 1 {
        failures.push("no _report_exposure sent".to_string());
    }
    if s.shot_fx_received < 1 {
        failures.push("no _shot_fx received".to_string());
    }
    if s.enemies_spawned < 1 || s.enemy_syncs < 1 {
        failures.push(format!(
            "enemy stream missing (spawned={}, syncs={})",
            s.enemies_spawned, s.enemy_syncs
        ));
    }
    if s.vitals_received < 1 {
        failures.push("no _apply_vitals received".to_string());
    }
    if s.phases_received < 1 {
        failures.push("no WeatherManager._receive_phase received".to_string());
    }
    if !s.protocol_errors.is_empty() {
        failures.push(format!("protocol errors: {:?}", s.protocol_errors));
    }

    println!(
        "SMOKE [{}] SUMMARY: peer={} map={} run_id={} transforms={} exposure={} shots={}/{} enemies_spawned={} enemy_syncs={} vitals={} phases={} errors={}",
        tag,
        app.you,
        app.current_map_id,
        app.run_id,
        s.transforms_sent,
        s.exposure_reports,
        s.shots_sent,
        s.shot_fx_received,
        s.enemies_spawned,
        s.enemy_syncs,
        s.vitals_received,
        s.phases_received,
        s.protocol_errors.len()
    );

    if !failures.is_empty() {
        bail!("Smoke test [{}] FAILED: {}", tag, failures.join("; "));
    }
    println!("SMOKE [{}] PASS", tag);
    Ok(())
}

pub fn dump_ascii_frame(app: &GameApp, dir: &Path, filename: &str, time_secs: f32) -> Result<()> {
    let backend = TestBackend::new(120, 38);
    let mut terminal = Terminal::new(backend)?;
    terminal.draw(|f| ui::draw(f, app, time_secs))?;
    let buf = terminal.backend().buffer();

    let mut text = String::with_capacity((buf.area.width as usize + 1) * buf.area.height as usize);
    for y in 0..buf.area.height {
        for x in 0..buf.area.width {
            text.push_str(buf[(x, y)].symbol());
        }
        text.push('\n');
    }

    let path = dir.join(filename);
    fs::write(&path, text).with_context(|| format!("Writing frame {}", path.display()))?;
    println!("Dumped ASCII frame -> {}", path.display());
    Ok(())
}

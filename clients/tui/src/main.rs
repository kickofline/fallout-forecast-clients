mod game;
mod protocol;
mod render;
mod smoke;

use std::io;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use anyhow::Result;
use clap::{Parser, ValueEnum};
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;

use crate::game::state::{ConnectConfig, GameApp, Screen};
use crate::protocol::frame::Encoding;
use crate::render::ui;

#[derive(Debug, Clone, Copy, ValueEnum)]
enum EncArg {
    Json,
    Bin,
}

impl From<EncArg> for Encoding {
    fn from(v: EncArg) -> Self {
        match v {
            EncArg::Json => Encoding::Json,
            EncArg::Bin => Encoding::Bin,
        }
    }
}

#[derive(Parser, Debug)]
#[command(
    name = "fallout-tui",
    version,
    about = "Fallout Forecast Full-tier Open Protocol ASCII terminal client"
)]
struct Cli {
    /// WebSocket endpoint URL (ws:// or wss://)
    #[arg(long, default_value = "wss://fallout-open.drew.place/")]
    url: String,

    /// Raw TCP endpoint (host:port). Overrides --url when provided.
    #[arg(long)]
    tcp: Option<String>,

    /// Open Protocol Full-tier RPC encoding (json or bin)
    #[arg(long, value_enum, default_value = "bin")]
    enc: EncArg,

    /// Player callsign
    #[arg(long, default_value = "ASCII-Runner")]
    name: String,

    /// Optional server join code
    #[arg(long, default_value = "")]
    code: String,

    /// Preferred suit color index (0..9)
    #[arg(long, default_value_t = 0)]
    color: i64,

    /// Suit skin index (0..4)
    #[arg(long, default_value_t = 0)]
    skin: i64,

    /// Skip the Title screen and connect immediately
    #[arg(long)]
    connect: bool,

    /// Run automated headless end-to-end smoke test
    #[arg(long)]
    smoke_test: bool,

    /// Directory to dump rendered ASCII frames (.txt) during --smoke-test
    #[arg(long)]
    dump_frames: Option<PathBuf>,

    /// Seconds to observe live run during --smoke-test
    #[arg(long, default_value_t = 8.0)]
    smoke_seconds: f32,
}

/// Ensures raw mode & alternate screen are always restored on normal exit or unwind.
struct TerminalGuard;

impl TerminalGuard {
    fn enter() -> Result<Self> {
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen)?;
        Ok(Self)
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let mut stdout = io::stdout();
        let _ = execute!(stdout, LeaveAlternateScreen);
    }
}

#[derive(Default)]
struct HoldTimers {
    forward: f32,
    back: f32,
    left: f32,
    right: f32,
    turn_left: f32,
    turn_right: f32,
    look_up: f32,
    look_down: f32,
}

impl HoldTimers {
    fn decay(&mut self, dt: f32) {
        self.forward = (self.forward - dt).max(0.0);
        self.back = (self.back - dt).max(0.0);
        self.left = (self.left - dt).max(0.0);
        self.right = (self.right - dt).max(0.0);
        self.turn_left = (self.turn_left - dt).max(0.0);
        self.turn_right = (self.turn_right - dt).max(0.0);
        self.look_up = (self.look_up - dt).max(0.0);
        self.look_down = (self.look_down - dt).max(0.0);
    }

    fn apply(&self, app: &mut GameApp) {
        app.input.forward = self.forward > 0.0;
        app.input.back = self.back > 0.0;
        app.input.left = self.left > 0.0;
        app.input.right = self.right > 0.0;
        app.input.turn_left = self.turn_left > 0.0;
        app.input.turn_right = self.turn_right > 0.0;
        app.input.look_up = self.look_up > 0.0;
        app.input.look_down = self.look_down > 0.0;
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Install rustls ring provider for wss:// connections
    let _ = rustls::crypto::ring::default_provider().install_default();

    let cli = Cli::parse();
    let config = ConnectConfig {
        use_tcp: cli.tcp.is_some(),
        ws_url: cli.url,
        tcp_addr: cli.tcp.unwrap_or_else(|| "127.0.0.1:7781".into()),
        enc: cli.enc.into(),
        name: cli.name,
        code: cli.code,
        color: cli.color.clamp(0, 9),
        skin: cli.skin.rem_euclid(5),
    };

    if cli.smoke_test {
        return smoke::run_smoke_test(config, cli.dump_frames.as_deref(), cli.smoke_seconds).await;
    }

    // Install panic hook that restores terminal cleanly before printing panic info
    let prev_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = disable_raw_mode();
        let mut stdout = io::stdout();
        let _ = execute!(stdout, LeaveAlternateScreen);
        prev_hook(info);
    }));

    let _guard = TerminalGuard::enter()?;
    let backend = CrosstermBackend::new(io::stdout());
    let mut terminal = Terminal::new(backend)?;
    terminal.clear()?;

    let mut app = GameApp::new(config);
    if cli.connect {
        app.connect();
    }

    let start = Instant::now();
    let mut last_frame = Instant::now();
    let mut holds = HoldTimers::default();

    let run_result: Result<()> = loop {
        let now = Instant::now();
        let dt = now.duration_since(last_frame).as_secs_f32().clamp(0.004, 0.05);
        last_frame = now;

        // Poll all queued keyboard events
        let mut quit = false;
        while event::poll(Duration::from_millis(0))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Release {
                    continue;
                }
                if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
                    quit = true;
                    break;
                }
                if handle_key(&mut app, &mut holds, key) {
                    quit = true;
                    break;
                }
            }
        }
        if quit {
            app.disconnect_gracefully();
            tokio::time::sleep(Duration::from_millis(80)).await;
            break Ok(());
        }

        holds.decay(dt);
        holds.apply(&mut app);
        app.tick(dt);

        let elapsed = start.elapsed().as_secs_f32();
        terminal.draw(|f| ui::draw(f, &app, elapsed))?;

        tokio::time::sleep(Duration::from_millis(16)).await;
    };

    terminal.show_cursor()?;
    run_result
}

/// Returns true if the application should exit.
fn handle_key(app: &mut GameApp, holds: &mut HoldTimers, key: KeyEvent) -> bool {
    if app.show_help {
        if matches!(key.code, KeyCode::Esc | KeyCode::Char('h') | KeyCode::Char('H') | KeyCode::Char('?')) {
            app.show_help = false;
        }
        return false;
    }

    match app.screen {
        Screen::Title => handle_title_key(app, key),
        Screen::Connecting => {
            if key.code == KeyCode::Esc {
                app.disconnect_gracefully();
                app.screen = Screen::Title;
            }
            false
        }
        Screen::Lobby => handle_lobby_key(app, key),
        Screen::Loading => {
            if key.code == KeyCode::Esc {
                app.disconnect_gracefully();
                app.screen = Screen::Title;
            }
            false
        }
        Screen::InRun => handle_in_run_key(app, holds, key),
        Screen::Results => match key.code {
            KeyCode::Char('l') | KeyCode::Char('L') => {
                app.screen = Screen::Lobby;
                false
            }
            KeyCode::Char('r') | KeyCode::Char('R') => {
                app.send_lobby_ready(true);
                app.screen = Screen::Lobby;
                false
            }
            KeyCode::Char('q') | KeyCode::Char('Q') | KeyCode::Esc => true,
            _ => false,
        },
        Screen::Disconnected => match key.code {
            KeyCode::Enter => {
                app.screen = Screen::Title;
                false
            }
            KeyCode::Char('r') | KeyCode::Char('R') => {
                app.connect();
                false
            }
            KeyCode::Char('q') | KeyCode::Char('Q') | KeyCode::Esc => true,
            _ => false,
        },
    }
}

fn handle_title_key(app: &mut GameApp, key: KeyEvent) -> bool {
    const NUM_FIELDS: usize = 7;
    match key.code {
        KeyCode::Esc => return true,
        KeyCode::Up => {
            app.title_field = (app.title_field + NUM_FIELDS - 1) % NUM_FIELDS;
        }
        KeyCode::Down | KeyCode::Tab => {
            app.title_field = (app.title_field + 1) % NUM_FIELDS;
        }
        KeyCode::Enter => {
            app.connect();
        }
        KeyCode::Left => match app.title_field {
            0 => app.config.use_tcp = !app.config.use_tcp,
            2 => {
                app.config.enc = match app.config.enc {
                    Encoding::Json => Encoding::Bin,
                    Encoding::Bin => Encoding::Json,
                };
            }
            5 => app.config.color = (app.config.color + 9) % 10,
            6 => app.config.skin = (app.config.skin + 4) % 5,
            _ => {}
        },
        KeyCode::Right => match app.title_field {
            0 => app.config.use_tcp = !app.config.use_tcp,
            2 => {
                app.config.enc = match app.config.enc {
                    Encoding::Json => Encoding::Bin,
                    Encoding::Bin => Encoding::Json,
                };
            }
            5 => app.config.color = (app.config.color + 1) % 10,
            6 => app.config.skin = (app.config.skin + 1) % 5,
            _ => {}
        },
        KeyCode::Backspace => match app.title_field {
            1 => {
                if app.config.use_tcp {
                    app.config.tcp_addr.pop();
                } else {
                    app.config.ws_url.pop();
                }
            }
            3 => {
                app.config.name.pop();
            }
            4 => {
                app.config.code.pop();
            }
            _ => {}
        },
        KeyCode::Char(c) => match app.title_field {
            1 => {
                if app.config.use_tcp {
                    app.config.tcp_addr.push(c);
                } else {
                    app.config.ws_url.push(c);
                }
            }
            3 => {
                if app.config.name.len() < 18 {
                    app.config.name.push(c);
                }
            }
            4 => {
                if app.config.code.len() < 32 {
                    app.config.code.push(c);
                }
            }
            _ => {}
        },
        _ => {}
    }
    false
}

fn handle_lobby_key(app: &mut GameApp, key: KeyEvent) -> bool {
    if app.chat_input_active {
        match key.code {
            KeyCode::Esc => {
                app.chat_input_active = false;
                app.chat_draft.clear();
            }
            KeyCode::Enter => {
                let msg = std::mem::take(&mut app.chat_draft);
                app.send_chat(&msg);
                app.chat_input_active = false;
            }
            KeyCode::Backspace => {
                app.chat_draft.pop();
            }
            KeyCode::Char(c) => {
                if app.chat_draft.len() < 100 {
                    app.chat_draft.push(c);
                }
            }
            _ => {}
        }
        return false;
    }

    match key.code {
        KeyCode::Char('q') | KeyCode::Char('Q') | KeyCode::Esc => return true,
        KeyCode::Char('r') | KeyCode::Char('R') => app.toggle_lobby_ready(),
        KeyCode::Char('f') | KeyCode::Char('F') => app.send_force_start(),
        KeyCode::Char('c') | KeyCode::Char('C') => app.chat_input_active = true,
        KeyCode::Char('h') | KeyCode::Char('H') | KeyCode::Char('?') => app.show_help = true,
        KeyCode::Char(d @ '1'..='9') => {
            let idx = (d as u8 - b'1') as usize;
            if let Some(m) = app.server_maps.get(idx).cloned() {
                app.send_map_vote(&m.id);
            } else if idx == app.server_maps.len() {
                app.send_map_vote("random");
            }
        }
        _ => {}
    }
    false
}

fn handle_in_run_key(app: &mut GameApp, holds: &mut HoldTimers, key: KeyEvent) -> bool {
    // Modal overlays intercept keys first
    if app.show_starter_picker {
        match key.code {
            KeyCode::Char('1') => app.pick_starter(0),
            KeyCode::Char('2') => app.pick_starter(1),
            KeyCode::Char('3') => app.pick_starter(2),
            KeyCode::Esc => app.show_starter_picker = false,
            _ => {}
        }
        return false;
    }

    if app.draft.is_some() {
        match key.code {
            KeyCode::Char('1') => app.vote_mutation(0),
            KeyCode::Char('2') => app.vote_mutation(1),
            KeyCode::Char('3') => app.vote_mutation(2),
            _ => {}
        }
        return false;
    }

    if app.tape_choice_pending && app.is_first_roster_peer() {
        match key.code {
            KeyCode::Char('c') | KeyCode::Char('C') => app.choose_tape(true),
            KeyCode::Char('e') | KeyCode::Char('E') => app.choose_tape(false),
            _ => {}
        }
        return false;
    }

    const HOLD_WINDOW: f32 = 0.22;
    let shift = key.modifiers.contains(KeyModifiers::SHIFT);
    match key.code {
        KeyCode::Esc => return true,
        KeyCode::Char('w') | KeyCode::Char('W') => {
            holds.forward = HOLD_WINDOW;
            if shift {
                app.input.sprint = true;
            }
        }
        KeyCode::Char('s') | KeyCode::Char('S') => holds.back = HOLD_WINDOW,
        KeyCode::Char('a') | KeyCode::Char('A') => holds.left = HOLD_WINDOW,
        KeyCode::Char('d') | KeyCode::Char('D') => holds.right = HOLD_WINDOW,
        KeyCode::Left | KeyCode::Char('j') | KeyCode::Char('J') => holds.turn_left = HOLD_WINDOW,
        KeyCode::Right | KeyCode::Char('l') | KeyCode::Char('L') => holds.turn_right = HOLD_WINDOW,
        KeyCode::Up | KeyCode::Char('i') | KeyCode::Char('I') => holds.look_up = HOLD_WINDOW,
        KeyCode::Down | KeyCode::Char('k') | KeyCode::Char('K') => holds.look_down = HOLD_WINDOW,
        KeyCode::Char('v') | KeyCode::Char('V') => app.input.sprint = !app.input.sprint,
        KeyCode::Char('c') | KeyCode::Char('C') => app.input.crouch = !app.input.crouch,
        KeyCode::Char('z') | KeyCode::Char('Z') => app.input.ads = !app.input.ads,
        KeyCode::Char('x') | KeyCode::Char('X') => app.input.jump_buffer = 0.12,
        KeyCode::Char(' ') | KeyCode::Enter => app.fire_or_use(),
        KeyCode::Char('r') | KeyCode::Char('R') => app.reload_weapon(),
        KeyCode::Char('1') => app.select_slot(0),
        KeyCode::Char('2') => app.select_slot(1),
        KeyCode::Char('3') => app.select_slot(2),
        KeyCode::Char('4') => app.select_slot(3),
        KeyCode::Char('5') => app.select_slot(4),
        KeyCode::Char('q') | KeyCode::Char('Q') => app.throw_pouch("frag"),
        KeyCode::Char('f') | KeyCode::Char('F') => app.throw_pouch("shield_dome"),
        KeyCode::Char('e') | KeyCode::Char('E') => app.trigger_interact(),
        KeyCode::Char('p') | KeyCode::Char('P') => app.send_context_ping(),
        KeyCode::Char('t') | KeyCode::Char('T') => app.toggle_tarp(),
        KeyCode::Char('g') | KeyCode::Char('G') => app.send_calm_ready(),
        KeyCode::Char('b') | KeyCode::Char('B') => app.drop_held_item(),
        KeyCode::Char('m') | KeyCode::Char('M') => app.view_mode = app.view_mode.next(),
        KeyCode::Char('h') | KeyCode::Char('H') | KeyCode::Char('?') => app.show_help = true,
        _ => {}
    }
    false
}

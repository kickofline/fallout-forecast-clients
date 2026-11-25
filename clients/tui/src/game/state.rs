#![allow(dead_code)]

use std::collections::{BTreeMap, HashMap, VecDeque};
use std::time::{Duration, Instant};

use crate::protocol::frame::{
    Encoding, InboundMessage, MapInfo, OutboundMessage, RpcMessage, GAME_PROTOCOL_VERSION,
    OPEN_PROTOCOL_VERSION,
};
use crate::protocol::transport::{NetClientHandle, NetEvent, TransportEndpoint};
use crate::protocol::variant::Variant;

use super::data::{GameCatalog, MapData};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Screen {
    Title,
    Connecting,
    Lobby,
    Loading,
    InRun,
    Results,
    Disconnected,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ViewMode {
    FpsWithMinimap,
    FullFps,
    TopDownMap,
}

impl ViewMode {
    pub fn next(self) -> Self {
        match self {
            ViewMode::FpsWithMinimap => ViewMode::FullFps,
            ViewMode::FullFps => ViewMode::TopDownMap,
            ViewMode::TopDownMap => ViewMode::FpsWithMinimap,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            ViewMode::FpsWithMinimap => "3D FPS + RADAR",
            ViewMode::FullFps => "FULL 3D FPS",
            ViewMode::TopDownMap => "TACTICAL MAP",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ConnectConfig {
    pub use_tcp: bool,
    pub ws_url: String,
    pub tcp_addr: String,
    pub enc: Encoding,
    pub name: String,
    pub code: String,
    pub color: i64,
    pub skin: i64,
}

impl ConnectConfig {
    pub fn endpoint(&self) -> TransportEndpoint {
        if self.use_tcp {
            TransportEndpoint::Tcp(self.tcp_addr.clone())
        } else {
            TransportEndpoint::WebSocket(self.ws_url.clone())
        }
    }
}

#[derive(Debug, Clone)]
pub struct RosterEntry {
    pub peer_id: i64,
    pub name: String,
    pub ready: bool,
    pub color: i64,
    pub skin: i64,
}

#[derive(Debug, Clone)]
pub struct ChatLine {
    pub sender: String,
    pub text: String,
}

#[derive(Debug, Clone)]
pub struct PlayerEntity {
    pub peer_id: i64,
    pub name: String,
    pub color: i64,
    pub skin: i64,
    pub pos: [f32; 3],
    pub target_pos: [f32; 3],
    pub vel: [f32; 3],
    pub yaw: f32,
    pub pitch: f32,
    pub last_relay: Instant,
    pub hp: f32,
    pub max_hp: f32,
    pub suit: f32,
    pub state: String, // "ok" | "downed" | "turned" | "out"
    pub bleed: f32,
    pub tarp: bool,
    pub charge: f32,
    pub invuln: bool,
    pub held_item: String,
    pub held_tier: i32,
}

impl PlayerEntity {
    pub fn new(peer_id: i64, name: String, color: i64, skin: i64, pos: [f32; 3], yaw: f32) -> Self {
        Self {
            peer_id,
            name,
            color,
            skin,
            pos,
            target_pos: pos,
            vel: [0.0; 3],
            yaw,
            pitch: 0.0,
            last_relay: Instant::now(),
            hp: 100.0,
            max_hp: 100.0,
            suit: 100.0,
            state: "ok".into(),
            bleed: 0.0,
            tarp: false,
            charge: 0.0,
            invuln: false,
            held_item: String::new(),
            held_tier: 0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct EnemyEntity {
    pub net_id: i32,
    pub kind: i32,
    pub pos: [f32; 3],
    pub target_pos: [f32; 3],
    pub yaw: f32,
    pub small: bool,
    pub elite: bool,
    pub miniboss_wave: i32,
    pub hp: Option<f32>,
    pub max_hp: Option<f32>,
    pub hit_flash: f32,
    pub tell_timer: f32,
}

#[derive(Debug, Clone)]
pub struct BossCumulusState {
    pub pos: [f32; 3],
    pub parts: Vec<f32>,
    pub sacs: i32,
    pub burn: f32,
}

#[derive(Debug, Clone)]
pub struct InventoryItem {
    pub serial: i64,
    pub id: String,
    pub tier: i32,
    pub count: i32,
}

#[derive(Debug, Clone, Default)]
pub struct InventoryState {
    pub rev: i64,
    pub slots: [Option<InventoryItem>; 5],
    pub stash: HashMap<String, i64>,
    pub selected_slot: usize,
    pub selected_pouch: String, // "", "frag", "shield_dome"
    pub scrap: i64,
    pub frags: i64,
    pub shield_domes: i64,
    pub reload_left: f32,
    pub reload_total: f32,
    pub jam_left: f32,
    pub cooldown: f32,
    pub has_tarp: bool,
}

impl InventoryState {
    pub fn held_item(&self) -> Option<&InventoryItem> {
        self.slots.get(self.selected_slot).and_then(|s| s.as_ref())
    }

    pub fn held_serial(&self) -> i64 {
        self.held_item().map(|i| i.serial).unwrap_or(0)
    }
}

#[derive(Debug, Clone)]
pub struct PickupEntity {
    pub id: i64,
    pub pos: [f32; 3],
    pub item: Option<InventoryItem>,
    pub flavor: String,
    pub claim_peer: i64,
}

#[derive(Debug, Clone)]
pub struct ProjectileEffect {
    pub seq: i64,
    pub id: String,
    pub pos: [f32; 3],
    pub vel: [f32; 3],
    pub tier: i32,
    pub deployed: bool,
    pub life_left: f32,
    pub yaw: f32,
}

#[derive(Debug, Clone)]
pub struct VendingOffer {
    pub item_id: String,
    pub tier: i32,
    pub price: i64,
    pub serial: i64,
}

#[derive(Debug, Clone)]
pub struct AirdropState {
    pub pos: [f32; 3],
    pub descent_left: f32,
}

#[derive(Debug, Clone)]
pub struct AcidCloud {
    pub id: i64,
    pub pos: [f32; 3],
    pub radius: f32,
}

#[derive(Debug, Clone)]
pub struct SporeArc {
    pub id: i64,
    pub from: [f32; 3],
    pub to: [f32; 3],
    pub elapsed: f32,
    pub flight: f32,
}

#[derive(Debug, Clone)]
pub struct TransientTracer {
    pub origin: [f32; 3],
    pub end: [f32; 3],
    pub impact: i32,
    pub ttl: f32,
}

#[derive(Debug, Clone)]
pub struct TransientBlast {
    pub pos: [f32; 3],
    pub size: f32,
    pub rgb: (u8, u8, u8),
    pub ttl: f32,
}

#[derive(Debug, Clone)]
pub struct SquadPing {
    pub peer_id: i64,
    pub kind: String,
    pub pos: [f32; 3],
    pub ttl: f32,
}

#[derive(Debug, Clone)]
pub struct BannerMsg {
    pub text: String,
    pub rgb: (u8, u8, u8),
    pub ttl: f32,
}

#[derive(Debug, Clone)]
pub struct MutationDraftState {
    pub enemy_mutation: String,
    pub dealt: Vec<String>,
    pub votes: Vec<i64>,
    pub my_vote: Option<usize>,
}

#[derive(Debug, Clone)]
pub struct PlayerResultRow {
    pub peer_id: i64,
    pub name: String,
    pub kills: i64,
    pub revives: i64,
    pub turned: i64,
    pub cursed: String,
    pub weapon: String,
}

#[derive(Debug, Clone)]
pub struct ResultsSummary {
    pub won: bool,
    pub map_id: String,
    pub waves: i64,
    pub wave_reached: i64,
    pub endless: bool,
    pub endless_score: i64,
    pub seconds: i64,
    pub squad_mutations: Vec<String>,
    pub players: Vec<PlayerResultRow>,
}

#[derive(Debug, Clone)]
pub struct ActiveInteract {
    pub label: String,
    pub kind: InteractKind,
    pub elapsed: f32,
    pub duration: f32,
}

#[derive(Debug, Clone)]
pub enum InteractKind {
    Decon { path: String, pos: [f32; 3] },
    Revive { path: String, pos: [f32; 3] },
    Vending { key: String, mode: String, serial: i64, pos: [f32; 3] },
}

#[derive(Debug, Clone, Default)]
pub struct InputState {
    pub forward: bool,
    pub back: bool,
    pub left: bool,
    pub right: bool,
    pub sprint: bool,
    pub crouch: bool,
    pub ads: bool,
    pub turn_left: bool,
    pub turn_right: bool,
    pub look_up: bool,
    pub look_down: bool,
    pub jump_buffer: f32,
}

#[derive(Debug, Clone, Default)]
pub struct SmokeStats {
    pub welcome_ok: bool,
    pub pong_ok: bool,
    pub roster_ok: bool,
    pub start_run_ok: bool,
    pub run_ready_ok: bool,
    pub starter_accepted: bool,
    pub transforms_sent: u64,
    pub exposure_reports: u64,
    pub shots_sent: u64,
    pub shot_fx_received: u64,
    pub enemies_spawned: u64,
    pub enemy_syncs: u64,
    pub vitals_received: u64,
    pub phases_received: u64,
    pub protocol_errors: Vec<String>,
}

pub struct GameApp {
    pub catalog: GameCatalog,
    pub config: ConnectConfig,
    pub screen: Screen,
    pub view_mode: ViewMode,
    pub show_help: bool,

    // Title screen focus
    pub title_field: usize,

    // Network session
    pub net: Option<NetClientHandle>,
    pub status_line: String,
    pub disconnect_reason: String,
    pub you: i64,
    pub game_protocol: i64,
    pub rtt_ms: f32,
    pub ping_sent_at: Option<Instant>,
    pub server_maps: Vec<MapInfo>,

    // Lobby state
    pub roster: Vec<RosterEntry>,
    pub default_map: String,
    pub voting_enabled: bool,
    pub vote_counts: HashMap<String, i64>,
    pub my_vote: String,
    pub chat_log: VecDeque<ChatLine>,
    pub chat_input_active: bool,
    pub chat_draft: String,

    // Run lifecycle
    pub current_map_id: String,
    pub current_map: Option<MapData>,
    pub run_id: i64,
    pub run_ready: bool,
    pub starter_chosen: bool,
    pub show_starter_picker: bool,
    pub run_finished_ignore: bool,

    // Local player physics
    pub my_pos: [f32; 3],
    pub my_vel: [f32; 3],
    pub my_pull: [f32; 3],
    pub my_yaw: f32,
    pub my_pitch: f32,
    pub on_ground: bool,
    pub coyote_timer: f32,
    pub eye_height: f32,
    pub input: InputState,
    pub last_transform_push: Instant,
    pub is_sheltered: bool,
    pub is_in_puddle: bool,
    pub exposure_sent_once: bool,
    pub last_shot_at: Instant,
    pub walk_phase: f32,
    pub view_recoil: f32,
    pub muzzle_flash_ttl: f32,
    pub hit_marker_ttl: f32,
    pub hit_marker_crit: bool,
    pub hurt_flash_ttl: f32,
    pub acid_flash_ttl: f32,
    pub prev_suit: f32,
    pub prev_hp: f32,

    // World entities
    pub players: BTreeMap<i64, PlayerEntity>,
    pub enemies: HashMap<i32, EnemyEntity>,
    pub boss: Option<BossCumulusState>,
    pub inventory: InventoryState,
    pub pickups: HashMap<i64, PickupEntity>,
    pub effects: HashMap<i64, ProjectileEffect>,
    pub cabinets: HashMap<String, Vec<VendingOffer>>,
    pub airdrop: Option<AirdropState>,
    pub clouds: HashMap<i64, AcidCloud>,
    pub spores: HashMap<i64, SporeArc>,
    pub tracers: Vec<TransientTracer>,
    pub blasts: Vec<TransientBlast>,
    pub pings: Vec<SquadPing>,
    pub banners: VecDeque<BannerMsg>,
    pub feed: VecDeque<String>,

    // Weather & wave
    pub phase: i32, // 0 Calm, 2 Drizzle, 3 Downpour, 4 Clearing
    pub wave: i32,
    pub phase_time_left: f32,
    pub storm_intensity: f32,
    pub intensity_override: f32,
    pub lightning_flash: f32,
    pub lightning_bolt_col: Option<f32>,
    pub puddle_growth: HashMap<String, f32>,
    pub puddle_tick_accum: f32,
    pub enemies_left: i32,
    pub enemies_total: i32,
    pub endless_score: i64,
    pub decon_charges: i64,
    pub ready_count: i32,
    pub ready_needed: i32,
    pub paused: bool,
    pub paused_by: String,

    // Mutations & Tape & Results
    pub active_enemy_mutations: Vec<String>,
    pub active_player_mutations: Vec<String>,
    pub draft: Option<MutationDraftState>,
    pub draft_hold_timer: f32,
    pub tape_choice_pending: bool,
    pub is_endless: bool,
    pub tape_locked: bool,
    pub active_interact: Option<ActiveInteract>,
    pub results: Option<ResultsSummary>,

    // Stats for smoke-test verification
    pub smoke: SmokeStats,
}

impl GameApp {
    pub fn new(config: ConnectConfig) -> Self {
        let catalog = GameCatalog::load_embedded();
        let default_maps = vec![
            MapInfo { id: "pinecrest".into(), name: "PINECREST".into() },
            MapInfo { id: "harbor".into(), name: "HARBOR POINT".into() },
            MapInfo { id: "maple_hollow".into(), name: "MAPLE HOLLOW".into() },
        ];
        Self {
            catalog,
            config,
            screen: Screen::Title,
            view_mode: ViewMode::FpsWithMinimap,
            show_help: false,
            title_field: 0,
            net: None,
            status_line: "Configure endpoint and press Enter to connect".into(),
            disconnect_reason: String::new(),
            you: 0,
            game_protocol: GAME_PROTOCOL_VERSION,
            rtt_ms: 0.0,
            ping_sent_at: None,
            server_maps: default_maps,
            roster: Vec::new(),
            default_map: "pinecrest".into(),
            voting_enabled: true,
            vote_counts: HashMap::new(),
            my_vote: String::new(),
            chat_log: VecDeque::with_capacity(64),
            chat_input_active: false,
            chat_draft: String::new(),
            current_map_id: "pinecrest".into(),
            current_map: None,
            run_id: 0,
            run_ready: false,
            starter_chosen: false,
            show_starter_picker: false,
            run_finished_ignore: false,
            my_pos: [0.0; 3],
            my_vel: [0.0; 3],
            my_pull: [0.0; 3],
            my_yaw: 0.0,
            my_pitch: 0.0,
            on_ground: true,
            coyote_timer: 0.0,
            eye_height: 1.65,
            input: InputState::default(),
            last_transform_push: Instant::now(),
            is_sheltered: false,
            is_in_puddle: false,
            exposure_sent_once: false,
            last_shot_at: Instant::now() - Duration::from_secs(2),
            walk_phase: 0.0,
            view_recoil: 0.0,
            muzzle_flash_ttl: 0.0,
            hit_marker_ttl: 0.0,
            hit_marker_crit: false,
            hurt_flash_ttl: 0.0,
            acid_flash_ttl: 0.0,
            prev_suit: 100.0,
            prev_hp: 100.0,
            players: BTreeMap::new(),
            enemies: HashMap::new(),
            boss: None,
            inventory: InventoryState::default(),
            pickups: HashMap::new(),
            effects: HashMap::new(),
            cabinets: HashMap::new(),
            airdrop: None,
            clouds: HashMap::new(),
            spores: HashMap::new(),
            tracers: Vec::new(),
            blasts: Vec::new(),
            pings: Vec::new(),
            banners: VecDeque::new(),
            feed: VecDeque::with_capacity(32),
            phase: 0,
            wave: 1,
            phase_time_left: 12.0,
            storm_intensity: 0.0,
            intensity_override: -1.0,
            lightning_flash: 0.0,
            lightning_bolt_col: None,
            puddle_growth: HashMap::new(),
            puddle_tick_accum: 0.0,
            enemies_left: 0,
            enemies_total: 0,
            endless_score: 0,
            decon_charges: 4,
            ready_count: 0,
            ready_needed: 1,
            paused: false,
            paused_by: String::new(),
            active_enemy_mutations: Vec::new(),
            active_player_mutations: Vec::new(),
            draft: None,
            draft_hold_timer: 0.0,
            tape_choice_pending: false,
            is_endless: false,
            tape_locked: false,
            active_interact: None,
            results: None,
            smoke: SmokeStats::default(),
        }
    }

    pub fn push_feed(&mut self, msg: impl Into<String>) {
        let s = msg.into();
        if self.feed.len() >= 12 {
            self.feed.pop_front();
        }
        self.feed.push_back(s);
    }

    pub fn connect(&mut self) {
        let endpoint = self.config.endpoint();
        self.status_line = format!("Connecting to {} ({})...", endpoint.display(), self.config.enc.as_str());
        self.disconnect_reason.clear();
        self.screen = Screen::Connecting;
        self.you = 0;
        self.roster.clear();
        self.chat_log.clear();
        self.run_ready = false;
        self.run_finished_ignore = false;
        self.net = Some(crate::protocol::transport::spawn_connection(
            endpoint,
            self.config.enc,
        ));
    }

    pub fn disconnect_gracefully(&mut self) {
        if let Some(net) = &self.net {
            let _ = net.send(OutboundMessage::Leave);
        }
        self.net = None;
    }

    pub fn send_rpc(&self, rpc: RpcMessage) {
        if let Some(net) = &self.net {
            let _ = net.send(OutboundMessage::Rpc(rpc));
        }
    }

    pub fn send_ping(&mut self) {
        let ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(1);
        self.ping_sent_at = Some(Instant::now());
        if let Some(net) = &self.net {
            let _ = net.send(OutboundMessage::Ping { ms });
        }
    }

    pub fn my_player_node(&self) -> String {
        format!("Main/Players/P_{}", self.you)
    }

    pub fn my_holder_node(&self) -> String {
        format!("Main/Players/P_{}/Head/Camera3D/WeaponHolder", self.you)
    }

    pub fn my_player(&self) -> Option<&PlayerEntity> {
        self.players.get(&self.you)
    }

    pub fn my_state_str(&self) -> &str {
        self.my_player()
            .map(|p| p.state.as_str())
            .unwrap_or("ok")
    }

    pub fn my_look_dir(&self) -> [f32; 3] {
        let cp = self.my_pitch.cos();
        [
            -self.my_yaw.sin() * cp,
            self.my_pitch.sin(),
            -self.my_yaw.cos() * cp,
        ]
    }

    pub fn my_eye_pos(&self) -> [f32; 3] {
        [self.my_pos[0], self.my_pos[1] + self.eye_height, self.my_pos[2]]
    }

    pub fn is_raining(&self) -> bool {
        (self.storm_intensity > 0.02 && (self.phase == 2 || self.phase == 3))
            || self.intensity_override > 0.001
    }

    pub fn phase_label(&self) -> &'static str {
        match self.phase {
            0 => "CALM",
            2 => "DRIZZLE",
            3 => {
                if self.storm_intensity >= 0.9 || self.wave >= 5 {
                    "ACID STORM"
                } else {
                    "DOWNPOUR"
                }
            }
            4 => "CLEARING",
            _ => "CALM",
        }
    }

    pub fn forecast_modifier(&self) -> &'static str {
        match self.wave {
            1 => "CLEAR",
            2 => "BLACKOUT",
            3 => "FLOOD",
            4 => "SWARM",
            5 => "HEAVY WEATHER",
            w if w >= 6 => match (w - 6) % 4 {
                0 => "HEAVY WEATHER",
                1 => "FLOOD",
                2 => "BLACKOUT",
                _ => "SWARM",
            },
            _ => "CLEAR",
        }
    }

    pub fn is_flood_wave(&self) -> bool {
        self.forecast_modifier() == "FLOOD"
    }

    pub fn has_mutation(&self, id: &str) -> bool {
        self.active_player_mutations.iter().any(|m| m == id)
    }

    pub fn is_first_roster_peer(&self) -> bool {
        self.roster.first().map(|r| r.peer_id == self.you).unwrap_or(false)
    }

    pub fn poll_network(&mut self) {
        let mut events = Vec::new();
        if let Some(net) = &mut self.net {
            while let Some(ev) = net.try_recv() {
                events.push(ev);
            }
        }
        for ev in events {
            self.handle_net_event(ev);
        }
    }

    pub fn handle_net_event(&mut self, ev: NetEvent) {
        match ev {
            NetEvent::Connected => {
                self.status_line = "Connected. Sending Open Protocol v1 hello...".into();
                if let Some(net) = &self.net {
                    let _ = net.send(OutboundMessage::Hello {
                        v: OPEN_PROTOCOL_VERSION,
                        tier: "full".into(),
                        enc: self.config.enc,
                        client: "fallout-tui/0.1".into(),
                        code: if self.config.code.is_empty() {
                            None
                        } else {
                            Some(self.config.code.clone())
                        },
                    });
                }
            }
            NetEvent::Message(msg) => self.handle_inbound(msg),
            NetEvent::Disconnected(reason) => {
                self.disconnect_reason = reason.clone();
                self.status_line = format!("Disconnected: {}", reason);
                self.net = None;
                if self.screen != Screen::Title {
                    self.screen = Screen::Disconnected;
                }
            }
        }
    }

    fn handle_inbound(&mut self, msg: InboundMessage) {
        match msg {
            InboundMessage::Welcome {
                v,
                tier,
                enc,
                you,
                game_protocol,
                maps,
            } => {
                self.you = you;
                self.game_protocol = game_protocol;
                if !maps.is_empty() {
                    self.server_maps = maps;
                }
                if v != OPEN_PROTOCOL_VERSION || tier != "full" {
                    self.disconnect_reason = format!(
                        "Unsupported welcome: v={} tier={} enc={}",
                        v,
                        tier,
                        enc.as_str()
                    );
                    self.screen = Screen::Disconnected;
                    self.disconnect_gracefully();
                    return;
                }
                if game_protocol != GAME_PROTOCOL_VERSION {
                    self.disconnect_reason = format!(
                        "Game protocol mismatch: server={}, client={}",
                        game_protocol, GAME_PROTOCOL_VERSION
                    );
                    self.screen = Screen::Disconnected;
                    self.disconnect_gracefully();
                    return;
                }
                self.smoke.welcome_ok = true;
                self.status_line = format!(
                    "Welcome! Peer #{} ({}) — sending Net._hello...",
                    you,
                    enc.as_str()
                );

                // Send control ping for RTT verification
                self.send_ping();

                // Send game handshake Net._hello(json_string, protocol)
                let clean_name: String = self
                    .config
                    .name
                    .chars()
                    .filter(|c| !c.is_control())
                    .take(32)
                    .collect();
                let name = if clean_name.is_empty() {
                    "ASCII-Runner".to_string()
                } else {
                    clean_name
                };
                let hello_json = serde_json::json!({
                    "name": name,
                    "color": self.config.color,
                    "skin": self.config.skin.rem_euclid(5),
                    "colors": []
                })
                .to_string();
                self.send_rpc(RpcMessage::reliable(
                    "Net",
                    "_hello",
                    vec![Variant::String(hello_json), Variant::Int(game_protocol)],
                ));
            }
            InboundMessage::Pong { .. } => {
                self.smoke.pong_ok = true;
                if let Some(t) = self.ping_sent_at.take() {
                    self.rtt_ms = t.elapsed().as_secs_f32() * 1000.0;
                }
            }
            InboundMessage::Error { msg } => {
                self.smoke.protocol_errors.push(msg.clone());
                self.push_feed(format!("! SERVER ERROR: {}", msg));
                if self.screen == Screen::Connecting {
                    self.disconnect_reason = msg;
                    self.screen = Screen::Disconnected;
                }
            }
            InboundMessage::Rpc(rpc) => self.handle_rpc(rpc),
            InboundMessage::Raw { .. } | InboundMessage::Unknown(_) => {}
        }
    }

    fn handle_rpc(&mut self, rpc: RpcMessage) {
        let node = rpc.node.trim_start_matches("/root/").trim_start_matches('/');
        let method = rpc.method.as_str();
        let args = &rpc.args;

        // Always handle Net RPCs in every state
        if node == "Net" {
            self.handle_net_rpc(method, args);
            return;
        }

        // Ignore run-scoped RPCs after _finish until the next _start_run
        if self.run_finished_ignore {
            return;
        }

        match node {
            "GameManager" => self.handle_game_manager_rpc(method, args),
            "GameManager/MutationRoll" => self.handle_mutation_rpc(method, args),
            "GameManager/CrateManager" => self.handle_crate_rpc(method, args),
            "GameManager/Feats" => {
                if method == "_feat_event" {
                    if let Some(id) = args.first().and_then(|v| v.as_str()) {
                        self.push_feed(format!("★ FEAT: {}", id));
                    }
                }
            }
            "WeatherManager" => self.handle_weather_rpc(method, args),
            "Main/Enemies" => self.handle_enemies_rpc(method, args),
            "Main/Enemies/BossCumulus" => self.handle_boss_rpc(method, args),
            "Main/RunLoot" => self.handle_run_loot_rpc(method, args),
            "Main/Pings" => {
                if method == "_show_ping" && args.len() >= 3 {
                    let peer = args[0].as_int().unwrap_or(0);
                    let kind = args[1].as_str().unwrap_or("go").to_string();
                    let pos = args[2].as_vec3().unwrap_or([0.0; 3]);
                    self.pings.push(SquadPing {
                        peer_id: peer,
                        kind: kind.clone(),
                        pos,
                        ttl: 7.0,
                    });
                    self.push_feed(format!("PING [{}] from #{}", kind.to_uppercase(), peer));
                }
            }
            _ => {
                if let Some(rest) = node.strip_prefix("Main/Players/P_") {
                    if let Some((pid_str, sub)) = rest.split_once('/') {
                        if let Ok(pid) = pid_str.parse::<i64>() {
                            if sub == "Head/Camera3D/WeaponHolder" {
                                self.handle_weapon_holder_rpc(pid, method, args);
                            }
                        }
                    } else if let Ok(pid) = rest.parse::<i64>() {
                        self.handle_player_rpc(pid, method, args);
                    }
                } else if node.starts_with("Main/Level/DeconShowers/") && method == "play_spray" {
                    self.push_feed("DECON SHOWER ACTIVATED — SUIT DECONTAMINATED");
                }
            }
        }
    }

    fn handle_net_rpc(&mut self, method: &str, args: &[Variant]) {
        match method {
            "_rtt_ping" => {
                if let Some(seq) = args.first().and_then(|v| v.as_int()) {
                    if let Some(measured) = args.get(1).and_then(|v| v.as_f32()) {
                        if measured > 0.0 {
                            self.rtt_ms = measured;
                        }
                    }
                    self.send_rpc(RpcMessage::unreliable(
                        "Net",
                        "_rtt_pong",
                        vec![Variant::Int(seq)],
                    ));
                }
            }
            "_reject" => {
                let reason = args
                    .first()
                    .and_then(|v| v.as_str())
                    .unwrap_or("Rejected by server")
                    .to_string();
                self.disconnect_reason = reason.clone();
                self.status_line = format!("Rejected: {}", reason);
                self.screen = Screen::Disconnected;
            }
            "_push_roster" => {
                let mut new_roster = Vec::new();
                if let Some(pairs) = args.first().and_then(|v| v.as_dict()) {
                    for (k, v) in pairs {
                        let pid = k.as_int().unwrap_or(0);
                        let name = v
                            .dict_get("name")
                            .and_then(|x| x.as_str())
                            .unwrap_or("PLAYER")
                            .to_string();
                        let ready = v
                            .dict_get("ready")
                            .and_then(|x| x.as_bool())
                            .unwrap_or(false);
                        let color = v.dict_get("color").and_then(|x| x.as_int()).unwrap_or(0);
                        let skin = v.dict_get("skin").and_then(|x| x.as_int()).unwrap_or(0);
                        new_roster.push(RosterEntry {
                            peer_id: pid,
                            name,
                            ready,
                            color,
                            skin,
                        });
                    }
                }
                if let Some(dm) = args.get(1).and_then(|v| v.as_str()) {
                    self.default_map = dm.to_string();
                }
                if let Some(ve) = args.get(2).and_then(|v| v.as_bool()) {
                    self.voting_enabled = ve;
                }
                self.vote_counts.clear();
                if let Some(pairs) = args.get(3).and_then(|v| v.as_dict()) {
                    for (k, v) in pairs {
                        if let (Some(mid), Some(cnt)) = (k.as_str(), v.as_int()) {
                            self.vote_counts.insert(mid.to_string(), cnt);
                        }
                    }
                }
                if let Some(mv) = args.get(4).and_then(|v| v.as_str()) {
                    self.my_vote = mv.to_string();
                }

                if new_roster.iter().any(|r| r.peer_id == self.you) {
                    self.smoke.roster_ok = true;
                }
                self.roster = new_roster;

                if self.screen == Screen::Connecting {
                    self.screen = Screen::Lobby;
                    self.status_line = "In Lobby".into();
                } else if self.screen == Screen::InRun || self.screen == Screen::Loading {
                    self.sync_players_with_roster();
                }
            }
            "_chat_rpc" => {
                let sender = args
                    .first()
                    .and_then(|v| v.as_str())
                    .unwrap_or("?")
                    .to_string();
                let text = args
                    .get(1)
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                if self.chat_log.len() >= 40 {
                    self.chat_log.pop_front();
                }
                self.chat_log.push_back(ChatLine {
                    sender: sender.clone(),
                    text: text.clone(),
                });
                self.push_feed(format!("[{}] {}", sender, text));
            }
            "_start_run" => {
                let map_id = args
                    .first()
                    .and_then(|v| v.as_str())
                    .unwrap_or("pinecrest")
                    .to_string();
                self.smoke.start_run_ok = true;
                self.begin_run_load(&map_id);
            }
            "_confirm_run_ready" => {
                self.run_ready = true;
                self.smoke.run_ready_ok = true;
                self.screen = Screen::InRun;
                self.status_line = format!("In Run — {}", self.current_map_id.to_uppercase());
                if !self.starter_chosen {
                    self.show_starter_picker = true;
                }
                // Immediately send initial exposure report per client-responsibilities §3
                self.update_and_report_exposure(true);
            }
            _ => {}
        }
    }

    fn begin_run_load(&mut self, map_id: &str) {
        self.run_finished_ignore = false;
        self.run_ready = false;
        self.starter_chosen = false;
        self.show_starter_picker = false;
        self.run_id = 0;
        self.current_map_id = map_id.to_string();
        self.current_map = self
            .catalog
            .map_data
            .get(map_id)
            .cloned()
            .or_else(|| self.catalog.map_data.get("pinecrest").cloned());

        self.enemies.clear();
        self.boss = None;
        self.pickups.clear();
        self.effects.clear();
        self.cabinets.clear();
        self.airdrop = None;
        self.clouds.clear();
        self.spores.clear();
        self.tracers.clear();
        self.blasts.clear();
        self.pings.clear();
        self.banners.clear();
        self.draft = None;
        self.draft_hold_timer = 0.0;
        self.tape_choice_pending = false;
        self.is_endless = false;
        self.tape_locked = false;
        self.active_enemy_mutations.clear();
        self.active_player_mutations.clear();
        self.inventory = InventoryState::default();
        self.active_interact = None;
        self.results = None;
        self.puddle_growth.clear();
        self.phase = 0;
        self.wave = 1;
        self.phase_time_left = 12.0;
        self.storm_intensity = 0.0;
        self.intensity_override = -1.0;
        self.lightning_flash = 0.0;
        self.exposure_sent_once = false;
        self.my_vel = [0.0; 3];
        self.my_pull = [0.0; 3];
        self.my_pitch = 0.0;
        self.eye_height = 1.65;
        self.on_ground = true;

        if let Some(map) = &self.current_map {
            for p in &map.puddles {
                self.puddle_growth.insert(p.sync_key.clone(), 0.0);
            }
        }

        // Create player entities sorted by ascending peer_id at spawn i % count
        self.players.clear();
        self.sync_players_with_roster();
        if let Some(me) = self.players.get(&self.you) {
            self.my_pos = me.pos;
            self.my_yaw = me.yaw;
        }

        self.screen = Screen::Loading;
        self.status_line = format!("Loading {}...", map_id.to_uppercase());
        self.push_feed(format!("Deploying to {}...", map_id.to_uppercase()));

        // Report loaded to server
        self.send_rpc(RpcMessage::reliable(
            "Net",
            "_report_in_run",
            vec![Variant::Bool(true)],
        ));
    }

    fn sync_players_with_roster(&mut self) {
        let mut sorted = self.roster.clone();
        sorted.sort_by_key(|r| r.peer_id);

        let active_ids: std::collections::HashSet<i64> =
            sorted.iter().map(|r| r.peer_id).collect();
        self.players.retain(|pid, _| active_ids.contains(pid));

        let spawns = self
            .current_map
            .as_ref()
            .map(|m| m.player_spawns.as_slice())
            .unwrap_or(&[]);

        for (i, entry) in sorted.iter().enumerate() {
            if let Some(existing) = self.players.get_mut(&entry.peer_id) {
                existing.name = entry.name.clone();
                existing.color = entry.color;
                existing.skin = entry.skin;
            } else {
                let (pos, yaw) = if !spawns.is_empty() {
                    let s = &spawns[i % spawns.len()];
                    (s.pos, s.yaw)
                } else {
                    ([0.0, 0.0, 0.0], 0.0)
                };
                self.players.insert(
                    entry.peer_id,
                    PlayerEntity::new(
                        entry.peer_id,
                        entry.name.clone(),
                        entry.color,
                        entry.skin,
                        pos,
                        yaw,
                    ),
                );
            }
        }
    }

    fn handle_game_manager_rpc(&mut self, method: &str, args: &[Variant]) {
        match method {
            "_sync_tape_state" => {
                if args.len() >= 3 {
                    self.tape_choice_pending = args[0].as_bool().unwrap_or(false);
                    self.is_endless = args[1].as_bool().unwrap_or(false);
                    self.tape_locked = args[2].as_bool().unwrap_or(false);
                }
            }
            "_sync_decon" => {
                if let Some(v) = args.first().and_then(|v| v.as_int()) {
                    self.decon_charges = v;
                }
            }
            "_ready_changed" => {
                if args.len() >= 2 {
                    self.ready_count = args[0].as_int().unwrap_or(0) as i32;
                    self.ready_needed = args[1].as_int().unwrap_or(1) as i32;
                }
            }
            "_sync_pause" => {
                if args.len() >= 2 {
                    self.paused = args[0].as_bool().unwrap_or(false);
                    self.paused_by = args[1].as_str().unwrap_or("").to_string();
                }
            }
            "_banner" => {
                let text = args.first().and_then(|v| v.as_str()).unwrap_or("").to_string();
                let rgb = args
                    .get(1)
                    .and_then(|v| v.as_color())
                    .map(|c| {
                        (
                            (c[0].clamp(0.0, 1.0) * 255.0) as u8,
                            (c[1].clamp(0.0, 1.0) * 255.0) as u8,
                            (c[2].clamp(0.0, 1.0) * 255.0) as u8,
                        )
                    })
                    .unwrap_or((120, 235, 220));
                let secs = args.get(2).and_then(|v| v.as_f32()).unwrap_or(2.5);
                if !text.is_empty() {
                    self.push_feed(format!("» {}", text));
                    self.banners.push_back(BannerMsg {
                        text,
                        rgb,
                        ttl: secs.max(0.5),
                    });
                }
            }
            "_spawn_boss" => {
                let pos = args.first().and_then(|v| v.as_vec3()).unwrap_or([0.0, 16.0, 0.0]);
                self.boss = Some(BossCumulusState {
                    pos,
                    parts: vec![100.0, 100.0, 100.0, 300.0],
                    sacs: 3,
                    burn: 0.0,
                });
                self.push_feed("⚠ CUMULUS HAS ARRIVED!");
            }
            "_spawn_cloud" => {
                if args.len() >= 4 {
                    let id = args[0].as_int().unwrap_or(0);
                    let pos = args[1].as_vec3().unwrap_or([0.0; 3]);
                    let radius = args[3].as_f32().unwrap_or(3.0);
                    self.clouds.insert(id, AcidCloud { id, pos, radius });
                }
            }
            "_disperse_cloud" => {
                if let Some(id) = args.first().and_then(|v| v.as_int()) {
                    self.clouds.remove(&id);
                }
            }
            "_spawn_spore" => {
                if args.len() >= 4 {
                    let id = args[0].as_int().unwrap_or(0);
                    let from = args[1].as_vec3().unwrap_or([0.0; 3]);
                    let to = args[2].as_vec3().unwrap_or([0.0; 3]);
                    let flight = args[3].as_f32().unwrap_or(1.0).max(0.1);
                    self.spores.insert(
                        id,
                        SporeArc {
                            id,
                            from,
                            to,
                            elapsed: 0.0,
                            flight,
                        },
                    );
                }
            }
            "_draw_blast" => {
                if args.len() >= 2 {
                    let pos = args[0].as_vec3().unwrap_or([0.0; 3]);
                    let size = args[1].as_f32().unwrap_or(4.0);
                    let rgb = args
                        .get(2)
                        .and_then(|v| v.as_color())
                        .map(|c| {
                            (
                                (c[0].clamp(0.0, 1.0) * 255.0) as u8,
                                (c[1].clamp(0.0, 1.0) * 255.0) as u8,
                                (c[2].clamp(0.0, 1.0) * 255.0) as u8,
                            )
                        })
                        .unwrap_or((255, 160, 60));
                    self.blasts.push(TransientBlast {
                        pos,
                        size,
                        rgb,
                        ttl: 0.45,
                    });
                }
            }
            "_draw_arc" => {
                if let Some(pts) = args.first().and_then(|v| v.as_array()) {
                    for w in pts.windows(2) {
                        if let (Some(a), Some(b)) = (w[0].as_vec3(), w[1].as_vec3()) {
                            self.tracers.push(TransientTracer {
                                origin: a,
                                end: b,
                                impact: 2,
                                ttl: 0.25,
                            });
                        }
                    }
                }
            }
            "_weapon_unlocked" => {
                if let Some(w) = args.first().and_then(|v| v.as_str()) {
                    self.push_feed(format!("UNLOCKED: {}", w));
                }
            }
            "_finish" => {
                let won = args.first().and_then(|v| v.as_bool()).unwrap_or(false);
                let res_var = args.get(1);
                let summary = parse_results(won, res_var);
                self.results = Some(summary);
                self.run_ready = false;
                self.run_finished_ignore = true;
                self.show_starter_picker = false;
                self.draft = None;
                self.tape_choice_pending = false;
                self.active_interact = None;
                self.screen = Screen::Results;
                // Unload run and tell server we left run scene (spec-full §5)
                self.send_rpc(RpcMessage::reliable(
                    "Net",
                    "_report_in_run",
                    vec![Variant::Bool(false)],
                ));
            }
            _ => {}
        }
    }

    fn handle_mutation_rpc(&mut self, method: &str, args: &[Variant]) {
        match method {
            "_reset_run_rpc" => {
                self.active_enemy_mutations.clear();
                self.active_player_mutations.clear();
                self.draft = None;
            }
            "_clear_rpc" => {
                self.active_enemy_mutations.clear();
            }
            "_sync_active" => {
                if args.len() >= 2 {
                    self.active_enemy_mutations = extract_string_list(&args[0]);
                    self.active_player_mutations = extract_string_list(&args[1]);
                }
            }
            "_deal_rpc" => {
                if args.len() >= 2 {
                    let enemy = args[0].as_str().unwrap_or("").to_string();
                    let dealt = extract_string_list(&args[1]);
                    let votes = vec![0; dealt.len()];
                    self.draft = Some(MutationDraftState {
                        enemy_mutation: enemy,
                        dealt,
                        votes,
                        my_vote: None,
                    });
                }
            }
            "_votes_rpc" => {
                if let Some(draft) = &mut self.draft {
                    if let Some(arr) = args.first().and_then(|v| v.as_array()) {
                        draft.votes = arr.iter().map(|v| v.as_int().unwrap_or(0)).collect();
                    }
                }
            }
            "_result_rpc" => {
                if args.len() >= 3 {
                    self.active_enemy_mutations = extract_string_list(&args[1]);
                    self.active_player_mutations = extract_string_list(&args[2]);
                    if let Some(granted) = args.get(3) {
                        let list = extract_string_list(granted);
                        if !list.is_empty() {
                            self.push_feed(format!("MUTATION GRANTED: {}", list.join(", ")));
                        }
                    }
                }
                self.draft = None;
                self.draft_hold_timer = 2.2;
            }
            _ => {}
        }
    }

    fn handle_crate_rpc(&mut self, method: &str, args: &[Variant]) {
        match method {
            "_snapshot" => {
                if let Some(rid) = args.first().and_then(|v| v.as_int()) {
                    if self.run_id == 0 {
                        self.run_id = rid;
                    }
                }
                if let Some(pairs) = args.get(1).and_then(|v| v.as_dict()) {
                    self.cabinets.clear();
                    for (k, v) in pairs {
                        if let Some(key) = k.as_str() {
                            self.cabinets.insert(key.to_string(), parse_offers(v));
                        }
                    }
                }
                if let Some(drop_arr) = args.get(2).and_then(|v| v.as_array()) {
                    if drop_arr.len() >= 2 {
                        let pos = drop_arr[0].as_vec3().unwrap_or([0.0; 3]);
                        let descent = drop_arr[1].as_f32().unwrap_or(0.0);
                        self.airdrop = Some(AirdropState {
                            pos,
                            descent_left: descent,
                        });
                    } else {
                        self.airdrop = None;
                    }
                }
            }
            "_stock" => {
                if args.len() >= 3 {
                    if let Some(key) = args[1].as_str() {
                        self.cabinets.insert(key.to_string(), parse_offers(&args[2]));
                    }
                }
            }
            "_airdrop_spawn" => {
                if args.len() >= 3 {
                    let pos = args[1].as_vec3().unwrap_or([0.0; 3]);
                    let descent = args[2].as_f32().unwrap_or(2.4);
                    self.airdrop = Some(AirdropState {
                        pos,
                        descent_left: descent,
                    });
                    self.push_feed("AIRDROP LANDING!");
                }
            }
            "_remove_drop" => {
                self.airdrop = None;
            }
            "_reveal" => {
                if args.len() >= 5 {
                    let title = args[4].as_str().unwrap_or("Item");
                    self.push_feed(format!("VENDING: {}", title));
                }
            }
            _ => {}
        }
    }

    fn handle_weather_rpc(&mut self, method: &str, args: &[Variant]) {
        match method {
            "_receive_phase" => {
                if args.len() >= 3 {
                    self.phase = args[0].as_int().unwrap_or(0) as i32;
                    self.wave = args[1].as_int().unwrap_or(1) as i32;
                    self.phase_time_left = args[2].as_f32().unwrap_or(0.0);
                    self.smoke.phases_received += 1;
                }
            }
            "_receive_intensity" => {
                if let Some(v) = args.first().and_then(|v| v.as_f32()) {
                    self.storm_intensity = v;
                }
            }
            "_override" => {
                if let Some(v) = args.first().and_then(|v| v.as_f32()) {
                    self.intensity_override = v;
                }
            }
            "_strike" => {
                self.lightning_flash = 1.0;
                if let Some(pos) = args.first().and_then(|v| v.as_vec3()) {
                    let dx = pos[0] - self.my_pos[0];
                    let dz = pos[2] - self.my_pos[2];
                    let angle = (-dx).atan2(-dz) - self.my_yaw;
                    self.lightning_bolt_col = Some(angle);
                }
            }
            "_sync_puddles" => {
                if let Some(pairs) = args.first().and_then(|v| v.as_dict()) {
                    for (k, v) in pairs {
                        if let (Some(path), Some(g)) = (k.as_str(), v.as_f32()) {
                            self.puddle_growth.insert(path.to_string(), g.clamp(0.0, 1.0));
                        }
                    }
                }
            }
            _ => {}
        }
    }

    fn handle_enemies_rpc(&mut self, method: &str, args: &[Variant]) {
        match method {
            "_spawn_enemy" => {
                if args.len() >= 3 {
                    let net_id = args[0].as_int().unwrap_or(0) as i32;
                    let kind = args[1].as_int().unwrap_or(0) as i32;
                    let pos = args[2].as_vec3().unwrap_or([0.0; 3]);
                    let small = args.get(3).and_then(|v| v.as_bool()).unwrap_or(false);
                    let elite = args.get(4).and_then(|v| v.as_bool()).unwrap_or(false);
                    let miniboss_wave = args.get(5).and_then(|v| v.as_int()).unwrap_or(0) as i32;
                    let max_hp = self
                        .catalog
                        .enemy_kinds
                        .get(&kind)
                        .map(|e| e.max_health);
                    self.enemies.insert(
                        net_id,
                        EnemyEntity {
                            net_id,
                            kind,
                            pos,
                            target_pos: pos,
                            yaw: 0.0,
                            small,
                            elite,
                            miniboss_wave,
                            hp: max_hp,
                            max_hp,
                            hit_flash: 0.0,
                            tell_timer: 0.0,
                        },
                    );
                    self.smoke.enemies_spawned += 1;
                }
            }
            "_sync_enemies" => {
                if args.len() >= 3 {
                    let ids = args[0].as_packed_i32().unwrap_or_default();
                    let places = args[1].as_packed_v3().unwrap_or_default();
                    let yaws = args[2].as_packed_f32().unwrap_or_default();
                    let n = ids.len().min(places.len()).min(yaws.len());
                    for i in 0..n {
                        if let Some(e) = self.enemies.get_mut(&ids[i]) {
                            e.target_pos = places[i];
                            e.yaw = yaws[i];
                        }
                    }
                    self.smoke.enemy_syncs += 1;
                }
            }
            "_despawn_enemy" => {
                if let Some(id) = args.first().and_then(|v| v.as_int()) {
                    if let Some(e) = self.enemies.remove(&(id as i32)) {
                        let crit = args.get(4).and_then(|v| v.as_bool()).unwrap_or(false);
                        let pos = args.get(2).and_then(|v| v.as_vec3()).unwrap_or(e.pos);
                        self.blasts.push(TransientBlast {
                            pos,
                            size: if crit { 1.6 } else { 1.0 },
                            rgb: if crit { (255, 220, 80) } else { (160, 235, 90) },
                            ttl: 0.25,
                        });
                    }
                }
            }
            "_retire_enemies" => {
                if let Some(ids) = args.first().and_then(|v| v.as_packed_i32()) {
                    for id in ids {
                        self.enemies.remove(&id);
                    }
                }
            }
            "_enemy_impacts" => {
                if let Some(rows) = args.first().and_then(|v| v.as_array()) {
                    for row in rows {
                        if let Some(cols) = row.as_array() {
                            if let Some(id) = cols.first().and_then(|v| v.as_int()) {
                                if let Some(e) = self.enemies.get_mut(&(id as i32)) {
                                    e.hit_flash = 0.2;
                                }
                            }
                        }
                    }
                }
            }
            "_play_enemy_tell" => {
                if let Some(id) = args.first().and_then(|v| v.as_int()) {
                    let dur = args.get(2).and_then(|v| v.as_f32()).unwrap_or(0.6);
                    if let Some(e) = self.enemies.get_mut(&(id as i32)) {
                        e.tell_timer = dur;
                    }
                }
            }
            "_sync_miniboss_hp" => {
                if args.len() >= 3 {
                    let id = args[0].as_int().unwrap_or(0) as i32;
                    let hp = args[1].as_f32().unwrap_or(0.0);
                    let max_hp = args[2].as_f32().unwrap_or(1.0);
                    if let Some(e) = self.enemies.get_mut(&id) {
                        e.hp = Some(hp);
                        e.max_hp = Some(max_hp);
                    }
                }
            }
            "_sync_progress" => {
                if args.len() >= 5 {
                    self.wave = args[0].as_int().unwrap_or(1) as i32;
                    self.enemies_left = args[1].as_int().unwrap_or(0) as i32;
                    self.enemies_total = args[2].as_int().unwrap_or(0) as i32;
                    self.endless_score = args[4].as_int().unwrap_or(0);
                }
            }
            "_receive_group_warning" => {
                self.push_feed("⚠ INFECTED GROUP APPROACHING");
            }
            _ => {}
        }
    }

    fn handle_boss_rpc(&mut self, method: &str, args: &[Variant]) {
        match method {
            "_sync" => {
                if args.len() >= 4 {
                    let pos = args[0].as_vec3().unwrap_or([0.0, 16.0, 0.0]);
                    let parts = args[1]
                        .as_array()
                        .map(|a| a.iter().filter_map(|x| x.as_f32()).collect())
                        .unwrap_or_default();
                    let sacs = args[2].as_int().unwrap_or(0) as i32;
                    let burn = args[3].as_f32().unwrap_or(0.0);
                    self.boss = Some(BossCumulusState {
                        pos,
                        parts,
                        sacs,
                        burn,
                    });
                }
            }
            "_died" => {
                self.boss = None;
                self.push_feed("★ CUMULUS DEFEATED!");
            }
            _ => {}
        }
    }

    fn handle_run_loot_rpc(&mut self, method: &str, args: &[Variant]) {
        match method {
            "_snapshot" => {
                if let Some(rid) = args.first().and_then(|v| v.as_int()) {
                    self.run_id = rid;
                }
                self.pickups.clear();
                if let Some(rows) = args.get(1).and_then(|v| v.as_array()) {
                    for entry in rows {
                        if let Some(pair) = entry.as_array() {
                            if pair.len() >= 2 {
                                let pid = pair[0].as_int().unwrap_or(0);
                                if let Some(p) = parse_pickup(pid, &pair[1]) {
                                    self.pickups.insert(pid, p);
                                }
                            }
                        }
                    }
                }
                self.effects.clear();
                if let Some(effs) = args.get(2).and_then(|v| v.as_array()) {
                    for entry in effs {
                        if let Some(pair) = entry.as_array() {
                            if pair.len() >= 2 {
                                let seq = pair[0].as_int().unwrap_or(0);
                                if let Some(eff) = parse_effect(seq, &pair[1]) {
                                    self.effects.insert(seq, eff);
                                }
                            }
                        }
                    }
                }
                if let Some(chosen) = args.get(4).and_then(|v| v.as_bool()) {
                    self.starter_chosen = chosen;
                    if chosen {
                        self.show_starter_picker = false;
                    }
                }
            }
            "_spawn" => {
                if args.len() >= 3 {
                    let pid = args[1].as_int().unwrap_or(0);
                    if let Some(p) = parse_pickup(pid, &args[2]) {
                        self.pickups.insert(pid, p);
                    }
                }
            }
            "_remove" => {
                if args.len() >= 2 {
                    let pid = args[1].as_int().unwrap_or(0);
                    self.pickups.remove(&pid);
                }
            }
            "_release" => {
                if args.len() >= 2 {
                    let pid = args[1].as_int().unwrap_or(0);
                    if let Some(p) = self.pickups.get_mut(&pid) {
                        p.claim_peer = 0;
                    }
                }
            }
            "_starter_accepted" => {
                self.starter_chosen = true;
                self.show_starter_picker = false;
                self.smoke.starter_accepted = true;
                self.push_feed("Starter kit equipped!");
            }
            "_effect_spawn" => {
                if args.len() >= 3 {
                    let seq = args[1].as_int().unwrap_or(0);
                    if let Some(eff) = parse_effect(seq, &args[2]) {
                        self.effects.insert(seq, eff);
                    }
                }
            }
            "_flight" => {
                if let Some(rows) = args.get(1).and_then(|v| v.as_array()) {
                    for row in rows {
                        if let Some(cols) = row.as_array() {
                            if cols.len() >= 3 {
                                let seq = cols[0].as_int().unwrap_or(0);
                                if let Some(eff) = self.effects.get_mut(&seq) {
                                    if let Some(p) = cols[1].as_vec3() {
                                        eff.pos = p;
                                    }
                                    if let Some(v) = cols[2].as_vec3() {
                                        eff.vel = v;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            "_effect_deploy" => {
                if args.len() >= 5 {
                    let seq = args[1].as_int().unwrap_or(0);
                    if let Some(eff) = self.effects.get_mut(&seq) {
                        eff.pos = args[2].as_vec3().unwrap_or(eff.pos);
                        eff.vel = [0.0; 3];
                        eff.deployed = true;
                        eff.life_left = args[3].as_f32().unwrap_or(eff.life_left);
                        eff.yaw = args[4].as_f32().unwrap_or(eff.yaw);
                    }
                }
            }
            "_effect_end" => {
                if args.len() >= 4 {
                    let seq = args[1].as_int().unwrap_or(0);
                    let pos = args[2].as_vec3().unwrap_or([0.0; 3]);
                    let blast = args[3].as_bool().unwrap_or(false);
                    self.effects.remove(&seq);
                    if blast {
                        self.blasts.push(TransientBlast {
                            pos,
                            size: 5.5,
                            rgb: (255, 165, 65),
                            ttl: 0.45,
                        });
                    }
                }
            }
            _ => {}
        }
    }

    fn handle_player_rpc(&mut self, pid: i64, method: &str, args: &[Variant]) {
        match method {
            "_relay_transform" => {
                // Ignore echo for our own peer id (spec-full §12)
                if pid == self.you {
                    return;
                }
                if args.len() >= 4 {
                    let pos = args[0].as_vec3().unwrap_or([0.0; 3]);
                    let yaw = args[1].as_f32().unwrap_or(0.0);
                    let pitch = args[2].as_f32().unwrap_or(0.0);
                    let vel = args[3].as_vec3().unwrap_or([0.0; 3]);
                    let p = self.players.entry(pid).or_insert_with(|| {
                        PlayerEntity::new(pid, format!("P_{}", pid), 0, 0, pos, yaw)
                    });
                    p.target_pos = pos;
                    p.yaw = yaw;
                    p.pitch = pitch;
                    p.vel = vel;
                    p.last_relay = Instant::now();
                }
            }
            "_apply_vitals" => {
                if args.len() >= 5 {
                    let hp = args[0].as_f32().unwrap_or(100.0);
                    let suit = args[1].as_f32().unwrap_or(100.0);
                    let new_state = args[2].as_str().unwrap_or("ok").to_string();
                    let bleed = args[3].as_f32().unwrap_or(0.0);
                    let tarp = args[4].as_bool().unwrap_or(false);
                    let max_hp = args.get(5).and_then(|v| v.as_f32()).unwrap_or(100.0);
                    let charge = args.get(6).and_then(|v| v.as_f32()).unwrap_or(0.0);
                    let invuln = args.get(7).and_then(|v| v.as_bool()).unwrap_or(false);

                    if pid == self.you {
                        if suit < self.prev_suit - 0.6 {
                            self.acid_flash_ttl = 0.25;
                        }
                        if hp < self.prev_hp - 0.5 {
                            self.hurt_flash_ttl = 0.3;
                        }
                        self.prev_suit = suit;
                        self.prev_hp = hp;
                        self.smoke.vitals_received += 1;
                    }

                    let p = self.players.entry(pid).or_insert_with(|| {
                        PlayerEntity::new(pid, format!("P_{}", pid), 0, 0, self.my_pos, 0.0)
                    });
                    p.hp = hp;
                    p.suit = suit;
                    p.state = new_state;
                    p.bleed = bleed;
                    p.tarp = tarp;
                    p.max_hp = max_hp;
                    p.charge = charge;
                    p.invuln = invuln;
                }
            }
            "_apply_tarp" => {
                if let Some(val) = args.first().and_then(|v| v.as_bool()) {
                    if let Some(p) = self.players.get_mut(&pid) {
                        p.tarp = val;
                    }
                }
            }
            "_grant_tarp" => {
                if pid == self.you {
                    self.inventory.has_tarp = true;
                    self.push_feed("TARP ACQUIRED — Press [T] to toggle shelter tarp");
                }
            }
            "_receive_enemy_pull" => {
                if pid == self.you {
                    if let Some(imp) = args.first().and_then(|v| v.as_vec3()) {
                        self.my_pull[0] += imp[0];
                        self.my_pull[1] += imp[1];
                        self.my_pull[2] += imp[2];
                    }
                }
            }
            "_receive_hits" => {
                if pid == self.you {
                    if let Some(hits) = args.get(1).and_then(|v| v.as_array()) {
                        for h in hits {
                            if let Some(cols) = h.as_array() {
                                let killed = cols.first().and_then(|v| v.as_bool()).unwrap_or(false);
                                let crit = cols.get(1).and_then(|v| v.as_bool()).unwrap_or(false);
                                let dmg = cols.get(3).and_then(|v| v.as_int()).unwrap_or(0);
                                self.hit_marker_ttl = 0.25;
                                self.hit_marker_crit = crit || killed;
                                if killed {
                                    self.push_feed(format!("✦ KILL! ({} dmg{})", dmg, if crit { " CRIT" } else { "" }));
                                }
                            }
                        }
                    }
                }
            }
            "_receive_hurt_from" => {
                if pid == self.you {
                    self.hurt_flash_ttl = 0.35;
                }
            }
            "_teleport" => {
                if pid == self.you {
                    if let Some(Variant::Transform3D { basis, origin }) = args.first() {
                        self.my_pos = *origin;
                        self.my_vel = [0.0; 3];
                        self.my_pull = [0.0; 3];
                        // Forward is -basis.z = (-basis[2][0], -basis[2][2])
                        self.my_yaw = basis[2][0].atan2(basis[2][2]);
                    }
                }
            }
            _ => {}
        }
    }

    fn handle_weapon_holder_rpc(&mut self, pid: i64, method: &str, args: &[Variant]) {
        match method {
            "_private_state" => {
                if pid != self.you || args.len() < 13 {
                    return;
                }
                let run = args[0].as_int().unwrap_or(0);
                let rev = args[1].as_int().unwrap_or(0);
                if self.run_id == 0 {
                    self.run_id = run;
                }
                if run != self.run_id || rev <= self.inventory.rev {
                    return;
                }
                self.inventory.rev = rev;
                if let Some(rows) = args[2].as_array() {
                    for i in 0..5 {
                        self.inventory.slots[i] = rows.get(i).and_then(parse_item);
                    }
                }
                self.inventory.stash.clear();
                if let Some(pairs) = args[3].as_dict() {
                    for (k, v) in pairs {
                        if let (Some(ammo), Some(cnt)) = (k.as_str(), v.as_int()) {
                            self.inventory.stash.insert(ammo.to_string(), cnt);
                        }
                    }
                }
                self.inventory.selected_slot =
                    (args[4].as_int().unwrap_or(0).clamp(0, 4)) as usize;
                self.inventory.selected_pouch = args[5].as_str().unwrap_or("").to_string();
                self.inventory.scrap = args[6].as_int().unwrap_or(0);
                self.inventory.frags = args[7].as_int().unwrap_or(0);
                self.inventory.shield_domes = args[8].as_int().unwrap_or(0);
                self.inventory.reload_left = args[9].as_f32().unwrap_or(0.0);
                self.inventory.reload_total = args[10].as_f32().unwrap_or(1.0);
                self.inventory.jam_left = args[11].as_f32().unwrap_or(0.0);
                self.inventory.cooldown = args[12].as_f32().unwrap_or(0.0);
            }
            "_equip_state" => {
                if pid == self.you || args.len() < 4 {
                    return;
                }
                if let Some(p) = self.players.get_mut(&pid) {
                    p.held_item = args[2].as_str().unwrap_or("").to_string();
                    p.held_tier = args[3].as_int().unwrap_or(0) as i32;
                }
            }
            "_shot_fx" => {
                self.smoke.shot_fx_received += 1;
                if args.len() >= 7 {
                    let origin = args[2].as_vec3().unwrap_or([0.0; 3]);
                    let predicted = args[6].as_bool().unwrap_or(false);
                    if pid == self.you && !predicted {
                        self.view_recoil = 1.0;
                        self.muzzle_flash_ttl = 0.1;
                    }
                    if let Some(traces) = args[4].as_array() {
                        for tr in traces {
                            if let Some(pair) = tr.as_array() {
                                if let Some(end) = pair.first().and_then(|v| v.as_vec3()) {
                                    let impact = pair.get(1).and_then(|v| v.as_int()).unwrap_or(0) as i32;
                                    self.tracers.push(TransientTracer {
                                        origin,
                                        end,
                                        impact,
                                        ttl: 0.14,
                                    });
                                }
                            }
                        }
                    }
                }
            }
            "_jam" => {
                if pid == self.you {
                    self.push_feed("WEAPON JAMMED!");
                }
            }
            "_scrap_feedback" => {
                if pid == self.you {
                    if let Some(amt) = args.get(1).and_then(|v| v.as_int()) {
                        self.push_feed(format!("+{} SCRAP", amt));
                    }
                }
            }
            _ => {}
        }
    }

    /// Main fixed/variable simulation tick (call ~30-60 Hz).
    pub fn tick(&mut self, dt: f32) {
        let dt = dt.clamp(0.001, 0.1);
        self.poll_network();

        if self.screen != Screen::InRun {
            return;
        }

        // Decay transient UI & VFX timers
        self.view_recoil = (self.view_recoil - dt * 6.0).max(0.0);
        self.muzzle_flash_ttl = (self.muzzle_flash_ttl - dt).max(0.0);
        self.hit_marker_ttl = (self.hit_marker_ttl - dt).max(0.0);
        self.hurt_flash_ttl = (self.hurt_flash_ttl - dt).max(0.0);
        self.acid_flash_ttl = (self.acid_flash_ttl - dt).max(0.0);
        self.lightning_flash = (self.lightning_flash - dt * 2.6).max(0.0);
        if self.lightning_flash <= 0.05 {
            self.lightning_bolt_col = None;
        }

        if let Some(front) = self.banners.front_mut() {
            front.ttl -= dt;
            if front.ttl <= 0.0 {
                self.banners.pop_front();
            }
        }
        self.tracers.retain_mut(|t| {
            t.ttl -= dt;
            t.ttl > 0.0
        });
        self.blasts.retain_mut(|b| {
            b.ttl -= dt;
            b.ttl > 0.0
        });
        self.pings.retain_mut(|p| {
            p.ttl -= dt;
            p.ttl > 0.0
        });
        self.spores.retain(|_, s| s.elapsed < s.flight);
        for s in self.spores.values_mut() {
            s.elapsed += dt;
        }

        // Countdown inventory timers locally between server pushes
        self.inventory.reload_left = (self.inventory.reload_left - dt).max(0.0);
        self.inventory.jam_left = (self.inventory.jam_left - dt).max(0.0);
        self.inventory.cooldown = (self.inventory.cooldown - dt).max(0.0);

        // Weather countdown & storm intensity easing (client-responsibilities §10)
        if !self.paused {
            if self.draft_hold_timer > 0.0 {
                self.draft_hold_timer = (self.draft_hold_timer - dt).max(0.0);
            }
            let hold_calm = self.phase == 0 && (self.draft.is_some() || self.draft_hold_timer > 0.0);
            if !hold_calm {
                self.phase_time_left = (self.phase_time_left - dt).max(0.0);
            }

            let target_intensity = if self.intensity_override >= 0.0 {
                self.intensity_override
            } else {
                match self.phase {
                    2 => 0.3,
                    3 => {
                        if self.wave >= 5 {
                            1.0
                        } else {
                            0.7
                        }
                    }
                    _ => 0.0,
                }
            };
            let max_step = 0.1 * dt;
            let diff = target_intensity - self.storm_intensity;
            if diff.abs() <= max_step {
                self.storm_intensity = target_intensity;
            } else {
                self.storm_intensity += diff.signum() * max_step;
            }

            // Local 0.1 s puddle growth/dry update
            self.puddle_tick_accum += dt;
            if self.puddle_tick_accum >= 0.1 {
                let pdt = self.puddle_tick_accum;
                self.puddle_tick_accum = 0.0;
                let raining = self.is_raining();
                let rate = if self.is_flood_wave() { 3.0 } else { 1.0 };
                let intensity = self.storm_intensity;
                if let Some(map) = &self.current_map {
                    for p in &map.puddles {
                        let g = self.puddle_growth.entry(p.sync_key.clone()).or_insert(0.0);
                        if raining {
                            *g = (*g + intensity * rate * pdt / p.grow_time.max(1.0)).min(1.0);
                        } else {
                            *g = (*g - pdt / p.dry_time.max(1.0)).max(0.0);
                        }
                    }
                }
            }
        }

        // Interpolate remote players & enemies
        let blend = 1.0 - (-14.0 * dt).exp();
        let now = Instant::now();
        for (&pid, p) in &mut self.players {
            if pid == self.you {
                continue;
            }
            let age = now.duration_since(p.last_relay).as_secs_f32().min(0.1);
            let extrap = [
                p.target_pos[0] + p.vel[0] * age,
                p.target_pos[1] + p.vel[1] * age,
                p.target_pos[2] + p.vel[2] * age,
            ];
            let err_sq = (extrap[0] - p.pos[0]).powi(2)
                + (extrap[1] - p.pos[1]).powi(2)
                + (extrap[2] - p.pos[2]).powi(2);
            if err_sq > 16.0 {
                p.pos = extrap;
            } else {
                for i in 0..3 {
                    p.pos[i] += (extrap[i] - p.pos[i]) * blend;
                }
            }
        }
        for e in self.enemies.values_mut() {
            for i in 0..3 {
                e.pos[i] += (e.target_pos[i] - e.pos[i]) * blend;
            }
            e.hit_flash = (e.hit_flash - dt).max(0.0);
            e.tell_timer = (e.tell_timer - dt).max(0.0);
        }

        // Dead-reckon projectiles between 10 Hz _flight updates
        for eff in self.effects.values_mut() {
            if !eff.deployed {
                let grav = self
                    .catalog
                    .items
                    .get(&eff.id)
                    .map(|i| i.projectile_gravity)
                    .unwrap_or(1.0);
                eff.pos[0] += eff.vel[0] * dt;
                eff.pos[1] += eff.vel[1] * dt;
                eff.pos[2] += eff.vel[2] * dt;
                eff.vel[1] -= 9.8 * grav * dt;
                if eff.pos[1] < 0.05 {
                    eff.pos[1] = 0.05;
                }
            }
            eff.life_left = (eff.life_left - dt).max(0.0);
        }

        if let Some(ad) = &mut self.airdrop {
            ad.descent_left = (ad.descent_left - dt).max(0.0);
        }

        // Local player simulation
        if !self.paused && self.my_state_str() != "out" {
            self.simulate_local_player(dt);
        }

        // Progress active hold interaction (Decon / Revive / Vending)
        self.tick_active_interact(dt);

        // Sync our local player entry
        if let Some(me) = self.players.get_mut(&self.you) {
            me.pos = self.my_pos;
            me.yaw = self.my_yaw;
            me.pitch = self.my_pitch;
            me.vel = self.my_vel;
        }

        // Only send run-scoped RPCs after _confirm_run_ready (spec-full §5)
        if self.run_ready && !self.run_finished_ignore {
            self.update_and_report_exposure(false);

            if self.my_state_str() != "out"
                && self.last_transform_push.elapsed() >= Duration::from_millis(50)
            {
                self.last_transform_push = Instant::now();
                self.send_rpc(RpcMessage::unreliable_ordered(
                    self.my_player_node(),
                    "_push_transform",
                    vec![
                        Variant::Vector3(self.my_pos[0], self.my_pos[1], self.my_pos[2]),
                        Variant::Float(self.my_yaw as f64),
                        Variant::Float(self.my_pitch as f64),
                        Variant::Vector3(self.my_vel[0], self.my_vel[1], self.my_vel[2]),
                    ],
                ));
                self.smoke.transforms_sent += 1;
            }
        }
    }

    fn simulate_local_player(&mut self, dt: f32) {
        let turn_speed = 2.4;
        if self.input.turn_left {
            self.my_yaw += turn_speed * dt;
        }
        if self.input.turn_right {
            self.my_yaw -= turn_speed * dt;
        }
        let pitch_speed = 1.6;
        if self.input.look_up {
            self.my_pitch += pitch_speed * dt;
        }
        if self.input.look_down {
            self.my_pitch -= pitch_speed * dt;
        }
        self.my_pitch = self.my_pitch.clamp(-1.5359, 1.5359);

        let state = self.my_state_str().to_string();
        let tarp_up = self.my_player().map(|p| p.tarp).unwrap_or(false);
        let adrenaline = self.has_mutation("adrenaline_glands");
        let speed_mult = if adrenaline { 1.18 } else { 1.0 };

        let target_eye = match state.as_str() {
            "downed" => 0.55,
            _ if self.input.crouch => 0.95,
            _ => 1.65,
        };
        self.eye_height += (target_eye - self.eye_height) * (dt * 8.0).min(1.0);

        let mut move_f = 0.0f32;
        let mut move_r = 0.0f32;
        if self.input.forward {
            move_f += 1.0;
        }
        if self.input.back {
            move_f -= 1.0;
        }
        if self.input.right {
            move_r += 1.0;
        }
        if self.input.left {
            move_r -= 1.0;
        }

        let fwd = [-self.my_yaw.sin(), -self.my_yaw.cos()];
        let right = [self.my_yaw.cos(), -self.my_yaw.sin()];
        let mut wish_x = fwd[0] * move_f + right[0] * move_r;
        let mut wish_z = fwd[1] * move_f + right[1] * move_r;
        let len = (wish_x * wish_x + wish_z * wish_z).sqrt();
        if len > 1e-4 {
            wish_x /= len;
            wish_z /= len;
        }

        let can_sprint = self.input.sprint
            && move_f > 0.0
            && !self.input.crouch
            && !self.input.ads
            && !tarp_up
            && state == "ok";

        let mut max_speed: f32 = match state.as_str() {
            "downed" => 1.0,
            "turned" => 5.5,
            _ if can_sprint => 8.0,
            _ if self.input.crouch => 2.5,
            _ => 5.0,
        } * speed_mult;

        if (self.input.ads || tarp_up) && state == "ok" {
            max_speed = max_speed.min(3.5 * speed_mult);
        }

        let accel = if self.on_ground { 60.0 } else { 12.0 };
        let target_vx = wish_x * max_speed;
        let target_vz = wish_z * max_speed;
        let step = accel * dt;
        self.my_vel[0] = move_toward(self.my_vel[0], target_vx, step);
        self.my_vel[2] = move_toward(self.my_vel[2], target_vz, step);

        // Apply decaying Undertow pull
        let pull_mag = (self.my_pull[0].powi(2) + self.my_pull[1].powi(2) + self.my_pull[2].powi(2)).sqrt();
        if pull_mag > 1e-4 {
            let decay = (22.0 * dt).min(pull_mag);
            let scale = (pull_mag - decay) / pull_mag;
            self.my_pull[0] *= scale;
            self.my_pull[1] *= scale;
            self.my_pull[2] *= scale;
        }

        // Jump + gravity
        if self.on_ground {
            self.coyote_timer = 0.12;
        } else {
            self.coyote_timer = (self.coyote_timer - dt).max(0.0);
        }
        self.input.jump_buffer = (self.input.jump_buffer - dt).max(0.0);

        if self.input.jump_buffer > 0.0
            && self.coyote_timer > 0.0
            && !self.input.crouch
            && state != "downed"
        {
            self.my_vel[1] = 4.8 * if adrenaline { 1.2 } else { 1.0 };
            self.on_ground = false;
            self.coyote_timer = 0.0;
            self.input.jump_buffer = 0.0;
        }

        if !self.on_ground {
            self.my_vel[1] -= 9.8 * dt;
        }

        self.my_pos[0] += (self.my_vel[0] + self.my_pull[0]) * dt;
        self.my_pos[1] += (self.my_vel[1] + self.my_pull[1]) * dt;
        self.my_pos[2] += (self.my_vel[2] + self.my_pull[2]) * dt;

        if self.my_pos[1] <= 0.0 {
            self.my_pos[1] = 0.0;
            self.my_vel[1] = 0.0;
            self.on_ground = true;
        }

        if let Some(map) = &self.current_map {
            map.resolve_horizontal_collision(&mut self.my_pos, 0.4);
        }

        let horiz_speed = (self.my_vel[0].powi(2) + self.my_vel[2].powi(2)).sqrt();
        if self.on_ground && horiz_speed > 0.3 {
            self.walk_phase += horiz_speed * dt * 1.4;
        }
    }

    pub fn update_and_report_exposure(&mut self, force: bool) {
        let eye = self.my_eye_pos();
        let feet_probe = [self.my_pos[0], self.my_pos[1] + 0.05, self.my_pos[2]];

        let mut sheltered = self
            .current_map
            .as_ref()
            .map(|m| m.is_sheltered(eye))
            .unwrap_or(false);

        // Also check teammate raised tarps (cylinder r=2.0, h=2.6 at their feet)
        if !sheltered {
            for (&pid, p) in &self.players {
                if pid == self.you || !p.tarp {
                    continue;
                }
                let dy = eye[1] - p.pos[1];
                if (0.0..=2.6).contains(&dy) {
                    let dx = eye[0] - p.pos[0];
                    let dz = eye[2] - p.pos[2];
                    if dx * dx + dz * dz <= 4.0 {
                        sheltered = true;
                        break;
                    }
                }
            }
        }

        let mut in_puddle = false;
        if let Some(map) = &self.current_map {
            for pud in &map.puddles {
                let growth = self.puddle_growth.get(&pud.sync_key).copied().unwrap_or(0.0);
                let radius = pud.max_radius * growth;
                if radius > 0.25 {
                    let dy = (feet_probe[1] - pud.pos[1]).abs();
                    let dx = feet_probe[0] - pud.pos[0];
                    let dz = feet_probe[2] - pud.pos[2];
                    if dy <= 0.25 && dx * dx + dz * dz <= radius * radius {
                        in_puddle = true;
                        break;
                    }
                }
            }
        }

        if force || !self.exposure_sent_once || sheltered != self.is_sheltered || in_puddle != self.is_in_puddle {
            self.is_sheltered = sheltered;
            self.is_in_puddle = in_puddle;
            self.exposure_sent_once = true;
            if self.run_ready && !self.run_finished_ignore {
                self.send_rpc(RpcMessage::reliable(
                    self.my_player_node(),
                    "_report_exposure",
                    vec![Variant::Bool(sheltered), Variant::Bool(in_puddle)],
                ));
                self.smoke.exposure_reports += 1;
            }
        }
    }

    // --- Lobby & Gameplay Action Helpers ---

    pub fn toggle_lobby_ready(&mut self) {
        let currently_ready = self
            .roster
            .iter()
            .find(|r| r.peer_id == self.you)
            .map(|r| r.ready)
            .unwrap_or(false);
        self.send_rpc(RpcMessage::reliable(
            "Net",
            "_request_ready",
            vec![Variant::Bool(!currently_ready)],
        ));
    }

    pub fn send_lobby_ready(&self, value: bool) {
        self.send_rpc(RpcMessage::reliable(
            "Net",
            "_request_ready",
            vec![Variant::Bool(value)],
        ));
    }

    pub fn send_force_start(&self) {
        self.send_rpc(RpcMessage::reliable("Net", "_request_force_start", vec![]));
    }

    pub fn send_map_vote(&self, map_id: &str) {
        self.send_rpc(RpcMessage::reliable(
            "Net",
            "_request_map_vote",
            vec![Variant::String(map_id.to_string())],
        ));
    }

    pub fn send_chat(&self, text: &str) {
        let clean: String = text.chars().filter(|c| !c.is_control()).take(100).collect();
        if !clean.is_empty() {
            self.send_rpc(RpcMessage::reliable(
                "Net",
                "_request_chat",
                vec![Variant::String(clean)],
            ));
        }
    }

    pub fn pick_starter(&mut self, index: i64) {
        if !self.run_ready || self.run_id == 0 {
            return;
        }
        self.send_rpc(RpcMessage::reliable(
            "Main/RunLoot",
            "_request_starter",
            vec![Variant::Int(self.run_id), Variant::Int(index.clamp(0, 2))],
        ));
    }

    pub fn select_slot(&mut self, slot: usize) {
        if !self.run_ready || self.run_id == 0 || slot >= 5 {
            return;
        }
        let expected = self.inventory.held_serial();
        self.send_rpc(RpcMessage::reliable(
            self.my_holder_node(),
            "_action",
            vec![
                Variant::Int(self.run_id),
                Variant::String("select".into()),
                Variant::Int(expected),
                Variant::Int(slot as i64),
            ],
        ));
    }

    pub fn reload_weapon(&mut self) {
        if !self.run_ready || self.run_id == 0 {
            return;
        }
        let serial = self.inventory.held_serial();
        if serial == 0 {
            return;
        }
        self.send_rpc(RpcMessage::reliable(
            self.my_holder_node(),
            "_action",
            vec![
                Variant::Int(self.run_id),
                Variant::String("reload".into()),
                Variant::Int(serial),
                Variant::Int(-1),
            ],
        ));
    }

    pub fn drop_held_item(&mut self) {
        if !self.run_ready || self.run_id == 0 {
            return;
        }
        let serial = self.inventory.held_serial();
        if serial == 0 {
            return;
        }
        self.send_rpc(RpcMessage::reliable(
            self.my_holder_node(),
            "_action",
            vec![
                Variant::Int(self.run_id),
                Variant::String("drop".into()),
                Variant::Int(serial),
                Variant::Int(-1),
            ],
        ));
    }

    pub fn fire_or_use(&mut self) {
        if !self.run_ready || self.run_id == 0 || self.paused || self.draft.is_some() {
            return;
        }
        if self.my_state_str() == "turned" {
            self.send_rpc(RpcMessage::reliable(
                self.my_player_node(),
                "_request_melee",
                vec![],
            ));
            self.view_recoil = 0.8;
            return;
        }
        if self.my_state_str() != "ok" {
            return;
        }

        // If a pouch is selected, throw it
        if !self.inventory.selected_pouch.is_empty() {
            let id = self.inventory.selected_pouch.clone();
            self.throw_pouch(&id);
            return;
        }

        let Some(held) = self.inventory.held_item().cloned() else {
            return;
        };
        let fire_interval = self
            .catalog
            .items
            .get(&held.id)
            .map(|i| {
                if self.has_mutation("reflex_tendons") {
                    i.fire_interval * 0.8
                } else {
                    i.fire_interval
                }
            })
            .unwrap_or(0.25);

        if self.last_shot_at.elapsed().as_secs_f32() < fire_interval * 0.9 {
            return;
        }
        if held.count <= 0 {
            self.reload_weapon();
            return;
        }

        let origin = self.my_eye_pos();
        let dir = self.my_look_dir();
        self.last_shot_at = Instant::now();
        self.view_recoil = 1.0;
        self.muzzle_flash_ttl = 0.11;

        self.send_rpc(RpcMessage::reliable(
            self.my_holder_node(),
            "_request_shot",
            vec![
                Variant::Int(self.run_id),
                Variant::Int(held.serial),
                Variant::Vector3(origin[0], origin[1], origin[2]),
                Variant::Vector3(dir[0], dir[1], dir[2]),
                Variant::Bool(self.input.ads),
                Variant::Bool(true),
            ],
        ));
        self.smoke.shots_sent += 1;
    }

    pub fn throw_pouch(&mut self, id: &str) {
        if !self.run_ready || self.run_id == 0 || self.my_state_str() != "ok" {
            return;
        }
        let pouch_idx = match id {
            "frag" if self.inventory.frags > 0 => 0,
            "shield_dome" if self.inventory.shield_domes > 0 => 1,
            _ => return,
        };
        self.send_rpc(RpcMessage::reliable(
            self.my_holder_node(),
            "_action",
            vec![
                Variant::Int(self.run_id),
                Variant::String("select_pouch".into()),
                Variant::Int(0),
                Variant::Int(pouch_idx),
            ],
        ));
        let origin = self.my_eye_pos();
        let dir = self.my_look_dir();
        self.send_rpc(RpcMessage::reliable(
            self.my_holder_node(),
            "_request_throw",
            vec![
                Variant::Int(self.run_id),
                Variant::String(id.to_string()),
                Variant::Vector3(origin[0], origin[1], origin[2]),
                Variant::Vector3(dir[0], dir[1], dir[2]),
            ],
        ));
        self.view_recoil = 0.6;
        self.push_feed(format!("THREW {}", id.to_uppercase()));
    }

    pub fn toggle_tarp(&mut self) {
        if !self.run_ready || !self.inventory.has_tarp {
            return;
        }
        let cur = self.my_player().map(|p| p.tarp).unwrap_or(false);
        self.send_rpc(RpcMessage::reliable(
            self.my_player_node(),
            "_push_tarp",
            vec![Variant::Bool(!cur)],
        ));
    }

    pub fn send_calm_ready(&self) {
        if !self.run_ready {
            return;
        }
        self.send_rpc(RpcMessage::reliable("GameManager", "_request_ready", vec![]));
    }

    pub fn send_context_ping(&mut self) {
        if !self.run_ready {
            return;
        }
        let (kind, pos, enemy_id) = if self.my_state_str() == "downed" {
            ("revive".to_string(), self.my_pos, 0)
        } else if let Some(e) = self.find_aimed_enemy() {
            ("enemy".to_string(), e.pos, e.net_id as i64)
        } else {
            let d = self.my_look_dir();
            let p = [
                self.my_pos[0] + d[0] * 12.0,
                0.2,
                self.my_pos[2] + d[2] * 12.0,
            ];
            ("go".to_string(), p, 0)
        };
        self.send_rpc(RpcMessage::reliable(
            "Main/Pings",
            "_request_ping",
            vec![
                Variant::String(kind),
                Variant::Vector3(pos[0], pos[1], pos[2]),
                Variant::Int(enemy_id),
            ],
        ));
    }

    pub fn vote_mutation(&mut self, index: usize) {
        if let Some(d) = &mut self.draft {
            if index < d.dealt.len() {
                d.my_vote = Some(index);
                self.send_rpc(RpcMessage::reliable(
                    "GameManager/MutationRoll",
                    "_request_vote",
                    vec![Variant::Int(index as i64)],
                ));
            }
        }
    }

    pub fn choose_tape(&mut self, keep_playing: bool) {
        if !self.tape_choice_pending {
            return;
        }
        self.send_rpc(RpcMessage::reliable(
            "GameManager",
            "_request_tape_choice",
            vec![Variant::Bool(keep_playing)],
        ));
    }

    pub fn nearby_interact_prompt(&self) -> Option<String> {
        if let Some(act) = &self.active_interact {
            let pct = ((act.elapsed / act.duration).clamp(0.0, 1.0) * 100.0) as u32;
            return Some(format!("HOLDING: {} ({}%)", act.label, pct));
        }

        // 1. Revive downed teammate (or self in solo)
        for (&pid, p) in &self.players {
            if p.state == "downed" && (pid != self.you || self.players.len() == 1) {
                if dist_xz(self.my_pos, p.pos) <= 2.3 {
                    return Some(format!("[E] Revive {} (3.0s)", p.name));
                }
            }
        }

        // 2. Decon shower
        if let Some(map) = &self.current_map {
            let my_suit = self.my_player().map(|p| p.suit).unwrap_or(100.0);
            if my_suit < 99.0 && self.decon_charges > 0 {
                for d in &map.decon_showers {
                    if dist_xz(self.my_pos, d.pos) <= d.radius + 0.5 {
                        return Some(format!(
                            "[E] Decon Shower: {} ({} left)",
                            d.name, self.decon_charges
                        ));
                    }
                }
            }
        }

        // 3. Ground item pickup
        if let Some(p) = self.nearest_claimable_pickup() {
            let name = p
                .item
                .as_ref()
                .map(|i| self.catalog.item_name(&i.id))
                .unwrap_or(&p.flavor);
            return Some(format!("[E] Pick up {}", name));
        }

        // 4. Airdrop
        if let Some(ad) = &self.airdrop {
            if ad.descent_left <= 0.05 && dist_xz(self.my_pos, ad.pos) <= 2.8 {
                return Some("[E] Open Surplus Airdrop (0.6s)".into());
            }
        }

        // 5. Vending cabinet
        if let Some((key, offer_idx, offer)) = self.nearest_affordable_vending() {
            let name = self.catalog.item_name(&offer.item_id);
            return Some(format!(
                "[E] Buy {} ({} scrap) @ {} [bay {}]",
                name,
                offer.price,
                key,
                offer_idx + 1
            ));
        }

        if self.phase == 0 || self.phase == 4 {
            if self.phase_time_left > 3.0 && self.draft.is_none() {
                return Some(format!(
                    "[G] Skip {} ({}/{} ready)",
                    self.phase_label(),
                    self.ready_count,
                    self.ready_needed.max(1)
                ));
            }
        }

        None
    }

    pub fn trigger_interact(&mut self) {
        if !self.run_ready || self.run_id == 0 || self.draft.is_some() || self.paused {
            return;
        }
        if self.active_interact.is_some() {
            return;
        }

        // 1. Revive
        for (&pid, p) in &self.players {
            if p.state == "downed" && (pid != self.you || self.players.len() == 1) {
                if dist_xz(self.my_pos, p.pos) <= 2.3 {
                    let path = format!("/root/Main/Players/P_{}/ReviveSpot", pid);
                    self.active_interact = Some(ActiveInteract {
                        label: format!("Reviving {}", p.name),
                        kind: InteractKind::Revive { path, pos: p.pos },
                        elapsed: 0.0,
                        duration: 3.0,
                    });
                    return;
                }
            }
        }

        // 2. Decon shower
        if let Some(map) = &self.current_map {
            let my_suit = self.my_player().map(|p| p.suit).unwrap_or(100.0);
            if my_suit < 99.0 && self.decon_charges > 0 {
                for d in &map.decon_showers {
                    if dist_xz(self.my_pos, d.pos) <= d.radius + 0.5 {
                        self.active_interact = Some(ActiveInteract {
                            label: format!("Decon {}", d.name),
                            kind: InteractKind::Decon {
                                path: d.interact_path.clone(),
                                pos: d.pos,
                            },
                            elapsed: 0.0,
                            duration: d.hold_time.max(1.0),
                        });
                        return;
                    }
                }
            }
        }

        // 3. World pickup
        if let Some(p) = self.nearest_claimable_pickup() {
            let expected = self.inventory.held_serial();
            let slot = self.inventory.selected_slot as i64;
            self.send_rpc(RpcMessage::reliable(
                "Main/RunLoot",
                "_claim",
                vec![
                    Variant::Int(self.run_id),
                    Variant::Int(p.id),
                    Variant::Int(expected),
                    Variant::Int(slot),
                ],
            ));
            return;
        }

        // 4. Airdrop
        if let Some(ad) = self.airdrop.clone() {
            if ad.descent_left <= 0.05 && dist_xz(self.my_pos, ad.pos) <= 2.8 {
                self.send_rpc(RpcMessage::reliable(
                    "GameManager/CrateManager",
                    "_hold_request",
                    vec![
                        Variant::Int(self.run_id),
                        Variant::String("Airdrop".into()),
                        Variant::String("airdrop".into()),
                        Variant::String("begin".into()),
                        Variant::Int(0),
                    ],
                ));
                self.active_interact = Some(ActiveInteract {
                    label: "Opening Airdrop".into(),
                    kind: InteractKind::Vending {
                        key: "Airdrop".into(),
                        mode: "airdrop".into(),
                        serial: 0,
                        pos: ad.pos,
                    },
                    elapsed: 0.0,
                    duration: 0.62,
                });
                return;
            }
        }

        // 5. Vending bay
        if let Some((key, offer_idx, offer)) = self.nearest_affordable_vending() {
            let mode = format!("offer_{}", offer_idx + 1);
            let vpos = self
                .current_map
                .as_ref()
                .and_then(|m| m.vending_stations.iter().find(|v| v.key == key))
                .map(|v| v.pos)
                .unwrap_or(self.my_pos);
            self.send_rpc(RpcMessage::reliable(
                "GameManager/CrateManager",
                "_hold_request",
                vec![
                    Variant::Int(self.run_id),
                    Variant::String(key.clone()),
                    Variant::String(mode.clone()),
                    Variant::String("begin".into()),
                    Variant::Int(offer.serial),
                ],
            ));
            self.active_interact = Some(ActiveInteract {
                label: format!("Buying {}", self.catalog.item_name(&offer.item_id)),
                kind: InteractKind::Vending {
                    key,
                    mode,
                    serial: offer.serial,
                    pos: vpos,
                },
                elapsed: 0.0,
                duration: 0.62,
            });
        }
    }

    fn tick_active_interact(&mut self, dt: f32) {
        let Some(mut act) = self.active_interact.take() else {
            return;
        };
        let target_pos = match &act.kind {
            InteractKind::Decon { pos, .. }
            | InteractKind::Revive { pos, .. }
            | InteractKind::Vending { pos, .. } => *pos,
        };
        if dist_xz(self.my_pos, target_pos) > 3.2 {
            // Walked away — cancel vending hold if needed
            if let InteractKind::Vending {
                key, mode, serial, ..
            } = act.kind
            {
                self.send_rpc(RpcMessage::reliable(
                    "GameManager/CrateManager",
                    "_hold_request",
                    vec![
                        Variant::Int(self.run_id),
                        Variant::String(key),
                        Variant::String(mode),
                        Variant::String("cancel".into()),
                        Variant::Int(serial),
                    ],
                ));
            }
            return;
        }

        act.elapsed += dt;
        if act.elapsed >= act.duration {
            match act.kind {
                InteractKind::Decon { path, .. } | InteractKind::Revive { path, .. } => {
                    self.send_rpc(RpcMessage::reliable(
                        "GameManager",
                        "_request_interact",
                        vec![Variant::NodePath(path)],
                    ));
                }
                InteractKind::Vending {
                    key, mode, serial, ..
                } => {
                    self.send_rpc(RpcMessage::reliable(
                        "GameManager/CrateManager",
                        "_hold_request",
                        vec![
                            Variant::Int(self.run_id),
                            Variant::String(key),
                            Variant::String(mode),
                            Variant::String("finish".into()),
                            Variant::Int(serial),
                        ],
                    ));
                }
            }
        } else {
            self.active_interact = Some(act);
        }
    }

    fn nearest_claimable_pickup(&self) -> Option<PickupEntity> {
        let mut best: Option<(f32, &PickupEntity)> = None;
        for p in self.pickups.values() {
            if !p.flavor.is_empty() {
                continue; // supplies auto-collect
            }
            if p.claim_peer != 0 && p.claim_peer != self.you {
                continue;
            }
            let d = dist_xz(self.my_pos, p.pos);
            if d <= 2.55 && best.map(|(bd, _)| d < bd).unwrap_or(true) {
                best = Some((d, p));
            }
        }
        best.map(|(_, p)| p.clone())
    }

    fn nearest_affordable_vending(&self) -> Option<(String, usize, VendingOffer)> {
        let map = self.current_map.as_ref()?;
        for v in &map.vending_stations {
            if dist_xz(self.my_pos, v.pos) <= 2.8 {
                if let Some(offers) = self.cabinets.get(&v.key) {
                    for (idx, off) in offers.iter().enumerate() {
                        if off.price <= self.inventory.scrap {
                            return Some((v.key.clone(), idx, off.clone()));
                        }
                    }
                }
            }
        }
        None
    }

    fn find_aimed_enemy(&self) -> Option<&EnemyEntity> {
        let eye = self.my_eye_pos();
        let dir = self.my_look_dir();
        let mut best: Option<(f32, &EnemyEntity)> = None;
        for e in self.enemies.values() {
            let dx = e.pos[0] - eye[0];
            let dy = (e.pos[1] + 0.9) - eye[1];
            let dz = e.pos[2] - eye[2];
            let dist = (dx * dx + dy * dy + dz * dz).sqrt();
            if dist < 0.5 || dist > 80.0 {
                continue;
            }
            let dot = (dx * dir[0] + dy * dir[1] + dz * dir[2]) / dist;
            if dot > 0.94 && best.map(|(bd, _)| dist < bd).unwrap_or(true) {
                best = Some((dist, e));
            }
        }
        best.map(|(_, e)| e)
    }
}

fn move_toward(cur: f32, target: f32, max_delta: f32) -> f32 {
    let diff = target - cur;
    if diff.abs() <= max_delta {
        target
    } else {
        cur + diff.signum() * max_delta
    }
}

pub fn dist_xz(a: [f32; 3], b: [f32; 3]) -> f32 {
    ((a[0] - b[0]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
}

fn extract_string_list(v: &Variant) -> Vec<String> {
    match v {
        Variant::Array(arr) => arr
            .iter()
            .filter_map(|x| x.as_str().map(|s| s.to_string()))
            .collect(),
        Variant::PackedStringArray(arr) => arr.clone(),
        _ => Vec::new(),
    }
}

fn parse_item(v: &Variant) -> Option<InventoryItem> {
    let arr = v.as_array()?;
    if arr.len() < 4 {
        return None;
    }
    Some(InventoryItem {
        serial: arr[0].as_int()?,
        id: arr[1].as_str()?.to_string(),
        tier: arr[2].as_int().unwrap_or(0) as i32,
        count: arr[3].as_int().unwrap_or(0) as i32,
    })
}

fn parse_pickup(id: i64, v: &Variant) -> Option<PickupEntity> {
    let arr = v.as_array()?;
    if arr.len() < 4 {
        return None;
    }
    Some(PickupEntity {
        id,
        pos: arr[0].as_vec3().unwrap_or([0.0; 3]),
        item: parse_item(&arr[1]),
        flavor: arr[2].as_str().unwrap_or("").to_string(),
        claim_peer: arr[3].as_int().unwrap_or(0),
    })
}

fn parse_effect(seq: i64, v: &Variant) -> Option<ProjectileEffect> {
    let arr = v.as_array()?;
    if arr.len() < 7 {
        return None;
    }
    Some(ProjectileEffect {
        seq,
        id: arr[0].as_str().unwrap_or("").to_string(),
        pos: arr[1].as_vec3().unwrap_or([0.0; 3]),
        vel: arr[2].as_vec3().unwrap_or([0.0; 3]),
        tier: arr[3].as_int().unwrap_or(0) as i32,
        deployed: arr[4].as_bool().unwrap_or(false),
        life_left: arr[5].as_f32().unwrap_or(0.0),
        yaw: arr[6].as_f32().unwrap_or(0.0),
    })
}

fn parse_offers(v: &Variant) -> Vec<VendingOffer> {
    let mut out = Vec::new();
    if let Some(arr) = v.as_array() {
        for item in arr {
            if let Some(cols) = item.as_array() {
                if cols.len() >= 4 {
                    out.push(VendingOffer {
                        item_id: cols[0].as_str().unwrap_or("").to_string(),
                        tier: cols[1].as_int().unwrap_or(0) as i32,
                        price: cols[2].as_int().unwrap_or(0),
                        serial: cols[3].as_int().unwrap_or(0),
                    });
                }
            }
        }
    }
    out
}

fn parse_results(won: bool, v: Option<&Variant>) -> ResultsSummary {
    let mut summary = ResultsSummary {
        won,
        map_id: "pinecrest".into(),
        waves: 0,
        wave_reached: 1,
        endless: false,
        endless_score: 0,
        seconds: 0,
        squad_mutations: Vec::new(),
        players: Vec::new(),
    };
    let Some(res) = v else {
        return summary;
    };
    if let Some(m) = res.dict_get("map_id").and_then(|x| x.as_str()) {
        summary.map_id = m.to_string();
    }
    if let Some(w) = res.dict_get("waves").and_then(|x| x.as_int()) {
        summary.waves = w;
    }
    if let Some(wr) = res.dict_get("wave_reached").and_then(|x| x.as_int()) {
        summary.wave_reached = wr;
    }
    if let Some(e) = res.dict_get("endless").and_then(|x| x.as_bool()) {
        summary.endless = e;
    }
    if let Some(es) = res.dict_get("endless_score").and_then(|x| x.as_int()) {
        summary.endless_score = es;
    }
    if let Some(s) = res.dict_get("seconds").and_then(|x| x.as_int()) {
        summary.seconds = s;
    }
    if let Some(sm) = res.dict_get("squad_mutations") {
        summary.squad_mutations = extract_string_list(sm);
    }
    if let Some(pairs) = res.dict_get("players").and_then(|x| x.as_dict()) {
        for (k, val) in pairs {
            summary.players.push(PlayerResultRow {
                peer_id: k.as_int().unwrap_or(0),
                name: val
                    .dict_get("name")
                    .and_then(|x| x.as_str())
                    .unwrap_or("PLAYER")
                    .to_string(),
                kills: val.dict_get("kills").and_then(|x| x.as_int()).unwrap_or(0),
                revives: val.dict_get("revives").and_then(|x| x.as_int()).unwrap_or(0),
                turned: val.dict_get("turned").and_then(|x| x.as_int()).unwrap_or(0),
                cursed: val
                    .dict_get("cursed")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .to_string(),
                weapon: val
                    .dict_get("weapon")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .to_string(),
            });
        }
    }
    summary
}

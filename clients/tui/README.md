# Fallout Forecast — Terminal ASCII Client (`fallout-tui`)

A **Full-tier Open Protocol v1** (game protocol `19`) terminal client written in Rust that renders **Fallout Forecast** in real-time 3D ASCII and top-down tactical ASCII directly in your terminal.

Built with `ratatui`, `crossterm`, `tokio`, and `tokio-tungstenite` (`rustls`), it joins the exact same lobbies and co-op runs as native Godot 4.7.2 players and Thin-tier clients over **WebSocket (`ws://` / `wss://`)** or **raw length-prefixed TCP**, speaking both **JSON (`enc: "json"`)** and **Godot Binary Variant (`enc: "bin"`)** encoding.

## Features

- **Full-tier Open Protocol v1 + Game Protocol 19:**
  - Dual transport: **WebSocket** (`ws://`, `wss://` with TLS via `rustls` + `webpki-roots`) and **raw TCP** (4-byte little-endian length-prefixed frames).
  - Dual encoding: exact **JSON Variant** mapping (including tagged dicts with integer/NodePath keys, `Vector3`, `Color`, `Transform3D`, `NodePath`) AND **Godot `encode_var`/`decode_var` binary Variant** format (`FLAG_64` f32/f64 floats, typed `Array`/`Dictionary` container headers, `Packed*Array`, `NodePath`).
  - Complete session lifecycle: `hello` → `welcome` → `Net._hello` → lobby roster, map voting, ready, force start, lobby chat, 1 Hz `Net._rtt_ping`/`_rtt_pong`, `Net._start_run` → map load → `Net._report_in_run(true)` → catch-up burst → `Net._confirm_run_ready` → starter kit → live run → mutation draft → endless tape choice → `GameManager._finish` results → return to lobby & graceful `leave`.
- **Client-side Simulation & Exposure:**
  - Real map data embedded from `docs/open-protocol/level-markers.json`, `docs/open-protocol/game-data.json`, and `assets/maps/{pinecrest,harbor,maple_hollow,environments}.json`.
  - Local capsule movement (walk/sprint/crouch/jump/gravity/enemy pull) with map obstacle collision, 20 Hz `Player._push_transform`, local puddle growth/drying, and real-time roof/canopy/tarp/puddle exposure reporting via `Player._report_exposure`.
  - Full combat & squad interactions: starter kit picker, hitscan & throwable firing, reload, 5-slot hotbar, frag/shield dome pouches, tarp toggle, hold-to-interact (Decon Showers, teammate Revive, Vending Bays, Surplus Airdrops using exact server NodePaths), context pings, Calm/Clearing ready-up, mutation draft voting, and endless tape decisions.
- **3D ASCII Raycaster & Tactical Views (`M` to cycle):**
  - **3D FPS + Corner Radar** (default): analytic 3D raycaster for real Pinecrest / Harbor Point / Maple Hollow buildings, awnings, canopies, tree trunks, puddles, and fences; depth-buffered ASCII sprites for all 9 infected types + Cloudburst miniboss + Boss Cumulus + hazmat teammates + pickups + deployables; dynamic acid rain & lightning flashes; crosshair + hit markers; and an animated ASCII first-person weapon viewmodel with recoil & muzzle flash.
  - **Full 3D FPS**: full-viewport ASCII raycaster.
  - **Full Top-Down Tactical Map**: live overhead ASCII radar showing buildings, dry shelters, trees, growing puddles, vending cabinets, decon showers, pickups, enemies, teammates, and player FOV cone.

## Build & Run

Requires Rust (`cargo` / `rustc`, tested with `1.99.1`):

```bash
cd clients/tui
cargo build --release
```

Release binary: `clients/tui/target/release/fallout-tui` (`.exe` on Windows).

### Quick Start

```bash
# Launch interactive Title/Connect screen (defaults to wss://fallout-open.drew.place/, bin encoding)
./target/release/fallout-tui

# Connect directly over WebSocket + JSON
./target/release/fallout-tui --url wss://fallout-open.drew.place/ --enc json --name "Runner" --color 1 --skin 1 --connect

# Connect directly over raw TCP + Binary
./target/release/fallout-tui --tcp fallout.drew.place:7781 --enc bin --name "Runner" --connect

# Run automated headless end-to-end smoke test & dump 120x38 ASCII frames
./target/release/fallout-tui --url ws://127.0.0.1:47780/ --enc json --smoke-test --dump-frames ./frames
```

## CLI Options

| Flag | Default | Description |
| --- | --- | --- |
| `--url <ws/wss>` | `wss://fallout-open.drew.place/` | WebSocket endpoint URL |
| `--tcp <host:port>` | *(none)* | Raw TCP endpoint (overrides `--url`) |
| `--enc <json\|bin>` | `bin` | Full-tier RPC wire encoding |
| `--name <callsign>` | `ASCII-Runner` | Player callsign |
| `--code <join-code>` | `""` | Optional server join code |
| `--color <0..9>` | `0` | Preferred hazmat suit color index |
| `--skin <0..4>` | `0` | Suit skin index (`0` Standard .. `4` Ion Rig) |
| `--connect` | `false` | Skip the Title screen and connect immediately |
| `--smoke-test` | `false` | Run automated headless end-to-end verification |
| `--dump-frames <dir>` | *(none)* | Write rendered ASCII `.txt` frames during `--smoke-test` |
| `--smoke-seconds <f32>` | `8.0` | Observation window in run during `--smoke-test` |

## Controls

### Title / Connect
- `↑` / `↓` / `Tab`: Select field
- `←` / `→`: Toggle Transport (`WS`/`TCP`), Encoding (`JSON`/`BIN`), Suit Color, Suit Skin
- Type / `Backspace`: Edit endpoint, callsign, or join code
- `Enter`: Connect · `Esc` / `Ctrl+C`: Quit

### Lobby
- `R`: Toggle Ready · `F`: Force Start
- `1`–`4`: Vote Map (`1`–`3` server maps, `4` Random)
- `C`: Open chat input (`Enter` send, `Esc` cancel)
- `H` / `?`: Help · `Q` / `Esc`: Leave & quit

### In-Run
- `W` `A` `S` `D`: Move / strafe (`Shift+W` or `V` toggles Sprint)
- `Arrow Keys` or `I` `J` `K` `L`: Turn & look pitch
- `C`: Toggle Crouch · `X`: Jump · `Z`: Toggle ADS zoom
- `Space` / `Enter`: Fire weapon / use held item / melee (when Turned)
- `R`: Reload · `1`–`5`: Select hotbar slot · `B`: Drop held item
- `Q`: Throw Frag Grenade · `F`: Throw Shield Dome · `T`: Toggle Shelter Tarp
- `E`: Context Interact (pick up weapon, hold Decon Shower, revive downed teammate, buy Vending bay, open Airdrop)
- `P`: Send squad context ping · `G`: Ready up to skip Calm/Clearing
- `M`: Cycle view mode (`3D FPS + Radar` → `Full 3D FPS` → `Tactical Map`)
- `1`–`3` during Starter Kit / Mutation Draft: Pick starter or vote mutation
- `C` / `E` during Endless Tape Choice (squad leader): Continue Endless / End Tape
- `H` / `?`: Controls overlay · `Esc`: Leave cleanly

## Architecture

```text
clients/tui/src/
├── main.rs                 # CLI parser, crossterm/ratatui loop, panic-safe terminal guard
├── smoke.rs                # Headless end-to-end smoke test & TestBackend ASCII frame dumper
├── protocol/
│   ├── variant.rs          # Godot 4.7.2 Variant type + JSON & encode_var binary codecs
│   ├── frame.rs            # Open Protocol envelopes, 0x03 binary RPC framing, TCP u32 LE framing
│   └── transport.rs        # Async Tokio WebSocket (ws/wss) & raw TCP transport task
├── game/
│   ├── data.rs             # Embedded game-data, level-markers, assets/maps geometry & collision
│   └── state.rs            # Full-tier RPC dispatcher, local physics, exposure, weather & combat
└── render/
    ├── raycaster.rs        # Analytic 3D ASCII raycaster, billboards, rain/lightning, viewmodel
    ├── map_view.rs         # Full top-down tactical ASCII map & corner radar widget
    └── ui.rs               # All ratatui screens (Title, Lobby, Loading, HUD, Overlays, Results)
```

## Tests

```bash
cd clients/tui
cargo test
```

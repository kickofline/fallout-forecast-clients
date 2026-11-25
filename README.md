# fallout-forecast-clients

Alternative clients, shared GLES2 asset pack, and implementer documentation for the **Fallout Forecast Open Protocol** (Thin + Full tiers).

## Clients

- **Car (`clients/car/`):** Godot 3.6.3 GLES2 Android APK targeting a 2017 Honda Android 5.1.1 head unit (`armeabi-v7a`, PowerVR SGX 544MP), connecting over the Open Protocol **Thin** tier. See [clients/car/README.md](clients/car/README.md).
- **Terminal ASCII (`clients/tui/`):** Rust terminal client rendering the game in 3D & top-down ASCII over the Open Protocol **Full** tier (WebSocket `ws://`/`wss://` + raw TCP, JSON + binary Variant codecs). See [clients/tui/README.md](clients/tui/README.md).
- **3DS / embedded / custom ports:** Build directly against the shared `assets/` pack and [Open Protocol implementer docs](docs/open-protocol/AGENTS.md).

## Live Open Protocol Endpoints

- **WebSocket (Thin + Full):** `wss://fallout-thin.drew.place/` (and `wss://fallout-open.drew.place/`)
- **Raw TCP (Thin + Full):** `fallout.drew.place:7781`

## Repository Layout

- [`docs/open-protocol/AGENTS.md`](docs/open-protocol/AGENTS.md) — AI-agent and human implementer guide, normative specs (`spec-common`, `spec-thin`, `spec-full`), RPC schema/catalog, game reference, conformance checks, and captured wire transcripts.
- [`assets/README.md`](assets/README.md) — Shared exported maps, articulated character rigs, weapons, environments, and audio cues (`assets/manifest.json`).
- [`exporter/README.md`](exporter/README.md) — Godot 4.7.2 scripts that regenerate `assets/` from the main game repo.
- `tools/` — Shared tooling (`sync_assets.py`, `mock_bridge.py`, `emu_test.sh`).

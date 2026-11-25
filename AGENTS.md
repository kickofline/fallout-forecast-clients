# AGENTS.md

This repository holds alternative clients (`clients/car/`, `clients/tui/`, etc.), the shared GLES2 asset pack (`assets/`, `exporter/`), and the mirrored **Fallout Forecast Open Protocol** documentation (`docs/open-protocol/`).

## Updating an Existing Client

1. Read [`docs/open-protocol/CHANGELOG.md`](docs/open-protocol/CHANGELOG.md) first (synced from `kickofline/fallout-forecast`).
2. Find the latest entry your client already implements (by date, Open Protocol `v`, or `game_protocol`) and apply every newer entry's **Client action** steps for your tier (Thin or Full).
3. If `open-protocol-schema.json`, `game-data.json`, or `level-markers.json` changed, update your client's embedded copies or bindings accordingly.

## Building a New Client

Start at [`docs/open-protocol/AGENTS.md`](docs/open-protocol/AGENTS.md) and [`docs/open-protocol/llms.txt`](docs/open-protocol/llms.txt).

## Repo Rules

- Keep this public repository infrastructure-agnostic (no private hostnames, internal IPs, dashboards, UUIDs, or secrets).
- Never commit build artifacts (`build/`, `target/`, `*.apk`, `.import/`, `.godot/`).

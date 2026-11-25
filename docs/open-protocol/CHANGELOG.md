# Open Protocol Changelog

Chronological log of every change affecting **Fallout Forecast**'s native multiplayer protocol (`Net.PROTOCOL`) or **Open Protocol** (Common, Thin, and Full tiers). Newest entries are first.

> **For agents updating an existing client:** Find the latest entry your client already implements (by date, `v`, or `game_protocol`), then read every newer entry above it. Each entry lists exact wire/RPC/behavior deltas and concrete **Client action** steps.
>
> **For agents editing the server or game:** Any change to `Net.PROTOCOL`, Open Protocol `v`, `@rpc` signatures/paths/payloads, Thin/Full messages, binary layouts, Variant mappings, error strings, limits/timeouts, or game-data IDs/markers **MUST** add a new entry at the top of this file in the same commit/PR (see root `CLAUDE.md` / `AGENTS.md`).

## Entry template

```markdown
## YYYY-MM-DD — Short summary (`<commit or PR>`)

- **Versions:** Open Protocol `v1` · `Net.PROTOCOL` `19`
- **Tiers affected:** Common | Thin | Full | Server config
- **Breaking:** No | Yes (explain)
- **Changes:**
  - Exact message, RPC, field, limit, error string, or catalog delta.
- **Client action:**
  - **Thin:** None | concrete update steps.
  - **Full:** None | concrete update steps (note if `open-protocol-schema.json` / `game-data.json` / `level-markers.json` changed).
- **Docs updated:** `spec-common.md`, `spec-full.md`, etc.
```

---

## 2026-11-25 — Tolerate slow and blocked clients ([PR #2](https://github.com/kickofline/fallout-forecast/pull/2))

- **Versions:** Open Protocol `v1` · `Net.PROTOCOL` `19`
- **Tiers affected:** Common, Thin, Full
- **Breaking:** No
- **Changes:**
  - Open Protocol WebSockets send a Ping every 20 s and allow 20 s for the matching Pong. Both intervals were 2 s.
  - Thin automatically sends the first `snap` in `run`, then sends at up to 2 Hz until optional JSON `{"t":"loaded"}`, first valid `in`, or 15 s from `load`. `loaded` can arrive during `loading` or `run` for either encoding.
  - Thin skips snapshot sends while its outbound transport queue is busy and samples fresh state when it drains. Pending events still batch within the 256-event cap. Draft and results messages stay ordered. The 524,288-byte reliable buffer cap stays in force.
  - Server logs now include Open Protocol disconnect reasons and available WebSocket close codes. Server-initiated closes can send an `error` or WebSocket close reason. This includes framing and buffer errors, the 5 s hello and 10 s Full join deadlines, and game-level rejection. A missed WebSocket Pong can still surface as an abnormal close.
- **Client action:**
  - **Thin:** Existing clients can keep waiting for the first snapshot. Optionally send `loaded` when ready, or send valid input after `status run` to enable the negotiated rate. Request a sustainable rate and accept gaps in snapshots. Display a diagnostic if delivered and handle EOF or WebSocket close.
  - **Full:** Keep answering WebSocket control Pings and game RTT probes. Treat a server-initiated disconnect as terminal, displaying any available error or close reason. RPC envelopes and catalog are unchanged.
- **Docs updated:** `spec-common.md`, `spec-thin.md`, `spec-full.md`, `KNOWN_ISSUES.md`, `conformance.md`, `AGENTS.md`

## 2026-11-25 — CIDR support for `FALLOUT_TRUSTED_PROXIES` (`d7c89ff`)

- **Versions:** Open Protocol `v1` · `Net.PROTOCOL` `19`
- **Tiers affected:** Server config (Common listener)
- **Breaking:** No
- **Changes:**
  - `FALLOUT_TRUSTED_PROXIES` / `--trusted-proxies=` now accepts IPv4 and IPv6 CIDR subnets (e.g. `10.0.2.0/24`, `fd7a:115c:a1e0::/48`) in addition to exact IP addresses, with IPv4-mapped IPv6 (`::ffff:x.x.x.x`) normalization. Invalid entries are logged and ignored.
- **Client action:**
  - **Thin:** None.
  - **Full:** None.
- **Docs updated:** `server/README.md`

## 2026-11-25 — Listener hardening, callsign sanitization, and strict JSON output (`27dbfbf`, PR #1)

- **Versions:** Open Protocol `v1` · `Net.PROTOCOL` `19`
- **Tiers affected:** Common, Thin, Full, Native
- **Breaking:** No (stricter validation and new rate-limit error string)
- **Changes:**
  - **Callsigns & chat (`game/net.gd`, `game/thin_server.gd`):** Native, Thin, and Full joins plus `Net._request_name` and chat now share `Net._clean_text` / `Net.clean_name` — stripping C0 (`< 0x20`), C1 (`0x7F–0x9F`), and bidi override/isolate code points (`U+202A–202E`, `U+2066–2069`), replacing `[`/`]` with `(`/`)`, and trimming Full `Net._hello` names to 32 chars (18 chars for Thin and `_request_name`; empty falls back to `"PLAYER"` / `"THIN PLAYER"`).
  - **RFC 8259 JSON backstop (`game/open_protocol_wire.gd`):** All server JSON frames pass through `OpenProtocolWire.strict_json`, escaping raw `0x00–0x1F` and rewriting Godot's non-standard `\v` to `\u000b`.
  - **Join-code rate limiting (`game/thin_server.gd`):** Constant-time join-code comparison; 5 wrong codes per address in 60 s triggers an exponential cooldown (`60 s` doubling up to `1 h`), plus a `30/min` server-wide cap. New terminal error message: `Too many join attempts, try again later`. Blocked addresses may also be dropped silently at TCP accept.
  - **Split connection pools (`game/thin_server.gd`):** Pre-`hello` sockets now have their own pool (`16` total, `3` per address) separate from the `12` established Thin + Full connections; `FALLOUT_TRUSTED_PROXIES` / `--trusted-proxies=` exempts reverse-proxy addresses from per-address limits.
  - **Full JSON input validation (`game/open_protocol/full_peer.gd`, `variant_json.gd`):** JSON `rpc`/`raw` frames require integer `ch` in `0..255` and boolean `rel` (invalid types fall back to defaults instead of casting); `VariantJson.from_json` caps nesting depth at `32` (deeper values decode as `null`).
- **Client action:**
  - **Thin:** Handle the new terminal `error` string `"Too many join attempts, try again later"` (and silent TCP close on rate-limit cooldown) cleanly in UI/reconnect logic.
  - **Full:** Same rate-limit handling; ensure outgoing JSON `rpc`/`raw` frames send integer `ch` (`0..255`) and boolean `rel` (not strings/numbers), and keep Variant payloads within depth `32`.
- **Docs updated:** `spec-common.md`, `spec-full.md`, `KNOWN_ISSUES.md`, `server/README.md`, `server/docker-compose.yml`

## 2026-11-25 — Open Protocol v1 launch: Thin + Full tiers (`ba4ea9a`, `947efeb`)

- **Versions:** Open Protocol `v1` · `Net.PROTOCOL` `19`
- **Tiers affected:** Common, Thin, Full
- **Breaking:** N/A (initial release; native Godot clients unchanged at `Net.PROTOCOL = 19`)
- **Changes:**
  - Added dedicated-server Open Protocol listeners on WebSocket `7780` and 4-byte LE length-prefixed raw TCP `7781` with JSON and binary encodings.
  - **Thin tier:** Server-simulated player slots (`hello`, `welcome`, `status`, `lobby`, `load`, `snap`, `ev`, `in`, `choice`, `draft`, `draft_done`, `tape`, `results`, `map_req`/`map`, `ping`/`pong`, `leave`, `error`).
  - **Full tier:** `MultiplayerPeerExtension` adapter (`FullPeer`) translating all 102 `SceneMultiplayer` RPCs and raw packets to JSON/binary Variant frames, with a 12-connection cap shared with Thin and a `10 s` post-`welcome` deadline to complete `Net._hello`.
  - Added full implementer docs, generated `open-protocol-schema.json`, `game-data.json`, `level-markers.json`, captured JSON/binary transcripts, and Python conformance checkers (`tools/thin_client/fake_client.py`, `tools/open_protocol/full_client.py`).
- **Client action:**
  - **Thin / Full:** Implement from `docs/open-protocol/AGENTS.md` baseline.
- **Docs updated:** Full `docs/open-protocol/` suite.

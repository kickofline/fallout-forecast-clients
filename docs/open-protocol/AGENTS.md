# Implement a Fallout Forecast client

Fallout Forecast is a 1–4 player co-op FPS. The Open Protocol lets clients
written in any language share a dedicated-server lobby and run with the native
game. Both tiers use WebSocket or length-prefixed TCP and Open Protocol v1.

## Choosing a tier

| Tier | Choose it when | What you implement |
| --- | --- | --- |
| Thin | You want server-simulated movement and combat, including for limited hardware or a terminal prototype. | Controls, lobby, rendering from snapshots and events. Version against Open Protocol `v`. |
| Full | You need local movement, collision and presentation like the native game, and can keep an RPC codec and local map data in sync. | Local player simulation and exposure, the game RPC stream, and world/HUD rendering. Version against both `v` and `game_protocol`. |

Start with JSON and one transport; choose binary when bandwidth or an existing
codec warrants it. TCP is convenient for native test clients; browser clients
use WebSocket. Both tiers can coexist in one squad.

## Reading order

1. [Common specification](spec-common.md) for ports, framing, hello, versions,
   ping and leave.
2. Read your tier in order.
   - **Thin:** [Thin specification](spec-thin.md) §§1–6, then §§8–12; read §7
     for the binary snapshot format.
   - **Full:** [Full specification](spec-full.md) §§1–7, 11–14 (also §§8–10
     for binary), then [client responsibilities](client-responsibilities.md).
     Use the [RPC catalog](rpc-catalog.md) to look up signatures, and the
     [machine-readable schema](open-protocol-schema.json) to generate bindings.
3. [Game reference](game-reference.md), with [game data](game-data.json) and
   [level markers](level-markers.json) for exact ids, rules and coordinates.
4. Read one real session in your chosen encoding.
   - Thin [JSON transcript](transcripts/thin-json.md) or [binary transcript](transcripts/thin-bin.md)
   - Full [JSON transcript](transcripts/full-json.md) or [binary transcript](transcripts/full-bin.md)

   Each annotated transcript has a corresponding raw `.jsonl` capture.
5. [Known issues](KNOWN_ISSUES.md) and [conformance instructions](conformance.md)
   before testing.

## Implementation checkpoints

| Step | Thin | Full | Conformance checkpoint |
| --- | --- | --- | --- |
| 1 | Send JSON `hello` for `thin`, verify `welcome`, round-trip `ping`. | Same for `full`, checking `game_protocol` against your schema. | T1 / F1. |
| 2 | Track the latest `lobby`, then send vote and ready. | Decode Variant values, send `Net._hello` with a JSON string argument, find yourself in the roster and answer `Net._rtt_ping`. Vote and ready using `Net` RPCs. | T2 / F2–F3. |
| 3 | On `load` select the map. Wait for `status run` and the starter kit in `snap`. | On `Net._start_run`, load the map, make player entities and send `Net._report_in_run(true)`. Retain catch-up data and wait for `Net._confirm_run_ready`. Request a starter using the run id. | T3 / F4–F5. |
| 4 | Send numbered `in` frames at 30 Hz. Verify `snap.ack`, movement and ammo/shot feedback. | Start 20 Hz tagged `Vector3` transform pushes and report your initial exposure. Check the echoed transform, vitals, and enemy stream. Add local movement collision and send exposure when it changes. | T4–T5 / F6 and supplemental Full checks. |
| 5 | Draw latest snapshots, using events for transient effects. Add map, draft, tape and results. | Add host-resolved combat requests, pickups, effects, interactions, draft, tape and results. Treat each new `_start_run` as a new run. | T6–T7 / F7 and supplemental checks. |
| 6 | Test graceful leave and rejection. | Test version rejection and graceful leave. Add the other encodings and transports your port ships, then repeat the checks. | T8 / F8 and the wire matrix. |

For the smallest live test, choose an otherwise empty server and send ready
after your id appears in the lobby. Keep reading the connection throughout
loading and play. A Full client must handle a new roster during a run and
must be able to decode an RPC for a node it has yet to render.

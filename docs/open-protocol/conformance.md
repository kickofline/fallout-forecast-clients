# Open Protocol conformance

Run the reference checkers from the Fallout Forecast game checkout. If this
guide came with an assets-only checkout, use the game checkout containing the
server and the two scripts.

## Start a local server

Use the Godot 4.7.2 console executable as `godot`. Import once if the checkout
has no Godot import cache. Start the server in a separate terminal with a clean
lobby, and stop it after testing.

```text
godot --headless --path . --import
godot --headless --path . --audio-driver Dummy -- --server --port=17777 --thin-port=17780 --thin-tcp-port=17781 --map pinecrest
```

Use the loopback host for `<server-host>` and the same ports on the client
command lines. The native port 17777 is only for a native Godot co-player.
The defaults without overrides are 7780 (Open Protocol WebSocket) and 7781
(Open Protocol TCP). An optional server join code must match the client's
`--code`. Run independent tests sequentially on an empty lobby. The only
exception below is the explicit mixed-peer check.

## Thin checker

Requires Python 3.11+ and `websockets==15.0.1`. With uv, the script declares
its own dependency. With pip, install it and replace `uv run` with `python`.

```text
uv run tools/thin_client/fake_client.py --transport ws --enc json --host <server-host> --port 17780
uv run tools/thin_client/fake_client.py --transport tcp --enc bin --host <server-host> --port 17781
```

| Id | What the checker verifies | Spec |
| --- | --- | --- |
| T1 | Accepted v1 Thin welcome, requested encoding/rate, your id in the lobby marked `car:true`, matching pong. | [Common §§4–6](spec-common.md#4-handshake-hello-welcome-error), [Thin §2](spec-thin.md#2-negotiation) |
| T2 | Your chat, map vote and ready state echo in the lobby. | [Thin §4](spec-thin.md#4-lobby) |
| T3 | Force start is sent, a concrete map loads and the session enters `run`. A starter item appears in the first slot. | [Thin §3](spec-thin.md#3-session-state-machine) |
| T4 | Numbered input is acknowledged. The player walks over one metre, rotates, sees pitch clamp and ADS, emits a shot event and spends ammo. | [Thin §5](spec-thin.md#5-input), [§6](spec-thin.md#6-snapshot-json), [§9](spec-thin.md#9-events) |
| T5 | Ticks increase, ack and timestamps are monotonic, enemies eventually arrive, and snapshot rate is near the request for an observation longer than 3 s. With radius/cap flags, rows stay sorted/in range or capped as applicable. Binary mode also checks the snapshot decode consumes the payload. | [Thin §6](spec-thin.md#6-snapshot-json), [§7](spec-thin.md#7-binary-snapshot-layout) |
| T6 | The requested map outline matches the loaded id and has valid nonempty boxes. | [Thin §8](spec-thin.md#8-map-outline) |
| T7 | With `--require-results`, the client sees damage and a result containing its name. | [Thin §9](spec-thin.md#9-events), [§11](spec-thin.md#11-results-and-return-to-the-lobby) |
| T8 | Graceful leave yields disconnected status and EOF/normal close. With `--expect-error`, an expected handshake rejection yields an error and close. | [Common §4.4](spec-common.md#44-error-server--client), [§7](spec-common.md#7-leaving-disconnects-and-timeouts) |

Use `--connect-only` for T1 and graceful leave; use `--observe-seconds` to
change the observation window (default 5 s). An interest-management check uses
`--rate 10 --radius 50 --max-enemies 16`. For a join-code rejection, configure
a test code on the server and pass a different code with
`--expect-error "Invalid join code"`. The checker prints `PASS`, snapshot
payload statistics and a nonzero exit on failure. `--url` accepts a complete
WebSocket URL for a TLS-enabled endpoint.

## Full checker

This checker uses Python 3.10+ and the standard library. Use `--mode check`
(the default) and add `--require-enemies` to check the decoded enemy stream.

```text
python tools/open_protocol/full_client.py --transport ws --enc json --host <server-host> --port 17780 --require-enemies
python tools/open_protocol/full_client.py --transport tcp --enc bin --host <server-host> --port 17781 --require-enemies
python tools/open_protocol/full_client.py --transport tcp --enc json --host <server-host> --port 17781 --mode reject
```

| Id | Check names and what they verify | Spec |
| --- | --- | --- |
| F1 | `open_protocol_welcome` checks tier, encoding, peer id, and a positive game version. `control_ping_pong` compares the echoed number. | [Common §§4–6](spec-common.md#4-handshake-hello-welcome-error), [Full §2](spec-full.md#2-open-protocol-handshake) |
| F2 | `game_hello_roster` requires your id in the decoded roster after the game hello. | [Full §§3–4](spec-full.md#3-game-handshake-net_hello), [§§6–9](spec-full.md#6-json-rpc-envelope-encjson) |
| F3 | `lobby_ready_and_start_run` sends vote, chat and ready, and requires `_start_run`. It does not assert vote or chat echoes. Optional `lobby_coexists_with_peers` checks the roster size. | [Full §4](spec-full.md#4-lobby), [§5](spec-full.md#5-run-lifecycle) |
| F4 | `run_report_and_confirm` requires `_confirm_run_ready` after reporting loaded. `run_loot_snapshot` requires a run id from the loot snapshot. | [Full §5](spec-full.md#5-run-lifecycle) |
| F5 | `starter_kit_accepted` requires explicit acceptance of starter choice 0. | [Responsibilities §6](client-responsibilities.md#6-starter-kit-inventory-and-weapons) |
| F6 | `sent_player_transforms` counts at least 20 synthetic 20 Hz pushes. `decoded_weather_phases` and `decoded_player_vitals` require incoming gameplay RPCs. With `--require-enemies`, `decoded_enemy_stream` requires enemy batches and spawn ids. | [Responsibilities §§2–5](client-responsibilities.md#2-movement-and-the-20-hz-transform-push), [§§9–10](client-responsibilities.md#9-enemies-and-the-boss) |
| F7 | `no_protocol_errors` checks for application error messages while receiving the stream. | [Full §11](spec-full.md#11-errors) |
| F8 | `--mode reject` sends a deliberately wrong game version and requires a `Net._reject` containing `UPDATE REQUIRED`. | [Common §5](spec-common.md#5-version-negotiation), [Full §3](spec-full.md#3-game-handshake-net_hello) |

The script answers game RTT probes, sends initial exposure and normally skips
Calm. `--no-skip-calm` leaves the normal timer and may require
`--walk-seconds 35` with `--require-enemies`. For a mixed roster, connect a
second peer first, run the checker with `--expect-peers 2`, then ready the other
peer before the start timeout. `--mode play` is an interactive smoke driver;
`--dump-transcript <file>` records decoded and raw RPC frames in check mode.
Expect a `SUMMARY` line and exit code 0 when every selected assertion passes.

## Wire matrix and supplemental checks

Repeat each tier's regular command for WebSocket/JSON, WebSocket/binary, TCP/JSON
and TCP/binary when validating server compatibility. Use `--enc` to switch
encoding while keeping the port for that transport. Use the corresponding
[transcripts](AGENTS.md#reading-order) for offline format comparisons.

The reference checks verify exchange and decode, with a synthetic Full walk.
A docs-only Full smoke test can use the first Pinecrest spawn from
`level-markers.json` on an empty lobby and move one metre along −Z at walk speed
during the first Calm. Report `(false, false)` for the open-air test spawn and
compare against the server's echoed pushes. This checks the transform wire
path. For a Full gameplay port also check these outcomes:

- See an own-player `_relay_transform` matching a position you sent. Start
  from the map's spawn marker and verify movement stays on the authored collision
  surfaces. Check reported exposure changes at a roof edge and a wet puddle.
  See [responsibilities §§2–3](client-responsibilities.md#2-movement-and-the-20-hz-transform-push).
- Select a starter, fire an accepted shot, and check the corresponding shot FX
  and authoritative ammo update. Throw a projectile and follow its lifecycle
  through deployment or removal. See [responsibilities §§6–7](client-responsibilities.md#6-starter-kit-inventory-and-weapons).
- Join during an active wave and confirm that live enemies, puddles, cabinets and
  inventory initialize before gameplay. After results, ready up and verify the
  next run uses a fresh run id. See [responsibilities §12](client-responsibilities.md#12-late-join-results-and-reset).
- Observe a decon or revive request and its host-side result. Test draft and
  tape choices against a run that reaches those states. See
  [responsibilities §8](client-responsibilities.md#8-interactables-and-pickups)
  and [§11](client-responsibilities.md#11-calm-mutation-draft-pings-pause-endless-tape).

The Thin checker plays through a short run with a shot and optionally observes
results. Exercise draft and tape choices separately in a run that reaches them.

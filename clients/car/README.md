# Fallout Forecast Car client

## Build and export

Use the Godot 3.6.3 editor with matching Android export templates, JDK 17,
Android SDK Platform-Tools and Build-Tools, and Python 3. In the Godot editor
settings under **Export → Android**, set **Java SDK Path** and **Android SDK
Path**. Configure a debug keystore there if Godot has not already created one.

From the repository root, sync the asset pack and create the output directory.

```powershell
python -m pip install soundfile   # optional: lets sync decode SFX .ogg to .wav
python tools/sync_assets.py
New-Item -ItemType Directory -Force build
```

With `soundfile` installed, `sync_assets.py` writes a PCM `.wav` next to each
SFX `.ogg` under `clients/car/assets/`, and the client plays those instead
(no per-voice Vorbis decoding on the head unit's CPU).

Open `clients/car/project.godot` in Godot 3.6.3 and wait for the first import to
finish. Set `GODOT3` to the Godot executable path, then export from `clients/car/`.
On Windows, `Start-Process -Wait` waits for the GUI executable to finish.

```powershell
Push-Location clients/car
Start-Process -FilePath $env:GODOT3 -ArgumentList '--path . --no-window --export-debug "Android Car" ../../build/fallout-car.apk' -Wait -NoNewWindow
Start-Process -FilePath $env:GODOT3 -ArgumentList '--path . --no-window --export-debug "Android Test" ../../build/fallout-car-test.apk' -Wait -NoNewWindow
Pop-Location
```

| Preset | Output | ABI |
| --- | --- | --- |
| Android Car | `build/fallout-car.apk` | `armeabi-v7a` |
| Android Test | `build/fallout-car-test.apk` | `armeabi-v7a` and `x86` |

Both instructions produce debug-signed APKs with package ID
`org.falloutforecast.car`. Use the same debug keystore for updates to an
existing installation.

## Install and connect

With the car parked and USB debugging enabled on the head unit, identify its
ADB serial, then substitute it for `HEAD_UNIT_SERIAL`.

```text
adb devices -l
adb -s HEAD_UNIT_SERIAL install -r build/fallout-car.apk
```

Open **Fallout Car**, pick a mode on the title screen, then connect.

| Mode | Tier | Server field default |
| --- | --- | --- |
| CLOUD | Thin: the server simulates the player | `wss://fallout-thin.drew.place/` |
| CLOUD FULL | Full: the car simulates its own player | `wss://fallout-open.drew.place/` |
| SOLO | Full rules against the in-process solo authority (`solo/local_link.gd`) | choose a district instead |

The app saves the mode, URLs and display name when you connect, and verifies
certificates for WSS connections. Vote for a map and ready up in the lobby.
In the run, use the left stick to move and drag on the right to look. Use the
on-screen actions and hotbar for combat and items.

## Controls

Keyboard + mouse, gamepad and touch all feed the `Controls` autoload
(`core/controls.gd`); gameplay reads only that. The last device used becomes
`Controls.device`. The on-screen touch layer shows only for touch, and the
mouse is captured for mouse look while you play with keyboard + mouse (Esc
releases it). Desktop has no touch layer unless you pass `--touch`.

| Action | Keyboard + mouse | Gamepad | Touch |
| --- | --- | --- | --- |
| Move | WASD / arrows | Left stick | Left floating stick |
| Look | Mouse | Right stick | Drag on the right half |
| Fire / aim | LMB / RMB | RT / LT | FIRE / AIM |
| Jump / crouch | Space / Ctrl or C | A / B | JUMP / CROUCH |
| Sprint | Shift | L3 (latches until you stop or back up) | Push the stick past the rim |
| Reload / interact (hold) | R / E | X / Y | RELOAD / USE |
| Tarp (use_item) | T | D-pad up | ITEM |
| Frag / Shield Dome | Q / F | D-pad left / right | Hotbar pouches |
| Slots / cycle | 1–5 / wheel | RB / LB | Hotbar |
| Drop item / ping | G / Z or MMB | R3 / D-pad down | — |
| Ready up | H | Back | READY |
| Pause / scoreboard (hold) | Esc / Tab | Start / Back | MENU (scoreboard in the menu) |
| Loadout / squad chat | I / Enter | Pause menu | Pause menu |
| Draft cards | 1 / 2 / 3 | Menu navigation | Tap a card |
| Menus | Arrows, Enter, Esc | D-pad or left stick, A, B | Tap |

Settings has separate touch, mouse and pad look sensitivities and inverted
look for all devices. The pad uses a radial 0.2 deadzone with a response curve
on the look stick and hot-plugs, on Android too. Screens can add
`ui/focus_nav.gd` for keyboard and pad focus navigation.

## Quality settings

| Setting | Default | Effect |
| --- | --- | --- |
| Retro VHS / PS1 look | On, 240 lines | Renders the 3D scene and the VHS post pass at a fixed vertical resolution, then upscales. Try 180 lines to reduce GPU load. |
| Render scale | 0.50 | Controls 3D resolution with retro mode off. |
| Map detail | Auto | Auto and Full use the full-detail export. Low uses the decimated export where one exists (Pinecrest), which can z-fight on roads. |
| Fog | Normal | Adjusts the GLES2 distance fog. |
| Particle density | 0.60 | Controls rain and effects density. |
| FPS / ping overlay | On | Shows local frame rate and server round-trip time. |
| Interpolation delay | 100 ms | Buffers replicated actors for smoother motion. |

Settings also exposes reduced flashing, volume, look sensitivity, inverted
look, and touch button sizing.

## Architecture

- `core/net.gd` sends the Thin v1 handshake and exchanges JSON over WebSocket.
  The server owns movement, inventory, combat, enemies, and run outcomes.
- `world/world.gd` sends input at 30 Hz, interpolates remote entities, and
  responds immediately to look and fire. A low-resolution viewport renders
  GLES2 3D with a VHS post-process. The touchscreen controls and HUD use the
  full interface resolution.
- `core/assets.gd` reads the synced manifest. The shipped maps, character
  rigs, weapons, props, and audio come from the main game. Procedural meshes
  cover missing asset IDs. The loading card covers enemy-rig merging, combat
  effect warm-up, and the first draw of the populated world.

The [Open Protocol specification](../../docs/open-protocol/) describes Thin
and Full. The client has no join-code field.

### Full tier (CLOUD FULL and SOLO)

**Settings → CLOUD FULL CONNECTION** saves the transport and encoding.
**WS JSON** is the default. **WS BIN**, **TCP JSON** and **TCP BIN** are also
available. Enter a `ws://` or `wss://` URL, or a TCP `host:port`, in the
CLOUD FULL server field. The client remembers the WebSocket and TCP
addresses separately. Raw TCP is plaintext and requires the server's TCP
listener, normally on port 7781.

- `core/ws_full_link.gd` and `core/tcp_full_link.gd` poll on a helper thread
  and answer `Net._rtt_ping` during main-loop stalls. `core/variant_codec.gd`
  handles JSON values. `core/variant_bin.gd` handles the Godot 4 binary RPC
  and raw frames and gives the session the same Godot 3 value types.
- `core/full_net.gd` (autoload `FullNet`) runs the hello and `game_protocol`
  check, `Net._hello`, the roster and lobby, RTT answers and the spec-full §5
  run lifecycle. It talks only to a FullLink, so solo play runs the same
  code. It mimics the Thin `Net` surface, and the shared screens and HUD read
  `FullNet.current()`. Run RPCs are queued until the world registers, run
  requests are gated on `_confirm_run_ready`, and RPCs after `_finish` are
  dropped.
- `world/full_world.gd` extends `world/world.gd` and reuses its renderer,
  loader, weather, actors, viewmodel and effects. It builds collision with
  `world/level_physics.gd` and spawns each roster peer at
  `player_spawn[i % n]`. It streams `_push_transform` at 20 Hz, reports
  exposure from the roof ray, shelter volumes, teammate tarps and growing
  puddles, and renders the host's enemy, loot, effect, vending, weather,
  draft and tape RPCs. Shots, throws, reloads, slot changes, pickups, decon,
  revive, vending holds and pings go to the host as requests.
- `world/full_player.gd` is the local KinematicBody with the native game's
  movement numbers. It steps once per rendered frame (sub-stepped to 1/30 s)
  instead of at 60 Hz physics, which is cheaper on the head unit.
- `data/game_data.json` is a copy of `docs/open-protocol/game-data.json`
  (game protocol 19). Copy it again when `game_protocol` changes.

The Full tier adds about 1 to 1.5 ms of script per frame on a desktop
(`w_local`, `w_sync`, `w_rpc` and `n_rpc` in `PROF`) over Thin. Draw counts
match Thin (`draws2d` about 55, 3D 65 to 190 draws on Pinecrest).

### Full HUD parity with the native game

The run HUD is `ui/hud.gd`. The pieces that come and go (boss strip, wave
progress, countdown, wave card, popups, teammate cards, feed, mutation row,
health trail) share one batched canvas, `ui/hud_panels.gd`, which redraws only
when its state changes. The loadout (`ui/loadout.gd`), squad chat
(`ui/quick_chat.gd`) and scoreboard (`ui/scoreboard.gd`) are built only while
open. Prompts use `Controls.hint`, so they show the key or button for the
current device. Touch shows no key labels because it has on-screen buttons.
The HUD reads the Full world's read-only state (`boss`, `enemy_mutations`,
`feat_log`, and teammates' `hp`/`suit` in `others`). Thin has none of these,
so the matching pieces stay hidden there.

Compared with the native HUD (`ui/hud.gd`, `juice_hud.gd`, `ping_hud.gd`,
`inventory_menu.gd`, `pause_menu.gd`, `results.gd` in the game repo):

| Native feature | Car Full client |
| --- | --- |
| Vitals: health, suit, hazard (dry / acid rain / acid pool / suit breach), decon charges | Implemented. Text labels replace the icons. |
| Tarp ready and raised with its key, static charge %, invulnerable tint | Implemented. |
| Ammo, reserve, mag pips, low ammo and jam colours, reload progress | Implemented. The reload and jam state show on the reticle. |
| Weapon hint (THROW / STOW for pouches, USE for items) | Simplified. It shows only device keys, not the per-item stat hint. |
| Reticle styles, spread, hit / crit / kill markers, interact hold arc | Implemented (existing). Rings are now batched quads. |
| Disruptor charge ring, downed bleed-out ring with seconds | Implemented. |
| Hotbar, belt pouches, scrap counter | Implemented (existing). |
| Inventory / loadout menu (equip, move, drop, stats, stash) | Implemented: I, or LOADOUT in the pause menu. Works with pad focus, touch and mouse. No drag and drop. |
| Vending prompt with price and affordability, airdrop / decon prompts | Implemented. The price turns pink with NEED N MORE. The native item stat card is not done. |
| Interact prompts with device keys, RELOAD prompt on an empty mag | Implemented. |
| Downed / turned / out: state flash, ATTACK prompt, CALL FOR HELP, SPECTATING name | Implemented. The downed heartbeat plays. The desaturated downed view is not done. |
| Forecast chip: phase, wave, Calm timer, endless counter, READY hint with tally | Implemented. The weather icon and wave pips are text. |
| Calm countdown (last 5 s) with the tick sound | Implemented. |
| Wave intro card | Implemented. The subtitle comes from the wave (storm, flood, acid storm). The forecast modifier text is not sent. |
| Enemies left and wave progress bar | Implemented. The count stays as text. |
| Cumulus boss bar: three sacs, then the core with burn flash; Cloudburst miniboss bar | Implemented. Sac maxima are learned from the first `_sync`. |
| Compass: infected, elites, boss, teammates, drops, stations, group warning | Implemented (existing). Pings are not on the compass. |
| Teammate cards (name, health, suit, state) and name tags | Implemented. Tags show distance, and a downed teammate off screen gets an edge arrow. |
| Supply drop plate and edge arrow | Implemented. |
| Screen-space damage direction markers, damage vignette, acid suit flash | Implemented. The direction markers are wedges with a tip. |
| Damage numbers, popups (scrap, multikill, pickups, feats), health damage trail | Implemented. |
| Rain drips, suit breach beep | Not done (extra full-screen layers cost too much on the car). |
| Pings: world markers, sound, ping feed | Implemented. The ping is contextual (enemy, go, or revive while downed), with no ping wheel. |
| Chat: receive in run, send | Implemented. Received lines go to the feed. SQUAD CHAT (Enter, or the pause menu) has eight quick messages for pad and touch, plus a text line. |
| Scoreboard | Car addition (the native game has none): hold Tab or pad Back, and it also shows in the pause menu. Kills only reach the client in results. |
| Mutation draft (cards, enemy forecast, timer) | Implemented. Pick with 1-3 on a keyboard, focus + A on a pad, or a tap. Vote tallies are not shown. |
| Mutation icons (enemy | squad) | Implemented as two-letter chips. |
| Endless tape choice | Implemented. Pick with 1 / 2, focus + A, or a tap. It blocks gameplay input, and it closes when another player chooses. |
| Feats / achievements | Simplified. Each `_feat_event` shows a popup and is listed on the results. There is no persistent unlock tracking, because the feat table is not in `game-data.json`. |
| Pause menu | Implemented: resume, loadout, squad chat, settings, leave, scoreboard and a controls line. Solo pauses the authority. |
| Results: title, wave segments, time / waves / kills / score tallies with skip, per-player kills / revives / turned / weapon, MVP, squad mutations, feats | Implemented. Suit unlock cards are not done (no cosmetics unlock tracking). |
| Settings: starter kit | Implemented (STARTER KIT, used by Full and solo). HUD scale is not done. |

## Performance notes (Honda head unit, PowerVR SGX 544MP)

Measured 2026-11-25 with the capture harness on the car, Pinecrest, before the
2D batching and material-fold fixes. The baseline was about 15 fps. Hiding the
HUD gave 21 fps, skipping the 3D viewport gave 21 fps, and hiding the HUD,
OSD and post pass together gave 26 fps. The main thread used about 60% of one
core, so the GPU limits the frame rate, and on this GPU draw calls cost more
than vertices:

- The whole-map merge (151k triangles) ran within about 1 fps of the decimated
  merge (103k). A 40 m chunked, frustum-culled export was slower on all three
  maps, so the client draws the full-detail merge.
- The VHS post shader at screen resolution capped the run at about 14 fps. It
  now runs in a viewport at the 3D resolution.
- Godot 3's default `colored_vertex_format_threshold` split 2D batches at every
  colour change. Antialiased lines and arcs, and unfilled rects, never batch.
  The HUD issued about 230 draw calls a frame, and after the fixes it issues
  about 60.
- ProceduralSky regenerated its texture and radiance on the CPU each time the
  storm changed a colour, which caused hitches of about 1 s. `shaders/sky.shader`
  replaces it.

`PROF` lines in logcat show per-section script ms, `render` (time inside
VisualServer draw, including GPU waits) and `draws2d`. `SPIKE` lines list frames
over 250 ms, and `LOAD` lines show map load stages. `NET` lines show socket
events and close codes.

Test switches go one per line in `user://test_args.txt`, the only way to pass
flags to the Godot 3 Android template. Write the file with `adb shell run-as
org.falloutforecast.car`. The switches are `--capture=DIR`, `--map=ID`,
`--run-seconds=N`, `--exit-when-done`, `--probe`, `--no-hud`, `--no-touch`,
`--no-3d`, `--no-post`, `--no-osd`, `--no-rain`, `--hide-level`,
`--hud-hide=i,j`, `--lines=N`, `--variant=glb|low_glb|chunked_glb`,
`--cam=x,y,z,yaw,pitch` and `--net-no-thread`. The project also reads
`user://override.cfg` as project settings, so renderer settings can be A/B
tested without a reinstall.

For local work without the car, compare these counters with the budgets
measured on the car. Watch `draws2d` in a run (about 60 now), 3D `draws`
(about 80 to 175 by map), and script ms in `PROF`, about 20 ms on the car or
roughly a fifth of that on a desktop. The API 22 x86 emulator with
`-cores 2 -gpu swiftshader_indirect`, pinned to two host cores, runs at a
similar overall frame rate (about 10 fps), but it is 3D-bound in software,
not draw-call-bound. Use it for Android behaviour and A/B direction, not
absolute fps.

## Local verification

Headless checks, run from `clients/car/` with Godot 3.6.3:

- `-s ../../tools/godot_check.gd` compiles every script (`bad=0`).
- `-s ../../tools/controls_check.gd` drives Controls and `ui/focus_nav.gd`
  with synthetic keyboard, gamepad and touch input.
- `-s ../../tools/physics_check.gd -- --verify=DIR` builds each map's collision
  and navigation with `world/level_physics.gd`. It walks a player-size capsule
  from every spawn, compares roof rays and shelter volumes with the native
  game's results, and paths from every enemy and drain spawn to every player
  spawn. `DIR` comes from the exporter's `--physics-verify=DIR`.
- `-s ../../tools/thin_input_live.gd -- --url=wss://HOST/ --name=CarTest`
  joins a Thin server and plays a short run with synthetic keyboard + mouse
  and gamepad input. It force-starts only when the lobby is otherwise empty,
  then leaves.

Run the Python mock server from the root in a separate shell.

```text
python tools/mock_bridge.py --fast --host 127.0.0.1
```

For desktop captures, launch the project with Godot 3.6.3 using
`--path clients/car -- --url=ws://127.0.0.1:8790/ --capture=../../build/desktop-captures --exit-when-done`.
The capture harness drives the lobby and run, then saves screenshots and
frame-rate samples. Use an absolute path for `--capture` if launching from
outside the repository.

Full-tier checks use `tests/full_drive.gd` (not exported). It drives the
real client through conformance checks F1 to F8, a short run (spawn, move,
shoot, take damage, results) and a clean leave, printing `DRIVE ... PASS`
lines. Run it against a local dedicated server's Open Protocol port, briefly
against a live server (it force-starts only an otherwise empty lobby), or
against solo.

```text
--path clients/car -- --full-drive --full-url=ws://127.0.0.1:7780/ --drive-probe --exit-when-done
--path clients/car -- --full-drive --full-url=tcp://127.0.0.1:7781 --full-enc=bin --drive-leave-after=24 --drive-wire-check --exit-when-done
--path clients/car -- --full-drive=reject --hello-protocol=18 --full-url=ws://127.0.0.1:7780/ --drive-wire-check --exit-when-done
--path clients/car -- --full-drive=solo --exit-when-done
```

Repeat the normal and reject checks with both URLs and `--full-enc=json`
and `--full-enc=bin` for the local wire matrix. Run
`--path clients/car --no-window -s res://tests/wire_codec.gd` to check and
benchmark the codec against the spec examples and binary transcript.
`res://tests/wire_tcp.gd` checks TCP framing, RTT and disconnects on loopback.

`--drive-probe` also checks shelter exposure, vending, decon, pings, and the
draft and tape overlays. `--drive-hud` (`tests/hud_probe.gd`) injects host RPCs
to step the HUD through 13 states on keyboard + mouse, pad and touch: miniboss,
Cumulus sacs and core, teammate card, feed, popups, downed, spectate, draft,
tape, scoreboard, loadout, chat, pause, countdown and wave card. It checks each
state, and `--drive-tag=S` adds a suffix to the screenshot names (for example a
`--resolution`). It teleports the player, so use it only on a local
server. Use `--drive-leave-after=N` for short live runs and
`--drive-live` to leave an occupied lobby after the handshake.
`--drive-shots=DIR` saves screenshots.

For Android captures, boot a rootable API 22 x86 Android SDK emulator and
run the following from Bash. Set `EMU` if its serial differs from
`emulator-5554`. The emulator reaches the host mock at `10.0.2.2:8790`.

```bash
bash tools/emu_test.sh
```

The script exports and installs the Test APK on the emulator, then pulls
screenshots, FPS samples, and the Godot log to `build/emu-captures/`.

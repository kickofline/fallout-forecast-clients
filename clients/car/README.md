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

Open **Fallout Car** and use **Cloud Play**. The server field defaults to
`wss://fallout-thin.drew.place/`. The app saves the URL and display name when
you connect, and verifies certificates for WSS connections. Vote for a map
and ready up in the lobby. In the run, use the left stick to move and drag on
the right to look. Use the on-screen actions and hotbar for combat and items.

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
| Pause / scoreboard | Esc / Tab | Start / Back | MENU |
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

The [Open Protocol specification](../../docs/open-protocol.md) describes Thin
and Full. This client uses Thin JSON WebSocket messages. It has no join-code
field.

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

For Android captures, boot a rootable API 22 x86 Android SDK emulator and
run the following from Bash. Set `EMU` if its serial differs from
`emulator-5554`. The emulator reaches the host mock at `10.0.2.2:8790`.

```bash
bash tools/emu_test.sh
```

The script exports and installs the Test APK on the emulator, then pulls
screenshots, FPS samples, and the Godot log to `build/emu-captures/`.

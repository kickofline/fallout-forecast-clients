# Fallout Forecast Car client

## Build and export

Use the Godot 3.6.3 editor with matching Android export templates, JDK 17,
Android SDK Platform-Tools and Build-Tools, and Python 3. In the Godot editor
settings under **Export → Android**, set **Java SDK Path** and **Android SDK
Path**. Configure a debug keystore there if Godot has not already created one.

From the repository root, sync the asset pack and create the output directory.

```powershell
python tools/sync_assets.py
New-Item -ItemType Directory -Force build
```

Open `client/project.godot` in Godot 3.6.3 and wait for the first import to
finish. Set `GODOT3` to the Godot executable path, then export from `client/`.
On Windows, `Start-Process -Wait` waits for the GUI executable to finish.

```powershell
Push-Location client
Start-Process -FilePath $env:GODOT3 -ArgumentList '--path . --no-window --export-debug "Android Car" ../build/fallout-car.apk' -Wait -NoNewWindow
Start-Process -FilePath $env:GODOT3 -ArgumentList '--path . --no-window --export-debug "Android Test" ../build/fallout-car-test.apk' -Wait -NoNewWindow
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
`wss://fallout-car.drew.place/`. The app saves the URL and display name when
you connect, and verifies certificates for WSS connections. Vote for a map
and ready up in the lobby. In the run, use the left stick to move and drag on
the right to look. Use the on-screen actions and hotbar for combat and items.

## Quality settings

| Setting | Default | Effect |
| --- | --- | --- |
| Retro VHS / PS1 look | On, 240 lines | Renders the 3D scene at a fixed vertical resolution. Try 180 lines to reduce GPU load. |
| Render scale | 0.50 | Controls 3D resolution with retro mode off. |
| Map detail | Auto | Uses the low-detail export on Android where one exists. Pinecrest includes a low-detail export. |
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

The [Open Protocol specification](../docs/open-protocol.md) describes Thin
and Full. This client uses Thin JSON WebSocket messages. It has no join-code
field.

## Local verification

Run the Python mock server from the root in a separate shell.

```text
python tools/mock_bridge.py --fast --host 127.0.0.1
```

For desktop captures, launch the project with Godot 3.6.3 using
`--path client -- --url=ws://127.0.0.1:8790/ --capture=../build/desktop-captures --exit-when-done`.
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

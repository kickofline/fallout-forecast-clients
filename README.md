# fallout-forecast-car

Car port of Fallout Forecast: a Godot 3.6 (GLES2) Android client for an Android 5.1 head unit
(PowerVR SGX 544MP, OpenGL ES 2.0) that plays Cloud Play co-op through a server-side bridge.

- `client/` Godot 3.6 project (APK).
- `assets/` maps, characters, weapons, fonts and audio exported from the main game.
- `exporter/` Godot 4.7.2 `-s` scripts that generate `assets/` from a checkout of the main game repo.
- `tools/` mock bridge and helper scripts.
- `docs/car-bridge-protocol.md` car <-> bridge protocol. The bridge itself lives in the main game repo (`--car-bridge` mode).

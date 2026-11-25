# fallout-forecast-car

Fallout Forecast Cloud Play client for a 2017 Honda Android 5.1.1 head unit
with a 32-bit ARM CPU and a PowerVR SGX 544MP GPU. The client uses Godot
3.6.3 with GLES2 and joins the dedicated server through the Open Protocol
Thin tier. It renders the game locally while the server simulates the run.

- [Build, install, controls, and quality settings](client/README.md)
- [Fallout Forecast Open Protocol](docs/open-protocol.md)
- [Exported maps, character rigs, weapons, and audio](assets/README.md)
- `exporter/` contains the Godot 4.7.2 scripts that generate the asset pack from the main game.
- `tools/` contains asset sync, the local mock server, and the emulator capture harness.

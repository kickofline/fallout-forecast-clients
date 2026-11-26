# Fallout Forecast Asset Exporter

Godot 4.7.2 `-s` SceneTree scripts that export maps, characters, weapons, items, props, projectiles, fonts, UI art, and audio from a read-only checkout of the original Fallout Forecast repository into `assets/` for the Godot 3.6 (GLES2 / OpenGL ES 2.0) Android head-unit client.

## Requirements

- Godot 4.7.2 console binary (e.g. `Godot_v4.7.2-stable_win64_console.exe`)
- A read-only checkout of the original `fallout-forecast` repository (never modified by the exporter; only Godot's own `.godot/` cache is read)

## Running the Exporter

Godot 4.7.2 accepts an external absolute path to `-s` while `--path` points at the original game checkout, so no files need to be copied into the game repo:

```powershell
C:/Users/drewd/Desktop/Godot_v4.7.2-stable_win64_console.exe `
  --headless `
  --path "C:/path/to/fallout-forecast" `
  --audio-driver Dummy `
  -s "C:/Users/drewd/fallout-forecast-clients/exporter/export_all.gd" `
  -- --out=C:/Users/drewd/fallout-forecast-clients/assets
```

### CLI Options

Pass after `--`:

- `--out=<dir>` — Output directory (default: `C:/Users/drewd/fallout-forecast-clients/assets`)
- `--only=<sections>` — Comma-separated subset of `maps,characters,weapons,audio` (default: all)
- `--maps=<ids>` — Comma-separated subset of `pinecrest,harbor,maple_hollow`
- `--skip-decimate` — Skip generating `<map>_low.glb` when a map exceeds 150k triangles
- `--no-fold-colors` — Keep one material per solid colour (by default untextured opaque solids are folded into vertex colours, which halves the maps' draw calls and renders identically on the client)
- `--chunked` — Also write `<map>_chunked.glb`: the full-detail map split into 40 m grid cells (one multi-surface mesh per cell) so Godot 3 can frustum-cull it. Off by default: on the head unit it ran slower than the whole-map merge on every map, because the extra draw calls cost more than the culled vertices save

### Architecture

- `export_all.gd` — Entry SceneTree script (`_initialize()`, runtime `load()`, zero compile-time `class_name` references). Writes `assets/manifest.json`.
- `lib/mesh_baker.gd` — Traverses `MeshInstance3D`, root `CSGShape3D` (`bake_static_mesh()`), `MultiMeshInstance3D`, and visible `Label3D`s. Bakes:
  - **World-triplanar UVs** (`uv1_triplanar` + `uv1_world_triplanar`): emits per-triangle planar UVs projected along each triangle's dominant normal axis using Godot's `(x*sx+ox, -(y*sy+oy), z*sz+oz)` triplanar mapping so 64×64 textures match without runtime triplanar shaders.
  - **Non-triplanar UV transforms** (`uv1_scale`, `uv1_offset`): baked directly into vertex UVs because Godot 3.6's glTF importer does not evaluate `KHR_texture_transform`.
  - **Custom map shaders**:
    - `props/harbor/tide.gdshader`: pre-blends `harbor_tide.png` with the shader's teal water mix (`mix(vec3(0.09,0.20,0.26), tex*vec3(0.48,0.69,0.75), 0.61)`) and generates world-XZ UVs `(x*0.086, z*0.105)`.
    - Maple Hollow ground mist shader: bakes the radial `smoothstep(1.0, 0.15, r)^2` falloff into a 64×64 RGBA texture on an unshaded alpha-blended material.
  - **Negative-scale winding**: flips triangle winding when `global_transform.basis.determinant() < 0`.
  - **3D Signage (`Label3D`)**: Pinecrest uses the game's runtime `props/map_signs.gd` (`NeonLettering`); Harbor and Maple Hollow static `Label3D` signs (excluding `decon_shower` labels, which `decon_shower.gd` hides) are baked as flat 3D stroke lettering so they export natively in glTF.
  - **Material merging**: merges all static map geometry into one surface per canonical material, after folding untextured opaque solid colours into vertex colours (Pinecrest 149 → 74 materials, Harbor 98 → 48, Maple Hollow 113 → 77).
  - **Triplanar tag**: materials whose triplanar UVs were baked get a `tri_` name; the car client skips PS1 vertex snapping on them like the original's triplanar path (snapped ground and road layers z-fought).
  - **Decimation**: generates `<map>_low.glb` via normal-octant-aware spatial vertex clustering if a map exceeds 150,000 triangles.
- `lib/export_maps.gd` — Instances `pinecrest`, `harbor`, `maple_hollow` (with `building_restyle.gd`, `map_signs.gd`, and `tree_shelter.gd`), extracts sidecar JSONs (`puddles` with raycasted `floor_y`, `shelters`, spawns, `vending_stations`, `decon_showers`, `boss_anchors`, `lights`) and per-weather environment tables (`maps/environments.json`).
- `lib/export_characters.gd` — Exports all 12 enemy types (`drip`, `gutter`, `mister`, `hailstone`, `sleet`, `smog`, `static`, `thunderhead`, `undertow`, `cloudburst`, `cumulus`, `turned`) and all 50 player skin × suit-color combinations with clean articulated node hierarchies and rest poses.
- `lib/export_weapons.gd` — Exports all 24 firearms/items (first-person viewmodels with `LeftHand`/`RightHand` + animated pivots + `Muzzle`/`Sight` markers, and world pickups), ground supply drops, vending station, crate station, airdrop + parachute + beacon, decon shower cells, shield dome, deployed props, and projectiles.
- `lib/export_ui_audio.gd` — Copies fonts, UI icons & map previews (plus PNG conversions of `.webp` previews), and all `.wav`/`.ogg` music & SFX with `audio/sound_map.json`.

## Validation & Comparison Screenshots

Run **without** `--headless` (and with `FALLOUT_TELEMETRY_URL=http://127.0.0.1:1/` so no production telemetry is sent; `user://settings.cfg` is automatically backed up and restored):

```powershell
$env:FALLOUT_TELEMETRY_URL = "http://127.0.0.1:1/"
C:/Users/drewd/Desktop/Godot_v4.7.2-stable_win64_console.exe `
  --path "C:/path/to/fallout-forecast" `
  --audio-driver Dummy `
  -s "C:/Users/drewd/fallout-forecast-clients/exporter/validate_and_capture.gd" `
  -- --assets=C:/Users/drewd/fallout-forecast-clients/assets `
     --shots=C:/Users/drewd/Downloads/fallout-car-assets
```

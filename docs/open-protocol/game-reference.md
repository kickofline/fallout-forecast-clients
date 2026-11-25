# Fallout Forecast game reference

Use [game-data.json](game-data.json) for machine-readable game constants and
[level-markers.json](level-markers.json) for coordinates and node paths. These
exports describe game protocol 19. The server's snapshots and RPCs drive live
state.

## 1. Units and axes

Positions and distances are in metres, timers in seconds, and angles in
radians, except where the wire format documents quantization or milliseconds.
The Godot world is right-handed with +Y up, +X right and −Z forward at yaw
zero. For yaw `y` and pitch `p`, look direction is
`(-sin(y)*cos(p), sin(p), -cos(y)*cos(p))`. Positive yaw turns left and
positive pitch looks up. Player positions are at the feet; the standing
camera is 1.65 m above them. The level marker transforms and weapon muzzle
offsets use the same axes. See [player simulation](client-responsibilities.md#2-movement-and-the-20-hz-transform-push).

## 2. Maps and markers

| Map id | Display | Landmarks |
| --- | --- | --- |
| `pinecrest` | Pinecrest | Main Street, gas canopy, cul-de-sac, water tower |
| `harbor` | Harbor Point | Tidal market, covered docks, Cannery, Signal Walk |
| `maple_hollow` | Maple Hollow | Forest, chapel, cemetery, ranger camp |

Use `welcome.maps` as the selectable list and the concrete map id in `load`
(Thin) or `Net._start_run` (Full) to load the level. `random` is a vote.
`level-markers.json` stores world-space data under `maps[map_id]`.

| Key | How a port uses it |
| --- | --- |
| `player_spawn` | Ordered initial positions and yaws. Full creates new players by ascending numeric peer id, cycling through the markers. |
| `enemy_spawn`, `drain_spawn`, `boss_anchor` | Authored spawn anchors for map presentation. The server sends actual enemy positions. |
| `crate_spawn`, `vending_stations` | Loot anchors and cabinet keys/transforms. |
| `decon_showers` | Marker name and positions. Prefix `interact_path` with `/root/` for a typed Full NodePath argument. |
| `shelter_areas` | World boxes and cylinders, including canopies, for local Full exposure queries. |
| `puddles` | Position, max radius, grow/dry timings, and the absolute `sync_key` for the Full growth dictionary. |

Thin clients can request a separate low-detail [map outline](spec-thin.md#8-map-outline).
A Full port needs world collision and roofs for movement and exposure.

## 3. Infected

| Full kind | Thin type | Infected |
| ---: | --- | --- |
| 0 | `drip` | Drip, the basic pursuer |
| 1 | `gutter` | Gutter, a pouncing hunter |
| 2 | `mister` | Mister, a ranged spore thrower |
| 3 | `sleet` | Sleet, a Swarm specialist |
| 4 | `hailstone` | Hailstone, an armoured heavy |
| 5 | `undertow` | Undertow, a Flood specialist that pulls players |
| 6 | `static` | Static, a Blackout specialist |
| 7 | `smog` | Smog, a weather specialist |
| 8 | `thunderhead` | Thunderhead, a Heavy Weather specialist |

Cloudburst is the wave-three miniboss. Thin emits `cloudburst`; Full sends
the base kind with `miniboss_wave: 3`. The Cumulus boss is `cumulus` on
Thin and has a dedicated spawn and update path on Full. Turned players are
`turned` enemies on Thin and keep their player ids with state `turned` on
Full. Thin binary enum offsets differ from Full kind values. See the
[Thin enemy enum](spec-thin.md#7-binary-snapshot-layout).

## 4. Waves

The campaign has five waves. Calm opens the wave and offers a squad mutation
draft from wave two. Finite groups arrive during Drizzle and Downpour with
forecast-specific mixes. After the timer reaches zero, combat can keep the
phase active until its completion rules are met. Clearing allows recovery
between waves. Cumulus appears in the wave-five storm; the tape choice after
victory can end the run or continue with endless waves and a score.

| Wave | Forecast modifier | Feature |
| ---: | --- | --- |
| 1 | — | Basic groups and shorter opening Calm |
| 2 | Blackout | First squad mutation draft |
| 3 | Flood | Faster puddle growth and Cloudburst |
| 4 | Swarm | Denser infected packs |
| 5 | Heavy Weather | Acid Storm and Cumulus |
| 6+ | Heavy Weather → Flood → Blackout → Swarm, repeating | Endless waves |

| Full phase id | Thin phase label | Typical timer | Target intensity |
| ---: | --- | --- | ---: |
| 0 | `calm` | 12 s first wave, 30 s later, draft can hold the timer | 0 |
| 1 | — | Reserved legacy mutation phase | — |
| 2 | `drizzle` | 30 s | 0.3 |
| 3 | `downpour`, `acid_storm` at full strength | 40–50 s before combat gating | 0.7 waves 1–4, 1.0 wave 5 onward |
| 4 | `clearing` | 15 s | 0 |

Use the received phase/timer and intensity rather than deriving transitions
from this table. Full ports ease intensity from the latest phase target, and
Thin clients receive it in every snapshot. Mutation ids and labels are in
`enemy_mutations` and `player_mutations`.

## 5. Items and weapons

Item ids are shared between tiers. `game-data.json` lists display names,
ammo types, caps, per-weapon firing and projectile data, and item categories.

| Category | Ids |
| --- | --- |
| Starter choices (Full order) | `pump_shotgun`, `nail_driver`, `service_revolver` |
| Other firearms | `spray_rifle`, `hunting_rifle`, `pressure_washer`, `rock_salt`, `battery_zapper`, `flare_launcher`, `harpoon`, `leaf_blower`, `disruptor` |
| Cursed firearms | `leaky_nailgun`, `boombox_launcher`, `lucky_penny_revolver` |
| Throwables | `frag`, `shield_dome`, `umbrella`, `bleach_bomb`, `bait_radio` |
| Deployables | `sandbag`, `lightning_rod` |
| Consumables | `med_tin`, `suit_patch` |

Both tiers have five inventory slots plus frag and shield-dome pouches.
Thin uses hotbar values 1–5 and automatically gets the pump shotgun kit.
Full uses slot indices 0–4 and requests its starter kit. Ground supplies
have a separate flavor such as `health` or `scrap`; decode the tier's
pickup message before indexing the item catalog.

## 6. Cosmetics

| Index | 0 | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- | --- |
| Suit skin | Standard | Gas Mask | Firefighter | Bio-Tech | Ion Rig |

Colour indices 0–9 are Hazmat Yellow, Teal, Hot Pink, Lime, Orange, Purple,
White, Red, Storm Blue and Rust. Exact RGB colours are in `cosmetics.colors`.
Use the assigned indexes in the Full roster and the colour/skin values in
Thin player snapshots to render teammates.

## 7. Exported asset pack

The exported client assets are in the private repository
`kickofline/fallout-forecast-car`. With repository access, start at
`assets/manifest.json`. It indexes the maps by protocol map id and the
enemies, weapons, projectiles, props, player rigs, UI, fonts and audio.
Paths in the manifest are relative to `assets/`. A map entry points to its
GLB and JSON sidecar and may offer a low-detail GLB. Use the marker data in
this documentation to preserve runtime world positions and server NodePaths
when adapting the pack to another engine. The protocol works with procedural
or placeholder art as well.

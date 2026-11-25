#![allow(dead_code)]

use std::collections::HashMap;

use ratatui::style::Color;
use serde::Deserialize;

const GAME_DATA_JSON: &str = include_str!("../../../../docs/open-protocol/game-data.json");
const LEVEL_MARKERS_JSON: &str = include_str!("../../../../docs/open-protocol/level-markers.json");
const ENVIRONMENTS_JSON: &str = include_str!("../../../../assets/maps/environments.json");
const PINECREST_JSON: &str = include_str!("../../../../assets/maps/pinecrest.json");
const HARBOR_JSON: &str = include_str!("../../../../assets/maps/harbor.json");
const MAPLE_HOLLOW_JSON: &str = include_str!("../../../../assets/maps/maple_hollow.json");

#[derive(Debug, Clone)]
pub struct CosmeticColor {
    pub index: i64,
    pub name: String,
    pub rgb: (u8, u8, u8),
}

#[derive(Debug, Clone)]
pub struct EnemyKindDef {
    pub kind: i32,
    pub id: String,
    pub name: String,
    pub max_health: f32,
}

#[derive(Debug, Clone)]
pub struct MutationDef {
    pub id: String,
    pub name: String,
    pub desc: String,
    pub color: (u8, u8, u8),
}

#[derive(Debug, Clone)]
pub struct ItemDef {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub ammo_type: String,
    pub cursed: bool,
    pub legendary: bool,
    pub mag_size: i32,
    pub fire_interval: f32,
    pub automatic: bool,
    pub charge_time: f32,
    pub max_range: f32,
    pub projectile_gravity: f32,
    pub reload_time: f32,
    pub tracer_rgb: (u8, u8, u8),
}

#[derive(Debug, Clone)]
pub struct MapSummary {
    pub id: String,
    pub name: String,
    pub blurb: String,
    pub accent: (u8, u8, u8),
}

#[derive(Debug, Clone)]
pub struct GameCatalog {
    pub colors: Vec<CosmeticColor>,
    pub skins: Vec<String>,
    pub enemy_kinds: HashMap<i32, EnemyKindDef>,
    pub items: HashMap<String, ItemDef>,
    pub player_mutations: HashMap<String, MutationDef>,
    pub enemy_mutations: HashMap<String, MutationDef>,
    pub maps: HashMap<String, MapSummary>,
    pub map_data: HashMap<String, MapData>,
}

#[derive(Debug, Clone)]
pub struct SpawnMarker {
    pub name: String,
    pub pos: [f32; 3],
    pub yaw: f32,
}

#[derive(Debug, Clone)]
pub struct VendingMarker {
    pub key: String,
    pub pos: [f32; 3],
    pub yaw: f32,
    pub size: [f32; 3],
}

#[derive(Debug, Clone)]
pub struct DeconMarker {
    pub name: String,
    pub interact_path: String, // absolute `/root/...`
    pub pos: [f32; 3],
    pub interact_pos: [f32; 3],
    pub radius: f32,
    pub hold_time: f32,
}

#[derive(Debug, Clone)]
pub enum ShelterShape {
    Box { size: [f32; 3] },
    Cylinder { radius: f32, height: f32 },
}

#[derive(Debug, Clone)]
pub struct ShelterArea {
    pub name: String,
    pub path: String,
    pub pos: [f32; 3],
    pub yaw: f32,
    pub is_tree_canopy: bool,
    pub shape: ShelterShape,
}

impl ShelterArea {
    pub fn contains_point(&self, p: [f32; 3]) -> bool {
        let dx = p[0] - self.pos[0];
        let dy = p[1] - self.pos[1];
        let dz = p[2] - self.pos[2];
        match self.shape {
            ShelterShape::Cylinder { radius, height } => {
                if dy.abs() > height * 0.5 {
                    return false;
                }
                dx * dx + dz * dz <= radius * radius
            }
            ShelterShape::Box { size } => {
                if dy.abs() > size[1] * 0.5 {
                    return false;
                }
                // Rotate (dx, dz) by -yaw into local box frame
                let c = self.yaw.cos();
                let s = self.yaw.sin();
                let lx = dx * c - dz * s;
                let lz = dx * s + dz * c;
                lx.abs() <= size[0] * 0.5 && lz.abs() <= size[2] * 0.5
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct PuddleDef {
    pub name: String,
    pub sync_key: String,
    pub pos: [f32; 3],
    pub max_radius: f32,
    pub grow_time: f32,
    pub dry_time: f32,
}

#[derive(Debug, Clone)]
pub struct LightMarker {
    pub pos: [f32; 3],
    pub rgb: (u8, u8, u8),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SolidKind {
    BuildingWall,
    ShelterPillar,
    TreeTrunk,
    Fence,
    VendingCabinet,
    DeconBooth,
}

/// 2D/3D oriented box primitive used by both collision and the 3D ASCII raycaster.
#[derive(Debug, Clone)]
pub struct BoxObstacle {
    pub center: [f32; 3],
    pub half_size: [f32; 3], // half width (x), half height (y), half depth (z)
    pub yaw: f32,
    pub kind: SolidKind,
    pub rgb: (u8, u8, u8),
    pub collidable: bool,
    pub label: String,
}

/// Vertical cylinder primitive (pillars, tree trunks, canopies).
#[derive(Debug, Clone)]
pub struct CylObstacle {
    pub center: [f32; 3],
    pub radius: f32,
    pub y_min: f32,
    pub y_max: f32,
    pub kind: SolidKind,
    pub rgb: (u8, u8, u8),
    pub collidable: bool,
}

/// Overhead roof slab rendered in 3D view (not horizontally collidable).
#[derive(Debug, Clone)]
pub struct RoofSlab {
    pub center_xz: [f32; 2],
    pub half_xz: [f32; 2],
    pub yaw: f32,
    pub y_height: f32,
    pub rgb: (u8, u8, u8),
    pub is_foliage: bool,
}

#[derive(Debug, Clone)]
pub struct EnvPalette {
    pub sky_top: (u8, u8, u8),
    pub sky_horizon: (u8, u8, u8),
    pub ground_bottom: (u8, u8, u8),
    pub ground_horizon: (u8, u8, u8),
    pub fog_calm: (u8, u8, u8),
    pub fog_acid: (u8, u8, u8),
}

#[derive(Debug, Clone)]
pub struct MapData {
    pub id: String,
    pub name: String,
    pub play_min: [f32; 2],
    pub play_max: [f32; 2],
    pub player_spawns: Vec<SpawnMarker>,
    pub enemy_spawns: Vec<SpawnMarker>,
    pub crate_spawns: Vec<SpawnMarker>,
    pub vending_stations: Vec<VendingMarker>,
    pub decon_showers: Vec<DeconMarker>,
    pub shelters: Vec<ShelterArea>,
    pub puddles: Vec<PuddleDef>,
    pub lights: Vec<LightMarker>,
    pub boss_anchor: [f32; 3],
    pub boxes: Vec<BoxObstacle>,
    pub cylinders: Vec<CylObstacle>,
    pub roofs: Vec<RoofSlab>,
    pub env: EnvPalette,
}

impl MapData {
    pub fn is_sheltered(&self, eye: [f32; 3]) -> bool {
        self.shelters.iter().any(|s| s.contains_point(eye))
    }

    /// Resolve horizontal capsule collision against solid map obstacles and arena bounds.
    pub fn resolve_horizontal_collision(&self, pos: &mut [f32; 3], radius: f32) {
        let min_x = self.play_min[0] + radius;
        let max_x = self.play_max[0] - radius;
        let min_z = self.play_min[1] + radius;
        let max_z = self.play_max[1] - radius;
        pos[0] = pos[0].clamp(min_x, max_x);
        pos[2] = pos[2].clamp(min_z, max_z);

        // 2 passes for corner stability
        for _ in 0..2 {
            for b in &self.boxes {
                if !b.collidable {
                    continue;
                }
                let b_min_y = b.center[1] - b.half_size[1];
                let b_max_y = b.center[1] + b.half_size[1];
                if pos[1] + 1.8 < b_min_y || pos[1] > b_max_y {
                    continue;
                }
                let dx = pos[0] - b.center[0];
                let dz = pos[2] - b.center[2];
                let c = b.yaw.cos();
                let s = b.yaw.sin();
                let lx = dx * c - dz * s;
                let lz = dx * s + dz * c;

                let cx = lx.clamp(-b.half_size[0], b.half_size[0]);
                let cz = lz.clamp(-b.half_size[2], b.half_size[2]);
                let diff_x = lx - cx;
                let diff_z = lz - cz;
                let dist_sq = diff_x * diff_x + diff_z * diff_z;

                if dist_sq < radius * radius {
                    let (push_lx, push_lz) = if dist_sq > 1e-6 {
                        let dist = dist_sq.sqrt();
                        let pen = radius - dist;
                        (diff_x / dist * pen, diff_z / dist * pen)
                    } else {
                        // Inside box: push along shallowest axis
                        let pen_x = b.half_size[0] - lx.abs() + radius;
                        let pen_z = b.half_size[2] - lz.abs() + radius;
                        if pen_x < pen_z {
                            (if lx >= 0.0 { pen_x } else { -pen_x }, 0.0)
                        } else {
                            (0.0, if lz >= 0.0 { pen_z } else { -pen_z })
                        }
                    };
                    // Rotate push back to world space
                    pos[0] += push_lx * c + push_lz * s;
                    pos[2] += -push_lx * s + push_lz * c;
                }
            }

            for cyl in &self.cylinders {
                if !cyl.collidable {
                    continue;
                }
                if pos[1] + 1.8 < cyl.y_min || pos[1] > cyl.y_max {
                    continue;
                }
                let dx = pos[0] - cyl.center[0];
                let dz = pos[2] - cyl.center[2];
                let min_d = radius + cyl.radius;
                let d_sq = dx * dx + dz * dz;
                if d_sq < min_d * min_d {
                    let d = d_sq.sqrt().max(1e-4);
                    let pen = min_d - d;
                    pos[0] += dx / d * pen;
                    pos[2] += dz / d * pen;
                }
            }
        }

        pos[0] = pos[0].clamp(min_x, max_x);
        pos[2] = pos[2].clamp(min_z, max_z);
    }
}

pub fn parse_hex_rgb(hex: &str) -> (u8, u8, u8) {
    let s = hex.trim_start_matches('#');
    if s.len() >= 6 {
        let r = u8::from_str_radix(&s[0..2], 16).unwrap_or(180);
        let g = u8::from_str_radix(&s[2..4], 16).unwrap_or(180);
        let b = u8::from_str_radix(&s[4..6], 16).unwrap_or(180);
        (r, g, b)
    } else {
        (180, 180, 180)
    }
}

pub fn rgb_to_color(rgb: (u8, u8, u8)) -> Color {
    Color::Rgb(rgb.0, rgb.1, rgb.2)
}

#[derive(Deserialize)]
struct RawGameData {
    cosmetics: RawCosmetics,
    enemy_kinds: Vec<RawEnemyKind>,
    items: Vec<RawItem>,
    player_mutations: Vec<RawMutation>,
    enemy_mutations: Vec<RawMutation>,
    maps: Vec<RawMapSummary>,
}

#[derive(Deserialize)]
struct RawCosmetics {
    colors: Vec<RawColor>,
    skins: Vec<RawSkin>,
}

#[derive(Deserialize)]
struct RawColor {
    index: i64,
    name: String,
    hex: String,
}

#[derive(Deserialize)]
struct RawSkin {
    name: String,
}

#[derive(Deserialize)]
struct RawEnemyKind {
    kind: i32,
    id: String,
    name: String,
    max_health: f32,
}

#[derive(Deserialize)]
struct RawItem {
    id: String,
    name: String,
    kind: String,
    #[serde(default)]
    ammo_type: String,
    #[serde(default)]
    cursed: bool,
    #[serde(default)]
    legendary: bool,
    weapon: RawWeapon,
}

#[derive(Deserialize)]
struct RawWeapon {
    mag_size: i32,
    fire_interval: f32,
    automatic: bool,
    charge_time: f32,
    max_range: f32,
    projectile_gravity: f32,
    reload_time: f32,
    tracer_color: String,
}

#[derive(Deserialize)]
struct RawMutation {
    id: String,
    name: String,
    desc: String,
    #[serde(default)]
    color: String,
}

#[derive(Deserialize)]
struct RawMapSummary {
    id: String,
    name: String,
    blurb: String,
    accent: String,
}

#[derive(Deserialize)]
struct RawLevelMarkers {
    maps: HashMap<String, RawMapMarkers>,
}

#[derive(Deserialize)]
struct RawMapMarkers {
    name: String,
    #[serde(default)]
    player_spawn: Vec<RawPosYaw>,
    #[serde(default)]
    enemy_spawn: Vec<RawPosYaw>,
    #[serde(default)]
    crate_spawn: Vec<RawPosYaw>,
    #[serde(default)]
    boss_anchor: Vec<RawPosYaw>,
    #[serde(default)]
    vending_stations: Vec<RawVending>,
    #[serde(default)]
    decon_showers: Vec<RawDecon>,
    #[serde(default)]
    shelter_areas: Vec<RawShelterMarker>,
    #[serde(default)]
    puddles: Vec<RawPuddle>,
}

#[derive(Deserialize)]
struct RawPosYaw {
    name: String,
    pos: [f32; 3],
    #[serde(default)]
    yaw: f32,
}

#[derive(Deserialize)]
struct RawVending {
    key: String,
    pos: [f32; 3],
    #[serde(default)]
    yaw: f32,
}

#[derive(Deserialize)]
struct RawDecon {
    name: String,
    interact_path: String,
    pos: [f32; 3],
    interact_pos: [f32; 3],
    radius: f32,
    hold_time: f32,
}

#[derive(Deserialize)]
struct RawShelterMarker {
    name: String,
    path: String,
    pos: [f32; 3],
    shape: String,
    #[serde(default)]
    size: Option<[f32; 3]>,
    #[serde(default)]
    radius: Option<f32>,
    #[serde(default)]
    height: Option<f32>,
    #[serde(default)]
    yaw: f32,
}

#[derive(Deserialize)]
struct RawPuddle {
    name: String,
    sync_key: String,
    pos: [f32; 3],
    max_radius: f32,
    grow_time: f32,
    dry_time: f32,
}

#[derive(Deserialize)]
struct RawAssetMap {
    #[serde(default)]
    lights: Vec<RawLight>,
    #[serde(default)]
    shelters: Vec<RawAssetShelter>,
    #[serde(default)]
    vending_stations: Vec<RawAssetVending>,
}

#[derive(Deserialize)]
struct RawLight {
    pos: [f32; 3],
    #[serde(default)]
    color: String,
}

#[derive(Deserialize)]
struct RawAssetShelter {
    name: String,
    pos: [f32; 3],
    #[serde(default)]
    is_tree_canopy: bool,
}

#[derive(Deserialize)]
struct RawAssetVending {
    name: String,
    #[serde(default)]
    size: Option<[f32; 3]>,
}

#[derive(Deserialize)]
struct RawEnvEntry {
    sky: RawSky,
    fog_base: RawFogBase,
}

#[derive(Deserialize)]
struct RawSky {
    sky_top_color: String,
    sky_horizon_color: String,
    ground_bottom_color: String,
    ground_horizon_color: String,
}

#[derive(Deserialize)]
struct RawFogBase {
    fog_color: String,
    acid_fog_color: String,
}

impl GameCatalog {
    pub fn load_embedded() -> Self {
        let raw_gd: RawGameData =
            serde_json::from_str(GAME_DATA_JSON).expect("embedded game-data.json valid");
        let raw_lm: RawLevelMarkers =
            serde_json::from_str(LEVEL_MARKERS_JSON).expect("embedded level-markers.json valid");
        let raw_envs: HashMap<String, RawEnvEntry> =
            serde_json::from_str(ENVIRONMENTS_JSON).expect("embedded environments.json valid");

        let asset_maps: HashMap<&str, RawAssetMap> = [
            ("pinecrest", serde_json::from_str(PINECREST_JSON).expect("pinecrest.json")),
            ("harbor", serde_json::from_str(HARBOR_JSON).expect("harbor.json")),
            (
                "maple_hollow",
                serde_json::from_str(MAPLE_HOLLOW_JSON).expect("maple_hollow.json"),
            ),
        ]
        .into_iter()
        .collect();

        let colors = raw_gd
            .cosmetics
            .colors
            .into_iter()
            .map(|c| CosmeticColor {
                index: c.index,
                name: c.name,
                rgb: parse_hex_rgb(&c.hex),
            })
            .collect();

        let skins = raw_gd.cosmetics.skins.into_iter().map(|s| s.name).collect();

        let enemy_kinds = raw_gd
            .enemy_kinds
            .into_iter()
            .map(|e| {
                (
                    e.kind,
                    EnemyKindDef {
                        kind: e.kind,
                        id: e.id,
                        name: e.name,
                        max_health: e.max_health,
                    },
                )
            })
            .collect();

        let items = raw_gd
            .items
            .into_iter()
            .map(|i| {
                (
                    i.id.clone(),
                    ItemDef {
                        id: i.id,
                        name: i.name,
                        kind: i.kind,
                        ammo_type: i.ammo_type,
                        cursed: i.cursed,
                        legendary: i.legendary,
                        mag_size: i.weapon.mag_size,
                        fire_interval: i.weapon.fire_interval,
                        automatic: i.weapon.automatic,
                        charge_time: i.weapon.charge_time,
                        max_range: i.weapon.max_range,
                        projectile_gravity: i.weapon.projectile_gravity,
                        reload_time: i.weapon.reload_time,
                        tracer_rgb: parse_hex_rgb(&i.weapon.tracer_color),
                    },
                )
            })
            .collect();

        let player_mutations = raw_gd
            .player_mutations
            .into_iter()
            .map(|m| {
                (
                    m.id.clone(),
                    MutationDef {
                        id: m.id,
                        name: m.name,
                        desc: m.desc,
                        color: if m.color.is_empty() {
                            (120, 230, 180)
                        } else {
                            parse_hex_rgb(&m.color)
                        },
                    },
                )
            })
            .collect();

        let enemy_mutations = raw_gd
            .enemy_mutations
            .into_iter()
            .map(|m| {
                (
                    m.id.clone(),
                    MutationDef {
                        id: m.id,
                        name: m.name,
                        desc: m.desc,
                        color: (255, 110, 80),
                    },
                )
            })
            .collect();

        let maps = raw_gd
            .maps
            .into_iter()
            .map(|m| {
                (
                    m.id.clone(),
                    MapSummary {
                        id: m.id,
                        name: m.name,
                        blurb: m.blurb,
                        accent: parse_hex_rgb(&m.accent),
                    },
                )
            })
            .collect();

        let mut map_data = HashMap::new();
        for (id, lm) in raw_lm.maps {
            let asset = asset_maps.get(id.as_str());
            let env_raw = raw_envs.get(&id);
            let md = build_map_data(&id, lm, asset, env_raw);
            map_data.insert(id, md);
        }

        Self {
            colors,
            skins,
            enemy_kinds,
            items,
            player_mutations,
            enemy_mutations,
            maps,
            map_data,
        }
    }

    pub fn color_rgb(&self, index: i64) -> (u8, u8, u8) {
        self.colors
            .iter()
            .find(|c| c.index == index)
            .map(|c| c.rgb)
            .unwrap_or((255, 217, 51))
    }

    pub fn color_name(&self, index: i64) -> &str {
        self.colors
            .iter()
            .find(|c| c.index == index)
            .map(|c| c.name.as_str())
            .unwrap_or("HAZMAT YELLOW")
    }

    pub fn skin_name(&self, index: i64) -> &str {
        self.skins
            .get((index.rem_euclid(self.skins.len().max(1) as i64)) as usize)
            .map(|s| s.as_str())
            .unwrap_or("STANDARD")
    }

    pub fn item_name<'a>(&'a self, id: &'a str) -> &'a str {
        self.items
            .get(id)
            .map(|i| i.name.as_str())
            .unwrap_or(id)
    }

    pub fn enemy_name(&self, kind: i32) -> &str {
        self.enemy_kinds
            .get(&kind)
            .map(|e| e.name.as_str())
            .unwrap_or("Infected")
    }
}

fn build_map_data(
    id: &str,
    lm: RawMapMarkers,
    asset: Option<&RawAssetMap>,
    env_raw: Option<&RawEnvEntry>,
) -> MapData {
    let player_spawns: Vec<SpawnMarker> = lm
        .player_spawn
        .into_iter()
        .map(|s| SpawnMarker {
            name: s.name,
            pos: s.pos,
            yaw: s.yaw,
        })
        .collect();
    let enemy_spawns: Vec<SpawnMarker> = lm
        .enemy_spawn
        .into_iter()
        .map(|s| SpawnMarker {
            name: s.name,
            pos: s.pos,
            yaw: s.yaw,
        })
        .collect();
    let crate_spawns: Vec<SpawnMarker> = lm
        .crate_spawn
        .into_iter()
        .map(|s| SpawnMarker {
            name: s.name,
            pos: s.pos,
            yaw: s.yaw,
        })
        .collect();
    let boss_anchor = lm
        .boss_anchor
        .first()
        .map(|b| b.pos)
        .unwrap_or([0.0, 18.0, 0.0]);

    let vending_sizes: HashMap<&str, [f32; 3]> = asset
        .map(|a| {
            a.vending_stations
                .iter()
                .filter_map(|v| v.size.map(|sz| (v.name.as_str(), sz)))
                .collect()
        })
        .unwrap_or_default();

    let vending_stations: Vec<VendingMarker> = lm
        .vending_stations
        .into_iter()
        .map(|v| {
            let size = vending_sizes
                .get(v.key.as_str())
                .copied()
                .unwrap_or([2.1, 2.1, 0.95]);
            VendingMarker {
                key: v.key,
                pos: v.pos,
                yaw: v.yaw,
                size,
            }
        })
        .collect();

    let decon_showers: Vec<DeconMarker> = lm
        .decon_showers
        .into_iter()
        .map(|d| {
            let abs_path = if d.interact_path.starts_with("/root/") {
                d.interact_path
            } else {
                format!("/root/{}", d.interact_path.trim_start_matches('/'))
            };
            DeconMarker {
                name: d.name,
                interact_path: abs_path,
                pos: d.pos,
                interact_pos: d.interact_pos,
                radius: d.radius,
                hold_time: d.hold_time,
            }
        })
        .collect();

    let asset_shelters = asset.map(|a| a.shelters.as_slice()).unwrap_or(&[]);
    let shelters: Vec<ShelterArea> = lm
        .shelter_areas
        .into_iter()
        .map(|s| {
            // Match with asset sidecar to pick up clean readable names & tree_canopy flag
            let matched = asset_shelters.iter().find(|as_| {
                (as_.pos[0] - s.pos[0]).abs() < 0.15 && (as_.pos[2] - s.pos[2]).abs() < 0.15
            });
            let is_tree = matched.map(|m| m.is_tree_canopy).unwrap_or_else(|| {
                s.shape == "cylinder"
                    && (s.path.contains("Tree")
                        || s.path.contains("Pine")
                        || s.path.contains("Forest")
                        || s.name.starts_with("@Area3D"))
            });
            let clean_name = matched
                .map(|m| m.name.clone())
                .unwrap_or_else(|| s.name.clone());
            let shape = if s.shape == "cylinder" {
                ShelterShape::Cylinder {
                    radius: s.radius.unwrap_or(2.0),
                    height: s.height.unwrap_or(4.0),
                }
            } else {
                ShelterShape::Box {
                    size: s.size.unwrap_or([4.0, 3.0, 4.0]),
                }
            };
            ShelterArea {
                name: clean_name,
                path: s.path,
                pos: s.pos,
                yaw: s.yaw,
                is_tree_canopy: is_tree,
                shape,
            }
        })
        .collect();

    let puddles: Vec<PuddleDef> = lm
        .puddles
        .into_iter()
        .map(|p| PuddleDef {
            name: p.name,
            sync_key: p.sync_key,
            pos: p.pos,
            max_radius: p.max_radius,
            grow_time: p.grow_time,
            dry_time: p.dry_time,
        })
        .collect();

    let lights: Vec<LightMarker> = asset
        .map(|a| {
            a.lights
                .iter()
                .map(|l| LightMarker {
                    pos: l.pos,
                    rgb: parse_hex_rgb(&l.color),
                })
                .collect()
        })
        .unwrap_or_default();

    let env = match env_raw {
        Some(e) => EnvPalette {
            sky_top: parse_hex_rgb(&e.sky.sky_top_color),
            sky_horizon: parse_hex_rgb(&e.sky.sky_horizon_color),
            ground_bottom: parse_hex_rgb(&e.sky.ground_bottom_color),
            ground_horizon: parse_hex_rgb(&e.sky.ground_horizon_color),
            fog_calm: parse_hex_rgb(&e.fog_base.fog_color),
            fog_acid: parse_hex_rgb(&e.fog_base.acid_fog_color),
        },
        None => EnvPalette {
            sky_top: (28, 22, 56),
            sky_horizon: (217, 88, 107),
            ground_bottom: (26, 20, 38),
            ground_horizon: (107, 58, 85),
            fog_calm: (107, 97, 133),
            fog_acid: (46, 82, 31),
        },
    };

    // Derive playable arena bounds from markers (~-64..64)
    let play_min = [-64.0f32, -64.0f32];
    let play_max = [64.0f32, 64.0f32];

    let mut boxes = Vec::new();
    let mut cylinders = Vec::new();
    let mut roofs = Vec::new();

    // 1. Map-specific signature landmarks & building volumes (non-blocking of spawns/shelters)
    build_map_architecture(id, &mut boxes, &mut cylinders);

    // 2. Derived geometry from every real shelter area (pillars + overhead roofs + tree trunks)
    let mut keepout_points: Vec<[f32; 2]> = Vec::new();
    for sp in &player_spawns {
        keepout_points.push([sp.pos[0], sp.pos[2]]);
    }
    for v in &vending_stations {
        keepout_points.push([v.pos[0], v.pos[2]]);
    }
    for d in &decon_showers {
        keepout_points.push([d.pos[0], d.pos[2]]);
    }

    for sh in &shelters {
        match sh.shape {
            ShelterShape::Cylinder { radius, height } => {
                if sh.is_tree_canopy {
                    // Solid tree trunk at center + overhead pine canopy
                    let near_keepout = keepout_points.iter().any(|kp| {
                        let dx = kp[0] - sh.pos[0];
                        let dz = kp[1] - sh.pos[2];
                        dx * dx + dz * dz < 2.2 * 2.2
                    });
                    if !near_keepout {
                        cylinders.push(CylObstacle {
                            center: [sh.pos[0], 0.0, sh.pos[2]],
                            radius: 0.32,
                            y_min: 0.0,
                            y_max: (sh.pos[1] + height * 0.45).max(3.2),
                            kind: SolidKind::TreeTrunk,
                            rgb: (118, 82, 54),
                            collidable: true,
                        });
                    }
                    roofs.push(RoofSlab {
                        center_xz: [sh.pos[0], sh.pos[2]],
                        half_xz: [radius, radius],
                        yaw: 0.0,
                        y_height: (sh.pos[1] + height * 0.2).max(2.8),
                        rgb: (56, 130, 74),
                        is_foliage: true,
                    });
                } else {
                    // Non-tree cylindrical canopy (e.g., Harbor CanopyShelter)
                    cylinders.push(CylObstacle {
                        center: [sh.pos[0], 0.0, sh.pos[2]],
                        radius: 0.22,
                        y_min: 0.0,
                        y_max: sh.pos[1] + height * 0.5,
                        kind: SolidKind::ShelterPillar,
                        rgb: (150, 165, 178),
                        collidable: true,
                    });
                    roofs.push(RoofSlab {
                        center_xz: [sh.pos[0], sh.pos[2]],
                        half_xz: [radius, radius],
                        yaw: 0.0,
                        y_height: sh.pos[1] + height * 0.5,
                        rgb: (130, 155, 175),
                        is_foliage: false,
                    });
                }
            }
            ShelterShape::Box { size } => {
                let roof_y = (sh.pos[1] + size[1] * 0.5).clamp(2.4, 7.0);
                let roof_rgb = shelter_color(id, &sh.name);
                roofs.push(RoofSlab {
                    center_xz: [sh.pos[0], sh.pos[2]],
                    half_xz: [size[0] * 0.5, size[2] * 0.5],
                    yaw: sh.yaw,
                    y_height: roof_y,
                    rgb: roof_rgb,
                    is_foliage: false,
                });

                // Place thin corner pillars so every shelter has visible architectural posts in 3D FPS
                let hx = (size[0] * 0.5 - 0.25).max(0.4);
                let hz = (size[2] * 0.5 - 0.25).max(0.4);
                let c = sh.yaw.cos();
                let s = sh.yaw.sin();
                let corners = [(-hx, -hz), (hx, -hz), (-hx, hz), (hx, hz)];
                for (lx, lz) in corners {
                    let wx = sh.pos[0] + lx * c + lz * s;
                    let wz = sh.pos[2] - lx * s + lz * c;
                    let blocked = keepout_points.iter().any(|kp| {
                        let dx = kp[0] - wx;
                        let dz = kp[1] - wz;
                        dx * dx + dz * dz < 1.6 * 1.6
                    });
                    if !blocked {
                        cylinders.push(CylObstacle {
                            center: [wx, 0.0, wz],
                            radius: 0.18,
                            y_min: 0.0,
                            y_max: roof_y,
                            kind: SolidKind::ShelterPillar,
                            rgb: brighten(roof_rgb, 24),
                            collidable: true,
                        });
                    }
                }
            }
        }
    }

    // 3. Vending cabinets & Decon booths (small solid visual props)
    for v in &vending_stations {
        boxes.push(BoxObstacle {
            center: [v.pos[0], v.pos[1] + v.size[1] * 0.5, v.pos[2]],
            half_size: [v.size[0] * 0.45, v.size[1] * 0.5, v.size[2] * 0.45],
            yaw: v.yaw,
            kind: SolidKind::VendingCabinet,
            rgb: (245, 195, 66),
            collidable: true,
            label: v.key.clone(),
        });
    }
    for d in &decon_showers {
        cylinders.push(CylObstacle {
            center: [d.pos[0], 0.0, d.pos[2]],
            radius: 0.35,
            y_min: 0.0,
            y_max: 2.6,
            kind: SolidKind::DeconBooth,
            rgb: (82, 232, 224),
            collidable: false,
        });
    }

    // 4. Perimeter boundary fence/wall around the arena
    let fence_rgb = match id {
        "pinecrest" => (98, 92, 114),
        "harbor" => (86, 112, 134),
        _ => (74, 88, 72),
    };
    let half_span = 64.5;
    let wall_h = 3.6;
    boxes.push(BoxObstacle {
        center: [0.0, wall_h * 0.5, -half_span],
        half_size: [half_span, wall_h * 0.5, 0.5],
        yaw: 0.0,
        kind: SolidKind::Fence,
        rgb: fence_rgb,
        collidable: true,
        label: "North Perimeter".into(),
    });
    boxes.push(BoxObstacle {
        center: [0.0, wall_h * 0.5, half_span],
        half_size: [half_span, wall_h * 0.5, 0.5],
        yaw: 0.0,
        kind: SolidKind::Fence,
        rgb: fence_rgb,
        collidable: true,
        label: "South Perimeter".into(),
    });
    boxes.push(BoxObstacle {
        center: [-half_span, wall_h * 0.5, 0.0],
        half_size: [0.5, wall_h * 0.5, half_span],
        yaw: 0.0,
        kind: SolidKind::Fence,
        rgb: fence_rgb,
        collidable: true,
        label: "West Perimeter".into(),
    });
    boxes.push(BoxObstacle {
        center: [half_span, wall_h * 0.5, 0.0],
        half_size: [0.5, wall_h * 0.5, half_span],
        yaw: 0.0,
        kind: SolidKind::Fence,
        rgb: fence_rgb,
        collidable: true,
        label: "East Perimeter".into(),
    });

    MapData {
        id: id.to_string(),
        name: lm.name,
        play_min,
        play_max,
        player_spawns,
        enemy_spawns,
        crate_spawns,
        vending_stations,
        decon_showers,
        shelters,
        puddles,
        lights,
        boss_anchor,
        boxes,
        cylinders,
        roofs,
        env,
    }
}

fn build_map_architecture(id: &str, boxes: &mut Vec<BoxObstacle>, cylinders: &mut Vec<CylObstacle>) {
    match id {
        "pinecrest" => {
            // Main Street storefronts behind BlockAAwning (-28, 8.2) & BlockBAwning (9, 8.2)
            // Awnings sit at Z = 6.45..9.95, so buildings sit just south at Z = 10.5..22.5
            boxes.push(BoxObstacle {
                center: [-28.0, 3.6, 16.5],
                half_size: [14.5, 3.6, 5.5],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (162, 114, 126),
                collidable: true,
                label: "Block A Storefronts".into(),
            });
            boxes.push(BoxObstacle {
                center: [9.0, 3.6, 16.5],
                half_size: [14.5, 3.6, 5.5],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (144, 122, 152),
                collidable: true,
                label: "Block B Hardware".into(),
            });
            // Gas station mini-mart behind GasCanopy (49, 22, size 17.5 x 11.5 -> Z 16.25..27.75)
            boxes.push(BoxObstacle {
                center: [49.0, 2.8, 33.0],
                half_size: [8.5, 2.8, 4.2],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (192, 144, 96),
                collidable: true,
                label: "Gas Station Mart".into(),
            });
            // Suburban houses around the cul-de-sac (north side)
            boxes.push(BoxObstacle {
                center: [0.0, 3.2, -60.5],
                half_size: [6.0, 3.2, 3.5],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (146, 132, 148),
                collidable: true,
                label: "North House".into(),
            });
            boxes.push(BoxObstacle {
                center: [-18.5, 3.0, -19.0],
                half_size: [4.5, 3.0, 5.0],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (154, 126, 118),
                collidable: true,
                label: "Lane West House".into(),
            });
            boxes.push(BoxObstacle {
                center: [23.5, 3.0, -11.5],
                half_size: [4.5, 3.0, 5.0],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (132, 142, 154),
                collidable: true,
                label: "Lane East House".into(),
            });
            boxes.push(BoxObstacle {
                center: [52.0, 3.0, -18.5],
                half_size: [5.5, 3.0, 4.2],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (148, 120, 124),
                collidable: true,
                label: "Main NE House".into(),
            });
            // Iconic Pinecrest Water Tower legs in park NW
            for (dx, dz) in [(-2.0, -2.0), (2.0, -2.0), (-2.0, 2.0), (2.0, 2.0)] {
                cylinders.push(CylObstacle {
                    center: [-52.0 + dx, 0.0, -44.0 + dz],
                    radius: 0.35,
                    y_min: 0.0,
                    y_max: 14.0,
                    kind: SolidKind::ShelterPillar,
                    rgb: (150, 170, 195),
                    collidable: true,
                });
            }
        }
        "harbor" => {
            // Cannery main wall north of the loading aprons (aprons at Z=-36.1)
            boxes.push(BoxObstacle {
                center: [-35.0, 4.5, -47.0],
                half_size: [14.0, 4.5, 7.0],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (126, 148, 168),
                collidable: true,
                label: "Cannery Bay 1".into(),
            });
            boxes.push(BoxObstacle {
                center: [39.0, 4.5, -47.0],
                half_size: [14.0, 4.5, 7.0],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (126, 148, 168),
                collidable: true,
                label: "Cannery Bay 3".into(),
            });
            // Shipping containers in the intermodal yard
            boxes.push(BoxObstacle {
                center: [-18.0, 1.5, -13.0],
                half_size: [4.8, 1.5, 1.4],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (196, 102, 74),
                collidable: true,
                label: "Shipping Container".into(),
            });
            boxes.push(BoxObstacle {
                center: [24.0, 1.5, -14.0],
                half_size: [4.8, 1.5, 1.4],
                yaw: 0.3,
                kind: SolidKind::BuildingWall,
                rgb: (78, 144, 186),
                collidable: true,
                label: "Shipping Container".into(),
            });
        }
        "maple_hollow" => {
            // Wayside Chapel nave behind ChapelPorch (24, -35.75)
            boxes.push(BoxObstacle {
                center: [24.0, 4.2, -45.0],
                half_size: [5.5, 4.2, 6.5],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (168, 158, 152),
                collidable: true,
                label: "Wayside Chapel".into(),
            });
            // Ranger Station behind RangerPorch (-14, 40.9)
            boxes.push(BoxObstacle {
                center: [-14.0, 3.0, 48.0],
                half_size: [6.5, 3.0, 4.5],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (136, 104, 78),
                collidable: true,
                label: "Ranger Station".into(),
            });
            // Lowell Mausoleum behind Portico (47, -8.8)
            boxes.push(BoxObstacle {
                center: [47.0, 3.8, -1.0],
                half_size: [6.2, 3.8, 4.8],
                yaw: 0.0,
                kind: SolidKind::BuildingWall,
                rgb: (140, 144, 156),
                collidable: true,
                label: "Lowell Mausoleum".into(),
            });
        }
        _ => {}
    }
}

fn shelter_color(map_id: &str, name: &str) -> (u8, u8, u8) {
    let lower = name.to_lowercase();
    if lower.contains("gas") || lower.contains("canopy") {
        (225, 165, 78)
    } else if lower.contains("awning") {
        (98, 214, 210)
    } else if lower.contains("gazebo") || lower.contains("pavilion") {
        (165, 134, 98)
    } else if lower.contains("bus") {
        (120, 180, 230)
    } else if lower.contains("cannery") || lower.contains("apron") || lower.contains("crane") {
        (134, 164, 188)
    } else if lower.contains("chapel") || lower.contains("portico") {
        (180, 174, 164)
    } else if map_id == "maple_hollow" {
        (146, 114, 86)
    } else {
        (150, 142, 168)
    }
}

fn brighten(rgb: (u8, u8, u8), delta: u8) -> (u8, u8, u8) {
    (
        rgb.0.saturating_add(delta),
        rgb.1.saturating_add(delta),
        rgb.2.saturating_add(delta),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_all_three_maps_with_real_markers() {
        let cat = GameCatalog::load_embedded();
        for id in ["pinecrest", "harbor", "maple_hollow"] {
            let m = cat.map_data.get(id).expect("map present");
            assert!(m.player_spawns.len() >= 4);
            assert!(!m.shelters.is_empty());
            assert!(!m.puddles.is_empty());
            assert!(!m.vending_stations.is_empty());
            assert!(!m.decon_showers.is_empty());
            for d in &m.decon_showers {
                assert!(d.interact_path.starts_with("/root/Main/Level/DeconShowers/"));
            }
            for p in &m.puddles {
                assert!(p.sync_key.starts_with("/root/Main/Level/Puddles/"));
            }
        }
    }

    #[test]
    fn pinecrest_shelter_detection_works() {
        let cat = GameCatalog::load_embedded();
        let m = &cat.map_data["pinecrest"];
        // Spawn P1 (-2.0, 0.0, 0.5) is open air
        assert!(!m.is_sheltered([-2.0, 1.65, 0.5]));
        // Under BlockBAwning (center [9.0, 1.6, 8.2], size [29.5, 3.2, 3.5])
        assert!(m.is_sheltered([9.0, 1.65, 8.2]));
        // Under GasCanopy (center [49.0, 2.2, 22.0], size [17.5, 4.4, 11.5])
        assert!(m.is_sheltered([49.0, 1.65, 22.0]));
    }
}

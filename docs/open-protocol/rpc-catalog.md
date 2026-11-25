# RPC catalog (generated)

Generated from [open-protocol-schema.json](open-protocol-schema.json) by `tools/open_protocol/gen_rpc_catalog.py`. Game protocol **19**, 102 RPCs on 13 node scripts. Every RPC is `call_remote` (never delivered back to the caller by Godot itself); *relayed* RPCs are re-sent by the server to every relevant peer **including the originator**. Mode `authority` means only the server may send it; `any_peer` RPCs on player nodes are validated by the server against the sender.

Semantics and when to send each client → server RPC are in [client-responsibilities.md](client-responsibilities.md); wire encoding is in [spec-full.md](spec-full.md).

## `Main/Enemies/BossCumulus`

Spawned on Wave 5 Downpour under Main/Enemies. Boss position, part HP, sac count, burn timer, death. Script `res://enemies/boss/boss_cumulus.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| server → peers in the run | reliable, ch 0, `authority` | `_died()` |
| server → peers in the run | reliable, ch 0, `authority` | `_sync(pos: Vector3, parts: Array, sacs: int, burn: float)` |

## `Main/Enemies`

Child of Main. Enemy spawn/despawn/retire, 20 Hz batched position/yaw stream, wave progress, impact/tell/molt cues. Script `res://enemies/enemy_spawner.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| server → peers in the run | reliable, ch 0, `authority` | `_despawn_enemy(net_id: int, drops: Array, at: Vector3, throw_vec: Vector3, critical: bool)` |
| server → peers in the run | unreliable, ch 0, `authority` | `_enemy_impacts(rows: Array)` |
| server → peers in the run | reliable, ch 0, `authority` | `_play_enemy_molt(net_id: int)` |
| server → peers in the run | reliable, ch 0, `authority` | `_play_enemy_tell(net_id: int, cue: String, duration: float, volume: float)` |
| server → peers in the run | reliable, ch 0, `authority` | `_receive_group_warning(at: Vector3)` |
| server → peers in the run | reliable, ch 0, `authority` | `_retire_enemies(ids: PackedInt32Array)` |
| server → peers in the run | reliable, ch 0, `authority` | `_spawn_enemy(net_id: int, kind: int, at: Vector3, small: bool, elite: bool = false, miniboss_wave: int = 0)` |
| server → peers in the run | unreliable ordered, ch 0, `authority` | `_sync_enemies(ids: PackedInt32Array, places: PackedVector3Array, yaws: PackedFloat32Array)` |
| server → peers in the run | unreliable ordered, ch 0, `authority` | `_sync_miniboss_hp(net_id: int, hp: float, max_hp: float)` |
| server → peers in the run | unreliable ordered, ch 0, `authority` | `_sync_progress(wave: int, left: int, total: int, recovery: float, score: int)` |

## `GameManager/CrateManager`

Child of GameManager. Vending cabinet stock/reveals, between-wave airdrops, and hold-to-buy/open requests. Script `res://game/crate_manager.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| client → server | reliable, ch 0, `any_peer` | `_hold_request(run: int, key: String, mode: String, step: String, offer_serial: int)` |
| server → peers in the run | reliable, ch 0, `authority` | `_airdrop_spawn(run: int, at: Vector3, descent: float)` |
| server → peers in the run | reliable, ch 0, `authority` | `_announce_drop(run: int)` |
| server → peers in the run | reliable, ch 0, `authority` | `_remove_drop(run: int)` |
| server → peers in the run | reliable, ch 0, `authority` | `_reveal(run: int, key: String, id: String, tier: int, title: String)` |
| server → one peer | reliable, ch 0, `authority` | `_snapshot(run: int, cabinets: Dictionary, drop: Array)` |
| server → peers in the run | reliable, ch 0, `authority` | `_stock(run: int, key: String, offers: Array)` |

## `GameManager/Feats`

Child of GameManager. Per-player achievement progress awards. Script `res://game/feat_tracker.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| server → one peer | reliable, ch 0, `authority` | `_feat_event(id: String, amount: int)` |

## `GameManager`

Autoload. Global pause, Calm/Clearing ready-up, world interacts, decon pool, boss spawn, endless tape choice, results, shared VFX/hazards. Script `res://game/game_manager.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| client → server | reliable, ch 0, `any_peer` | `_request_interact(path: NodePath)` |
| client → server | reliable, ch 0, `any_peer` | `_request_pause_rpc(paused: bool, who: String)` |
| client → server | reliable, ch 0, `any_peer` | `_request_ready()` |
| client → server | reliable, ch 0, `any_peer` | `_request_tape_choice(keep_playing: bool)` |
| server → every connected peer | reliable, ch 0, `authority` | `_banner(text: String, color: Color, seconds: float)` |
| server → peers in the run | reliable, ch 0, `authority` | `_disperse_cloud(id: int)` |
| server → every connected peer | unreliable, ch 0, `authority` | `_draw_arc(points: Array, color: Color)` |
| server → every connected peer | unreliable, ch 0, `authority` | `_draw_blast(at: Vector3, size: float, color: Color)` |
| server → every connected peer | reliable, ch 0, `authority` | `_finish(won: bool, results: Dictionary)` |
| server → every connected peer | reliable, ch 0, `authority` | `_ready_changed(count: int, needed: int)` |
| server → peers in the run | reliable, ch 0, `authority` | `_spawn_boss(at: Vector3)` |
| server → peers in the run | reliable, ch 0, `authority` | `_spawn_cloud(id: int, at: Vector3, damage_per_second: float, radius: float)` |
| server → peers in the run | reliable, ch 0, `authority` | `_spawn_spore(id: int, from: Vector3, to: Vector3, flight: float, damage_per_second: float, acid: bool, cloudburst: bool)` |
| server → every connected peer | reliable, ch 0, `authority` | `_sync_decon(value: int)` |
| server → every connected peer | reliable, ch 0, `authority` | `_sync_tape_state(choice: bool, is_endless: bool, locked: bool)` |
| server → every connected peer | reliable, ch 0, `authority` | `_weapon_unlocked(weapon_name: String)` |
| relayed (server → all incl. sender) | reliable, ch 0, `authority` | `_sync_pause(paused: bool, who: String)` |

## `GameManager/MutationRoll`

Child of GameManager. Wave 2+ Calm mutation draft deal, vote tally, resolution, and late-join sync. Script `res://game/mutation_roll.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| client → server | reliable, ch 0, `any_peer` | `_request_vote(index: int)` |
| server → every connected peer | reliable, ch 0, `authority` | `_clear_rpc()` |
| server → every connected peer | reliable, ch 0, `authority` | `_deal_rpc(enemy: String, dealt: Array)` |
| server → every connected peer | reliable, ch 0, `authority` | `_reset_run_rpc()` |
| server → every connected peer | reliable, ch 0, `authority` | `_result_rpc(pick: int, enemy_list: Array, player_list: Array, granted: Array)` |
| server → every connected peer | reliable, ch 0, `authority` | `_sync_active(enemy_list: Array, player_list: Array)` |
| server → every connected peer | reliable, ch 0, `authority` | `_votes_rpc(counts: Array)` |

## `Net`

Autoload. Session handshake, lobby roster, map voting, chat, run start/readiness, RTT pings. Script `res://game/net.gd`, available: always.

| Direction | Delivery | Signature |
| --- | --- | --- |
| client → server | reliable, ch 0, `any_peer` | `_hello(hello: String, protocol: int = 0)` |
| client → server | reliable, ch 0, `any_peer` | `_report_in_run(value: bool)` |
| client → server | reliable, ch 0, `any_peer` | `_request_chat(text: String)` |
| client → server | reliable, ch 0, `any_peer` | `_request_cosmetic(color: int, skin: int, unlocked: Array = null)` |
| client → server | reliable, ch 0, `any_peer` | `_request_force_start()` |
| client → server | reliable, ch 0, `any_peer` | `_request_map_vote(id: String)` |
| client → server | reliable, ch 0, `any_peer` | `_request_name(new_name: String)` |
| client → server | reliable, ch 0, `any_peer` | `_request_ready(value: bool)` |
| client → server | unreliable, ch 0, `any_peer` | `_rtt_pong(seq: int)` |
| server → one peer | reliable, ch 0, `authority` | `_confirm_run_ready()` |
| server → one peer | reliable, ch 0, `authority` | `_push_roster(new_roster: Dictionary, map_id: String, voting: bool, counts: Dictionary, my_vote: String)` |
| server → one peer | reliable, ch 0, `authority` | `_reject(reason: String)` |
| server → one peer | unreliable, ch 0, `authority` | `_rtt_ping(seq: int, measured_rtt: float)` |
| server → one peer | reliable, ch 0, `authority` | `_start_run(map_id: String)` |
| relayed (server → all incl. sender) | reliable, ch 0, `authority` | `_chat_rpc(sender: String, text: String)` |

## `Main/Pings`

Created by main.gd. Contextual/wheel squad pings (client request -> host validated relay). Script `res://game/ping_system.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| client → server | reliable, ch 0, `any_peer` | `_request_ping(kind: String, pos: Vector3, enemy_id: int)` |
| relayed (server → all incl. sender) | reliable, ch 0, `authority` | `_show_ping(peer: int, kind: String, pos: Vector3, enemy_id: int)` |

## `Main/Players/P_<peer_id>`

One node per peer in Net.roster, authority = owning peer_id. All RPCs use any_peer + explicit sender validation. Script `res://player/player.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| client → server | reliable, ch 0, `any_peer` | `_push_tarp(value: bool)` |
| client → server | unreliable ordered, ch 0, `any_peer` | `_push_transform(pos: Vector3, yaw: float, pitch: float, vel: Vector3)` |
| client → server | reliable, ch 0, `any_peer` | `_report_exposure(is_sheltered: bool, is_in_puddle: bool)` |
| client → server | reliable, ch 0, `any_peer` | `_request_melee()` |
| server → peers in the run | unreliable ordered, ch 0, `any_peer` | `_apply_vitals(hp: float, suit: float, new_state: String, bleed: float, tarp: bool, max_hp: float = 100.0, charge: float = 0.0, invuln: bool = false)` |
| server → one peer | reliable, ch 0, `any_peer` | `_grant_tarp()` |
| server → one peer | reliable, ch 0, `any_peer` | `_receive_enemy_pull(impulse: Vector3)` |
| server → one peer | reliable, ch 0, `any_peer` | `_receive_hits(run: int, hits: Array)` |
| server → one peer | unreliable, ch 0, `any_peer` | `_receive_hurt_from(at: Vector3)` |
| server → one peer | reliable, ch 0, `any_peer` | `_teleport(xf: Transform3D)` |
| relayed (server → all incl. sender) | reliable, ch 0, `any_peer` | `_apply_tarp(value: bool)` |
| relayed (server → all incl. sender) | unreliable ordered, ch 0, `any_peer` | `_relay_transform(pos: Vector3, yaw: float, pitch: float, vel: Vector3)` |

## `Main/Level/DeconShowers/<decon_marker>/Interact`

Attached under each node in group 'decon_shower' by main.gd (exact paths per map in docs/open-protocol/level-markers.json). Spray VFX broadcast when a player repairs their suit. Script `res://props/decon_shower.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| server → peers in the run | reliable, ch 0, `authority` | `play_spray()` |

## `Main/RunLoot`

Created by main.gd. Starter kit selection, world pickups, projectiles/deployables, weapon unlocks. Script `res://weapons/run_loot.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| client → server | reliable, ch 0, `any_peer` | `_claim(run: int, id: int, expected: int, slot: int)` |
| client → server | reliable, ch 0, `any_peer` | `_request_starter(run: int, index: int)` |
| server → peers in the run | reliable, ch 0, `authority` | `_discover(run: int, id: String)` |
| server → peers in the run | reliable, ch 0, `authority` | `_effect_deploy(run: int, seq: int, at: Vector3, life: float, yaw: float)` |
| server → peers in the run | reliable, ch 0, `authority` | `_effect_end(run: int, seq: int, at: Vector3, blast: bool)` |
| server → peers in the run | reliable, ch 0, `authority` | `_effect_spawn(run: int, seq: int, row: Array)` |
| server → peers in the run | unreliable ordered, ch 0, `authority` | `_flight(run: int, rows: Array)` |
| server → peers in the run | reliable, ch 0, `authority` | `_release(run: int, id: int)` |
| server → peers in the run | reliable, ch 0, `authority` | `_remove(run: int, id: int, collector: int)` |
| server → one peer | reliable, ch 0, `authority` | `_snapshot(run: int, rows: Array, effects: Array, found: Array, chosen: bool)` |
| server → peers in the run | reliable, ch 0, `authority` | `_spawn(run: int, id: int, row: Array)` |
| server → one peer | reliable, ch 0, `authority` | `_starter_accepted(run: int)` |

## `Main/Players/P_<peer_id>/Head/Camera3D/WeaponHolder`

Child of each player's camera. Authoritative 5-slot inventory, belt pouches, shot/throw/reload/swap/drop requests and FX relays. Script `res://weapons/weapon_holder.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| client → server | reliable, ch 0, `any_peer` | `_action(run: int, action: String, expected: int, slot: int)` |
| client → server | reliable, ch 0, `any_peer` | `_request_shot(run: int, serial: int, origin: Vector3, dir: Vector3, is_aiming: bool, predicted: bool)` |
| client → server | reliable, ch 0, `any_peer` | `_request_throw(run: int, id: String, origin: Vector3, dir: Vector3)` |
| server → one peer | reliable, ch 0, `any_peer` | `_jam(run: int)` |
| server → one peer | reliable, ch 0, `any_peer` | `_play_charge(run: int, serial: int)` |
| server → one peer | reliable, ch 0, `any_peer` | `_pouch_full_feedback(run: int, id: String)` |
| server → one peer | reliable, ch 0, `any_peer` | `_private_state(run: int, rev: int, rows: Array, stash: Dictionary, slot: int, pouch: String, new_scrap: int, frags: int, shield_domes: int, reload_left: float, reload_total: float, jam_left: float, cooldown: float)` |
| server → one peer | reliable, ch 0, `any_peer` | `_scrap_feedback(run: int, amount: int)` |
| relayed (server → all incl. sender) | reliable, ch 0, `any_peer` | `_equip_state(run: int, rev: int, id: String, tier: int, left: float, total: float)` |
| relayed (server → all incl. sender) | unreliable ordered, ch 0, `any_peer` | `_shot_fx(run: int, id: String, origin: Vector3, dir: Vector3, traces: Array, ads: bool, predicted: bool)` |
| relayed (server → all incl. sender) | unreliable ordered, ch 0, `any_peer` | `_throw_fx(run: int, id: String, origin: Vector3, dir: Vector3, predicted: bool)` |

## `WeatherManager`

Autoload. Storm phase/wave transitions, intensity overrides, lightning strikes, and puddle growth. Script `res://weather/weather_manager.gd`, available: run.

| Direction | Delivery | Signature |
| --- | --- | --- |
| server → every connected peer | reliable, ch 0, `authority` | `_override(value: float)` |
| server → one peer | reliable, ch 0, `authority` | `_receive_intensity(value: float)` |
| server → every connected peer | reliable, ch 0, `authority` | `_receive_phase(new_phase: int, new_wave: int, time_left: float)` |
| server → every connected peer | reliable, ch 0, `authority` | `_strike(position: Vector3, strike_seed: int)` |
| server → peers in the run | reliable, ch 0, `authority` | `_sync_puddles(wet: Dictionary)` |

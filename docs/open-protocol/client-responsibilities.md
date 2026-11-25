# Full tier: client responsibilities

Fallout Forecast is **owner-predicted, host-authoritative**. A Full-tier
client does what a native Godot client does: it simulates its own player and
local effects, reports a few facts the host trusts, and renders everything the
host replicates. This page is the checklist. Wire formats are in
[spec-full.md](spec-full.md); exact signatures in [rpc-catalog.md](rpc-catalog.md);
numbers in [game-data.json](game-data.json) and [level-markers.json](level-markers.json).

Notation: `ME` = `Main/Players/P_<you>`, `HOLDER` = `ME/Head/Camera3D/WeaponHolder`,
`run` = the run id from `Main/RunLoot._snapshot` (first argument). Every
run-scoped request you send waits for `Net._confirm_run_ready`
([spec-full §5](spec-full.md#5-run-lifecycle)).

## Who owns what

| You (the client) own | The server owns |
| --- | --- |
| Your position, velocity, yaw, pitch, crouch, jumping, collision with the level | Health, suit, state (ok/downed/turned/out), bleed-out, invulnerability |
| Shelter / puddle detection for **your** player (reported) | Inventory, ammo, scrap, pouches, reload/jam/cooldown timers |
| Local presentation: camera, viewmodel, recoil, muzzle flash, tracers you predict, audio, HUD | Hit detection and damage for every shot, explosion, melee and hazard |
| Hold-to-interact timing (decon, revive) before sending the request | Enemy AI, navigation, spawns, waves, boss |
| Weather countdown/intensity easing between phase messages | Phase changes, lightning, drafts, vending stock, airdrops, results |
| Projectile flight *visuals* between corrections | Projectile physics, deploys, blasts |

## 1. Units, axes and timing

Godot conventions: metres, seconds, radians, right-handed, **+Y up, -Z forward**
at yaw 0, +X right. `ME` position = feet. Body yaw rotates about +Y (a yaw of
`y` faces `(-sin y, 0, -cos y)`); head pitch rotates about the head's local +X,
positive up, clamped ±88°. Camera/eye = feet + (current height − 0.15):
1.65 m standing, 0.95 m crouched, 0.55 m downed. The server simulates at 60
physics ticks per second.

## 2. Movement and the 20 Hz transform push

Simulate your own avatar with a capsule of radius **0.4 m**, height 1.8 m
standing / 1.1 m crouched / 0.7 m downed, colliding with world geometry
(physics layer 1; the exported level meshes in the asset pack). Reference
constants ([game-data.json](game-data.json) → `player`):

| Constant | Value |
| --- | --- |
| walk / sprint / crouch speed | 5.0 / 8.0 / 2.5 m/s |
| crawl (downed) / turned speed | 1.0 / 5.5 m/s |
| aiming or tarp raised | speed capped at 3.5 m/s (0.7 × walk) |
| ground / air acceleration | 60 / 12 m/s² |
| jump velocity | 4.8 m/s (coyote time 0.12 s, jump buffer 0.12 s; no jump while crouched or downed) |
| gravity | 9.8 m/s² |
| sprint allowed | only while moving forward, standing, not aiming, state `ok` |
| Adrenaline Glands mutation | × 1.18 speed, × 1.2 jump |

**Push:** every **50 ms (20 Hz)** while in a run and not `out`, send
`ME._push_transform(pos: Vector3, yaw: float, pitch: float, vel: Vector3)`
**unreliable-ordered** (`rel:false` / binary flags `01`). `pos` = feet,
`yaw` = body yaw, `pitch` = head pitch, `vel` = current velocity. The server
relays it to the other players and uses it as your authoritative position for
enemy targeting, pickups, interaction reach and shot validation.

**Apply server movement overrides immediately.**

- `ME._teleport(xf: Transform3D)`: snap to `xf.origin` and its yaw, zero your
  velocity (used when Turned/out players respawn at Clearing).
- `ME._receive_enemy_pull(impulse: Vector3)`: add `impulse` to your velocity
  as a decaying pull (it decays toward zero at 22 m/s²; Undertow drags players).

**Other players:** `Main/Players/P_<id>._relay_transform(pos, yaw, pitch, vel)`
arrives at ~20 Hz for every player in the run — **including you; ignore your
own**. For smooth remote players, keep the latest target, extrapolate
`target + vel × min(age, 0.1 s)` and blend each frame with factor
`1 − exp(−14 × dt)`; snap if the error exceeds 4 m. Thin-tier players are
simulated by the server and arrive through the same RPC.

**Turned players** (`state == "turned"`, co-op only) are enemies of the living:
move them with `turned_speed`; pressing fire sends `ME._request_melee()`
(server checks 2.2 m range in front of you and a 0.9 s cooldown).

## 3. Shelter and puddle exposure (critical)

The host does **not** compute shelter for Full or native clients. It trusts
`ME._report_exposure(is_sheltered: bool, is_in_puddle: bool)` (reliable). If you
never send it, you are treated as exposed and acid rain eats your suit, then
your health.

Compute every physics frame:

- `sheltered` = **roof ray** OR **shelter volume**:
  - roof ray: from feet + (0, 1.0, 0) straight up 40 m; true if it hits world
    geometry (layer 1: roofs, awnings, canopies built from level meshes);
  - shelter volume: the head/eye point (feet + height − 0.15) is inside any
    shelter area (layer 4): the map's `shelter_areas` in
    [level-markers.json](level-markers.json) (boxes, cylinders and tree canopies,
    with world position and yaw), plus every teammate's **raised tarp** — a
    vertical cylinder of radius 2.0 m and height 2.6 m with its base at that
    player's feet (tarp state from `_apply_tarp` / `_apply_vitals`).
- `in_puddle` = the point feet + (0, 0.05, 0) is inside an active puddle: a
  vertical cylinder at the puddle's position (`puddles` in level-markers.json),
  height 0.4 m centred on that position, radius `max_radius × growth`, active
  only while that radius is > 0.25 m (§10 puddle growth).

Send `_report_exposure(sheltered, in_puddle)` once right after
`Net._confirm_run_ready` and again on **every change** of either value.
`exposed = !sheltered || in_puddle` (a puddle under a roof still burns). Shield
Domes and Umbrella Stands are applied by the host itself; you do not report them.

What the host does with it: while it rains (Drizzle/Downpour), an exposed `ok`
player loses suit at 0–6 points/s depending on storm intensity (× 0.65 with
Chitin Suit, × 0.25 inside a dried bleach zone); at 0 suit the drain hits
health. The first rain contact each storm has a 0.8 s grace. You see the result
in `_apply_vitals`.

## 4. RTT keepalive

Once per second the host sends `Net._rtt_ping(seq: int, measured_rtt: float)`
(unreliable; it starts right after `welcome`, before `Net._hello`). Reply at once
with `Net._rtt_pong(seq)` (unreliable). The host smooths the RTT and rewinds
enemy hitboxes by `clamp(rtt/2 + 33 ms, 0, 250 ms)` when it resolves **your**
shots (50 ms if it has no sample). `measured_rtt` is the host's current
estimate of your RTT in ms (display it if you like). Not answering makes your
shots resolve against stale positions.

## 5. Vitals and player state

The host pushes `P_<id>._apply_vitals(hp, suit, new_state, bleed, tarp, max_hp, charge, invuln)`
every 0.2 s (unreliable-ordered) for every player, **including you**. Treat it
as authoritative: health, suit (0–100), state (`ok`, `downed`, `turned`, `out`),
bleed-out seconds left (starts at 20 s), tarp raised, max health (100, 125
with Chitin Suit), static charge 0–1, invulnerable (spawn/revive grace).

- `downed`: crawl at 1 m/s, low camera; teammates revive you (§8).
- `turned`: you are an infected; see §2.
- `out`: spectate (no input). Clearing brings you back (`_teleport`).
- Damage feedback: `ME._receive_hurt_from(at: Vector3)` (direction of the hit);
  health drops arrive in `_apply_vitals`.
- Tarp: `ME._grant_tarp()` gives you a tarp; toggle it with
  `ME._push_tarp(value: bool)`; the host answers everyone with `_apply_tarp`.

## 6. Starter kit, inventory and weapons

**Inventory is host-authoritative.** Your state arrives in
`HOLDER._private_state(run, rev, rows, stash, slot, pouch, new_scrap, frags, shield_domes, reload_left, reload_total, jam_left, cooldown)`;
apply only if `run` matches and `rev` > the last applied `rev`. `rows` = five
items `[serial, id, tier, count]` or `[]`; `stash` = reserve ammo by ammo type
(`{"nail":60}`); `slot` = selected slot 0–4; `pouch` = `""`, `"frag"` or
`"shield_dome"` (selected pouch). Other players' held item: `P_<id>/…/WeaponHolder._equip_state(run, rev, id, tier, left, total)`
(ignore it for yourself).

**Starter kit (required).** A fresh player starts with an empty inventory and empty pouches. After
`Net._confirm_run_ready`, send `Main/RunLoot._request_starter(run, index)` with
`index` 0 = `pump_shotgun`, 1 = `nail_driver`, 2 = `service_revolver`. The host
sends the updated `_private_state` and `Main/RunLoot._starter_accepted(run)`.
For a blank inventory, expect the gun in slot 0, reserve ammo, two frags and
one shield dome. Use the selected slot reported by the host if the player
picked up gear first. One kit is granted per peer id per run.
`RunLoot._snapshot(..., chosen)` = true means this peer already claimed a kit.
A reconnect receives a new peer id. Offer a choice or choose automatically
while the player can act. If a draft or pause blocked the request, retry
when normal play resumes.

**Inventory actions** — `HOLDER._action(run, action, expected, slot)`:

| `action` | `expected` | `slot` | Effect |
| --- | --- | --- | --- |
| `select` | any (send the held serial) | 0–4 | Hold that slot (clears a selected pouch). |
| `select_pouch` | 0 | 0 frag, 1 shield dome, -1 none | Ready a pouch item; the next "fire" throws it. |
| `reload` | held item's serial | -1 | Start reloading (shell-by-shell for shotguns). |
| `drop` | held item's serial | -1 | Drop the held item in front of you. |
| `drop_slot` | that slot's item serial | 0–4 | Drop a specific slot. |
| `swap` | moving item's serial | `from × 5 + to` | Move/swap/merge two slots. |
| `charge` | held item's serial | -1 | Begin charging a weapon with `charge_time` > 0 (Disruptor); fire after the charge time. |

A mismatching serial or a request while downed, voting, awaiting a tape
choice or paused is
ignored; re-read `_private_state`.

**Using the held item** (guns, throwables, deployables, consumables in slots):
`HOLDER._request_shot(run, serial, origin: Vector3, dir: Vector3, is_aiming: bool, predicted: bool)`
(reliable).

- `serial` = held item's serial; `origin` = your camera/eye position;
  `dir` = view direction (unit vector, from yaw/pitch:
  `(-sin y·cos p, sin p, -cos y·cos p)`).
- The host rejects it unless: you are in the run and `ok`; `run` and `serial`
  match, no pouch is selected, no tarp is raised, sprint is inactive and the
  weapon's cooldown elapsed
  (`fire_interval`, × 0.8 with Reflex Tendons — see `items[].weapon` in
  game-data.json); ammo > 0; not jammed; not mid-reload (except shell reloads);
  `origin` is within **3 m** of the host's copy of your camera with clear line of
  sight; `dir` is finite and has length squared ≥ 0.5 (send a unit vector).
- The host resolves spread, pellets, damage, pierce and lag compensation, then
  sends everyone `HOLDER._shot_fx(run, id, origin, dir, traces, ads, predicted)`
  with `traces = [[end, impact], ...]` (impact 0 none, 1 soft surface, 2
  damageable, 3 metal), and you a `ME._receive_hits(run, hits)` for hit markers
  and damage numbers (`[[killed, critical, pos, damage, enemy_id], ...]`).
- **Prediction:** you may play muzzle flash, recoil and sound immediately and
  send `predicted = true`; when your own `_shot_fx` comes back with
  `predicted = true`, skip those effects and only draw the authoritative
  tracers. With `predicted = false` play everything from `_shot_fx`.
- Hold-to-fire for automatic weapons = send `_request_shot` every
  `fire_interval` while the trigger is held.
- Non-hitscan items spawn effects (§7); consumables (Med Tin, Suit Patch) heal
  you; deployables (Sandbag, Lightning Rod, Umbrella) are placed in front of you.
- Feedback-only RPCs: `HOLDER._jam(run)` (your gun jammed), `_play_charge`,
  `_pouch_full_feedback(run, id)`, `_scrap_feedback(run, amount)`.

**Pouch throws:** `_action(run, "select_pouch", 0, 0|1)`, then
`HOLDER._request_throw(run, id, origin, dir)` with `id` `"frag"` or
`"shield_dome"` (same origin rules; 0.35 s owner cooldown). Everyone gets `_throw_fx`.
The host sets `predicted:true` for Full throw requests. Track whether you
already played local throw effects before deciding what to render from the echo.

## 7. Projectiles, deployables and hazards

The host simulates projectiles; you draw them.

- `Main/RunLoot._effect_spawn(run, seq, row)` with
  `row = [id, pos, vel, tier, deployed, life_left, yaw]`: create a visual for
  `seq`; integrate `pos += vel·dt`, `vel.y -= 9.8 × projectile_gravity × dt`
  (weapon data) between corrections.
- `Main/RunLoot._flight(run, [[seq, pos, vel], ...])` at 10 Hz: correct them.
- `_effect_deploy(run, seq, at, life, yaw)`: it landed/deployed (dome, sandbag,
  rod…) for `life` seconds. `_effect_end(run, seq, at, blast)`: remove it
  (`blast` → explosion visual).
- Enemy hazards: `GameManager._spawn_spore(id, from, to, flight, dps, acid, cloudburst)`
  (an arcing glob from `from` to `to` over `flight` seconds that leaves a cloud),
  `GameManager._spawn_cloud(id, at, dps, radius)`, `GameManager._disperse_cloud(id)`.
  Damage is host-only; these are visuals.
- Visual helpers: `GameManager._draw_arc(points, color)` (lightning chains),
  `GameManager._draw_blast(at, size, color)`, `GameManager._banner(text, color, seconds)`.

Never apply damage locally.

## 8. Interactables and pickups

Mirror the level's marker nodes so you can find interactables and their exact
server paths ([level-markers.json](level-markers.json)).

| Interactable | How | Server checks |
| --- | --- | --- |
| **Decon shower** (refills suit to 100, spends one shared charge) | Hold interact **1.0 s** locally, then `GameManager._request_interact(path)` with the **absolute** NodePath `"/root/Main/Level/DeconShowers/<Name>/Interact"` (`interact_path` in level-markers.json, prefixed with `/root/`). | You are `ok`, within 3.7 m (2.2 + 1.5) of the Interact node (marker + 1 m up), suit < 99, shared charges > 0. Success: `.../Interact.play_spray()` to run peers and `GameManager._sync_decon`. |
| **Revive a downed teammate** | Hold **3.0 s** within 2.2 m, then `GameManager._request_interact("/root/Main/Players/P_<their id>/ReviveSpot")`. Solo: once per wave on your own ReviveSpot while downed. | Target `downed`; you `ok` (or self-revive allowed); within 3.7 m. |
| **World pickup** (weapon or item on the ground) | When within 2.55 m and the pickup (+0.28 m) is in view with clear line of sight, `Main/RunLoot._claim(run, pickup_id, expected = held serial, slot = selected slot)`. Frags/domes fill the pouches. | Reach + line of sight, your selection unchanged. The replaced item drops. |
| **Supplies & scrap** (`flavor` ammo/supply/ammo_box/health/suit/scrap/scrap_large/tarp/decon) | Nothing — walk over them. | Host auto-collects within 1.8 m (5 m with Magnet Hands) every 0.12 s → `RunLoot._remove(run, id, collector)`. |
| **Vending cabinet bay / ammo / airdrop** | `GameManager/CrateManager._hold_request(run, key, mode, step, offer_serial)`: `step:"begin"` when you start holding, `"finish"` after ≥ **0.6 s** (host minimum 0.48 s), `"cancel"` if you let go. `key` = cabinet key (`vending_stations[].key`) or `"Airdrop"`; `mode` = `"offer_1"`, `"offer_2"`, `"offer_3"`, `"ammo"`, or `"airdrop"`; `offer_serial` = that bay's offer serial (`offer[3]`), else 0. | You are `ok` within 2.8 m of the pad, clear line of sight from your eye, enough scrap. |

Pickup lifecycle: `RunLoot._spawn(run, id, [pos, item, flavor, claim_peer])`,
`RunLoot._remove(run, id, collector)`, `RunLoot._release(run, id)` (a reserved
drop opens to everyone). Vending: `CrateManager._snapshot`, `_stock(run, key,
offers)`, `_reveal(run, key, id, tier, title)`; airdrops: `_announce_drop(run)`,
`_airdrop_spawn(run, at, descent)`, `_remove_drop(run)`.

Cabinets live at `Main/RunLoot/<key>` on the server, rotated by the marker yaw;
pad offsets in cabinet-local space: `offer_1/2/3` at (−0.62 | 0 | 0.62, 1.25,
−0.58), `ammo` at (−0.68, 0.56, −0.58), airdrop pad at (0, 0.85, 0).

## 9. Enemies and the boss

- `Main/Enemies._spawn_enemy(net_id, kind, at, small, elite, miniboss_wave)`:
  create enemy `net_id` of `kind` (0 Drip, 1 Gutter, 2 Mister, 3 Sleet,
  4 Hailstone, 5 Undertow, 6 Static, 7 Smog, 8 Thunderhead). `small` = a split
  child (Splitters), `elite` = marked elite. The campaign's Cloudburst spawn
  uses `miniboss_wave:3`; ordinary enemies use 0.
- `Main/Enemies._sync_enemies(ids, places, yaws)` at 20 Hz (unreliable-ordered):
  latest position (feet) and yaw per id. Interpolate known enemies and skip
  rows for unknown ids until their spawn arrives.
- `_despawn_enemy(net_id, drops, at, throw_vec, critical)`: death (ragdoll along
  `throw_vec`); `_retire_enemies(ids)`: silent removal (Clearing stragglers).
- Cues: `_play_enemy_tell(net_id, cue, duration, volume)` (attack wind-up),
  `_play_enemy_molt(net_id)`, `_enemy_impacts(rows)` (hit flinch direction),
  `_sync_miniboss_hp(net_id, hp, max_hp)` (boss bar), `_receive_group_warning(at)`
  (a new group is arriving there).
- HUD: `Main/Enemies._sync_progress(wave, left, total, recovery, score)` ≈ 3.6 Hz.
- Wave 5 boss: `GameManager._spawn_boss(at)` creates `Main/Enemies/BossCumulus`;
  `BossCumulus._sync(pos, parts, sacs, burn)` (parts = 3 sac healths + core),
  `BossCumulus._died()`.

## 10. Weather, puddles and lightning

Only **phase changes** cross the network:
`WeatherManager._receive_phase(new_phase, new_wave, time_left)` (0 Calm,
2 Drizzle, 3 Downpour, 4 Clearing). Between them, every frame:

- count `phase_time_left` down to 0 — **except** while a mutation draft holds
  Calm (from `_deal_rpc` until 2.2 s after `_result_rpc`);
- ease `storm_intensity` toward the target at **0.1 per second**: Calm/Clearing
  0.0, Drizzle 0.3, Downpour 0.7 (waves 1–4) or 1.0 (wave ≥ 5); if
  `WeatherManager._override(value)` is ≥ 0, ease toward that instead (−1 = no
  override). `_receive_intensity(value)` (catch-up) sets it directly.
- It is *raining* when intensity > 0.02 and the phase is Drizzle/Downpour (or an
  override > 0.001 is active).

Downpour may run past 0 s until the wave is cleared; wait for the next
`_receive_phase`. Ready-up (`GameManager._request_ready()`) skips Calm/Clearing
when everyone agrees (`GameManager._ready_changed(count, needed)` shows the
tally); the host then sends a `_receive_phase` with 3 s left.

**Puddles** grow locally on every client and are exposure volumes. Use their
`sync_key` values as typed NodePath dictionary keys for catch-up.
`_request_interact` targets interactable nodes such as decon and revive, while
puddle contact uses `_report_exposure`. Each puddle (`puddles[]` in
level-markers.json) has `max_radius`, `grow_time` (45 s) and `dry_time` (25 s).
On the local 0.1 s puddle update: while raining, `growth = min(growth + intensity × rate × dt / grow_time, 1)`
with `rate` 3 on Flood waves (wave 3 and endless Flood waves, see
[game-reference.md](game-reference.md#4-waves)) else 1; otherwise
`growth = max(growth − dt / dry_time, 0)`. Radius = `max_radius × growth`, active
above 0.25 m. The host corrects growth with
`WeatherManager._sync_puddles({NodePath "/root/Main/Level/Puddles/<Name>": growth})`
on join and after bleach-bomb drying. Sandbag walls cap growth (optional detail).

**Lightning:** `WeatherManager._strike(position, strike_seed)` — negative seed:
ambient (flash and thunder only); positive: a tactical strike (Lightning Rod),
which also reveals and shocks enemies. Sound/visual only on the client.

## 11. Calm, mutation draft, pings, pause, endless tape

- **Ready-up** in Calm/Clearing (when > 3 s remain): `GameManager._request_ready()`.
- **Mutation draft** (Calm of wave 2+): `GameManager/MutationRoll._deal_rpc(enemy, dealt)`
  → show `dealt` (three player-mutation ids, names in game-data.json) and the
  forecast enemy mutation `enemy` (may be `""`); vote with
  `GameManager/MutationRoll._request_vote(index)` (0–2, changeable). Tally:
  `_votes_rpc(counts)`. Result: `_result_rpc(pick, enemy_list, player_list, granted)`
  — `player_list` is the squad's full mutation list; apply its effects
  (movement speed, max health, etc.). `_sync_active(enemy_list, player_list)` on
  join; `_clear_rpc()` clears enemy mutations at Clearing; `_reset_run_rpc()` at
  run start. While a draft is open, inventory actions and interaction are
  blocked.
- **Pings:** `Main/Pings._request_ping(kind, pos, enemy_id)` with `kind` one of
  `enemy`, `go`, `revive` (only while downed), `shelter`, `danger`, `crate`,
  `decon`, `ammo`, `health`, `suit`, `supply`, `ammo_box`, `tarp`; max 4/s,
  120 m. Everyone (you included) gets `Main/Pings._show_ping(peer, kind, pos, enemy_id)`.
- **Pause:** `GameManager._request_pause_rpc(paused, who)` → `GameManager._sync_pause(paused, who)`.
- **Endless tape:** after the boss dies the host sends
  `GameManager._sync_tape_state(true, false, true)`. The first roster peer (the
  first key of the roster dictionary) decides with
  `GameManager._request_tape_choice(keep_playing)`: `true` continues into endless
  waves (score in `_sync_progress`), `false` ends the run as a victory.
- `GameManager/Feats._feat_event(id, amount)`, `GameManager._weapon_unlocked(name)`,
  `Main/RunLoot._discover(run, id)`: achievement/unlock feedback; store locally
  if you want, otherwise ignore.

## 12. Late join, results and reset

- **Late join** is the normal path: after `_push_roster` you receive
  `Net._start_run(map)` straight away; load, `_report_in_run(true)`, process the
  catch-up burst (it contains every live enemy, pickups, cabinets, your
  inventory), wait for `_confirm_run_ready`, then request your starter kit.
- **New roster member mid-run:** a `_push_roster` with a new id → create
  `Main/Players/P_<id>` at spawn `index % spawns` (index = position in the
  ascending id list); a removed id → delete that player.
- **Results:** `GameManager._finish(won, results)`. Show results (the native
  client shows its results screen 4.5 s later), unload the level, send
  `Net._report_in_run(false)`, and go back to your lobby UI. Ignore run RPCs that
  still arrive after `_finish` (the server keeps ticking the empty run for 5 s).
  When the player chooses to ready up, send `Net._request_ready(true)`. If
  everyone readies up during results, the next run starts after the server's
  5 s reset. Keep answering RTT probes throughout.

## 13. Implementation order (suggested)

1. Transport + hello/welcome + ping (spec-common).
2. Variant codec for your encoding (JSON tags or `encode_var`), round-trip tested
   against the worked examples in spec-full §10.
3. `Net._hello`, roster, chat, vote, ready (lobby UI).
4. `_start_run` → load map → spawn players → `_report_in_run(true)` → catch-up →
   `_confirm_run_ready`.
5. Starter kit, `_report_exposure`, 20 Hz `_push_transform`, `_rtt_pong`.
6. Render enemies, other players, weather; HUD from `_apply_vitals`,
   `_private_state`, `_sync_progress`.
7. Shooting with `_request_shot`; reload/select; hit markers.
8. Pickups, decon, revive, vending, pouches, tarp, pings, draft, results.

Each step has a matching check in [conformance.md](conformance.md).

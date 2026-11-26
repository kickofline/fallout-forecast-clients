extends Reference
## Owner hotbar, world pickups, projectile effects and supply stations.

const KITS = ["pump_shotgun", "nail_driver", "service_revolver"]
const POUCHES = ["frag", "shield_dome"]
const DAMAGE_SCALE = [1.0, 1.08, 1.16]
const BAYS = ["offer_1", "offer_2", "offer_3"]
const BAY_X = [-0.62, 0.0, 0.62]
const PRICES = [6, 11, 18]
const POOLS = [
	["med_tin", "suit_patch", "frag", "shield_dome", "umbrella", "bleach_bomb", "bait_radio"],
	["pump_shotgun", "spray_rifle", "nail_driver", "rock_salt", "hunting_rifle", "pressure_washer", "battery_zapper", "flare_launcher"],
	["lightning_rod", "harpoon", "leaf_blower", "flare_launcher", "battery_zapper", "boombox_launcher", "leaky_nailgun", "lucky_penny_revolver"]
]
const DROP_GUNS = [
	["pump_shotgun", "nail_driver", "rock_salt", "spray_rifle"],
	["hunting_rifle", "pressure_washer", "battery_zapper", "flare_launcher", "harpoon", "leaf_blower"],
	["leaky_nailgun", "boombox_launcher", "lucky_penny_revolver"]
]
const DROP_SUPPLIES = [
	["ammo_box", "med_tin"],
	["ammo_box", "med_tin", "suit_patch", "frag"],
	["ammo_box", "med_tin", "suit_patch", "frag", "shield_dome"],
	["ammo_box", "ammo_box", "med_tin", "suit_patch", "frag", "shield_dome", "lightning_rod"]
]
const DROP_CURSED = [0.0, 0.1, 0.22, 0.35]
const DROP_LEGENDARY = [0.0, 0.0, 0.1, 0.25]
const MAX_EFFECTS = 24
const SCRAP_CAP = 48

var items = {}
var slots = [[], [], [], [], []]
var stash = {}
var selected = 0
var pouch = ""
var scrap = 0
var pouches = {"frag": 0, "shield_dome": 0}
var pickups = {}
var effects = {}
var discoveries = []
var chosen = false
var stations = {}
var drop = []
var last_drop = Vector3.INF
var cooldown = 0.0

var _next_id = 0
var _next_serial = 0
var _next_offer = 0
var _revision = 1
var _reload = 0.0
var _reload_total = 1.0
var _reload_serial = 0
var _public_reload = false
var _charge_serial = 0
var _charge_at = 0.0
var _jam_until = {}
var _heat = 0.0
var _last_fire = 0.0
var _last_throw = -1.0
var _shots = 0
var _scan_at = 0.0
var _sync_at = 0.0
var _hold = {}
var _caps = {}
var _seeded = {}
var _scrap_count = 0


func setup(run) -> void:
	for item in run.data.items:
		items[item.id] = item
		if item.ammo_type != "":
			_caps[item.ammo_type] = int(item.reserve_cap)
	for marker in run.markers.vending_stations:
		stations[marker.key] = {"pos": marker.pos, "yaw": marker.yaw, "offers": []}
		_restock(run, marker.key, -1, false)


func held_id() -> String:
	if pouch != "":
		return pouch
	return "" if slots[selected].empty() else slots[selected][1]


func held_serial() -> int:
	return 0 if slots[selected].empty() else slots[selected][0]


func send_state(run, public: bool, advance = true) -> void:
	if advance:
		_revision += 1
	if public or _reload > 0.0 or _public_reload:
		_public_reload = _reload > 0.0
		var tier = 0 if pouch != "" or slots[selected].empty() else slots[selected][2]
		run.rpc(run.holder_path, "_equip_state", [run.id, _revision, held_id(), tier, _reload, _reload_total])
	run.rpc(run.holder_path, "_private_state", [run.id, _revision, slots.duplicate(true), stash.duplicate(), selected,
		pouch, scrap, pouches.frag, pouches.shield_dome, _reload, _reload_total,
		max(0.0, _jam_until.get(held_serial(), 0.0) - run.clock), cooldown])


func snapshot(run) -> void:
	var rows = []
	var deployed = []
	for id in pickups:
		rows.append([id, pickups[id].row.duplicate(true)])
	for id in effects:
		deployed.append([id, _effect_row(effects[id])])
	run.rpc(run.LOOT, "_snapshot", [run.id, rows, deployed, discoveries.duplicate(), chosen])


func crate_snapshot(run) -> void:
	var cabinets = {}
	for key in stations:
		cabinets[key] = stations[key].offers.duplicate(true)
	run.rpc(run.CRATES, "_snapshot", [run.id, cabinets, drop.duplicate()])


func request(run, method: String, args: Array) -> void:
	match method:
		"_request_starter":
			_starter(run, int(args[1]))
		"_action":
			_action(run, args[1], int(args[2]), int(args[3]))
		"_request_shot":
			_shot(run, int(args[1]), args[2], args[3], args[4], args[5])
		"_request_throw":
			_throw(run, args[1], args[2], args[3])
		"_claim":
			_claim(run, int(args[1]), int(args[2]), int(args[3]))
		"_hold_request":
			_hold_request(run, args[1], args[2], args[3], int(args[4]))


func step(run, dt: float) -> void:
	cooldown = max(cooldown - dt, 0.0)
	if _reload_serial != 0:
		_reload = max(_reload - dt, 0.0)
		if _reload == 0.0:
			_finish_reload(run)
	if not drop.empty():
		drop[1] = max(0.0, drop[1] - dt)
	if not _hold.empty() and run.clock - _hold.start > 2.5:
		_hold = {}
	if run.clock >= _scan_at:
		_scan_at = run.clock + 0.12
		_scan_pickups(run)
	if not effects.empty():
		_tick_effects(run, dt)


func on_phase(run) -> void:
	if run.phase == run.CALM:
		for key in stations:
			_restock(run, key)
		_drop_remove(run)
		_spawn_drop(run)
	elif run.phase == run.CLEARING:
		_drop_remove(run)


func add_supply(run, at: Vector3, flavor: String, expires = 35.0) -> bool:
	if flavor.begins_with("scrap") and _scrap_count >= SCRAP_CAP:
		return false
	_spawn(run, at, [], flavor, expires)
	return true


func protection(_run, at: Vector3) -> int:
	if effects.empty():
		return 0
	var result = 0
	for seq in effects:
		var effect = effects[seq]
		if not effect.deployed:
			continue
		var to = at - effect.pos
		if effect.id == "shield_dome" and to.length_squared() <= pow(effect.spec.effect_radius, 2):
			return 2
		if effect.id in ["umbrella", "flare_launcher"] and abs(to.y) < 2.7 \
				and to.x * to.x + to.z * to.z <= pow(effect.spec.effect_radius, 2):
			if effect.id == "umbrella":
				return 2
			result = 1
	return result


func lured_target(at: Vector3, fallback: Vector3) -> Vector3:
	for seq in effects:
		var e = effects[seq]
		if e.id in ["bait_radio", "frag"] and e.pos.distance_squared_to(at) < 100.0:
			return e.pos
	return fallback


func _make_item(id: String, tier: int) -> Array:
	var def = items[id]
	_next_serial += 1
	return [_next_serial, id, tier, int(def.weapon.mag_size if def.kind == "gun" else def.spawn_count)]


func _starter(run, index: int) -> void:
	if chosen or index < 0 or index >= KITS.size():
		return
	var item = _make_item(KITS[index], 0)
	var slot = 0
	if not slots[0].empty() and slots[0][1] != "service_revolver":
		slot = _open_slot()
	if slot < 0:
		return
	var def = items[item[1]]
	var cap = def.reserve_cap
	var amount = cap if item[1] == "service_revolver" else min(cap, max(2 * def.weapon.mag_size, int(cap * 0.5)))
	stash[def.ammo_type] = int(max(stash.get(def.ammo_type, 0), amount))
	_seeded[def.ammo_type] = true
	slots[slot] = item
	selected = slot
	pouch = ""
	_cancel_actions()
	chosen = true
	_add_pouch("frag", 2)
	_add_pouch("shield_dome", 1)
	send_state(run, true)
	run.rpc(run.LOOT, "_starter_accepted", [run.id])


func _action(run, action: String, serial: int, slot: int) -> void:
	match action:
		"select":
			if slot >= 0 and slot < slots.size() and (slot != selected or pouch != ""):
				selected = slot
				pouch = ""
				_switch(run, 0.22)
		"select_pouch":
			if slot >= -1 and slot < POUCHES.size():
				var choice = "" if slot == -1 else POUCHES[slot]
				if choice != pouch and (choice == "" or pouches[choice] > 0):
					pouch = choice
					_switch(run, 0.18)
		"swap":
			_swap(run, serial, slot)
		"drop_slot":
			_drop_slot(run, serial, slot)
		_:
			if serial == 0 or serial != held_serial() or pouch != "":
				return
			match action:
				"drop":
					_drop_slot(run, serial, selected)
				"reload":
					_start_reload(run)
				"charge":
					var def = items[held_id()]
					if def.weapon.charge_time > 0.0 and cooldown <= 0.0 and _reload_serial == 0 \
							and slots[selected][3] > 0 and not run.tarp and _charge_serial == 0:
						_charge_serial = serial
						_charge_at = run.clock
						run.rpc(run.holder_path, "_play_charge", [run.id, serial])


func _switch(run, delay: float) -> void:
	_cancel_actions()
	_heat = 0.0
	cooldown = max(cooldown, delay)
	send_state(run, true)


func _cancel_actions() -> void:
	_reload = 0.0
	_reload_serial = 0
	_charge_serial = 0


func _swap(run, expected: int, packed: int) -> void:
	if packed < 0 or packed >= 25:
		return
	var from = int(packed / 5)
	var to = packed % 5
	var moving = slots[from]
	if from == to or moving.empty() or moving[0] != expected:
		return
	var target = slots[to]
	var old = held_serial()
	var count = _stack_room(moving, target)
	if count > 0:
		target[3] += count
		moving[3] -= count
		if moving[3] == 0:
			slots[from] = []
			if selected == from:
				selected = to
	else:
		slots[from] = target
		slots[to] = moving
		if selected == from:
			selected = to
		elif selected == to:
			selected = from
	if old != held_serial():
		_cancel_actions()
	cooldown = max(cooldown, 0.25)
	_heat = 0.0
	send_state(run, true)


func _drop_slot(run, expected: int, slot: int) -> void:
	if slot < 0 or slot >= slots.size() or slots[slot].empty() or slots[slot][0] != expected:
		return
	var at = _ground_near(run, Vector3(-sin(run.yaw), 0, -cos(run.yaw)) * 1.1)
	if at == Vector3.INF:
		at = _ground_near(run, Vector3.ZERO)
	if at == Vector3.INF:
		return
	_spawn(run, at, slots[slot])
	slots[slot] = []
	if slot == selected:
		_cancel_actions()
	send_state(run, true)


func _start_reload(run) -> void:
	if _reload_serial != 0 or run.tarp or slots[selected].empty():
		return
	var item = slots[selected]
	var def = items[item[1]]
	if def.kind != "gun" or item[3] >= def.weapon.mag_size or stash.get(def.ammo_type, 0) <= 0:
		return
	_charge_serial = 0
	_reload_serial = item[0]
	_reload_total = def.weapon.reload_time * (0.65 if run.player_mutations.has("reflex_tendons") else 1.0)
	_reload = _reload_total
	send_state(run, false)


func _finish_reload(run) -> void:
	if not run.can_act() or held_serial() != _reload_serial:
		_cancel_actions()
		send_state(run, false)
		return
	var item = slots[selected]
	var def = items[item[1]]
	var rounds = int(min(1 if def.weapon.shell_reload else def.weapon.mag_size - item[3], stash[def.ammo_type]))
	item[3] += rounds
	stash[def.ammo_type] -= rounds
	_reload_serial = 0
	if def.weapon.shell_reload and item[3] < def.weapon.mag_size and stash[def.ammo_type] > 0:
		_start_reload(run)
	else:
		send_state(run, false)


func _aim_valid(run, origin: Vector3, direction: Vector3) -> bool:
	return direction.length_squared() >= 0.5 and origin.distance_squared_to(run.eye()) <= 9.0 \
		and run.clear_path(run.eye(), origin)


func _shot(run, serial: int, origin: Vector3, direction: Vector3, ads: bool, predicted: bool) -> void:
	if serial == 0 or serial != held_serial() or pouch != "" or run.tarp or cooldown > 0.0 \
			or Vector2(run.vel.x, run.vel.z).length_squared() > 36.0 or not _aim_valid(run, origin, direction):
		return
	var item = slots[selected]
	var id = item[1]
	var def = items[id]
	var weapon = def.weapon
	if item[3] <= 0 or run.clock < _jam_until.get(serial, 0.0) or (_reload_serial != 0 and not weapon.shell_reload):
		return
	if weapon.charge_time > 0.0:
		var charged = _charge_serial == serial and run.clock - _charge_at >= weapon.charge_time
		_charge_serial = 0
		if not charged:
			return
	direction = direction.normalized()
	var fire_kind = weapon.fire_kind
	var at = Vector3.INF
	if fire_kind == "place":
		var flat = Vector3(direction.x, 0, direction.z).normalized()
		at = _ground_near(run, flat * 2.0)
		if at == Vector3.INF or not _effects_room(run):
			return
	elif fire_kind == "use":
		if (id == "med_tin" and run.hp >= run.max_hp) or (id == "suit_patch" and run.suit >= 100.0):
			return
	elif fire_kind != "hitscan" and not _effects_room(run):
		return
	_cancel_actions()
	item[3] -= 1
	cooldown = weapon.fire_interval * (0.8 if run.player_mutations.has("reflex_tendons") else 1.0)
	if weapon.jam_chance > 0.0 and run.rng.randf() < weapon.jam_chance:
		_jam_until[serial] = run.clock + 2.0
		run.rpc(run.holder_path, "_jam", [run.id])
		send_state(run, false)
		return
	var damage = weapon.damage * DAMAGE_SCALE[item[2]]
	var traces = []
	match fire_kind:
		"hitscan":
			_heat = move_toward(_heat, 0.0, (run.clock - _last_fire) * 1.6)
			_last_fire = run.clock
			_shots += 1
			var focus = run.player_mutations.has("hyper_focus")
			var spread = (weapon.spread_degrees + weapon.burst_spread * _heat) * ((0.25 if focus else 0.45) if ads else 1.0)
			_heat = min(1.0, _heat + 0.22)
			var voltaic = run.player_mutations.has("voltaic_veins") and _shots % 4 == 0
			traces = run.arena.shoot(run, id, origin, direction, weapon, spread, damage * (1.25 if ads and focus else 1.0), voltaic)
		"use":
			if id == "med_tin":
				run.heal(weapon.damage)
			else:
				run.suit = min(100.0, run.suit + weapon.damage)
		"place":
			_launch(run, id, at, direction, item[2], true)
		_:
			_launch(run, id, _throw_origin(run, origin, direction), direction, item[2], false)
	run.rpc(run.holder_path, "_shot_fx", [run.id, id, origin, direction, traces, ads, predicted], false)
	var emptied = item[3] == 0 and def.ammo_type == ""
	if emptied:
		slots[selected] = []
	send_state(run, emptied)


func _throw(run, id: String, origin: Vector3, direction: Vector3) -> void:
	if id == "" or id != pouch or not pouches.has(id) or pouches[id] <= 0 or run.tarp \
			or run.clock - _last_throw < 0.21 or not _aim_valid(run, origin, direction) or not _effects_room(run):
		return
	_last_throw = run.clock
	pouches[id] -= 1
	direction = direction.normalized()
	_launch(run, id, _throw_origin(run, origin, direction), direction, 0, false)
	run.rpc(run.holder_path, "_throw_fx", [run.id, id, origin, direction, true], false)
	var emptied = pouches[id] == 0
	if emptied:
		pouch = ""
	send_state(run, emptied)


func _throw_origin(run, origin: Vector3, direction: Vector3) -> Vector3:
	var ahead = origin + direction * 0.45
	return ahead if run.clear_path(origin, ahead) else origin


func _add_pouch(id: String, amount: int) -> int:
	var added = int(min(amount, int(items[id].pouch_cap) - pouches[id]))
	pouches[id] += added
	return added


func _spawn(run, at: Vector3, item: Array, flavor = "", expires = 0.0, claim_peer = 0) -> void:
	_next_id += 1
	var row = [at, item.duplicate(), flavor, claim_peer]
	pickups[_next_id] = {"row": row, "expires": run.clock + expires if expires > 0.0 else INF,
		"ready": run.clock + 0.3, "release": run.clock + 7.0}
	if flavor.begins_with("scrap"):
		_scrap_count += 1
	run.rpc(run.LOOT, "_spawn", [run.id, _next_id, row.duplicate(true)])


func _remove(run, id: int, collector: int) -> void:
	if pickups[id].row[2].begins_with("scrap"):
		_scrap_count -= 1
	pickups.erase(id)
	run.rpc(run.LOOT, "_remove", [run.id, id, collector])


func _scan_pickups(run) -> void:
	for id in pickups.keys():
		var record = pickups[id]
		if run.clock >= record.expires:
			_remove(run, id, 0)
			continue
		var row = record.row
		if row[3] != 0 and run.clock >= record.release:
			row[3] = 0
			run.rpc(run.LOOT, "_release", [run.id, id])
		if row[1].empty() and run.clock >= record.ready and run.state == "ok":
			var reach = 5.0 if run.player_mutations.has("magnet_hands") else 1.8
			if run.pos.distance_squared_to(row[0]) <= reach * reach \
					and run.clear_path(run.eye(), row[0] + Vector3.UP * 0.28) and _collect(run, row[2]):
				_remove(run, id, run.peer)


func _collect(run, flavor: String) -> bool:
	if flavor.begins_with("scrap"):
		var amount = 15 if flavor == "scrap_large" else 5
		if run.player_mutations.has("magnet_hands"):
			amount = int(round(amount * 1.25))
		scrap += amount
		send_state(run, false)
		run.rpc(run.holder_path, "_scrap_feedback", [run.id, amount])
		return true
	var collected = false
	if flavor in ["ammo", "supply", "ammo_box"] and _collect_ammo(run, flavor == "ammo_box"):
		send_state(run, false)
		collected = true
	if flavor in ["health", "supply"] and run.hp < run.max_hp:
		run.heal(20.0)
		collected = true
	if flavor in ["suit", "supply"] and run.suit < 100.0:
		run.suit = min(100.0, run.suit + 25.0)
		collected = true
	if flavor == "tarp" and not run.has_tarp:
		run.has_tarp = true
		run.rpc(run.player_path, "_grant_tarp", [])
		collected = true
	if flavor == "decon" and run.decon < 4:
		run.decon += 1
		run.rpc(run.GAME, "_sync_decon", [run.decon])
		collected = true
	return collected


func _collect_ammo(run, full: bool) -> bool:
	var types = {}
	for item in slots:
		if not item.empty():
			var def = items[item[1]]
			if def.ammo_type != "":
				types[def.ammo_type] = max(types.get(def.ammo_type, 0), def.weapon.mag_size)
	var collected = false
	for key in types:
		var old = stash.get(key, 0)
		var amount = max(1, round(types[key] * (0.6 if run.player_mutations.has("magnet_hands") else 0.4)))
		var total = _caps[key] if full else min(old + amount, _caps[key])
		if total > old:
			stash[key] = int(total)
			collected = true
	return collected


func _claim(run, id: int, expected: int, slot: int) -> void:
	if not pickups.has(id) or slot != selected or expected != held_serial():
		return
	var row = pickups[id].row
	var at = row[0]
	if row[1].empty() or (row[3] != 0 and row[3] != run.peer) or run.pos.distance_squared_to(at) > 2.55 * 2.55 \
			or not run.clear_path(run.eye(), at + Vector3.UP * 0.28):
		return
	var item = row[1]
	var original_count = item[3]
	var remainder = _accept(run, item)
	if remainder == item and remainder[3] == original_count:
		if pouches.has(item[1]):
			run.rpc(run.holder_path, "_pouch_full_feedback", [run.id, item[1]])
		return
	_remove(run, id, run.peer)
	if not remainder.empty():
		_spawn(run, at, remainder)
	_discover(run, item[1])
	send_state(run, true)


func _open_slot() -> int:
	for i in range(slots.size()):
		if slots[i].empty():
			return i
	return -1


func _stack_room(moving: Array, target: Array) -> int:
	if target.empty() or target[1] != moving[1] or target[2] != moving[2] or items[moving[1]].kind == "gun":
		return 0
	return int(clamp(items[moving[1]].stack_cap - target[3], 0, moving[3]))


func _accept(run, item: Array) -> Array:
	var id = item[1]
	if pouches.has(id):
		item[3] -= _add_pouch(id, item[3])
		return item if item[3] > 0 else []
	for other in slots:
		var count = _stack_room(item, other)
		if count > 0:
			other[3] += count
			item[3] -= count
			if item[3] == 0:
				return []
	var slot = selected if slots[selected].empty() else _open_slot()
	if slot < 0:
		slot = selected
	var remainder = slots[slot]
	slots[slot] = item
	if slot == selected:
		pouch = ""
		_cancel_actions()
	var def = items[id]
	if def.ammo_type != "" and not _seeded.has(def.ammo_type):
		_seeded[def.ammo_type] = true
		stash[def.ammo_type] = int(min(def.reserve_cap, max(def.weapon.mag_size * 2, int(def.reserve_cap * 0.5))))
	if def.cursed:
		run.cursed += 1
	return remainder


func _discover(run, id: String) -> void:
	var def = items[id]
	if def.kind == "gun" and not def.cursed and id != "disruptor" and not discoveries.has(id):
		discoveries.append(id)
		run.rpc(run.LOOT, "_discover", [run.id, id])
		run.rpc(run.GAME, "_weapon_unlocked", [def.name.to_upper()])


func _ground_near(run, offset: Vector3) -> Vector3:
	var from = run.pos + Vector3.UP * 0.65
	var want = from + offset
	if not run.clear_path(from, want):
		return Vector3.INF
	var hit = run.ray(want, want - Vector3.UP * 3.0)
	return Vector3.INF if hit.empty() else hit.position + Vector3.UP * 0.06


func _restock(run, key: String, sold = -1, announce = true) -> void:
	var offers = stations[key].offers.duplicate()
	offers.resize(3)
	for bay in range(BAYS.size()):
		if sold >= 0 and bay != sold:
			continue
		var pool = POOLS[bay].duplicate()
		if run.wave <= 2:
			pool.resize([5, 6, 5][bay])
		if offers[bay] != null:
			pool.erase(offers[bay][0])
		var id = pool[run.rng.randi_range(0, pool.size() - 1)]
		if bay == 2 and run.wave >= 4 and run.rng.randf() < 0.05:
			id = "disruptor"
		var tier = 0
		if (bay == 2 and run.wave >= 2) or (bay == 1 and run.wave >= 4):
			tier = 2
		elif bay == 2 or (bay == 1 and run.wave >= 2):
			tier = 1
		_next_offer += 1
		offers[bay] = [id, tier, 10 if run.wave == 2 and bay == 1 else PRICES[bay], _next_offer]
	stations[key].offers = offers
	if announce:
		run.rpc(run.CRATES, "_stock", [run.id, key, offers.duplicate(true)])


func _spawn_drop(run) -> void:
	var pool = run.markers.crate_spawn
	if pool.empty():
		return
	var point = Vector3.INF
	var best = INF
	for marker in pool:
		var distance = run.pos.distance_to(marker.pos)
		var penalty = abs(distance - 15.0) + run.rng.randf_range(0.0, 5.0)
		if penalty < best:
			point = marker.pos
			best = penalty
	last_drop = point
	drop = [point, 2.4]
	run.rpc(run.CRATES, "_announce_drop", [run.id])
	run.rpc(run.CRATES, "_airdrop_spawn", [run.id, point, 2.4])
	var grade = int(clamp(run.wave - 2, 0, 3))
	var label = ["SURPLUS", "TUNED", "OVERCLOCKED", "APEX"][grade]
	var tint = [Color("#ffc365"), Color("#66dfda"), Color("#ffc365"), Color("#ff884d")][grade]
	run.rpc(run.GAME, "_banner", [label + " SUPPLY DROP INBOUND", tint, 3.2])


func _drop_remove(run) -> void:
	if not drop.empty():
		drop = []
		run.rpc(run.CRATES, "_remove_drop", [run.id])


func _hold_request(run, key: String, mode: String, step: String, serial: int) -> void:
	if step == "cancel":
		_hold = {}
		return
	var offer = []
	var pad = Vector3.INF
	var bay = BAYS.find(mode)
	if key == "Airdrop" and mode == "airdrop" and not drop.empty() and drop[1] == 0.0:
		pad = drop[0] + Vector3.UP * 0.85
	elif stations.has(key) and (bay >= 0 or mode == "ammo"):
		var cabinet = stations[key]
		var offset = Vector3(-0.68, 0.56, -0.58)
		if bay >= 0:
			offer = cabinet.offers[bay]
			offset = Vector3(BAY_X[bay], 1.25, -0.58)
		pad = cabinet.pos + offset.rotated(Vector3.UP, cabinet.yaw)
	if pad == Vector3.INF or run.pos.distance_squared_to(pad) > 2.8 * 2.8 or not run.clear_path(run.eye(), pad) \
			or (not offer.empty() and offer[3] != serial):
		_hold = {}
		return
	if step == "begin":
		_hold = {"key": key, "mode": mode, "serial": serial, "start": run.clock}
		return
	if step != "finish":
		return
	var hold = _hold
	_hold = {}
	if hold.empty() or hold.key != key or hold.mode != mode or hold.serial != serial \
			or run.clock - hold.start < 0.48 or run.clock - hold.start > 2.5:
		return
	if mode == "airdrop":
		_open_drop(run)
	elif mode == "ammo":
		if scrap >= 5 and _collect_ammo(run, true):
			scrap -= 5
			send_state(run, false)
			run.rpc(run.CRATES, "_reveal", [run.id, key, "ammo_box", 0, "AMMO REFILLED"])
	elif scrap >= offer[2]:
		var item = _make_item(offer[0], offer[1])
		var original_count = item[3]
		var remainder = _accept(run, item)
		if remainder == item and remainder[3] == original_count:
			return
		if not remainder.empty():
			var at = _ground_near(run, Vector3.ZERO)
			_spawn(run, run.pos if at == Vector3.INF else at, remainder)
		scrap -= offer[2]
		_discover(run, offer[0])
		send_state(run, true)
		run.rpc(run.CRATES, "_reveal", [run.id, key, offer[0], offer[1], "DISPENSED"])
		_restock(run, key, bay)


func _open_drop(run) -> void:
	var point = drop[0]
	var grade = int(clamp(run.wave - 2, 0, 3))
	var tier = int(min(grade, 2))
	var weapons = 1 if grade < 3 else 2
	var supplies = DROP_SUPPLIES[grade]
	var count = weapons + supplies.size()
	for i in range(count):
		var offset = Vector3(2.25, 0, 0).rotated(Vector3.UP, TAU * i / count)
		var spot = point + offset
		if not run.clear_path(point + Vector3.UP * 0.7, spot + Vector3.UP * 0.7):
			spot = point
		spot = run.ground(spot, 0.7)
		if i < weapons:
			var roll = run.rng.randf()
			var pool = DROP_GUNS[0 if grade == 0 else 1]
			if roll < DROP_LEGENDARY[grade] + DROP_CURSED[grade]:
				pool = DROP_GUNS[2]
			var id = "disruptor" if roll < DROP_LEGENDARY[grade] else pool[run.rng.randi_range(0, pool.size() - 1)]
			_spawn(run, spot, _make_item(id, tier))
		else:
			var id = supplies[i - weapons]
			if id == "ammo_box":
				add_supply(run, spot, id, 0.0)
			else:
				_spawn(run, spot, _make_item(id, 0))
	_drop_remove(run)


func _effects_room(run) -> bool:
	if effects.size() < MAX_EFFECTS:
		return true
	_end_effect(run, effects.keys()[0], false)
	return true


func _launch(run, id: String, at: Vector3, direction: Vector3, tier: int, deployed: bool) -> void:
	var spec = items[id].weapon
	var kind = spec.fire_kind
	var life = spec.effect_time if deployed else (spec.fuse if kind == "grenade" else 5.0)
	var motion = Vector3.ZERO if deployed else direction * spec.projectile_speed
	if not deployed and kind == "grenade":
		motion.y += 2.5
	_next_id += 1
	var effect = {"id": id, "spec": spec, "pos": at, "vel": motion, "tier": tier, "deployed": deployed,
		"life": life, "yaw": atan2(-direction.x, -direction.z), "pulse": run.clock, "body": null}
	effects[_next_id] = effect
	run.rpc(run.LOOT, "_effect_spawn", [run.id, _next_id, _effect_row(effect)])
	if deployed:
		_deploy(run, _next_id, effect)


func _effect_row(effect: Dictionary) -> Array:
	return [effect.id, effect.pos, effect.vel, effect.tier, effect.deployed, effect.life, effect.yaw]


func _deploy(run, seq: int, effect: Dictionary) -> void:
	effect.vel = Vector3.ZERO
	effect.deployed = true
	effect.life = effect.spec.effect_time
	if effect.id == "sandbag":
		var body = StaticBody.new()
		body.name = "SoloSandbag"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape = CollisionShape.new()
		shape.shape = BoxShape.new()
		shape.shape.extents = Vector3(0.925, 0.375, 0.4)
		body.add_child(shape)
		run.level.add_child(body, true)
		body.global_transform = Transform(Basis(Vector3.UP, effect.yaw), effect.pos + Vector3.UP * 0.375)
		effect.body = body
	run.rpc(run.LOOT, "_effect_deploy", [run.id, seq, effect.pos, effect.life, effect.yaw])


func detach() -> void:
	for seq in effects:
		var body = effects[seq].body
		if is_instance_valid(body):
			body.queue_free()
	effects.clear()


func _tick_effects(run, dt: float) -> void:
	var flight = []
	var sync = run.clock >= _sync_at
	if sync:
		_sync_at = run.clock + 0.1
	for seq in effects.keys():
		var e = effects[seq]
		var spec = e.spec
		e.life -= dt
		if e.deployed:
			if e.life <= 0.0:
				if e.id == "lightning_rod":
					run.arena.tactical_lightning(run, e.pos, spec.effect_radius, spec.damage)
				_end_effect(run, seq, false)
				continue
			if run.clock >= e.pulse and e.id in ["flare_launcher", "bleach_bomb", "umbrella", "shield_dome"]:
				e.pulse = run.clock + 0.25
				_zone_pulse(run, e)
			continue
		e.vel.y -= 9.8 * spec.projectile_gravity * dt
		var next = e.pos + e.vel * dt
		var hit = run.ray(e.pos, next)
		if spec.fire_kind == "rocket" or e.id == "flare_launcher":
			var contact = run.arena.projectile_contact(e.pos, hit.get("position", next))
			if contact != Vector3.INF:
				e.pos = contact
				if e.id == "flare_launcher":
					run.arena.blast(run, contact, 1.4, spec.damage * DAMAGE_SCALE[e.tier], 0.0, false)
					_deploy(run, seq, e)
				else:
					_explode(run, seq, e)
				continue
		if not hit.empty():
			e.pos = hit.position + hit.normal * 0.06
			match spec.fire_kind:
				"grenade":
					e.vel = e.vel.bounce(hit.normal) * 0.43 if e.vel.length_squared() > 1.0 else Vector3.ZERO
				"flare":
					_deploy(run, seq, e)
					continue
				_:
					_explode(run, seq, e)
					continue
		else:
			e.pos = next
		if e.life <= 0.0:
			if e.id in ["bait_radio", "bleach_bomb"]:
				_deploy(run, seq, e)
			elif spec.fire_kind in ["grenade", "rocket"]:
				_explode(run, seq, e)
			else:
				_end_effect(run, seq, false)
		elif sync:
			flight.append([seq, e.pos, e.vel])
	if not flight.empty():
		run.rpc(run.LOOT, "_flight", [run.id, flight], false)


func _explode(run, seq: int, e: Dictionary) -> void:
	var radius = e.spec.effect_radius * (1.3 if run.player_mutations.has("blast_glands") else 1.0)
	var damage = e.spec.damage * DAMAGE_SCALE[e.tier] * (1.3 if run.player_mutations.has("blast_glands") else 1.0)
	run.dry_puddles(e.pos, radius)
	run.arena.blast(run, e.pos, radius, damage, e.spec.knockback, true)
	if run.pos.distance_squared_to(e.pos) < radius * radius and run.clear_path(e.pos, run.eye()):
		var falloff = 1.0 - 0.6 * run.pos.distance_to(e.pos) / radius
		run.damage(damage * falloff, e.pos)
	_end_effect(run, seq, true)


func _zone_pulse(run, effect: Dictionary) -> void:
	var radius = effect.spec.effect_radius
	var delta = run.pos - effect.pos
	match effect.id:
		"flare_launcher":
			run.arena.flare(run, effect.pos, radius, DAMAGE_SCALE[effect.tier])
		"bleach_bomb":
			run.arena.clear_clouds(run, effect.pos, radius)
			if delta.length_squared() <= radius * radius:
				run.suit = min(100.0, run.suit + 2.6)
			run.arena.blast(run, effect.pos, radius, effect.spec.damage * 0.25, 0.0, false)
		"umbrella":
			if abs(delta.y) < 2.7 and delta.x * delta.x + delta.z * delta.z <= radius * radius:
				run.suit = min(100.0, run.suit + 0.625)
		"shield_dome":
			run.arena.repel(run, effect.pos, radius)


func _end_effect(run, seq: int, blast: bool) -> void:
	var e = effects[seq]
	if is_instance_valid(e.body):
		e.body.queue_free()
	effects.erase(seq)
	run.rpc(run.LOOT, "_effect_end", [run.id, seq, e.pos, blast])



func has_scrap_room(pending: int) -> bool:
	return _scrap_count + pending < SCRAP_CAP

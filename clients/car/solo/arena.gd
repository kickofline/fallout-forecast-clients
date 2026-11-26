extends Reference
## Finite wave director and kinematic enemy simulation on level geometry.

const DRIP = 0
const GUTTER = 1
const MISTER = 2
const SLEET = 3
const HAILSTONE = 4
const UNDERTOW = 5
const STATIC = 6
const SMOG = 7
const THUNDERHEAD = 8
const SPECIAL = {"BLACKOUT": STATIC, "SWARM": SLEET, "HEAVY WEATHER": THUNDERHEAD}
const CUES = ["drip_windup", "gutter_windup", "mister_windup", "sleet_leap", "hailstone_charge",
	"undertow_emerge", "static_shock", "smog_spit", "thunderhead_fuse"]
const WINDUP = [0.45, 0.44, 0.45, 0.35, 0.9, 0.45, 0.57, 0.65, 1.72]
const CRIT_HEIGHT = [1.42, 1.16, 1.63, 0.95, 1.68, 1.25, 1.32, 1.63, 1.55]
const BODY_RADIUS = [0.44, 0.45, 0.49, 0.34, 0.65, 0.45, 0.43, 0.53, 0.55]
const THINK_TIME = 0.1
const BOSS_MAX = [540.0, 540.0, 540.0, 1400.0]

var enemies = []
var _kinds = []
var _next_enemy = 0
var _next_hazard = 0
var _spawned = 0
var _extras = 0
var _budget = 26
var _arrive_at = 2.1
var _opening = true
var _group = []
var _group_pos = Vector3.ZERO
var _warn_group = false
var _ambush = false
var _miniboss = false
var _clean_at = INF
var _progress_at = 0.0
var _sync_at = 0.0
var _nav_budget = 0
var _hazards = []
var _hazard_at = 0.0
var _pending_pops = []
var _boss = {}


func setup(run) -> void:
	_kinds = run.data.enemy_kinds


func catch_up(run) -> void:
	for enemy in enemies:
		_spawn_packet(run, enemy)
	_progress(run)
	if boss_alive():
		run.rpc(run.GAME, "_spawn_boss", [_boss.pos])


func on_phase(run) -> void:
	_group.clear()
	_opening = true
	match run.phase:
		run.CALM:
			_spawned = 0
			_extras = 0
			_ambush = false
			_miniboss = false
		run.CLEARING:
			retire(run)
	_budget = _budget_for(run)
	_clean_at = INF
	_arrive_at = run.clock + (1.25 if run.phase == run.DRIZZLE else 2.1)
	_progress_at = run.clock


func step(run, dt: float) -> void:
	_nav_budget = 1
	_tick_director(run)
	var i = enemies.size() - 1
	while i >= 0 and not run.finished:
		var enemy = enemies[i]
		if run.clock >= enemy.think_at:
			_think(run, enemy)
		enemy.pos = enemy.pos.move_toward(enemy.goal, enemy.motion * dt)
		i = min(i - 1, enemies.size() - 1)
	if run.finished:
		return
	_tick_hazards(run)
	if boss_alive():
		_tick_boss(run, dt)
	if not _pending_pops.empty():
		var pop = _pending_pops.pop_front()
		blast(run, pop, 4.94, 45.5, 6.0, true)
		run.rpc(run.GAME, "_draw_blast", [pop + Vector3.UP * 0.6, 1.73, Color("#ff8838")], false)
	if run.clock + 0.00001 >= _sync_at:
		_sync_at = run.clock + 0.05
		if not enemies.empty():
			_sync(run)
	if run.clock >= _progress_at:
		_progress(run)


func wave_complete(wave: int) -> bool:
	if _spawned < _budget or (wave == 3 and not _miniboss) or (not enemies.empty() and _clean_at != 0.0):
		return false
	for e in enemies:
		if e.elite or e.miniboss > 0:
			return false
	return true


func retire(run) -> void:
	if not enemies.empty():
		var ids = PoolIntArray()
		for enemy in enemies:
			ids.append(enemy.id)
		enemies.clear()
		run.rpc(run.ENEMIES, "_retire_enemies", [ids])


func boss_alive() -> bool:
	return not _boss.empty()


func queue_pop(at: Vector3) -> void:
	if _pending_pops.size() < 8:
		_pending_pops.append(at)


func _budget_for(run) -> int:
	var budget = 18 + 8 * int(min(run.wave, 5)) + 6 * int(clamp(run.wave - 5, 0, 6))
	return budget * (2 if run.enemy_mutations.has("swarm") else 1)


func _tick_director(run) -> void:
	if run.locked or not (run.phase == run.DRIZZLE or run.phase == run.DOWNPOUR):
		return
	var downpour = run.phase == run.DOWNPOUR
	if _group.empty():
		_budget = int(max(_spawned, _budget_for(run)))
	var limit = _budget if downpour else int(ceil(_budget * 0.35))
	if run.clock >= _arrive_at and _spawned < limit and enemies.size() < run.alive_cap:
		if _group.empty():
			_plan_group(run, limit - _spawned, downpour)
		var kind = _group.pop_front()
		if _warn_group and kind == GUTTER:
			_group_pos = _marker(run, "drain_spawn")
		var at = _group_pos + Vector3(run.rng.randf_range(-1.8, 1.8), 0, run.rng.randf_range(-1.8, 1.8))
		var puddle = _wet_spawn(run) if kind == UNDERTOW else Vector3.INF
		if puddle != Vector3.INF:
			at = puddle
		var e = _spawn(run, kind, at)
		if puddle != Vector3.INF:
			e.submerged_at = run.clock + 10.0
			_tell(run, e, "undertow_lurk", 0.0, -15.0)
		_spawned += 1
		if _warn_group:
			_warn_group = false
			run.rpc(run.ENEMIES, "_receive_group_warning", [e.pos])
		var rest = max(2.7, 5.0 - (run.wave - 1) * 0.25) if downpour else 7.5
		_arrive_at = run.clock + (rest + (1.6 if enemies.size() > 7 else 0.0) if _group.empty() else 0.28)
	if not _ambush and run.wave == 2 and _spawned >= 2 and run.loot.last_drop != Vector3.INF \
			and (run.loot.drop.empty() or run.loot.drop[1] <= 0.0) and enemies.size() < run.alive_cap:
		_ambush = true
		var point = _marker(run, "drain_spawn", run.loot.last_drop)
		run.rpc(run.GAME, "_banner", ["GUTTER AMBUSH", Color("#ffc365"), 2.0])
		run.rpc(run.ENEMIES, "_receive_group_warning", [point])
		for _n in range(min(4, run.alive_cap - enemies.size())):
			_spawn(run, GUTTER, point + Vector3(run.rng.randf_range(-2.0, 2.0), 0, run.rng.randf_range(-2.0, 2.0)))
			_extras += 1
	if downpour and run.wave > 5 and not _ambush and run.forecast == "HEAVY WEATHER" \
			and _spawned >= int(ceil(_budget * 0.5)) and enemies.size() < run.alive_cap:
		_ambush = true
		var e = _spawn(run, THUNDERHEAD, _marker(run, "enemy_spawn"))
		_extras += 1
		run.rpc(run.ENEMIES, "_receive_group_warning", [e.pos])
	if downpour and run.wave == 3 and not _miniboss and _spawned >= int(ceil(_budget * 0.5)) and enemies.size() < run.alive_cap:
		_miniboss = true
		var e = _spawn(run, MISTER, _marker(run, "enemy_spawn"), false, false, 3)
		_extras += 1
		run.rpc(run.ENEMIES, "_receive_group_warning", [e.pos])
		run.rpc(run.GAME, "_banner", ["CLOUDBURST", Color("#ff5689"), 3.2])
	if _spawned >= _budget and enemies.size() <= 3 and (run.wave != 3 or _miniboss):
		if _clean_at == INF:
			_clean_at = run.clock + 5.0
		elif _clean_at <= run.clock:
			_clean_at = 0.0
	else:
		_clean_at = INF


func _plan_group(run, slots: int, downpour: bool) -> void:
	_group_pos = _marker(run, "enemy_spawn")
	_warn_group = true
	var flood = run.forecast == "FLOOD"
	var special = SPECIAL.get(run.forecast, -1)
	if _opening:
		_opening = false
		_group = [DRIP, UNDERTOW if flood else GUTTER, DRIP]
		if run.wave >= 2:
			if downpour:
				_group.insert(1, HAILSTONE)
				if special >= 0:
					_group.append(special)
			_group.append(MISTER)
		_group.resize(min(slots, _group.size()))
		return
	var mix = [11 if run.forecast == "SWARM" else 8, 0 if flood else 3, 2 if run.wave >= 2 else 0,
		0, 0, 3 if flood else 0, 0, 0, 0]
	if run.wave >= 2 and downpour:
		mix[HAILSTONE] = 2 if run.wave == 2 else 3
	elif run.wave >= 3:
		mix[HAILSTONE] = 1
	if special >= 0:
		mix[special] = 2 if downpour else 1
	if run.wave >= 4 and downpour:
		mix[SMOG] = 1
	var specials = 0
	var count = min(slots, clamp(4 + run.wave, 5, 12))
	for _i in range(count):
		var total = 0
		for weight in mix:
			total += weight
		var roll = run.rng.randi_range(0, total - 1)
		for kind in range(mix.size()):
			roll -= mix[kind]
			if roll < 0:
				_group.append(kind)
				if kind >= SLEET:
					specials += 1
					mix[kind] = 0
					if specials == 2:
						for index in range(SLEET, mix.size()):
							mix[index] = 0
				break


func _marker(run, group: String, near = Vector3.INF) -> Vector3:
	var candidates = run.markers[group]
	var best = INF
	var result = candidates[0].pos
	var fallback_distance = -1.0
	for marker in candidates:
		var point = marker.pos
		var distance = run.pos.distance_to(point)
		if distance < 12.0:
			if best == INF and distance > fallback_distance:
				result = point
				fallback_distance = distance
			continue
		var penalty = abs(distance - 30.0) + run.rng.randf_range(0.0, 22.0)
		if near != Vector3.INF:
			penalty = near.distance_to(point)
		if penalty < best:
			best = penalty
			result = point
	return result


func _wet_spawn(run) -> Vector3:
	var best = 45.0 * 45.0
	var result = Vector3.INF
	for marker in run.markers.puddles:
		var distance = marker.pos.distance_squared_to(run.pos)
		if distance < best and distance > 7.5 * 7.5 and run.puddles[NodePath(marker.sync_key)] * marker.max_radius > 0.25:
			result = marker.pos
			best = distance
	return result


func _spawn(run, kind: int, at: Vector3, small = false, elite = false, mini = 0) -> Dictionary:
	_next_enemy += 1
	var scale = 2.5 if mini > 0 else (0.6 if small else (1.35 if elite else 1.0))
	var multiplier = 7.2 if mini > 0 else (0.3 if small else (2.2 if elite else 1.0))
	var escalation = 1.0 + clamp(run.wave - 5.0, 0.0, 10.0) * 0.08
	var spec = _kinds[kind]
	var hp = spec.max_health * multiplier * escalation * (0.5 if run.enemy_mutations.has("swarm") else 1.0)
	var point = run.ground(at, 0.45, 3.0)
	var enemy = {"id": _next_enemy, "kind": kind, "pos": point, "yaw": 0.0, "hp": hp, "max_hp": hp,
		"small": small, "elite": elite, "miniboss": mini, "scale": scale, "spec": spec, "goal": point, "motion": 0.0,
		"think_at": run.clock + 0.03 + float(_next_enemy % 6) / 60.0, "attack_at": run.clock + 0.6,
		"wind_at": INF, "recover": 0.0, "stagger": 0.0, "slow": 0.0, "dash": 0.0, "dash_dir": Vector3.ZERO,
		"dash_hit": false, "push": Vector3.ZERO, "path": PoolVector3Array(), "path_i": 0, "nav_at": 0.0,
		"wall_until": 0.0, "wall_side": 1.0 if _next_enemy % 2 == 0 else -1.0, "submerged_at": 0.0,
		"blink_at": run.clock + 4.0, "powered": 0.0, "crash_at": -10.0}
	enemies.append(enemy)
	_spawn_packet(run, enemy)
	if mini > 0:
		_miniboss_hp(run, enemy)
	return enemy


func _spawn_packet(run, e: Dictionary) -> void:
	run.rpc(run.ENEMIES, "_spawn_enemy", [e.id, e.kind, e.pos, e.small, e.elite, e.miniboss])


func _sync(run) -> void:
	var ids = PoolIntArray()
	var positions = PoolVector3Array()
	var yaws = PoolRealArray()
	ids.resize(enemies.size())
	positions.resize(enemies.size())
	yaws.resize(enemies.size())
	for i in range(enemies.size()):
		var e = enemies[i]
		ids[i] = e.id
		positions[i] = e.pos
		yaws[i] = e.yaw
	run.rpc(run.ENEMIES, "_sync_enemies", [ids, positions, yaws], false)


func _progress(run) -> void:
	_progress_at = run.clock + 0.28
	var pending = int(run.wave == 3 and not _miniboss)
	var left = 0 if run.phase == run.CLEARING or run.locked else _budget - _spawned + enemies.size() + pending
	var recovery = max(_arrive_at - run.clock, 0.0) if left > 0 else 0.0
	run.rpc(run.ENEMIES, "_sync_progress", [run.wave, left, _budget + _extras + pending, recovery, run.score], false)


func _miniboss_hp(run, enemy: Dictionary) -> void:
	run.rpc(run.ENEMIES, "_sync_miniboss_hp", [enemy.id, enemy.hp, enemy.max_hp], false)


func _think(run, e: Dictionary) -> void:
	var elapsed = min(0.18, THINK_TIME + max(0.0, run.clock - e.think_at))
	e.think_at += THINK_TIME
	if e.think_at <= run.clock:
		e.think_at = run.clock + THINK_TIME
	var kind = e.kind
	var to = run.pos - e.pos
	var distance = to.length()
	var aim = _flat(to).normalized()
	var range_at = (6.0 if kind == GUTTER else e.spec.attack_range) * (1.2 if e.miniboss > 0 else 1.0)
	if e.submerged_at > 0.0:
		if distance < 4.0 or run.clock >= e.submerged_at or _spawned >= _budget:
			e.submerged_at = 0.0
			e.recover = run.clock + 0.6
			_tell(run, e, "undertow_emerge", 0.6, -8.0)
		return
	var hero = run.state == "ok" or run.state == "downed"
	var facing = aim
	var motion = Vector3.ZERO
	var velocity = e.spec.move_speed * run.enemy_buff() * (1.0 + clamp((run.wave - 5) * 0.025, 0.0, 0.42))
	if run.clock < e.slow:
		velocity *= 0.58
	if run.clock < e.powered:
		velocity *= 1.33
	if run.clock >= e.stagger:
		if e.wind_at != INF and run.clock >= e.wind_at:
			e.wind_at = INF
			if hero:
				_execute_attack(run, e, distance, range_at, aim)
		if e.dash > run.clock:
			facing = e.dash_dir
			motion = facing * (11.0 if kind == GUTTER else (13.0 if kind == HAILSTONE else 8.0))
			if hero and not e.dash_hit and distance <= (1.8 if kind == HAILSTONE else 1.65) \
					and run.clear_path(e.pos + Vector3.UP, run.eye()):
				e.dash_hit = true
				if run.state == "ok":
					run.damage(e.spec.damage * run.enemy_buff(), e.pos)
		elif hero and e.wind_at == INF and run.clock >= e.recover:
			var target = run.loot.lured_target(e.pos, run.pos)
			var lured = target != run.pos
			if not lured and run.clock >= e.attack_at and distance <= range_at and run.state == "ok" \
					and run.clear_path(e.pos + Vector3.UP * (0.75 * e.scale), run.eye()):
				e.wind_at = run.clock + WINDUP[kind]
				e.dash_dir = aim
				e.attack_at = run.clock + e.spec.attack_cooldown
				_tell(run, e, CUES[kind], WINDUP[kind], -12.0 if kind < SLEET else -8.0)
			if e.wind_at == INF:
				if kind == STATIC and run.clock >= e.blink_at and distance > 6.0 and distance < 17.0:
					e.blink_at = run.clock + 5.0
					var hop = aim.rotated(Vector3.UP, e.wall_side * 0.7) * 3.4
					if run.clear_path(e.pos + Vector3.UP, e.pos + hop + Vector3.UP):
						e.pos = run.ground(e.pos + hop, 0.7, 3.0)
						_tell(run, e, "static_blink", 0.0, -11.0)
				var keep = 7.0 if kind == MISTER else (10.0 if kind == SMOG else 0.0)
				if lured or distance > max(0.95, e.spec.attack_range * 0.68) or keep > 0.0 \
						or not run.clear_path(e.pos + Vector3.UP, run.eye()):
					if not lured and keep > 0.0 and distance < keep - 1.0 and run.clear_path(e.pos + Vector3.UP, run.eye()):
						motion = -aim * velocity * 0.75
					elif not lured and keep > 0.0 and distance < keep + 2.0 and run.clear_path(e.pos + Vector3.UP, run.eye()):
						motion = aim.rotated(Vector3.UP, e.wall_side * PI / 2.0) * velocity * 0.55
					else:
						motion = _route(run, e, target) * velocity
						if kind == SLEET:
							motion = motion.rotated(Vector3.UP, sin(run.clock * 6.0 + e.id) * 0.22)
	if run.clock >= e.dash and motion.length_squared() > 0.04:
		motion += _separation(e) * 0.8
	if e.push.length_squared() > 0.04:
		motion += e.push
		e.push = e.push.move_toward(Vector3.ZERO, elapsed * 23.0)
	if facing.length_squared() > 0.0:
		var desired_yaw = atan2(-facing.x, -facing.z)
		var difference = wrapf(desired_yaw - e.yaw, -PI, PI)
		e.yaw += clamp(difference, -1.1 * elapsed, 1.1 * elapsed) if kind == HAILSTONE else difference
	_move(run, e, motion, elapsed)


func _separation(e: Dictionary) -> Vector3:
	var drift = Vector3.ZERO
	for other in enemies:
		if other.id == e.id:
			continue
		var between = _flat(e.pos - other.pos)
		var length = between.length_squared()
		if length > 0.001 and length < 0.50:
			drift += between * (1.0 - length)
	return drift.normalized() if drift.length_squared() > 1.0 else drift


func _route(run, e: Dictionary, target: Vector3) -> Vector3:
	if is_instance_valid(run.navigation) and run.clock >= e.nav_at and _nav_budget > 0:
		_nav_budget -= 1
		e.nav_at = run.clock + 0.9 + (e.id % 4) * 0.08
		e.path = run.navigation.get_simple_path(e.pos, target, true)
		e.path_i = 0
	while e.path_i < e.path.size():
		var toward = _flat(e.path[e.path_i] - e.pos)
		if toward.length_squared() >= 0.56 * 0.56:
			return toward.normalized()
		e.path_i += 1
	return _flat(target - e.pos).normalized()


func _move(run, e: Dictionary, motion: Vector3, dt: float) -> void:
	e.goal = e.pos
	e.motion = 0.0
	if motion.length_squared() < 0.002:
		return
	var start = e.pos + Vector3.UP * 0.55
	var offset = motion * dt
	var unit = motion.normalized()
	var hit = run.ray(start, start + offset + unit * 0.28)
	if not hit.empty():
		if run.clock < e.dash:
			e.dash = 0.0
			e.recover = run.clock + 1.1
			e.crash_at = run.clock
			_tell(run, e, "hailstone_crash" if e.kind == HAILSTONE else "gutter_skid", 0.0, -7.0)
			return
		var normal = _flat(hit.normal).normalized()
		var tangent = Vector3(-normal.z, 0.0, normal.x)
		if run.clock >= e.wall_until:
			e.wall_side = 1.0 if tangent.dot(unit) >= 0.0 else -1.0
			e.wall_until = run.clock + 1.0
		offset = tangent * e.wall_side * offset.length() + normal * 0.05
		if not run.clear_path(start, start + offset):
			e.wall_side *= -1.0
			return
	var floor_hit = run.ray(e.pos + offset + Vector3.UP * 0.55, e.pos + offset - Vector3.UP * 2.8)
	if floor_hit.empty() or floor_hit.normal.y < 0.45:
		return
	var candidate = floor_hit.position + Vector3.UP * 0.04
	if abs(candidate.y - e.pos.y) > 1.15:
		return
	e.goal = candidate
	e.motion = max(0.01, e.pos.distance_to(e.goal) / dt)


func _execute_attack(run, e: Dictionary, distance: float, reach: float, aim: Vector3) -> void:
	var kind = e.kind
	var amount = e.spec.damage * run.enemy_buff()
	e.recover = run.clock + (0.46 if kind == DRIP else 0.6)
	if kind != HAILSTONE and (distance > reach + 0.7 or not run.clear_path(e.pos + Vector3.UP * (0.75 * e.scale), run.eye())):
		return
	match kind:
		GUTTER, SLEET, HAILSTONE:
			e.dash = run.clock + (0.55 if kind == GUTTER else (0.67 if kind == HAILSTONE else 0.42))
			e.dash_hit = false
			e.recover = e.dash + (0.8 if kind == HAILSTONE else 0.45)
		MISTER, SMOG:
			var acid = kind == SMOG or e.miniboss > 0
			var start = e.pos + Vector3.UP * 1.15 * e.scale
			var at = run.pos + _flat(run.vel) * 0.55
			if e.miniboss > 0:
				for n in range(3):
					var point = at + Vector3(3.4, 0, 0).rotated(Vector3.UP, n * TAU / 3.0 + run.clock)
					_spore(run, start, point, 1.35, amount * 1.15, true, true)
			else:
				_spore(run, start, at, 1.2 if kind == MISTER else 1.6, amount, acid)
		UNDERTOW:
			run.mark_dragged()
			var factor = 0.3 if run.player_mutations.has("hydro_skin") else 1.0
			run.rpc(run.player_path, "_receive_enemy_pull", [-aim * 7.0 * factor])
			run.damage(amount, e.pos)
		STATIC:
			if run.loot.protection(run, run.eye()) == 2:
				run.feat("faraday_cage")
			else:
				run.damage(amount * (1.35 if run.clock < e.powered else 1.0), e.pos)
			run.rpc(run.GAME, "_draw_arc", [[e.pos + Vector3.UP, run.eye()], Color("#fff074")], false)
		THUNDERHEAD:
			_thunderhead(run, e, amount)
		_:
			run.damage(amount, e.pos)


func _thunderhead(run, e: Dictionary, damage: float) -> void:
	var radius = 6.3 if e.elite else 5.1
	e.hp = 0.0
	_die(run, e, Vector3.ZERO, false, false)
	run.rpc(run.GAME, "_draw_blast", [e.pos, radius * 0.59, Color("#ff9b65")], false)
	if run.pos.distance_squared_to(e.pos) <= radius * radius and run.clear_path(e.pos + Vector3.UP, run.eye()):
		run.damage(damage, e.pos)


func _tell(run, e: Dictionary, cue: String, duration: float, volume: float) -> void:
	run.rpc(run.ENEMIES, "_play_enemy_tell", [e.id, cue, duration, volume])



func shoot(run, id: String, from: Vector3, direction: Vector3, spec: Dictionary, spread: float, damage: float, voltaic: bool) -> Array:
	var traces = []
	var hits = []
	var impacts = []
	var special_hits = {}
	var pierce = int(spec.pierce) + int(run.player_mutations.has("bone_piercer"))
	if spec.mechanic in ["wash", "gust"]:
		for hazard in _hazards.duplicate():
			var relative = hazard.pos - from
			if hazard.land <= run.clock and relative.length_squared() <= spec.max_range * spec.max_range \
					and direction.dot(relative.normalized()) > 0.92 and run.clear_path(from, hazard.pos):
				_remove_hazard(run, hazard)
	if spec.mechanic == "gust":
		for enemy in enemies.duplicate():
			var at = enemy.pos + Vector3.UP * 0.8
			var ray = (at - from).normalized()
			if at.distance_squared_to(from) <= spec.max_range * spec.max_range and ray.dot(direction) > 0.80 \
					and run.clear_path(from, at):
				hits.append(_hurt(run, enemy, damage, at, ray, false, spec.knockback))
				traces.append([at, 2])
	else:
		for _pellet in range(int(spec.pellets)):
			var ray = _pellet_dir(run, direction, spread)
			var terminal = from + ray * spec.max_range
			var obstacle = run.ray(from, terminal)
			var impact = 0
			if not obstacle.empty():
				terminal = obstacle.position
				impact = _surface_impact(obstacle.collider)
			var candidates = _contacts(from, ray, from.distance_to(terminal), spec.mechanic == "reel")
			var count = 0
			for hit in candidates:
				if count > pierce:
					break
				if hit.e == null:
					var boss_hit = _hit_boss(run, hit.part, damage, hit.at)
					if not boss_hit.empty():
						hits.append(boss_hit)
					terminal = hit.at
					impact = 3 if boss_hit.empty() else 2
					break
				var e = hit.e
				if e.hp <= 0.0:
					continue
				count += 1
				var armored = e.kind == HAILSTONE and _armored(e, from)
				var head = hit.critical
				if e.kind == HAILSTONE:
					var relative_height = (hit.at.y - e.pos.y) / e.scale
					head = relative_height >= 0.94 and relative_height <= 1.94 and _facing_dot(e, from) < -0.35
				var amount = damage * (spec.critical_bonus * (2.6 if run.player_mutations.has("bone_piercer") else 2.0) if head else 1.0)
				if id == "lucky_penny_revolver" and e.miniboss == 0 and run.rng.randf() < 0.25:
					amount = e.hp
				if armored:
					amount *= 0.36
				var was_hit = _hurt(run, e, amount, hit.at, ray, head, spec.knockback)
				hits.append(was_hit)
				if not was_hit[0]:
					impacts.append([e.id, ray, head])
					if not special_hits.has(e.id):
						special_hits[e.id] = true
						_weapon_special(run, e, hit.at, from, damage, spec.mechanic, voltaic)
				if count > pierce:
					terminal = hit.at
					impact = 2
					break
			traces.append([terminal, impact])
	if not hits.empty():
		run.rpc(run.player_path, "_receive_hits", [run.id, hits])
	if not impacts.empty():
		run.rpc(run.ENEMIES, "_enemy_impacts", [impacts], false)
	return traces


func _contacts(from: Vector3, dir: Vector3, length: float, harpoon: bool) -> Array:
	var contacts = []
	for e in enemies:
		if e.submerged_at > 0.0 and not harpoon:
			continue
		var scale = e.scale
		var radius = BODY_RADIUS[e.kind] * scale
		var height = CRIT_HEIGHT[e.kind] * scale
		var critical = _sphere(from, dir, e.pos + Vector3.UP * (height + 0.12 * scale), radius * 0.62, length)
		var chest = _sphere(from, dir, e.pos + Vector3.UP * height * 0.61, radius, length)
		var legs = _sphere(from, dir, e.pos + Vector3.UP * 0.42 * scale, radius * 0.76, length)
		var distance = min(critical, min(chest, legs))
		if distance != INF:
			contacts.append({"dist": distance, "e": e, "critical": critical <= distance + 0.08, "at": from + dir * distance})
	if boss_alive():
		for part in range(4):
			if _boss.hp[part] > 0.0:
				var distance = _sphere(from, dir, _boss_part(part), 2.414 if part < 3 else 3.124, length)
				if distance != INF:
					contacts.append({"dist": distance, "e": null, "part": part, "at": from + dir * distance})
	if contacts.size() > 1:
		contacts.sort_custom(self, "_contact_before")
	return contacts


func _contact_before(a: Dictionary, b: Dictionary) -> bool:
	return a.dist < b.dist


func projectile_contact(from: Vector3, to: Vector3) -> Vector3:
	var direction = to - from
	if direction.length_squared() < 0.001:
		return Vector3.INF
	var contacts = _contacts(from, direction.normalized(), direction.length(), false)
	return Vector3.INF if contacts.empty() else contacts[0].at


func _weapon_special(run, e: Dictionary, at: Vector3, from: Vector3, amount: float, mechanic: String, voltaic: bool) -> void:
	match mechanic:
		"pin", "suppress", "salt", "wash":
			e.slow = run.clock + (1.4 if mechanic == "salt" else 0.8)
			if mechanic in ["salt", "suppress"]:
				_stagger(run, e, 0.72)
		"reel":
			e.submerged_at = 0.0
			e.push = _flat(from - e.pos).normalized() * 11.0
			_stagger(run, e, 0.45)
	if voltaic or mechanic == "zap":
		_chain(run, e, at, amount * 0.7, 3 if mechanic == "zap" else 2, 6.0, Color("#fff074"))


func _chain(run, first, at: Vector3, amount: float, hops: int, radius: float, color: Color, credited = true) -> void:
	var used = [first]
	var points = [at]
	var hit_rows = []
	for _hop in range(hops):
		var best = radius * radius
		var next = null
		for enemy in enemies:
			if enemy in used:
				continue
			var distance = at.distance_squared_to(enemy.pos + Vector3.UP)
			if distance < best:
				next = enemy
				best = distance
		if next == null or not run.clear_path(at, next.pos + Vector3.UP):
			break
		used.append(next)
		at = next.pos + Vector3.UP
		points.append(at)
		var row = _hurt(run, next, amount, at, Vector3.ZERO, false, 0.0, credited)
		if credited:
			hit_rows.append(row)
		amount *= 0.75
	if points.size() > 1:
		run.rpc(run.GAME, "_draw_arc", [points, color], false)
	if not hit_rows.empty():
		run.rpc(run.player_path, "_receive_hits", [run.id, hit_rows])


func _hurt(run, e: Dictionary, damage: float, at: Vector3, direction: Vector3, critical: bool, knock: float, credited = true) -> Array:
	var previous = e.hp
	e.hp = max(0.0, e.hp - damage)
	if e.miniboss > 0:
		_miniboss_hp(run, e)
	if e.hp <= 0.0:
		_die(run, e, direction * min(12.0, damage * 0.1 + knock), critical, credited)
	else:
		if at.y - e.pos.y < 0.65 * e.scale:
			e.slow = run.clock + 0.9
		if critical or knock >= 3.0:
			_stagger(run, e, 0.25 if e.miniboss > 0 else (0.55 if critical else 0.40))
		if knock > 0.0:
			e.push += _flat(direction) * knock / e.scale
	return [e.hp <= 0.0, critical, at, int(ceil(previous - e.hp)), e.id]


func _stagger(run, e: Dictionary, time: float) -> void:
	e.stagger = max(e.stagger, run.clock + time)
	e.wind_at = INF
	e.dash = 0.0


func _die(run, e: Dictionary, shove: Vector3, critical: bool, credited: bool) -> void:
	enemies.erase(e)
	if credited:
		run.record_kill(e.elite, e.pos)
		if e.kind == HAILSTONE:
			if critical:
				run.feat("cold_shoulder")
			if run.clock - e.crash_at < 2.5:
				run.feat("brake_check")
			elif e.dash > run.clock:
				run.feat("hail_mary")
	var drops = []
	if e.miniboss > 0:
		for i in range(3):
			if run.loot.has_scrap_room(i):
				drops.append([e.pos + Vector3(0.85, 0, 0).rotated(Vector3.UP, i * TAU / 3.0), "scrap_large"])
		run.rpc(run.GAME, "_banner", ["CLOUDBURST DEFEATED", Color("#ffd56a"), 2.4])
	elif run.loot.has_scrap_room(0) and (not e.small or run.rng.randf() < 0.35):
		drops.append([e.pos, "scrap_large" if e.elite else "scrap"])
	if run.rng.randf() < 0.05:
		var types = ["ammo", "health", "suit"]
		drops.append([e.pos + Vector3(0.4, 0, 0.2), types[run.rng.randi_range(0, 2)]])
	run.rpc(run.ENEMIES, "_despawn_enemy", [e.id, drops, e.pos, shove, critical])
	for drop in drops:
		run.loot.add_supply(run, drop[0], drop[1], 45.0 if drop[1].begins_with("scrap") else 35.0)
	if e.kind == THUNDERHEAD and credited:
		run.rpc(run.GAME, "_draw_blast", [e.pos, 2.8, Color("#ff9b65")], false)
		if run.pos.distance_squared_to(e.pos) < 2.8 * 2.8 and run.clear_path(e.pos + Vector3.UP, run.eye()):
			run.damage(e.spec.damage * 0.5, e.pos)


func blast(run, at: Vector3, radius: float, amount: float, knock: float, falloff: bool) -> void:
	if radius <= 0.0 or amount <= 0.0:
		return
	var hit_rows = []
	for enemy in enemies.duplicate():
		if enemy.hp <= 0.0:
			continue
		var target = enemy.pos + Vector3.UP * 0.65 * enemy.scale
		var distance = at.distance_to(target)
		if distance <= radius and run.clear_path(at + Vector3.UP * 0.1, target):
			var damage = amount * (1.0 - 0.6 * distance / radius if falloff else 1.0)
			hit_rows.append(_hurt(run, enemy, damage, target, (target - at).normalized(), false, knock))
	if boss_alive():
		for i in range(4):
			if not boss_alive():
				break
			var target = _boss_part(i)
			if target.distance_squared_to(at) <= radius * radius and run.clear_path(at + Vector3.UP * 0.1, target):
				var boss_hit = _hit_boss(run, i, amount, target)
				if not boss_hit.empty():
					hit_rows.append(boss_hit)
	if not hit_rows.empty():
		run.rpc(run.player_path, "_receive_hits", [run.id, hit_rows])


func _spore(run, from: Vector3, want: Vector3, flight: float, damage: float, acid: bool, cloudburst = false) -> void:
	var at = run.ground(want, 1.0, 4.0)
	_next_hazard += 1
	var radius = 3.0 if acid else 2.5
	_add_hazard(run, {"id": _next_hazard, "pos": at, "dps": damage, "radius": radius,
		"land": run.clock + flight, "end": run.clock + flight + (7.0 if acid else 4.0)})
	run.rpc(run.GAME, "_spawn_spore", [_next_hazard, from, at, flight, damage, acid, cloudburst])


func _cloud(run, at: Vector3, dps: float, radius: float, life: float) -> void:
	_next_hazard += 1
	_add_hazard(run, {"id": _next_hazard, "pos": at, "dps": dps, "radius": radius, "land": run.clock, "end": run.clock + life})
	run.rpc(run.GAME, "_spawn_cloud", [_next_hazard, at, dps, radius])


func _add_hazard(run, hazard: Dictionary) -> void:
	if _hazards.size() >= 28:
		_remove_hazard(run, _hazards[0])
	_hazards.append(hazard)


func _remove_hazard(run, hazard: Dictionary) -> void:
	_hazards.erase(hazard)
	run.rpc(run.GAME, "_disperse_cloud", [hazard.id])


func clear_clouds(run, at: Vector3, radius: float) -> void:
	for hazard in _hazards.duplicate():
		if hazard.land <= run.clock and at.distance_squared_to(hazard.pos) <= pow(radius + hazard.radius, 2):
			_remove_hazard(run, hazard)


func _tick_hazards(run) -> void:
	if _hazards.empty() or run.clock < _hazard_at:
		return
	_hazard_at = run.clock + 0.1
	var strength = 0.0
	var i = _hazards.size() - 1
	while i >= 0:
		var h = _hazards[i]
		if run.clock >= h.end:
			_remove_hazard(run, h)
		elif run.clock >= h.land and abs(run.pos.y - h.pos.y) < 2.4 \
				and _flat(run.pos - h.pos).length_squared() <= h.radius * h.radius:
			strength = max(strength, h.dps)
		i -= 1
	if strength > 0.0 and run.loot.protection(run, run.pos + Vector3.UP) < 2:
		run.damage(strength * 0.1, Vector3.INF, true)


func ambient_lightning(run, at: Vector3) -> void:
	for e in enemies:
		if e.kind == STATIC and at.distance_squared_to(e.pos) < 30.0 * 30.0:
			e.powered = run.clock + 5.0
			_tell(run, e, "static_power", 0.0, -8.0)
	if run.enemy_mutations.has("conductors") and not enemies.empty():
		_chain(run, null, at, 28.0, 4, 20.0, Color("#fff074"), false)


func tactical_lightning(run, at: Vector3, radius: float, damage: float) -> void:
	run.rpc(run.WEATHER, "_strike", [at, run.rng.randi_range(1, 2147483646)])
	blast(run, at, radius, damage, 5.0, false)
	ambient_lightning(run, at)


func repel(run, at: Vector3, radius: float) -> void:
	for e in enemies:
		var away = _flat(e.pos - at)
		if away.length_squared() <= radius * radius and abs(e.pos.y - at.y) < 2.7:
			e.push = away.normalized() * 3.5
			e.slow = run.clock + 0.35


func flare(run, at: Vector3, radius: float, scale: float) -> void:
	if boss_alive() and _flat(_boss.pos - at).length_squared() <= pow(radius + 6.0, 2):
		_boss.burn = 1.0
	blast(run, at, radius, 18.0 * scale * 0.25, 0.0, false)


func spawn_boss(run) -> void:
	if boss_alive() or run.markers.boss_anchor.empty():
		return
	var at = run.markers.boss_anchor[0].pos
	_boss = {"pos": at, "center": _flat(at), "anchor": at, "hp": BOSS_MAX.duplicate(), "sacs": 3, "burn": 0.0,
		"attack": run.clock + 3.0, "summon": run.clock + 10.5, "sync": run.clock, "t": 0.0}
	run.rpc(run.GAME, "_spawn_boss", [at])
	run.set_override(1.0)
	run.rpc(run.GAME, "_banner", ["CUMULUS", Color("#8fd65a"), 2.2])


func _tick_boss(run, dt: float) -> void:
	_boss.t += dt
	var ground = _flat(run.pos)
	var radius = 9.0 if _boss.sacs == 0 else 5.0
	var orbit = _boss.t * (0.85 if _boss.sacs == 0 else 0.35)
	_boss.center = _boss.center.move_toward(ground, 8.2 * dt)
	var position = _boss.center + Vector3(cos(orbit), 0, sin(orbit)) * radius
	var want_y = max(run.pos.y + 5.0, _boss.anchor.y - 4.0 * (3 - _boss.sacs))
	position.y = move_toward(_boss.pos.y, want_y, 2.2 * dt)
	_boss.pos = position
	_boss.burn = max(0.0, _boss.burn - dt)
	if _boss.burn <= 0.0:
		var regen = 18.0 * run.intensity * dt
		for i in range(4):
			if _boss.hp[i] > 0.0:
				_boss.hp[i] = min(_boss.hp[i] + regen, BOSS_MAX[i])
	if run.clock >= _boss.attack:
		_boss.attack = run.clock + (0.9 if _boss.sacs == 0 else max(1.35, 1.9 - 0.22 * (3 - _boss.sacs)))
		var target = run.pos + _flat(run.vel) * 0.65
		var start = _boss.pos - Vector3.UP * 1.1
		if run.clear_path(start, target + Vector3.UP * 0.5):
			_spore(run, start, target, 1.35, 13.0, true)
			if _boss.sacs == 0:
				for i in range(2):
					_spore(run, start, target + Vector3(4.2, 0, 0).rotated(Vector3.UP, i * PI + orbit), 1.45, 13.0, true)
	if run.clock >= _boss.summon:
		_boss.summon = run.clock + 10.5
		for i in range(min(3, run.alive_cap - enemies.size())):
			_spawn(run, GUTTER if i == 1 else DRIP, _marker(run, "enemy_spawn"))
			_extras += 1
	if run.clock >= _boss.sync:
		_boss.sync = run.clock + 0.1
		_sync_boss(run)


func _sync_boss(run) -> void:
	run.rpc(run.BOSS, "_sync", [_boss.pos, _boss.hp.duplicate(), _boss.sacs, _boss.burn])


func _boss_part(i: int) -> Vector3:
	if i == 3:
		return _boss.pos - Vector3.UP * 2.556
	var angle = i * TAU / 3.0
	return _boss.pos + Vector3(cos(angle) * 7.1, -1.704, sin(angle) * 7.1)


func _hit_boss(run, part: int, damage: float, at: Vector3) -> Array:
	if not boss_alive() or _boss.hp[part] <= 0.0 or (part == 3 and _boss.sacs > 0):
		return []
	var amount = min(_boss.hp[part], damage)
	_boss.hp[part] -= amount
	var dead = _boss.hp[part] <= 0.0
	if dead:
		if part < 3:
			_boss.sacs -= 1
			run.set_override([0.35, 0.55, 0.80][_boss.sacs])
			run.rpc(run.GAME, "_draw_blast", [at, 3.0, Color("#8fd65a")], false)
			_cloud(run, at, 10.0, 4.0, 4.0)
		else:
			if run.loot.protection(run, run.eye()) > 0:
				run.feat("umbrella_policy")
			_sync_boss(run)
			run.rpc(run.BOSS, "_died", [])
			_boss.clear()
			run.boss_defeated()
	return [dead, false, at, int(ceil(amount)), 900000 + part]


static func _pellet_dir(run, direction: Vector3, spread: float) -> Vector3:
	if spread <= 0.0:
		return direction
	var axis = Vector3.RIGHT if abs(direction.y) > 0.95 else Vector3.UP
	var right = direction.cross(axis).normalized()
	var up = right.cross(direction).normalized()
	var angle = run.rng.randf() * TAU
	var extent = sqrt(run.rng.randf()) * tan(deg2rad(spread))
	return (direction + (right * cos(angle) + up * sin(angle)) * extent).normalized()


static func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)


static func _sphere(from: Vector3, direction: Vector3, center: Vector3, radius: float, length: float) -> float:
	var offset = center - from
	var middle = offset.dot(direction)
	var discriminant = radius * radius - (offset.length_squared() - middle * middle)
	if discriminant < 0.0:
		return INF
	var near = middle - sqrt(discriminant)
	var far = middle + sqrt(discriminant)
	return max(0.0, near) if far >= 0.0 and near <= length else INF


static func _armored(enemy: Dictionary, from: Vector3) -> bool:
	return _facing_dot(enemy, from) > 0.3


static func _facing_dot(enemy: Dictionary, from: Vector3) -> float:
	var forward = Vector3(-sin(enemy.yaw), 0, -cos(enemy.yaw))
	return _flat(from - enemy.pos).normalized().dot(forward)


static func _surface_impact(collider) -> int:
	if collider is Node:
		var path = str(collider.get_path()).to_lower()
		if "metal" in path or "rail" in path or "grate" in path or "fence" in path:
			return 3
	return 1

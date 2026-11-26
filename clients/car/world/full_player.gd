extends KinematicBody
## Local player for the Full tier (client-responsibilities §1–2): a capsule
## KinematicBody with the native game's movement (player/player.gd):
## walk 5 / sprint 8 / crouch 2.5 / crawl 1 / turned 5.5 m/s, ground accel 60,
## air accel 12, jump 4.8 m/s with 0.12 s coyote time and jump buffer,
## gravity 9.8, floor snap 0.3 m, capsule radius 0.4, height 1.8 / 1.1 / 0.7,
## crouch transition 8 m/s. Speed is capped at 3.5 m/s while aiming or with
## the tarp raised. Enemy pulls decay at 22 m/s².
##
## The body itself never rotates; yaw/pitch live on the world camera. Origin
## = feet. Collides with layer 1 (level geometry), sits on layer 2 (players).
##
## Stepping runs once per rendered frame (sub-stepped to <= 1/30 s) instead of
## in _physics_process: cheaper on the head unit than 60 Hz physics ticks,
## and input edges are read in the same frame.

const WALK = 5.0
const SPRINT = 8.0
const CROUCH = 2.5
const CRAWL = 1.0
const TURNED = 5.5
const GROUND_ACCEL = 60.0
const AIR_ACCEL = 12.0
const JUMP = 4.8
const COYOTE = 0.12
const JUMP_BUFFER = 0.12
const GRAVITY = 9.8
const STAND_H = 1.8
const CROUCH_H = 1.1
const DOWNED_H = 0.7
const CROUCH_RATE = 8.0
const RADIUS = 0.4
const SNAP = 0.3
const STEP_UP = 0.32
const MAX_STEP_DT = 1.0 / 30.0

var vel = Vector3.ZERO
var height = STAND_H
var crouching = false
var sprinting = false
var grounded = true
var speed_scale = 1.0              # Adrenaline Glands: 1.18
var jump_scale = 1.0               # Adrenaline Glands: 1.2
var enemy_pull = Vector3.ZERO
var _applied_pull = Vector3.ZERO
var _coyote = 0.0
var _jump_buf = 0.0
var _jumped = false
var _shape = CollisionShape.new()
var _capsule = CapsuleShape.new()
var _step_dist = 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	_shape.shape = _capsule
	_shape.rotation_degrees = Vector3(90, 0, 0)
	add_child(_shape)
	_apply_height()


func _apply_height() -> void:
	var r: float = min(RADIUS, height * 0.5 - 0.01)
	_capsule.radius = r
	_capsule.height = max(0.01, height - 2.0 * r)
	_shape.translation = Vector3(0, height * 0.5, 0)


func eye_height() -> float:
	return height - 0.15


func feet() -> Vector3:
	return global_transform.origin


func teleport(pos: Vector3) -> void:
	global_transform.origin = pos
	vel = Vector3.ZERO
	enemy_pull = Vector3.ZERO


func can_stand() -> bool:
	return not test_move(global_transform, Vector3(0, STAND_H - height + 0.05, 0))


## One frame of movement. inp: move (Vector2, x right / y forward), jump
## (pressed edge), crouch (held), sprint (held), aiming, tarp, state, yaw.
func step(delta: float, inp: Dictionary) -> void:
	if inp.get("state", "ok") == "out":
		vel = Vector3.ZERO
		return
	if inp.get("jump", false):
		_jump_buf = JUMP_BUFFER
	var left = min(delta, 0.25)
	while left > 0.0001:
		var dt = min(left, MAX_STEP_DT)
		left -= dt
		_tick(dt, inp)
		inp["jump"] = false


func _tick(dt: float, inp: Dictionary) -> void:
	var state = str(inp.get("state", "ok"))
	if grounded:
		_coyote = COYOTE
	else:
		vel.y -= GRAVITY * dt
		_coyote -= dt
	_jump_buf -= dt
	if inp.get("crouch", false) and state in ["ok", "turned"]:
		crouching = true
	elif crouching and can_stand():
		crouching = false
	var target_h = CROUCH_H if crouching else STAND_H
	if state == "downed":
		target_h = DOWNED_H
	if not is_equal_approx(height, target_h):
		var grow = target_h > height
		var nh = move_toward(height, target_h, CROUCH_RATE * dt)
		if not grow or not test_move(global_transform, Vector3(0, nh - height + 0.02, 0)):
			height = nh
			_apply_height()
	_jumped = false
	if _jump_buf > 0.0 and _coyote > 0.0 and not crouching and state != "downed":
		vel.y = JUMP * jump_scale
		_jump_buf = 0.0
		_coyote = 0.0
		_jumped = true
	var mv: Vector2 = inp.get("move", Vector2.ZERO)
	var yaw: float = inp.get("yaw", 0.0)
	var dir = Basis(Vector3.UP, yaw).xform(Vector3(mv.x, 0.0, -mv.y))
	var aiming = bool(inp.get("aiming", false))
	sprinting = bool(inp.get("sprint", false)) and not crouching and mv.y > 0.1 and state == "ok" and not aiming
	var speed = WALK
	match state:
		"downed":
			speed = CRAWL
		"turned":
			speed = TURNED
		_:
			if crouching:
				speed = CROUCH
			elif sprinting:
				speed = SPRINT
			speed *= speed_scale
			if bool(inp.get("tarp", false)) or aiming:
				speed = min(speed, WALK * 0.7)
	var accel = GROUND_ACCEL if grounded else AIR_ACCEL
	var own = vel - _applied_pull
	var h = Vector2(own.x, own.z).move_toward(Vector2(dir.x, dir.z) * speed, accel * dt)
	vel.x = h.x
	vel.z = h.y
	enemy_pull = enemy_pull.move_toward(Vector3.ZERO, 22.0 * dt)
	_applied_pull = enemy_pull if state == "ok" else Vector3.ZERO
	vel += _applied_pull
	var want = Vector3(vel.x, 0, vel.z)
	var before = global_transform.origin
	var snap = Vector3.DOWN * SNAP if grounded and not _jumped and vel.y <= 0.0 else Vector3.ZERO
	vel = move_and_slide_with_snap(vel, snap, Vector3.UP, true, 4, deg2rad(46.0), false)
	grounded = is_on_floor()
	if grounded and is_on_wall() and want.length() > 0.5:
		_try_step(want * dt, before)
	var moved = global_transform.origin - before
	if grounded and state in ["ok", "turned"]:
		_step_dist += Vector2(moved.x, moved.z).length()
		if _step_dist >= 1.9:
			_step_dist = 0.0
			Sound.play("step_%d" % (randi() % 4), -20.0)


## Climb a low ledge (curb, porch step) the slide stopped us at.
func _try_step(motion: Vector3, before: Vector3) -> void:
	var achieved = global_transform.origin - before
	achieved.y = 0.0
	if achieved.length() > motion.length() * 0.6:
		return
	var t = global_transform
	t.origin = before
	var up = Vector3(0, STEP_UP, 0)
	if test_move(t, up):
		return
	t.origin += up
	var fwd = motion.normalized() * max(motion.length(), 0.08)
	if test_move(t, fwd):
		return
	t.origin += fwd
	var saved = global_transform
	global_transform = t
	var col = move_and_collide(Vector3(0, -STEP_UP - 0.05, 0))
	if col == null or col.normal.y < 0.7:
		global_transform = saved
	else:
		grounded = true

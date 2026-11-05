class_name Raven
extends Node3D
## One of the camp's ravens (jj, 2026-11-04: "birds land on it with real movement"): the Meshy raven
## (assets/models/camp/birds/raven.glb, rigged by tools/blender/npc/rig_raven.py: root, legs, body, neck, head, tail
## and each wing in three, wL1..3 / wR1..3), posed in code every frame. CampRavens moves it between its roosts
## (rooftops, the palisade, the ground by the fire); this is the bird itself: how it sits, looks about in quick snaps,
## pecks, preens, hops, stretches a wing, caws, shakes its feathers out; how it springs off and climbs with hard beats,
## flies on flapping and gliding, banking into its turns, and comes in to land: body up, wings forward in a flare with
## quick back-beats, tail fanned, feet out, then wings folded and a settle. Only for the look; local to each game.

const GLB := "res://assets/models/camp/birds/raven.glb"
const SIZE := 1.0
const FLY_SPEED := 6.2
const LAND_T := 1.05          # seconds of the approach spent slowing into the flare
const TAKEOFF_T := 0.55

static var _scene: PackedScene

var body: Node3D
var sk: Skeleton3D
var _b := {}                  # bone name -> index
var _rg := {}                 # index -> rest global basis
var _rp := {}                 # index -> parent's rest global basis

var state := "perch"          # perch, takeoff, fly, land
var t := 0.0                  # time in the state
var at := Vector3.ZERO        # where it stands (perched)
var yaw := 0.0
var ground := false           # on the ground (pecks there) rather than a roof
# the flight: a curve from a to b over c, its length and time
var fa := Vector3.ZERO
var fb := Vector3.ZERO
var fc := Vector3.ZERO
var fdur := 1.0
var _prev := Vector3.ZERO
var _vel := Vector3.ZERO
var _bank := 0.0
var _pitch := 0.0
# what it's doing on its perch: an act and its time
var act := ""
var act_t := 0.0
var act_dur := 0.0
var _next_act := 1.0
var _head_yaw := 0.0
var _head_want := 0.0
var _head_snap := 0.5
var _hop := Vector3.ZERO      # a hop under way: from, to (in at), t
var _hop_from := Vector3.ZERO
var _hop_t := -1.0
var _fold := 1.0              # 0 spread .. 1 folded
var _flap_ph := 0.0
var on_caw: Callable          # CampRavens plays the sound

static func make() -> Raven:
	var r := Raven.new()
	if _scene == null and ResourceLoader.exists(GLB):
		_scene = load(GLB)
	if _scene != null:
		r.body = _scene.instantiate()
		r.add_child(r.body)
		r.body.scale = Vector3.ONE * SIZE * randf_range(0.9, 1.08)
		r.sk = r.body.find_child("Skeleton3D", true, false)
		for mi in r.body.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if r.sk != null:
		for i in r.sk.get_bone_count():
			r._b[r.sk.get_bone_name(i)] = i
			r._rg[i] = r.sk.get_bone_global_rest(i).basis.orthonormalized()
			var p := r.sk.get_bone_parent(i)
			r._rp[i] = r.sk.get_bone_global_rest(p).basis.orthonormalized() if p >= 0 else Basis()
	return r

## Sat down at p (facing y) at once.
func perch_at(p: Vector3, y: float, on_ground: bool) -> void:
	at = p
	yaw = y
	ground = on_ground
	state = "perch"
	t = 0.0
	_fold = 1.0
	global_position = p
	rotation = Vector3(0, yaw, 0)

## Off to b (a roost), over a curve that climbs first.
func fly_to(b: Vector3, by_ground: bool) -> void:
	fa = global_position
	fb = b
	var d := fb - fa
	var flat := Vector2(d.x, d.z).length()
	fc = (fa + fb) * 0.5 + Vector3(0, clampf(flat * 0.28, 1.8, 6.0) + maxf(0.0, fb.y - fa.y) * 0.5, 0)
	fdur = maxf(1.4, (flat + absf(d.y)) / FLY_SPEED * 1.15)
	ground = by_ground
	state = "takeoff"
	t = 0.0
	_prev = global_position
	act = ""

func flying() -> bool:
	return state != "perch"

func _curve(u: float) -> Vector3:
	var a := fa.lerp(fc, u)
	var b := fc.lerp(fb, u)
	return a.lerp(b, u)

func tick(delta: float) -> void:
	t += delta
	match state:
		"perch":
			_perched(delta)
		"takeoff":
			_takeoff(delta)
		"fly", "land":
			_fly(delta)

# ------------------------------------------------------------------ on the perch
func _perched(delta: float) -> void:
	_fold = move_toward(_fold, 1.0, delta * 2.2)
	_next_act -= delta
	if act == "" and _next_act <= 0.0:
		var choices := ["look", "look", "look", "preen", "shake", "stretch", "caw", "hop", "settle"]
		if ground:
			choices += ["peck", "peck", "peck", "hop", "hop"]
		act = choices[randi() % choices.size()]
		act_t = 0.0
		act_dur = {"look": 1.4, "preen": 2.6, "shake": 0.7, "stretch": 1.8, "caw": 1.6, "hop": 0.42, "settle": 1.0, "peck": 1.1}[act]
		if act == "hop":
			_hop_from = at
			var a := yaw + randf_range(-1.4, 1.4)
			var step := Vector3(sin(a), 0, cos(a)) * randf_range(0.12, 0.3) if ground else Vector3.ZERO
			at += step
			yaw = wrapf(yaw + randf_range(-1.6, 1.6), -PI, PI)
			_hop_t = 0.0
		if act == "caw" and on_caw.is_valid():
			on_caw.call(self)
	if act != "":
		act_t += delta
		if act_t >= act_dur:
			act = ""
			_next_act = randf_range(0.4, 2.8)
	# the head: snaps to a new look now and then and holds (a bird's head moves in quick jerks)
	_head_snap -= delta
	if _head_snap <= 0.0:
		_head_want = randf_range(-1.2, 1.2) if randf() < 0.75 else 0.0
		_head_snap = randf_range(0.35, 1.6)
	_head_yaw = lerpf(_head_yaw, _head_want, minf(1.0, delta * 18.0))
	# a hop: a little spring with the wings flicked open
	var lift := 0.0
	if _hop_t >= 0.0:
		_hop_t += delta
		var u := clampf(_hop_t / 0.42, 0.0, 1.0)
		lift = sin(PI * u) * 0.09
		global_position = _hop_from.lerp(at, u) + Vector3(0, lift, 0)
		if u >= 1.0:
			_hop_t = -1.0
	else:
		global_position = at
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, delta * 10.0))
	_pose_perched(lift)

func _pose_perched(lift: float) -> void:
	var tt := Time.get_ticks_msec() * 0.001 + get_instance_id() % 97
	var breath := sin(tt * 3.1) * 0.025
	var u := clampf(act_t / maxf(act_dur, 0.01), 0.0, 1.0)
	var bell := sin(PI * u)
	var body_p := -0.12 + breath           # (it sits a little forward)
	var body_r := 0.0
	var neck_p := 0.0
	var head_p := 0.0
	var head_y := _head_yaw
	var head_r := 0.0
	var tail_p := 0.05 + breath
	var tail_y := sin(tt * 1.7) * 0.05
	var wl := 0.0                  # a wing opening (stretch, hop, shake)
	var wr := 0.0
	match act:
		"look":
			head_r = sin(u * TAU) * 0.35 * bell        # the cocked head of a raven eyeing something
		"peck":
			var k := absf(sin(u * TAU * 1.5))
			body_p += 0.75 * bell
			neck_p = 0.6 * k
			head_p = 0.5 * k
			head_y = 0.0
		"preen":
			head_y = (1.0 if int(get_instance_id()) % 2 == 0 else -1.0) * 2.4 * bell
			neck_p = 0.5 * bell
			head_p = 0.6 * bell + sin(u * 40.0) * 0.12 * bell
			wl = 0.12 * bell if head_y > 0 else 0.0
			wr = 0.12 * bell if head_y < 0 else 0.0
		"shake":
			body_r = sin(u * 60.0) * 0.18 * bell
			wl = 0.18 * bell
			wr = 0.18 * bell
			tail_y = sin(u * 70.0) * 0.4 * bell
		"stretch":
			if int(get_instance_id()) % 2 == 0:
				wl = 0.9 * bell
			else:
				wr = 0.9 * bell
			tail_p -= 0.3 * bell
		"caw":
			# three caws, the body pumping forward and the head thrown up with each
			var c := absf(sin(u * PI * 3.0))
			body_p += 0.25 * c
			neck_p = -0.35 * c
			head_p = -0.5 * c
			head_y *= 0.3
			tail_p += 0.4 * c
			wl = 0.06 * c
			wr = 0.06 * c
		"hop":
			wl = 0.45 * bell
			wr = 0.45 * bell
			body_p -= 0.25 * bell
			tail_p += 0.4 * bell
		"settle":
			body_r = sin(u * TAU * 2.0) * 0.06
			wl = 0.1 * bell
			wr = 0.1 * bell
	_pose(body_p, body_r, neck_p, head_p, head_y, head_r, tail_p, tail_y, 0.0)
	_wing("L", _fold * (1.0 - wl), 0.0, 0.0)
	_wing("R", _fold * (1.0 - wr), 0.0, 0.0)

# ------------------------------------------------------------------ in the air
func _takeoff(delta: float) -> void:
	var u := clampf(t / TAKEOFF_T, 0.0, 1.0)
	# a crouch, then a spring up and off with the wings thrown open and beating hard
	var crouch := sin(PI * clampf(u / 0.35, 0.0, 1.0)) * (1.0 if u < 0.35 else 0.0)
	_fold = move_toward(_fold, 0.0, delta * 6.0)
	_flap_ph += delta * TAU * 7.0
	var up := smoothstep(0.3, 1.0, u)
	var p := fa + Vector3(0, up * 0.9 - crouch * 0.05, 0) + (_curve(0.08) - fa) * up * 0.4
	global_position = p
	var dir := (_curve(0.12) - fa)
	dir.y = 0
	if dir.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 8.0))
	_pose(-0.4 * up - 0.2 * crouch, 0.0, -0.2 * up, 0.0, 0.0, 0.0, 0.3 * up, 0.0, 0.3 * up)
	var a := sin(_flap_ph) * 1.0
	_wing("L", _fold, a, 0.0)
	_wing("R", _fold, a, 0.0)
	if u >= 1.0:
		state = "fly"
		t = 0.0
		_prev = global_position

func _fly(delta: float) -> void:
	var u := clampf(t / fdur, 0.0, 1.0)
	# ease out at the end: the last LAND_T seconds slow into the flare
	var land_start := maxf(0.0, 1.0 - LAND_T / fdur)
	var eu := u
	if u > land_start:
		var k := (u - land_start) / maxf(1.0 - land_start, 0.001)
		eu = land_start + (1.0 - land_start) * (1.0 - (1.0 - k) * (1.0 - k)) * 0.999 + (1.0 - land_start) * 0.001 * k
	var p := _curve(eu)
	global_position = p
	_vel = (p - _prev) / maxf(delta, 0.001)
	_prev = p
	var flat := Vector2(_vel.x, _vel.z)
	var landing := u > land_start
	state = "land" if landing else "fly"
	if flat.length() > 0.3:
		var want := atan2(flat.x, flat.y)
		var dy := angle_difference(rotation.y, want)
		rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * 5.0))
		_bank = lerpf(_bank, clampf(dy * 2.2, -0.7, 0.7), minf(1.0, delta * 4.0))
	_pitch = lerpf(_pitch, clampf(-_vel.y * 0.12, -0.5, 0.5), minf(1.0, delta * 4.0))
	_fold = move_toward(_fold, 0.0, delta * 4.0)
	# flapping, gliding when it comes down (and at a whim), quick back-beats in the flare
	var glide := 0.0
	if not landing:
		glide = smoothstep(-0.2, -1.6, _vel.y) * 0.85 + (0.6 if fmod(t + float(get_instance_id() % 7), 4.0) > 2.9 else 0.0)
	_flap_ph += delta * TAU * (4.2 if not landing else 6.5)
	var a := sin(_flap_ph) * lerpf(0.95, 0.12, clampf(glide, 0.0, 1.0)) + 0.18 * clampf(glide, 0.0, 1.0)
	var sweep := 0.0
	var body_p := 0.25 + _pitch
	var tail_p := 0.0
	var legs := 0.0
	if landing:
		var k := (u - land_start) / maxf(1.0 - land_start, 0.001)
		var fl := smoothstep(0.2, 0.75, k)
		body_p = lerpf(body_p, -0.95, fl)         # body up into the flare
		sweep = -0.45 * fl                          # wings forward
		a = lerpf(a, 0.35 + sin(_flap_ph) * 0.55, fl)
		tail_p = 0.6 * fl                           # tail fanned down
		legs = 0.9 * fl
		if u >= 1.0:
			perch_at(fb, rotation.y, ground)
			act = "settle"
			act_t = 0.0
			act_dur = 1.0
			return
	rotation.z = 0.0
	_pose(body_p, -_bank, -0.15, 0.1, 0.0, 0.0, tail_p, 0.0, legs)
	_wing("L", _fold, a, sweep)
	_wing("R", _fold, a, sweep)

# ------------------------------------------------------------------ the pose
## The trunk: body pitch (+ forward/down) and roll, neck and head pitch, head yaw and roll, tail pitch (+ down) and
## yaw, the legs swung forward (landing) / tucked (flying).
func _pose(body_p: float, body_r: float, neck_p: float, head_p: float, head_y: float, head_r: float, tail_p: float, tail_y: float, legs: float) -> void:
	_bone_d("body", Basis(Vector3.FORWARD, body_r) * Basis(Vector3.RIGHT, body_p))
	_bone_d("neck", Basis(Vector3.RIGHT, neck_p))
	_bone_d("head", Basis(Vector3.UP, head_y) * Basis(Vector3.FORWARD, head_r) * Basis(Vector3.RIGHT, head_p))
	_bone_d("tail", Basis(Vector3.UP, tail_y) * Basis(Vector3.RIGHT, tail_p))
	_bone_d("legs", Basis(Vector3.RIGHT, -legs * 0.8 + (0.9 if state == "fly" else 0.0)))

## A wing: fold 0 spread .. 1 folded along the flank; a = beat (+ up), sweep (+ back).
func _wing(side: String, fold: float, a: float, sweep: float) -> void:
	var s := 1.0 if side == "L" else -1.0
	# spread: the mesh's own wings rise ~40 degrees at the shoulder; level them, then beat and sweep
	var o1 := Basis(Vector3.UP, s * sweep) * Basis(Vector3.BACK, s * (a - 0.55))
	var o2 := Basis(Vector3.BACK, s * (0.3 + a * 0.35))
	var o3 := Basis(Vector3.BACK, s * (0.15 + a * 0.5))
	# folded: the arm swept back and down along the flank, the forearm folded forward on it, the hand back again
	var f1 := Basis(Vector3.UP, s * 1.45) * Basis(Vector3.BACK, s * -1.05)
	var f2 := Basis(Vector3.UP, s * -2.5)
	var f3 := Basis(Vector3.UP, s * 2.3)
	var k := smoothstep(0.0, 1.0, fold)
	_bone_d("w%s1" % side, _blend(o1, f1, k))
	_bone_d("w%s2" % side, _blend(o2, f2, k))
	_bone_d("w%s3" % side, _blend(o3, f3, k))

static func _blend(a: Basis, b: Basis, k: float) -> Basis:
	return Basis(a.get_rotation_quaternion().slerp(b.get_rotation_quaternion(), k))

## A bone turned by d, a rotation in the bird's own frame (x its left, y up, z forward) applied where the bone rests in
## its parent's (turned) frame: local = parent rest^-1 * d * rest.
func _bone_d(nm: String, d: Basis) -> void:
	if sk == null or not _b.has(nm):
		return
	var i: int = _b[nm]
	var rp: Basis = _rp[i]
	var rg: Basis = _rg[i]
	sk.set_bone_pose_rotation(i, (rp.inverse() * d * rg).get_rotation_quaternion())

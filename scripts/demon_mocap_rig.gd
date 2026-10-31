extends "res://scripts/knight_mocap_rig.gd"
## The Demon on his motion-captured body (assets/models/demon_mocap.glb, tools/blender/demon/prep_demon_mocap.py;
## built by Demon.build_mocap): the shared mocap system with his own moving parts laid over the clips every frame:
##  - the wings (bones wL1..4 / wR1..4 from Spine01: root, arm, leading finger, lower finger) are posed in code,
##    springs lagging behind what the moment wants: folded and breathing at rest, half open and flexing with the
##    walk, spread and swept back at a run or a charge, thrown wide for a roar or a cast, a big beat on the slams
##    and stomps, sagging in death (_wings);
##  - the tail (tail1..7 from the hips, re-skinned along its own centreline) is a heavy chain of springs: held off
##    the ground, swaying with his gait, swinging the other way round a turn, lashing on attacks, jolted by each
##    footfall, limp when he dies (_tail);
##  - the loincloth's front flap (hA1..3, KnightMocapRig's lock naming) swings like the Wraith's robe (_cloth);
##  - the footfalls (each foot's bone landing) are counted (thump: the hero shakes the camera a touch);
##  - death: after the clip's fall the lava cools (the shader's "cool", meta "demon_mats") and embers rise (meta
##    "death_embers"); all reset on revive. Nothing here is synced: every peer runs it from the same pose.

var wing_bones := {}          # "L"/"R" -> [root, arm, finger_out, finger_low] bone indices
var wing_sx := {}             # side -> +1 if the wing is on the rig's +x
var wing_sp := {}             # side -> {fold: [x, v], lift: [x, v], sweep: [x, v]}
var tail_bones: Array = []
var tail_p: Array = []        # per bone pitch spring [x, v] (about the rig's x)
var tail_y: Array = []        # per bone yaw spring [x, v] (about the rig's y)
var tail_lash := 0.0
var bone_conj := {}           # bone -> [rest local rotation, rest rotation in the rig frame]
var bone_rest_pos := {}
var _st := {}
var _atk_prev := -1.0
var _hit_prev2 := 0.0
var foot_bones: Array = []
var foot_y: Array = [0.0, 0.0]
var foot_vy: Array = [0.0, 0.0]
var thump := 0.0              # a footfall this frame (its weight), read and cleared by the hero
var dead_t := -1.0
var cloth_kick := 0.0
var lash_sign := 1.0
var _gait := 0.0

const TAIL_LIFT := [-0.6, -0.3, -0.08, 0.05, 0.08, 0.05, 0.0]     # the resting pitch per bone (rad, - = swung back)
const TAIL_BEND := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]            # yaw laid on the curl at rest

func setup(root_node: Node3D, skeleton: Skeleton3D, joints: Dictionary) -> void:
	super(root_node, skeleton, joints)
	for side in ["L", "R"]:
		var ids := []
		for k in range(1, 5):
			var i := skel.find_bone("w%s%d" % [side, k])
			if i >= 0:
				ids.append(i)
		if ids.size() == 4:
			wing_bones[side] = ids
			var o: Vector3 = R * (rest_g[ids[2]] as Transform3D).origin
			wing_sx[side] = 1.0 if o.x > 0.0 else -1.0
			wing_sp[side] = {"fold": [0.0, 0.0], "lift": [0.0, 0.0], "sweep": [0.0, 0.0]}
	for k in range(1, 12):
		var i := skel.find_bone("tail%d" % k)
		if i < 0:
			break
		tail_bones.append(i)
		tail_p.append([TAIL_LIFT[mini(k - 1, TAIL_LIFT.size() - 1)], 0.0])
		tail_y.append([0.0, 0.0])
	for i in skel.get_bone_count():
		bone_conj[i] = [skel.get_bone_rest(i).basis.get_rotation_quaternion(), rest_rot(i)]
		bone_rest_pos[i] = skel.get_bone_rest(i).origin
	for n in ["LeftFoot", "RightFoot"]:
		foot_bones.append(skel.find_bone(n))

func sync_pose(st: Dictionary) -> void:
	_st = st
	super(st)

## A turn in the rig's frame laid on a bone, over its rest (the parent's pose carries down the chain).
func _set_rig_rot(b: int, q: Quaternion) -> void:
	var c: Quaternion = bone_conj[b][1]
	skel.set_bone_pose_position(b, bone_rest_pos[b])
	skel.set_bone_pose_rotation(b, (bone_conj[b][0] as Quaternion) * (c.inverse() * q * c))

static func _spring(s: Array, target: float, stiff: float, damp: float, dt: float, lim := 3.0) -> float:
	s[1] += ((target - s[0]) * stiff - s[1] * damp) * dt
	s[0] = clampf(s[0] + s[1] * dt, -lim, lim)
	return s[0]

## The cloth, the wings and the tail, in place of the hair locks (called by knight_rig.gd's sync every frame).
func _sway_hair(fwd_speed: float, side_speed: float, t: float, dt: float) -> void:
	var yaw := global_rotation.y
	var yaw_v := wrapf(yaw - _last_yaw, -PI, PI) / dt
	_last_yaw = yaw
	if absf(yaw_v) > 30.0:
		yaw_v = 0.0
	var a: float = _st.get("atk", -1.0)
	var style := str(_st.get("style", ""))
	var hit: float = _st.get("hit", 0.0)
	var die: bool = float(_st.get("dead", 0.0)) > 0.0
	var g := clampf(speed / 4.8, 0.0, 1.6)
	var started := a >= 0.0 and _atk_prev < 0.0
	var struck := hit > _hit_prev2 + 0.3
	_atk_prev = a
	_hit_prev2 = hit
	if die:
		dead_t = 0.0 if dead_t < 0.0 else dead_t + dt
		_cooling(dt)
	elif dead_t >= 0.0:
		dead_t = -1.0
		_cooling(dt)
	_gait += dt * (2.2 + 4.5 * clampf(g, 0.0, 1.2)) * clampf(g * 3.0, 0.0, 1.0)
	_footfalls(dt, g)
	_wings(a, style, hit, die, g, t, dt, started, struck, yaw_v)
	_tail(a, style, die, g, t, dt, started, struck, yaw_v, fwd_speed, side_speed)
	_cloth(g, t, dt, die, fwd_speed, side_speed, yaw_v)

## Each foot's bone coming down hard while he moves: a thump (the camera), a jolt into the cloth and the tail.
func _footfalls(dt: float, g: float) -> void:
	thump = 0.0
	if foot_bones.size() < 2 or dt <= 0.0:
		return
	for k in 2:
		var b: int = foot_bones[k]
		if b < 0:
			continue
		var y: float = (X * skel.get_bone_global_pose(b).origin).y
		var vy: float = (y - foot_y[k]) / dt
		if foot_y[k] == 0.0:
			vy = 0.0
		if foot_vy[k] < -0.5 and vy > -0.08 and y < 0.2 and g > 0.12:
			thump = maxf(thump, clampf(-foot_vy[k] * 0.4, 0.3, 1.0))
			cloth_kick += 0.12
			for i in tail_p.size():
				tail_p[i][1] += 0.35 * (0.5 + 0.1 * i)
		foot_y[k] = y
		foot_vy[k] = vy

## The wings: what the moment wants (spread 0..1, the lift of the whole wing, how far it sweeps back), chased by
## springs, laid on the four bones of each side.
func _wings(a: float, style: String, hit: float, die: bool, g: float, t: float, dt: float, started: bool, struck: bool, yaw_v: float) -> void:
	if wing_bones.is_empty():
		return
	var want_fold := 0.0
	var want_lift := sin(t * 0.8) * 0.035 + sin(t * 0.37 + 1.0) * 0.02       # breathing
	var want_sweep := 0.0
	var stiff := 14.0
	var beat := 0.0        # an impulse this frame
	if die:
		want_fold = 0.1
		want_lift = -0.35
		want_sweep = 0.1
		stiff = 5.0
	elif a >= 0.0:
		var imp := Anim.impact_at(style)
		var big := style in ["slam", "swipe3", "stomp", "cleave"]
		match style:
			"cast":
				want_fold = 1.0
				want_lift = 0.3 + 0.15 * sin(a * PI)
			"roar", "scream":
				want_fold = 1.0
				want_lift = 0.4
			_:
				want_fold = 1.0 if big else 0.75
				# wings go up with the wind-up and beat down through the blow
				want_lift = (0.55 if big else 0.25) * smoothstep(0.0, imp * 0.8, a) if a < imp else (-0.3 if big else -0.12)
				stiff = 24.0 if a < imp + 0.25 else 14.0
	elif hit > 0.3:
		want_fold = 0.4
		want_lift = -0.1
	elif g > 0.62:
		# running: spread, swept back by the air, flexing with the stride
		want_fold = 1.0
		want_sweep = 0.12 + 0.18 * clampf((g - 0.6) / 0.6, 0.0, 1.0)
		want_lift = 0.12 + sin(_gait) * 0.06
	elif g > 0.1:
		want_fold = 0.45
		want_lift = sin(_gait) * 0.08
	else:
		want_fold = 0.12
	if struck:
		beat = -0.9
	if started and not (style in ["slam", "swipe3", "stomp", "cleave"]):
		beat += 0.4
	var turn := clampf(yaw_v * 0.05, -0.12, 0.12)
	for side in wing_bones.keys():
		var sp: Dictionary = wing_sp[side]
		var sx: float = wing_sx[side]
		if beat != 0.0:
			sp["lift"][1] += beat * 3.0
		var fold := _spring(sp["fold"], want_fold, stiff * 0.7, 4.2, dt, 1.2)
		var lift := _spring(sp["lift"], want_lift, stiff * 1.4, 4.0, dt, 1.0)
		var sweep := _spring(sp["sweep"], want_sweep - turn * sx, 10.0, 3.5, dt, 0.6)
		var closed := 1.0 - clampf(fold, 0.0, 1.0)
		var ids: Array = wing_bones[side]
		# the root: folded, the wing sweeps round behind him and droops; lifted, the whole wing rises
		var q1 := Quaternion(Vector3.UP, -sx * (0.45 * closed + sweep)) * Quaternion(Vector3.BACK, sx * (lift - 0.1 * closed))
		_set_rig_rot(ids[0], q1)
		# the arm folds back and in
		var q2 := Quaternion(Vector3.UP, -sx * 0.3 * closed) * Quaternion(Vector3.BACK, sx * (0.3 * closed + 0.3 * lift))
		_set_rig_rot(ids[1], q2)
		# the fingers close toward the arm, the membrane gathering between them
		var q3 := Quaternion(Vector3.BACK, -sx * (0.55 * closed - 0.45 * lift)) * Quaternion(Vector3.UP, -sx * 0.15 * closed)
		_set_rig_rot(ids[2], q3)
		var q4 := Quaternion(Vector3.BACK, -sx * (0.3 * closed - 0.2 * lift)) * Quaternion(Vector3.UP, sx * 0.3 * closed)
		_set_rig_rot(ids[3], q4)

## The tail: a chain of springs (pitch and yaw per bone, the end looser than the root).
func _tail(a: float, style: String, die: bool, g: float, t: float, dt: float, started: bool, struck: bool, yaw_v: float, fwd_speed: float, side_speed: float) -> void:
	var n := tail_bones.size()
	if n == 0:
		return
	if started:
		lash_sign = -lash_sign
		tail_lash = 1.0
		for i in n:
			tail_y[i][1] += lash_sign * (1.4 + 0.45 * i)
			if style in ["slam", "swipe3", "stomp", "cleave"]:
				tail_p[i][1] += -1.2 - 0.3 * i
	if struck:
		for i in n:
			tail_p[i][1] += 1.5 + 0.3 * i
	tail_lash = maxf(tail_lash - dt * 1.5, 0.0)
	var sway_amp := 0.03 + 0.12 * clampf(g, 0.0, 1.0)
	var turn := clampf(yaw_v * 0.22, -0.7, 0.7)
	var limp := smoothstep(0.3, 1.4, dead_t) if dead_t >= 0.0 else 0.0
	for i in n:
		var d := float(i) / maxf(n - 1, 1)
		var lift: float = TAIL_LIFT[mini(i, TAIL_LIFT.size() - 1)]
		# the heavy tail hangs toward the ground: at speed it streams out behind and rises a little
		var want_p: float = lift - 0.22 * clampf(g, 0.0, 1.2) * (0.3 + d) + sin(t * 1.1 + d * 2.0) * 0.03 * (1.0 - g)
		var want_y: float = TAIL_BEND[mini(i, TAIL_BEND.size() - 1)] + sin(_gait * 0.5 - d * 2.4) * sway_amp * (0.3 + d) + sin(t * 0.7 + d * 3.0) * 0.04
		want_y += turn * (0.4 + 0.8 * d)        # swings out the other way round a turn
		want_y -= clampf(side_speed * 0.05, -0.25, 0.25) * (0.3 + d)
		if limp > 0.0:
			want_p = lerpf(want_p, 0.3 + 0.2 * d, limp)
			want_y = lerpf(want_y, 0.0, limp)
		var stiff := (34.0 - 3.2 * i) * (1.0 - 0.7 * limp)
		var damp := (4.8 - 0.35 * i) * (1.0 + 1.5 * limp)
		var p := _spring(tail_p[i], want_p, stiff, damp, dt, 1.3)
		var y := _spring(tail_y[i], want_y, stiff * 0.9, damp, dt, 1.1)
		_set_rig_rot(tail_bones[i], Quaternion(Vector3.UP, y) * Quaternion(Vector3.RIGHT, p))

## The loincloth's front flap: kicked forward by the stride, pressed back a little by the air, never into the legs.
func _cloth(g: float, t: float, dt: float, die: bool, fwd_speed: float, side_speed: float, yaw_v: float) -> void:
	var n := hair_bones.size()
	if n == 0:
		return
	if hair_ang.size() != n:
		hair_ang.resize(n); hair_ang.fill(0.0)
		hair_vel.resize(n); hair_vel.fill(0.0)
		hair_side.resize(n); hair_side.fill(0.0)
		hair_side_vel.resize(n); hair_side_vel.fill(0.0)
	cloth_kick = lerpf(cloth_kick, 0.0, 1.0 - exp(-dt * 8.0))
	var limp := smoothstep(0.3, 1.4, dead_t) if dead_t >= 0.0 else 0.0
	for i in n:
		var d: int = hair_key[i][1]
		var ph := float(hair_key[i][0]) * 1.9
		var gust := (sin(t * 1.1 + ph) * 0.6 + sin(t * 2.3 + ph * 1.3) * 0.4) * 0.025 * (1.0 - 0.6 * clampf(g, 0.0, 1.0))
		var kick := (sin(_gait + 0.6) * 0.12 * clampf(g * 1.5, 0.0, 1.0) + cloth_kick) * (0.5 + 0.5 * d)
		var tx := kick + gust - clampf(fwd_speed * 0.02, 0.0, 0.08) * (0.6 + 0.3 * d)
		tx *= 1.0 - limp
		var tz := (clampf(side_speed * 0.04 - yaw_v * 0.03, -0.2, 0.2) + sin(t * (2.1 + d) + ph) * 0.012) * (0.6 + 0.3 * d) * (1.0 - limp)
		var stiff := 30.0 - d * 7.0
		var damp := 4.4 - d * 0.8
		hair_vel[i] += ((tx - hair_ang[i]) * stiff - hair_vel[i] * damp) * dt
		hair_ang[i] = clampf(hair_ang[i] + hair_vel[i] * dt, -0.1, 0.6)     # back is into the legs
		hair_side_vel[i] += ((tz - hair_side[i]) * stiff - hair_side_vel[i] * damp) * dt
		hair_side[i] = clampf(hair_side[i] + hair_side_vel[i] * dt, -0.4, 0.4)
		var b: int = hair_bones[i]
		_set_rig_rot(b, Quaternion.from_euler(Vector3(hair_ang[i], 0.0, hair_side[i])))

## Dead: once he has fallen the lava cools to cinders and embers rise off him; alive again, it all comes back.
func _cooling(_dt: float) -> void:
	var cool := smoothstep(1.3, 3.4, dead_t) if dead_t >= 0.0 else 0.0
	if has_meta("demon_mats"):
		for m in get_meta("demon_mats"):
			(m as ShaderMaterial).set_shader_parameter("cool", cool)
	if has_meta("death_embers"):
		var e := get_meta("death_embers") as GPUParticles3D
		if e != null:
			var want := dead_t >= 0.9 and dead_t < 4.5
			if want != e.emitting:
				e.emitting = want
	if has_meta("eye_light"):
		var l := get_meta("eye_light") as OmniLight3D
		if l != null:
			l.light_energy = 0.5 * (1.0 - cool)

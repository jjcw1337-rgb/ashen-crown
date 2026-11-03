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
var tail_bend_y: Array = []   # the model's own curl: each bone's yaw and pitch from the one before (rig frame), undone to straighten it
var tail_bend_p: Array = []
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
var flick_t := 3.0            # seconds to the tail's next flick or curl
var wag_ph := 0.0             # the wag oscillator's phase
var tail_up: Array = [0.0, 0.0]   # the whole tail's lift at speed (an underdamped spring)
var _gait := 0.0
var ease_speed := 0.0         # the ground speed the clips are blended by, eased in
var _ease_t := -1.0
var _ease_gp := Vector3.INF
var _vis_yaw := INF           # the body's lagging turn
var _vis_t := -1.0

const TAIL_LIFT := [-0.5, -0.28, -0.14, -0.08, -0.04, -0.02, 0.0]   # the resting pitch per bone (rad, - = swung back; -1.06 in all: low, the outer half just over the ground)
const LIFT_W := [0.35, 0.25, 0.15, 0.1, 0.08, 0.05, 0.02]           # how a lift of the whole tail is shared down the chain

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
	# the tail's curl as modelled: the turn of each bone from the one before, so the sim can straighten it out
	var prev_dir := Vector3.DOWN
	for k in tail_bones.size():
		var b: int = tail_bones[k]
		var dir: Vector3
		if k + 1 < tail_bones.size():
			dir = R * ((rest_g[tail_bones[k + 1]] as Transform3D).origin - (rest_g[b] as Transform3D).origin)
		else:
			dir = R * ((rest_g[b] as Transform3D).basis * Vector3.UP)   # the last bone's own length (Blender bones point along +y)
		dir = dir.normalized()
		var yaw0 := atan2(prev_dir.x, prev_dir.z)
		var yaw1 := atan2(dir.x, dir.z)
		var flat0 := Vector2(prev_dir.x, prev_dir.z).length()
		var flat1 := Vector2(dir.x, dir.z).length()
		tail_bend_y.append(wrapf(yaw1 - yaw0, -PI, PI) if flat0 > 0.2 and flat1 > 0.2 else 0.0)
		tail_bend_p.append(atan2(dir.y, flat1) - atan2(prev_dir.y, flat0))
		prev_dir = dir
	for n in ["LeftFoot", "RightFoot"]:
		foot_bones.append(skel.find_bone(n))

func sync_pose(st: Dictionary) -> void:
	_st = st
	# a heavy start: his ground speed, as the clips see it, eases in over ~0.3 s (and drops at once when he stops),
	# so standing crossfades into the stride instead of snapping
	if not st.has("speed") and is_inside_tree():
		var t: float = st.get("time", 0.0)
		var dt := clampf(t - _ease_t, 0.0, 0.1) if _ease_t >= 0.0 else 0.0
		_ease_t = t
		var gp := global_position
		var meas := 0.0
		if _ease_gp != Vector3.INF and dt > 0.0:
			var dd := gp - _ease_gp
			dd.y = 0.0
			meas = dd.length() / dt
			if meas >= 15.0:
				meas = 0.0
		_ease_gp = gp
		if dt > 0.0:
			ease_speed = lerpf(ease_speed, meas, 1.0 - exp(-dt * (5.0 if meas > ease_speed else 14.0)))
		st = st.duplicate()
		st["speed"] = ease_speed
	super(st)
	# the body turns heavily: it lags the hero's snap turn and catches up in a beat (visual only). Not while
	# he attacks or casts: then the body shows the aim (the pointer's direction) at once, so a blow never
	# looks as if it leaves sideways out of a body still turning
	if body_root != null and dead_t < 0.0:
		var yaw := global_rotation.y if is_inside_tree() else rotation.y
		var dt2 := clampf(float(st.get("time", 0.0)) - _vis_t, 0.0, 0.1) if _vis_t >= 0.0 else 0.0
		_vis_t = float(st.get("time", 0.0))
		var acting := float(st.get("atk", -1.0)) >= 0.0
		if _vis_yaw == INF or dt2 <= 0.0 or acting:
			_vis_yaw = yaw
		else:
			_vis_yaw = lerp_angle(_vis_yaw, yaw, 1.0 - exp(-dt2 * 9.0))
		var lag := clampf(wrapf(_vis_yaw - yaw, -PI, PI), -0.6, 0.6)
		body_root.rotation.y += lag

## The run's planted foot moves at Demon.RUN_SPEED; between the crawl and the run the blend's natural speed runs
## from the walk's to the run's, so the clips play at his real ground speed (slower than Meshy's, heavy).
func _rate(v: float, pts: Array) -> float:
	if v < 0.3 or pts.size() < 4:
		return super(v, pts)
	var nat: float
	if v <= pts[1]:
		nat = pts[1]
	elif v <= pts[2]:
		nat = lerpf(pts[1], pts[3], (v - pts[1]) / maxf(pts[2] - pts[1], 0.01))
	elif v <= pts[3]:
		nat = pts[3]
	else:
		nat = pts[3] + (v - pts[3]) * 0.4    # toward the charge clip, a little quicker on its feet
	return clampf(v / maxf(nat, 0.3), 0.5, 1.8)

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
	if style == "fists" and a >= 0.0 and not die:
		_fists_pose(a, t)
	_gait += dt * (2.2 + 4.5 * clampf(g, 0.0, 1.2)) * clampf(g * 3.0, 0.0, 1.0)
	_footfalls(dt, g)
	_wings(a, style, hit, die, g, t, dt, started, struck, yaw_v)
	_tail(a, style, die, g, t, dt, started, struck, yaw_v, fwd_speed, side_speed)
	_cloth(g, t, dt, die, fwd_speed, side_speed, yaw_v)

## Molten Fists over its clip (Demon.SHOTS "fists" snaps into the chamber and holds it): through the gather he
## rears back, chest out and head up, twisting into it with a strained tremble; through the blow he folds down
## over his fists, driving them at the ground ahead, then straightens with the recovery. Turns in the rig frame
## (-z ahead: a negative turn about x bends forward) laid over whatever the clip has the bone doing.
var _fist_bones := {}
func _fists_pose(a: float, t: float) -> void:
	if _fist_bones.is_empty():
		for n in ["Spine02", "Spine01", "Spine", "Head", "LeftArm", "RightArm"]:
			_fist_bones[n] = skel.find_bone(n)
	var imp := Anim.impact_at("fists")
	var gather := smoothstep(0.02, 0.17, a) * (1.0 - smoothstep(imp - 0.08, imp - 0.01, a))
	var drive := smoothstep(imp - 0.06, imp + 0.01, a) * (1.0 - smoothstep(imp + 0.12, 0.97, a))
	var trem := gather * smoothstep(0.15, imp - 0.1, a) * (sin(t * 53.0) * 0.6 + sin(t * 37.0) * 0.4) * 0.018
	_rig_turn("Spine02", Quaternion(Vector3.RIGHT, 0.13 * gather - 0.3 * drive) * Quaternion(Vector3.UP, 0.15 * gather))
	_rig_turn("Spine01", Quaternion(Vector3.RIGHT, 0.08 * gather - 0.17 * drive + trem))
	_rig_turn("Spine", Quaternion(Vector3.RIGHT, 0.05 * gather - 0.1 * drive))
	_rig_turn("Head", Quaternion(Vector3.RIGHT, 0.16 * gather - 0.12 * drive))
	_rig_turn("LeftArm", Quaternion(Vector3.RIGHT, -0.26 * drive))
	_rig_turn("RightArm", Quaternion(Vector3.RIGHT, -0.26 * drive))

func _rig_turn(bone: String, q: Quaternion) -> void:
	var b: int = _fist_bones.get(bone, -1)
	if b < 0 or q.is_equal_approx(Quaternion.IDENTITY):
		return
	var gq: Quaternion = (R * skel.get_bone_global_pose(b).basis.orthonormalized()).get_rotation_quaternion()
	skel.set_bone_pose_rotation(b, skel.get_bone_pose_rotation(b) * (gq.inverse() * q * gq))

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
			# the stride's phase locks to the feet (left lands at 0, right at PI), so the tail's sway keeps time
			var want_ph := 0.0 if k == 0 else PI
			_gait += wrapf(want_ph - fmod(_gait, TAU), -PI, PI) * 0.5
			for i in tail_p.size():
				tail_p[i][1] += (0.3 + 0.3 * clampf(g, 0.0, 1.6)) * (0.5 + 0.12 * i)
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
			"wrath_roar":
				# the Crucible bursts open: flung wide and high, then held spread over the roar
				want_fold = 1.0
				want_lift = 0.55 if a < 0.6 else 0.35
				want_sweep = -0.15
				stiff = 30.0
			"crucible":
				# folded forward round him like a cocoon, hunched in, trembling with the heat
				want_fold = 0.55
				want_sweep = -1.05
				want_lift = 0.32 + sin(t * 23.0) * 0.012
				stiff = 18.0
			"icharge_wind":
				# drawn back and up, ready to drive
				want_fold = 0.8
				want_sweep = 0.25
				want_lift = 0.3
			"icharge_skid":
				# thrown forward to brake against the air
				want_fold = 1.0
				want_sweep = -0.45
				want_lift = 0.35
			"grip_haul":
				want_fold = 0.9
				want_sweep = 0.2
				want_lift = 0.2
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
		var sweep := _spring(sp["sweep"], want_sweep - turn * sx, 10.0, 3.5, dt, 1.2)
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

## The tail: a heavy chain of springs (pitch and yaw per bone, the end looser than the root), never still. It hangs
## low, the outer half just above the ground, and wags the whole time like a big cat's: a wag oscillator whose
## speed, size and axis (side to side, tilting toward diagonal) drift on slow noise, so the direction keeps changing
## and nothing repeats; the root sways moderately and the swing grows and lags down the chain, so the tip sweeps in
## an S. Every few seconds the tip flicks or curls on top. Moving, the stride's sway (phased to the footfalls) joins
## the wag, the modelled curl straightens out behind him, and the whole tail springs up (an underdamped lift that
## overshoots when he sets off) into a raised arc, bouncing on each footfall; it settles low again when he stops.
## The charge lifts it highest; a turn swings it out the other way; an attack lashes it.
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
	var moving := clampf(g * 2.5, 0.0, 1.0)          # 0 standing .. 1 walking and above
	var limp := smoothstep(0.3, 1.4, dead_t) if dead_t >= 0.0 else 0.0
	# the occasional flick of the tip (or a slow curl): an impulse into the outer bones, more often standing
	flick_t -= dt
	if flick_t <= 0.0 and limp == 0.0:
		flick_t = randf_range(2.5, 6.5) * (1.0 + moving)
		var curl := randf() < 0.45
		var sgn := -1.0 if randf() < 0.5 else 1.0
		for i in n:
			var d := float(i) / maxf(n - 1, 1)
			var reach := smoothstep(0.3, 1.0, d)
			if curl:
				tail_p[i][1] += -1.1 * reach       # the tip curls up, then settles
				tail_y[i][1] += sgn * 0.5 * reach
			else:
				tail_y[i][1] += sgn * (1.6 + 0.6 * randf()) * reach     # a sideways flick
	# the wag: its speed, size and axis drift on slow noise (two incommensurate sines each)
	var n_f := sin(t * 0.071 * TAU) * 0.6 + sin(t * 0.113 * TAU + 1.7) * 0.4
	var n_a := sin(t * 0.053 * TAU + 0.9) * 0.6 + sin(t * 0.097 * TAU + 2.8) * 0.4
	var n_x := sin(t * 0.041 * TAU + 2.2) * 0.6 + sin(t * 0.089 * TAU + 0.4) * 0.4
	var wag_f := 0.42 + 0.2 * n_f                       # Hz: a slow heavy wag, quicker now and then
	wag_ph += dt * wag_f * TAU * (1.0 + 0.35 * moving)
	var wag_a := (0.16 + 0.07 * n_a) * (1.0 - 0.35 * moving) * (1.0 - limp)
	var wag_axis := 0.5 * n_x                           # how far the wag tilts off level (diagonal, never vertical)
	# the whole tail's lift at speed, an underdamped spring so it springs up and overshoots as he sets off
	var want_up := (0.55 * clampf(g, 0.0, 1.0) + 0.25 * clampf((g - 1.1) / 0.5, 0.0, 1.0)) * (1.0 - limp)
	var up := _spring(tail_up, want_up, 11.0, 2.4, dt, 1.2)
	var turn := clampf(yaw_v * 0.16, -0.5, 0.5)
	var sway_amp := 0.05 + 0.12 * clampf(g, 0.0, 1.6)
	var breath := sin(t * 0.21 + 0.4) * 0.6 + sin(t * 0.137) * 0.4       # the slow lift and settle, standing
	# the model's curl opens as he moves: coiled a quarter at rest, straight out behind him at a run
	var straight := 0.25 + 0.75 * clampf(g / 0.9, 0.0, 1.0)
	for i in n:
		var d := float(i) / maxf(n - 1, 1)
		var lift: float = TAIL_LIFT[mini(i, TAIL_LIFT.size() - 1)]
		var lw: float = LIFT_W[mini(i, LIFT_W.size() - 1)]
		var uncurl_y: float = -tail_bend_y[i] * straight
		var uncurl_p: float = tail_bend_p[i] * straight * 0.8 if i > 0 else 0.0
		# the wag: the root sways, the swing grows and lags down the chain (an S by the tip)
		var lag := d * 3.2
		var grow := 0.35 + 0.95 * d
		var wag := sin(wag_ph - lag) * wag_a * grow
		var wag_y := wag * cos(wag_axis)
		# its vertical part lifts from the hang and comes back down, never below the rest
		var wag_p := -absf(wag * sin(wag_axis)) - (0.5 + 0.5 * sin(wag_ph * 0.5 - lag * 0.7 + 1.0)) * 0.06 * grow * (1.0 - moving)
		# the stride's sway (phased to the footfalls, lagging down the chain) and bounce
		var gait_y := sin(_gait - 0.4 - d * 1.9) * sway_amp * (0.25 + 0.75 * d) * moving
		var gait_p := sin(_gait * 2.0 - d * 1.5) * 0.03 * (0.3 + d) * moving
		var want_p := lift + wag_p + gait_p - up * lw * 1.6 - breath * 0.08 * lw * (1.0 - moving) + uncurl_p
		var want_y := wag_y + gait_y + uncurl_y
		want_y += turn * (0.25 + 0.5 * d)       # swings out the other way round a turn
		want_y -= clampf(side_speed * 0.05, -0.25, 0.25) * (0.3 + d)
		if limp > 0.0:
			want_p = lerpf(want_p, 0.3 + 0.2 * d, limp)
			want_y = lerpf(want_y, 0.0, limp)
		var stiff := (30.0 - 2.8 * i) * (1.0 - 0.7 * limp)
		var damp := (4.6 - 0.32 * i) * (1.0 + 1.5 * limp)
		var p := _spring(tail_p[i], want_p, stiff, damp, dt, 1.4)
		var y := _spring(tail_y[i], want_y, stiff * 0.9, damp, dt, 1.1)
		# never down into the ground past its rest hang, and the root never swings in between the legs
		if limp == 0.0:
			var floor_p := lift + uncurl_p + 0.1 * (0.4 + 0.6 * d)
			if p > floor_p:
				tail_p[i][0] = floor_p
				tail_p[i][1] = minf(tail_p[i][1], 0.0)
				p = floor_p
			if i < 2 and absf(y) > 0.55:
				tail_y[i][0] = signf(y) * 0.55
				y = tail_y[i][0]
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
	if has_meta("crust"):
		cool = maxf(cool, float(get_meta("crust")))     # Wrath of the Pit's Crucible: an obsidian crust
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

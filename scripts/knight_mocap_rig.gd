extends "res://scripts/knight_rig.gd"
## The armoured knight on his motion-captured body (assets/models/knight_mocap.glb: the Meshy crusader on
## a 24-bone humanoid skeleton, with Meshy library clips; tools/blender/knight/prep_knight_mocap.py),
## built by Knight.build_mocap.
##
## Two layers, blended per bone every frame (sync_pose, called by Anim.pose with the same pose dictionary
## every other body gets, so the hero, co-op puppets and tools all drive it the same way):
##  1. motion capture: an AnimationTree blends idle / walk / run / fast run by ground speed (the clips'
##     playback rate follows the speed too, so the feet don't slide), relaxed or battle-ready by how far
##     the weapon is drawn ("draw"), and plays the death clip
##  2. the game's own procedural moves (Anim: the combo, Holy Slam, casts, the block, hit wobble): Anim
##     poses the familiar 13 proxy joints (J, Knight.ARMORED_LAYOUT); each proxy's turn from its rest is
##     laid onto the matching skeleton bone (its rest turned into the game's arms-down stance, B_ref), the
##     spine sharing the torso's turn over its three bones.
## While he only moves, layer 1 owns every bone. An attack, a cast, the block or the draw fades layer 2 in
## over the upper body (and over the legs too for attacks with footwork), and out again after.
## Gear rides followers of the real bones (J "at_hand_r" etc.; grip_r, grip_l, mount_l, chest are their children).
## The cloak hangs on hA1..hC3 and swings like the old cape (knight_rig.gd _sway_hair).

var tree: AnimationTree
var body_root: Node3D
var followers := {}           # bone name -> [bone index, follower Node3D, proxy name]
var X := Transform3D()        # rig frame <- skeleton frame
var R := Basis()              # its rotation
var s_scale := 1.0            # skeleton units per metre... inverse (Meshy's armature is in centimetres: 0.01)
var B_ref := {}               # bone index -> global basis (rig frame) in the game's rest stance
var rest_g := {}              # bone index -> rest global transform (skeleton frame)
var parent_of := {}           # bone index -> parent index
var order: Array = []         # bones, parents first
var map := {}                 # bone name -> proxy name
var J: Dictionary
var hips_rest := Vector3.ZERO
var hips_pose_rest := Vector3.ZERO
var w_up := 0.0               # how much of the upper body the procedural moves own (0..1)
var w_low := 0.0              # ... and of the legs
var speed := 0.0              # smoothed ground speed (m/s)
var shot := {}                # whole-body clip for an attack style: {style, clip, t0, release, t1}; see sync_pose
var w_shot := 0.0
var w_side := 0.0
var w_aimwalk := 0.0          # shooting on the move: the aimed walk (shot "walk_clip")
var w_reach := 0.0            # on the move, the drawing arm reaching to the quiver (shot "reach")
var yaw_now := 0.0            # the body's side-on turn (degrees)
var hover := 0.0              # metres the body floats above the ground (the Wraith), with a slow drift
var hover_now := 0.0
var hover_base := 0.0
## A body that floats instead of walking (the Wraith, Wraith.build_mocap): the clips are never retimed to a ground
## speed, the glide is procedural (sync_pose -> _float: the body leans into its travel and banks into turns,
## bobs, lifts a little at speed), the robe panels hA..hF are cloth in the wind (_sway_robe), and the death
## rears up, then sinks into the ground dissolving (the spectral materials' phase_amt, meta "spectral_mats").
var float_mode := false
var lean_now := 0.0           # pitch (rad, + = forward) and roll the glide puts on the body
var bank_now := 0.0
var _yaw_prev := INF
var _speed_prev := 0.0
var death_t := -1.0           # seconds since he died (float mode), -1 alive
var _hit_prev := 0.0
var robe_out: Array = []      # per robe bone: the panel's outward direction (rig frame, horizontal), from its rest
var robe_kick := Vector2.ZERO # a jolt into the robe (rig frame, horizontal), from a hit
var chain_last := {}          # the wrist chains' hands: last position and velocity (rig frame), per lock
var chain_vel := {}
const FLOAT_LEAN := 0.2      # rad of forward lean at full glide
const FLOAT_BANK := 0.14      # rad of roll per rad/s of turn at full glide
const FLOAT_LIFT := 0.07      # extra height at full glide
const FLOAT_PIVOT := 1.05     # the lean turns about this height (his hips)

## A shot's clip time for the attack's progress a: piecewise along shot "keys" [[a, t], ...] (the release key at
## Anim's impact), or the old three-point squeeze (t0, release, t1).
static func shot_time(shot: Dictionary, a: float) -> float:
	if shot.has("keys"):
		var ks: Array = shot["keys"]
		for i in range(1, ks.size()):
			if a <= float(ks[i][0]):
				var k0: Array = ks[i - 1]
				var k1: Array = ks[i]
				return lerpf(float(k0[1]), float(k1[1]), clampf((a - float(k0[0])) / maxf(float(k1[0]) - float(k0[0]), 0.0001), 0.0, 1.0))
		return float(ks[ks.size() - 1][1])
	var imp := Anim.impact_at(str(shot["style"]))
	return lerpf(shot["t0"], shot["release"], a / imp) if a < imp else lerpf(shot["release"], shot["t1"], (a - imp) / (1.0 - imp))

## A piecewise weight [[a, w], ...] at a.
static func curve_at(pts: Array, a: float) -> float:
	if pts.is_empty() or a < float(pts[0][0]):
		return 0.0
	for i in range(1, pts.size()):
		if a <= float(pts[i][0]):
			var p0: Array = pts[i - 1]
			var p1: Array = pts[i]
			return lerpf(float(p0[1]), float(p1[1]), smoothstep(float(p0[0]), float(p1[0]), a))
	return float(pts[pts.size() - 1][1])
var rel_pts: Array = []       # the blend spaces' clip speeds (from Knight.build_mocap's opts)
var com_pts: Array = []
var hilt_bone := -1           # the bone the scabbard rides (the hips)
var hilt_local := Vector3.ZERO  # the hilt's centre in that bone's frame (skeleton units)
var _last_st_t := -1.0
var _last_gp := Vector3.INF
var _state := ""            # the death transition's state ("" until the first frame sends one)

const UPPER := ["Spine", "Spine01", "Spine02", "neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const LOWER := ["Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
## attacks whose footwork the procedural move owns (steps, leaps, spins)
const FOOTWORK := ["swipe1", "swipe2", "swipe3", "cleave", "over", "back", "side", "thrust", "slam", "leap", "spin"]
## the clips' own ground speeds (m/s, measured from the planted foot), as in the blend spaces
const RELAXED_TIP := -38.0    # degrees the sword tips down while the motion capture owns the arm
const RELAXED_PTS := [0.0, 0.55, 4.25]
const COMBAT_PTS := [0.0, 0.6, 4.25]

## Sets up the conversions (works before the rig is in the tree).
func setup(root_node: Node3D, skeleton: Skeleton3D, joints: Dictionary) -> void:
	body_root = root_node
	skel = skeleton
	J = joints
	map = {"Hips": "hips", "Spine02": "torso", "Head": "head", "RightArm": "sh_r", "RightForeArm": "el_r",
		"RightHand": "hand_r", "LeftArm": "sh_l", "LeftForeArm": "el_l", "LeftHand": "hand_l",
		"RightUpLeg": "leg_r", "RightLeg": "knee_r", "LeftUpLeg": "leg_l", "LeftLeg": "knee_l"}
	X = _rel(skel)
	s_scale = X.basis.get_scale().x
	R = X.basis.orthonormalized()
	for i in skel.get_bone_count():
		parent_of[i] = skel.get_bone_parent(i)
	var todo: Array = range(skel.get_bone_count())
	while not todo.is_empty():
		for i in todo.duplicate():
			var p: int = parent_of[i]
			if p < 0 or rest_g.has(p):
				var local := skel.get_bone_rest(i)
				rest_g[i] = local if p < 0 else (rest_g[p] as Transform3D) * local
				order.append(i)
				todo.erase(i)
	# the game's rest stance: arms and legs straight down, spine and head upright
	for i in order:
		var nm := skel.get_bone_name(i)
		var B: Basis = R * (rest_g[i] as Transform3D).basis.orthonormalized()
		var want := Vector3.ZERO
		if nm.contains("Arm") or nm.contains("Hand") or nm.ends_with("UpLeg") or nm.ends_with("Leg"):
			want = Vector3.DOWN
		elif nm.begins_with("Spine") or nm == "neck":
			want = Vector3.UP
		if want != Vector3.ZERO:
			var dir := _bone_dir(i)
			if dir.length() > 0.001:
				B = Basis(Quaternion(dir.normalized(), want)) * B
		B_ref[i] = B
	_find_hilt()
	hips_rest = (J["hips"] as Node3D).position
	hips_pose_rest = skel.get_bone_rest(skel.find_bone("Hips")).origin

## The bone's rest rotation in the rig frame (for the cloak's swing).
func rest_rot(i: int) -> Quaternion:
	return (R * (rest_g[i] as Transform3D).basis.orthonormalized()).get_rotation_quaternion()

## A node's transform relative to this rig (no need to be in the tree).
func _rel(n: Node3D) -> Transform3D:
	var t := Transform3D()
	var c: Node = n
	while c != null and c != self:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t

## A bone's direction (rig frame) at rest: toward its main child (a hand: along its forearm).
func _bone_dir(i: int) -> Vector3:
	var o := (rest_g[i] as Transform3D).origin
	for c in skel.get_bone_children(i):
		var cn := skel.get_bone_name(c)
		if _is_lock(cn) or cn == "headfront":
			continue
		return R * ((rest_g[c] as Transform3D).origin - o)
	var p: int = parent_of[i]
	if p >= 0:
		return R * (o - (rest_g[p] as Transform3D).origin)
	return Vector3.ZERO

static func _is_lock(n: String) -> bool:
	return n.length() == 3 and n.begins_with("h") and n.unicode_at(1) >= 65 and n.unicode_at(1) <= 90

## Called by Anim.pose with this frame's pose.
func sync_pose(st: Dictionary) -> void:
	if tree == null or skel == null:
		return
	var t: float = st.get("time", 0.0)
	var dt := clampf(t - _last_st_t, 0.0, 0.1) if _last_st_t >= 0.0 else 0.0
	if fixed_dt > 0.0:
		dt = fixed_dt
	_last_st_t = t
	var m: float = st.get("move", 0.0)
	var a: float = st.get("atk", -1.0)
	var dead: float = st.get("dead", 0.0)
	var drawn: float = clampf(float(st.get("draw", 1.0)), 0.0, 1.0)
	# ground speed: measured from how far he went, else from the pose's "move" (tools, puppets in place)
	var v := m * 4.8
	if st.has("speed"):
		v = st["speed"]
	elif is_inside_tree() and dt > 0.0:
		var gp := global_position
		if _last_gp != Vector3.INF:
			var d := gp - _last_gp
			d.y = 0.0
			var meas := d.length() / dt
			if meas < 15.0 and (meas > 0.05 or m < 0.05):
				v = meas
		_last_gp = gp
	speed = lerpf(speed, v, 1.0 - exp(-dt * 10.0)) if dt > 0.0 else v
	# --- layer 1: motion capture
	var rp: Array = rel_pts if not rel_pts.is_empty() else RELAXED_PTS
	var cp: Array = com_pts if not com_pts.is_empty() else COMBAT_PTS
	tree.set("parameters/relaxed/blend_position", minf(speed, float(rp[rp.size() - 1])))
	tree.set("parameters/combat/blend_position", minf(speed, float(cp[cp.size() - 1])))
	tree.set("parameters/mix/blend_amount", drawn)
	tree.set("parameters/speed/scale", _rate(speed, cp if drawn > 0.5 else rp))
	# the whole-body attack clip (the archer's shot): its draw squeezed into the attack before the release frame,
	# the follow-through after it, so the arrow leaves on Anim.impact_at's frame at any attack speed
	var die := dead > 0.0
	var shooting: bool = not shot.is_empty() and a >= 0.0 and st.get("style", "") == shot["style"] and not die
	# stepping while he shoots: the aimed walk carries the whole body instead of the standing shot
	var stepping: bool = shooting and speed > 0.45 and shot.has("walk_clip")
	if not shot.is_empty():
		var kk := 1.0 - exp(-dt * 18.0) if dt > 0.0 else 1.0
		w_aimwalk = lerpf(w_aimwalk, 1.0 if stepping else 0.0, kk)
		if shot.has("walk_clip"):
			tree.set("parameters/aimwalk_mix/blend_amount", w_aimwalk)
			tree.set("parameters/aimwalk_speed/scale", clampf(speed / float(shot.get("walk_speed", 0.82)), 0.6, 2.4))
		if shot.has("reach_clip"):
			w_reach = curve_at(shot.get("reach", []), a) if stepping else lerpf(w_reach, 0.0, kk)
			tree.set("parameters/reach_mix/blend_amount", w_reach)
			if stepping:
				tree.set("parameters/reach_seek/seek_request", shot_time({"keys": shot["reach_keys"]}, a))
		if stepping:
			shooting = false
		w_shot = lerpf(w_shot, 1.0 if shooting else 0.0, kk)
		if shooting:
			tree.set("parameters/shot_seek/seek_request", shot_time(shot, a))
		tree.set("parameters/shot_mix/blend_amount", w_shot)
		# an archer stands side-on to his mark: the body turns so the bow arm points where the shot goes; his
		# battle-ready stand ("combat_idle", aiming) is side-on too, so it turns the same way while he stands
		if body_root != null:
			var stand := drawn * (1.0 - clampf(speed / 0.8, 0.0, 1.0)) * (1.0 - w_aimwalk) if shot.get("idle_side", false) else 0.0
			w_side = lerpf(w_side, maxf(w_shot, stand), kk)
			# the shot's clip and the aiming stand may each want their own turn
			var want_yaw: float = float(shot.get("yaw", 0.0)) if shooting else float(shot.get("stand_yaw", shot.get("yaw", 0.0))) * stand
			yaw_now = lerpf(yaw_now, want_yaw, kk * 0.6)
			body_root.rotation.y = PI + deg_to_rad(yaw_now)
	var want_state := "dead" if die else "alive"
	if want_state != _state:
		_state = want_state
		tree.set("parameters/state/transition_request", want_state)
	tree.advance(dt)
	# a body that floats (the Wraith): risen off the ground, drifting slowly, sinking when it dies
	if hover > 0.0 and body_root != null:
		if hover_now == 0.0 and hover_base == 0.0:
			hover_base = body_root.position.y
		if float_mode:
			_float(st, t, dt, die)
		else:
			var want_h := 0.0 if die else hover + sin(t * 1.7) * 0.035 + sin(t * 0.63) * 0.02
			hover_now = lerpf(hover_now, want_h, 1.0 - exp(-dt * (2.0 if die else 6.0)))
			body_root.position.y = hover_base + hover_now
	# --- layer 2: the procedural moves, by weight
	var style: String = st.get("style", "")
	# the draw / holster (WeaponCarry) is acting only while the blade is on its way (0 = put away, 1 = in guard)
	var drawing := drawn > 0.001 and drawn < 0.999
	var acting: bool = (a >= 0.0 and not shooting and not stepping) or float(st.get("block", 0.0)) > 0.05 or drawing or float(st.get("hit", 0.0)) > 0.3
	var up_t := 0.0 if die else (1.0 if acting else 0.0)
	var low_t := 0.0 if die else (1.0 if (a >= 0.0 and FOOTWORK.has(style)) else 0.0)
	var k := 1.0 - exp(-dt * 14.0) if dt > 0.0 else 1.0
	w_up = lerpf(w_up, up_t, k)
	w_low = lerpf(w_low, low_t, k)
	if w_up > 0.002 or w_low > 0.002:
		_apply_procedural()
	_reach_hilt(st)
	sync()   # the cloak (knight_rig.gd)
	_follow()

## Playback rate so the planted foot moves at the ground speed (between clips, by the blend).
func _rate(v: float, pts: Array) -> float:
	if v < 0.3 or float_mode:
		return 1.0
	var nat: float = pts[pts.size() - 1]
	if v <= pts[1]:
		nat = pts[1]
	else:
		for i in range(2, pts.size()):
			if v <= pts[i]:
				nat = lerpf(pts[i - 1], pts[i], (v - pts[i - 1]) / (pts[i] - pts[i - 1]))
				break
	return clampf(v / maxf(nat, 0.3), 0.6, 1.8)

## Lays the proxies' turns onto the skeleton, blended by w_up / w_low.
func _apply_procedural() -> void:
	var proc_g := {}
	var torso_q := _rel(J["torso"]).basis.orthonormalized()
	var head_q := _rel(J["head"]).basis.orthonormalized()
	for i in order:
		var nm := skel.get_bone_name(i)
		var p: int = parent_of[i]
		var g: Basis
		if map.has(nm):
			var Q := _rel(J[map[nm]]).basis.orthonormalized()
			g = Q * (B_ref[i] as Basis)
		elif p >= 0 and proc_g.has(p):
			g = (proc_g[p] as Basis) * ((B_ref[p] as Basis).inverse() * (B_ref[i] as Basis))
		else:
			g = B_ref[i]
		# the spine shares the torso's turn: a third, two thirds, all (Spine02 carries the torso); the neck half the head's
		if nm == "Spine" or nm == "Spine01" or nm == "neck":
			var full := (head_q if nm == "neck" else torso_q) * (B_ref[i] as Basis)
			var from_q := g.get_rotation_quaternion()
			g = Basis(from_q.slerp(full.get_rotation_quaternion(), 0.34 if nm == "Spine" else (0.67 if nm == "Spine01" else 0.5)))
		proc_g[i] = g
		var w := w_up if UPPER.has(nm) else (w_low if LOWER.has(nm) else 0.0)
		if w <= 0.002:
			continue
		# global (rig) -> local: pose_local = parent_global^-1 * global, both in the skeleton frame
		var gs := R.inverse() * g
		var lq: Quaternion
		if p >= 0:
			var ps := R.inverse() * (proc_g[p] as Basis)
			lq = (ps.inverse() * gs).get_rotation_quaternion()
		else:
			lq = gs.get_rotation_quaternion()
		var cur := skel.get_bone_pose_rotation(i)
		skel.set_bone_pose_rotation(i, cur.slerp(lq, w))
	# the hips' crouch, lunge and lift from the procedural move
	if w_low > 0.002:
		var hb := skel.find_bone("Hips")
		var d := ((J["hips"] as Node3D).position - hips_rest) / maxf(s_scale, 1e-6)
		var cur_p := skel.get_bone_pose_position(hb)
		skel.set_bone_pose_position(hb, cur_p.lerp(hips_pose_rest + R.inverse() * d, w_low))

## Puts the gear followers on their bones (in the proxies' frame, so the old grip offsets fit).
func _follow() -> void:
	if not shot.is_empty() or hover > 0.0:
		X = _rel(skel)        # the body may be turned (the archer's side-on stance) or floating (the Wraith)
		R = X.basis.orthonormalized()
	for nm in followers.keys():
		var f: Array = followers[nm]
		var i: int = f[0]
		var g := skel.get_bone_global_pose(i)
		var nd: Node3D = f[1]
		var basis := (R * g.basis.orthonormalized()) * (B_ref[i] as Basis).inverse()
		if nm == "RightHand":
			# a relaxed hand (motion capture) carries the blade tipped down, not pointing ahead
			basis = basis * Basis(Vector3.RIGHT, deg_to_rad(RELAXED_TIP) * (1.0 - w_up))
		nd.transform = Transform3D(basis.orthonormalized(), X * g.origin)

## The scabbard hilt's centre (its "Hilt" surface, prep_knight_mocap.py), kept in the hips' frame so it can be
## found wherever the hips are this frame.
func _find_hilt() -> void:
	hilt_bone = skel.find_bone("Hips")
	if hilt_bone < 0:
		return
	for mi in skel.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si)
			if mat == null or mat.resource_name != "Hilt":
				continue
			var verts: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var c := Vector3.ZERO
			for v in verts:
				c += v
			c /= verts.size()
			# the mesh is in metres; the skeleton (under Meshy's 0.01-scaled armature) in centimetres
			c /= maxf(s_scale, 1e-6)
			hilt_local = skel.get_bone_global_rest(hilt_bone).affine_inverse() * c
			return
	hilt_bone = -1

## The cross-body draw (WeaponCarry, Anim's "knight" draw motion): around the grab the right hand is steered
## onto the real hilt at his left hip by a two-bone IK on the arm, blended in and out, so he takes hold of the
## sword where it hangs (the procedural keys alone stop at his chest on this body).
func _reach_hilt(st: Dictionary) -> void:
	if hilt_bone < 0 or str(st.get("draw_motion", "")) != "knight" or float(st.get("atk", -1.0)) >= 0.0:
		return
	var dr: float = st.get("draw", 1.0)
	if dr <= 0.12 or dr >= 0.6:
		return
	var w := Anim.kf(dr, [[0.12, 0.0], [0.3, 1.0], [0.42, 1.0], [0.6, 0.0]])
	if w <= 0.001:
		return
	var ua := skel.find_bone("RightArm")
	var fa := skel.find_bone("RightForeArm")
	var ha := skel.find_bone("RightHand")
	if ua < 0 or fa < 0 or ha < 0:
		return
	skel.force_update_all_bone_transforms()
	var Gu := skel.get_bone_global_pose(ua)
	var Gf := skel.get_bone_global_pose(fa)
	var Gh := skel.get_bone_global_pose(ha)
	var T: Vector3 = skel.get_bone_global_pose(hilt_bone) * hilt_local
	var S := Gu.origin
	var E := Gf.origin
	var H := Gh.origin
	var a := (E - S).length()
	var b := (H - E).length()
	var to_t := T - S
	var d := clampf(to_t.length(), absf(a - b) + 0.01, a + b - 0.01)
	var dir := to_t.normalized()
	# the elbow stays on the side it bends to now (out and back)
	var pole := (E - S) - dir * (E - S).dot(dir)
	if pole.length() < 0.001:
		pole = Vector3.UP.cross(dir)
	pole = pole.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var E2 := S + dir * a * cos_a + pole * a * sqrt(1.0 - cos_a * cos_a)
	var q1 := Quaternion((E - S).normalized(), (E2 - S).normalized())
	var H1 := S + q1 * (H - S)
	var q2 := Quaternion((H1 - E2).normalized(), (S + dir * d - E2).normalized())
	var up_g := Basis(q1) * Gu.basis.orthonormalized()
	var fo_g := Basis(q2 * q1) * Gf.basis.orthonormalized()
	var par_g := skel.get_bone_global_pose(skel.get_bone_parent(ua)).basis.orthonormalized()
	var up_l := (par_g.inverse() * up_g).get_rotation_quaternion()
	var fo_l := (up_g.inverse() * fo_g).get_rotation_quaternion()
	skel.set_bone_pose_rotation(ua, skel.get_bone_pose_rotation(ua).slerp(up_l, w))
	skel.set_bone_pose_rotation(fa, skel.get_bone_pose_rotation(fa).slerp(fo_l, w))

# ---------------------------------------------------------------- the float (the Wraith)
## The glide: no steps, the body carried on its travel. It leans into the direction it moves by its speed (and a
## touch more as it accelerates, a touch back as it brakes), banks into turns, lifts a little at speed and bobs
## slowly. Dead, it rears up with the clip's throw of the arms, hangs, then sinks into the ground dissolving.
func _float(st: Dictionary, t: float, dt: float, die: bool) -> void:
	var yaw := global_rotation.y if is_inside_tree() else rotation.y
	var yaw_v := 0.0
	if _yaw_prev != INF and dt > 0.0:
		yaw_v = wrapf(yaw - _yaw_prev, -PI, PI) / dt
	_yaw_prev = yaw
	if absf(yaw_v) > 30.0:
		yaw_v = 0.0
	var g := clampf(speed / 4.8, 0.0, 1.15)
	var accel := (speed - _speed_prev) / dt if dt > 0.0 else 0.0
	_speed_prev = speed
	var want_lean := FLOAT_LEAN * g + clampf(accel * 0.025, -0.14, 0.1)
	var want_bank := -clampf(yaw_v, -3.0, 3.0) * FLOAT_BANK * (0.25 + 0.75 * g)
	var want_h := hover + FLOAT_LIFT * g + sin(t * 1.7) * 0.035 + sin(t * 0.63) * 0.02 + sin(t * 2.6) * 0.012 * g
	var k_lean := 1.0 - exp(-dt * 4.5)
	var k_h := 1.0 - exp(-dt * 6.0)
	if die:
		death_t = 0.0 if death_t < 0.0 else death_t + dt
		var rise := smoothstep(0.0, 0.45, death_t)
		var sink := smoothstep(0.85, 2.7, death_t)
		sink = sink * sink
		want_h = hover + 0.4 * rise - 1.45 * sink
		want_lean = -0.3 * rise + 0.55 * sink
		want_bank = 0.0
		k_lean = 1.0 - exp(-dt * 3.0)
		k_h = 1.0 - exp(-dt * 5.0)
		_death_look(smoothstep(0.7, 2.4, death_t), rise)
	elif death_t >= 0.0:
		# back from the dead: whole again
		death_t = -1.0
		_death_look(0.0, 0.0)
	lean_now = lerpf(lean_now, want_lean, k_lean)
	bank_now = lerpf(bank_now, want_bank, k_lean)
	hover_now = lerpf(hover_now, want_h, k_h)
	body_root.rotation.x = lean_now
	body_root.rotation.z = bank_now
	# the lean and bank pivot at his hips, not at the ground
	var piv := Vector3(0.0, FLOAT_PIVOT, 0.0)
	body_root.position = Vector3(0.0, hover_base + hover_now, 0.0) + piv - body_root.basis * piv
	body_root.visible = death_t < 3.2
	# a hit jolts the robe
	var hit: float = st.get("hit", 0.0)
	if hit > _hit_prev + 0.3:
		robe_kick += Vector2(0.0, 1.0) * 2.5    # back
	_hit_prev = hit

## The dissolve: the spectral materials thin to nothing (phase_amt), the eyes flare as he rears then go out, the
## hem's mist stops.
func _death_look(fade: float, rise: float) -> void:
	if has_meta("spectral_mats"):
		for m in get_meta("spectral_mats"):
			(m as ShaderMaterial).set_shader_parameter("phase_amt", fade)
	if has_meta("eye_light"):
		var l := get_meta("eye_light") as OmniLight3D
		if l != null:
			l.light_energy = 0.45 * (1.0 + 2.0 * rise) * (1.0 - fade)
	if has_meta("hem_mist"):
		var mist := get_meta("hem_mist") as GPUParticles3D
		if mist != null:
			mist.amount_ratio = clampf(1.0 - smoothstep(0.75, 0.95, fade), 0.0, 1.0)

## The robe panels (float mode) instead of the hair locks.
func _sway_hair(fwd_speed: float, side_speed: float, t: float, dt: float) -> void:
	if float_mode:
		_sway_robe(fwd_speed, side_speed, t, dt)
	else:
		super(fwd_speed, side_speed, t, dt)

## Six panels of three bones hang from the hips round the body (hA..hF). Each bone swings about the rig's x and z
## (in the bone's own frame through hair_conj, like the locks), toward a wanted horizontal push on its hanging tip:
## the air of his travel lifts the panels behind him out and back (they stream), presses the ones in front a little
## in, sweeps the side ones along; a turn drags every panel the other way round; a gust drifts them when he hangs
## still; a hit kicks them back; the ones lower down are looser, so the panel curves instead of turning like a board.
## Dying, they flare out as he rears, then go limp as he sinks.
func _sway_robe(fwd_speed: float, side_speed: float, t: float, dt: float) -> void:
	var n := hair_bones.size()
	if n == 0:
		return
	if hair_ang.size() != n:
		hair_ang.resize(n); hair_ang.fill(0.0)
		hair_vel.resize(n); hair_vel.fill(0.0)
		hair_side.resize(n); hair_side.fill(0.0)
		hair_side_vel.resize(n); hair_side_vel.fill(0.0)
	if robe_out.size() != n:
		robe_out.resize(n)
		var hb := skel.find_bone("Hips")
		var hp: Vector3 = R * (rest_g[hb] as Transform3D).origin
		for i in n:
			var root_i: int = hair_bones[i - (hair_key[i][1] as int)]
			var o: Vector3 = R * (rest_g[root_i] as Transform3D).origin - hp
			var o2 := Vector2(o.x, o.z)
			robe_out[i] = o2.normalized() if o2.length() > 0.001 else Vector2(0, 1)
	var yaw := global_rotation.y
	var yaw_v := wrapf(yaw - _last_yaw, -PI, PI) / dt
	_last_yaw = yaw
	if absf(yaw_v) > 30.0:
		yaw_v = 0.0
	# the air he moves through, in the rig frame (forward is -z)
	var wind := Vector2(-side_speed, fwd_speed) * hair_run
	var g := clampf(fwd_speed / 4.5, 0.0, 1.2)
	var dying := death_t >= 0.0
	var rise := smoothstep(0.0, 0.5, death_t) if dying else 0.0
	var limp := smoothstep(0.9, 2.2, death_t) if dying else 0.0
	robe_kick = robe_kick.lerp(Vector2.ZERO, 1.0 - exp(-dt * 9.0))
	var pend_g := {}        # pendulum chains: each bone's wanted global basis (skeleton frame), parents first
	var updated := false
	for i in n:
		var lock: int = hair_key[i][0]
		var d: int = hair_key[i][1]
		if lock >= 6:
			# the shackle chains (hG.., hH..): pendulums from the hands. They hang straight down whatever the arm
			# does, swing back against the hand's own motion and the air, and settle with the same springs
			var b: int = hair_bones[i]
			var p: int = parent_of[b]
			if not updated:
				skel.force_update_all_bone_transforms()
				updated = true
			var pg: Basis = pend_g[p] if pend_g.has(p) else skel.get_bone_global_pose(p).basis.orthonormalized()
			if d == 0:
				var hp := X * skel.get_bone_global_pose(p).origin
				var hv := Vector3.ZERO
				if chain_last.has(lock):
					hv = (hp - (chain_last[lock] as Vector3)) / dt
				chain_last[lock] = hp
				if hv.length() > 30.0:
					hv = Vector3.ZERO
				chain_vel[lock] = (chain_vel[lock] as Vector3).lerp(hv, 1.0 - exp(-dt * 14.0)) if chain_vel.has(lock) else hv
			var cv: Vector3 = chain_vel.get(lock, Vector3.ZERO)
			var ph2 := float(lock) * 2.3
			var Dc := (wind - Vector2(cv.x, cv.z) * 0.9) * 0.06 * (0.7 + 0.5 * d)
			Dc += Vector2(sin(t * 1.3 + ph2), cos(t * 1.7 + ph2)) * 0.02 * (0.5 + 0.5 * d)
			Dc += robe_kick * 0.2
			Dc *= 1.0 - limp * 0.5
			var txc := -Dc.y
			var tzc := Dc.x
			var stc := 26.0 - d * 5.0
			var dpc := 4.0 - d * 0.6
			hair_vel[i] += ((txc - hair_ang[i]) * stc - hair_vel[i] * dpc) * dt
			hair_ang[i] = clampf(hair_ang[i] + hair_vel[i] * dt, -0.9, 0.9)
			hair_side_vel[i] += ((tzc - hair_side[i]) * stc - hair_side_vel[i] * dpc) * dt
			hair_side[i] = clampf(hair_side[i] + hair_side_vel[i] * dt, -0.9, 0.9)
			var swing := Basis(Quaternion.from_euler(Vector3(hair_ang[i], 0.0, hair_side[i])))
			var g_des: Basis = R.inverse() * (swing * Basis(hair_conj[i][1] as Quaternion))
			pend_g[b] = g_des
			skel.set_bone_pose_position(b, hair_rest[i])
			skel.set_bone_pose_rotation(b, (pg.inverse() * g_des).get_rotation_quaternion())
			continue
		var o: Vector2 = robe_out[i]
		var tang := Vector2(-o.y, o.x)
		var ph := float(lock) * 1.9
		# the wanted push on this bone's tip (rig frame, horizontal; rad of swing)
		var along := wind.dot(o)        # + the air pushes this panel outward
		var across := wind.dot(tang)
		var lift := clampf(along * 0.05, -0.03, 0.095) * (0.6 + 0.7 * d)
		var sweep := clampf(across * 0.045, -0.1, 0.1) * (0.6 + 0.7 * d)
		var turn := clampf(yaw_v * 0.06, -0.15, 0.15) * (0.5 + 0.4 * d)
		var calm := 1.0 - 0.6 * clampf(g, 0.0, 1.0)
		var gust := (sin(t * 1.1 + ph) * 0.6 + sin(t * 2.3 + ph * 1.3) * 0.4) * (0.5 + 0.5 * sin(t * 0.31 + 0.7)) * 0.03 * calm * (0.6 + 0.5 * d)
		var flutter := sin(t * (2.6 + d * 1.5) + ph * 2.3 + d) * (0.008 + d * 0.009) * (0.4 + 0.8 * g)
		var D := o * (lift + gust + rise * 0.18 * (0.6 + 0.4 * d)) + tang * (sweep + turn + flutter) + robe_kick * 0.25 * (0.5 + 0.4 * d)
		D *= 1.0 - limp
		# front panels never swing in far (the body is there); behind, they stream freely
		var inward := -D.dot(o)
		if inward > 0.06:
			D += o * (inward - 0.06)
		var tx := -D.y
		var tz := D.x
		var stiff := (30.0 - d * 7.0) * (1.0 - 0.6 * limp)
		var damp := (4.4 - d * 0.9) * (1.0 + 1.5 * limp)
		var acc: float = (tx - hair_ang[i]) * stiff - hair_vel[i] * damp
		hair_vel[i] += acc * dt
		hair_ang[i] = clampf(hair_ang[i] + hair_vel[i] * dt, -0.55, 0.55)
		var acc2: float = (tz - hair_side[i]) * stiff - hair_side_vel[i] * damp
		hair_side_vel[i] += acc2 * dt
		hair_side[i] = clampf(hair_side[i] + hair_side_vel[i] * dt, -0.55, 0.55)
		var b: int = hair_bones[i]
		skel.set_bone_pose_position(b, hair_rest[i])
		var q := Quaternion.from_euler(Vector3(hair_ang[i], 0.0, hair_side[i]))
		if not hair_conj.is_empty():
			var c: Quaternion = hair_conj[i][1]
			q = (hair_conj[i][0] as Quaternion) * (c.inverse() * q * c)
		skel.set_bone_pose_rotation(b, q)

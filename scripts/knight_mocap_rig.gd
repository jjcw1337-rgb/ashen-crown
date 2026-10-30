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
	tree.set("parameters/relaxed/blend_position", minf(speed, 4.25))
	tree.set("parameters/combat/blend_position", minf(speed, 4.25))
	tree.set("parameters/mix/blend_amount", drawn)
	tree.set("parameters/speed/scale", _rate(speed, COMBAT_PTS if drawn > 0.5 else RELAXED_PTS))
	var die := dead > 0.0
	var want_state := "dead" if die else "alive"
	if want_state != _state:
		_state = want_state
		tree.set("parameters/state/transition_request", want_state)
	tree.advance(dt)
	# --- layer 2: the procedural moves, by weight
	var style: String = st.get("style", "")
	# the draw / holster (WeaponCarry) is acting only while the blade is on its way (0 = put away, 1 = in guard)
	var drawing := drawn > 0.001 and drawn < 0.999
	var acting := a >= 0.0 or float(st.get("block", 0.0)) > 0.05 or drawing or float(st.get("hit", 0.0)) > 0.3
	var up_t := 0.0 if die else (1.0 if acting else 0.0)
	var low_t := 0.0 if die else (1.0 if (a >= 0.0 and FOOTWORK.has(style)) else 0.0)
	var k := 1.0 - exp(-dt * 14.0) if dt > 0.0 else 1.0
	w_up = lerpf(w_up, up_t, k)
	w_low = lerpf(w_low, low_t, k)
	if w_up > 0.002 or w_low > 0.002:
		_apply_procedural()
	sync()   # the cloak (knight_rig.gd)
	_follow()

## Playback rate so the planted foot moves at the ground speed (between clips, by the blend).
func _rate(v: float, pts: Array) -> float:
	if v < 0.3:
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

class_name Lion
## The arena lion (A2's games): a Meshy model on a 20-bone quadruped skeleton made in Blender
## (sources/lion.blend: spine, neck, head, three bones a leg, a three-bone tail; skinned by distance
## along the surface). Unlike the Feral it has no baked animations: every frame `pose` turns the bones
## from the enemy's state. A trot in diagonal pairs that keeps pace with the ground covered, the head
## steady, the tail swinging; the pounce (the Feral AI's "feral_lunge": coil, leap with the forepaws
## reaching, land); the maul ("feral_swipe": rear, rake with the right paw, then a bite). Lions use the
## Feral's pack AI (circle, one lunges at a time, back off, dart in).

const GLB := "res://assets/models/monsters/lion.glb"
const SCALE := 1.3
## ground the trot covers per cycle, at the model's own scale
const STRIDE := 1.7

static func ok() -> bool:
	return ResourceLoader.exists(GLB)

## glb/sc: another quadruped on the same skeleton (the archer's wolf, rigged by rig_quadruped.py).
static func build(glb := GLB, sc := SCALE) -> Node3D:
	var root := Node3D.new()
	var body: Node3D = (load(glb) as PackedScene).instantiate()
	body.name = "Body"
	body.rotation.y = PI          # Blender's front (-Y) arrives facing +z; monsters face -z
	body.scale = Vector3.ONE * sc
	root.add_child(body)
	var sks := body.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return root
	var sk: Skeleton3D = sks[0]
	# per bone: index, rest rotation, and the model's side (X) and up (Y) axes in the bone's own frame,
	# so poses can be written as "swing about the side axis" whatever way Blender rolled each bone
	var info := {}
	for i in sk.get_bone_count():
		var g := sk.get_bone_global_rest(i).basis.orthonormalized()
		var gi := g.inverse()
		info[sk.get_bone_name(i)] = [i, sk.get_bone_rest(i).basis.get_rotation_quaternion(), (gi * Vector3.RIGHT).normalized(), (gi * Vector3.UP).normalized(), (gi * Vector3.BACK).normalized()]
	root.set_meta("lion", sk)
	root.set_meta("lion_bones", info)
	root.set_meta("lion_body", body)
	return root

## Turn a bone from its rest: ax about the model's side axis (+ tips the bone's end backward, toward
## the tail), ay about the up axis (+ swings it to the lion's left), az about the long axis.
static func _turn(sk: Skeleton3D, info: Dictionary, bone: String, ax: float, ay := 0.0, az := 0.0) -> void:
	if not info.has(bone):
		return
	var b: Array = info[bone]
	var q: Quaternion = b[1]
	if ax != 0.0:
		q = q * Quaternion(b[2], ax)
	if ay != 0.0:
		q = q * Quaternion(b[3], ay)
	if az != 0.0:
		q = q * Quaternion(b[4], az)
	sk.set_bone_pose_rotation(b[0], q)

static func pose(rig: Node3D, st: Dictionary, height: float) -> void:
	if not rig.has_meta("lion"):
		return
	var sk: Skeleton3D = rig.get_meta("lion")
	var info: Dictionary = rig.get_meta("lion_bones")
	var body: Node3D = rig.get_meta("lion_body")
	var t: float = st.get("time", 0.0)
	var mv := clampf(float(st.get("move", 0.0)), 0.0, 1.3)
	var style: String = st.get("style", "")
	var atk: float = st.get("atk", -1.0)
	var hit: float = st.get("hit", 0.0)
	if st.has("dead"):
		mv = 0.0
		atk = -1.0
	# the trot: phase grows 1.6 / height per metre covered
	var per_cycle := STRIDE * SCALE * 1.6 / maxf(height, 0.3)
	var u := fposmod(float(st.get("phase", 0.0)) / per_cycle, 1.0)
	var legs := {"l_f": 0.0, "r_b": 0.04, "r_f": 0.5, "l_b": 0.54}
	var a := {}
	for k in legs:
		var ang := TAU * (u + float(legs[k]))
		a[k] = [sin(ang) * 0.5 * mv, maxf(0.0, cos(ang)) * 0.9 * mv]
	var bob := absf(sin(TAU * u * 2.0)) * 0.035 * mv
	var spine_x := sin(TAU * u * 2.0) * 0.04 * mv + sin(t * 1.6) * 0.015
	var neck_x := -sin(TAU * u * 2.0) * 0.05 * mv + hit * 0.25
	var neck_y := sin(t * 0.7) * 0.18 * (1.0 - minf(mv, 1.0))
	var head_x := 0.0
	var tail_lift := -(0.25 + 0.35 * minf(mv, 1.0))
	var front := {"l": [-a["l_f"][0], a["l_f"][1], a["l_f"][1] * 0.5], "r": [-a["r_f"][0], a["r_f"][1], a["r_f"][1] * 0.5]}
	var hind := {"l": [-a["l_b"][0], -a["l_b"][1] * 0.8, a["l_b"][1] * 0.6], "r": [-a["r_b"][0], -a["r_b"][1] * 0.8, a["r_b"][1] * 0.6]}
	var chest_x := 0.0
	var lift_y := 0.0
	var swipe_y := 0.0
	if atk >= 0.0 and style == "feral_lunge":
		# the pounce: coil low, launch with the forepaws reaching and the hind legs thrown back, land
		var k := atk
		var coil := smoothstep(0.0, 0.3, k) * (1.0 - smoothstep(0.3, 0.38, k))
		var fly := smoothstep(0.3, 0.42, k) * (1.0 - smoothstep(0.62, 0.78, k))
		var land := smoothstep(0.62, 0.72, k) * (1.0 - smoothstep(0.8, 1.0, k))
		bob = -0.14 * coil + sin(clampf((k - 0.3) / 0.38, 0.0, 1.0) * PI) * 0.7 - 0.08 * land
		spine_x = 0.12 * coil - 0.1 * fly
		for s in ["l", "r"]:
			front[s] = [0.35 * coil - 1.05 * fly - 0.25 * land, 0.6 * coil - 0.35 * fly + 0.5 * land, 0.3 * coil]
			hind[s] = [-0.4 * coil + 0.9 * fly, 0.7 * coil - 0.5 * fly, -0.3 * coil + 0.3 * fly]
		neck_x = 0.15 * coil - 0.3 * fly + 0.1 * land
		head_x = -0.2 * fly
		tail_lift = -0.2 - 0.5 * fly
	elif atk >= 0.0 and style == "feral_swipe":
		# the maul: rear onto the haunches and rake with the right paw (impact ~0.32), then bite
		var k := atk
		var rear := smoothstep(0.0, 0.22, k) * (1.0 - smoothstep(0.42, 0.6, k))
		var rake := smoothstep(0.22, 0.34, k)
		var bite := smoothstep(0.5, 0.66, k) * (1.0 - smoothstep(0.75, 1.0, k))
		lift_y = 0.38 * rear
		chest_x = -0.6 * rear
		front["r"] = [lerpf(-1.9 * rear, 0.4, rake * rear), 0.5 * rear - 0.3 * rake * rear, -0.3 * rear]
		front["l"] = [-0.6 * rear, 0.7 * rear, 0.2 * rear]
		swipe_y = lerpf(0.5, -0.4, rake) * rear
		hind["l"] = [0.45 * rear, -0.5 * rear, 0.35 * rear]
		hind["r"] = [0.45 * rear, -0.5 * rear, 0.35 * rear]
		neck_x = -0.15 * rear + 0.45 * bite
		head_x = -0.25 * bite + 0.35 * bite * smoothstep(0.62, 0.66, k)
		neck_y = 0.0
	body.position.y = bob + lift_y
	_turn(sk, info, "hips", spine_x * 0.5 - chest_x * 0.3)
	_turn(sk, info, "spine", spine_x)
	_turn(sk, info, "chest", spine_x * 0.6 + chest_x)
	_turn(sk, info, "neck", neck_x, neck_y)
	_turn(sk, info, "head", head_x, neck_y * 0.5)
	for s in ["l", "r"]:
		var f: Array = front[s]
		_turn(sk, info, "arm_" + s, f[0], swipe_y if s == "r" else 0.0)
		_turn(sk, info, "forearm_" + s, f[1])
		_turn(sk, info, "paw_" + s, f[2])
		var h: Array = hind[s]
		_turn(sk, info, "thigh_" + s, h[0])
		_turn(sk, info, "shin_" + s, h[1])
		_turn(sk, info, "foot_" + s, h[2])
	var sway := sin(t * 2.2)
	_turn(sk, info, "tail1", tail_lift, sway * 0.35)
	_turn(sk, info, "tail2", 0.15, sin(t * 2.2 - 0.6) * 0.4)
	_turn(sk, info, "tail3", 0.1, sin(t * 2.2 - 1.2) * 0.5)

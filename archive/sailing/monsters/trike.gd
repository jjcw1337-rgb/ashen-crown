class_name Trike
## The Verdant Isle's triceratops (Data.ENEMIES "trike", the mother, and "trike_baby"): Meshy models on the
## quadruped skeleton of tools/blender/act1/rig_quadruped.py (the bear's bone names), so the bear's heavy walk
## (Bear.pose) carries them; their own moves are laid over it here instead of the bear's rearing:
##  - "bear_roar": the bellow: the head swung low and up, the frill shown, the jaw wide, a stamp of the forefeet
##  - "bear_maul": the horn toss: the head dropped with the horns forward (0..MAUL_HIT), then hooked up and round
## The AI is the bear's (enemy.gd _bear_*): wander, bellow on noticing you, charge, toss.

const GLB := {"trike": "res://assets/models/monsters/dino/triceratops.glb", "trike_baby": "res://assets/models/monsters/dino/baby_trike.glb"}
const MAUL_HIT := 0.45

static func ok(kind: String) -> bool:
	return GLB.has(kind) and ResourceLoader.exists(GLB[kind])

static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	var body: Node3D = ResCache.inst(GLB[kind])
	body.name = "Body"
	body.rotation.y = PI
	root.add_child(body)
	var sks := body.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return root
	var sk: Skeleton3D = sks[0]
	var info := {}
	for i in sk.get_bone_count():
		var g := sk.get_bone_global_rest(i).basis.orthonormalized()
		var gi := g.inverse()
		info[sk.get_bone_name(i)] = [i, sk.get_bone_rest(i).basis.get_rotation_quaternion(), (gi * Vector3.RIGHT).normalized(), (gi * Vector3.UP).normalized(), (gi * Vector3.BACK).normalized()]
	# Bear.pose drives the walk through these
	root.set_meta("bear", sk)
	root.set_meta("bear_bones", info)
	root.set_meta("bear_body", body)
	root.set_meta("bear_base", body.transform)
	root.set_meta("trike", kind)
	return root

static func pose(rig: Node3D, st: Dictionary, height: float) -> void:
	if not rig.has_meta("bear"):
		return
	var style: String = st.get("style", "")
	var atk: float = st.get("atk", -1.0)
	var mine := atk >= 0.0 and style in ["bear_roar", "bear_maul"] and not st.has("dead")
	var walk_st := st
	if mine:
		walk_st = st.duplicate()
		walk_st["style"] = ""
		walk_st["atk"] = -1.0
	Bear.pose(rig, walk_st, height)
	if not mine:
		return
	var sk: Skeleton3D = rig.get_meta("bear")
	var info: Dictionary = rig.get_meta("bear_bones")
	var t: float = st.get("time", 0.0)
	var k := atk
	if style == "bear_roar":
		var low := smoothstep(0.0, 0.25, k) * (1.0 - smoothstep(0.3, 0.45, k))
		var up := smoothstep(0.3, 0.45, k) * (1.0 - smoothstep(0.75, 0.95, k))
		Bear._turn(sk, info, "neck", 0.35 * low - 0.3 * up, sin(t * 3.0) * 0.15 * up)
		Bear._turn(sk, info, "head", 0.25 * low - 0.25 * up + sin(t * 11.0) * 0.04 * up)
		Bear._turn(sk, info, "jaw", 0.05 + 0.6 * up)
		var stamp := absf(sin(k * TAU * 2.0)) * 0.35 * up
		Bear._turn(sk, info, "arm_l", -stamp)
		Bear._turn(sk, info, "arm_r", -0.35 * up + stamp)
	else:
		var drop := smoothstep(0.0, MAUL_HIT, k) * (1.0 - smoothstep(MAUL_HIT, MAUL_HIT + 0.12, k))
		var hook := smoothstep(MAUL_HIT, MAUL_HIT + 0.1, k) * (1.0 - smoothstep(0.7, 1.0, k))
		Bear._turn(sk, info, "chest", 0.12 * drop - 0.08 * hook)
		Bear._turn(sk, info, "neck", 0.45 * drop - 0.35 * hook, 0.3 * hook)
		Bear._turn(sk, info, "head", 0.35 * drop - 0.45 * hook, 0.25 * hook)
		Bear._turn(sk, info, "jaw", 0.05 + 0.2 * hook)

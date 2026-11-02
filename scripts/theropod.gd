class_name Theropod
## The Verdant Isle's two-legged dinosaurs (Data.ENEMIES "raptor", "trex"): Meshy models on the 25-bone skeleton
## of tools/blender/dino/rig_theropod.py (hips spine chest neck neck2 head jaw, tail1..6, thigh/shin/foot/toe, the
## little arms). Like the lion and the bear there are no baked animations: every frame `pose` turns the bones from
## the enemy's state, each move written for what it is.
##  - the gait: digitigrade strides, the body held level over the hips like a see-saw, the tail streaming out behind
##    and swinging against the stride, the head steady and bobbing a little; faster = longer strides, more lean
##  - the raptor (the Feral pack AI): "feral_lunge" = the pounce (crouch, spring, the sickle claws thrown forward,
##    land); "feral_swipe" = a slashing kick and a snap of the jaws
##  - the tyrant (the bear AI): "bear_roar" = the roar (rears back, head up, jaw wide, the whole body shaking);
##    "bear_maul" = the bite (lunges low with the jaws wide, snaps them shut at MAUL_HIT, wrenches the head)

const GLB := {"raptor": "res://assets/models/monsters/dino/raptor.glb", "trex": "res://assets/models/monsters/dino/trex.glb"}
const STRIDE := 1.25         # metres covered per stride cycle, per metre of hip height
const ROAR_T := 2.6
const MAUL_T := 1.6
const MAUL_HIT := 0.5        # the jaws close
const ROAR_AT := 0.3

static func ok(kind: String) -> bool:
	return GLB.has(kind) and ResourceLoader.exists(GLB[kind])

static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	var body: Node3D = (load(GLB[kind]) as PackedScene).instantiate()
	body.name = "Body"
	body.rotation.y = PI          # Blender's front (-Y) arrives facing +z; monsters face -z
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
	var hip := 1.0
	if info.has("thigh_l"):
		hip = sk.get_bone_global_rest(int(info["thigh_l"][0])).origin.y
	root.set_meta("dino", sk)
	root.set_meta("dino_bones", info)
	root.set_meta("dino_body", body)
	root.set_meta("dino_base", body.transform)
	root.set_meta("dino_hip", hip)
	root.set_meta("dino_kind", kind)
	return root

## As Bear._turn: ax about the model's side axis (+ tips a hanging bone's end backward and a forward-pointing one's
## down), ay about the up axis (+ to its left), az about the long axis.
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

static func _e(a: float, b: float, k: float) -> float:
	return smoothstep(a, b, k)

static func pose(rig: Node3D, st: Dictionary, _height: float) -> void:
	if not rig.has_meta("dino"):
		return
	var sk: Skeleton3D = rig.get_meta("dino")
	var info: Dictionary = rig.get_meta("dino_bones")
	var body: Node3D = rig.get_meta("dino_body")
	var base: Transform3D = rig.get_meta("dino_base")
	var hip: float = rig.get_meta("dino_hip")
	var t: float = st.get("time", 0.0)
	var mv := clampf(float(st.get("move", 0.0)), 0.0, 1.6)
	var style: String = st.get("style", "")
	var atk: float = st.get("atk", -1.0)
	var hit: float = st.get("hit", 0.0)
	var dead := st.has("dead")
	if dead:
		mv = 0.0
		atk = -1.0
	var walk := minf(mv, 1.0)
	var run := clampf(mv - 1.0, 0.0, 0.6) / 0.6
	# --- the stride: the phase grows a cycle per STRIDE * hip metres
	var u := fposmod(float(st.get("phase", 0.0)) / (STRIDE * 1.6 * maxf(hip, 0.3) / maxf(hip, 0.3)), 1.0)
	var amp := 0.42 + 0.22 * run
	var leg := {}
	for s in ["l", "r"]:
		var ang := TAU * (u + (0.0 if s == "l" else 0.5))
		var sw := sin(ang)                       # + = swinging forward
		var up := maxf(0.0, cos(ang))            # the foot off the ground on the way forward
		# thigh, shin (the knee folds more as the foot lifts), foot (the long metatarsus), toes (curl in the air)
		leg[s] = [-sw * amp * walk, up * (0.55 + 0.3 * run) * walk, -up * (0.5 + 0.2 * run) * walk + sw * 0.15 * walk, up * 0.6 * walk]
	var bob := absf(sin(TAU * u)) * 0.035 * hip * walk
	var lean := 0.1 * run                        # the body pitches forward as it runs
	var spine_x := sin(TAU * u * 2.0) * 0.025 * walk + sin(t * 1.3) * 0.012
	var sway := sin(TAU * u) * 0.08 * walk       # the hips roll with each stride
	var tail_y := -sin(TAU * u) * 0.14 * walk + sin(t * 0.9) * 0.12 * (1.0 - walk)
	var tail_x := -0.04 - 0.06 * walk            # streams out level, a little higher on the run
	var neck_x := 0.02 + sin(TAU * u * 2.0 + 0.6) * 0.04 * walk + hit * 0.25
	var neck_y := sin(t * 0.5) * 0.18 * (1.0 - walk) + sin(TAU * u) * 0.04 * walk
	var head_x := 0.0
	var head_y := 0.0
	var jaw := 0.03 + 0.03 * sin(t * 1.9)
	var arm := 0.25 + sin(t * 2.0) * 0.05        # the little arms held folded
	var pitch := lean
	var lift := 0.0
	var fwd := 0.0
	if atk >= 0.0 and style == "feral_lunge":
		# the pounce: crouch (0..0.25), spring (0.25..0.45), the claws thrown forward in the air, land (0.75..1)
		var k := atk
		var crouch := _e(0.0, 0.25, k) * (1.0 - _e(0.25, 0.32, k))
		var air := _e(0.25, 0.4, k) * (1.0 - _e(0.7, 0.85, k))
		var land := _e(0.75, 0.85, k) * (1.0 - _e(0.88, 1.0, k))
		lift = -0.12 * hip * crouch + 0.35 * hip * air - 0.06 * hip * land
		pitch = 0.18 * crouch - 0.15 * air + 0.1 * land
		for s in ["l", "r"]:
			# crouched: thighs forward, knees folded; in the air: the feet thrown forward, sickle claws first
			leg[s] = [lerpf(-0.5, -1.1, air) * maxf(crouch, air) + leg[s][0] * (1.0 - maxf(crouch, air)),
				0.9 * crouch + 0.4 * air, -0.7 * crouch - 0.3 * air, -0.6 * air]
		neck_x = 0.25 * crouch - 0.2 * air
		head_x = 0.1 * crouch - 0.15 * air
		jaw = 0.05 + 0.6 * air
		arm = 0.25 - 0.6 * air
		tail_x = 0.06 * crouch + 0.12 * air      # (for the tail, + lifts it: it streams out behind the leap)
	elif atk >= 0.0 and style == "feral_swipe":
		# the slash: a kick with the right foot's sickle claw (0..0.5), then a snap of the jaws (0.5..0.8)
		var k := atk
		var kick := _e(0.05, 0.35, k) * (1.0 - _e(0.45, 0.6, k))
		var snap := _e(0.45, 0.6, k) * (1.0 - _e(0.7, 0.9, k))
		leg["r"] = [-1.1 * kick, 0.3 * kick, -0.9 * kick, -0.8 * kick]
		leg["l"] = [0.15 * kick, 0.2 * kick, -0.1 * kick, 0.0]
		pitch = -0.12 * kick + 0.12 * snap
		neck_x = 0.1 * kick + 0.3 * snap
		head_x = -0.05 * kick + 0.15 * snap
		jaw = 0.05 + 0.65 * _e(0.45, 0.55, k) * (1.0 - _e(0.58, 0.66, k))
		tail_y += 0.3 * kick
	elif atk >= 0.0 and style == "bear_roar":
		# the roar: rear back (0..0.25), head up and the jaws wide, the body shaking (0.25..0.75), come down
		var k := atk
		var up := _e(0.0, 0.25, k) * (1.0 - _e(0.8, 0.95, k))
		var roar := _e(0.25, 0.32, k) * (1.0 - _e(0.7, 0.8, k))
		pitch = -0.28 * up
		lift = 0.04 * hip * up
		neck_x = lerpf(neck_x, -0.3, up)
		head_x = -0.25 * up + sin(t * 10.0) * 0.04 * roar
		neck_y = sin(t * 2.2) * 0.25 * roar
		jaw = lerpf(jaw, 0.85 + sin(t * 13.0) * 0.06, roar)
		spine_x += sin(t * 16.0) * 0.03 * roar
		tail_x = -0.04 + 0.16 * up         # (lifted as he rears back, or it would drag on the ground)
		tail_y += sin(t * 6.0) * 0.18 * roar
		arm = 0.25 - 0.3 * roar + sin(t * 12.0) * 0.08 * roar
		for s in ["l", "r"]:
			leg[s] = [0.12 * up, 0.15 * up, -0.08 * up, 0.0]
	elif atk >= 0.0 and style == "bear_maul":
		# the bite: rear back with the jaws opening (0..0.3), lunge low (0.3..MAUL_HIT), snap shut, wrench, recover
		var k := atk
		var back := _e(0.0, 0.3, k) * (1.0 - _e(0.32, MAUL_HIT, k))
		var lunge := _e(0.32, MAUL_HIT, k) * (1.0 - _e(0.7, 1.0, k))
		var wrench := _e(MAUL_HIT, 0.62, k) * (1.0 - _e(0.75, 0.9, k))
		pitch = -0.15 * back + 0.32 * lunge
		fwd = -0.08 * hip * back + 0.35 * hip * lunge
		neck_x = -0.2 * back + 0.35 * lunge
		head_x = -0.15 * back + 0.2 * lunge
		neck_y = sin(k * 40.0) * 0.22 * wrench
		jaw = 0.05 + 0.85 * _e(0.05, 0.3, k) * (1.0 - _e(MAUL_HIT - 0.04, MAUL_HIT + 0.02, k))
		tail_x = -0.04 - 0.1 * back + 0.15 * lunge
		for s in ["l", "r"]:
			leg[s] = [(0.2 if s == "l" else -0.35) * lunge + 0.1 * back, 0.3 * lunge, -0.2 * lunge, 0.0]
	if dead:
		# down on its side
		var k := clampf(float(st.get("dead_t", 1.0)), 0.0, 1.0)
		body.transform = Transform3D(Basis(Vector3.BACK, 1.45 * _e(0.0, 0.7, k)), Vector3(0, -0.15 * hip * k, 0)) * base
		_turn(sk, info, "jaw", 0.35)
		_turn(sk, info, "neck", 0.3 * k)
		return
	# --- the body: pitched about the hips (the rig faces -z), bobbing with the stride
	var pv := Vector3(0, hip, 0)
	var tilt := Transform3D(Basis(Vector3.RIGHT, -pitch), Vector3.ZERO)
	body.transform = Transform3D(Basis(), pv + Vector3(0, bob + lift, -fwd)) * tilt * Transform3D(Basis(), -pv) * base
	_turn(sk, info, "hips", spine_x * 0.4, 0.0, sway)
	_turn(sk, info, "spine", spine_x)
	_turn(sk, info, "chest", spine_x * 0.6, 0.0, -sway * 0.6)
	# the head held steady against the body's pitch (shared down the neck so no one joint folds)
	_turn(sk, info, "neck", neck_x + pitch * 0.4, neck_y)
	_turn(sk, info, "neck2", neck_x * 0.6 + pitch * 0.3, neck_y * 0.6)
	_turn(sk, info, "head", head_x + pitch * 0.3, neck_y * 0.3 + head_y)
	_turn(sk, info, "jaw", jaw)
	# the tail: each bone a little more of the swing, lagging, so it whips like a whip rather than a plank
	for i in 6:
		var k := float(i + 1) / 6.0
		var lag := sin(t * 1.6 - i * 0.5) * 0.03 * (1.0 - walk)
		_turn(sk, info, "tail%d" % (i + 1), tail_x * (0.6 + 0.4 * k) - pitch * (0.3 if i == 0 else 0.0), (tail_y + lag) * (0.5 + 0.5 * k))
	for s in ["l", "r"]:
		var g: Array = leg[s]
		_turn(sk, info, "thigh_" + s, g[0] + pitch * 0.9)
		_turn(sk, info, "shin_" + s, g[1])
		_turn(sk, info, "foot_" + s, g[2])
		_turn(sk, info, "toe_" + s, g[3])
		_turn(sk, info, "arm_" + s, -arm)
		_turn(sk, info, "forearm_" + s, arm * 1.4)

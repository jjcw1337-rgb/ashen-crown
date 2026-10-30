class_name Bear
## The Forsaken Bear (Act I, and any later act that wants it: Data.ENEMIES "bear"): the Meshy "corrupted ancient"
## (antlers, roots wrapped round its legs, green-glowing eyes) on a 21-bone quadruped skeleton made by
## tools/blender/act1/rig_bear.py (the lion's bone names, plus the jaw and the antlers). Like the lion it has no
## baked animations: every frame `pose` turns the bones from the enemy's state.
##  - the walk: a slow heavy gait in diagonal pairs, the head low and swinging, the shoulders rolling
##  - "bear_roar": it rears onto its hind legs, forepaws up (the whole body pitched about the hind feet), throws
##    its head forward with the jaw wide, the chest heaving and a shake running down the spine, and drops back down
##  - "bear_maul": rears, then slams both forepaws down in front (the impact at MAUL_HIT), and settles
## The AI (wander, roar, charge, maul, leash) is in enemy.gd (_bear_*).

const GLB := "res://assets/models/monsters/bear.glb"
const STRIDE := 1.9          # metres covered per walk cycle
const ROAR_T := 2.6          # seconds: rear up, roar, come down
const MAUL_T := 1.5
const MAUL_HIT := 0.48       # the paws hit the ground
const ROAR_AT := 0.32        # the roar's sound and shake
const PIVOT := Vector3(0, 1.12, 0.64)   # the hip joints (the rig faces -z): he rears about them, the hind legs kept planted

## Its sounds, or a stand-in until they're made (tools/audio): the lion's roar pitched down, the boss slam.
const SOUND_FALLBACK := {"bear_roar": ["lion_roar", 0.66, 2.0], "bear_maul": ["slam", 0.8, -2.0]}

static func sound(nm: String, pos: Vector3) -> void:
	if Sfx.bank.has(nm):
		Sfx.play_at(nm, pos, 0.0, randf_range(0.95, 1.05))
	elif SOUND_FALLBACK.has(nm):
		var f: Array = SOUND_FALLBACK[nm]
		Sfx.play_at(f[0], pos, f[2], f[1] * randf_range(0.95, 1.05))

static func ok() -> bool:
	return ResourceLoader.exists(GLB)

static func build() -> Node3D:
	var root := Node3D.new()
	var body: Node3D = (load(GLB) as PackedScene).instantiate()
	body.name = "Body"
	body.rotation.y = PI          # Blender's front (-Y) arrives facing +z; monsters face -z
	root.add_child(body)
	var sks := body.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return root
	var sk: Skeleton3D = sks[0]
	# per bone: index, rest rotation, and the model's side (X), up (Y) and back (Z) axes in the bone's own frame,
	# so a pose is "swing about the side axis" whatever way Blender rolled the bone (as lion.gd)
	var info := {}
	for i in sk.get_bone_count():
		var g := sk.get_bone_global_rest(i).basis.orthonormalized()
		var gi := g.inverse()
		info[sk.get_bone_name(i)] = [i, sk.get_bone_rest(i).basis.get_rotation_quaternion(), (gi * Vector3.RIGHT).normalized(), (gi * Vector3.UP).normalized(), (gi * Vector3.BACK).normalized()]
	root.set_meta("bear", sk)
	root.set_meta("bear_bones", info)
	root.set_meta("bear_body", body)
	root.set_meta("bear_base", body.transform)
	return root

## Turn a bone from its rest: ax about the model's side axis (+ tips a hanging bone's end backward, toward the
## tail, and a forward-pointing one's down), ay about the up axis (+ to the bear's left), az about the long axis.
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

static func _ease(a: float, b: float, k: float) -> float:
	return smoothstep(a, b, k)

static func pose(rig: Node3D, st: Dictionary, height: float) -> void:
	if not rig.has_meta("bear"):
		return
	var sk: Skeleton3D = rig.get_meta("bear")
	var info: Dictionary = rig.get_meta("bear_bones")
	var body: Node3D = rig.get_meta("bear_body")
	var base: Transform3D = rig.get_meta("bear_base")
	var t: float = st.get("time", 0.0)
	var mv := clampf(float(st.get("move", 0.0)), 0.0, 1.4)
	var style: String = st.get("style", "")
	var atk: float = st.get("atk", -1.0)
	var hit: float = st.get("hit", 0.0)
	if st.has("dead"):
		mv = 0.0
		atk = -1.0
	# --- the walk: diagonal pairs, the phase grows 1.6 / height per metre covered
	var per_cycle := STRIDE * 1.6 / maxf(height, 0.3)
	var u := fposmod(float(st.get("phase", 0.0)) / per_cycle, 1.0)
	var legs := {"l_f": 0.0, "r_b": 0.06, "r_f": 0.5, "l_b": 0.56}
	var a := {}
	for k in legs:
		var ang := TAU * (u + float(legs[k]))
		a[k] = [sin(ang) * 0.42 * mv, maxf(0.0, cos(ang)) * 0.75 * mv]
	var walk := minf(mv, 1.0)
	var bob := absf(sin(TAU * u * 2.0)) * 0.03 * mv
	var front := {"l": [-a["l_f"][0], a["l_f"][1], a["l_f"][1] * 0.45], "r": [-a["r_f"][0], a["r_f"][1], a["r_f"][1] * 0.45]}
	var hind := {"l": [-a["l_b"][0], -a["l_b"][1] * 0.7, a["l_b"][1] * 0.6], "r": [-a["r_b"][0], -a["r_b"][1] * 0.7, a["r_b"][1] * 0.6]}
	var roll := sin(TAU * u) * 0.07 * walk                       # the shoulders roll with each forepaw
	var spine_x := sin(TAU * u * 2.0) * 0.03 * mv + sin(t * 1.1) * 0.012
	var spine_y := 0.0
	var chest_x := 0.0
	var neck_x := 0.16 * walk + sin(t * 0.8) * 0.03 + hit * 0.3   # the head carried low on the move
	var neck_y := sin(TAU * u) * 0.16 * walk + sin(t * 0.45) * 0.2 * (1.0 - walk)
	var head_x := 0.0
	var head_y := 0.0
	var jaw := 0.04 + 0.03 * sin(t * 1.7)
	var pitch := 0.0          # the whole body, nose up, about the hips
	var lift := 0.0
	if atk >= 0.0 and style == "bear_roar":
		# up onto the hind legs (0..0.22), hold and roar (0.22..0.78), down onto all fours (0.78..1)
		var k := atk
		var up := _ease(0.0, 0.22, k) * (1.0 - _ease(0.78, 0.95, k))
		var roar := _ease(0.26, 0.34, k) * (1.0 - _ease(0.66, 0.78, k))
		pitch = 1.05 * up
		lift = 0.05 * up
		for s in ["l", "r"]:
			# the forepaws raised in front, the claws hanging; the hind legs kept under him
			var sway := sin(t * 3.0 + (0.0 if s == "l" else 1.4)) * 0.12 * up
			front[s] = [lerpf(front[s][0], -0.45 + sway, up), lerpf(front[s][1], 0.7, up), lerpf(front[s][2], 0.55, up)]
			hind[s] = [lerpf(hind[s][0], pitch * 0.92, up), lerpf(hind[s][1], -0.25 * up, up), lerpf(hind[s][2], -pitch * 0.55, up)]
		# the head comes level with the world as he rises, then is thrown forward to roar
		# shared over the chest, neck and head so no one joint folds the hide
		# (he roars up and out over you rather than levelling his head, which would fold the hide on his nape)
		chest_x = 0.16 * up
		neck_x = lerpf(neck_x, 0.18 + 0.12 * roar, up)
		head_x = 0.2 * up - 0.12 * roar + sin(t * 9.0) * 0.05 * roar
		neck_y = lerpf(neck_y, sin(t * 2.5) * 0.12 * roar, up)
		jaw = lerpf(jaw, 0.75 + sin(t * 11.0) * 0.06, roar)
		chest_x += sin(t * 7.5) * 0.06 * roar                    # the chest heaving
		spine_y = sin(t * 14.0) * 0.05 * roar                    # the shake down the spine
		spine_x = lerpf(spine_x, -0.12, up)
	elif atk >= 0.0 and style == "bear_maul":
		# rear (0..0.34), slam both forepaws down in front (0.34..MAUL_HIT), hold, settle
		var k := atk
		var rear := _ease(0.0, 0.32, k) * (1.0 - _ease(0.34, MAUL_HIT, k))
		var slam := _ease(0.34, MAUL_HIT, k) * (1.0 - _ease(0.7, 1.0, k))
		pitch = 0.8 * rear - 0.12 * slam
		lift = 0.04 * rear
		for s in ["l", "r"]:
			front[s] = [-0.55 * rear - 0.45 * slam, 0.7 * rear + 0.1 * slam, 0.5 * rear - 0.2 * slam]
			hind[s] = [pitch * 0.9 + 0.1 * slam, -0.3 * rear - 0.25 * slam, -pitch * 0.5 + 0.2 * slam]
		neck_x = 0.3 * rear + 0.3 * slam
		head_x = 0.25 * rear - 0.1 * slam
		neck_y = 0.0
		jaw = 0.1 + 0.55 * rear + 0.2 * slam
		chest_x = 0.2 * rear + 0.12 * slam
		spine_x = -0.1 * rear + 0.08 * slam
	# --- the body: pitched about the hips (rig frame: the bear faces -z, the hips are behind at +z)
	var pv := PIVOT
	var tilt := Transform3D(Basis(Vector3.RIGHT, pitch), Vector3.ZERO)
	body.transform = Transform3D(Basis(), pv + Vector3(0, bob + lift, 0)) * tilt * Transform3D(Basis(), -pv) * base
	_turn(sk, info, "hips", spine_x * 0.5)
	_turn(sk, info, "spine", spine_x, spine_y)
	_turn(sk, info, "chest", spine_x * 0.6 + chest_x, -spine_y * 0.6, roll)
	_turn(sk, info, "neck", neck_x, neck_y)
	_turn(sk, info, "head", head_x, neck_y * 0.4 + head_y)
	_turn(sk, info, "jaw", jaw)
	for s in ["l", "r"]:
		var f: Array = front[s]
		_turn(sk, info, "arm_" + s, f[0], 0.0, roll * (1.0 if s == "l" else -1.0))
		_turn(sk, info, "forearm_" + s, f[1])
		_turn(sk, info, "paw_" + s, f[2])
		var h: Array = hind[s]
		_turn(sk, info, "thigh_" + s, h[0])
		_turn(sk, info, "shin_" + s, h[1])
		_turn(sk, info, "foot_" + s, h[2])
	_turn(sk, info, "tail1", -0.2 - 0.25 * walk, sin(t * 1.8) * 0.25)

class_name Dragon
extends RefCounted
## The dragon classes: the Obsidian Wyrm (four legs and wings), the Frost Serpent (long, wingless, four short
## legs) and the Storm Wyvern (two legs, its wings are its forelimbs). Meshy models (concept image or text, then
## image/text-to-3D, ~31k triangles, 2K PBR textures + a glow map) rigged in Blender with a chain skeleton:
## spine_*, neck_*, head_0/1, jaw_0, tail_*, leg_<FL|FR|HL|HR|L|R>_0..2, and for the winged two arm_<L|R>_0/1
## plus fing<N>_<L|R>_0/1. The `_L` chains sit at -x of the model (the dragon's right), `_R` at +x.
##
## Like the arena lion there are no baked animations in play (the glb carries Idle/Flap/Roar for previews, unused):
## `pose` turns every bone from its rest each frame from the hero's animation state (Anim.pose hands any rig with
## the "dragon" meta here), on the local hero and on a co-op puppet alike. What it shows:
##   idle    breathing, the head looking about, the jaw working, the wings folded and breathing;
##   moving  a diagonal trot (wyrm, serpent) or a striding biped run (wyvern) phased to the ground covered (the rig's
##           `stride` meta slows the hero's phase to the dragon's long legs), the body bobbing and swaying, the
##           serpent's whole body undulating, the wings half open and beating with the stride at a sprint;
##   tail    always moving, and more than the Demon's: a wag that travels down the chain into an S, its speed and
##           size drifting, lifted off the ground at a run, swinging with the stride, a flick or curl of the tip
##           every few seconds, a lash when hit;
##   attack  the basic attack (left mouse) is the hero's three-swipe combo: swipe1 a raking foreclaw (the wyvern's
##           wing claw), swipe2 a lunging bite, swipe3 a full spin that sweeps the tail round (it hits the combo
##           finisher's half circle); any other style (future skills) plays a roar with the wings flared;
##   block   hunkered down behind the wings (the serpent coils), hit = a flinch, dead = it falls onto its side.
## Footfalls and wing beats are sounds (Sfx `<kind>_step`, `wyvern_flap`) played where the body is.
##
## Skills: none yet (DragonSkills is ready for them). Weapons and shields still give their stats; their models hang
## off a hidden joint so a dragon never holds a sword. Joints for effects: head (J["head"]), chest, the front paws
## or wing claws as hand_r / hand_l.

const KINDS := {
	"wyrm": {"glb": "res://assets/models/dragons/wyrm.glb", "scale": 0.46, "h": 2.45, "stride": 0.62,
		"gait": "quad", "wings": true, "tail": 0.2, "reach": 2.3, "radius": 0.8, "stage": 0.55, "stage_yaw": 0.75,
		"bob": 0.06, "fold": 0.35},
	# (the serpent's stride: its phase runs at its short legs' own pace, so a planted foot keeps to the ground)
	"serpent": {"glb": "res://assets/models/dragons/serpent.glb", "scale": 0.42, "h": 2.75, "stride": 2.3,
		"gait": "serpent", "wings": false, "tail": 0.22, "reach": 2.2, "radius": 0.7, "stage": 0.5, "stage_yaw": 0.8,
		"bob": 0.04, "fold": 0.0},
	"wyvern": {"glb": "res://assets/models/dragons/wyvern.glb", "scale": 0.45, "h": 2.8, "stride": 0.82,
		"gait": "biped", "wings": true, "tail": 0.2, "reach": 2.1, "radius": 0.65, "stage": 0.58, "stage_yaw": 0.45,
		"bob": 0.08, "fold": 0.6},
}
## seconds between tail flicks (random in this range)
const FLICK_EVERY := Vector2(3.5, 7.0)

static func is_dragon(c: String) -> bool:
	return KINDS.has(c)

static func spec(c: String) -> Dictionary:
	return KINDS[c] if KINDS.has(c) else KINDS["wyrm"]

static func ok(c: String) -> bool:
	return ResourceLoader.exists(str(spec(c)["glb"]))

## How far the basic attack reaches (Hero.reach).
static func reach(c: String) -> float:
	return float(spec(c)["reach"])

## The model scaled down for the class picker's plinths, and turned three-quarters so its length shows.
static func stage_scale(c: String) -> float:
	return float(spec(c)["stage"])

static func stage_yaw(c: String) -> float:
	return float(spec(c)["stage_yaw"])

# ---------------------------------------------------------------- body
static func build(c: String) -> Node3D:
	var sp := spec(c)
	var root := Node3D.new()
	root.name = "Dragon_" + c
	var hold := Node3D.new()        # bob, spin and the fall onto its side are moved here
	hold.name = "Hold"
	root.add_child(hold)
	var body: Node3D
	if ok(c):
		body = ResCache.inst(str(sp["glb"])) as Node3D
	else:
		body = _stand_in()
	body.name = "Body"
	body.rotation.y = PI            # Blender's front (-Y) arrives facing +z; heroes face -z
	body.scale = Vector3.ONE * float(sp["scale"])
	hold.add_child(body)
	for ap in body.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	var sk: Skeleton3D = null
	var sks := body.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		sk = sks[0] as Skeleton3D
	var info := {}
	if sk != null:
		# per bone: index, rest rotation, and the model's side (x), up (y) and forward (z) axes in the bone's own frame,
		# so a pose is "pitch about the side axis, yaw about the up axis, roll about the forward axis" whatever way
		# Blender rolled the bone (the lion's scheme)
		for i in sk.get_bone_count():
			var g := sk.get_bone_global_rest(i).basis.orthonormalized()
			var gi := g.inverse()
			info[sk.get_bone_name(i)] = [i, sk.get_bone_rest(i).basis.get_rotation_quaternion(),
				(gi * Vector3.RIGHT).normalized(), (gi * Vector3.UP).normalized(), (gi * Vector3.BACK).normalized()]
	# joints the shared hero code reads; the weapon/shield/amulet ones are hidden (no sword in a dragon's claws)
	var hidden := Node3D.new()
	hidden.name = "Hidden"
	hidden.visible = false
	root.add_child(hidden)
	var J := {}
	for k in ["grip_r", "grip_l", "mount_l", "chest", "torso", "at_torso"]:
		var n := Node3D.new()
		n.name = k
		hidden.add_child(n)
		J[k] = n
	J["head"] = _attach(sk, root, "head_0", Vector3(0, sp["h"] * 0.8, -1.0))
	J["at_head"] = J["head"]
	var paws := ["arm_R_1", "arm_L_1"] if sp["gait"] == "biped" else ["leg_FR_2", "leg_FL_2"]
	J["hand_r"] = _attach(sk, root, paws[0], Vector3(0.4, 0.3, -0.8))
	J["hand_l"] = _attach(sk, root, paws[1], Vector3(-0.4, 0.3, -0.8))
	J["hips_y"] = float(sp["h"]) * 0.45
	root.set_meta("j", J)
	root.set_meta("h", float(sp["h"]))
	root.set_meta("dragon", c)
	root.set_meta("own_death", true)       # Hero's death tilt stays off it: pose lays it down itself
	root.set_meta("stride", float(sp["stride"]))
	root.set_meta("drg_hold", hold)
	root.set_meta("drg_mem", {"flick_at": randf_range(FLICK_EVERY.x, FLICK_EVERY.y), "seed": randf() * 10.0})
	if sk != null:
		root.set_meta("drg_sk", sk)
		root.set_meta("drg_info", info)
	return root

## A follower on a bone (or a plain node at `fallback` if the bone is missing).
static func _attach(sk: Skeleton3D, root: Node3D, bone: String, fallback: Vector3) -> Node3D:
	if sk != null and sk.find_bone(bone) >= 0:
		var ba := BoneAttachment3D.new()
		ba.name = "at_" + bone
		ba.bone_name = bone
		sk.add_child(ba)
		var n := Node3D.new()
		n.name = bone + "_pt"
		ba.add_child(n)
		return n
	var p := Node3D.new()
	p.position = fallback
	root.add_child(p)
	return p

## Without the glb (a stripped build): a dark capsule so nothing else breaks.
static func _stand_in() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.9
	cm.height = 5.0
	mi.mesh = cm
	mi.rotation.x = PI * 0.5
	mi.position.y = 1.4
	n.add_child(mi)
	return n

# ---------------------------------------------------------------- pose helpers
## Adds a turn to a bone's pose this frame: ax about the model's side axis (+ lifts a bone that points back,
## tips one that points forward down, swings one that points down backward), ay about the up axis (+ swings a
## forward-pointing bone to the dragon's left), az about the forward axis (+ lowers a bone pointing to -x).
static func _add(P: Dictionary, bone: String, ax: float, ay := 0.0, az := 0.0) -> void:
	var v: Vector3 = P.get(bone, Vector3.ZERO)
	P[bone] = v + Vector3(ax, ay, az)

## The wing's side: -1 for the `_L` chains (at -x), +1 for `_R`.
static func _side(bone: String) -> float:
	return -1.0 if bone.ends_with("_L") or bone.contains("_L_") else 1.0

## Lower a wing bone by `lo` (its tip down) and sweep it back toward the tail by `bk`.
static func _wing(P: Dictionary, bone: String, lo: float, bk: float) -> void:
	var s := _side(bone)
	_add(P, bone, 0.0, s * bk, -s * lo)

static func _chain(info: Dictionary, prefix: String) -> Array:
	var out: Array = []
	var i := 0
	while info.has(prefix + str(i)):
		out.append(prefix + str(i))
		i += 1
	return out

static func _sm(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)

# ---------------------------------------------------------------- pose
static func pose(rig: Node3D, st: Dictionary) -> void:
	if not rig.has_meta("drg_sk"):
		return
	var sk: Skeleton3D = rig.get_meta("drg_sk")
	var info: Dictionary = rig.get_meta("drg_info")
	var hold: Node3D = rig.get_meta("drg_hold")
	var mem: Dictionary = rig.get_meta("drg_mem")
	var c: String = str(rig.get_meta("dragon"))
	if c == "serpent" and info.has("spine_3"):
		SerpentBody.pose(rig, st)     # the re-rigged serpent's own body (scripts/serpent_body.gd)
		return
	var sp := spec(c)
	var gait: String = sp["gait"]
	var t: float = float(st.get("time", 0.0))
	var dt := clampf(t - float(mem.get("t", t)), 0.0, 0.05)
	mem["t"] = t
	var sd: float = float(mem.get("seed", 0.0))
	var ph: float = float(st.get("phase", 0.0))
	var m := clampf(float(st.get("move", 0.0)), 0.0, 1.4)
	var a: float = float(st.get("atk", -1.0))
	var style: String = str(st.get("style", ""))
	var blk := clampf(float(st.get("block", 0.0)), 0.0, 1.0)
	var hit := clampf(float(st.get("hit", 0.0)), 0.0, 1.0)
	var look := clampf(float(st.get("look", 0.0)), -0.8, 0.8)
	var dead := clampf(float(st.get("dead", 0.0)), 0.0, 1.0) if st.has("dead") else 0.0
	if dead > 0.0:
		m = 0.0
		a = -1.0
		blk = 0.0
	var mw := minf(m, 1.0)
	var run := clampf((m - 1.0) / 0.3, 0.0, 1.0)     # 0 at a walk .. 1 at a sprint (move 1.3)
	var calm := 1.0 - mw
	var P := {}
	var spine := _chain(info, "spine_")
	var neck := _chain(info, "neck_")
	var tail := _chain(info, "tail_")
	var breath := sin(t * 1.3 + sd) * 0.025

	# --- body: bob, sway, lean, breathing
	var bob := (0.5 - 0.5 * cos(2.0 * ph)) * float(sp["bob"]) * m
	var lean := 0.0
	if gait == "biped":
		lean = 0.1 * mw + 0.16 * run
	elif gait == "quad":
		lean = 0.04 * run
	for i in spine.size():
		var k := float(i + 1) / maxf(1.0, spine.size())
		_add(P, spine[i], -breath * 0.6 + sin(2.0 * ph) * 0.025 * m + lean / maxf(1.0, spine.size()),
			sin(ph) * 0.04 * m * k)
	# the serpent swims: a wave down the whole body while it moves, a slow drift at rest
	if gait == "serpent":
		var body_chain: Array = []
		for n in neck:
			body_chain.append(n)
		body_chain.reverse()          # head end first
		for s in spine:
			body_chain.append(s)
		for j in body_chain.size():
			var w := 0.11 * mw * sin(ph * 0.5 - j * 0.7) + 0.04 * calm * sin(t * 0.8 - j * 0.5 + sd)
			_add(P, body_chain[j], 0.0, w)

	# --- neck and head: steady over the stride, looking about at rest, into turns while moving
	var wander := (sin(t * 0.37 + sd) * 0.25 + sin(t * 0.91 + sd * 2.0) * 0.1) * calm
	var nn := maxf(1.0, neck.size())
	for i in neck.size():
		_add(P, neck[i], breath * 0.5 - sin(2.0 * ph) * 0.03 * m - lean * 0.5 / nn, (look * 0.7 + wander) / nn)
	_add(P, "head_0", sin(t * 1.1 + sd) * 0.03 * calm - lean * 0.3, look * 0.3 + wander * 0.4)
	var jaw := maxf(0.0, sin(t * 0.9 + sd)) * 0.05 * calm + 0.1 * run

	# --- legs
	var legs := {}
	if gait == "biped":
		legs = {"leg_L": 0.0, "leg_R": PI}
	else:
		legs = {"leg_FL": 0.0, "leg_HR": 0.0, "leg_FR": PI, "leg_HL": PI}
	var amp := (0.38 if gait == "biped" else (0.26 if gait == "serpent" else 0.42)) * (mw + run * 0.3)
	for lg in legs:
		var phi := ph + float(legs[lg])
		var sw := sin(phi)
		var lift := maxf(0.0, cos(phi)) * (mw + run * 0.4)
		var front: bool = str(lg).contains("F")
		_add(P, lg + "_0", -sw * amp)
		if front:
			_add(P, lg + "_1", lift * 0.8)
			_add(P, lg + "_2", -lift * 0.5)
		else:
			_add(P, lg + "_1", lift * 0.7)
			_add(P, lg + "_2", -lift * 0.45)

	# --- wings: folded at rest, half open and beating at a run
	var winged: bool = sp["wings"]
	var fold: float = float(sp["fold"])
	var flap := 0.0
	var wing_lo := fold * (1.0 - 0.55 * mw) + breath * 0.6
	var wing_bk := fold * 0.8 * (1.0 - 0.4 * mw)
	if run > 0.0:
		flap = sin(ph + 0.6) * (0.32 if gait == "biped" else 0.22) * run
	# (the wyvern, jj: more life in the wings) they sway against the stride as it walks, twitch at rest, and every so
	# often it rouses them: half spread, a shake, folded again
	var wsway := 0.0
	var rouse := 0.0
	if winged and gait == "biped":
		wsway = sin(ph + PI * 0.5) * 0.12 * mw
		var ra: float = float(mem.get("rouse_at", 6.0))
		if t > ra and mw < 0.2 and a < 0.0:
			mem["rouse_t0"] = t
			mem["rouse_at"] = t + randf_range(8.0, 14.0)
		var r0: float = float(mem.get("rouse_t0", -10.0))
		if t - r0 < 1.6:
			var u := (t - r0) / 1.6
			rouse = sin(PI * u) * (1.0 + 0.25 * sin(u * 40.0) * sin(PI * u))
		wing_lo -= 0.55 * rouse * calm
		wing_bk -= 0.4 * rouse * calm
		wing_lo += 0.03 * sin(t * 2.3 + sd) * calm
	# its flight (the dodge, Dodge.pose: the rig's "fly" meta): the wings spread and beat hard, the legs tucked up
	var fly: float = float(rig.get_meta("fly")) if rig.has_meta("fly") else -1.0
	if fly >= 0.0 and winged:
		var fk := smoothstep(0.0, 0.12, fly) * (1.0 - smoothstep(0.85, 1.0, fly))
		wing_lo -= 0.9 * fk
		wing_bk -= 0.5 * fk
		flap += sin(fly * TAU * 3.5) * 0.85 * fk
		for lg in legs:
			_add(P, lg + "_0", 0.45 * fk)
			_add(P, lg + "_1", 0.7 * fk)

	# --- tail: never still
	var wag_w := lerpf(1.7, 3.0, mw)
	mem["wag"] = float(mem.get("wag", 0.0)) + dt * wag_w * (0.85 + 0.3 * sin(t * 0.23 + sd))
	var wag: float = mem["wag"]
	var tail_amp: float = float(sp["tail"]) * (0.8 + 0.35 * sin(t * 0.37 + sd * 3.0)) * (1.45 if gait == "biped" else 1.0)
	# turning: the tail swings wide and catches up (the heading's rate, smoothed)
	var yaw_now := rig.global_rotation.y if rig.is_inside_tree() else 0.0
	var yr := 0.0
	if mem.has("yaw") and dt > 0.0:
		yr = wrapf(yaw_now - float(mem["yaw"]), -PI, PI) / dt
	mem["yaw"] = yaw_now
	var turn: float = lerpf(float(mem.get("turn", 0.0)), clampf(yr, -6.0, 6.0), 1.0 - exp(-dt * 4.0))
	mem["turn"] = turn
	var flick := 0.0
	var fa: float = float(mem.get("flick_at", 5.0))
	if t > fa:
		mem["flick_t0"] = t
		mem["flick_at"] = t + randf_range(FLICK_EVERY.x, FLICK_EVERY.y)
	var f0: float = float(mem.get("flick_t0", -10.0))
	if t - f0 < 0.9:
		flick = sin((t - f0) / 0.9 * PI)
	var nt := maxf(1.0, tail.size())
	for i in tail.size():
		var k := float(i + 1) / nt
		var yaw := tail_amp * (0.35 + 0.9 * k) * sin(wag - i * 0.55) + 0.1 * m * sin(ph - i * 0.5)
		yaw += -turn * 0.06 * (0.4 + k) * sin(clampf(1.0 - i * 0.15, 0.0, 1.0) * PI * 0.5 + 0.6)
		if fly >= 0.0:
			yaw *= 0.4      # streamlined in the air
		yaw += flick * 0.55 * k * k * (1.0 if fmod(f0, 2.0) < 1.0 else -1.0)
		yaw += hit * 0.35 * sin(t * 22.0 - i) * k
		var pit := -0.02
		if i == 0:
			pit = 0.18 * mw + 0.14 * run - 0.06 * calm
		elif i < 3:
			pit = -0.04 + 0.03 * run
		pit += flick * 0.25 * k * k
		_add(P, tail[i], pit, yaw)

	# --- the basic attack: claw, bite, spin (and a roar for anything else)
	var spin := 0.0
	var lift_y := 0.0
	if a >= 0.0:
		var env := _sm(0.0, 0.18, a) * (1.0 - _sm(0.78, 1.0, a))
		match style:
			"swipe1":
				# rear a little, the foreclaw (the wyvern's wing claw) raised then raked down on the impact (0.4)
				var raise := _sm(0.0, 0.3, a) * (1.0 - _sm(0.42, 0.75, a))
				var rake := _sm(0.3, 0.42, a)
				lift_y = 0.12 * raise
				for s in spine:
					_add(P, s, -0.1 * raise / maxf(1.0, spine.size()))
				if gait == "biped":
					_wing(P, "arm_R_0", -0.45 * raise + 0.5 * rake * env, -0.9 * raise + 0.4 * rake * env)
					_wing(P, "arm_R_1", 0.0, -0.4 * raise)
				else:
					_add(P, "leg_FR_0", lerpf(-1.3 * raise, 0.35, rake) * env, -0.25 * raise)
					_add(P, "leg_FR_1", 0.9 * raise * (1.0 - rake))
				for i in neck.size():
					_add(P, neck[i], 0.12 * rake * env / nn, -0.15 * env / nn)
				jaw += 0.25 * raise
			"swipe2":
				# the bite: draw the head back and up, lunge, snap shut on the impact (0.42)
				var draw := _sm(0.0, 0.28, a) * (1.0 - _sm(0.3, 0.42, a))
				var strike := _sm(0.3, 0.42, a) * (1.0 - _sm(0.62, 0.95, a))
				for i in neck.size():
					_add(P, neck[i], (-0.35 * draw + 0.45 * strike) / nn)
				_add(P, "head_0", -0.2 * draw + 0.25 * strike)
				jaw += 0.65 * _sm(0.1, 0.36, a) * (1.0 - _sm(0.4, 0.45, a))
				lift_y = -0.06 * strike
			"swipe3":
				# a full spin that sweeps the tail round in front (impact 0.47 halfway round), tail flung out wide
				spin = TAU * _sm(0.12, 0.82, a)
				var out := env
				for i in tail.size():
					var k := float(i + 1) / nt
					_add(P, tail[i], 0.06 * out, -0.18 * out * (0.4 + k))     # trailing the spin (it turns left)
				for s in spine:
					_add(P, s, 0.0, -0.08 * out)
				if winged:
					wing_lo -= 0.45 * out
					wing_bk -= 0.3 * out
				jaw += 0.3 * out
			_:
				# a roar (skills to come): head up, jaws wide, wings flared
				for i in neck.size():
					_add(P, neck[i], -0.25 * env / nn)
				_add(P, "head_0", -0.3 * env)
				jaw += 0.75 * env
				if winged:
					wing_lo -= 0.5 * env
					wing_bk -= 0.35 * env

	# --- block: hunker down behind the wings (the serpent coils), head tucked
	if blk > 0.0:
		lift_y -= 0.18 * blk
		for i in neck.size():
			_add(P, neck[i], 0.3 * blk / nn)
		_add(P, "head_0", 0.15 * blk)
		if winged and gait == "biped":
			# the wyvern wraps itself in its wings (jj): raised, swept round to the front and closed over it
			wing_lo += -0.35 * blk - fold * blk
			wing_bk -= 1.45 * blk
			for i in neck.size():
				_add(P, neck[i], 0.18 * blk / nn)
		elif winged:
			wing_lo += 0.1 * blk - fold * blk
			wing_bk -= 0.75 * blk
		else:
			for s in spine:
				_add(P, s, 0.0, 0.25 * blk)
	# hit: the head jerks back
	if hit > 0.0:
		for i in neck.size():
			_add(P, neck[i], -0.3 * hit / nn)
		_add(P, "head_0", -0.15 * hit)

	if winged:
		for side in ["L", "R"]:
			_wing(P, "arm_" + side + "_0", wing_lo - flap + wsway * (1.0 if side == "L" else -1.0), wing_bk * 0.6)
			_wing(P, "arm_" + side + "_1", wing_lo * 0.4 - flap * 0.5, wing_bk * 1.1)
			var f := 1
			while info.has("fing%d_%s_0" % [f, side]):
				# (the fingers curl in round it when the wings close for a block)
				_wing(P, "fing%d_%s_0" % [f, side], 0.1 * wing_lo - flap * 0.3, wing_bk * 0.6 - 0.35 * blk * (1.0 if gait == "biped" else 0.0))
				_wing(P, "fing%d_%s_1" % [f, side], 0.05 * wing_lo - flap * 0.15, wing_bk * 0.3 - 0.3 * blk * (1.0 if gait == "biped" else 0.0))
				f += 1

	# --- death: it slumps and rolls onto its side, neck and tail limp, wings sagging
	if dead > 0.0:
		var d := _sm(0.0, 1.0, dead)
		for i in neck.size():
			_add(P, neck[i], 0.35 * d / nn * 2.0)
		_add(P, "head_0", 0.3 * d)
		jaw = lerpf(jaw, 0.35, d)
		for lg in legs:
			_add(P, lg + "_0", 0.25 * d)
			_add(P, lg + "_1", 0.6 * d)
		if winged:
			for side in ["L", "R"]:
				_wing(P, "arm_" + side + "_0", 0.5 * d, 0.2 * d)
	_add(P, "jaw_0", jaw)

	# --- apply: every bone from its rest plus this frame's turns
	for bone in info:
		var b: Array = info[bone]
		var q: Quaternion = b[1]
		var v: Vector3 = P.get(bone, Vector3.ZERO)
		if v.x != 0.0:
			q = q * Quaternion(b[2] as Vector3, v.x)
		if v.y != 0.0:
			q = q * Quaternion(b[3] as Vector3, v.y)
		if v.z != 0.0:
			q = q * Quaternion(b[4] as Vector3, v.z)
		sk.set_bone_pose_rotation(int(b[0]), q)
	var dd := _sm(0.0, 1.0, dead)
	hold.position = Vector3(0.0, bob + lift_y - dd * float(sp["h"]) * 0.12, 0.0)
	hold.rotation = Vector3(0.0, spin, dd * 1.25)

	# --- sounds: footfalls (each pair landing), the wyvern's wing beats at a sprint
	var step := int(floor(ph / PI))
	if m > 0.25 and step != int(mem.get("step", step)) and rig.is_inside_tree():
		# the Sfx autoload looked up at run time: Anim (which every tool loads) reaches this script, and a -s tool
		# compiles before autoloads exist
		var sfx: Node = rig.get_tree().root.get_node_or_null("Sfx")
		if sfx != null:
			var at := rig.global_position
			sfx.call("play_at", c + "_step", at, -4.0 + 4.0 * run, randf_range(0.92, 1.06))
			if gait == "biped" and run > 0.5 and step % 2 == 0:
				sfx.call("play_at", "wyvern_flap", at, -6.0, randf_range(0.95, 1.05))
	mem["step"] = step

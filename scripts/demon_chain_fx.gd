class_name DemonChainFx
extends RefCounted
## Hellgrip's look, "Chain of the Pit" (the Demon's G; the gameplay is DemonSkills). Forged iron and sparks, not
## hellfire: nothing here is Molten Fists'.
##
##  The reach ("cast"): his forearm glows forge-hot, sparks spit off it.
##  The fling ("fling" {p, d, x: the time out, r: the reach}): the chain (the Meshy forged-iron chain, section after
##  section laid end to end from his hand to its head) pays out at full speed, the sections nearest his arm
##  glowing cherry-red and the rest dull iron, sparks grinding off it as it goes; the Meshy iron claw leads it,
##  talons first.
##  The hook ("hook" {t | pid, p, x: the haul, n: 1 = he is dragged to it}): the claw bites with a clang, a burst of
##  sparks and a puff of dust; the chain draws taut (it straightens and shivers) and hauls them in (or him to them).
##  A miss ("miss" {p}): the claw snaps shut on nothing in a few sparks and the chain whips back to his arm.
##  The smash ("smash" {p, t, x}): driven into the ground: the earth crushed in round them (a Meshy-painted mark),
##  chunks of ground and a cloud of dust (simulated) thrown up, a shock ring, the chain gone in the dust.
## State: h.fxs["chain"], kept by `update`.

const SEG := 1.2                 # one chain section's length (assets/models/fx/demon/chain.glb, laid along x)
const SEG_SCALE := 0.78          # its size in play (thick enough to read from the game camera: a skillshot to dodge)
const MAX_SEGS := 16
const CLAW_SIZE := 0.7

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"fling":
			_fling(h, ev)
		"hook":
			_hook(h, ev)
		"miss":
			_miss(h, ev)
		"smash":
			_smash(h, ev)
		"end":
			_retract(h)
		"cast":
			_reach(h)
		_:
			return false
	return true

## The forearm glowing forge-hot as he reaches back.
static func _reach(h: Hero) -> void:
	_end(h)
	var root: Node3D = h.game.world.fx_root
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.35, 0.1)
	l.light_energy = 1.4
	l.omni_range = 2.6
	l.shadow_enabled = false
	root.add_child(l)
	var tr := InfernalFx.tier(h.game)
	var sp := InfernalFx.particles(root, SkillFx.hand(h, true), {"amount": [5, 8, 12, 14][tr], "life": 0.35, "one_shot": false,
		"dir": Vector3.UP, "spread": 80.0, "vel": [1.0, 3.0], "gravity": -9.0, "scale": [0.5, 1.0], "size": 0.035,
		"colors": [[0.0, Color(1.0, 0.95, 0.8)], [0.4, Color(1.0, 0.6, 0.2)], [1.0, Color(0.8, 0.15, 0.02, 0.0)]]})
	h.fxs["chain"] = {"state": "ready", "light": l, "spit": sp, "until": 3.0, "len": 0.0, "max": DemonSkills.CHAIN_LEN,
		"dir": h.facing(), "speed": DemonSkills.CHAIN_SPEED, "segs": [], "grind": 0.0}
	SkillFx.snd(h, "impact_metal", -12.0, 0.7)

static func _fling(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var st: Dictionary = h.fxs.get("chain", {})
	if st.is_empty() or str(st.get("state", "")) != "ready":
		_reach(h)
		st = h.fxs["chain"]
	st["state"] = "out"
	st["dir"] = ev.get("d", h.facing())
	st["len"] = 0.0
	st["max"] = float(ev.get("r", DemonSkills.CHAIN_LEN))
	st["speed"] = st["max"] / maxf(float(ev.get("x", 0.3)), 0.05)
	st["until"] = 4.0
	# the sections, made now and shown as the chain pays out
	var segs: Array = []
	var n := mini(int(ceil(float(st["max"]) / (SEG * SEG_SCALE))) + 1, MAX_SEGS)
	for i in n:
		var s := DemonKitFx.model(DemonKitFx.CHAIN)
		if s == null:
			break
		DemonKitFx.heat_model(s, 0.0, Color(1.0, 0.25, 0.05))
		s.scale = Vector3.ONE * SEG_SCALE
		s.visible = false
		root.add_child(s)
		segs.append(s)
	st["segs"] = segs
	var claw := Node3D.new()
	root.add_child(claw)
	var cm := DemonKitFx.model(DemonKitFx.CLAW)
	if cm != null:
		DemonKitFx.heat_model(cm, 0.5, Color(1.0, 0.3, 0.06))
		# modelled upright with the chain ring on top: laid along the chain, talons leading
		cm.rotation = Vector3(-PI * 0.5, 0, 0)
		cm.position = Vector3(0, 0, -CLAW_SIZE * 0.5)
		cm.scale = Vector3.ONE * CLAW_SIZE
		claw.add_child(cm)
	st["claw"] = claw
	SkillFx.snd(h, "cleave_swing", -3.0, 0.75)
	SkillFx.snd(h, "shackles", -6.0, 0.8)

static func _hook(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var st: Dictionary = h.fxs.get("chain", {})
	if st.is_empty():
		return
	var vs := DemonKitFx.targets(h, ev)
	var p: Vector3 = ev.get("p", h.global_position)
	st["state"] = "hooked"
	st["self"] = int(ev.get("n", 0)) == 1
	st["until"] = float(ev.get("x", 0.5)) + 2.5
	if not vs.is_empty():
		st["victim"] = vs[0]
	DemonKitFx.sparks(root, p, -(st["dir"] as Vector3) + Vector3(0, 0.5, 0), [14, 20, 28, 34][tr], 60.0, Vector2(4.0, 10.0))
	DemonKitFx.flash_light(root, p, Color(1.0, 0.7, 0.4), 2.5, 4.0, 0.2)
	var gp := p
	gp.y = h.game.world.height_at(p.x, p.z)
	DemonKitFx.smoke(root, gp, "ash", 1.4, 0.9)
	Sfx.play_at("impact_metal", p, -2.0, 0.8)
	Sfx.play_at("shackles", p, -6.0, 1.1)
	SkillFx.shake(h, 0.18)

static func _miss(h: Hero, ev: Dictionary) -> void:
	var st: Dictionary = h.fxs.get("chain", {})
	if st.is_empty():
		return
	st["state"] = "back"
	st["until"] = 1.5
	var p: Vector3 = ev.get("p", h.global_position)
	DemonKitFx.sparks(h.game.world.fx_root, p, Vector3.UP, 6, 80.0, Vector2(1.5, 4.0), 0.3)
	Sfx.play_at("impact_metal", p, -12.0, 1.3)

## The smash: the ground crushed in round them, chunks and dust thrown up, the chain gone.
static func _smash(h: Hero, ev: Dictionary) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var at: Vector3 = ev["p"]
	at.y = world.height_at(at.x, at.z)
	var held: bool = bool(ev.get("x", false))
	DemonKitFx.decal(root, at, "crush", Vector2(DemonSkills.GRIP_SHOCK_R * 2.0, DemonSkills.GRIP_SHOCK_R * 2.0), randf() * TAU, 5.0, 0.5 if held else 0.2)
	DemonKitFx.smoke(root, at, "impact", DemonSkills.GRIP_SHOCK_R * (1.6 if held else 1.0), 1.5)
	DemonKitFx.pieces(root, world, at + Vector3(0, 0.2, 0), DemonKitFx.BOULDER_PIECES, 0.32 if held else 0.2, 5.5, 1.2, 2.2, 1.0, Vector3.ZERO, tr >= 2)
	DemonKitFx.clods(root, at + Vector3(0, 0.2, 0), [12, 18, 26, 32][tr], 5.0)
	DemonKitFx.shock_ring(root, h.game, at, DemonSkills.GRIP_SHOCK_R * 1.2, 0.3)
	DemonKitFx.flash_light(root, at + Vector3(0, 0.8, 0), Color(1.0, 0.55, 0.25), 3.5 if held else 1.5, 6.0, 0.4)
	_end(h)
	Sfx.play_at("slam", at, 0.0 if held else -6.0, 0.8)
	Sfx.play_at("boom", at, -6.0, 0.85)
	Sfx.play_at("impact_bone", at, -6.0, 0.6)
	SkillFx.shake(h, 0.45 if held else 0.15)

static func _retract(h: Hero) -> void:
	var st: Dictionary = h.fxs.get("chain", {})
	if st.is_empty():
		return
	st["state"] = "back"
	st["until"] = minf(float(st.get("until", 1.0)), 1.2)

static func _end(h: Hero) -> void:
	if not h.fxs.has("chain"):
		return
	var st: Dictionary = h.fxs["chain"]
	h.fxs.erase("chain")
	for s in st.get("segs", []):
		if is_instance_valid(s):
			(s as Node).queue_free()
	for key in ["claw", "light"]:
		var n = st.get(key)
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	var sp = st.get("spit")
	if sp != null and is_instance_valid(sp):
		(sp as GPUParticles3D).emitting = false
		Fx._free_later(sp, 0.5)

## Every frame: the chain from his hand to its head (paying out, held taut, or coming back).
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("chain"):
		return
	var st: Dictionary = h.fxs["chain"]
	st["until"] = float(st["until"]) - delta
	if float(st["until"]) <= 0.0:
		_end(h)
		return
	var hand := SkillFx.hand(h, true)
	var sp = st.get("spit")
	if sp != null and is_instance_valid(sp):
		(sp as Node3D).global_position = hand
	var l = st.get("light")
	if l != null and is_instance_valid(l):
		(l as OmniLight3D).global_position = hand
	var dir: Vector3 = st["dir"]
	var tip: Vector3
	match str(st["state"]):
		"ready":
			return
		"out":
			st["len"] = minf(float(st["len"]) + float(st["speed"]) * delta, float(st["max"]))
			tip = hand + dir * float(st["len"])
		"hooked":
			var v = st.get("victim")
			if v != null and is_instance_valid(v):
				tip = DemonKitFx.chest(v, 0.6)
			else:
				st["state"] = "back"
				tip = hand + dir * float(st["len"])
			st["len"] = (tip - hand).length()
		"back":
			st["len"] = maxf(float(st["len"]) - 26.0 * delta, 0.0)
			tip = hand + dir * float(st["len"])
			if float(st["len"]) <= 0.05:
				_end(h)
				return
		_:
			tip = hand
	var claw = st.get("claw")
	if claw != null and is_instance_valid(claw):
		(claw as Node3D).global_position = tip
		var fw := tip - hand
		if fw.length() > 0.05:
			(claw as Node3D).look_at(tip + fw.normalized(), Vector3.UP if absf(fw.normalized().y) < 0.95 else Vector3.RIGHT)
	var taut := str(st["state"]) == "hooked"
	_lay(st, hand, tip, h.anim_time, taut)
	# sparks grinding off it while it moves
	st["grind"] = float(st["grind"]) - delta
	if float(st["grind"]) <= 0.0 and str(st["state"]) != "ready" and (tip - hand).length() > 0.5:
		st["grind"] = 0.07
		var u := randf()
		DemonKitFx.sparks(h.game.world.fx_root, hand.lerp(tip, u), Vector3.UP, 2, 70.0, Vector2(1.0, 3.0), 0.3)

## The sections end to end along a slight sag from his hand to the head; the ones by his arm glow hot.
static func _lay(st: Dictionary, a: Vector3, b: Vector3, t: float, taut: bool) -> void:
	var segs: Array = st.get("segs", [])
	var d := b - a
	var len := d.length()
	var step := SEG * SEG_SCALE
	var n := mini(int(ceil(len / step)), segs.size())
	var axis := d / maxf(len, 0.001)
	var sag := (0.04 if taut else 0.22) * len / DemonSkills.CHAIN_LEN
	for i in segs.size():
		var s: Node3D = segs[i]
		if not is_instance_valid(s):
			continue
		s.visible = i < n
		if i >= n:
			continue
		var u0 := float(i) * step / maxf(len, 0.001)
		var u := clampf(u0 + step * 0.5 / maxf(len, 0.001), 0.0, 1.0)
		var p := a + d * u - Vector3(0, sin(u * PI) * sag, 0)
		if taut:
			p += axis.cross(Vector3.UP).normalized() * sin(u * 30.0 + t * 40.0) * 0.012
		var up := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
		var z := axis.cross(up).normalized()
		var y := z.cross(axis)
		# each section turned a quarter about the chain from the last, so the links read as interlocked
		s.basis = Basis(axis, y, z).rotated(axis, PI * 0.5 * float(i % 2)).scaled(Vector3.ONE * SEG_SCALE)
		s.global_position = p
		# a dull forge-red the whole way (the chain reads on dark ground), white-hot by his arm, throbbing when taut
		var heat := 0.55 + clampf(1.0 - u * 2.2, 0.0, 1.0) * 2.4 + (0.6 if taut else 0.0) * (0.6 + 0.4 * sin(t * 12.0 + u * 9.0))
		DemonKitFx.set_heat(s, heat)

static func clear(h: Hero) -> void:
	_end(h)

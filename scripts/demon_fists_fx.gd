class_name DemonFistsFx
extends RefCounted
## Molten Fists' look, "Hellbrand" (the Demon's Q; the gameplay is DemonSkills, unchanged). Built from InfernalFx.
##
##  Gather, from the "cast" event to the blow (Anim.impact_at "fists"): his fists catch fire as hellfire gauntlets
##  (a black flame shell round a molten core, embers streaming off, crimson motes pulled in, a light between his
##  hands), the magma in his cracks runs down his arms into them (the body shader's `brand`), and his sigil draws
##  itself on the ground under him, turning faster as the blow comes.
##  Release, the "impact" event {y, r, t}: a white-gold flash at the fists, the sigil flares, the ground tears open
##  in a wedge of cracks running out to the tip with a light sweeping along it, a crescent wave of fire (and heat
##  haze from High), a fan of obsidian fangs bursting up near to far that crack white and shatter into burning
##  fragments, tongues of hellfire along the fissures, rolling smoke lit from below, embers, earth thrown up. Each
##  foe struck: a molten flash in place of the white one, a hot splash out of its far side, a lick of hellfire and
##  a stagger of its body (visual only: the rig tilts away and springs back; nothing moves it). Then the rift cools
##  to black, the sigil burns down.
##
## State: h.fxs["fists"] (the gauntlets, the light, the sigil; on the caster and on his puppet alike, kept by
## `update`, timing itself out if the impact never comes) and h.fxs["fists_stag"] (the staggering bodies).
## Budgets by InfernalFx.tier: the counts below are [Low, Medium, High, Ultra].

const IMPACT := 0.48
const SIGIL_R := 1.6
const SHARDS := [5, 8, 11, 13]
const FRAGS := [0, 3, 4, 5]
const TONGUES := [3, 5, 7, 9]
const SMOKE_N := [4, 7, 11, 14]
const EMBERS := [14, 26, 42, 56]
const HAND_EMBERS := [8, 14, 22, 26]
const MOTES := [0, 12, 18, 24]

static var _warm_world := 0

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["e"]):
		"cast":
			_gather(h, ev)
		"impact":
			_release(h, ev)
		_:
			return false
	return true

# ---------------------------------------------------------------- the gather
static func _gather(h: Hero, _ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var st: Dictionary = h.fxs.get("fists", {})
	_drop_hands(st, true)
	st["stage"] = "gather"
	st["t"] = 0.0
	st["k"] = 0.0
	st["whoosh"] = false
	var hands := []
	for right in [false, true]:
		hands.append(_hand(h, root, tr, right))
	st["hands"] = hands
	var l := OmniLight3D.new()
	l.light_color = InfernalFx.BLOODFIRE
	l.light_energy = 0.0
	l.omni_range = 4.5
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = h.global_position + Vector3(0, 1.2, 0)
	st["light"] = l
	# the brand under him (one at a time: a quick follow-up redraws the one already burning)
	var at := h.global_position
	at.y = h.game.world.height_at(at.x, at.z)
	var sg = st.get("sigil")
	if sg == null or not is_instance_valid(sg) or (sg as Node3D).global_position.distance_to(at) > 0.9:
		_drop_sigil(st)
		var mat := InfernalFx.sigil_mat()
		var mi := MeshInstance3D.new()
		mi.mesh = InfernalFx.disc_mesh(h.game.world, at, SIGIL_R, 40, 5, 0.035)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.global_position = at
		st["sigil"] = mi
		st["sig_mat"] = mat
		st["draw"] = 0.0
		st["spin"] = randf() * TAU
		if tr >= 1:
			# dark wisps curling up off its rim
			var q := QuadMesh.new()
			q.size = Vector2(0.75, 0.75)
			q.material = InfernalFx.smoke_mat(0.8, 0.55)
			var w := InfernalFx.particles(mi, at + Vector3(0, 0.1, 0), {"amount": 6 + 3 * tr, "life": 1.3, "one_shot": false,
				"shape": "ring", "r": SIGIL_R * 0.92, "r_in": SIGIL_R * 0.8, "dir": Vector3.UP, "spread": 15.0, "vel": [0.3, 0.7],
				"gravity": 0.25, "scale": [0.6, 1.1], "grow": [0.5, 1.4], "angle": true, "spin": 30.0, "mesh": q,
				"colors": [[0.0, Color(1, 1, 1, 0)], [0.2, Color(1, 1, 1, 0.8)], [1.0, Color(1, 1, 1, 0)]]})
			st["wisps"] = w
	else:
		st["draw"] = minf(float(st.get("draw", 0.0)), 0.45)
	st["sig_life"] = 1.0
	st["flare"] = 0.0
	h.fxs["fists"] = st
	SkillFx.snd(h, "fireball", -11.0, 0.6)
	SkillFx.snd(h, "growl", -9.0, 0.72)

## One hellfire gauntlet: a black flame shell, a hot flame inside, a molten core glow, embers streaming off as the
## hand moves (world-space particles), and crimson motes drawn in from round it while he gathers.
static func _hand(h: Hero, root: Node3D, tr: int, right: bool) -> Dictionary:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = SkillFx.hand(h, right)
	var dark := InfernalFx.flame_mat(0.95, 0.9, 1.5)
	var hot := InfernalFx.flame_mat(0.15, 1.4, 2.0)
	var f1 := InfernalFx.flame(n, n.global_position, Vector2(0.62, 0.95), dark)
	var f2 := InfernalFx.flame(n, n.global_position, Vector2(0.36, 0.6), hot)
	var core_mat := InfernalFx.glow_mat(InfernalFx.MOLTEN, 2.6, 2.4)
	var core := InfernalFx.glow(n, n.global_position, 0.5, core_mat)
	var em := InfernalFx.particles(n, n.global_position, {"amount": HAND_EMBERS[tr], "life": 0.5, "one_shot": false,
		"shape": "sphere", "r": 0.12, "dir": Vector3.UP, "spread": 40.0, "vel": [0.6, 1.6], "gravity": 2.0,
		"scale": [0.5, 1.0], "size": 0.06,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.3, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	var motes: GPUParticles3D = null
	if MOTES[tr] > 0:
		motes = InfernalFx.particles(n, n.global_position, {"amount": MOTES[tr], "life": 0.32, "one_shot": false,
			"shape": "sphere", "r": 0.85, "dir": Vector3.UP, "spread": 180.0, "vel": [0.0, 0.2], "radial": [-16.0, -11.0],
			"scale": [0.5, 1.0], "size": 0.05,
			"colors": [[0.0, Color(InfernalFx.CRIMSON, 0.0)], [0.45, InfernalFx.BLOODFIRE], [1.0, InfernalFx.MOLTEN]]})
	return {"node": n, "right": right, "dark": dark, "hot": hot, "core": core, "core_mat": core_mat, "f1": f1, "f2": f2,
		"em": em, "motes": motes}

# ---------------------------------------------------------------- every frame
static func update(h: Hero, delta: float) -> void:
	if h.fxs.has("fists_stag"):
		_staggers(h, delta)
	if _warm_world != h.game.world.get_instance_id() and h.is_inside_tree():
		_warm_world = h.game.world.get_instance_id()
		InfernalFx.warm(h, h.game)
	if not h.fxs.has("fists"):
		return
	var st: Dictionary = h.fxs["fists"]
	st["t"] = float(st["t"]) + delta
	var a := SkillFx.atk(h)
	var mine := SkillFx.style(h) == "fists" and a >= 0.0
	var k: float = float(st.get("k", 0.0))
	var flare := 0.0
	match str(st["stage"]):
		"gather":
			if mine:
				k = smoothstep(0.0, 0.36, a)
				if not bool(st["whoosh"]) and a >= 0.34:
					st["whoosh"] = true
					SkillFx.snd(h, "swing_heavy", -4.0, 0.78)
			elif float(st["t"]) > 0.2:
				st["stage"] = "fade"          # cut short (a hit, a dodge, another skill)
			if float(st["t"]) > 1.6:
				st["stage"] = "fade"          # a partner's copy whose impact never came
		"release":
			st["rel_t"] = float(st.get("rel_t", 0.0)) + delta
			var rt: float = float(st["rel_t"])
			flare = 1.0 - smoothstep(0.0, 0.3, rt)
			k = 1.0 - smoothstep(0.12, 0.4, rt)
			if rt > 0.42:
				_drop_hands(st, false)
		"fade":
			k = maxf(k - delta * 5.0, 0.0)
			if k <= 0.0:
				_drop_hands(st, false)
	st["k"] = k
	var hl := Vector3(0, -100, 0)
	var hr := Vector3(0, -100, 0)
	var hands: Array = st.get("hands", [])
	for hd in hands:
		var n: Node3D = hd["node"]
		if not is_instance_valid(n):
			continue
		var p := SkillFx.hand(h, bool(hd["right"]))
		n.global_position = p
		if bool(hd["right"]):
			hr = p
		else:
			hl = p
		var s := (0.25 + 0.75 * k) * (1.0 + 0.45 * flare)
		(hd["f1"] as Node3D).scale = Vector3(0.62 * s, 0.95 * s, 1.0)
		(hd["f1"] as Node3D).position = Vector3(0, -0.14 * s, 0)
		(hd["f2"] as Node3D).scale = Vector3(0.36 * s, 0.6 * s, 1.0)
		(hd["f2"] as Node3D).position = Vector3(0, -0.07 * s, 0)
		(hd["dark"] as ShaderMaterial).set_shader_parameter("alpha", clampf(k * 1.3, 0.0, 1.0))
		(hd["hot"] as ShaderMaterial).set_shader_parameter("alpha", clampf(k * 1.5, 0.0, 1.0))
		(hd["hot"] as ShaderMaterial).set_shader_parameter("heat", 0.9 + 0.8 * k + 1.6 * flare)
		(hd["core"] as Node3D).scale = Vector3.ONE * (0.3 + 0.35 * k + 0.6 * flare)
		(hd["core_mat"] as ShaderMaterial).set_shader_parameter("alpha", clampf(k * 1.2 + flare, 0.0, 1.0))
		(hd["core_mat"] as ShaderMaterial).set_shader_parameter("energy", 2.2 + 1.5 * k + 3.0 * flare)
		(hd["em"] as GPUParticles3D).emitting = k > 0.08
		if hd["motes"] != null:
			(hd["motes"] as GPUParticles3D).emitting = str(st["stage"]) == "gather" and k > 0.05
	var l = st.get("light")
	if l != null and is_instance_valid(l):
		var mid := (hl + hr) * 0.5 if hands.size() == 2 and hl.y > -50.0 else h.global_position + Vector3(0, 1.2, 0)
		(l as OmniLight3D).global_position = mid
		var fl := 0.85 + 0.15 * sin(h.anim_time * 31.0) * sin(h.anim_time * 11.7)
		(l as OmniLight3D).light_energy = (0.4 + 2.0 * k + 3.0 * flare) * fl
		(l as OmniLight3D).light_color = InfernalFx.BLOODFIRE.lerp(InfernalFx.MOLTEN, clampf(k * 0.6 + flare, 0.0, 1.0))
		if k <= 0.0 and str(st["stage"]) != "gather":
			(l as Node).queue_free()
			st.erase("light")
	_brand_body(h, k + flare * 0.5, hl, hr)
	# the sigil
	var sg = st.get("sigil")
	if sg != null and is_instance_valid(sg):
		var m: ShaderMaterial = st["sig_mat"]
		var draw: float = float(st.get("draw", 0.0))
		if str(st["stage"]) == "gather" and mine:
			draw = maxf(draw, clampf(a / (IMPACT - 0.06), 0.0, 1.0))
		elif str(st["stage"]) == "release":
			draw = 1.0
		st["draw"] = draw
		st["spin"] = float(st.get("spin", 0.0)) + delta * (0.5 + 2.6 * k + 6.0 * flare)
		var f: float = maxf(float(st.get("flare", 0.0)) - delta * 3.0, 0.0)
		st["flare"] = f
		if str(st["stage"]) != "gather":
			st["sig_life"] = maxf(float(st["sig_life"]) - delta / 2.4, 0.0)
		m.set_shader_parameter("draw", draw)
		m.set_shader_parameter("spin", float(st["spin"]))
		m.set_shader_parameter("flare", f)
		m.set_shader_parameter("life", float(st["sig_life"]))
		if float(st["sig_life"]) <= 0.0:
			_drop_sigil(st)
	if not st.has("hands") and not st.has("sigil") and not st.has("light"):
		h.fxs.erase("fists")

## The magma in his cracks runs down into his fists and burns white round them (the body shader).
static func _brand_body(h: Hero, k: float, hl: Vector3, hr: Vector3) -> void:
	if h.rig == null or not h.rig.has_meta("demon_mats"):
		return
	for m in h.rig.get_meta("demon_mats"):
		(m as ShaderMaterial).set_shader_parameter("brand", clampf(k, 0.0, 1.5))
		(m as ShaderMaterial).set_shader_parameter("hand_l", hl)
		(m as ShaderMaterial).set_shader_parameter("hand_r", hr)

static func _drop_hands(st: Dictionary, now: bool) -> void:
	for hd in st.get("hands", []):
		var n = hd["node"]
		if n == null or not is_instance_valid(n):
			continue
		if now:
			(n as Node).queue_free()
		else:
			# let the embers already flying finish
			(hd["em"] as GPUParticles3D).emitting = false
			if hd["motes"] != null:
				(hd["motes"] as GPUParticles3D).emitting = false
			for key in ["f1", "f2", "core"]:
				(hd[key] as Node3D).visible = false
			Fx._free_later(n, 0.6)
	st.erase("hands")

static func _drop_sigil(st: Dictionary) -> void:
	var sg = st.get("sigil")
	if sg != null and is_instance_valid(sg):
		var w = st.get("wisps")
		if w != null and is_instance_valid(w):
			(w as GPUParticles3D).emitting = false
			(w as Node3D).reparent((sg as Node).get_parent())
			Fx._free_later(w, 1.5)
		(sg as Node).queue_free()
	st.erase("sigil")
	st.erase("sig_mat")
	st.erase("wisps")

## Everything of it is gone at once (death, a class change, a zone change).
static func clear(h: Hero) -> void:
	if h.fxs.has("fists"):
		var st: Dictionary = h.fxs["fists"]
		_drop_hands(st, true)
		_drop_sigil(st)
		var l = st.get("light")
		if l != null and is_instance_valid(l):
			(l as Node).queue_free()
		h.fxs.erase("fists")
	if h.fxs.has("fists_stag"):
		for s in h.fxs["fists_stag"]:
			_unstagger(s)
		h.fxs.erase("fists_stag")
	if h.rig != null and is_instance_valid(h.rig):
		_brand_body(h, 0.0, Vector3(0, -100, 0), Vector3(0, -100, 0))

# ---------------------------------------------------------------- the blow
static func _release(h: Hero, ev: Dictionary) -> void:
	var world = h.game.world
	var root: Node3D = world.fx_root
	var tr := InfernalFx.tier(h.game)
	var yaw: float = float(ev.get("y", h.rig.global_rotation.y))
	var reach: float = float(ev.get("r", DemonSkills.FISTS_R))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var wide := reach > DemonSkills.FISTS_R + 0.5
	var half := deg_to_rad(DemonSkills.FISTS_HALF + (12.0 if wide else 0.0) + 6.0)
	var pos := h.global_position
	pos.y = world.height_at(pos.x, pos.z)
	var hit: Array = ev.get("t", [])
	var st: Dictionary = h.fxs.get("fists", {"t": 0.0, "k": 1.0, "sig_life": 0.0})
	st["stage"] = "release"
	st["rel_t"] = 0.0
	st["flare"] = 1.0
	st["sig_life"] = maxf(float(st.get("sig_life", 0.0)), 1.0) if st.has("sigil") else 0.0
	h.fxs["fists"] = st
	var fist := pos + Vector3(0, 1.1, 0) + fwd * 1.0
	var hands: Array = st.get("hands", [])
	if hands.size() == 2 and is_instance_valid(hands[0]["node"]) and is_instance_valid(hands[1]["node"]):
		fist = ((hands[0]["node"] as Node3D).global_position + (hands[1]["node"] as Node3D).global_position) * 0.5
	# the flash at the fists: a white-gold star over a wide blood-red bloom
	var f1 := InfernalFx.glow_mat(InfernalFx.WHITEHOT, 3.2, 1.7, 1.2)
	var g1 := InfernalFx.glow(root, fist, 0.6, f1)
	var tw1 := g1.create_tween().set_parallel(true)
	tw1.tween_property(g1, "scale", Vector3.ONE * 3.4, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	InfernalFx.tween_param(g1, f1, "alpha", 1.0, 0.0, 0.2)
	Fx._free_later(g1, 0.25)
	var f2 := InfernalFx.glow_mat(InfernalFx.BLOODFIRE, 2.0, 1.3)
	var g2 := InfernalFx.glow(root, fist, 1.0, f2)
	g2.create_tween().tween_property(g2, "scale", Vector3.ONE * 5.0, 0.3).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g2, f2, "alpha", 0.8, 0.0, 0.32)
	Fx._free_later(g2, 0.36)
	Fx.flash(root, fist, InfernalFx.WHITEHOT, 5.0, 0.16, 6.0)
	# a light running out along the rift, then dying to crimson
	var sw := OmniLight3D.new()
	sw.light_color = InfernalFx.MOLTEN
	sw.light_energy = 4.5
	sw.omni_range = 4.8
	sw.shadow_enabled = false
	root.add_child(sw)
	sw.global_position = pos + Vector3(0, 0.6, 0) + fwd * 0.5
	var tws := sw.create_tween()
	tws.tween_property(sw, "global_position", pos + fwd * reach * 0.85 + Vector3(0, 0.55, 0), 0.16).set_ease(Tween.EASE_OUT)
	tws.set_parallel(true)
	tws.tween_property(sw, "light_energy", 0.0, 0.7).set_delay(0.16)
	tws.tween_property(sw, "light_color", InfernalFx.CRIMSON, 0.5).set_delay(0.16)
	Fx._free_later(sw, 0.95)
	# the rift
	var rm := InfernalFx.rift_mat()
	rm.set_shader_parameter("span", reach / DemonSkills.FISTS_R)
	var rift := MeshInstance3D.new()
	rift.mesh = InfernalFx.wedge_mesh(world, pos, yaw, 0.25, reach * 1.12, half, 20, 10)
	rift.material_override = rm
	rift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rift)
	rift.global_position = pos
	InfernalFx.tween_param(rift, rm, "front", 0.0, 1.08, 0.16).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(rift, rm, "heat", 1.0, 0.0, 1.5, 0.35)
	InfernalFx.tween_param(rift, rm, "life", 1.0, 0.0, 1.6, 1.3)
	Fx._free_later(rift, 3.0)
	# the obsidian fangs
	_fangs(root, world, pos, yaw, reach, half, tr)
	# the crescent wave of fire (and the air bending over it)
	var wm := InfernalFx.wave_mat()
	var wave := MeshInstance3D.new()
	wave.mesh = InfernalFx.arc_mesh(half * 0.92)
	wave.material_override = wm
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wave)
	wave.global_position = pos + Vector3(0, 0.02, 0)
	wave.rotation.y = yaw
	wave.scale = Vector3(0.7, 0.5, 0.7)
	var hz: ShaderMaterial = null
	if InfernalFx.haze_ok(h.game):
		hz = InfernalFx.haze_mat(0.035)
		wm.next_pass = hz
	var tww := wave.create_tween().set_parallel(true)
	tww.tween_property(wave, "scale", Vector3(reach * 1.05, 0.95, reach * 1.05), 0.24).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	InfernalFx.tween_param(wave, wm, "life", 1.0, 0.0, 0.3, 0.04)
	if hz != null:
		InfernalFx.tween_param(wave, hz, "life", 1.0, 0.0, 0.42)
	Fx._free_later(wave, 0.5)
	# tongues of hellfire licking up along the fissures
	var tm := InfernalFx.flame_mat(0.7, 1.35, 1.7)
	for i in TONGUES[tr]:
		var lane: float = [-0.52, 0.0, 0.52][i % 3] + randf_range(-0.08, 0.08)
		var u := randf_range(0.18, 0.92)
		var ang := yaw - lane * half
		var p := pos + Vector3(-sin(ang), 0, -cos(ang)) * (0.25 + u * reach)
		p.y = world.height_at(p.x, p.z) - 0.05
		var sz := Vector2(randf_range(0.45, 0.75), randf_range(0.85, 1.5)) * (1.2 - 0.45 * u)
		var fm := InfernalFx.flame(root, p, Vector2(0.01, 0.01), tm)
		var twf := fm.create_tween()
		twf.tween_interval(0.02 + u * 0.15)
		twf.tween_property(fm, "scale", Vector3(sz.x, sz.y, 1.0), 0.08).set_ease(Tween.EASE_OUT)
		twf.tween_interval(randf_range(0.1, 0.3))
		twf.tween_property(fm, "scale", Vector3(sz.x * 0.5, 0.01, 1.0), 0.22).set_ease(Tween.EASE_IN)
		twf.tween_callback(fm.queue_free)
	# smoke rolling out low, lit from below
	var mid := pos + fwd * reach * 0.5 + Vector3(0, 0.35, 0)
	InfernalFx.smoke(root, mid, SMOKE_N[tr], Vector3(reach * 0.32, 0.15, reach * 0.32), (fwd + Vector3(0, 0.45, 0)).normalized(), 1.5, 1.8, 1.2, 0.75)
	# embers rising over the rift
	InfernalFx.particles(root, pos + fwd * reach * 0.5 + Vector3(0, 0.15, 0), {"amount": EMBERS[tr], "life": 1.4,
		"explosive": 0.7, "shape": "box", "box": Vector3(reach * 0.36, 0.1, reach * 0.36), "dir": Vector3.UP, "spread": 25.0,
		"vel": [1.0, 3.2], "gravity": 1.2, "damping": [0.5, 1.0], "scale": [0.4, 1.0], "size": 0.06,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.25, InfernalFx.MOLTEN], [0.7, InfernalFx.BLOODFIRE], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	# a spray of molten drops off the fists along the blow
	InfernalFx.particles(root, fist, {"amount": [14, 22, 30, 36][tr], "life": 0.45, "explosive": 0.95,
		"dir": (fwd + Vector3(0, -0.25, 0)).normalized(), "spread": 26.0, "vel": [5.0, 11.0], "gravity": -9.0,
		"damping": [2.0, 3.0], "scale": [0.5, 1.0], "size": 0.07,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.35, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	# earth thrown up out of the cracks
	Fx.burst(root, pos + fwd * reach * 0.45 + Vector3(0, 0.2, 0), Color(0.2, 0.16, 0.14, 0.75), [8, 12, 16, 18][tr], 3.2, 0.3, 0.7, false, -5.0, 55.0, fwd * 0.4 + Vector3.UP)
	# the foes struck
	for e in hit:
		_brand(h, root, e, pos, tr)
	# sound and the caster's screen
	SkillFx.snd(h, "slam", -1.0, 0.78)
	SkillFx.snd(h, "boom", -7.0, 0.88)
	SkillFx.snd(h, "fire_erupt", -5.0, 0.82)
	SkillFx.snd(h, "hellclaw", -8.0, 0.8)
	SkillFx.shake(h, 0.26 if not hit.is_empty() else 0.14)
	if not hit.is_empty():
		SkillFx.hitstop(h, 0.035)

## The fangs: obsidian shards bursting up through the wedge, near to far, leaning away from him; they hold, their
## veins crack white, and they shatter into burning fragments (Low: they sink back into the ground).
static func _fangs(root: Node3D, world, pos: Vector3, yaw: float, reach: float, half: float, tr: int) -> void:
	var n: int = SHARDS[tr]
	var mat := InfernalFx.shard_mat()
	var frag_mat := InfernalFx.shard_mat(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(int(pos.x * 4.0), int(pos.z * 4.0), int(yaw * 100.0)))
	var first := [true]
	for i in n:
		var u := (float(i) + rng.randf_range(0.15, 0.85)) / float(n)
		var rr := lerpf(0.85, reach * 0.95, u)
		var lane := rng.randf_range(-0.85, 0.85) * (0.5 + 0.5 * u)
		var ang := yaw - lane * half
		var dir := Vector3(-sin(ang), 0, -cos(ang))
		var p := pos + dir * rr
		p.y = world.height_at(p.x, p.z)
		var hgt := lerpf(0.7, 1.55, sin(clampf(u * 1.05, 0.0, 1.0) * PI * 0.85 + 0.25)) * rng.randf_range(0.8, 1.15)
		var w := rng.randf_range(0.85, 1.3)
		var mi := MeshInstance3D.new()
		mi.mesh = InfernalFx.shard_mesh(rng.randi() % 6)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tr >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var axis := dir.cross(Vector3.UP).normalized()
		mi.basis = Basis(axis, -rng.randf_range(0.25, 0.6)) * Basis(Vector3.UP, rng.randf() * TAU)
		mi.scale = Vector3(hgt * 0.85 * w, hgt, hgt * 0.85 * w)
		mi.global_position = p - Vector3(0, hgt * 0.95, 0)
		var delay := 0.01 + u * 0.13
		var brk := 0.5 + u * 0.14 + rng.randf_range(0.0, 0.06)
		var tw := mi.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(mi, "global_position", p, 0.075).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(maxf(brk - delay - 0.075, 0.05))
		var seed_i := rng.randi()
		tw.tween_callback(func(): _shatter(root, mi, p, dir, hgt, tr, frag_mat, seed_i, first))
	# the veins: hot as they burst out, cooling a little, cracking white before they break
	var holder := Node.new()
	root.add_child(holder)
	Fx._free_later(holder, 2.0)
	InfernalFx.tween_param(holder, mat, "heat", 1.8, 1.0, 0.35)
	InfernalFx.tween_param(holder, mat, "crack", 0.0, 1.0, 0.14, 0.42)
	InfernalFx.tween_param(holder, frag_mat, "heat", 1.6, 0.0, 1.4, 0.5)

static func _shatter(root: Node3D, mi: MeshInstance3D, p: Vector3, dir: Vector3, hgt: float, tr: int, frag_mat: ShaderMaterial, seed_i: int, first: Array) -> void:
	if not is_instance_valid(mi):
		return
	if bool(first[0]):
		first[0] = false
		Sfx.play_at("ice_shatter", p, -9.0, 0.55)
		Sfx.play_at("impact_bone", p, -13.0, 0.7)
	if FRAGS[tr] <= 0:
		# Low: back down into the ground
		var tw := mi.create_tween()
		tw.tween_property(mi, "global_position", p - Vector3(0, hgt * 1.1, 0), 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	for j in FRAGS[tr]:
		var fr := MeshInstance3D.new()
		fr.mesh = InfernalFx.shard_mesh(j + seed_i % 3)
		fr.material_override = frag_mat
		fr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fr)
		var s := hgt * rng.randf_range(0.16, 0.3)
		fr.scale = Vector3(s, s * rng.randf_range(0.8, 1.4), s)
		fr.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		fr.global_position = p + Vector3(rng.randf_range(-0.12, 0.12), hgt * rng.randf_range(0.1, 0.75), rng.randf_range(-0.12, 0.12))
		var side := dir.cross(Vector3.UP) * rng.randf_range(-1.6, 1.6)
		var v := dir * rng.randf_range(0.8, 3.2) + side + Vector3(0, rng.randf_range(2.0, 4.8), 0)
		var wv := Vector3(rng.randf_range(-11, 11), rng.randf_range(-8, 8), rng.randf_range(-11, 11))
		InfernalFx.fly(fr, v, wv, rng.randf_range(0.6, 0.95), -15.0)
	InfernalFx.particles(root, p + Vector3(0, hgt * 0.45, 0), {"amount": 8, "life": 0.4, "explosive": 1.0,
		"shape": "sphere", "r": 0.15, "dir": Vector3.UP, "spread": 70.0, "vel": [1.5, 4.0], "gravity": -8.0,
		"scale": [0.5, 1.0], "size": 0.06,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.4, InfernalFx.BLOODFIRE], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	mi.queue_free()

# ---------------------------------------------------------------- the foes struck
static func _brand(h: Hero, root: Node3D, e, from: Vector3, tr: int) -> void:
	if e == null or not is_instance_valid(e):
		return
	var chest := SkillFx.chest_of(e)
	var away: Vector3 = (e.global_position - from) * Vector3(1, 0, 1)
	away = away.normalized() if away.length() > 0.01 else h.facing()
	InfernalFx.particles(root, chest, {"amount": [8, 12, 16, 20][tr], "life": 0.42, "explosive": 1.0,
		"dir": (away + Vector3(0, 0.45, 0)).normalized(), "spread": 32.0, "vel": [3.0, 7.0], "gravity": -9.0,
		"damping": [1.0, 2.0], "scale": [0.5, 1.0], "size": 0.07,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.3, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	Fx.burst(root, chest, Color(0.05, 0.03, 0.035, 0.7), 6, 1.4, 0.4, 0.6, false, 0.6, 60.0, away + Vector3.UP)
	var gm := InfernalFx.glow_mat(InfernalFx.BLOODFIRE, 2.4, 1.6, 0.6)
	var g := InfernalFx.glow(root, chest, 0.6, gm)
	g.create_tween().tween_property(g, "scale", Vector3.ONE * 1.9, 0.18).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, gm, "alpha", 1.0, 0.0, 0.2)
	Fx._free_later(g, 0.24)
	# a lick of hellfire up the body
	if e is Node3D and not bool(e.get("dead")):
		var fm := InfernalFx.flame_mat(0.6, 1.3, 1.8)
		var height: float = float(e.get("height")) if e.get("height") != null else 1.0
		var f := InfernalFx.flame(e, (e as Node3D).global_position + Vector3(0, 0.1, 0), Vector2(0.01, 0.01), fm)
		var twf := f.create_tween()
		twf.tween_property(f, "scale", Vector3(0.75, height * 1.5, 1.0), 0.06)
		twf.tween_interval(0.12)
		twf.tween_method(func(v: float): fm.set_shader_parameter("alpha", v), 1.0, 0.0, 0.3)
		twf.tween_callback(f.queue_free)
	# the molten flash in place of the white one (it shows only while the hit's own flash is on)
	var fmat = e.get("flash_mat")
	if fmat != null and float(e.get("flash_t")) > 0.0:
		(fmat as StandardMaterial3D).albedo_color = Color(1.0, 0.3, 0.06, 0.85)
	# the stagger: its body thrown back and springing home (visual only)
	var ss: Array = h.fxs.get("fists_stag", [])
	for s in ss.duplicate():
		if s["e"] == e:
			_unstagger(s)
			ss.erase(s)
	var rig = e.get("rig")
	if rig != null and is_instance_valid(rig):
		ss.append({"e": e, "rig": rig, "t": 0.0, "away": away, "base": [rig.rotation.x, rig.rotation.z, rig.position.y]})
	h.fxs["fists_stag"] = ss

const STAG_T := 0.45
const STAG_TILT := 0.34

static func _staggers(h: Hero, delta: float) -> void:
	var ss: Array = h.fxs["fists_stag"]
	for s in ss.duplicate():
		s["t"] = float(s["t"]) + delta
		var e = s["e"]
		var rig = s["rig"]
		var done: bool = float(s["t"]) >= STAG_T or e == null or not is_instance_valid(e) or bool(e.dead) or rig == null or not is_instance_valid(rig)
		if done:
			_unstagger(s)
			ss.erase(s)
			continue
		var t: float = float(s["t"])
		var amt := (1.0 - exp(-t * 45.0)) * exp(-t * 7.5) * 1.4
		var away: Vector3 = s["away"]
		var la := away.rotated(Vector3.UP, -(rig as Node3D).global_rotation.y)
		var base: Array = s["base"]
		(rig as Node3D).rotation.x = float(base[0]) + STAG_TILT * amt * la.z
		(rig as Node3D).rotation.z = float(base[1]) - STAG_TILT * amt * la.x
		(rig as Node3D).position.y = float(base[2]) + 0.12 * amt
	if ss.is_empty():
		h.fxs.erase("fists_stag")

static func _unstagger(s: Dictionary) -> void:
	var e = s.get("e")
	var rig = s.get("rig")
	if rig == null or not is_instance_valid(rig) or e == null or not is_instance_valid(e) or bool(e.dead):
		return
	var base: Array = s["base"]
	(rig as Node3D).rotation.x = float(base[0])
	(rig as Node3D).rotation.z = float(base[1])
	(rig as Node3D).position.y = float(base[2])

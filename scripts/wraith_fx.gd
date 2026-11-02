class_name WraithFx
extends RefCounted
## Visual effects for the Wraith's skills (WraithSkills). Everything one-shot is parented to the zone's FX node;
## what rides the body (the spectral claws) hangs on the rig's hand followers. The colours: his cold cyan spirit-
## light (SPIRIT), the pale core of a torn soul (PALE), and the violet of the dark he moves through (VIOLET, NIGHT).
##
## `play` is the skills' fx events (SkillFx: the same on his own game and on his puppet on every partner's), `update`
## what lingers (h.fxs: the tether following its victim, the night's stages riding the attack's progress, the
## phantoms in flight, the claws growing with the rakes), `clear` takes it all away:
##  Spectral Rend: "rake" {y: yaw, l: the left claw, x: all round, n: souls}, "souls" {ps: where they were torn out}
##  Soul Siphon: "latch" {t: [the victim], x: the hold} (the tether, h.fxs["tether"], drawn from his hand each frame
##    until "end" {x: its hold ran out}, or after x + 2 s on a partner's game if that is lost), "tick", "soul" {p}
##  Shadowstep: "blink" {p: from, q: to} (the afterimage, the mist out and in, the shade's collapse SHADE_DELAY
##    later), "strike" {y}
##  Haunting Grasp: "impact" {p: the ground, x: the hold}
##  Phantom Assault: "split" {d: ahead, n: how many} (the phantoms, h.fxs["phantoms"], flown by update), "hit" {p, d},
##    "strike" {y}
##  Eternal Night: "cast" (the night node, h.fxs["night"]: the dark floor, the souls, his rise and glow, and for the
##    caster the screen's edges darkening; a partner sees a fainter darkening when he stands near it), "rise",
##    "scream" (the four wheeling ghosts), "tick", "fall", "end" {x: finished}

const SPIRIT := Color(0.35, 0.85, 1.0)
const VIOLET := Color(0.62, 0.38, 1.0)
const PALE := Color(0.85, 0.95, 1.0)
const NIGHT := Color(0.18, 0.08, 0.32)

static var _crescent: ArrayMesh
static var _mark: ArrayMesh
static var _disc: ArrayMesh
static var _claw: ArrayMesh
static var _floor_shader: Shader
static var _ribbon_mat: StandardMaterial3D

const SHADE_DELAY := 0.45          # Shadowstep: the shade left behind collapses this long after the blink
const SIPHON_SLACK := 2.0          # a partner's tether outlives its hold by this much at most if the "end" is lost
const NIGHT_PARTNER := 0.45        # how much of the night's darkening a partner standing in it gets

## How long the i-th soul wisp takes to reach him (the heal waits the same, in WraithSkills).
static func wisp_time(i: int) -> float:
	return 0.45 + 0.25 * fposmod(float(i) * 0.618, 1.0)

# ---------------------------------------------------------------- the skills' events (SkillFx)
static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var pos := h.global_position
	match [str(ev["s"]), str(ev["e"])]:
		["rend", "cast"], ["siphon", "cast"], ["step", "cast"], ["grasp", "cast"], ["phantom", "cast"]:
			pass
		["rend", "rake"]:
			var yaw: float = float(ev["y"])
			var left: bool = bool(ev.get("l", false))
			rake(root, pos, yaw, 3.0, left)
			if bool(ev.get("x", false)):
				rake(root, pos, yaw + PI, 3.0, not left)
			if left:
				SkillFx.snd(h, "swing_light", -4.0, 0.9)
			SkillFx.shake(h, 0.14 if int(ev.get("n", 0)) > 0 else 0.05)
		["rend", "souls"]:
			var ps: PackedVector3Array = ev["ps"]
			for i in ps.size():
				Fx.sparks(root, ps[i], PALE)
				soul_wisp(root, ps[i], h, wisp_time(i))
		["siphon", "latch"]:
			_end_tether(h, false)
			var vs: Array = ev.get("t", [])
			if vs.is_empty():
				return true
			var v = vs[0]
			latch(root, SkillFx.chest_of(v))
			h.fxs["tether"] = {"victim": v, "node": tether(root), "hum": Sfx.start_loop("drain_loop", -16.0, 0.72),
				"until": float(ev.get("x", 2.5)) + SIPHON_SLACK}
			v.set_drained(true, SPIRIT)
			SkillFx.snd(h, "spirit_dart", -4.0, 0.8)
			SkillFx.shake(h, 0.08)
		["siphon", "tick"]:
			if h.fxs.has("tether"):
				var v = h.fxs["tether"]["victim"]
				if is_instance_valid(v) and not v.dead:
					v.drain_flash(SPIRIT)
				h.fxs["tether"]["until"] = maxf(float(h.fxs["tether"]["until"]), SIPHON_SLACK)
			if h.puppet:
				Sfx.play_at("drain_tick", pos, -16.0, 1.3)
			else:
				Sfx.play("drain_tick", -12.0, 1.3)
		["siphon", "soul"]:
			var p: Vector3 = ev["p"]
			pulse(root, p, PALE, 1.6, 0.35)
			soul_wisp(root, p, h, wisp_time(0))
		["siphon", "end"]:
			_end_tether(h, bool(ev.get("x", false)))
		["step", "blink"]:
			var from: Vector3 = ev["p"]
			var to: Vector3 = ev["q"]
			afterimage(h.rig, root, VIOLET, 0.55, 0.3)
			mist_out(root, from)
			Sfx.play_at("shade_out", from, -2.0)
			# a trail of fainter shades along the way
			var dist := from.distance_to(to)
			var steps := clampi(int(dist / 1.6), 1, 5)
			for i in range(1, steps):
				var p := from.lerp(to, float(i) / steps)
				_spirit_burst(root, p + Vector3(0, 1.0, 0), Color(0.3, 0.26, 0.42, 0.55), 8, 1.2, 0.35, 0.5, false, 0.8)
			mist_in(root, to)
			SkillFx.snd(h, "shade_in", -2.0)
			SkillFx.shake(h, 0.15)
			# the shade left behind caves in a moment later
			Fx.later(root, SHADE_DELAY, func():
				shade_collapse(root, from)
				Sfx.play_at("shade_implode", from, -1.0))
		["step", "strike"]:
			var yaw: float = float(ev["y"])
			rake(root, pos, yaw, 2.6, true)
			rake(root, pos, yaw + PI, 2.6, false)
			SkillFx.snd(h, "reap_swing", -3.0, 1.1)
			SkillFx.shake(h, 0.22 if bool(ev.get("x", false)) else 0.1)
		["grasp", "impact"]:
			var at: Vector3 = ev["p"]
			grasp(root, at, WraithSkills.GRASP_R, float(ev.get("x", 2.5)))
			Sfx.play_at("slam", at, -4.0, 0.85)
			Sfx.play_at("shackles", at, -8.0, 1.15)
			SkillFx.shake(h, 0.3)
		["phantom", "split"]:
			var fwd: Vector3 = ev["d"]
			var count: int = int(ev.get("n", 3))
			var spread := deg_to_rad(22.0)
			var ps: Array = h.fxs.get("phantoms", [])
			for i in count:
				var ang := (float(i) - (count - 1) * 0.5) * spread
				var dir := fwd.rotated(Vector3.UP, ang)
				var g := afterimage(h.rig, root, VIOLET.lerp(SPIRIT, 0.3), WraithSkills.PHANTOM_RANGE / WraithSkills.PHANTOM_SPEED + 0.25, 0.2)
				if g == null:
					continue
				g.rotation.y = atan2(-dir.x, -dir.z)
				g.rotation.x = 0.0
				var tr := _trail(VIOLET, 0.16, 30, 0.45)
				tr.position = Vector3(0, 1.0, 0)
				g.add_child(tr)
				ps.append({"node": g, "dir": dir, "left": WraithSkills.PHANTOM_RANGE, "hit": {}, "lean": 0.0})
			h.fxs["phantoms"] = ps
			split(root, pos)
			SkillFx.snd(h, "host_summon", -5.0, 1.15)
			SkillFx.shake(h, 0.18)
		["phantom", "hit"]:
			var p: Vector3 = ev["p"]
			phantom_hit(root, p, ev["d"])
			Sfx.play_at("spirit_dart", p, -5.0)
		["phantom", "strike"]:
			rake(root, pos, float(ev["y"]), 2.8, true)
			SkillFx.shake(h, 0.15)
		["night", "cast"]:
			_end_night(h, false)
			var grade: ShaderMaterial = null
			if not h.puppet and h.game.get("vignette") != null:
				grade = h.game.vignette.material
			h.fxs["night"] = {"node": night(root, pos, WraithSkills.NIGHT_R * 0.8, grade), "ghosts": [], "k": 0.0, "vig": 0.0}
			_set_hover(h, WraithSkills.NIGHT_HOVER)
			SkillFx.snd(h, "host_summon", -4.0, 0.8)
			SkillFx.duck(h, -6.0, 1.5)
		["night", "rise"]:
			Fx.flash(root, pos + Vector3(0, 2.0, 0), VIOLET, 3.0, 0.6, 9.0)
		["night", "scream"]:
			scream(root, pos, WraithSkills.NIGHT_R)
			SkillFx.snd(h, "wail", 0.0, 0.9)
			SkillFx.duck(h, -8.0, 1.0)
			SkillFx.shake(h, 0.5)
			SkillFx.hitstop(h, 0.06)
			if h.fxs.has("night"):
				# four phantoms wheel round him for the rest of the night
				for i in 4:
					var g := afterimage(h.rig, root, VIOLET, 20.0, 0.25)
					if g != null:
						g.set_meta("phase", TAU * i / 4.0)
						(h.fxs["night"]["ghosts"] as Array).append(g)
		["night", "tick"]:
			_spirit_burst(root, pos + Vector3(0, 1.2, 0), VIOLET, 10, 6.0, 0.1, 0.4, true, 0.0, 180.0)
		["night", "fall"]:
			collapse(root, pos, 6.5)
			SkillFx.snd(h, "slam", -2.0, 0.8)
			SkillFx.snd(h, "phase_erupt", -4.0, 0.9)
			SkillFx.duck(h, -8.0, 1.0)
			SkillFx.shake(h, 0.6)
			SkillFx.hitstop(h, 0.08)
		["night", "end"]:
			_end_night(h, bool(ev.get("x", false)))
		_:
			return false
	return true

static func _set_hover(h: Hero, extra: float) -> void:
	if h.rig != null and h._floats():
		h.rig.set("hover", Wraith.HOVER + extra)

static func _set_glow(h: Hero, g: float) -> void:
	if h.rig != null and h.rig.has_meta("spectral_mats"):
		for m in h.rig.get_meta("spectral_mats"):
			(m as ShaderMaterial).set_shader_parameter("glow", g)
	if h.rig != null and h.rig.has_meta("eye_light"):
		var l := h.rig.get_meta("eye_light") as OmniLight3D
		if l != null:
			l.light_energy = 0.45 * g

## The tether lets go: it thins and is gone, the victim's rim and the hum with it (a violet pulse if its hold ran out).
static func _end_tether(h: Hero, spent: bool) -> void:
	if not h.fxs.has("tether"):
		return
	var t: Dictionary = h.fxs["tether"]
	h.fxs.erase("tether")
	var v = t["victim"]
	if v != null and is_instance_valid(v):
		v.set_drained(false)
		if spent and not v.dead and h.game.world != null:
			pulse(h.game.world.fx_root, SkillFx.chest_of(v), VIOLET, 1.2, 0.3)
	var n = t["node"]
	if n != null and is_instance_valid(n):
		var tw: Tween = n.create_tween()
		tw.tween_property(n, "fade", 0.0, 0.25)
		tw.tween_callback(n.queue_free)
	var hum = t["hum"]
	if hum != null and is_instance_valid(hum):
		hum.stop()
		hum.queue_free()

## The night lifts: the dark fades up, the ghosts go, he comes down and dims.
static func _end_night(h: Hero, finished: bool) -> void:
	if not h.fxs.has("night"):
		return
	var n: Dictionary = h.fxs["night"]
	h.fxs.erase("night")
	_set_hover(h, 0.0)
	var node = n["node"]
	if node != null and is_instance_valid(node):
		var tw: Tween = node.create_tween()
		tw.tween_method(func(v: float): set_night(node, v), 1.0 if finished else 0.6, 0.0, 0.5 if finished else 0.3)
		tw.tween_callback(node.queue_free)
	_partner_night(h, 0.0)
	for g in n["ghosts"]:
		if is_instance_valid(g):
			(g as Node).queue_free()
	_set_glow(h, 1.0)

## A partner's night darkens this screen's edges a little when our own hero stands in it (never over our own).
static func _partner_night(h: Hero, want: float) -> void:
	if not h.puppet or h.game.get("vignette") == null:
		return
	var mine: Hero = h.game.hero
	if mine != null and mine.fxs.has("night"):
		return
	(h.game.vignette.material as ShaderMaterial).set_shader_parameter("night", want)

## Every frame after the pose (the caster's and the puppet's): the claws, the tether, the phantoms, the night.
static func update(h: Hero, delta: float) -> void:
	if not h.is_wraith():
		return
	var a := SkillFx.atk(h)
	var st := SkillFx.style(h)
	# the claws: out for the rakes, grown as the arm draws back, gone soon after the last strike
	var want := 0.0
	if a >= 0.0 and st == "rend":
		want = Anim.kf(a, [[0.0, 0.0], [0.3, 1.0], [0.85, 1.0], [1.0, 0.0]])
	elif a >= 0.0 and st == "phantom":
		want = Anim.kf(a, [[0.0, 0.0], [0.25, 1.0], [0.8, 1.0], [1.0, 0.0]])
	elif a >= 0.0 and st == "wstep":
		want = Anim.kf(a, [[0.35, 0.0], [0.6, 1.0], [0.9, 1.0], [1.0, 0.0]])
	var ck: float = float(h.fxs.get("claw_k", 0.0))
	ck = lerpf(ck, want, clampf(delta * 18.0, 0.0, 1.0)) if want < ck else want
	h.fxs["claw_k"] = ck
	if h.rig != null and h._floats() and (ck > 0.001 or bool(h.fxs.get("claw_shown", false))):
		set_claws(h.rig, ck)
		h.fxs["claw_shown"] = ck > 0.001
	# the tether, from the hand to the victim's chest
	if h.fxs.has("tether"):
		var t: Dictionary = h.fxs["tether"]
		var v = t["victim"]
		var n = t["node"]
		t["until"] = float(t["until"]) - delta
		if v == null or not is_instance_valid(v) or n == null or not is_instance_valid(n) or (h.puppet and float(t["until"]) <= 0.0):
			_end_tether(h, false)
		else:
			(n as Tether).draw(SkillFx.hand(h, true), SkillFx.chest_of(v), h.anim_time)
	# the phantoms streak on until their range or a wall, and come apart there
	if h.fxs.has("phantoms"):
		var ps: Array = h.fxs["phantoms"]
		var world = h.game.world
		for p in ps.duplicate():
			var g = p["node"]
			if not is_instance_valid(g):
				ps.erase(p)
				continue
			var step := WraithSkills.PHANTOM_SPEED * delta
			var pos: Vector3 = g.global_position
			var np: Vector3 = world.move(pos, (p["dir"] as Vector3) * step, 0.3)
			var moved := np - pos
			moved.y = 0
			np.y = world.height_at(np.x, np.z)
			g.global_position = np
			p["lean"] = lerpf(float(p["lean"]), 0.45, clampf(delta * 8.0, 0.0, 1.0))
			g.rotation.x = -float(p["lean"])
			p["left"] -= step
			if p["left"] <= 0.0 or moved.length() < step * 0.3:
				ps.erase(p)
				for m in g.get_meta("mats", []):
					(m as ShaderMaterial).set_shader_parameter("phase_amt", 1.0)
				_spirit_burst(world.fx_root, np + Vector3(0, 1.0, 0), VIOLET, 12, 2.5, 0.1, 0.4, true, 0.0)
		if ps.is_empty():
			h.fxs.erase("phantoms")
	# the night: the dark comes down through the rise, he glows, the ghosts wheel, he sinks through the fall
	if h.fxs.has("night"):
		var n: Dictionary = h.fxs["night"]
		var node = n["node"]
		if node == null or not is_instance_valid(node):
			_end_night(h, false)
			return
		var k: float = float(n["k"])
		if st == "night_rise" and a >= 0.0:
			k = smoothstep(0.0, 0.85, a)
			_set_glow(h, 1.0 + a * 2.5)
		elif st in WraithSkills.NIGHT_STAGES:
			k = 1.0
		elif h.puppet and a < 0.0:
			# a puppet between stages keeps its night; one whose night ended without the word loses it after a while
			n["idle"] = float(n.get("idle", 0.0)) + delta
			if float(n["idle"]) > 1.0:
				_end_night(h, false)
				return
		if st in WraithSkills.NIGHT_STAGES:
			n["idle"] = 0.0
		n["k"] = k
		set_night(node, k)
		if st == "night_fall" and a > 0.2:
			_set_hover(h, WraithSkills.NIGHT_HOVER * (1.0 - smoothstep(0.2, 0.5, a)))
		var c := h.global_position
		for g in n["ghosts"]:
			if not is_instance_valid(g):
				continue
			var ph: float = float(g.get_meta("phase")) + h.anim_time * 2.2
			var r := 3.2
			(g as Node3D).global_position = c + Vector3(cos(ph) * r, 0.25 + sin(ph * 2.0) * 0.3, sin(ph) * r)
			(g as Node3D).rotation = Vector3(-0.35, -ph + PI * 0.5, 0.0)
		if h.puppet:
			# a partner's night: our own screen darkens a little while we stand in it
			var mine: Hero = h.game.hero
			var d: float = mine.global_position.distance_to(c) if mine != null else 99.0
			_partner_night(h, k * NIGHT_PARTNER * (1.0 - smoothstep(WraithSkills.NIGHT_R, WraithSkills.NIGHT_R * 2.0, d)))

## Everything of his that lingers is gone (death, a class change, a zone change).
static func clear(h: Hero) -> void:
	_end_tether(h, false)
	_end_night(h, false)
	if h.fxs.has("phantoms"):
		for p in h.fxs["phantoms"]:
			if is_instance_valid(p["node"]):
				(p["node"] as Node).queue_free()
		h.fxs.erase("phantoms")
	if h.rig != null and h.rig.has_meta("claws"):
		set_claws(h.rig, 0.0)
	h.fxs.erase("claw_k")
	h.fxs.erase("claw_shown")

## The Wraith's own particles and rings (visual overhaul): his spirit-light was the generic soft-dot burst and his
## shock rings the generic glowing torus, the same as every class's. Now spirit light streaks out as curling wisps
## (quads stretched along their flight, fading cyan to violet), shadow rolls as soft smoke (InfernalFx's smoke, unlit by
## fire), and a ring is a ripple of soul-mist racing over the ground. Same arguments as Fx.burst / Fx.ring.
static var _wisp_mat: StandardMaterial3D
static var _ring_shader: Shader

static func _wisp_material() -> StandardMaterial3D:
	if _wisp_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		_wisp_mat = StandardMaterial3D.new()
		_wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wisp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_wisp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		_wisp_mat.billboard_keep_scale = true
		_wisp_mat.vertex_color_use_as_albedo = true
		_wisp_mat.albedo_color = Color(2.2, 2.2, 2.2)
		_wisp_mat.albedo_texture = gt
		_wisp_mat.disable_receive_shadows = true
	return _wisp_mat

static func _spirit_burst(root: Node3D, pos: Vector3, col: Color, amount: int = 16, speed: float = 3.0, size: float = 0.12, life: float = 0.5, additive := true, gravity: float = -6.0, spread: float = 180.0, dir := Vector3.UP) -> GPUParticles3D:
	if not additive:
		# shadow: soft rolling smoke in the burst's colour
		var sm := InfernalFx.smoke_mat(0.0, clampf(col.a, 0.2, 1.0))
		sm.set_shader_parameter("smoke", Vector3(col.r, col.g, col.b))
		var q := QuadMesh.new()
		q.size = Vector2(size * 2.2, size * 2.2)
		q.material = sm
		return InfernalFx.particles(root, pos, {"amount": maxi(3, amount / 3), "life": life * 1.4, "explosive": 0.9,
			"shape": "sphere", "r": size, "dir": dir, "spread": spread, "vel": [speed * 0.25, speed * 0.6], "gravity": gravity * 0.3,
			"damping": [1.0, 1.8], "scale": [0.7, 1.2], "grow": [0.6, 1.5], "angle": true, "spin": 25.0, "mesh": q,
			"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.15, Color(1, 1, 1, 0.9)], [0.6, Color(1, 1, 1, 0.5)], [1.0, Color(1, 1, 1, 0.0)]]})
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = life * 1.2
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity * 0.5 + 0.6, 0)
	pm.damping_min = speed * 0.6
	pm.damping_max = speed * 1.1
	pm.particle_flag_align_y = true
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.22
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.6))
	c.add_point(Vector2(0.2, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(PALE.r, PALE.g, PALE.b, 0.0))
	g.add_point(0.08, Color(PALE.r, PALE.g, PALE.b, 1.0))
	g.add_point(0.35, Color(col.r, col.g, col.b, 0.9))
	g.set_color(1, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q2 := QuadMesh.new()
	q2.size = Vector2(size * 0.7, size * 3.2)
	q2.material = _wisp_material()
	p.draw_pass_1 = q2
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_later(p, p.lifetime + 0.5)
	return p

## A ripple of soul-mist racing out over the ground from pos to `radius` in `dur` (the ring every Wraith skill used),
## with the grass shoved and a flash of its light, as Fx.ring had.
static func _soul_ring(root: Node3D, pos: Vector3, radius: float, col: Color, dur: float = 0.5, height: float = 0.25) -> void:
	GrassField.impulse(pos, radius, clampf(0.35 + radius * 0.06, 0.35, 0.75), clampf(dur * 0.8, 0.25, 0.55))
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = SOUL_RING_SHADER
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	m.set_shader_parameter("noise_tex", InfernalFx.noise())
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("pale", PALE)
	m.set_shader_parameter("seed", randf() * 10.0)
	var mi := MeshInstance3D.new()
	mi.mesh = HolyFx.flat()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, minf(height, 0.12), 0)
	mi.scale = Vector3(radius * 2.3, 1.0, radius * 2.3)
	InfernalFx.tween_param(mi, m, "front", 0.12, 0.92, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	InfernalFx.tween_param(mi, m, "life", 1.0, 0.0, dur).set_ease(Tween.EASE_IN)
	_free_later(mi, dur + 0.05)
	Fx.flash(root, pos + Vector3(0, 1, 0), col, 3.0, dur, radius * 1.5)

## The soul-mist ring on a flat quad (UV 0.5 at the centre): a band at `front` eroded into wisps by noise, pale at its
## leading edge and fading to the skill's colour behind it.
const SOUL_RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 col : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform vec4 pale : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float front = 0.1;
uniform float life = 1.0;
uniform float seed = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float a = atan(d.y, d.x);
	float n = texture(noise_tex, vec2(a * 0.6 + seed, r * 1.5 - TIME * 0.4)).r;
	float n2 = texture(noise_tex, vec2(a * 2.1 - seed, r * 3.0)).r;
	float x = (r - front) / 0.16;
	float band = exp(-x * x * 2.0) * smoothstep(0.25, 0.7, n + 0.25);
	float trail = smoothstep(front, front - 0.35, r) * smoothstep(front - 0.5, front - 0.2, r) * 0.35 * smoothstep(0.4, 0.8, n2);
	float lead = exp(-pow((r - front - 0.03) / 0.04, 2.0));
	vec3 c = mix(col.rgb, pale.rgb, clamp(lead * 1.2, 0.0, 1.0)) * 2.4;
	ALBEDO = c;
	ALPHA = clamp((band + trail + lead * 0.5) * life * smoothstep(1.0, 0.92, r), 0.0, 1.0);
}
"""

static func _free_later(n: Node, t: float) -> void:
	var w: WeakRef = weakref(n)
	n.get_tree().create_timer(t, false).timeout.connect(func():
		var m: Node = w.get_ref() as Node
		if m != null and is_instance_valid(m):
			m.queue_free())

## A flat crescent blade lying in the XZ plane and opening forward (-Z); UV.y 0 at its cutting edge.
static func _crescent_mesh() -> ArrayMesh:
	if _crescent != null:
		return _crescent
	_crescent = _crescent_make(0.32, 85.0)
	return _crescent

## A thin claw-mark crescent (a narrower band over a shorter arc).
static func _mark_mesh() -> ArrayMesh:
	if _mark != null:
		return _mark
	_mark = _crescent_make(0.1, 55.0)
	return _mark

static func _crescent_make(thick: float, half_deg: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	var a0 := deg_to_rad(-half_deg)
	var a1 := deg_to_rad(half_deg)
	for i in seg:
		var t0 := float(i) / seg
		var t1 := float(i + 1) / seg
		var pts := []
		for t in [t0, t1]:
			var a: float = lerpf(a0, a1, t)
			var taper: float = sin(t * PI)
			var inner: float = 1.0 - thick * taper
			var d := Vector3(sin(a), 0, -cos(a))
			pts.append([d * inner, d, t])
		for q in [[pts[0][0], 0.0, pts[0][2]], [pts[0][1], 1.0, pts[0][2]], [pts[1][1], 1.0, pts[1][2]],
				[pts[0][0], 0.0, pts[0][2]], [pts[1][1], 1.0, pts[1][2]], [pts[1][0], 0.0, pts[1][2]]]:
			st.set_uv(Vector2(q[2], 1.0 - q[1]))
			st.set_normal(Vector3.UP)
			st.add_vertex(q[0])
	return st.commit()

## A unit disc in the XZ plane with UV = position (0.5 at the centre), for ground decals.
static func _disc_mesh() -> ArrayMesh:
	if _disc != null:
		return _disc
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for p in [Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))]:
			st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 + p.z * 0.5))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	_disc = st.commit()
	return _disc

## A curved spectral claw: a tapering blade bent along its length, pointing down -Y from the fingertip.
static func _claw_mesh() -> ArrayMesh:
	if _claw != null:
		return _claw
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var prev: Array = []
	for i in n + 1:
		var t := float(i) / n
		var r := 0.011 * (1.0 - t * 0.92)
		var p := Vector3(0.0, -t, -0.3 * t * t)     # bends forward as it goes down
		var ring := []
		for k in 5:
			var a := TAU * k / 5.0
			ring.append(p + Vector3(cos(a) * r, 0.0, sin(a) * r * 0.6))
		if not prev.is_empty():
			for k in 5:
				var k2 := (k + 1) % 5
				for v in [prev[k], ring[k], ring[k2], prev[k], ring[k2], prev[k2]]:
					st.set_uv(Vector2(0.0, t))
					st.add_vertex(v)
		prev = ring
	st.generate_normals()
	_claw = st.commit()
	return _claw

static func _ribbon_mat_get() -> StandardMaterial3D:
	if _ribbon_mat == null:
		_ribbon_mat = StandardMaterial3D.new()
		_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ribbon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ribbon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ribbon_mat.vertex_color_use_as_albedo = true
		_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ribbon_mat.albedo_color = Color(1.2, 1.2, 1.2)
	return _ribbon_mat

# ---------------------------------------------------------------- the spectral claws (Spectral Rend, Phantom Assault)
## Four claws of spirit-light on each hand, on the skeleton's hand bones (BoneAttachment3D: the bone's own Y runs
## down the fingers), grown out by set_claws. The armature is in centimetres (scale 0.01), hence the x100.
static func claws(rig: Node3D) -> Array:
	if rig.has_meta("claws"):
		return rig.get_meta("claws")
	var out := []
	var skels := rig.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		rig.set_meta("claws", out)
		return out
	var skel: Skeleton3D = skels[0]
	for bone in ["RightHand", "LeftHand"]:
		var bi := skel.find_bone(bone)
		if bi < 0:
			continue
		var at := BoneAttachment3D.new()
		at.bone_name = bone
		skel.add_child(at)
		var side := 1.0 if bone == "RightHand" else -1.0
		# the way the fingers point, in the hand bone's own frame: on along the forearm
		var hg := skel.get_bone_global_rest(bi)
		var fg := skel.get_bone_global_rest(skel.get_bone_parent(bi))
		var fingers: Vector3 = (hg.basis.inverse() * (hg.origin - fg.origin)).normalized()
		var hand_up: Vector3 = (hg.basis.inverse() * Vector3.UP).normalized()      # the back of the hand (A-pose, palms down)
		var across := fingers.cross(hand_up).normalized()
		var base := Basis(-across, -fingers, -across.cross(-fingers)).orthonormalized()  # the claw mesh hangs down -y, curling to the palm
		for i in 4:
			var c := MeshInstance3D.new()
			c.mesh = _claw_mesh()
			c.material_override = Mats.glow_unique(PALE.lerp(SPIRIT, 0.6), 2.2, 0.0, 0.0)
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var fan := Basis(fingers, deg_to_rad((i - 1.5) * 9.0 * side)) * Basis(across, deg_to_rad(-12.0))
			c.transform = Transform3D((fan * base).scaled(Vector3(100.0, 0.1, 100.0)), fingers * 9.0 + across * (i - 1.5) * 2.0 * side)
			c.set_meta("base", fan * base)
			c.visible = false
			at.add_child(c)
			out.append(c)
	rig.set_meta("claws", out)
	return out

## k 0..1: how far the claws are out (0.38 m at full), their light with them.
static func set_claws(rig: Node3D, k: float) -> void:
	for c in claws(rig):
		var m := c as MeshInstance3D
		if not is_instance_valid(m):
			continue
		m.visible = k > 0.01
		m.basis = (m.get_meta("base") as Basis).scaled(Vector3(100.0 + k * 30.0, maxf(0.1, 24.0 * k), 100.0 + k * 30.0))
		(m.material_override as ShaderMaterial).set_shader_parameter("alpha_mul", clampf(k * 1.4, 0.0, 1.0))

## The rake: three thin spectral crescents tearing across in front, a flash and a spray of torn light.
static func rake(root: Node3D, pos: Vector3, yaw: float, radius: float, left: bool) -> void:
	var dir := Vector3(-sin(yaw), 0, -cos(yaw))
	for layer in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = _mark_mesh()
		var col: Color = [PALE, SPIRIT, SPIRIT.lerp(VIOLET, 0.5)][layer]
		var m := Mats.glow_unique(col, [2.0, 1.5, 1.1][layer], 1.2)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var r: float = radius * [0.9, 1.0, 0.8][layer]
		mi.global_position = pos + Vector3(0, 1.05 + (layer - 1) * 0.2, 0)
		var s := 1.0 if left else -1.0
		mi.scale = Vector3(r * 0.5, 1.0, r * 0.5)
		mi.rotation = Vector3(-0.3 * s * (0.6 + layer * 0.2), yaw + 0.7 * s, 0.3 * s)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		var d := 0.16 + layer * 0.03
		tw.tween_property(mi, "rotation:y", yaw - 0.7 * s, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3(r, 1.0, r), d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.3).set_delay(0.06)
		_free_later(mi, 0.45)
	_spirit_burst(root, pos + Vector3(0, 1.1, 0) + dir * radius * 0.6, SPIRIT, 18, 4.5, 0.08, 0.4, true, 0.5, 60.0, dir + Vector3(0, 0.3, 0))
	Fx.flash(root, pos + Vector3(0, 1.2, 0) + dir * 0.8, SPIRIT, 1.6, 0.2, 5.0)

## A soul torn out of a foe: a pale flame that curves back to the Wraith over dur s (the heal lands then, WraithSkills).
static func soul_wisp(root: Node3D, from: Vector3, hero: Node3D, dur: float) -> void:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = from
	var core := MeshInstance3D.new()
	core.mesh = Geo.sph(0.07, 10)
	core.material_override = Mats.glow(PALE, 5.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	var tr := _trail(SPIRIT, 0.11, 24, 0.45)
	n.add_child(tr)
	var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.0, 2.0) + Vector3(0, randf_range(1.0, 2.2), 0)
	var tw := n.create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(hero):
			return
		var to: Vector3 = hero.global_position + Vector3(0, 1.3, 0)
		var mid := from.lerp(to, 0.5) + side
		var a := from.lerp(mid, t)
		var b := mid.lerp(to, t)
		n.global_position = a.lerp(b, t), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		core.visible = false
		tr.emitting = false
		_spirit_burst(root, n.global_position, SPIRIT, 10, 1.5, 0.08, 0.35, true, 0.0))
	_free_later(n, dur + 0.8)

# ---------------------------------------------------------------- Soul Siphon: the tether
## The tether from the Wraith's hand into a victim: two strands of spirit-light twisted round a dark core, pulled
## taut, with the stolen soul-stuff flowing back along it as pale motes, and the soul being torn loose at the far
## end (a writhing pale knot). Redrawn each frame (an ImmediateMesh ribbon facing the camera).
class Tether extends MeshInstance3D:
	var born := -1.0
	var jitter := 0.0
	var _from := Vector3.ZERO
	var _span := Vector3.ZERO
	var _len := 1.0
	var _side := Vector3.RIGHT
	var _up := Vector3.UP
	var _vup := Vector3.UP
	var _t := 0.0
	var fade := 1.0      # 1 holding, eased to 0 as it lets go

	func _init() -> void:
		jitter = randf() * 10.0
		mesh = ImmediateMesh.new()
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		top_level = true
		material_override = WraithFx._ribbon_mat_get()

	func _at(u: float, wob: float, rate: float, ph: float) -> Vector3:
		var env := sin(u * PI)
		var a := u * rate * TAU * _len / 5.0 + _t * 6.0 + ph + jitter
		var sag := Vector3.DOWN * 0.18 * env * _len * 0.12
		return _from + _span * u + (_side * sin(a) + _up * cos(a * 1.3) * 0.7) * wob * env + sag

	func _blob(im: ImmediateMesh, p: Vector3, r: float, c0: Color, c1: Color, seg := 10, star := 0.0) -> void:
		for i in seg:
			var a0 := TAU * i / seg + _t * 2.0
			var a1 := TAU * (i + 1) / seg + _t * 2.0
			var r0 := r * (1.0 + star * sin(a0 * 3.0 + _t * 11.0))
			var r1 := r * (1.0 + star * sin(a1 * 3.0 + _t * 11.0))
			im.surface_set_color(c0)
			im.surface_add_vertex(p)
			im.surface_set_color(c1)
			im.surface_add_vertex(p + (_side * cos(a0) + _vup * sin(a0)) * r0)
			im.surface_add_vertex(p + (_side * cos(a1) + _vup * sin(a1)) * r1)

	func _strip(im: ImmediateMesh, pts: Array, ws: Array, cols: Array, across: Vector3) -> void:
		for i in range(1, pts.size()):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			var wa: float = ws[i - 1]
			var wb: float = ws[i]
			var ca: Color = cols[i - 1]
			var cb: Color = cols[i]
			var la := a - across * wa * 0.5
			var ra := a + across * wa * 0.5
			var lb := b - across * wb * 0.5
			var rb := b + across * wb * 0.5
			for v in [[la, ca], [ra, ca], [rb, cb], [la, ca], [rb, cb], [lb, cb]]:
				im.surface_set_color(v[1])
				im.surface_add_vertex(v[0])

	## from: the Wraith's hand; to: the victim's chest.
	func draw(from: Vector3, to: Vector3, t: float) -> void:
		global_transform = Transform3D.IDENTITY
		var im: ImmediateMesh = mesh
		im.clear_surfaces()
		if born < 0.0:
			born = t
		var grow := 1.0 - pow(1.0 - clampf((t - born) / 0.14, 0.0, 1.0), 3.0)
		to = from.lerp(to, grow)
		_t = t
		_from = from
		_span = to - from
		_len = _span.length()
		if _len < 0.05 or fade <= 0.01:
			return
		var dir := _span / _len
		var cam := get_viewport().get_camera_3d()
		var view := Vector3.UP
		if cam != null:
			view = (cam.global_position - (from + to) * 0.5).normalized()
		_side = dir.cross(view)
		if _side.length() < 0.01:
			_side = dir.cross(Vector3.RIGHT)
		_side = _side.normalized()
		_up = _side.cross(dir).normalized()
		_vup = view.cross(_side).normalized()
		var n := clampi(int(_len * 6.0), 12, 64)
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var strands := [
			[0.3, 0.02, 1.5, 0.0, WraithFx.NIGHT.lightened(0.2), 0.5],
			[0.11, 0.1, 3.2, 0.0, WraithFx.SPIRIT, 0.8],
			[0.08, 0.1, 3.2, PI, WraithFx.VIOLET, 0.7],
			[0.04, 0.01, 2.0, 1.0, WraithFx.PALE, 0.85],
		]
		for s in strands:
			var pts := []
			var ws := []
			var cols := []
			for i in n + 1:
				var u := float(i) / n
				pts.append(_at(u, float(s[1]), float(s[2]), float(s[3])))
				ws.append(float(s[0]) * (0.6 + 0.4 * sin(u * PI)) * grow * fade)
				var pulse := pow(0.5 + 0.5 * sin(u * _len * 2.5 - t * 12.0 + jitter), 5.0)
				var c: Color = s[4]
				cols.append(Color(c.r, c.g, c.b, clampf(float(s[5]) * (0.5 + 0.8 * pulse) * fade, 0.0, 1.0)))
			_strip(im, pts, ws, cols, _side)
		# motes of the stolen soul drifting down the tether into the hand
		for k in 10:
			var h := fposmod(sin(k * 12.9898 + jitter) * 43758.5453, 1.0)
			var u := fposmod(k / 10.0 + h * 0.1 - t * (0.6 + h * 0.5), 1.0)
			var e := sin(u * PI)
			var mp := _at(u, 0.08 + h * 0.12, 3.2, k * 1.7)
			_blob(im, mp, (0.05 + 0.05 * h) * (0.4 + 0.6 * e) * fade, Color(0.95, 1.0, 1.0, 0.9 * e * fade), Color(WraithFx.SPIRIT.r, WraithFx.SPIRIT.g, WraithFx.SPIRIT.b, 0.0), 6)
		# the soul being torn loose: a pale knot writhing at the victim
		var throb := 1.0 + 0.25 * sin(t * 16.0)
		_blob(im, to, 0.5 * throb * fade, Color(WraithFx.VIOLET.r, WraithFx.VIOLET.g, WraithFx.VIOLET.b, 0.3 * fade), Color(0.1, 0.0, 0.2, 0.0), 14)
		_blob(im, to, 0.22 * throb * fade, Color(1.0, 1.0, 1.0, 0.8 * fade), Color(WraithFx.SPIRIT.r, WraithFx.SPIRIT.g, WraithFx.SPIRIT.b, 0.0), 10, 0.4)
		# the grip: a small vortex at the hand
		_blob(im, from, 0.16 * fade, Color(WraithFx.PALE.r, WraithFx.PALE.g, WraithFx.PALE.b, 0.7 * fade), Color(WraithFx.VIOLET.r, WraithFx.VIOLET.g, WraithFx.VIOLET.b, 0.0), 8, 0.3)
		im.surface_end()

static func tether(root: Node3D) -> Tether:
	var t := Tether.new()
	root.add_child(t)
	return t

## The tether's bite: a flash of violet where it sinks in.
static func latch(root: Node3D, pos: Vector3) -> void:
	_spirit_burst(root, pos, VIOLET, 14, 2.5, 0.09, 0.4, true, 0.0)
	Fx.flash(root, pos, VIOLET, 1.6, 0.25, 3.0)

## A ring of pale light that races out from a point in the air (hits, the soul leaving).
static func pulse(root: Node3D, pos: Vector3, col: Color, size: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.sph(1.0, 16)
	var m := Mats.glow_unique(col, 1.6, 0.0, 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.1
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, dur)
	_free_later(mi, dur + 0.05)

# ---------------------------------------------------------------- Shadowstep: the mist and the shade
## He comes apart into mist: dark smoke curling up off him and a cold flash in it.
static func mist_out(root: Node3D, pos: Vector3) -> void:
	_spirit_burst(root, pos + Vector3(0, 0.9, 0), Color(0.3, 0.26, 0.42, 0.7), 34, 2.0, 0.4, 0.9, false, 0.9, 120.0)
	_spirit_burst(root, pos + Vector3(0, 1.0, 0), SPIRIT, 20, 2.5, 0.09, 0.5, true, 0.0)
	Fx.flash(root, pos + Vector3(0, 1.1, 0), VIOLET, 2.2, 0.3, 5.0)

## He re-forms: mist drawn in off the ground into the body, a ring of spirit-light, a flash.
static func mist_in(root: Node3D, pos: Vector3) -> void:
	_soul_ring(root, pos, 2.2, SPIRIT, 0.32, 0.12)
	var p := _spirit_burst(root, pos + Vector3(0, 0.15, 0), SPIRIT, 30, 4.0, 0.12, 0.6, true, 3.5, 30.0)
	p.position = pos + Vector3(0, 0.15, 0)
	_spirit_burst(root, pos + Vector3(0, 0.7, 0), Color(0.3, 0.26, 0.42, 0.6), 18, 1.4, 0.4, 0.7, false, 1.2)

## The shade he left: a dark echo of his shape (an afterimage) standing where he was, which caves in on itself.
static func shade_collapse(root: Node3D, pos: Vector3) -> void:
	_soul_ring(root, pos, 2.6, VIOLET, 0.35, 0.3)
	_spirit_burst(root, pos + Vector3(0, 0.8, 0), VIOLET, 28, 5.0, 0.12, 0.45, true, 0.0)
	_spirit_burst(root, pos + Vector3(0, 0.9, 0), Color(0.3, 0.26, 0.42, 0.7), 16, 2.5, 0.45, 0.7, false, 0.6)
	Fx.flash(root, pos + Vector3(0, 1.0, 0), VIOLET, 3.0, 0.3, 6.0)

# ---------------------------------------------------------------- afterimages (Shadowstep, Phantom Assault, Eternal Night)
## A ghost of the Wraith frozen in his pose this instant: a copy of the skinned body (the armature with its bone
## poses) under its own spectral materials, tinted and thinned to spirit (the shader's "ghost" and phase_amt).
## It lives `life` seconds, dissolving over the last part. Returns the ghost's root (its origin = the hero's).
static func afterimage(rig: Node3D, root: Node3D, tint: Color, life: float, start_phase := 0.3) -> Node3D:
	var body: Node3D = rig.get_node_or_null("Body")
	if body == null:
		return null
	var arm: Node3D = body.get_node_or_null("Armature")
	if arm == null:
		return null
	var g := Node3D.new()
	root.add_child(g)
	g.global_transform = rig.global_transform
	var b := Node3D.new()
	b.transform = body.transform       # the float's lean and height, the turn
	g.add_child(b)
	var copy: Node3D = arm.duplicate()
	b.add_child(copy)
	var mats := []
	for mi in copy.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in (m.mesh.get_surface_count() if m.mesh != null else 0):
			var src := m.get_surface_override_material(si) as ShaderMaterial
			if src == null:
				continue
			var mat := src.duplicate() as ShaderMaterial
			mat.set_shader_parameter("ghost", 1.0)
			mat.set_shader_parameter("spirit", tint)
			mat.set_shader_parameter("phase_amt", start_phase)
			mat.set_shader_parameter("glow", 2.0)
			m.set_surface_override_material(si, mat)
			mats.append(mat)
	g.set_meta("mats", mats)
	g.set_meta("born", 0.0)
	var tw := g.create_tween()
	tw.tween_method(func(v: float):
		for mt in mats:
			(mt as ShaderMaterial).set_shader_parameter("phase_amt", v), start_phase, 1.0, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_free_later(g, life + 0.05)
	return g

# ---------------------------------------------------------------- Haunting Grasp
## Spectral hands bursting up out of the ground round a point: long-fingered claws of spirit-light reaching up and
## closing, on a dark stain that spreads under them; they sink again as the hold ends.
static func grasp(root: Node3D, pos: Vector3, radius: float, dur: float) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos
	# the stain: a dark disc with a violet rim, grown out
	var stain := MeshInstance3D.new()
	stain.mesh = _disc_mesh()
	var sm := _floor_mat(VIOLET, 0.0)
	stain.material_override = sm
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(stain)
	stain.position.y = 0.04
	stain.scale = Vector3.ONE * 0.2
	var tw := stain.create_tween()
	tw.tween_property(stain, "scale", Vector3.ONE * radius, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(maxf(dur - 0.6, 0.1))
	tw.tween_method(func(v: float): sm.set_shader_parameter("amt", v), 1.0, 0.0, 0.5)
	sm.set_shader_parameter("amt", 1.0)
	# the hands: eight round the ring, two in the middle, each a palm and four fingers, rising then closing
	var hands := []
	for i in 9:
		var a := TAU * i / 8.0 + 0.3
		var r := radius * (0.72 if i < 8 else 0.0) + (randf_range(-0.2, 0.2) if i < 8 else 0.0)
		var h := Node3D.new()
		n.add_child(h)
		h.position = Vector3(cos(a) * r, -0.9, sin(a) * r)
		h.rotation.y = -a + PI * 0.5 + randf_range(-0.4, 0.4)
		var palm := MeshInstance3D.new()
		palm.mesh = Geo.cyl(0.07, 0.11, 0.9, 7)
		palm.material_override = Mats.glow_unique(VIOLET.lerp(NIGHT, 0.4), 1.1, 0.0, 0.9)
		palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		palm.position.y = 0.45
		h.add_child(palm)
		var fingers := []
		for k in 4:
			var f := MeshInstance3D.new()
			f.mesh = _claw_mesh()
			f.material_override = Mats.glow_unique(SPIRIT.lerp(VIOLET, 0.35), 1.5, 0.0, 0.0)
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			f.position = Vector3((k - 1.5) * 0.06, 0.92, 0.0)
			f.rotation_degrees = Vector3(180.0 - 35.0, 0.0, (k - 1.5) * 10.0)   # the claws point up, curling inward
			f.scale = Vector3(2.6, 0.42, 2.6)
			h.add_child(f)
			fingers.append(f)
		hands.append([h, fingers])
		var rise := h.create_tween()
		rise.tween_interval(0.03 * i)
		rise.tween_property(h, "position:y", 0.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		# the fingers close on whatever is there
		for f in fingers:
			var cl: Tween = f.create_tween()
			cl.tween_interval(0.25 + 0.03 * i)
			cl.tween_property(f, "rotation_degrees:x", 180.0 - 85.0, 0.18).set_ease(Tween.EASE_IN)
		var sink := h.create_tween()
		sink.tween_interval(maxf(dur - 0.45, 0.1))
		sink.tween_property(h, "position:y", -1.0, 0.45).set_ease(Tween.EASE_IN)
	n.set_meta("hands", hands)
	_spirit_burst(root, pos + Vector3(0, 0.2, 0), Color(0.08, 0.04, 0.12, 0.85), 30, 3.0, 0.35, 0.8, false, 1.5, 70.0)
	_spirit_burst(root, pos + Vector3(0, 0.3, 0), VIOLET, 30, 4.5, 0.1, 0.6, true, 1.0, 60.0)
	Fx.flash(root, pos + Vector3(0, 1.0, 0), VIOLET, 2.5, 0.5, radius * 2.5)
	_free_later(n, dur + 0.1)
	return n

## A dark ground decal: black fading to a coloured rim, with slow drifting noise.
static func _floor_mat(col: Color, amt: float) -> ShaderMaterial:
	if _floor_shader == null:
		_floor_shader = Shader.new()
		_floor_shader.code = FLOOR_SHADER
	var m := ShaderMaterial.new()
	m.shader = _floor_shader
	m.set_shader_parameter("rim", col)
	m.set_shader_parameter("amt", amt)
	return m

const FLOOR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 rim : source_color = vec3(0.6, 0.4, 1.0);
uniform float amt = 1.0;
uniform float runes = 0.0;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
void fragment(){
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float n = vn(c * 9.0 + vec2(TIME * 0.25, -TIME * 0.17)) * 0.5 + vn(c * 19.0 - TIME * 0.4) * 0.25;
	float edge = 1.0 - smoothstep(0.78, 1.0, r + (n - 0.4) * 0.25);
	float dark = edge * 0.78;
	float ring = smoothstep(0.1, 0.0, abs(r - 0.86 + (n - 0.4) * 0.2)) * 0.9;
	float ang = atan(c.y, c.x);
	float rn = 0.0;
	if (runes > 0.0) {
		float spokes = smoothstep(0.75, 1.0, sin(ang * 12.0 + TIME * 0.6) * 0.5 + 0.5) * smoothstep(0.3, 0.45, r) * (1.0 - smoothstep(0.7, 0.8, r));
		float inner = smoothstep(0.06, 0.0, abs(r - 0.42));
		rn = (spokes + inner) * runes;
	}
	vec3 col = mix(vec3(0.02, 0.01, 0.04), rim, clamp(ring + rn, 0.0, 1.0) * 0.8) * (0.6 + 0.4 * n);
	ALBEDO = col * (1.0 + (ring + rn) * 0.7);
	ALPHA = clamp(dark + ring * 0.9 + rn * 0.6, 0.0, 1.0) * amt;
}
"""

# ---------------------------------------------------------------- Phantom Assault
## Where a phantom tears through a foe: a pale crescent and a spray.
static func phantom_hit(root: Node3D, pos: Vector3, dir: Vector3) -> void:
	_spirit_burst(root, pos, PALE, 14, 4.0, 0.08, 0.35, true, 0.0, 70.0, dir)
	Fx.flash(root, pos, VIOLET, 1.4, 0.15, 3.5)

## The split: a violet flash and a ring where the phantoms leave him.
static func split(root: Node3D, pos: Vector3) -> void:
	Fx.flash(root, pos + Vector3(0, 1.2, 0), VIOLET, 3.0, 0.35, 6.0)
	_spirit_burst(root, pos + Vector3(0, 1.0, 0), VIOLET, 26, 3.5, 0.1, 0.5, true, 0.0)
	_soul_ring(root, pos, 2.0, VIOLET, 0.3, 0.2)

# ---------------------------------------------------------------- Eternal Night
## The night: the screen's edges close in with violet dark (the vignette's "night", `grade`: the hero's own light
## stays in the middle, so the fight is readable), the dark floor under him with his runes turning, and souls
## drifting up out of the ground. `set_night(n, k)` brings it down (k 0..1) and lifts it again.
static func night(root: Node3D, pos: Vector3, radius: float, grade: ShaderMaterial = null) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos
	var floor_m := MeshInstance3D.new()
	floor_m.mesh = _disc_mesh()
	var fm := _floor_mat(VIOLET, 0.0)
	fm.set_shader_parameter("runes", 1.0)
	floor_m.material_override = fm
	floor_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_m.position.y = 0.05
	floor_m.scale = Vector3.ONE * radius * 0.6
	n.add_child(floor_m)
	# souls drifting up out of the ground under the night
	var souls := _trail(VIOLET.lerp(PALE, 0.4), 0.14, 60, 2.2)
	var pm := souls.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius * 0.7
	pm.emission_ring_inner_radius = 1.0
	pm.emission_ring_height = 0.2
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	souls.amount_ratio = 0.0
	n.add_child(souls)
	n.set_meta("floor", fm)
	n.set_meta("souls", souls)
	if grade != null:
		n.set_meta("grade", grade)     # the caster's own screen darkens; a puppet's night has no grade
	return n

static func set_night(n: Node3D, k: float) -> void:
	if n == null or not is_instance_valid(n):
		return
	(n.get_meta("floor") as ShaderMaterial).set_shader_parameter("amt", k)
	(n.get_meta("souls") as GPUParticles3D).amount_ratio = k
	if n.has_meta("grade"):
		var g := n.get_meta("grade") as ShaderMaterial
		if g != null:
			g.set_shader_parameter("night", k)

## The scream of the night: three rings of terror racing out, a burst of pale shrieking shapes.
static func scream(root: Node3D, pos: Vector3, radius: float) -> void:
	_soul_ring(root, pos, radius, SPIRIT.darkened(0.3), 0.5, 0.3)
	Fx.later(root, 0.1, func(): _soul_ring(root, pos, radius * 0.85, VIOLET, 0.55, 0.9))
	Fx.later(root, 0.2, func(): _soul_ring(root, pos, radius * 1.05, SPIRIT.darkened(0.55), 0.5, 0.15))
	_spirit_burst(root, pos + Vector3(0, 1.5, 0), Color(0.75, 0.9, 1.0, 0.7), 34, 10.0, 0.22, 0.5, true, 0.0, 180.0)
	_spirit_burst(root, pos + Vector3(0, 0.5, 0), VIOLET, 40, 6.0, 0.12, 0.8, true, 1.5, 90.0)
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.cone(0.6, 2.6, 24)
	var m := Mats.glow_unique(SPIRIT, 2.0, 1.0, 0.6)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos + Vector3(0, 2.4, 0)
	mi.rotation = Vector3(PI, 0, 0)
	mi.scale = Vector3(0.2, 0.3, 0.2)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.6, 1.3, 1.6), 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 0.9, 0.0, 0.45)
	_free_later(mi, 0.6)

## The night's collapse: the dark drawn into the slam and thrown out again as a wave of spirit-light.
static func collapse(root: Node3D, pos: Vector3, radius: float) -> void:
	_soul_ring(root, pos, radius, VIOLET, 0.5, 0.3)
	_soul_ring(root, pos, radius * 0.7, PALE, 0.35, 0.15)
	_spirit_burst(root, pos + Vector3(0, 0.3, 0), SPIRIT, 50, 8.0, 0.14, 0.7, true, 1.0, 80.0)
	_spirit_burst(root, pos + Vector3(0, 0.4, 0), Color(0.06, 0.03, 0.1, 0.9), 30, 4.0, 0.5, 0.9, false, 1.0, 90.0)
	Fx.flash(root, pos + Vector3(0, 1.2, 0), PALE, 5.0, 0.5, radius * 2.0)

## A soft comet trail that stays in world space behind whatever it is attached to.
static func _trail(col: Color, size: float, amount: int, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.15
	pm.gravity = Vector3.ZERO
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.8))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = Mats.particle_mat(true, Color(2, 2, 2))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p

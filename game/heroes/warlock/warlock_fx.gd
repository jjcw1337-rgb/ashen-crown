class_name WarlockFx
extends RefCounted
## Visual effects for the Warlock's skills (her effects script: it only draws, from the events her skills send,
## WarlockSkills). Everything is parented to the zone's FX node.

const FEL := Warlock.FEL
const PALE := Warlock.PALE
const DEEP := Warlock.DEEP

static var _beam_mat: StandardMaterial3D

static func _free_later(n: Node, t: float) -> void:
	n.get_tree().create_timer(t, false).timeout.connect(n.queue_free)

# ---------------------------------------------------------------- the skills' events (SkillFx)
## What each skill shows, on the Warlock's own game and on his puppet on every partner's:
##  Drain Life: "start" {t: [the victim]} (the latch, the sigil, the hum; the beams are h.fxs["drain"], drawn by
##    `update` from his hand to the main victim and arching on to the forks), "victims" {t: all of them now} whenever
##    the set changes, "tick" (the motes of life streaming back and the victims' green flash, every 0.3 s) and
##    "end" (the release). A partner's copy also ends itself after DRAIN_TIMEOUT s without a tick.
##    "healed" {x}: the green "+N" over her (her own screen), about once a second.
##  Blight Bolt: "bolt" {d: direction, x: Twin Skulls}: the skulls fly in h.fxs["blight_bolts"] (`update`) as the
##    rules fly theirs (BlightBolt.fly), hiding at the first foe they meet; "burst" {p, r, x: dur}: the burst and the
##    pool (the skull nearest the burst is taken by it).
##  Soul Shackles: "impact" {r: reach, x: how long, t: the foes bound}
##  Fel Covenant: "impact"
const DRAIN_TIMEOUT := 1.5

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var pos := h.global_position
	match [str(ev["s"]), str(ev["e"])]:
		["drain", "cast"], ["blight", "cast"], ["shackles", "cast"], ["covenant", "cast"]:
			pass
		["drain", "start"]:
			_end_drain(h, false)
			var victims: Array = ev.get("t", [])
			var d := {"victims": victims, "beams": {}, "lit": {}, "light": null, "sigil": sigil(root, 1.25),
				"hum": Sfx.start_loop("drain_loop", -9.0, 1.0, h), "until": DRAIN_TIMEOUT}
			(d["sigil"] as Node3D).global_position = pos + Vector3(0, 0.06, 0)
			h.fxs["drain"] = d
			for e in victims:
				latch(root, SkillFx.chest_of(e, 1.0))
			SkillFx.snd(h, "drain_start", -3.0)
			SkillFx.shake(h, 0.08)
		["drain", "healed"]:
			if not h.puppet and float(ev.get("x", 0.0)) >= 1.0:
				Fx.number(root, h.global_position + Vector3(0, 2.3, 0), "+%d" % int(float(ev["x"])), Color(0.45, 1.0, 0.4))
		["drain", "victims"]:
			if not h.fxs.has("drain"):
				return true
			var d: Dictionary = h.fxs["drain"]
			var was: Array = d["victims"]
			var now: Array = ev.get("t", [])
			for e in now:
				if not was.has(e):
					latch(root, SkillFx.chest_of(e, 1.0))
			d["victims"] = now
			d["until"] = DRAIN_TIMEOUT
		["drain", "tick"]:
			if not h.fxs.has("drain"):
				return true
			var d: Dictionary = h.fxs["drain"]
			d["until"] = DRAIN_TIMEOUT
			var victims: Array = d["victims"]
			if victims.is_empty():
				return true
			var hand := SkillFx.hand(h, false)
			var main = victims[0]
			for i in victims.size():
				var e = victims[i]
				if not is_instance_valid(e):
					continue
				if not e.dead:
					if e.has_method("drain_flash"):
						e.drain_flash(Warlock.FEL)
				siphon(root, SkillFx.chest_of(e, 1.0), hand if i == 0 else (SkillFx.chest_of(main, 1.0) if is_instance_valid(main) else hand))
			if h.puppet:
				Sfx.play_at("drain_tick", pos, -12.0)
			else:
				Sfx.play("drain_tick", -7.0)
		["drain", "end"]:
			_end_drain(h, true)
		["blight", "bolt"]:
			var dir: Vector3 = ev["d"]
			if not h.fxs.has("blight_bolts"):
				h.fxs["blight_bolts"] = []
			for dv in BlightBolt.dirs(dir, bool(ev.get("x", false))):
				var n := bolt_node(root)
				n.global_position = pos + Vector3(0, 1.3, 0) + dv * 0.6
				n.look_at(n.global_position + dv, Vector3.UP)
				h.fxs["blight_bolts"].append({"node": n, "p": n.global_position, "d": dv, "left": float(Data.skill_def("blight").get("range", 15.0))})
		["blight", "burst"]:
			var g: Vector3 = ev["p"]
			var rad: float = float(ev.get("r", 3.0))
			blight_burst(root, g, rad)
			blight_pool(root, g, rad, float(ev.get("x", 4.0)))
			Sfx.play_at("blight_burst", g, -1.0)
			SkillFx.shake(h, 0.18)
			# the skull that burst: the one nearest to it is gone
			var best = null
			var bd := 3.0
			for b in h.fxs.get("blight_bolts", []):
				var n = b["node"]
				if is_instance_valid(n) and n.global_position.distance_to(g) < bd:
					bd = n.global_position.distance_to(g)
					best = b
			if best != null:
				(best["node"] as Node).queue_free()
				h.fxs["blight_bolts"].erase(best)
		["shackles", "impact"]:
			var reach_s: float = float(ev.get("r", 7.0))
			var bind_t: float = float(ev.get("x", 2.5))
			shackle_cast(root, pos, reach_s)
			SkillFx.snd(h, "shackles")
			SkillFx.shake(h, 0.25)
			for e in ev.get("t", []):
				chain(root, pos + Vector3(0, 1.1, 0), SkillFx.chest_of(e, 0.8), 0.8)
				if not e.dead:
					shackle(e, bind_t * (0.3 if e.get("boss") else 1.0))
		["covenant", "impact"]:
			covenant(root, pos)
			SkillFx.snd(h, "covenant")
			SkillFx.duck(h, -9.0, 1.6)
			SkillFx.shake(h, 0.3)
		_:
			return WarlockHarrowFx.play(h, ev)      # his three directions (WarlockHex)
	return true

## The beams let go: the victims' rims, the hand's light, the sigil and the hum are gone.
static func _end_drain(h: Hero, release_flash: bool) -> void:
	if not h.fxs.has("drain"):
		return
	var d: Dictionary = h.fxs["drain"]
	for b in (d["beams"] as Dictionary).values():
		if is_instance_valid(b):
			b.queue_free()
	for e in (d["lit"] as Dictionary).values():
		if is_instance_valid(e):
			e.set_drained(false)
	var l = d["light"]
	if l != null and is_instance_valid(l):
		if release_flash and h.game.world != null:
			release(h.game.world.fx_root, l.global_position)
		l.queue_free()
	if d["sigil"] != null:
		sigil_fade(d["sigil"])
	var hum = d["hum"]
	if hum != null and is_instance_valid(hum):
		hum.stop()
		hum.queue_free()
	h.fxs.erase("drain")

## Every frame after the pose: the beams leave the hand where it is now and follow the victims; the skulls fly.
static func update(h: Hero, delta: float) -> void:
	if h.fxs.has("drain"):
		_draw_drain(h, delta)
	if not (h.fxs.get("blight_bolts", []) as Array).is_empty():
		_fly_bolts(h, delta)
	WarlockHarrowFx.update(h, delta)

static func _draw_drain(h: Hero, delta: float) -> void:
	var d: Dictionary = h.fxs["drain"]
	if h.puppet:
		d["until"] = float(d["until"]) - delta
		if float(d["until"]) <= 0.0:
			_end_drain(h, false)
			return
	var victims: Array = (d["victims"] as Array).filter(func(e): return is_instance_valid(e) and not e.dead)
	var root: Node3D = h.game.world.fx_root
	var hand: Vector3 = SkillFx.hand(h, false) + (-h.rig.global_transform.basis.z) * 0.08
	var beams: Dictionary = d["beams"]
	var lit: Dictionary = d["lit"]
	var keep := {}
	if not victims.is_empty():
		var main = victims[0]
		var mc: Vector3 = SkillFx.chest_of(main, 1.0)
		for i in victims.size():
			var e = victims[i]
			var id: int = e.get_instance_id()
			keep[id] = true
			var b = beams.get(id)
			if b == null or not is_instance_valid(b):
				b = beam(root, 0.26 if i == 0 else 0.15)
				beams[id] = b
			b.width = 0.26 if i == 0 else 0.15
			b.caps = i == 0
			if not lit.has(id) and e.has_method("set_drained"):
				lit[id] = e
				e.set_drained(true)
			if i == 0:
				b.draw(hand, mc, h.anim_time)
			else:
				var ec: Vector3 = SkillFx.chest_of(e, 1.0)
				b.arc = 0.45 + mc.distance_to(ec) * 0.12
				b.draw(mc, ec, h.anim_time)
	for id in beams.keys():
		if not keep.has(id):
			var b = beams[id]
			if is_instance_valid(b):
				b.queue_free()
			beams.erase(id)
	for id in lit.keys():
		if not keep.has(id):
			var e = lit[id]
			if is_instance_valid(e):
				e.set_drained(false)
			lit.erase(id)
	var l = d["light"]
	if l == null or not is_instance_valid(l):
		l = hand_light(root)
		d["light"] = l
	l.global_position = hand
	l.light_energy = 1.5 + 0.4 * sin(h.anim_time * 23.0) + 0.3 * sin(h.anim_time * 7.0)
	var sg = d["sigil"]
	if sg != null and is_instance_valid(sg):
		sg.global_position = h.global_position + Vector3(0, 0.06, 0)
		sg.rotation.y = h.anim_time * 0.9

## A Blight Bolt's skull flies straight as its rules' does (BlightBolt.fly), until the "burst" event takes it (the
## rules found a foe, a wall or the end of its range), or quietly vanishes at a wall, its range or the first foe it
## meets (the burst comes a moment later from the rules, here or from the match server).
static func _fly_bolts(h: Hero, delta: float) -> void:
	var world = h.game.world
	var bolts: Array = h.fxs["blight_bolts"]
	var speed := Skill.num("blight", "speed", 16.0)
	var near := Skill.num("blight", "near", 1.0)
	for b in bolts.duplicate():
		var n = b["node"]
		if not is_instance_valid(n):
			bolts.erase(b)
			continue
		var blocked := BlightBolt.fly(world, b, delta, speed)
		var np: Vector3 = b["p"]
		n.global_position = np
		if blocked or not h.game.enemies_near(np, near).filter(func(e) -> bool: return int(e.get("pvp_pid")) != int(h.peer_id) or int(h.peer_id) <= 0).is_empty():
			n.queue_free()
			bolts.erase(b)

static func clear(h: Hero) -> void:
	_end_drain(h, false)
	WarlockHarrowFx.clear(h)
	for b in h.fxs.get("blight_bolts", []):
		if is_instance_valid(b["node"]):
			(b["node"] as Node).queue_free()
	h.fxs.erase("blight_bolts")

## One Drain Life beam: twisting green strands redrawn every frame, turned to face the
## camera. Bright pulses and motes of life run from the victim back toward the caster, a
## glowing bite sits on the victim and (on the main beam) a vortex swirls in the palm.
class Beam extends MeshInstance3D:
	var width := 0.22
	var arc := 0.0       # lifts the middle of the beam (forks arch from victim to victim)
	var caps := false    # the main beam: a vortex at the caster's hand as well as the bite
	var jitter := 0.0
	var born := -1.0
	# frame state shared by the helpers below
	var _from := Vector3.ZERO
	var _span := Vector3.ZERO
	var _len := 1.0
	var _side := Vector3.RIGHT
	var _up := Vector3.UP
	var _vup := Vector3.UP
	var _t := 0.0

	func _init(w: float) -> void:
		width = w
		jitter = randf() * 10.0
		mesh = ImmediateMesh.new()
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		top_level = true
		material_override = WarlockFx.beam_mat()

	## A point on a strand: u runs 0 (caster) to 1 (victim), pinned at both ends.
	func _at(u: float, wob: float, rate: float, ph: float) -> Vector3:
		var env := sin(u * PI)
		var a := u * rate * TAU * _len / 6.0 + _t * 7.0 + ph + jitter
		var off := (_side * sin(a) + _up * cos(a * 1.3) * 0.6) * wob * env
		return _from + _span * u + off + Vector3.UP * arc * env

	## A soft camera-facing disc: bright in the middle, fading to the rim.
	func _blob(im: ImmediateMesh, p: Vector3, r: float, c0: Color, c1: Color, seg := 12, star := 0.0) -> void:
		for i in seg:
			var a0 := TAU * i / seg + _t * 3.0
			var a1 := TAU * (i + 1) / seg + _t * 3.0
			var r0 := r * (1.0 + star * sin(a0 * 3.0 + _t * 9.0))
			var r1 := r * (1.0 + star * sin(a1 * 3.0 + _t * 9.0))
			im.surface_set_color(c0)
			im.surface_add_vertex(p)
			im.surface_set_color(c1)
			im.surface_add_vertex(p + (_side * cos(a0) + _vup * sin(a0)) * r0)
			im.surface_add_vertex(p + (_side * cos(a1) + _vup * sin(a1)) * r1)

	## A ribbon through pts, each point with its own width and colour, facing the camera.
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

	## from: the end the life flows to (the caster's hand, or the main victim for a fork);
	## to: the victim.
	func draw(from: Vector3, to: Vector3, t: float) -> void:
		global_transform = Transform3D.IDENTITY
		var im: ImmediateMesh = mesh
		im.clear_surfaces()
		if born < 0.0:
			born = t
		# on the latch the beam shoots out from the hand to the victim
		var grow := 1.0 - pow(1.0 - clampf((t - born) / 0.16, 0.0, 1.0), 3.0)
		to = from.lerp(to, grow)
		_t = t
		_from = from
		_span = to - from
		_len = _span.length()
		if _len < 0.05:
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
		var n := clampi(int(_len * 5.0), 12, 60)
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		# strands: [width, wobble, twist rate, phase, colour, alpha]
		var strands := [
			[width * 2.2, 0.05, 2.0, 0.0, WarlockFx.DEEP, 0.45],
			[width, 0.14, 3.0, 0.0, WarlockFx.FEL, 0.75],
			[width * 0.6, 0.2, 4.5, 2.1, WarlockFx.FEL, 0.6],
			[width * 0.45, 0.24, 3.7, 4.4, WarlockFx.DEEP.lightened(0.3), 0.7],
			[width * 0.28, 0.03, 2.5, 4.0, WarlockFx.PALE, 0.75],
		]
		for s in strands:
			var pts := []
			var ws := []
			var cols := []
			for i in n + 1:
				var u := float(i) / n
				pts.append(_at(u, float(s[1]), float(s[2]), float(s[3])))
				ws.append(float(s[0]) * (0.55 + 0.45 * sin(u * PI)) * grow)
				# pulses travel from the victim (u = 1) to the caster (u = 0)
				var pulse := pow(0.5 + 0.5 * sin(u * _len * 2.2 + t * 14.0 + jitter), 6.0)
				var c: Color = s[4]
				var al: float = float(s[5]) * (0.55 + 0.9 * pulse) * smoothstep(0.0, 0.05, u)
				cols.append(Color(c.r, c.g, c.b, clampf(al, 0.0, 1.0)))
			_strip(im, pts, ws, cols, _side)
		# motes of stolen life drifting down the beam into the hand
		for k in 12:
			var h := fposmod(sin(k * 12.9898 + jitter) * 43758.5453, 1.0)
			var u := fposmod(k / 12.0 + h * 0.08 - t * (0.75 + h * 0.4), 1.0)
			var e := sin(u * PI)
			var mp := _at(u, 0.1 + h * 0.2, 3.0, k * 1.7)
			_blob(im, mp, width * (0.22 + 0.2 * h) * (0.4 + 0.6 * e), Color(0.9, 1.0, 0.8, 0.95 * e), Color(0.4, 1.0, 0.3, 0.0), 6)
		# the bite: where the beam sinks into the victim
		var throb := 1.0 + 0.2 * sin(t * 18.0)
		_blob(im, to, width * 3.2 * throb, Color(WarlockFx.FEL.r, WarlockFx.FEL.g, WarlockFx.FEL.b, 0.35), Color(0.0, 0.3, 0.0, 0.0), 16)
		_blob(im, to, width * 1.3 * throb, Color(0.75, 1.0, 0.65, 0.75), Color(WarlockFx.FEL.r, WarlockFx.FEL.g, WarlockFx.FEL.b, 0.0), 12, 0.35)
		if caps:
			# a vortex in the palm: three arms spiralling into a bright core
			_blob(im, from, width * 2.4, Color(WarlockFx.FEL.r, WarlockFx.FEL.g, WarlockFx.FEL.b, 0.3), Color(0.0, 0.3, 0.0, 0.0), 16)
			for arm in 3:
				var pts := []
				var ws := []
				var cols := []
				for i in 10:
					var f := float(i) / 9.0
					var ang := arm * TAU / 3.0 + f * 2.6 - t * 9.0
					var rr := width * 2.1 * (1.0 - f)
					pts.append(from + (_side * cos(ang) + _vup * sin(ang)) * rr)
					ws.append(width * 0.28 * (0.3 + f))
					cols.append(Color(0.6, 1.0, 0.5, 0.15 + 0.8 * f))
				_strip(im, pts, ws, cols, _vup)
			_blob(im, from, width * 0.8, Color(0.8, 1.0, 0.7, 0.75), Color(WarlockFx.FEL.r, WarlockFx.FEL.g, WarlockFx.FEL.b, 0.0), 10)
		im.surface_end()

static func beam_mat() -> StandardMaterial3D:
	if _beam_mat == null:
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mat.vertex_color_use_as_albedo = true
		_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_mat.no_depth_test = false
		_beam_mat.albedo_color = Color(1.15, 1.15, 1.15)
	return _beam_mat

static func beam(root: Node3D, w: float) -> Beam:
	var b := Beam.new(w)
	root.add_child(b)
	return b

## The fel light popping on what's round a blow and dying (no sprite: the blows draw their own glows).
static func flash_light(root: Node3D, pos: Vector3, col: Color, energy: float, life: float, reach: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, life).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)

## A green light riding the caster's hand while the beam is up.
static func hand_light(root: Node3D) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = FEL
	l.light_energy = 1.6
	l.omni_range = 4.5
	l.shadow_enabled = false
	root.add_child(l)
	return l

## Life torn out of a victim: a puff of motes streaming toward the caster.
static func siphon(root: Node3D, at: Vector3, toward: Vector3) -> void:
	var d := toward - at
	InfernalFx.particles(root, at, {"amount": 7, "life": 0.4, "explosive": 0.9, "shape": "sphere", "r": 0.15,
		"dir": d.normalized() if d.length() > 0.1 else Vector3.UP, "spread": 22.0, "vel": [2.6, 4.0], "damping": [1.0, 2.0],
		"scale": [0.5, 1.0], "size": 0.07, "grow": [1.0, 0.3], "turb": 0.3,
		"colors": [[0.0, Color(PALE, 0.0)], [0.2, PALE], [0.7, FEL], [1.0, Color(FEL, 0.0)]]})

## The latch: a flash where the beam first bites.
static func latch(root: Node3D, at: Vector3) -> void:
	var g := InfernalFx.glow(root, at, 0.9, InfernalFx.glow_mat(PALE, 2.4, 2.4, 0.4))
	var tw := g.create_tween()
	tw.set_parallel(true)
	tw.tween_property(g, "scale", Vector3.ONE * 1.6, 0.25).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, g.material_override as ShaderMaterial, "alpha", 1.0, 0.0, 0.25)
	_free_later(g, 0.3)
	InfernalFx.particles(root, at, {"amount": 12, "life": 0.45, "explosive": 1.0, "shape": "sphere", "r": 0.1,
		"dir": Vector3.UP, "spread": 180.0, "vel": [1.5, 3.0], "damping": [2.0, 3.0], "scale": [0.5, 1.0], "size": 0.06,
		"colors": [[0.0, PALE], [0.6, FEL], [1.0, Color(DEEP, 0.0)]]})
	flash_light(root, at, FEL, 2.0, 0.25, 4.0)

## The fel sigil that turns on the ground under a channelling Warlock.
static func sigil(root: Node3D, radius: float) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	var m := Mats.glow_unique(FEL, 0.65)
	var faint := Mats.glow_unique(DEEP.lightened(0.25), 0.9)
	for spec in [[radius, 0.06, m], [radius * 0.64, 0.04, m], [radius * 0.84, 0.025, faint]]:
		var ring := MeshInstance3D.new()
		ring.mesh = Geo.torus(float(spec[0]) - float(spec[1]), float(spec[0]), 48, 4)
		ring.material_override = spec[2]
		ring.scale = Vector3(1.0, 0.2, 1.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(ring)
	# a pentagram inside the inner ring
	var pr := radius * 0.64
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := TAU * ((i + 2) % 5) / 5.0
		var p0 := Vector3(sin(a0), 0, -cos(a0)) * pr
		var p1 := Vector3(sin(a1), 0, -cos(a1)) * pr
		var d := p1 - p0
		var line := MeshInstance3D.new()
		line.mesh = Geo.box(0.035, 0.01, d.length())
		line.material_override = m
		line.position = (p0 + p1) * 0.5
		line.rotation.y = atan2(d.x, d.z)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(line)
	# rune marks between the rings
	for k in 12:
		var a := TAU * k / 12.0
		var rune := MeshInstance3D.new()
		rune.mesh = Geo.box(0.04, 0.01, 0.13 if k % 3 == 0 else 0.08)
		rune.material_override = m
		rune.position = Vector3(sin(a), 0, -cos(a)) * radius * 0.82
		rune.rotation.y = a + (0.6 if k % 2 == 0 else 0.0)
		rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(rune)
	n.scale = Vector3(0.6, 1.0, 0.6)
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float):
		m.set_shader_parameter("alpha_mul", v)
		faint.set_shader_parameter("alpha_mul", v), 0.0, 1.0, 0.2)
	n.set_meta("mats", [m, faint])
	return n

## The sigil gutters out when the channel ends.
static func sigil_fade(n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	var mats: Array = n.get_meta("mats") if n.has_meta("mats") else []
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector3(1.25, 1.0, 1.25), 0.3)
	tw.tween_method(_set_alpha.bind(mats), 1.0, 0.0, 0.3)
	_free_later(n, 0.35)

static func _set_alpha(v: float, mats: Array) -> void:
	for mm in mats:
		(mm as ShaderMaterial).set_shader_parameter("alpha_mul", v)

## Released: the stolen life left in the palm flares and scatters.
static func release(root: Node3D, at: Vector3) -> void:
	InfernalFx.particles(root, at, {"amount": 18, "life": 0.7, "explosive": 0.9, "shape": "sphere", "r": 0.12,
		"dir": Vector3.UP, "spread": 120.0, "vel": [0.8, 2.2], "gravity": 0.8, "damping": [1.0, 1.6], "turb": 0.4,
		"scale": [0.4, 1.0], "size": 0.07, "colors": [[0.0, PALE], [0.5, FEL], [1.0, Color(FEL, 0.0)]]})

## Blight Bolt in flight: a pale-green skull of fire trailing fel flame.
static func bolt_node(root: Node3D) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	var core := MeshInstance3D.new()
	core.mesh = Geo.sph(0.12, 12)
	core.material_override = Mats.glow(PALE, 4.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	var halo := MeshInstance3D.new()
	halo.mesh = Geo.sph(0.24, 12)
	halo.material_override = Mats.glow(FEL, 1.4, 0.0, 1.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(halo)
	# two dark eye sockets so it reads as a skull
	for sx in [-1, 1]:
		var e := MeshInstance3D.new()
		e.mesh = Geo.sph(0.035, 6)
		e.material_override = Mats.flat(Color(0.0, 0.05, 0.0))
		e.position = Vector3(0.045 * sx, 0.03, -0.1)
		n.add_child(e)
	n.add_child(Warlock.fel_flame(1.3, FEL))
	var l := OmniLight3D.new()
	l.light_color = FEL
	l.light_energy = 1.2
	l.omni_range = 3.5
	n.add_child(l)
	return n

## Fel fire: InfernalFx's hellfire flame with the Warlock's palette (a black shell, deep green, fel, pale at the core).
static func fel_flame_mat(dark := 0.7, heat := 1.15) -> ShaderMaterial:
	var m := InfernalFx.flame_mat(dark, heat, 1.2)
	m.set_shader_parameter("crimson", DEEP)
	m.set_shader_parameter("molten", FEL)
	m.set_shader_parameter("whitehot", PALE)
	return m

## n fel flames standing round pos on a ring of radius r (heights h0..h1), licking up and dying over `life`.
static func fel_ring(root: Node3D, pos: Vector3, r: float, n: int, h0: float, h1: float, life: float, delay_max := 0.08) -> void:
	for i in n:
		var a := TAU * (float(i) + randf_range(-0.3, 0.3)) / n
		var at := pos + Vector3(cos(a), 0, sin(a)) * r * randf_range(0.85, 1.05)
		var hh := randf_range(h0, h1)
		var m := fel_flame_mat()
		var f := InfernalFx.flame(root, at + Vector3(0, hh * 0.42, 0), Vector2(hh * 0.55, hh), m)
		f.scale = Vector3(hh * 0.55, hh * 0.15, 1.0)
		var d0 := randf_range(0.0, delay_max)
		var tw := f.create_tween()
		tw.tween_interval(d0)
		tw.tween_property(f, "scale", Vector3(hh * 0.55, hh, 1.0), 0.12).set_ease(Tween.EASE_OUT)
		InfernalFx.tween_param(f, m, "alpha", 1.0, 0.0, life * 0.6, d0 + life * 0.4)
		_free_later(f, d0 + life + 0.1)

## Blight Bolt bursting: a ring of fel fire licks up round the blast, a pale flare at its heart, sickly smoke rolls
## out, gobbets of blight splash down and three souls wail up out of it (the generic ring and bursts it was).
static func blight_burst(root: Node3D, pos: Vector3, radius: float) -> void:
	var tr := InfernalFx.tier(root.get_tree().current_scene if root.is_inside_tree() else null)
	fel_ring(root, pos, radius * 0.6, [6, 8, 11, 14][tr], 0.9, 1.6, 0.65)
	var g := InfernalFx.glow(root, pos + Vector3(0, 0.7, 0), 2.0, InfernalFx.glow_mat(PALE, 2.6, 2.4, 0.7))
	var tg := g.create_tween()
	tg.set_parallel(true)
	tg.tween_property(g, "scale", Vector3.ONE * 3.0, 0.3).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, g.material_override as ShaderMaterial, "alpha", 1.0, 0.0, 0.3)
	_free_later(g, 0.35)
	flash_light(root, pos + Vector3(0, 1.0, 0), FEL, 3.0, 0.35, 7.0)
	InfernalFx.particles(root, pos + Vector3(0, 0.5, 0), {"amount": [5, 7, 10, 14][tr], "life": 1.5, "explosive": 0.9,
		"shape": "sphere", "r": radius * 0.3, "dir": Vector3.UP, "spread": 80.0, "vel": [0.6, 1.8], "radial": [1.0, 2.0],
		"gravity": 0.25, "damping": [1.0, 1.6], "scale": [0.8, 1.4], "size": 1.3, "grow": [0.5, 1.6], "angle": true, "spin": 20.0,
		"add": false, "colors": [[0.0, Color(0.06, 0.14, 0.04, 0.0)], [0.12, Color(0.07, 0.16, 0.05, 0.7)], [0.7, Color(0.05, 0.1, 0.04, 0.35)], [1.0, Color(0.04, 0.08, 0.03, 0.0)]]})
	InfernalFx.particles(root, pos + Vector3(0, 0.4, 0), {"amount": [8, 12, 18, 24][tr], "life": 0.8, "explosive": 1.0,
		"shape": "sphere", "r": 0.3, "dir": Vector3.UP, "spread": 70.0, "vel": [3.0, 6.5], "gravity": -12.0,
		"scale": [0.5, 1.1], "size": 0.09, "add": false, "colors": [[0.0, Color(0.2, 0.55, 0.12)], [1.0, Color(0.06, 0.2, 0.04)]]})
	for k in 3:
		var soul := InfernalFx.glow(root, pos + Vector3(randf_range(-0.6, 0.6), 0.6, randf_range(-0.6, 0.6)), 0.7, InfernalFx.glow_mat(PALE, 1.8, 3.2, 0.0))
		var ts := soul.create_tween()
		ts.set_parallel(true)
		ts.tween_property(soul, "global_position:y", pos.y + randf_range(2.6, 3.6), 1.1).set_ease(Tween.EASE_OUT)
		ts.tween_property(soul, "scale", Vector3(0.35, 1.1, 0.35), 1.1)
		InfernalFx.tween_param(soul, soul.material_override as ShaderMaterial, "alpha", 1.0, 0.0, 0.8, 0.3)
		_free_later(soul, 1.15)

## A plague pool: a soft, ragged green stain glowing brightest just inside its edge, with
## bubbles rising off it.
static func blight_pool(root: Node3D, pos: Vector3, radius: float, dur: float) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos + Vector3(0, 0.07, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 48
	var ph := randf() * TAU
	# rings out from the centre: [radius fraction, colour]
	var rings := [[0.0, Color(0.02, 0.2, 0.03, 0.12)], [0.55, Color(0.04, 0.32, 0.05, 0.18)],
		[0.86, Color(0.25, 0.9, 0.2, 0.42)], [1.0, Color(0.05, 0.4, 0.05, 0.0)]]
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		# a ragged edge: the radius wanders around the circle
		var w0 := 1.0 + 0.09 * sin(a0 * 5.0 + ph) + 0.05 * sin(a0 * 11.0 + ph * 2.0)
		var w1 := 1.0 + 0.09 * sin(a1 * 5.0 + ph) + 0.05 * sin(a1 * 11.0 + ph * 2.0)
		for k in rings.size() - 1:
			var f0: float = rings[k][0]
			var f1: float = rings[k + 1][0]
			var c0: Color = rings[k][1]
			var c1: Color = rings[k + 1][1]
			var p00 := Vector3(sin(a0), 0, -cos(a0)) * radius * f0 * w0
			var p01 := Vector3(sin(a1), 0, -cos(a1)) * radius * f0 * w1
			var p10 := Vector3(sin(a0), 0, -cos(a0)) * radius * f1 * w0
			var p11 := Vector3(sin(a1), 0, -cos(a1)) * radius * f1 * w1
			for v in [[p00, c0], [p10, c1], [p11, c1], [p00, c0], [p11, c1], [p01, c0]]:
				st.set_color(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	var disc := MeshInstance3D.new()
	disc.mesh = st.commit()
	var dm: StandardMaterial3D = beam_mat().duplicate()
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(disc)
	disc.scale = Vector3(0.3, 1.0, 0.3)
	disc.create_tween().tween_property(disc, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var bub := GPUParticles3D.new()
	bub.amount = 36
	bub.lifetime = 1.1
	bub.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius * 0.9
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.02
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.4, 0)
	var g := Gradient.new()
	g.set_color(0, Color(0.35, 0.9, 0.3, 0.7))
	g.set_color(1, Color(0.05, 0.3, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	bub.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	q.material = Mats.particle_mat(true, Color.WHITE)
	bub.draw_pass_1 = q
	bub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(bub)
	var tw := n.create_tween()
	tw.tween_interval(maxf(0.0, dur - 0.6))
	tw.tween_callback(func(): bub.emitting = false)
	tw.tween_property(dm, "albedo_color:a", 0.0, 0.6)
	_free_later(n, dur + 1.2)
	return n

## Soul Shackles: a chain of fel links snapping out from the caster to a victim.
static func chain(root: Node3D, from: Vector3, to: Vector3, dur: float) -> void:
	var d := to - from
	if d.length() < 0.2:
		return
	var c := Node3D.new()
	root.add_child(c)
	c.look_at_from_position(from, to, Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
	var m := Mats.glow_unique(FEL, 1.2)
	var spacing := 0.13
	var count := int(d.length() / spacing)
	for i in count:
		var link := MeshInstance3D.new()
		link.mesh = Geo.torus(0.028, 0.045, 12, 4)
		link.material_override = m
		link.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		link.position = Vector3(0, 0, -(i + 0.5) * spacing)
		link.scale = Vector3(0.75, 1.0, 1.35)
		link.rotation = Vector3(0, 0, PI * 0.5 if i % 2 == 1 else 0.0)
		c.add_child(link)
	c.scale = Vector3(1.0, 1.0, 0.05)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(0.0, dur - 0.5))
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.35)
	_free_later(c, dur + 0.2)

## A glowing fetter around a bound enemy's waist for as long as it is held.
static func shackle(target: Node3D, dur: float) -> void:
	if not is_instance_valid(target):
		return
	var h: float = SkillFx.height_of(target)
	var r: float = float(target.get("radius")) + 0.2
	var n := Node3D.new()
	target.add_child(n)
	n.position = Vector3(0, 0.75 * h, 0)
	var m := Mats.glow_unique(FEL, 0.9)
	for k in 2:
		var ring := MeshInstance3D.new()
		ring.mesh = Geo.torus(r - 0.05, r, 32, 4)
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(0, k * 0.28 * h - 0.14 * h, 0)
		ring.scale = Vector3(1.0, 0.35, 1.0)
		n.add_child(ring)
	var tw := n.create_tween()
	tw.tween_property(n, "rotation:y", TAU * dur * 0.3, dur)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 1.0, 0.0, 0.4).set_delay(maxf(0.0, dur - 0.4))
	_free_later(n, dur + 0.05)

## Soul Shackles' cast: his sigil flares under him and turns, the dark is pulled in from the edge of its reach
## (shadow and fel sparks sucked toward him) and the air shudders (the generic ring and burst it was).
static func shackle_cast(root: Node3D, pos: Vector3, radius: float) -> void:
	var tr := InfernalFx.tier(root.get_tree().current_scene if root.is_inside_tree() else null)
	var sg := sigil(root, 1.7)
	sg.global_position = pos + Vector3(0, 0.06, 0)
	var ts := sg.create_tween()
	ts.tween_property(sg, "rotation:y", -1.6, 0.8)
	Fx.later(sg, 0.55, func(): sigil_fade(sg))
	InfernalFx.particles(root, pos + Vector3(0, 0.6, 0), {"amount": [10, 16, 24, 32][tr], "life": 0.55, "explosive": 0.9,
		"shape": "ring", "r": radius * 0.9, "r_in": radius * 0.6, "dir": Vector3.UP, "spread": 20.0, "vel": [0.2, 0.6],
		"radial": [-26.0, -20.0], "damping": [1.0, 2.0], "scale": [0.8, 1.3], "size": 0.9, "grow": [1.2, 0.3], "angle": true,
		"add": false, "colors": [[0.0, Color(0.02, 0.06, 0.02, 0.0)], [0.2, Color(0.02, 0.06, 0.02, 0.55)], [1.0, Color(0.01, 0.03, 0.01, 0.0)]]})
	InfernalFx.particles(root, pos + Vector3(0, 0.9, 0), {"amount": [12, 18, 26, 36][tr], "life": 0.5, "explosive": 0.85,
		"shape": "ring", "r": radius * 0.85, "r_in": radius * 0.5, "dir": Vector3.UP, "spread": 30.0, "vel": [0.2, 0.8],
		"radial": [-30.0, -22.0], "damping": [0.5, 1.0], "scale": [0.4, 0.9], "size": 0.06,
		"colors": [[0.0, Color(FEL, 0.0)], [0.25, FEL], [1.0, Color(PALE, 0.0)]]})
	HolyFx.shockwave(root, root.get_tree().current_scene if root.is_inside_tree() else null, pos, radius, 0.4, 0.02)
	flash_light(root, pos + Vector3(0, 1.2, 0), FEL, 2.4, 0.35, 8.0)

## Fel Covenant: his sigil burns big under him, a crown of fel fire roars up round him and souls spiral up through
## it (the generic pillar, ring and burst it was).
static func covenant(root: Node3D, pos: Vector3) -> void:
	var tr := InfernalFx.tier(root.get_tree().current_scene if root.is_inside_tree() else null)
	var sg := sigil(root, 2.6)
	sg.global_position = pos + Vector3(0, 0.06, 0)
	var ts := sg.create_tween()
	ts.tween_property(sg, "rotation:y", 1.2, 1.4)
	Fx.later(sg, 1.0, func(): sigil_fade(sg))
	fel_ring(root, pos, 1.0, [7, 10, 13, 16][tr], 1.8, 2.8, 0.95, 0.15)
	fel_ring(root, pos, 2.3, [0, 6, 9, 12][tr], 0.6, 1.1, 0.7, 0.25)
	InfernalFx.particles(root, pos + Vector3(0, 0.3, 0), {"amount": [14, 22, 32, 44][tr], "life": 1.6, "explosive": 0.6,
		"shape": "ring", "r": 1.2, "r_in": 0.4, "dir": Vector3.UP, "spread": 10.0, "vel": [1.6, 3.2], "radial": [-1.2, -0.6],
		"gravity": 0.6, "damping": [0.4, 0.8], "scale": [0.4, 1.0], "size": 0.07, "turb": 0.9,
		"colors": [[0.0, Color(PALE, 0.0)], [0.12, PALE], [0.6, FEL], [1.0, Color(DEEP, 0.0)]]})
	flash_light(root, pos + Vector3(0, 1.5, 0), FEL, 4.0, 0.6, 9.0)

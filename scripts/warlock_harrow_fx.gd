class_name WarlockHarrowFx
extends RefCounted
## The look of the Warlock's three directions (WarlockHex): the jungle void spirit's own visual language (Blaine
## 2026-11-06: ethereal green and purple void energy, dark thorned vines, beautiful and evil, Warcraft-bright).
## Corruption is fel green (curses: runes turning round the cursed, motes rising off them), Fear is void violet (a
## terror mark over the frightened, void wisps wheeling round it, the Dread Totem, petals and vines), Drain is pale
## life (bolts, the Thornlash and beams pulling motes back into her hand, overflow hardening into a green glass shield).
## Events (Hero.fx, the caster's game and his puppet on everyone else's alike; WarlockFx.play hands them here):
##   <any of IDS> "cast"                 the hand flares in the direction's colour (void wisps burst out for the fear skills)
##   <curse> "curse" {t: [foe], x: secs}   the curse's mark on the foe (refreshed by the next)
##   w_festering "fester" {t}            the hex bursts
##   w_malediction / w_leechbolt "bolt" {t, n}  a bolt from his hand into the foe (bigger with more curses)
##   <any> "fear" {t, x}                 the terror mark; "root" {t}: thorns hold the foe where its fear ended
##   w_terrify "scream" {t}              a shriek from him to the foe
##   w_effigy "plant" {p, x} / "caw" {p, t} / "gone" {p}
##   w_darkwind "wind" {t}               a void wisp flies the chain, WarlockHex.WIND_GAP a hop
##   w_crowstorm "blink" {p, q} / "storm" {x, r}
##   w_harvest "sweep" {r, t}
##   w_soulfeast "feast" {x} / "end"     beams to every foe in reach, drawn here every frame from the local enemies
##   drain "shield" {x: fraction of his life}  the shield (0: it breaks)
## Lingering things live in h.fxs (keys hx_*) and end themselves on a puppet if their end is lost.

const FEL := Warlock.FEL
const PALE := Warlock.PALE
const DEEP := Warlock.DEEP
const SHADOW := Color(0.42, 0.22, 0.7)
const VIOLET := Color(0.72, 0.45, 1.0)
const LIFE := Color(0.75, 1.0, 0.6)
const TOTEM_GLB := "res://assets/models/warlock/dread_totem.glb"
const CURSE_COLORS := {"w_corruption": Color(0.35, 1.0, 0.25), "w_unending": Color(0.85, 0.95, 0.25),
	"w_festering": Color(0.62, 0.35, 0.95), "w_leeching": Color(0.95, 0.4, 0.45), "w_reckoning": Color(0.92, 1.0, 0.85)}
const DIR_COLOR := {"w_corruption": FEL, "w_malediction": FEL, "w_unending": FEL, "w_festering": FEL, "w_leeching": FEL,
	"w_reckoning": PALE, "w_terrify": VIOLET, "w_effigy": VIOLET, "w_darkwind": VIOLET, "w_crowstorm": VIOLET,
	"w_leechbolt": LIFE, "w_harvest": LIFE, "w_soulfeast": LIFE}

static var _eye_mat: Material
static var _straw_mat: StandardMaterial3D
static var _sack_mat: StandardMaterial3D
static var _wood_mat: StandardMaterial3D
static var _cloth_mat: StandardMaterial3D

static func _free_later(n: Node, t: float) -> void:
	if n.is_inside_tree():
		n.get_tree().create_timer(t, false).timeout.connect(n.queue_free)

static func _snd(h: Hero, nm: String, fallback: String, db := 0.0, pitch := 1.0) -> void:
	SkillFx.snd(h, nm if (Sfx.bank.has(nm) or Sfx.streams.has(nm)) else fallback, db, pitch)

static func _snd_at(nm: String, fallback: String, p: Vector3, db := 0.0) -> void:
	Sfx.play_at(nm if (Sfx.bank.has(nm) or Sfx.streams.has(nm)) else fallback, p, db)

static func play(h: Hero, ev: Dictionary) -> bool:
	var s := str(ev["s"])
	var e := str(ev["e"])
	if not (WarlockHex.has(s) or (s == "drain" and e == "shield")):
		return false
	var root: Node3D = h.game.world.fx_root
	var pos := h.global_position
	var targets: Array = ev.get("t", [])
	match e:
		"cast":
			var c: Color = DIR_COLOR.get(s, FEL)
			var hand := SkillFx.hand(h, false)
			WarlockFx.flash_light(root, hand, c, 1.8, 0.3, 4.0)
			_motes(root, hand, c, 10, 0.4)
			if s in ["w_terrify", "w_effigy", "w_darkwind", "w_crowstorm"]:
				_wisp_burst(root, pos + Vector3(0, 1.6, 0), 2 if s != "w_crowstorm" else 6, 1.0)
			if s == "w_crowstorm":
				_snd(h, "eclipse_storm", "drain_start", -4.0)
			if s == "w_soulfeast" or s == "w_crowstorm":
				var sg := WarlockFx.sigil(root, 2.2)
				sg.global_position = pos + Vector3(0, 0.06, 0)
				sg.create_tween().tween_property(sg, "rotation:y", 2.0, 1.5)
				Fx.later(sg, 1.3, func(): WarlockFx.sigil_fade(sg))
		"curse":
			var dur := float(ev.get("x", 8.0))
			for t in targets:
				_streak(root, SkillFx.hand(h, false), SkillFx.chest_of(t, 1.0), CURSE_COLORS.get(s, FEL), 0.16, 0.05)
				_curse_mark(h, t, s, dur)
			_snd(h, "curse_cast", "blight_cast", -6.0, 1.1)
		"fester":
			for t in targets:
				var at := SkillFx.chest_of(t, 0.9)
				_burst(root, at, CURSE_COLORS["w_festering"], 1.2)
				_snd_at("fester_burst", "blight_burst", at, -4.0)
		"bolt":
			for t in targets:
				var at := SkillFx.chest_of(t, 1.0)
				var big := 1.0 + 0.25 * float(ev.get("n", 0))
				var col: Color = LIFE if s == "w_leechbolt" else FEL
				_bolt(root, SkillFx.hand(h, false), at, col, big, s == "w_leechbolt")
				if s == "w_leechbolt":
					Fx.later(root, 0.2, func(): WarlockFx.siphon(root, at, SkillFx.hand(h, false)))
				_snd(h, "leech_bolt" if s == "w_leechbolt" else "malediction", "blight_cast", -3.0, 1.2 if s == "w_leechbolt" else 0.9)
		"fear":
			for t in targets:
				_terror_mark(h, t, float(ev.get("x", 1.0)))
		"root":
			for t in targets:
				_thorns(root, t)
		"scream":
			for t in targets:
				_scream(root, h.global_position + Vector3(0, 1.5, 0), SkillFx.chest_of(t, 1.2))
			_snd(h, "terrify", "drain_start", -2.0, 0.7)
			SkillFx.shake(h, 0.15)
		"plant":
			var at: Vector3 = ev["p"]
			var n := totem()
			root.add_child(n)
			n.global_position = at
			n.scale = Vector3(1.0, 0.05, 1.0)
			n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_dirt(root, at)
			h.fxs["hx_effigy_%d_%d" % [roundi(at.x * 10.0), roundi(at.z * 10.0)]] = {"n": n, "until": float(ev.get("x", 8.0)) + 0.5}
			_snd_at("totem_rise", "shackles", at, -4.0)
		"caw":
			var at: Vector3 = ev["p"]
			var key := "hx_effigy_%d_%d" % [roundi(at.x * 10.0), roundi(at.z * 10.0)]
			var head := at + Vector3(0, 1.9, 0)
			if h.fxs.has(key) and is_instance_valid(h.fxs[key]["n"]):
				_eyes_flare(h.fxs[key]["n"])
			for t in targets:
				_wisp_dart(root, head, SkillFx.chest_of(t, 1.3))
			WarlockFx.flash_light(root, head, VIOLET, 2.5, 0.4, 6.0)
			_snd_at("totem_wail", "drain_start", head, -1.0)
		"gone":
			var at: Vector3 = ev["p"]
			var key := "hx_effigy_%d_%d" % [roundi(at.x * 10.0), roundi(at.z * 10.0)]
			if h.fxs.has(key):
				_sink(h.fxs[key]["n"])
				h.fxs.erase(key)
		"wind":
			var wisp := wisp_node()
			root.add_child(wisp)
			wisp.global_position = SkillFx.hand(h, false)
			h.fxs["hx_wind_%d" % Time.get_ticks_usec()] = {"wisp": wisp, "t": targets, "i": 0, "hop": 0.0, "from": wisp.global_position, "until": 4.0}
			_snd(h, "void_wisp", "drain_start", -3.0, 1.3)
		"blink":
			var a: Vector3 = ev["p"]
			var b: Vector3 = ev["q"]
			_wisp_burst(root, a + Vector3(0, 1.2, 0), 8, 1.3)
			_puff(root, a + Vector3(0, 1.0, 0))
			Fx.later(root, 0.08, func():
				_wisp_burst(root, b + Vector3(0, 1.2, 0), 6, 0.8)
				_puff(root, b + Vector3(0, 1.0, 0)))
		"storm":
			if h.fxs.has("hx_storm"):
				_end_storm(h)
			var r := float(ev.get("r", WarlockHex.STORM_R))
			var n := Node3D.new()
			root.add_child(n)
			var wisps := []
			var count: int = [10, 14, 18, 24][InfernalFx.tier(h.game)]
			for i in count:
				var c := wisp_node()
				n.add_child(c)
				wisps.append({"n": c, "a": TAU * i / count, "r": r * randf_range(0.35, 1.0), "y": randf_range(0.8, 3.2),
					"sp": randf_range(1.6, 2.6) * (1.0 if i % 3 else -1.0)})
			var petals := InfernalFx.particles(n, n.global_position + Vector3(0, 1.2, 0), {"amount": [24, 36, 48, 64][InfernalFx.tier(h.game)],
				"life": 1.6, "explosive": 0.0, "shape": "ring", "r": r * 0.9, "r_in": r * 0.3, "dir": Vector3.UP, "spread": 40.0,
				"vel": [0.6, 1.6], "gravity": 0.3, "damping": [0.2, 0.5], "angle": true, "spin": 160.0, "scale": [0.6, 1.2],
				"size": 0.14, "turb": 1.2, "add": false, "one_shot": false,
				"colors": [[0.0, Color(VIOLET, 0.0)], [0.15, VIOLET], [0.6, Color(0.35, 0.95, 0.4)], [1.0, Color(DEEP, 0.0)]]})
			var ring := WarlockFx.sigil(root, r)
			var loop = Sfx.start_loop("eclipse_storm", -10.0) if (Sfx.bank.has("eclipse_storm") or Sfx.streams.has("eclipse_storm")) else null
			h.fxs["hx_storm"] = {"n": n, "wisps": wisps, "ring": ring, "until": float(ev.get("x", 5.0)), "loop": loop}
			_snd(h, "eclipse_bloom", "covenant", -2.0)
			SkillFx.shake(h, 0.3)
		"sweep":
			_sweep(h, root, float(ev.get("r", WarlockHex.HARVEST_R)))
			for t in targets:
				var at := SkillFx.chest_of(t, 1.0)
				_burst(root, at, SHADOW, 0.6)
				Fx.later(root, 0.15, func(): WarlockFx.siphon(root, at, h.global_position + Vector3(0, 1.2, 0)))
			_snd(h, "thornlash", "shackles", -3.0, 1.2)
		"feast":
			_end_feast(h)
			var hum = Sfx.start_loop("soul_feast" if (Sfx.bank.has("soul_feast") or Sfx.streams.has("soul_feast")) else "drain_loop", -7.0)
			var sg := WarlockFx.sigil(root, 2.4)
			sg.global_position = pos + Vector3(0, 0.06, 0)
			h.fxs["hx_feast"] = {"beams": {}, "until": float(ev.get("x", 3.0)) + 0.3, "sigil": sg, "hum": hum, "scan": 0.0, "near": []}
			SkillFx.shake(h, 0.2)
		"end":
			_end_feast(h)
		"shield":
			_shield(h, float(ev.get("x", 0.0)))
		_:
			return true
	return true

# ---------------------------------------------------------------- every frame (after the pose)
static func update(h: Hero, delta: float) -> void:
	if h.fxs.is_empty():
		return
	var now := ArrowFx.now()
	for k in h.fxs.keys():
		var key := str(k)
		if not key.begins_with("hx_"):
			continue
		var d: Dictionary = h.fxs[k]
		if key == "hx_shield":
			_update_shield(h, d, now)
			continue
		if key.begins_with("hx_mark_"):
			_update_mark(h, key, d, delta, now)
			continue
		d["until"] = float(d.get("until", 1.0)) - delta
		if key.begins_with("hx_effigy_"):
			var n = d["n"]
			if d["until"] <= 0.0 or not is_instance_valid(n):
				if is_instance_valid(n):
					_sink(n)
				h.fxs.erase(k)
			else:
				_sway(n, now)
		elif key.begins_with("hx_wind_"):
			_update_wind(h, key, d, delta, now)
		elif key == "hx_storm":
			if d["until"] <= 0.0:
				_end_storm(h)
			else:
				_update_storm(h, d, delta, now)
		elif key == "hx_feast":
			if d["until"] <= 0.0:
				_end_feast(h)
			else:
				_update_feast(h, d, delta, now)

static func clear(h: Hero) -> void:
	for k in h.fxs.keys():
		var key := str(k)
		if not key.begins_with("hx_"):
			continue
		var d: Dictionary = h.fxs[k]
		for f in ["n", "wisp", "node", "ring", "sigil", "bubble"]:
			if d.has(f) and d[f] != null and is_instance_valid(d[f]):
				(d[f] as Node).queue_free()
		if d.get("loop") != null and is_instance_valid(d["loop"]):
			d["loop"].stop()
			d["loop"].queue_free()
		if d.get("hum") != null and is_instance_valid(d["hum"]):
			d["hum"].stop()
			d["hum"].queue_free()
		for b in (d.get("beams", {}) as Dictionary).values():
			if is_instance_valid(b):
				b.queue_free()
		h.fxs.erase(k)

# ---------------------------------------------------------------- void wisps and petals
static var _core_mats := {}
## A void wisp: a bright core of fel green or void violet in a soft halo, motes trailing it. "pulse" breathes it.
static func wisp_node(violet := false) -> Node3D:
	var n := Node3D.new()
	n.set_meta("flap", randf() * TAU)
	var col: Color = VIOLET if (violet or randf() < 0.5) else FEL
	var key := col.to_html()
	if not _core_mats.has(key):
		_core_mats[key] = [Mats.glow(col.lightened(0.5), 5.0), InfernalFx.glow_mat(col, 2.2, 2.6, 0.0)]
	var core := MeshInstance3D.new()
	core.mesh = Geo.sph(0.07, 8)
	core.material_override = _core_mats[key][0]
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.name = "core"
	n.add_child(core)
	# a soft camera-facing glow round it (a shared material: InfernalFx's glow, no hard rim)
	var halo := MeshInstance3D.new()
	halo.mesh = InfernalFx.quad()
	halo.scale = Vector3.ONE * 0.6
	halo.extra_cull_margin = 2.0
	halo.material_override = _core_mats[key][1]
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(halo)
	var tr := Fx.aura(n, col, 10, 0.25, 0.045, 0.5, 0.0, 0.06)
	tr.local_coords = false
	return n

## Breathe a wisp (a quick flicker when `beat` is near 1, slow near 0).
static func pulse(c: Node3D, now: float, beat := 1.0) -> void:
	var ph := float(c.get_meta("flap", 0.0))
	var core := c.get_node_or_null("core")
	if core != null:
		core.scale = Vector3.ONE * (1.0 + 0.25 * sin(now * (6.0 + 10.0 * beat) + ph))

## Wisps bursting out of a point and scattering up and away.
static func _wisp_burst(root: Node3D, at: Vector3, n: int, life: float) -> void:
	for i in n:
		var c := wisp_node()
		root.add_child(c)
		c.global_position = at + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.3), randf_range(-0.3, 0.3))
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.1), randf_range(-1.0, 1.0)).normalized()
		var to := c.global_position + dir * randf_range(2.5, 5.0)
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "global_position", to, life).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", Vector3.ONE * 0.1, life * 0.4).set_delay(life * 0.6)
		_free_later(c, life + 0.05)
	_petals(root, at)

## One wisp darting from a point into a foe.
static func _wisp_dart(root: Node3D, from: Vector3, to: Vector3) -> void:
	var c := wisp_node(true)
	root.add_child(c)
	c.global_position = from
	var tw := c.create_tween()
	tw.tween_property(c, "global_position", to, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Fx.later(c, 0.28, func(): _petals(root, to))
	_free_later(c, 0.3)

## Void petals: violet and green, spinning as they fall.
static func _petals(root: Node3D, at: Vector3) -> void:
	InfernalFx.particles(root, at, {"amount": 12, "life": 1.0, "explosive": 1.0, "shape": "sphere", "r": 0.2,
		"dir": Vector3.UP, "spread": 160.0, "vel": [1.0, 2.6], "gravity": -1.5, "damping": [1.5, 2.5], "angle": true, "spin": 220.0,
		"scale": [0.6, 1.1], "size": 0.1, "add": false,
		"colors": [[0.0, VIOLET], [0.5, Color(0.4, 0.95, 0.45)], [1.0, Color(DEEP, 0.0)]]})

static func _update_wind(h: Hero, key: String, d: Dictionary, delta: float, now: float) -> void:
	var c = d["wisp"]      # (the wisp)
	var chain: Array = d["t"]
	if not is_instance_valid(c) or d["until"] <= 0.0 or int(d["i"]) >= chain.size():
		if is_instance_valid(c):
			_wisp_burst(h.game.world.fx_root, c.global_position, 3, 0.6)
			c.queue_free()
		h.fxs.erase(key)
		return
	var e = chain[int(d["i"])]
	if e == null or not is_instance_valid(e):
		d["i"] = int(d["i"]) + 1
		d["hop"] = 0.0
		d["from"] = c.global_position
		return
	d["hop"] = float(d["hop"]) + delta
	var to := SkillFx.chest_of(e, 1.1)
	var u := clampf(float(d["hop"]) / WarlockHex.WIND_GAP, 0.0, 1.0)
	var p: Vector3 = (d["from"] as Vector3).lerp(to, u) + Vector3.UP * sin(u * PI) * 0.6
	if p.distance_to(c.global_position) > 0.01:
		c.look_at(p + (p - c.global_position), Vector3.UP)
	c.global_position = p
	pulse(c, now, 0.8)
	if u >= 1.0:
		_petals(h.game.world.fx_root, to)
		_burst(h.game.world.fx_root, to, SHADOW, 0.5)
		d["i"] = int(d["i"]) + 1
		d["hop"] = 0.0
		d["from"] = to

static func _update_storm(h: Hero, d: Dictionary, delta: float, now: float) -> void:
	var n: Node3D = d["n"]
	if not is_instance_valid(n):
		return
	n.global_position = h.global_position
	if is_instance_valid(d["ring"]):
		(d["ring"] as Node3D).global_position = h.global_position + Vector3(0, 0.06, 0)
		(d["ring"] as Node3D).rotation.y += delta * 0.8
	for cw in d["wisps"]:      # (the storm's wisps)
		var c: Node3D = cw["n"]
		cw["a"] = float(cw["a"]) + float(cw["sp"]) * delta
		var a: float = cw["a"]
		var r: float = float(cw["r"]) * (0.9 + 0.1 * sin(now * 2.0 + a))
		var p := Vector3(cos(a) * r, float(cw["y"]) + sin(now * 3.0 + a * 2.0) * 0.3, sin(a) * r)
		var tangent := Vector3(-sin(a), 0, cos(a)) * signf(float(cw["sp"]))
		c.position = p
		c.look_at(c.global_position + tangent, Vector3.UP)
		pulse(c, now, 0.7)

static func _end_storm(h: Hero) -> void:
	if not h.fxs.has("hx_storm"):
		return
	var d: Dictionary = h.fxs["hx_storm"]
	if is_instance_valid(d["n"]):
		for cw in d["wisps"]:
			if is_instance_valid(cw["n"]):
				var c: Node3D = cw["n"]
				var at := c.global_position
				var root: Node3D = h.game.world.fx_root
				c.reparent(root)
				c.global_position = at
				var tw := c.create_tween()
				tw.tween_property(c, "global_position", at + Vector3(randf_range(-4, 4), randf_range(3, 6), randf_range(-4, 4)), 0.8)
				_free_later(c, 0.85)
		(d["n"] as Node).queue_free()
	if is_instance_valid(d["ring"]):
		WarlockFx.sigil_fade(d["ring"])
	if d.get("loop") != null and is_instance_valid(d["loop"]):
		d["loop"].stop()
		d["loop"].queue_free()
	h.fxs.erase("hx_storm")

# ---------------------------------------------------------------- the Dread Totem
## The Dread Totem: the Meshy idol when its model is in, else built here: a carved pillar of black jungle wood with a
## void mask and two burning fel eyes, black thorned vines spiralling up it, glowing green flowers and roots at its foot.
static func totem() -> Node3D:
	var n := Node3D.new()
	if ResourceLoader.exists(TOTEM_GLB):
		var m = ResCache.inst(TOTEM_GLB)
		if m != null:
			n.add_child(m)
			n.set_meta("eyes", [])
			_totem_lights(n)
			return n
	if _wood_mat == null:
		_wood_mat = Mats.flat(Color(0.1, 0.07, 0.09))
		_sack_mat = Mats.flat(Color(0.22, 0.12, 0.3))
		_straw_mat = Mats.flat(Color(0.03, 0.05, 0.03))
		_cloth_mat = Mats.flat(Color(0.05, 0.09, 0.05))
	var pillar := MeshInstance3D.new()
	pillar.mesh = Geo.cyl(0.22, 0.32, 2.0, 8)
	pillar.position = Vector3(0, 1.0, 0)
	pillar.material_override = _wood_mat
	n.add_child(pillar)
	var mask := MeshInstance3D.new()
	mask.mesh = Geo.sph(0.3, 12)
	mask.position = Vector3(0, 2.15, -0.05)
	mask.scale = Vector3(1.0, 1.25, 0.7)
	mask.material_override = _sack_mat
	n.add_child(mask)
	for sx in [-1, 1]:
		var horn := MeshInstance3D.new()
		horn.mesh = Geo.cone(0.06, 0.55, 6)
		horn.position = Vector3(0.22 * sx, 2.5, 0)
		horn.rotation.z = -0.5 * sx
		horn.material_override = _wood_mat
		n.add_child(horn)
	var eyes := []
	for sx in [-1, 1]:
		var eye := MeshInstance3D.new()
		eye.mesh = Geo.sph(0.05, 6)
		eye.position = Vector3(0.1 * sx, 2.2, -0.26)
		var em := Mats.glow_unique(FEL, 3.0)
		eye.material_override = em
		n.add_child(eye)
		eyes.append(em)
	# vines: thorned segments spiralling up the pillar
	for k in 22:
		var t := k / 22.0
		var a := t * TAU * 2.2
		var seg := MeshInstance3D.new()
		seg.mesh = Geo.cyl(0.035, 0.035, 0.22, 5)
		seg.position = Vector3(cos(a) * 0.3, 0.15 + t * 1.85, sin(a) * 0.3)
		seg.rotation = Vector3(0.9, -a, 0)
		seg.material_override = _straw_mat
		n.add_child(seg)
		if k % 3 == 0:
			var thorn := MeshInstance3D.new()
			thorn.mesh = Geo.cone(0.025, 0.1, 4)
			thorn.position = seg.position * 1.12
			thorn.rotation = Vector3(0, -a, PI * 0.5)
			thorn.material_override = _straw_mat
			n.add_child(thorn)
		if k % 5 == 2:
			var fl := MeshInstance3D.new()
			fl.mesh = Geo.sph(0.06, 6)
			fl.position = seg.position * 1.15
			fl.material_override = Mats.glow(Color(0.45, 1.0, 0.5), 2.5)
			n.add_child(fl)
	for k in 6:
		var a := TAU * k / 6.0
		var root_n := MeshInstance3D.new()
		root_n.mesh = Geo.cone(0.08, 0.7, 5)
		root_n.position = Vector3(cos(a) * 0.45, 0.12, sin(a) * 0.45)
		root_n.rotation = Vector3(sin(a) * 1.2, 0, -cos(a) * 1.2)
		root_n.material_override = _cloth_mat
		n.add_child(root_n)
	for k in 3:
		var w := wisp_node(true)
		w.position = Vector3(0, 2.3, 0)
		w.name = "perched_%d" % k
		w.set_meta("orbit", TAU * k / 3.0)
		n.add_child(w)
	n.set_meta("eyes", eyes)
	_totem_lights(n)
	return n

static func _totem_lights(n: Node3D) -> void:
	var l := OmniLight3D.new()
	l.light_color = FEL
	l.light_energy = 0.8
	l.omni_range = 3.5
	l.position = Vector3(0, 2.0, -0.4)
	n.add_child(l)
	n.set_meta("light", l)

static func _eyes_flare(n: Node3D) -> void:
	for em in n.get_meta("eyes", []):
		InfernalFx.tween_param(n, em, "energy", 9.0, 3.0, 0.5)
	var l = n.get_meta("light", null)
	if l != null and is_instance_valid(l):
		var tw := (l as Node).create_tween()
		tw.tween_property(l, "light_energy", 3.0, 0.08)
		tw.tween_property(l, "light_energy", 0.8, 0.5)
	for c in n.get_children():
		if str(c.name).begins_with("perched_"):
			c.visible = false
			Fx.later(n, 1.2, func(): if is_instance_valid(c): c.visible = true)

static func _sway(n: Node3D, now: float) -> void:
	for c in n.get_children():
		if str(c.name).begins_with("perched_"):
			var a: float = float(c.get_meta("orbit", 0.0)) + now * 1.6
			c.position = Vector3(cos(a) * 0.75, 2.2 + sin(now * 2.0 + a) * 0.25, sin(a) * 0.75)
			pulse(c, now, 0.3)

static func _sink(n) -> void:
	if n == null or not is_instance_valid(n):
		return
	var tw := (n as Node3D).create_tween()
	tw.tween_property(n, "scale", Vector3(1.0, 0.05, 1.0), 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(n.queue_free)
	if n.is_inside_tree():
		_wisp_burst(n.get_parent(), (n as Node3D).global_position + Vector3(0, 1.6, 0), 3, 0.9)

static func _dirt(root: Node3D, at: Vector3) -> void:
	InfernalFx.particles(root, at + Vector3(0, 0.1, 0), {"amount": 16, "life": 0.7, "explosive": 1.0, "shape": "sphere", "r": 0.3,
		"dir": Vector3.UP, "spread": 50.0, "vel": [2.0, 4.0], "gravity": -9.0, "scale": [0.6, 1.2], "size": 0.07, "add": false,
		"colors": [[0.0, Color(0.2, 0.15, 0.1)], [1.0, Color(0.12, 0.1, 0.07, 0.0)]]})

# ---------------------------------------------------------------- curses and fear marks on a foe
## A curse on a foe: a ring of its colour turning round the waist, motes rising off it. One node per foe holds every
## curse he has on it (a ring each), each fading when its time is up.
static func _mark(h: Hero, e) -> Dictionary:
	var key := "hx_mark_%d" % e.get_instance_id()
	var m: Dictionary = h.fxs.get(key, {})
	if m.is_empty() or not is_instance_valid(m["node"]):
		var n := Node3D.new()
		e.add_child(n)
		n.position = Vector3(0, float(e.get("height")) * 0.9, 0)
		var motes := Fx.aura(n, FEL, 10, 0.5, 0.05, 1.0, 0.4, float(e.get("radius")) + 0.15)
		motes.emitting = false
		m = {"node": n, "e": e, "rings": {}, "motes": motes, "terror": null, "terror_until": 0.0}
		h.fxs[key] = m
	return m

static func _curse_mark(h: Hero, e, id: String, dur: float) -> void:
	if e == null or not is_instance_valid(e):
		return
	var m := _mark(h, e)
	var rings: Dictionary = m["rings"]
	var now := ArrowFx.now()
	if not rings.has(id):
		var ring := MeshInstance3D.new()
		var r: float = float(e.get("radius")) + 0.3 + rings.size() * 0.12
		ring.mesh = Geo.torus(r - 0.03, r, 32, 4)
		var mat := Mats.glow_unique(CURSE_COLORS.get(id, FEL), 1.6)
		ring.material_override = mat
		ring.position.y = -0.3 + rings.size() * 0.22
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(m["node"] as Node3D).add_child(ring)
		# runes on the ring
		for k in 6:
			var rune := MeshInstance3D.new()
			rune.mesh = Geo.box(0.05, 0.1, 0.02)
			var a := TAU * k / 6.0
			rune.position = Vector3(cos(a) * r, 0, sin(a) * r)
			rune.rotation.y = -a
			rune.material_override = mat
			ring.add_child(rune)
		rings[id] = {"ring": ring, "until": now + dur, "mat": mat, "spin": 1.5 if rings.size() % 2 == 0 else -1.2}
		ring.scale = Vector3(2.0, 0.3, 2.0)
		ring.create_tween().tween_property(ring, "scale", Vector3(1.0, 0.3, 1.0), 0.25).set_ease(Tween.EASE_OUT)
	else:
		rings[id]["until"] = now + dur

static func _terror_mark(h: Hero, e, dur: float) -> void:
	if e == null or not is_instance_valid(e):
		return
	var m := _mark(h, e)
	var now := ArrowFx.now()
	m["terror_until"] = maxf(float(m["terror_until"]), now + dur)
	if m["terror"] == null or not is_instance_valid(m["terror"]):
		var t := Node3D.new()
		(m["node"] as Node3D).add_child(t)
		t.position = Vector3(0, float(e.get("height")) * 1.3 + 0.5, 0)
		var skull := InfernalFx.glow(t, t.global_position, 0.8, InfernalFx.glow_mat(VIOLET, 2.4, 2.2, 0.3))
		skull.reparent(t)
		skull.position = Vector3.ZERO
		for i in 3:
			var c := wisp_node()
			c.scale = Vector3.ONE * 0.6
			t.add_child(c)
			c.set_meta("orbit", TAU * i / 3.0)
		m["terror"] = t
		t.scale = Vector3.ONE * 0.2
		t.create_tween().tween_property(t, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_petals(h.game.world.fx_root, t.global_position)

static func _update_mark(h: Hero, key: String, m: Dictionary, delta: float, now: float) -> void:
	var e = m["e"]
	var n = m["node"]
	if e == null or not is_instance_valid(e) or not is_instance_valid(n) or e.dead:
		if is_instance_valid(n):
			(n as Node).queue_free()
		h.fxs.erase(key)
		return
	var rings: Dictionary = m["rings"]
	for id in rings.keys():
		var r: Dictionary = rings[id]
		var ring = r["ring"]
		if not is_instance_valid(ring):
			rings.erase(id)
			continue
		(ring as Node3D).rotation.y += delta * float(r["spin"])
		var left := float(r["until"]) - now
		if left <= 0.0:
			(ring as Node).queue_free()
			rings.erase(id)
		elif left < 0.5:
			(r["mat"] as ShaderMaterial).set_shader_parameter("alpha_mul", left / 0.5)
	if is_instance_valid(m["motes"]):
		(m["motes"] as GPUParticles3D).emitting = not rings.is_empty()
	var t = m["terror"]
	if t != null and is_instance_valid(t):
		if float(m["terror_until"]) <= now:
			(t as Node).queue_free()
			m["terror"] = null
		else:
			(t as Node3D).position.y += sin(now * 6.0) * 0.004
			for c in (t as Node3D).get_children():
				if c.has_meta("orbit"):
					var a: float = float(c.get_meta("orbit")) + now * 4.0
					c.position = Vector3(cos(a) * 0.55, sin(now * 5.0 + a) * 0.1, sin(a) * 0.55)
					c.look_at(c.global_position + Vector3(-sin(a), 0, cos(a)), Vector3.UP)
					pulse(c, now, 0.9)
	if rings.is_empty() and (t == null or not is_instance_valid(t)):
		(n as Node).queue_free()
		h.fxs.erase(key)

static func _thorns(root: Node3D, e) -> void:
	if e == null or not is_instance_valid(e):
		return
	var at: Vector3 = e.global_position
	for i in 6:
		var a := TAU * i / 6.0 + randf() * 0.4
		var sp := MeshInstance3D.new()
		sp.mesh = Geo.cone(0.06, 0.9, 5)
		sp.material_override = Mats.glow(SHADOW, 0.6)
		root.add_child(sp)
		sp.global_position = at + Vector3(cos(a), 0, sin(a)) * (float(e.get("radius")) + 0.15)
		sp.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
		sp.scale = Vector3(1, 0.05, 1)
		var tw := sp.create_tween()
		tw.tween_property(sp, "scale", Vector3.ONE, 0.12)
		tw.tween_interval(0.8)
		tw.tween_property(sp, "scale", Vector3(1, 0.05, 1), 0.2)
		tw.tween_callback(sp.queue_free)

# ---------------------------------------------------------------- bolts, bursts, the scream, the sweep
static func _streak(root: Node3D, from: Vector3, to: Vector3, col: Color, life: float, w: float) -> void:
	var b := WarlockFx.beam(root, w)
	var t0 := ArrowFx.now()
	b.draw(from, to, t0)
	var tw := b.create_tween()
	tw.tween_method(func(t: float): if is_instance_valid(b): b.draw(from.lerp(to, t), to, t0 + t), 0.0, 1.0, life)
	tw.tween_callback(b.queue_free)
	Fx.later(root, life, func(): _burst(root, to, col, 0.5))

static func _bolt(root: Node3D, from: Vector3, to: Vector3, col: Color, big: float, life_back: bool) -> void:
	var n := WarlockFx.bolt_node(root)
	n.global_position = from
	n.scale = Vector3.ONE * (0.7 * big)
	var tw := n.create_tween()
	tw.tween_property(n, "global_position", to, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_burst(root, to, col, 0.7 * big)
		if not life_back:
			WarlockFx.fel_ring(root, to - Vector3(0, 1.0, 0), 0.6 * big, 6, 0.6, 1.1, 0.45)
		n.queue_free())

static func _burst(root: Node3D, at: Vector3, col: Color, size: float) -> void:
	var g := InfernalFx.glow(root, at, 0.9 * size, InfernalFx.glow_mat(col, 2.4, 2.4, 0.5))
	var tw := g.create_tween().set_parallel(true)
	tw.tween_property(g, "scale", Vector3.ONE * 2.0, 0.3).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(g, g.material_override as ShaderMaterial, "alpha", 1.0, 0.0, 0.3)
	_free_later(g, 0.35)
	_motes(root, at, col, int(10 * size) + 4, 0.6)
	WarlockFx.flash_light(root, at, col, 1.6 * size, 0.3, 4.0 * size)

static func _motes(root: Node3D, at: Vector3, col: Color, n: int, life: float) -> void:
	InfernalFx.particles(root, at, {"amount": maxi(n, 2), "life": life, "explosive": 1.0, "shape": "sphere", "r": 0.12,
		"dir": Vector3.UP, "spread": 180.0, "vel": [1.0, 2.6], "damping": [2.0, 3.0], "scale": [0.5, 1.0], "size": 0.06,
		"colors": [[0.0, PALE], [0.4, col], [1.0, Color(col, 0.0)]]})

static func _puff(root: Node3D, at: Vector3) -> void:
	InfernalFx.particles(root, at, {"amount": 14, "life": 0.9, "explosive": 0.9, "shape": "sphere", "r": 0.4,
		"dir": Vector3.UP, "spread": 120.0, "vel": [0.5, 1.5], "damping": [1.0, 2.0], "scale": [0.8, 1.5], "size": 0.6,
		"grow": [0.6, 1.6], "angle": true, "spin": 30.0, "add": false,
		"colors": [[0.0, Color(0.05, 0.03, 0.08, 0.0)], [0.15, Color(0.06, 0.03, 0.1, 0.75)], [1.0, Color(0.02, 0.01, 0.04, 0.0)]]})

## Terrify: a shriek of shadow tearing from him to the foe, a pale face in it.
static func _scream(root: Node3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var n := maxi(3, int(d.length() / 1.2))
	for i in n:
		var u := float(i + 1) / (n + 1)
		var at := from.lerp(to, u)
		Fx.later(root, u * 0.15, func():
			var g := InfernalFx.glow(root, at, 0.5 + u * 0.8, InfernalFx.glow_mat(VIOLET, 1.8, 2.0, 0.2))
			var tw := g.create_tween().set_parallel(true)
			tw.tween_property(g, "scale", Vector3.ONE * 2.2, 0.35)
			InfernalFx.tween_param(g, g.material_override as ShaderMaterial, "alpha", 0.8, 0.0, 0.35)
			_free_later(g, 0.4))
	Fx.later(root, 0.16, func():
		_puff(root, to)
		WarlockFx.flash_light(root, to, VIOLET, 2.6, 0.4, 5.0))

## Bountiful Harvest: a scythe of shadow swept once round him, a dark arc trailing it.
static func _sweep(h: Hero, root: Node3D, r: float) -> void:
	var pivot := Node3D.new()
	root.add_child(pivot)
	pivot.global_position = h.global_position + Vector3(0, 1.0, 0)
	# the lash: a curling thorned vine reaching out to the edge, glowing veins along it
	var vine_m := Mats.glow_unique(Color(0.12, 0.3, 0.12), 1.4)
	var vein_m := Mats.glow_unique(Color(0.55, 1.0, 0.5), 3.0)
	var n := 16
	for k in n:
		var t := (k + 0.5) / n
		var d := r * (0.15 + 0.85 * t)
		var bend := sin(t * PI) * 0.6
		var seg := MeshInstance3D.new()
		seg.mesh = Geo.cyl(0.11 * (1.1 - t), 0.11 * (1.1 - t), r / n * 1.3, 5)
		seg.position = Vector3(sin(bend) * d * 0.3, sin(t * PI * 2.0) * 0.15, -d)
		seg.rotation = Vector3(PI * 0.5, bend, 0)
		seg.material_override = vine_m if k % 4 != 1 else vein_m
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(seg)
		if k % 2 == 0:
			var thorn := MeshInstance3D.new()
			thorn.mesh = Geo.cone(0.03, 0.14, 4)
			thorn.position = seg.position + Vector3(0, 0.08, 0)
			thorn.material_override = vine_m
			pivot.add_child(thorn)
	var tw := pivot.create_tween()
	tw.tween_property(pivot, "rotation:y", -TAU, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(pivot.queue_free)
	InfernalFx.particles(root, h.global_position + Vector3(0, 0.9, 0), {"amount": 40, "life": 0.6, "explosive": 0.9,
		"shape": "ring", "r": r * 0.85, "r_in": r * 0.5, "dir": Vector3.UP, "spread": 20.0, "vel": [0.3, 0.8],
		"damping": [1.0, 2.0], "scale": [0.6, 1.2], "size": 0.5, "grow": [1.0, 0.3], "angle": true, "add": false,
		"colors": [[0.0, Color(0.06, 0.03, 0.1, 0.0)], [0.2, Color(0.1, 0.05, 0.16, 0.6)], [1.0, Color(0.02, 0.01, 0.04, 0.0)]]})
	HolyFx.shockwave(root, h.game, h.global_position, r, 0.35, 0.02)
	WarlockFx.fel_ring(root, h.global_position, r * 0.8, 14, 0.5, 0.9, 0.45, 0.3)
	_petals(root, h.global_position + Vector3(0, 1.0, 0))
	SkillFx.shake(h, 0.18)

# ---------------------------------------------------------------- Soul Feast and the shield
static func _update_feast(h: Hero, d: Dictionary, delta: float, now: float) -> void:
	d["scan"] = float(d["scan"]) - delta
	if d["scan"] <= 0.0:
		d["scan"] = 0.2
		d["near"] = h.game.enemies_near(h.global_position, WarlockHex.FEAST_R).filter(func(e): return not e.get("pvp_obj") and not e.get("pvp_hidden")).slice(0, 8)
	var beams: Dictionary = d["beams"]
	var hand := SkillFx.hand(h, false)
	var live := {}
	for e in d["near"]:
		if not is_instance_valid(e) or e.dead:
			continue
		var k: int = e.get_instance_id()
		live[k] = true
		if not beams.has(k) or not is_instance_valid(beams[k]):
			var b := WarlockFx.beam(h.game.world.fx_root, 0.14)
			b.arc = 0.25
			beams[k] = b
			WarlockFx.latch(h.game.world.fx_root, SkillFx.chest_of(e, 1.0))
		(beams[k] as WarlockFx.Beam).draw(hand, SkillFx.chest_of(e, 1.0), now)
	for k in beams.keys():
		if not live.has(k):
			if is_instance_valid(beams[k]):
				beams[k].queue_free()
			beams.erase(k)
	if is_instance_valid(d["sigil"]):
		(d["sigil"] as Node3D).global_position = h.global_position + Vector3(0, 0.06, 0)
		(d["sigil"] as Node3D).rotation.y += delta * 1.5

static func _end_feast(h: Hero) -> void:
	if not h.fxs.has("hx_feast"):
		return
	var d: Dictionary = h.fxs["hx_feast"]
	for b in (d["beams"] as Dictionary).values():
		if is_instance_valid(b):
			b.queue_free()
	if is_instance_valid(d["sigil"]):
		WarlockFx.sigil_fade(d["sigil"])
	if d["hum"] != null and is_instance_valid(d["hum"]):
		d["hum"].stop()
		d["hum"].queue_free()
	if h.game.world != null:
		WarlockFx.release(h.game.world.fx_root, SkillFx.hand(h, false))
	h.fxs.erase("hx_feast")

## The shield: a bubble of green glass round him, as thick as the shield is big; it shatters at 0.
static func _shield(h: Hero, frac: float) -> void:
	var d: Dictionary = h.fxs.get("hx_shield", {})
	if frac <= 0.0:
		if not d.is_empty():
			var b = d["bubble"]
			if is_instance_valid(b):
				var at: Vector3 = (b as Node3D).global_position
				InfernalFx.particles(h.game.world.fx_root, at, {"amount": 24, "life": 0.7, "explosive": 1.0, "shape": "sphere",
					"r": 0.9, "dir": Vector3.UP, "spread": 180.0, "vel": [2.0, 4.0], "gravity": -8.0, "scale": [0.5, 1.0], "size": 0.07,
					"colors": [[0.0, PALE], [1.0, Color(FEL, 0.0)]]})
				(b as Node).queue_free()
			_snd(h, "shield_break", "ice_shatter", -6.0, 1.3)
			h.fxs.erase("hx_shield")
		return
	if d.is_empty() or not is_instance_valid(d["bubble"]):
		var bub := MeshInstance3D.new()
		bub.mesh = Geo.sph(1.0, 20)
		var m := Mats.glow_unique(FEL, 0.8, 0.0, 1.0)
		bub.material_override = m
		bub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(bub)
		bub.position = Vector3(0, 1.0, 0)
		bub.scale = Vector3(0.95, 1.15, 0.95)
		d = {"bubble": bub, "mat": m, "frac": 0.0}
		h.fxs["hx_shield"] = d
		_snd(h, "shield_up", "covenant", -10.0, 1.4)
	d["frac"] = frac

static func _update_shield(h: Hero, d: Dictionary, now: float) -> void:
	var b = d["bubble"]
	if not is_instance_valid(b):
		h.fxs.erase("hx_shield")
		return
	var a := clampf(0.25 + float(d["frac"]) * 2.0, 0.25, 1.0) * (0.85 + 0.15 * sin(now * 4.0))
	(d["mat"] as ShaderMaterial).set_shader_parameter("alpha_mul", a)

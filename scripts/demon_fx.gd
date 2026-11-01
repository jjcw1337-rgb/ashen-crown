class_name DemonFx
extends RefCounted
## Visual effects for the Demon's skills (DemonSkills): lava, cracks, boulders and meteors. Everything one-shot is
## parented to the zone's FX node; what lingers (the lava on the ground, a boulder or meteor in the air, the foe in
## his grip, the wrath's white heat) is state in h.fxs that `update` moves every frame, on his own game and on his
## puppet on every partner's. The colours: his ember orange (EMBER), the white-yellow of molten rock (HOT), the
## near-black of cooled crust (CRUST).
##
## `play` is the skills' fx events (SkillFx: the same on the caster and on his puppet):
##  Molten Fists: "impact" {y: yaw, r: reach, t: the foes set alight} (the ground cracks open in a wedge)
##  Infernal Charge: "start" {d} (embers off his hooves, h.fxs["icharge"]), "hit" {p, d}, "trail" {ps: the lava patches,
##    x: how long they burn}, "end"
##  Cataclysm Slam: "impact" {p: the blow, y, ps: every fissure point, n: fissures, x: hit any} (the ring and the
##    fissures racing out), "erupt" {ps: this wave's bursts, n: the wave}
##  Brimstone Hurl: "throw" {p: from the hand, ps: where each lands, x: the flight} (the boulders, h.fxs["boulders"],
##    flown by update), "splash" {p, x: the pool's life, t: set alight}
##  Hellgrip: "grab" {t: [the victim], x: the hold} (the victim lifted off the ground, h.fxs["grip"], until "smash"
##    or x + a slack on a partner's game), "smash" {p, t, x: held anyone}
##  Wrath of the Pit: "cast" (the white heat rising in his cracks, h.fxs["wrath"]), "roar", "stomp" {x: the rain's
##    length}, "meteor" {p: where it lands, n: which, x: its fall} (h.fxs["meteors"], flown by update), "end" {x}

const EMBER := Color(1.0, 0.42, 0.06)
const HOT := Color(1.0, 0.75, 0.3)
const CRUST := Color(0.06, 0.04, 0.035)
const BLOOD := Color(0.85, 0.04, 0.08)
const SOUL := Color(0.62, 0.42, 1.0)
const GRIP_SLACK := 1.5          # a partner's held foe is let go this long after the hold if the smash is lost
const WRATH_SLACK := 1.5

static var _lava_shader: Shader
static var _disc: ArrayMesh
static var _strip: ArrayMesh
static var _rock: Mesh

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var pos := h.global_position
	match [str(ev["s"]), str(ev["e"])]:
		["fists", "cast"], ["icharge", "cast"], ["cslam", "cast"], ["hurl", "cast"], ["grip", "cast"]:
			pass
		["fists", "impact"]:
			var yaw: float = float(ev["y"])
			var reach: float = float(ev.get("r", DemonSkills.FISTS_R))
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var at := pos + fwd * 0.6
			at.y = h.game.world.height_at(at.x, at.z)
			var d := lava_decal(root, at + fwd * reach * 0.42, reach * 0.55, 1.6, 0.25, yaw, deg_to_rad(DemonSkills.FISTS_HALF + 8.0))
			d.rotation.y = yaw
			Fx.burst(root, pos + Vector3(0, 0.3, 0) + fwd * 1.2, EMBER, 28, 5.0, 0.07, 0.5, true, -4.0, 50.0, fwd + Vector3(0, 0.5, 0))
			Fx.burst(root, pos + Vector3(0, 0.15, 0) + fwd * 1.0, Color(0.35, 0.3, 0.25, 0.6), 14, 2.5, 0.3, 0.5, false, -2.0, 70.0, fwd + Vector3(0, 0.6, 0))
			Fx.flash(root, pos + Vector3(0, 0.6, 0) + fwd * 1.4, EMBER, 2.4, 0.25, 5.0)
			for e in ev.get("t", []):
				ignite(root, e)
			SkillFx.snd(h, "hellclaw", -2.0, 0.9)
			SkillFx.snd(h, "slam", -9.0, 1.2)
			SkillFx.shake(h, 0.2 if not (ev.get("t", []) as Array).is_empty() else 0.1)
		["icharge", "start"]:
			_end_charge(h)
			var au := Fx.aura(h.rig, EMBER, 40, 1.8, 0.1, 0.5, 1.2, 0.45, 60.0, Vector3(0, 0.3, 0.3))
			h.fxs["icharge"] = {"node": au, "until": 1.6}
			Fx.flash(root, pos + Vector3(0, 1.4, 0), EMBER, 2.0, 0.3, 5.0)
			SkillFx.snd(h, "charge_dash", -2.0, 0.85)
			SkillFx.snd(h, "growl", -8.0, 0.8)
		["icharge", "hit"]:
			var p: Vector3 = ev["p"]
			Fx.sparks(root, p, HOT)
			Fx.burst(root, p, EMBER, 16, 4.0, 0.08, 0.4, true, -3.0, 60.0, (ev.get("d", Vector3.FORWARD) as Vector3) + Vector3(0, 0.6, 0))
			Sfx.play_at("charge_impact", p, -4.0, 0.9)
			SkillFx.shake(h, 0.12)
		["icharge", "trail"]:
			var ps: PackedVector3Array = ev["ps"]
			for p in ps:
				lava_decal(root, p, DemonSkills.TRAIL_R * 1.15, float(ev.get("x", DemonSkills.TRAIL_DUR)), 0.7)
				Fx.burst(root, p + Vector3(0, 0.1, 0), EMBER, 8, 2.0, 0.07, 0.5, true, -2.0, 50.0)
			if h.puppet:
				Sfx.play_at("fire_erupt", pos, -16.0, 1.3)
			else:
				Sfx.play("fire_erupt", -14.0, 1.3)
		["icharge", "end"]:
			_end_charge(h)
		["cslam", "impact"]:
			var at: Vector3 = ev["p"]
			Fx.holy_slam(root, at, DemonSkills.SLAM_R)
			lava_decal(root, at, DemonSkills.SLAM_R * 1.05, 3.5, 0.4)
			Fx.burst(root, at + Vector3(0, 0.2, 0), EMBER, 40, 5.5, 0.08, 0.6, true, -4.0, 70.0)
			Fx.burst(root, at + Vector3(0, 0.2, 0), Color(0.3, 0.25, 0.2, 0.7), 24, 3.0, 0.35, 0.7, false, -2.0, 60.0)
			Fx.flash(root, at + Vector3(0, 0.8, 0), EMBER, 3.0, 0.3, 7.0)
			# the fissures: strips of cracked, glowing rock racing out from the blow along each line
			var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
			var n: int = int(ev.get("n", 1))
			var per: int = ps.size() / maxi(n, 1)
			var life := DemonSkills.FISSURE_DELAY + per * DemonSkills.FISSURE_WAVE + 2.2
			for i in n:
				var prev := at
				for k in per:
					var q: Vector3 = ps[i * per + k]
					var seg := lava_strip(root, prev, q, 0.45, life, 0.3)
					var delay := 0.04 * k
					seg.scale = Vector3(1, 1, 0.01)
					var tw := seg.create_tween()
					tw.tween_property(seg, "scale", Vector3(1, 1, 1), 0.12).set_delay(delay)
					prev = q
			SkillFx.snd(h, "slam", 0.0, 0.8)
			SkillFx.snd(h, "fire_erupt", -8.0, 0.7)
			SkillFx.duck(h, -4.0, 0.8)
			SkillFx.shake(h, 0.45)
		["cslam", "erupt"]:
			var ps: PackedVector3Array = ev["ps"]
			for p in ps:
				eruption(root, p, DemonSkills.FISSURE_R)
			if not ps.is_empty():
				Sfx.play_at("boom", ps[0], -7.0, 1.1 + 0.08 * (int(ev.get("n", 0)) % 3))
			SkillFx.shake(h, 0.12)
		["hurl", "throw"]:
			var from: Vector3 = ev["p"]
			var ps: PackedVector3Array = ev["ps"]
			var flight: float = float(ev.get("x", DemonSkills.HURL_FLIGHT))
			var bs: Array = h.fxs.get("boulders", [])
			for to in ps:
				var b := boulder(root, 0.38)
				b.global_position = from
				bs.append({"node": b, "from": from, "to": to, "t": 0.0, "dur": flight})
			h.fxs["boulders"] = bs
			Fx.burst(root, from, EMBER, 18, 3.0, 0.08, 0.5, true, -3.0, 90.0)
			SkillFx.snd(h, "cleave_swing", -3.0, 0.7)
			SkillFx.snd(h, "fireball", -6.0, 0.8)
		["hurl", "splash"]:
			var at: Vector3 = ev["p"]
			splash(root, at, DemonSkills.HURL_R)
			lava_decal(root, at, DemonSkills.POOL_R, float(ev.get("x", DemonSkills.POOL_DUR)), 1.0)
			for e in ev.get("t", []):
				ignite(root, e)
			Sfx.play_at("boom", at, -3.0, 0.9)
			Sfx.play_at("fire_erupt", at, -6.0, 0.9)
			SkillFx.shake(h, 0.3)
		["grip", "grab"]:
			_end_grip(h, false)
			var vs: Array = ev.get("t", [])
			if not vs.is_empty():
				var v = vs[0]
				h.fxs["grip"] = {"victim": v, "lift": 0.0, "until": float(ev.get("x", 0.8)) + GRIP_SLACK, "t": 0.0}
				Fx.sparks(root, SkillFx.chest_of(v, 0.6), EMBER)
				var fl := Props.fire(v, Vector3(0, 0.5 * float(v.get("height")), 0), 0.3, EMBER, false, false, false)
				fl.name = "GripFire"
			SkillFx.snd(h, "growl", -4.0, 0.75)
		["grip", "smash"]:
			var at: Vector3 = ev["p"]
			var held: bool = bool(ev.get("x", false))
			_end_grip(h, true)
			lava_decal(root, at, DemonSkills.GRIP_SHOCK_R * 0.85, 2.5, 0.5)
			Fx.ring(root, at + Vector3(0, 0.05, 0), DemonSkills.GRIP_SHOCK_R, EMBER, 0.4, 0.3)
			Fx.burst(root, at + Vector3(0, 0.3, 0), EMBER, 34 if held else 14, 5.0, 0.08, 0.55, true, -4.0, 80.0)
			Fx.burst(root, at + Vector3(0, 0.2, 0), Color(0.3, 0.25, 0.2, 0.7), 18, 3.0, 0.35, 0.6, false, -2.0, 70.0)
			Fx.flash(root, at + Vector3(0, 0.8, 0), HOT, 3.0 if held else 1.5, 0.3, 6.0)
			for e in ev.get("t", []):
				ignite(root, e)
			Sfx.play_at("slam", at, -1.0 if held else -6.0, 0.9)
			if held:
				Sfx.play_at("hellclaw", at, -6.0, 0.8)
			SkillFx.shake(h, 0.4 if held else 0.15)
		["wrath", "cast"]:
			_end_wrath(h, false)
			h.fxs["wrath"] = {"k": 0.0, "want": 0.0, "until": 4.0, "rain": 0.0}
			var l := OmniLight3D.new()
			l.light_color = HOT
			l.light_energy = 0.0
			l.omni_range = 7.0
			l.shadow_enabled = false
			l.position = Vector3(0, 1.6, 0)
			h.rig.add_child(l)
			h.fxs["wrath"]["light"] = l
			SkillFx.snd(h, "fire_erupt", -4.0, 0.7)
		["wrath", "roar"]:
			Fx.ring(root, pos + Vector3(0, 0.05, 0), DemonSkills.ROAR_R, EMBER, 0.5, 0.4)
			Fx.burst(root, pos + Vector3(0, 1.6, 0), HOT, 40, 7.0, 0.1, 0.6, true, -1.0, 180.0)
			Fx.flash(root, pos + Vector3(0, 1.8, 0), HOT, 4.0, 0.5, 9.0)
			if h.fxs.has("wrath"):
				h.fxs["wrath"]["want"] = 1.0
			SkillFx.snd(h, "roar", 0.0, 0.8)
			SkillFx.duck(h, -8.0, 1.2)
			SkillFx.shake(h, 0.5)
			SkillFx.hitstop(h, 0.06)
		["wrath", "stomp"]:
			var rain: float = float(ev.get("x", DemonSkills.WRATH_DUR))
			Fx.holy_slam(root, pos, 4.0)
			lava_decal(root, pos, 4.2, rain + 1.5, 0.55)
			Fx.burst(root, pos + Vector3(0, 0.2, 0), EMBER, 50, 6.0, 0.09, 0.7, true, -4.0, 75.0)
			Fx.flash(root, pos + Vector3(0, 0.8, 0), EMBER, 3.0, 0.35, 8.0)
			if h.fxs.has("wrath"):
				h.fxs["wrath"]["until"] = rain + WRATH_SLACK
				h.fxs["wrath"]["rain"] = rain
			SkillFx.snd(h, "slam", -1.0, 0.75)
			SkillFx.snd(h, "boom", -6.0, 0.8)
			SkillFx.shake(h, 0.4)
		["wrath", "meteor"]:
			var at: Vector3 = ev["p"]
			var fall: float = float(ev.get("x", DemonSkills.WRATH_FALL))
			var k: int = int(ev.get("n", 0))
			var m := boulder(root, 0.42)
			var from := at + Vector3(cos(k * 2.4) * 3.0, 15.0, sin(k * 2.4) * 3.0 + 2.0)
			m.global_position = from
			var ms: Array = h.fxs.get("meteors", [])
			ms.append({"node": m, "from": from, "to": at, "t": 0.0, "dur": fall})
			h.fxs["meteors"] = ms
			if h.fxs.has("wrath"):
				h.fxs["wrath"]["until"] = maxf(float(h.fxs["wrath"]["until"]), fall + WRATH_SLACK)
			if h.puppet:
				Sfx.play_at("fireball", at, -10.0, 0.7)
			else:
				Sfx.play("fireball", -9.0, 0.7)
		["wrath", "end"]:
			_end_wrath(h, bool(ev.get("x", false)))
		_:
			return false
	return true

static func _end_charge(h: Hero) -> void:
	if not h.fxs.has("icharge"):
		return
	var c: Dictionary = h.fxs["icharge"]
	h.fxs.erase("icharge")
	var n = c["node"]
	if n != null and is_instance_valid(n):
		(n as GPUParticles3D).emitting = false
		SkillFx.free_later(n, 0.8)

## The grip lets go: the victim is back on the ground (dropped, or smashed into it).
static func _end_grip(h: Hero, smashed: bool) -> void:
	if not h.fxs.has("grip"):
		return
	var g: Dictionary = h.fxs["grip"]
	h.fxs.erase("grip")
	var v = g["victim"]
	if v != null and is_instance_valid(v):
		var rig = v.get("rig")
		if rig != null and is_instance_valid(rig):
			rig.position.y = 0.0
			rig.rotation.z = 0.0
		var fl: Node = v.get_node_or_null("GripFire")
		if fl != null:
			fl.queue_free()
		if not smashed:
			v.set_meta("gripped", false)

## The wrath ends: the white heat fades, the light with it.
static func _end_wrath(h: Hero, _finished: bool) -> void:
	if not h.fxs.has("wrath"):
		return
	var n: Dictionary = h.fxs["wrath"]
	h.fxs.erase("wrath")
	_set_heat(h, 0.0)
	var l = n.get("light")
	if l != null and is_instance_valid(l):
		var tw: Tween = (l as Node).create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.6)
		tw.tween_callback((l as Node).queue_free)

## The white heat in his cracks (the body shader's "wrath", Demon.animate keeps "glow" on top of it).
static func _set_heat(h: Hero, k: float) -> void:
	if h.rig == null or not h.rig.has_meta("demon_mats"):
		return
	for m in h.rig.get_meta("demon_mats"):
		(m as ShaderMaterial).set_shader_parameter("wrath", k)

## Every frame after the pose (the caster's and the puppet's): the charge's embers, the boulders and meteors in
## the air, the foe held up, the wrath's heat.
static func update(h: Hero, delta: float) -> void:
	if not h.is_demon():
		return
	var world = h.game.world
	var root: Node3D = world.fx_root
	if h.fxs.has("icharge"):
		var c: Dictionary = h.fxs["icharge"]
		c["until"] = float(c["until"]) - delta
		if float(c["until"]) <= 0.0 or (not h.puppet and not h.dm.has("charge")):
			_end_charge(h)
	for key in ["boulders", "meteors"]:
		if not h.fxs.has(key):
			continue
		var bs: Array = h.fxs[key]
		for b in bs.duplicate():
			var n = b["node"]
			if n == null or not is_instance_valid(n):
				bs.erase(b)
				continue
			b["t"] = float(b["t"]) + delta
			var u := clampf(float(b["t"]) / maxf(float(b["dur"]), 0.01), 0.0, 1.0)
			var from: Vector3 = b["from"]
			var to: Vector3 = b["to"]
			var p := from.lerp(to, u)
			if key == "boulders":
				p.y += sin(u * PI) * (2.2 + from.distance_to(to) * 0.18)
			(n as Node3D).global_position = p
			(n as Node3D).rotation += Vector3(delta * 6.0, delta * 2.0, 0.0)
			if u >= 1.0:
				bs.erase(b)
				(n as Node).queue_free()
				if key == "meteors":
					crater(root, to, DemonSkills.METEOR_R)
					Sfx.play_at("boom", to, -4.0, 1.05)
					SkillFx.shake(h, 0.22)
		if bs.is_empty():
			h.fxs.erase(key)
	if h.fxs.has("grip"):
		var g: Dictionary = h.fxs["grip"]
		var v = g["victim"]
		g["until"] = float(g["until"]) - delta
		g["t"] = float(g["t"]) + delta
		if v == null or not is_instance_valid(v) or v.dead or float(g["until"]) <= 0.0:
			_end_grip(h, false)
		else:
			# hauled up into the air over his head, squirming
			g["lift"] = lerpf(float(g["lift"]), DemonSkills.GRIP_LIFT, clampf(delta * 7.0, 0.0, 1.0))
			var rig = v.get("rig")
			if rig != null and is_instance_valid(rig):
				rig.position.y = float(g["lift"]) + sin(float(g["t"]) * 14.0) * 0.06
				rig.rotation.z = sin(float(g["t"]) * 9.0) * 0.25 * clampf(float(g["lift"]) / DemonSkills.GRIP_LIFT, 0.0, 1.0)
			if h.puppet:
				# a partner's puppet holds it beside the hero's hands
				var hand := SkillFx.hand(h, true)
				var pv: Vector3 = v.global_position
				pv.x = lerpf(pv.x, hand.x, clampf(delta * 6.0, 0.0, 1.0))
				pv.z = lerpf(pv.z, hand.z, clampf(delta * 6.0, 0.0, 1.0))
	if h.fxs.has("wrath"):
		var n: Dictionary = h.fxs["wrath"]
		n["until"] = float(n["until"]) - delta
		var st := SkillFx.style(h)
		if st in DemonSkills.WRATH_STAGES:
			n["until"] = maxf(float(n["until"]), 2.0)
		if float(n["until"]) <= 0.0 or (not h.puppet and not h.dm.has("wrath")):
			_end_wrath(h, false)
		else:
			var want: float = float(n["want"])
			var k: float = float(n["k"])
			k = lerpf(k, want, clampf(delta * (3.0 if want > k else 1.5), 0.0, 1.0))
			n["k"] = k
			_set_heat(h, k)
			var l = n.get("light")
			if l != null and is_instance_valid(l):
				(l as OmniLight3D).light_energy = 2.2 * k * (0.85 + 0.15 * sin(h.anim_time * 9.0))
			if k > 0.3 and randf() < delta * 10.0 * k:
				Fx.burst(root, h.global_position + Vector3(randf_range(-0.5, 0.5), randf_range(0.6, 2.0), randf_range(-0.4, 0.4)), HOT, 2, 1.5, 0.06, 0.6, true, 0.6, 40.0)

## Everything of his that lingers is gone (death, a class change, a zone change).
static func clear(h: Hero) -> void:
	_end_charge(h)
	_end_grip(h, false)
	_end_wrath(h, false)
	for key in ["boulders", "meteors"]:
		if h.fxs.has(key):
			for b in h.fxs[key]:
				if is_instance_valid(b["node"]):
					(b["node"] as Node).queue_free()
			h.fxs.erase(key)

# ---------------------------------------------------------------- the pieces
## Cracked rock with magma glowing through it, flat on the ground (a disc, or a wedge of one opening toward -z),
## breathing, cooling to black over its life. melt 0..1: how molten (a pool) rather than cracked (a slam's floor).
static func lava_decal(root: Node3D, at: Vector3, radius: float, life: float, melt: float, yaw := 0.0, wedge := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _disc_mesh()
	var m := _lava_mat(melt, wedge)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = at + Vector3(0, 0.05, 0)
	mi.rotation.y = yaw
	mi.scale = Vector3(radius, 1.0, radius)
	var l := OmniLight3D.new()
	l.light_color = EMBER
	l.light_energy = 0.8 + melt * 1.2
	l.omni_range = radius * 2.2
	l.shadow_enabled = false
	l.position = Vector3(0, 0.6, 0)
	mi.add_child(l)
	l.scale = Vector3.ONE / maxf(radius, 0.01)
	var em := Fx.aura(mi, EMBER, int(6 + radius * 6 * (0.5 + melt)), 0.9, 0.07, 1.0, 0.8, 0.8, 30.0, Vector3.ZERO)
	em.scale = Vector3.ONE / maxf(radius, 0.01)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("life", v), 1.0, 0.0, life)
	tw.tween_callback(mi.queue_free)
	var tw2 := l.create_tween()
	tw2.tween_property(l, "light_energy", 0.0, life)
	return mi

## A strip of the same cracked, glowing rock from a to b (the fissures).
static func lava_strip(root: Node3D, a: Vector3, b: Vector3, width: float, life: float, melt: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _strip_mesh()
	var m := _lava_mat(melt, 0.0, true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var d := b - a
	var len := Vector2(d.x, d.z).length()
	mi.global_position = a + Vector3(0, 0.06, 0)
	mi.rotation.y = atan2(-d.x, -d.z)
	mi.scale = Vector3(width, 1.0, maxf(len, 0.05))
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("life", v), 1.0, 0.0, life)
	tw.tween_callback(mi.queue_free)
	return mi

## A burst of lava out of a fissure: a pillar of fire, a flash, embers and a short-lived glow on the ground.
static func eruption(root: Node3D, at: Vector3, r: float) -> void:
	Fx.burst(root, at + Vector3(0, 0.2, 0), EMBER, 26, 6.5, 0.09, 0.6, true, -5.0, 28.0, Vector3.UP)
	Fx.burst(root, at + Vector3(0, 0.2, 0), HOT, 10, 4.0, 0.14, 0.4, true, -3.0, 40.0, Vector3.UP)
	Fx.burst(root, at + Vector3(0, 0.1, 0), Color(0.25, 0.2, 0.17, 0.7), 12, 2.5, 0.35, 0.7, false, -1.5, 60.0, Vector3.UP)
	Fx.flash(root, at + Vector3(0, 0.7, 0), EMBER, 2.5, 0.25, 5.0)
	# a short spout of fire (Fx.pillar is a six-metre column: far too much for a crack in the ground)
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.cyl(0.9, 0.9, 1.0, 16)
	var m := Mats.glow_unique(EMBER, 2.2, 1.2, 0.55)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = at + Vector3(0, 0.9, 0)
	mi.scale = Vector3(0.12, 0.3, 0.12)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(0.26, 1.5, 0.26), 0.12)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha_mul", v), 0.8, 0.0, 0.3).set_delay(0.12)
	SkillFx.free_later(mi, 0.6)
	lava_decal(root, at, r * 0.8, 1.8, 0.6)

## A boulder lands: the splash of molten rock, the flash, the ring.
static func splash(root: Node3D, at: Vector3, r: float) -> void:
	Fx.ring(root, at + Vector3(0, 0.05, 0), r, EMBER, 0.45, 0.35)
	Fx.burst(root, at + Vector3(0, 0.3, 0), EMBER, 44, 6.0, 0.1, 0.7, true, -5.0, 75.0)
	Fx.burst(root, at + Vector3(0, 0.3, 0), HOT, 16, 4.0, 0.16, 0.5, true, -4.0, 60.0)
	Fx.burst(root, at + Vector3(0, 0.2, 0), Color(0.3, 0.25, 0.2, 0.7), 22, 3.0, 0.4, 0.8, false, -2.0, 70.0)
	Fx.flash(root, at + Vector3(0, 0.9, 0), HOT, 3.5, 0.3, 7.0)

## A meteor's crater: dark rock, molten at the heart, embers rising off it.
static func crater(root: Node3D, at: Vector3, r: float) -> void:
	lava_decal(root, at, r, 4.0, 0.7)
	Fx.ring(root, at + Vector3(0, 0.05, 0), r, EMBER, 0.4, 0.3)
	Fx.burst(root, at + Vector3(0, 0.3, 0), EMBER, 36, 6.0, 0.09, 0.7, true, -5.0, 70.0)
	Fx.burst(root, at + Vector3(0, 0.3, 0), HOT, 12, 4.0, 0.15, 0.45, true, -4.0, 50.0)
	Fx.burst(root, at + Vector3(0, 0.2, 0), Color(0.28, 0.22, 0.18, 0.7), 20, 3.2, 0.4, 0.8, false, -2.0, 70.0)
	Fx.flash(root, at + Vector3(0, 0.9, 0), HOT, 3.5, 0.3, 7.0)

## A lump of molten rock (a boulder, a meteor): dark crust with lava showing, an ember trail behind it.
static func boulder(root: Node3D, r: float) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	var mi := MeshInstance3D.new()
	mi.mesh = _rock_mesh()
	mi.material_override = _rock_mat()
	mi.scale = Vector3(r, r * 0.85, r * 1.1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = EMBER
	l.light_energy = 1.4
	l.omni_range = 4.0
	l.shadow_enabled = false
	n.add_child(l)
	var tr := Fx.aura(n, EMBER, 30, 1.2, 0.1, 0.5, 0.2, r * 0.9, 120.0, Vector3.ZERO)
	tr.local_coords = false
	return n

static func _rock_mesh() -> Mesh:
	if _rock == null:
		_rock = Geo.sph(1.0, 10)
	return _rock

static var _rock_m: StandardMaterial3D
static func _rock_mat() -> StandardMaterial3D:
	if _rock_m == null:
		# a dark crust, the heat a dull red inside it (a bright emission reads as a flat yellow disc from afar)
		_rock_m = Mats.mat(Color(0.1, 0.06, 0.05), 0.95, 0.0, Color(0.9, 0.25, 0.04), 0.45, 0.3)
	return _rock_m

static func _lava_mat(melt: float, wedge: float, strip := false) -> ShaderMaterial:
	if _lava_shader == null:
		_lava_shader = Shader.new()
		_lava_shader.code = LAVA_SHADER
	var m := ShaderMaterial.new()
	m.shader = _lava_shader
	m.set_shader_parameter("melt", melt)
	m.set_shader_parameter("wedge", wedge)
	m.set_shader_parameter("strip", 1.0 if strip else 0.0)
	m.set_shader_parameter("seed", randf() * 10.0)
	m.set_shader_parameter("ember", EMBER)
	return m

## A unit disc in the XZ plane, UV = position (0.5 at the centre).
static func _disc_mesh() -> ArrayMesh:
	if _disc != null:
		return _disc
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 36
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for p in [Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))]:
			st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 + p.z * 0.5))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	_disc = st.commit()
	return _disc

## A unit strip in the XZ plane from z 0 to -1, x -0.5..0.5; UV.x across, UV.y along.
static func _strip_mesh() -> ArrayMesh:
	if _strip != null:
		return _strip
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 0, -1), Vector3(-0.5, 0, 0), Vector3(0.5, 0, -1), Vector3(-0.5, 0, -1)]
	for p in quad:
		st.set_uv(Vector2(p.x + 0.5, -p.z))
		st.set_normal(Vector3.UP)
		st.add_vertex(p)
	_strip = st.commit()
	return _strip

const LAVA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float life = 1.0;      // 1 fresh .. 0 cooled and gone
uniform float melt = 0.0;      // 0 cracked rock, 1 a molten pool
uniform float wedge = 0.0;     // > 0: only a wedge of this half-angle (rad) opening toward -z
uniform float strip = 0.0;     // 1: a strip (UV.y along it) instead of a disc
uniform float seed = 0.0;
uniform vec3 ember : source_color = vec3(1.0, 0.42, 0.06);
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y); }
float fb(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a * vn(p); p = p * 2.1 + 1.7; a *= 0.5; } return v; }
void fragment(){
	vec2 q = UV * 2.0 - 1.0;
	float edge;
	vec2 np;
	if (strip > 0.5) {
		edge = (1.0 - smoothstep(0.55, 1.0, abs(q.x))) * (1.0 - smoothstep(0.9, 1.0, abs(q.y)));
		np = vec2(UV.x * 1.5, UV.y * 4.0);
	} else {
		float r = length(q);
		edge = 1.0 - smoothstep(0.62 + 0.25 * melt, 1.0, r + (vn(q * 5.0 + seed) - 0.5) * 0.25);
		if (wedge > 0.0) {
			float ang = atan(q.x, -q.y);
			edge *= 1.0 - smoothstep(wedge * 0.8, wedge, abs(ang));
			edge *= smoothstep(0.0, 0.25, r);
		}
		np = q * 3.0;
	}
	if (edge < 0.02) { discard; }
	float n = fb(np + seed);
	float crack = 1.0 - smoothstep(0.0, 0.07 + 0.05 * melt, abs(n - 0.5));
	float pool = smoothstep(0.35, 0.6, n) * melt;
	float hot = clamp(crack + pool, 0.0, 1.0);
	float breathe = 0.75 + 0.25 * sin(TIME * 2.1 + n * 9.0 + seed);
	float glow = hot * life * breathe;
	// cooling: the glow goes, then the dark rock fades out
	float rock = smoothstep(0.0, 0.25, life);
	ALBEDO = mix(vec3(0.05, 0.035, 0.03), ember * 0.5, glow);
	EMISSION = ember * glow * 3.4 + vec3(1.0, 0.9, 0.6) * pool * life * breathe * 1.6;
	ALPHA = edge * (0.45 + 0.5 * max(hot * life, rock * 0.6));
}
"""

## A steady drift of embers (Blood Pact on a summoned demon).
static func ember_aura() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.9
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.45
	pm.emission_ring_inner_radius = 0.3
	pm.emission_ring_height = 0.05
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.5, 0.1, 0.9))
	g.set_color(1, Color(0.9, 0.05, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	q.material = Mats.particle_mat(true, Color(2, 2, 2))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p

## A few seconds of flame clinging to a clawed monster.
static func ignite(root: Node3D, target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	var f := Props.fire(target, Vector3(0, 0.9 * float(target.get("height")), 0), 0.35, EMBER, false, false, false)
	SkillFx.free_later(f, 1.6)

# ---------------------------------------------------------------- the Underworld
## Souls rising from the ground all around the Demon while Phase lasts.
static func soul_field() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 160
	p.lifetime = 3.2
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-16, -2, -12), Vector3(32, 10, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 0.2, 9)
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, 0.35, 0)
	pm.turbulence_enabled = false
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.2))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.4))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.6, 1.0, 0.0))
	g.add_point(0.25, Color(0.8, 0.7, 1.0, 0.75))
	g.set_color(1, Color(0.9, 0.2, 0.4, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.2)
	q.material = Mats.particle_mat(true, Color(2.2, 2.2, 2.2))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p

## Full-screen grade for the Underworld: the act is still there, but drained to bone and
## violet, crimson where anything burns, rippling like heat over the dark.
const UNDERWORLD_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amt = 0.0;
void fragment(){
	vec2 uv = SCREEN_UV;
	float w = sin(uv.y * 38.0 + TIME * 2.2) * 0.0018 + sin(uv.x * 23.0 - TIME * 1.4) * 0.0014;
	uv += vec2(w, -w * 0.7) * amt;
	vec2 dc = (uv - 0.5) * 0.007 * amt;
	vec3 c;
	c.r = texture(screen_tex, uv + dc).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - dc).b;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	// shadows sink to indigo, mid-tones turn violet, highlights go bone-pale; lifted so the
	// fight stays easy to read
	l = pow(clamp(l, 0.0, 1.0), 0.75);
	vec3 g = mix(vec3(0.05, 0.02, 0.1), vec3(0.46, 0.22, 0.66), smoothstep(0.0, 0.4, l));
	g = mix(g, vec3(1.0, 0.9, 0.95), smoothstep(0.4, 1.0, l));
	// anything burning (fires, eyes, ember edges) keeps its colour and turns blood-hot
	float hot = clamp((c.r - max(c.g, c.b)) * 2.2, 0.0, 1.0);
	g = mix(g, c * vec3(1.25, 0.55, 0.6), hot);
	vec3 o = mix(c, g, amt * 0.82);
	// a dark ring of veins pulsing at the edge of sight
	vec2 q = SCREEN_UV - 0.5;
	float r = length(q * vec2(1.7, 1.0));
	float vig = smoothstep(0.32, 0.92, r);
	float ang = atan(q.y, q.x);
	float veins = smoothstep(0.86, 1.0, sin(ang * 17.0 + sin(r * 28.0 - TIME * 1.8) * 1.6)) * vig;
	o = mix(o, vec3(0.015, 0.0, 0.03), vig * 0.55 * amt);
	o += vec3(0.65, 0.05, 0.22) * veins * 0.4 * amt * (0.6 + 0.4 * sin(TIME * 3.0));
	COLOR = vec4(o, 1.0);
}
"""

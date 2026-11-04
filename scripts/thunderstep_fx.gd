class_name ThunderstepFx
extends RefCounted
## Thunderstep's look (jj's pick in place of Storm Snare, 2026-11-04; its lightning gold, jj: "thunderstone should be
## yellow or gold"). Draws only: ArcherFx plays its events on the archer's game and on his puppet's alike; the vault's
## travel, the stun and the damage are archer.gd's (Archer._vault, _detonate).
##  - "vault" {p, q}: he backflips from p to q (`update` turns the rig over backwards round his middle and lifts it on an
##    arc, facing the way he came, on his own body and on his puppet), crackling: lightning off the ground where he
##    leaves it and along his path, gold sparks. Where he stood a gold storm sigil burns into the ground (the
##    Meshy-painted sigil, SIGIL_SHADER: drawn round in a sweep, turning slowly, flickering, brightening as it charges)
##    and the Meshy thunderstone (black volcanic glass, gold lightning in its cracks) is driven into its heart; arcs
##    crawl over the ring and a gold light rises with the charge.
##  - "spring" {p, r, t, n, x}: the sigil detonates. A bolt out of the sky onto the stone, lightning racing out along
##    the ground to the ring, into every foe on it and leaping on into the ones beyond (t: the first n were on it), a
##    flash, sparks, a shock ring of bending air, dust, a scorch; the stone shatters into its Blender-fractured pieces,
##    molten gold inside. With Aftershock (x) the sigil flares and stays for its next strike.
## Assets: assets/models/fx/storm/thunderstone.glb + thunderstone_pieces.glb (Meshy image-to-3D, prep_prop.py,
## fracture_rock.py; its blue veins turned gold), assets/textures/fx/storm/sigil.png (Meshy, cut and turned gold);
## sounds thunder_vault, sigil_charge, thunder_blast (ElevenLabs).

const STONE := "res://assets/models/fx/storm/thunderstone.glb"
const STONE_PIECES := "res://assets/models/fx/storm/thunderstone_pieces.glb"
const SIGIL := "res://assets/textures/fx/storm/sigil.png"
const CORE := Color(1.0, 0.96, 0.78)
const GOLD := Color(1.0, 0.68, 0.18)
const FLIP_PIVOT := 0.9
const FLIP_H := 1.1
const STONE_H := 0.75

static var _shader: Shader
static var _tex: Texture2D

static func sigil_tex() -> Texture2D:
	if _tex == null and ResourceLoader.exists(SIGIL):
		_tex = load(SIGIL)
	return _tex

static func play(h: Hero, ev: Dictionary) -> void:
	match str(ev["e"]):
		"vault":
			_vault(h, ev["p"], ev["q"])
		"spring":
			_spring(h, ev)

# ---------------------------------------------------------------- the vault
static func _vault(h: Hero, p: Vector3, q: Vector3) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var back := (q - p) * Vector3(1, 0, 1)
	var face := -back.normalized() if back.length() > 0.1 else h.facing()
	h.fxs["vault"] = {"t": 0.0, "yaw": atan2(-face.x, -face.z), "last": h.global_position + Vector3(0, 1.1, 0), "bolt": 0.0}
	# lightning off the ground where he leaves it, gold sparks, dust
	for i in [1, 1, 2, 3][tr]:
		var a := randf() * TAU
		ElementalFx.bolt(root, p + Vector3(cos(a), 0.05, sin(a)) * randf_range(0.6, 1.2), p + Vector3(0, randf_range(1.2, 1.8), 0),
			0.22, 0.07, tr, CORE, GOLD)
	DemonKitFx.sparks(root, p + Vector3(0, 0.3, 0), Vector3.UP, [10, 16, 24, 32][tr], 70.0, Vector2(3.0, 8.0), 0.5)
	ElementalFx._dust(root, p + Vector3(0, 0.12, 0), Color(0.42, 0.38, 0.32), 0.8, 0.4, {"amount": [3, 4, 6, 8][tr],
		"life": 0.8, "explosive": 0.9, "shape": "ring", "r": 0.35, "r_in": 0.15, "dir": Vector3.UP, "spread": 20.0,
		"vel": [0.2, 0.5], "radial": [1.5, 3.0], "damping": [2.0, 3.0], "scale": [0.7, 1.1], "grow": [0.5, 1.5]})
	Fx.flash(root, p + Vector3(0, 1.0, 0), GOLD, 2.5, 0.25, 5.0)
	SkillFx.snd(h, "thunder_vault", -2.0, randf_range(0.97, 1.05))
	GrassField.impulse(p, 1.4, 0.6, 0.3)
	_sigil(h, root, p, tr)

## The sigil burning into the ground at p, the thunderstone driven into it, the light rising with the charge.
static func _sigil(h: Hero, root: Node3D, p: Vector3, tr: int) -> void:
	var r := Archer.SIGIL_R
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SIGIL_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("sigil_tex", sigil_tex())
	m.set_shader_parameter("col", GOLD)
	var disc := ElementalFx._piece(root, InfernalFx.disc_mesh(h.game.world, p, r, 40, 4, 0.07), m, p, 12.0)
	InfernalFx.tween_param(disc, m, "draw", 0.0, 1.0, 0.28).set_ease(Tween.EASE_OUT)
	var stone := DemonKitFx.model(STONE)
	if stone != null:
		DemonKitFx.heat_model(stone, 1.5, GOLD)
		root.add_child(stone)
		var tilt := Vector3(randf_range(-0.18, 0.18), randf() * TAU, randf_range(-0.18, 0.18))
		stone.rotation = tilt
		stone.global_position = p + Vector3(0, 2.0, 0)
		var tw := stone.create_tween()
		tw.tween_property(stone, "global_position", p + Vector3(0, -0.12, 0), 0.12).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			# driven in: a crack of sparks and a puff of dust at its foot
			if is_instance_valid(root):
				DemonKitFx.sparks(root, p + Vector3(0, 0.15, 0), Vector3.UP, [6, 8, 12, 16][tr], 80.0, Vector2(2.0, 5.0), 0.4))
	var lt := OmniLight3D.new()
	lt.light_color = GOLD
	lt.light_energy = 0.0
	lt.omni_range = r * 2.2
	lt.shadow_enabled = false
	root.add_child(lt)
	lt.global_position = p + Vector3(0, 1.2, 0)
	var ss: Array = h.fxs.get("sigils", [])
	ss.append({"p": p, "disc": disc, "mat": m, "stone": stone, "light": lt, "t": 0.0, "arc": 0.0})
	h.fxs["sigils"] = ss
	Sfx.play_at("sigil_charge", p, -4.0, 1.0)

# ---------------------------------------------------------------- every frame
static func update(h: Hero, delta: float) -> void:
	if h.fxs.has("vault"):
		_flip(h, delta)
	if not h.fxs.has("sigils"):
		return
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var ss: Array = h.fxs["sigils"]
	for sg in ss.duplicate():
		sg["t"] = float(sg["t"]) + delta
		var k := clampf(float(sg["t"]) / Archer.SIGIL_ARM, 0.0, 1.0)
		var m: ShaderMaterial = sg["mat"]
		m.set_shader_parameter("charge", k)
		m.set_shader_parameter("spin", float(sg["t"]) * 0.6)
		var lt = sg["light"]
		if is_instance_valid(lt):
			(lt as OmniLight3D).light_energy = (0.4 + 2.2 * k * k) * randf_range(0.85, 1.0)
		var st = sg["stone"]
		if is_instance_valid(st):
			DemonKitFx.set_heat(st, 1.2 + 3.0 * k * k + randf_range(0.0, 0.5))
		# arcs crawling over the ring, quicker as it charges
		sg["arc"] = float(sg["arc"]) - delta
		if float(sg["arc"]) <= 0.0:
			sg["arc"] = lerpf(0.16, 0.06, k) * (2.0 if tr == 0 else 1.0)
			var p: Vector3 = sg["p"]
			var a := randf() * TAU
			var a2 := a + randf_range(0.5, 1.4) * (1.0 if randf() < 0.5 else -1.0)
			var rr := Archer.SIGIL_R * randf_range(0.55, 0.95)
			var from := p + Vector3(cos(a) * rr, 0.08, sin(a) * rr)
			var to := p + Vector3(cos(a2) * rr, 0.08, sin(a2) * rr) if randf() < 0.6 else p + Vector3(0, STONE_H * 0.8, 0)
			ElementalFx.bolt(root, from, to, 0.12, 0.04 + 0.04 * k, tr, CORE, GOLD)
		# a lost "spring" (a partner's): it burns out by itself
		if float(sg["t"]) > Archer.SIGIL_ARM + 3.5:
			_end_sigil(h, root, sg, false)

## The backflip: the rig turned over backwards round his middle and lifted on an arc, facing the way he came.
static func _flip(h: Hero, delta: float) -> void:
	var v: Dictionary = h.fxs["vault"]
	v["t"] = float(v["t"]) + delta
	var s := clampf(float(v["t"]) / Archer.VAULT_T, 0.0, 1.0)
	var yaw: float = v["yaw"]
	if s >= 1.0 or h.dead:
		h.fxs.erase("vault")
		h.rig.rotation.x = 0.0
		h.rig.position = Vector3.ZERO
		h.rig.rotation.y = yaw
		# landed: a little crackle and dust at his feet
		var root: Node3D = h.game.world.fx_root
		DemonKitFx.sparks(root, h.global_position + Vector3(0, 0.1, 0), Vector3.UP, 8, 80.0, Vector2(1.5, 4.0), 0.35)
		ElementalFx._dust(root, h.global_position + Vector3(0, 0.1, 0), Color(0.42, 0.38, 0.32), 0.6, 0.35, {"amount": 3,
			"life": 0.6, "explosive": 0.9, "shape": "sphere", "r": 0.2, "dir": Vector3.UP, "spread": 70.0, "vel": [0.2, 0.6],
			"damping": [1.5, 2.5], "scale": [0.7, 1.1], "grow": [0.5, 1.4]})
		return
	var a := TAU * smoothstep(0.08, 0.92, s)
	var piv := Vector3(0, FLIP_PIVOT, 0)
	var off := piv - Basis(Vector3.RIGHT, a) * piv
	off.y += FLIP_H * sin(PI * s)
	h.rig.rotation.y = yaw
	h.rig.rotation.x = a
	h.rig.position = Basis(Vector3.UP, yaw) * off
	# lightning along his path through the air
	v["bolt"] = float(v["bolt"]) - delta
	var now: Vector3 = h.global_position + Vector3(0, FLIP_PIVOT + FLIP_H * sin(PI * s), 0)
	if float(v["bolt"]) <= 0.0:
		v["bolt"] = 0.06
		ElementalFx.bolt(h.game.world.fx_root, v["last"], now, 0.18, 0.06, InfernalFx.tier(h.game), CORE, GOLD)
		v["last"] = now

# ---------------------------------------------------------------- the detonation
static func _spring(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var w = h.game.world
	var tr := InfernalFx.tier(h.game)
	var p: Vector3 = ev["p"]
	var r: float = float(ev.get("r", Archer.SIGIL_R))
	var again: bool = bool(ev.get("x", false))
	var foes: Array = ev.get("t", [])
	var on: int = int(ev.get("n", foes.size()))
	# the bolt out of the sky onto the stone
	var top := p + Vector3(randf_range(-0.6, 0.6), 10.0, randf_range(-0.6, 0.6))
	ElementalFx.bolt(root, top, p + Vector3(0, STONE_H, 0), 0.4, 0.32, tr, CORE, GOLD)
	if tr >= 1:
		ElementalFx.bolt(root, top + Vector3(0.8, 0, -0.5), p + Vector3(0, STONE_H * 0.5, 0), 0.3, 0.16, tr, CORE, GOLD)
	# lightning racing out along the ground to the ring
	var rays: int = [4, 6, 8, 10][tr]
	for i in rays:
		var a := TAU * (float(i) + randf_range(-0.3, 0.3)) / rays
		var to := p + Vector3(cos(a), 0, sin(a)) * r * randf_range(0.85, 1.05)
		to.y = w.height_at(to.x, to.z) + 0.1
		ElementalFx.bolt(root, p + Vector3(0, 0.15, 0), to, 0.3, 0.08, tr, CORE, GOLD)
	# into each foe on it, and leaping on from one to the next beyond it
	var prev := p + Vector3(0, STONE_H, 0)
	for i in foes.size():
		var e = foes[i]
		if e == null or not is_instance_valid(e):
			continue
		var at: Vector3 = (e as Node3D).global_position + Vector3(0, DemonKitFx.height_of(e) * 0.6, 0)
		var src := p + Vector3(0, STONE_H, 0) if i < on else prev
		ElementalFx.bolt(root, src, at, 0.35, 0.12, tr, CORE, GOLD)
		DemonKitFx.sparks(root, at, Vector3.UP, [4, 6, 9, 12][tr], 90.0, Vector2(2.0, 5.0), 0.35)
		prev = at
	# the flash, the sparks, the blast of air and dust, the scorch
	DemonKitFx.flash_light(root, p + Vector3(0, 1.6, 0), GOLD, 9.0, r * 3.2, 0.55)
	DemonKitFx.sparks(root, p + Vector3(0, 0.4, 0), Vector3.UP, [16, 26, 36, 48][tr], 75.0, Vector2(4.0, 11.0), 0.6)
	DemonKitFx.shock_ring(root, h.game, p + Vector3(0, 0.4, 0), r * 1.5, 0.45)
	ElementalFx._dust(root, p + Vector3(0, 0.2, 0), Color(0.34, 0.3, 0.26), 1.4, 0.45, {"amount": [5, 8, 12, 16][tr],
		"life": 1.2, "explosive": 1.0, "shape": "ring", "r": 0.6, "r_in": 0.2, "dir": Vector3.UP, "spread": 18.0,
		"vel": [0.3, 0.7], "radial": [r * 1.6, r * 2.4], "damping": [2.4, 3.2], "scale": [0.8, 1.3], "grow": [0.6, 1.8]})
	if not again:
		ArrowFx.scorch(h.game, p, Vector3.FORWARD, r * 0.9, r * 0.9)
	Sfx.play_at("thunder_blast", p, -1.0 if not again else -5.0, randf_range(0.96, 1.04) if not again else 1.15)
	SkillFx.shake(h, 0.28 if not again else 0.14)
	GrassField.impulse(p, r * 1.4, 0.9, 0.45)
	# the sigil that went off: it flares; the stone shatters unless the sigil strikes again
	var best: Dictionary = {}
	var bd := 2.0
	for sg in h.fxs.get("sigils", []):
		var d: float = (sg["p"] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = sg
	if not best.is_empty():
		var m: ShaderMaterial = best["mat"]
		if is_instance_valid(best["disc"]):
			InfernalFx.tween_param(best["disc"], m, "flash", 1.0, 0.0, 0.4)
		if again:
			best["t"] = Archer.SIGIL_ARM - 0.8       # it charges again for its next strike
		else:
			_end_sigil(h, root, best, true)

## The sigil done: the stone breaks into its pieces (molten gold inside), the sigil and its light fade out.
static func _end_sigil(h: Hero, root: Node3D, sg: Dictionary, burst: bool) -> void:
	var ss: Array = h.fxs.get("sigils", [])
	ss.erase(sg)
	if ss.is_empty():
		h.fxs.erase("sigils")
	var st = sg["stone"]
	if is_instance_valid(st):
		if burst:
			var at: Vector3 = (st as Node3D).global_position + Vector3(0, STONE_H * 0.5, 0)
			DemonKitFx.pieces(root, h.game.world, at, STONE_PIECES, 1.0, 5.0, 3.0, 1.8, 0.9)
		(st as Node3D).queue_free()
	var disc = sg["disc"]
	if is_instance_valid(disc):
		InfernalFx.tween_param(disc, sg["mat"], "life", 1.0, 0.0, 0.7 if burst else 1.2, 0.15)
		Fx._free_later(disc, 1.4)
	var lt = sg["light"]
	if is_instance_valid(lt):
		var tw := (lt as Node).create_tween()
		tw.tween_property(lt, "light_energy", 0.0, 0.6)
		tw.tween_callback((lt as Node).queue_free)

static func clear(h: Hero) -> void:
	if h.fxs.has("vault") and h.rig != null:
		h.rig.rotation.x = 0.0
		h.rig.position = Vector3.ZERO
	h.fxs.erase("vault")
	h.fxs.erase("sigils")

## The storm sigil on InfernalFx.disc_mesh (UV 0.5 at the centre): the Meshy-painted sigil (RGB its hue, A its light),
## drawn round in a sweep (`draw`), turning (`spin`), flickering like live current, brighter as it charges (`charge`),
## blazing as it goes off (`flash`), fading (`life`). Added light.
const SIGIL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D sigil_tex : source_color, filter_linear_mipmap;
uniform vec4 col : source_color = vec4(1.0, 0.68, 0.18, 1.0);
uniform float draw = 0.0;
uniform float charge = 0.0;
uniform float flash = 0.0;
uniform float life = 1.0;
uniform float spin = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float ang = atan(d.y, d.x);
	float sweep = fract(ang / 6.2831853 + 0.25);
	float cs = cos(spin);
	float sn = sin(spin);
	vec2 q = vec2(cs * d.x - sn * d.y, sn * d.x + cs * d.y) + vec2(0.5);
	vec4 t = texture(sigil_tex, q);
	float on = smoothstep(draw + 0.02, draw - 0.02, sweep) * step(0.001, draw);
	float fl = 0.78 + 0.22 * sin(TIME * 37.0 + ang * 5.0) * sin(TIME * 23.0 + length(d) * 30.0);
	float e = (0.8 + 2.2 * charge * charge + 4.0 * flash) * fl;
	ALBEDO = mix(col.rgb, t.rgb, 0.55) * e;
	ALPHA = clamp(t.a * on * life * (0.6 + 0.4 * charge + 0.6 * flash), 0.0, 1.0);
}
"""

class_name ArcherFx
extends RefCounted
## Visual effects for the archer's skills (SkillFx events; the gameplay is in archer.gd and skills/). His arrows
## are drawn and flown by ArcherArrowFx on every game, and hurt nothing: the hits are the skills' own (ArrowSkill).
## Frost Volley's rain, Arrow Storm and Thunderstep are drawn by their own looks (skills/), from their events.
##  the attack / Fire Arrow: "loose" {p: from, d: direction, k: "war"|"fire", x: it pierces}
##  Frost Volley: "cast" (the glacier arrow drawn, aimed high), "impact" {p: the ground, r: radius}: the flight up,
##    the storm and the rain's strikes (FrostVolleyRainFx, FrostVolleyFx)
##  Thunderstep: "vault" {p: the sigil, q: where he lands}, "spring" {p, r, t: the foes struck, n: how many of them
##    were on the sigil, x: it strikes again} (ThunderstepFx)
##  Spirit Beast: "impact" {p: the point, t: [the foe] when it was sent at one, x: called home} (the command's
##    rings and the roar; a puppet's own wolf (SpiritBeast.keep) takes the same command and only shows its bites)

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match [str(ev["s"]), str(ev["e"])]:
		["pierce", "cast"]:
			# the fire wakes on the cast: a low fuse under the draw, the charge (update) from here on
			h.fxs["fire_cast"] = Time.get_ticks_msec() / 1000.0
			ArrowFx.sounds(h, "fire", "cast")
		["volley", "cast"]:
			# the volley's shot: the glacier arrow and the high aim through its draw (update), the puppet's too
			h.fxs["volley_cast"] = Time.get_ticks_msec() / 1000.0
		["snare", "cast"], ["beast", "cast"]:
			pass
		["attack", "loose"], ["pierce", "loose"], ["a_multishot", "loose"], ["a_explosive", "loose"], ["a_glacial", "loose"], ["a_stormshot", "loose"]:
			# the arrow of its kind, flown on every game (ArcherArrowFx); the hits are the skill's own (ArrowSkill)
			ArcherArrowFx.loosed(h, ev)
		["volley", "impact"]:
			# the flight going up out of the bow, the storm over the mark, and its rain (FrostVolleyRainFx)
			FrostVolleyRainFx.start(h, ev)
		["snare", "vault"], ["snare", "spring"]:
			ThunderstepFx.play(h, ev)
		["a_barrage", "impact"]:
			ArrowStormFx.play(h, ev)
		["a_mark", "impact"]:
			var foes2: Array = ev.get("t", [])
			var at2: Vector3 = ev["p"]
			hunter_mark(root, at2, 1.3, Archer.HUNTER, 1.2)
			if not foes2.is_empty() and is_instance_valid(foes2[0]):
				var foe2: Node3D = foes2[0]
				var ring := Fx.aura(foe2, Archer.HUNTER, 18, 0.2, 0.09, 0.8, 0.4, 0.5, 30.0, Vector3(0, 2.4, 0))
				ring.name = "hunted"
				Fx._free_later(ring, float(ev.get("x", Skill.num("a_mark", "secs", 8.0))))
			SkillFx.snd(h, "hunter_mark", -2.0)
		["a_explosive", "blast"]:
			# Blast Arrow's burst: the fire sim's fireball is ArrowFx.finish's; here the blast's own boom and ring, and
			# the simulated fire on the nearest it set burning ("t"; the rest burn on their numbers)
			var bp: Vector3 = ev["p"]
			Fx.ring(root, Vector3(bp.x, h.game.world.height_at(bp.x, bp.z), bp.z), float(ev.get("r", 3.5)), Color(1.0, 0.5, 0.15), 0.45)
			for e in ev.get("t", []):
				if is_instance_valid(e):
					ArrowFx.burn(h.game, e, "fire", float(ev.get("x", 3.0)))
			Sfx.play_at("blast_arrow", bp, 0.0)
			SkillFx.shake(h, 0.25)
		["beast", "impact"]:
			var foes: Array = ev.get("t", [])
			var foe = foes[0] if not foes.is_empty() else null
			var home: bool = bool(ev.get("x", false))
			var aim: Vector3 = ev["p"]
			# a partner's copy of his wolf takes the command here (his own took it from BeastCommand)
			for b in h.beasts if h.puppet else []:
				if not is_instance_valid(b) or b.dead:
					continue
				if foe != null:
					b.command("attack", foe)
				elif home:
					b.command("follow")
				else:
					b.command("hold", null, aim)
			if foe != null:
				hunter_mark(root, foe.global_position, 1.1, Archer.HUNTER)
			elif not home:
				hunter_mark(root, aim, 1.3, Archer.HUNTER)
			SkillFx.snd(h, "lion_roar", -4.0, 1.25)
			SkillFx.shake(h, 0.15)
		_:
			return false
	return true

## Arrows and rains have their own looks; sigils move in Archer.update (the puppet's too). Here: the fire gathering on the nocked
## arrow through the draw of a Fire Arrow shot (from the attack's progress, so the puppet shows it too).
# ---------------------------------------------------------------- the hunter's own marks (visual overhaul)
## The hunter's mark on the ground (a command to his wolf): three claw rakes torn across a pale ring,
## glowing in col, drawn in a blink and fading. In place of the generic ring.
static func hunter_mark(root: Node3D, pos: Vector3, r: float, col: Color, life := 0.9) -> void:
	if _claw_shader == null:
		_claw_shader = Shader.new()
		_claw_shader.code = CLAW_SHADER
	var m := ShaderMaterial.new()
	m.shader = _claw_shader
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("seed", randf() * 6.28)
	var cs = root.get_tree().current_scene if root.is_inside_tree() else null
	var w = cs.world if cs != null and "world" in cs else null
	var mi := ElementalFx._piece(root, InfernalFx.disc_mesh(w, pos, r, 32, 3, 0.07), m, pos, life + 0.1)
	InfernalFx.tween_param(mi, m, "draw", 0.0, 1.0, 0.12).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(mi, m, "life", 1.0, 0.0, life * 0.6, life * 0.4)

static func _light(root: Node3D, pos: Vector3, col: Color, energy: float, life: float, reach: float) -> void:
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

static var _claw_shader: Shader
## InfernalFx.disc_mesh UVs (centre 0.5, rim 0.5 out): a thin ring and three curved rakes across it, drawn in (draw
## 0..1, the rakes sweeping across), glowing, fading out (life 1..0).
const CLAW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.62, 0.85, 0.75, 1.0);
uniform float draw = 0.0;
uniform float life = 1.0;
uniform float seed = 0.0;
void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r = length(d);
	float ring = smoothstep(0.06, 0.0, abs(r - 0.88)) * 0.5;
	float cs = cos(seed); float sn = sin(seed);
	vec2 q = vec2(cs * d.x - sn * d.y, sn * d.x + cs * d.y);
	float rake = 0.0;
	for (int i = 0; i < 3; i++) {
		float off = (float(i) - 1.0) * 0.26;
		float bow = q.x * q.x * 0.35;                       // each rake curves like a swipe
		float dist = abs(q.y - off - bow + 0.1);
		float along = q.x * 0.5 + 0.5;
		float w = 0.035 * (1.0 - abs(q.x) * 0.8);           // thick in the middle, tapering to points
		float on = step(along, draw * 1.15) * step(abs(q.x), 0.85);
		rake = max(rake, smoothstep(w, 0.0, dist) * on);
	}
	float a = (ring + rake * 1.3) * life;
	ALBEDO = col.rgb * a * 1.6;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

static func update(h: Hero, _delta: float) -> void:
	var a := SkillFx.atk(h)
	var sty := SkillFx.style(h)
	var skill: String = h.atk_skill if not h.puppet else str(h.net_st.get("skill", ""))
	if sty == "bow" and a >= 0.0 and a < Anim.impact_at("bow") and (skill == "pierce" or (h.puppet and _puppet_fire(h))):
		# the charge grows from the nock to the full draw
		var k := clampf((a - ArcherBody.GRAB) / (Anim.impact_at("bow") - 0.08 - ArcherBody.GRAB), 0.0, 1.0)
		ArrowFx.draw_charge(h, "fire", k)
		h.fxs["draw_fire"] = true
	elif h.fxs.has("draw_fire"):
		ArrowFx.end_draw(h)
		h.fxs.erase("draw_fire")
	# Frost Volley's draw: the glacier arrow, the rime on it, the high aim (to the end of the shot's follow-through)
	if sty == "bow" and a >= 0.0 and a < 1.0 and (skill == "volley" or (h.puppet and _puppet_volley(h))):
		FrostVolleyFx.draw(h, a)
		h.fxs["draw_volley"] = true
	elif h.fxs.has("draw_volley"):
		FrostVolleyFx.end_draw(h)
		h.fxs.erase("draw_volley")
	ArcherArrowFx.update(h, _delta)
	FrostVolleyRainFx.update(h, _delta)
	FrostVolleyFx.update(h, _delta)
	ThunderstepFx.update(h, _delta)

## A puppet's shot has no skill id on the wire: the volley's "cast" event marks the next shot its.
static func _puppet_volley(h: Hero) -> bool:
	return h.fxs.has("volley_cast") and Time.get_ticks_msec() / 1000.0 - float(h.fxs["volley_cast"]) < 2.5

## A puppet's shot has no skill id on the wire: the Fire Arrow's "cast" event marks the next shot his.
static func _puppet_fire(h: Hero) -> bool:
	return h.fxs.has("fire_cast") and Time.get_ticks_msec() / 1000.0 - float(h.fxs["fire_cast"]) < 2.5

static func clear(h: Hero) -> void:
	Archer.clear(h)

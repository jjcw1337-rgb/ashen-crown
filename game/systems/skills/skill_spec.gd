class_name SkillSpec
extends RefCounted
## The skill format, the Path of Exile way (docs/content/skills.md, "Designing a skill"): a skill's timing, damage, area and damage over
## time are fields of its `Data.SKILLS` entry, so a skill is tuned in data.gd alone. Every field is optional: a skill
## without "use" keeps the timing its class script gives it, one without "area" or "dmg" deals what its script deals.
##   "style":  the animation its use plays (an Anim / Net.STYLES style); its "hit" is that style's impact frame
##   "use":    seconds to perform it at normal speed (final: Data.ATTACK_PACE isn't applied on top)
##   "hit":    when it lands, 0..1 of "use" (quick ~0.45, heavy ~0.75: the wind-up the foes can read)
##   "speed":  "attack" or "cast", what shortens it (cast speed is attack speed until it has its own stat)
##   "lock":   seconds on top that no speed shortens
##   "cancel": false = the dodge roll can't break it before it lands (default true)
##   "dmg":    % of weapon damage; "base": [min, max] and "per_lvl": a spell's own damage (no weapon), added
##   "type":   "phys" | "fire" | "cold" | "lightning" | "poison": the numbers' colour (resistances later)
##   "knock":  knockback on each foe struck
##   "area":   {"shape": "wedge", "r", "angle"} ahead | {"shape": "circle", "r", "at": "self" | "aim"} |
##             {"shape": "line", "r", "w"} ahead | {"shape": "single", "r"} (the nearest in front)
##   "dot":    {"kind": "burn", "pct": % of the hit dealt over "secs"} | {"kind": "chill" | "slow", "k": 0..1, "secs"};
##             one per source on a foe, refreshed, never stacked
##   "tags":   ["attack", "spell", "melee", "slam", "heavy", "fire", ...], for talents and supports to pick skills by
##   "pvp":    numbers for its blows on players in the Battlegrounds, read by the class's script ("dmg": the share of
##             what it deals monsters; a status's seconds; the Demon's are listed in DemonSkills)
##   "role":   its one job in the class's kit, in a few words ("Burst finisher", "Pick / pull"; for design and tooltips)
## A class's impact code calls `targets` and `strike` (DemonSkills' Molten Fists is the example).

const TINTS := {"fire": Color(1.0, 0.55, 0.15), "cold": Color(0.55, 0.8, 1.0), "lightning": Color(0.85, 0.75, 1.0),
	"poison": Color(0.55, 0.95, 0.35)}

static var _hits := {}
static var over := {}       # tests: fields laid over a skill's data ({id: {field: value}}; Data.SKILLS is const)

static func of(id: String) -> Dictionary:
	if over.has(id):
		return Data.skill_def(id).merged(over[id], true)
	return Data.skill_def(id)

## The impact frame a skill's data gives its style (-1: none, Anim's own table decides).
static func style_hit(style: String) -> float:
	if _hits.is_empty():
		_hits["_"] = -1.0
		for s in Data.SKILLS:
			if s.has("style") and s.has("hit"):
				_hits[str(s["style"])] = float(s["hit"])
	return float(_hits.get(style, -1.0))

## Seconds the skill takes this hero to use.
static func use_time(h: Hero, id: String) -> float:
	var d := of(id)
	return float(d["use"]) / maxf(h.aspd, 0.1) + float(d.get("lock", 0.0))

## Hero.use_skill, after the class script has started the skill: the data's use time wins.
static func apply_timing(h: Hero, id: String) -> void:
	if of(id).has("use") and h.atk_skill == id and h.atk_t >= 0.0:
		h.atk_dur = use_time(h, id)

## A skill whose data says the dodge roll can't break it, still winding up.
static func uncancellable(h: Hero) -> bool:
	return h.atk_t >= 0.0 and not h.impact_done and h.atk_skill != "" and of(h.atk_skill).get("cancel", true) == false

## The foes in the skill's area. opts (talents): "r_add" metres, "angle_add" degrees; (rules that run elsewhere than
## the cast, ServerRules) "d" the way it was aimed in place of the hero's, "ok" a Callable passing only the foes it may
## strike.
static func targets(h: Hero, id: String, opts := {}) -> Array:
	var d := of(id)
	var ar: Dictionary = d.get("area", {})
	var shape := str(ar.get("shape", "single"))
	var r := float(ar.get("r", d.get("range", 2.5))) + float(opts.get("r_add", 0.0))
	var fwd: Vector3 = opts.get("d", h.aim_dir())
	var c := h.global_position
	var ok: Callable = opts.get("ok", Callable())
	if shape == "circle" and str(ar.get("at", "self")) == "aim":
		c = h.atk_aim
	var cos_half := cos(deg_to_rad((float(ar.get("angle", 90.0)) + float(opts.get("angle_add", 0.0))) * 0.5))
	var out := []
	var best = null
	var bd := 1e9
	for e in h.game.enemies_near(c, r + 2.0):
		var to: Vector3 = e.global_position - c
		to.y = 0
		var gap := to.length() - float(e.radius)
		if gap > r or (ok.is_valid() and not ok.call(e)):
			continue
		match shape:
			"wedge":
				if to.length() > 0.6 and fwd.dot(to.normalized()) < cos_half:
					continue
			"line":
				var along := to.dot(fwd)
				if along < -0.5 or (to - fwd * along).length() - float(e.radius) > float(ar.get("w", 1.2)) * 0.5:
					continue
			"single":
				if to.length() > 0.6 and fwd.dot(to.normalized()) < 0.5:
					continue
				if gap < bd:
					bd = gap
					best = e
				continue
		out.append(e)
	if shape == "single":
		return [best] if best != null else []
	return out

## A spell's own damage ("base" + "per_lvl" by level), before the hero's multipliers.
static func spell_damage(h: Hero, id: String) -> float:
	var d := of(id)
	if not d.has("base"):
		return 0.0
	var b: Array = d["base"]
	return randf_range(float(b[0]), float(b[1])) + float(d.get("per_lvl", 0.0)) * h.level

## What one blow of the skill deals on average (for its damage over time).
static func expected(h: Hero, id: String, extra := 0.0) -> float:
	var d := of(id)
	var b: Array = d.get("base", [0.0, 0.0])
	var weapon := (h.dmg_min + h.dmg_max) * 0.5 * float(d.get("dmg", 0.0)) / 100.0 * h.buff_mult()
	return (weapon + extra + (float(b[0]) + float(b[1])) * 0.5 + float(d.get("per_lvl", 0.0)) * h.level) * h.dmg_mult(id)

## One foe struck: its damage (the weapon's % and/or the spell's own, plus `extra`, a class's own part such as the
## Demon's magma), in its type's colour, and its damage over time. opts: "knock", "dot_secs" (a multiplier, talents),
## "mult" (on everything this blow deals and its burn: a bonus on this one foe, e.g. the Demon's Brand), "dot": false
## (none: the skill sends its own to a player, PvpStatus).
static func strike(h: Hero, id: String, e, extra := 0.0, opts := {}) -> void:
	if not is_instance_valid(e) or e.dead:
		return
	var d := of(id)
	var k := float(opts.get("mult", 1.0))
	var tint: Color = TINTS.get(str(d.get("type", "phys")), Color(0, 0, 0, 0))
	if tint.a > 0.0:
		e.dmg_tint = tint
	h._hit_enemy(e, float(d.get("dmg", 0.0)) / 100.0 * k, float(opts.get("knock", d.get("knock", 0.0))), id, (extra + spell_damage(h, id)) * k)
	if is_instance_valid(e):
		e.dmg_tint = Color(0, 0, 0, 0)
	var dt: Dictionary = d.get("dot", {})
	if dt.is_empty() or not opts.get("dot", true) or not is_instance_valid(e) or e.dead:
		return
	var secs := float(dt.get("secs", 3.0))
	var last := secs * float(opts.get("dot_secs", 1.0))
	match str(dt.get("kind", "burn")):
		"burn":
			e.ignite(expected(h, id, extra) * k * float(dt.get("pct", 25.0)) / 100.0 / secs, last)
		"chill":
			e.chill(float(dt.get("k", 0.3)), last)
		"slow":
			e.slow(last, float(dt.get("k", 0.3)))

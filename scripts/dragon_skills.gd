class_name DragonSkills
extends RefCounted
## The dragon classes' skills (Obsidian Wyrm "wyrm", Frost Serpent "serpent", Storm Wyvern "wyvern"). The Storm
## Wyvern's Storm Arc (jj): it rears and breathes chain lightning from its jaws (SharedSkills.chain, WYVERN_JUMPS
## leaps; the look is ArcFx's, its wings crackling); the others have none yet.
## For now a dragon has only the common Attack (left mouse: the hero's three-swipe combo, which Dragon.pose shows as
## a foreclaw rake, a bite and a tail spin) and Block; this script plays their own sounds for the attack.
##
## Ready for skills (see CLAUDE.md "Adding a class"): add Data.SKILLS entries with "cls" set to the dragon's id and
## an "aim", then handle their ids below (cast -> h._start_attack(style, id, seconds); impact on Anim.impact_at of
## the style; state on the hero in one dictionary, e.g. `h.set_meta("drg", {...})` or a new `Hero.dg`); Dragon.pose
## already plays any unknown attack style as a roar with the wings flared, so a new skill animates before it has a
## pose of its own. Effects go in a DragonFx.play(h, ev) handler added to SkillFx.play's match.

static func is_mine(h: Hero) -> bool:
	return Dragon.is_dragon(h.cls)

static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	return true

const WYVERN_JUMPS := 4
## Frost Breath: its ticks while the jaws are open (of the breath's progress), every BREATH_TICK s
const BREATH_OPEN := Vector2(0.15, 0.9)
const BREATH_TICK := 0.2

static func cast(h: Hero, id: String, _aim: Vector3) -> void:
	if id == "storm_arc":
		h._start_attack("cast", id)
		h.moving = false
		h.path = PackedVector3Array()
	elif id == "frost_breath":
		h._start_attack("breath", id)
		h.moving = false
		h.path = PackedVector3Array()
		h.set_meta("breath_tick", 0.0)

static func impact(h: Hero) -> bool:
	if is_mine(h) and h.atk_skill == "frost_breath":
		return true         # (its damage comes in ticks while it breathes: update)
	if not is_mine(h) or h.atk_skill != "storm_arc":
		return false
	var pts := SharedSkills.chain(h, "storm_arc", jaws(h), WYVERN_JUMPS)
	h.fx("storm_arc", "impact", {"ps": pts, "d": h.aim_dir()})
	return true

## Where a dragon's breath leaves it: in front of its head.
static func jaws(h: Hero) -> Vector3:
	var J: Dictionary = h.rig.get_meta("j") if h.rig != null and h.rig.has_meta("j") else {}
	var hd = J.get("at_head", J.get("head"))
	if hd is Node3D and is_instance_valid(hd):
		return (hd as Node3D).global_position + h.facing() * 0.5
	return h.global_position + Vector3(0, 2.0, 0) + h.facing() * 1.2

## Frost Breath's ticks: cold damage and a chill on everything in the cone (SkillSpec: its "area" and "dot"), every
## BREATH_TICK s while the jaws are open. Only the breather's own game deals it (a puppet has no attack running).
static func update(h: Hero, delta: float) -> void:
	if h.puppet or not is_mine(h) or h.atk_t < 0.0 or h.atk_skill != "frost_breath":
		return
	var a := h.atk_t / maxf(h.atk_dur, 0.001)
	if a < BREATH_OPEN.x or a > BREATH_OPEN.y:
		return
	var tk: float = float(h.get_meta("breath_tick", 0.0)) - delta
	if tk <= 0.0:
		tk = BREATH_TICK
		for e in SkillSpec.targets(h, "frost_breath"):
			SkillSpec.strike(h, "frost_breath", e)
	h.set_meta("breath_tick", tk)

static func rooted(_h: Hero) -> bool:
	return false

static func clear(_h: Hero) -> void:
	pass

static func died(h: Hero) -> void:
	if is_mine(h) and h.rig != null and h.rig.is_inside_tree():
		Sfx.play_at(h.cls + "_roar", h.global_position, -6.0, 0.8)    # a last roar under the death cry

## The basic attack's sounds, each landing on its impact frame: claw, bite, tail spin.
static func sound(h: Hero, skill: String, at: float) -> bool:
	if is_mine(h) and skill == "storm_arc":
		Sfx.play(h.cls + "_roar", -8.0, 1.15)
		Sfx.play_synced("arc_zap", at, -2.0)
		return true
	if not is_mine(h) or skill != "":
		return false
	match h.atk_style:
		"swipe1":
			Sfx.play_synced(h.cls + "_claw", at, -2.0)
		"swipe2":
			Sfx.play_synced(h.cls + "_bite", at, -2.0)
		"swipe3":
			Sfx.play_synced(h.cls + "_tail", at, -1.0)
			Sfx.play(h.cls + "_roar", -12.0, 1.1)
		_:
			return false
	return true

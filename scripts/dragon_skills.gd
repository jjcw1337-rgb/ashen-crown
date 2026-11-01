class_name DragonSkills
extends RefCounted
## The dragon classes' skills (Obsidian Wyrm "wyrm", Frost Serpent "serpent", Storm Wyvern "wyvern"): none yet.
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

static func cast(_h: Hero, _id: String, _aim: Vector3) -> void:
	pass

static func impact(_h: Hero) -> bool:
	return false

static func update(_h: Hero, _delta: float) -> void:
	pass

static func rooted(_h: Hero) -> bool:
	return false

static func clear(_h: Hero) -> void:
	pass

static func died(h: Hero) -> void:
	if is_mine(h) and h.rig != null and h.rig.is_inside_tree():
		Sfx.play_at(h.cls + "_roar", h.global_position, -6.0, 0.8)    # a last roar under the death cry

## The basic attack's sounds, each landing on its impact frame: claw, bite, tail spin.
static func sound(h: Hero, skill: String, at: float) -> bool:
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

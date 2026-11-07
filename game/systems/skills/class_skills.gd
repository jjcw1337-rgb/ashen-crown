class_name ClassSkills
extends RefCounted
## The one place Hero hands a class's skills to that class's own script. Hero.use_skill, _impact, _process,
## take_hit, set_class and new_character call in here; nothing in hero.gd names a class's skill ids.
##
## Every class's skills script (KnightSkills, Wraith, Demon, WarlockSkills, Archer, Plague) has
## the same static functions:
##   can_cast(h, id, aim) -> bool   checks before mana and the cooldown are spent (shows its own message on false)
##   cast(h, id, aim)               starts the skill: usually h._start_attack(style, id[, seconds])
##   impact(h) -> bool              the attack's impact frame; true when h.atk_skill (or a weapon style) was its own
##   update(h, delta)               every frame on the local hero, whatever his class (each looks after its own state)
##   rooted(h) -> bool              a skill of his that holds him in place right now
##   clear(h)                       drops everything of the class's (a class change, a new character)
##   died(h)                        what ends when he dies
##   sound(h, skill, at) -> bool    the cast's sound, timed to land at `at` seconds (Sfx.play_synced); true if handled
## A class whose skills are objects (Skill, game/systems/skills/skill.gd: one per skill id in Hero.kit) has them run
## here once, whatever the class: their update, rooted, died and clear go with the calls above.
##
## Adding a class: write `scripts/<class>_skills.gd` with those functions (start from
## `tools/templates/new_class_skills.gd`) and add it to `of` and `all` below. Its effects go in `<Class>Fx.play`
## (SkillFx), its numbers and text in its codex file. See docs/content/heroes.md.

## The skills script for a class, or null. ADD NEW CLASSES HERE (and in `all`).
static func of(cls: String):
	match cls:
		"knight": return KnightSkills
		"wraith": return Wraith
		"demon": return Demon
		"warlock": return WarlockSkills
		"archer": return Archer
		"plague": return Plague
		"doug": return Doug
		"wyrm", "serpent", "wyvern": return DragonSkills
		"any": return SharedSkills       # the shared skills (Data.SKILLS "cls": "any")
	return null

## Every class's skills script (update/clear/died run on all of them: each looks after its own state).
static func all() -> Array:
	return [KnightSkills, Wraith, Demon, WarlockSkills, Archer, Plague, Doug, DragonSkills, SharedSkills]

## The class a skill id belongs to ("any" for the common Attack and Block).
static func owner(id: String) -> String:
	return str(Data.skill_def(id).get("cls", "any"))

static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	var m = of(owner(id))
	return m == null or m.can_cast(h, id, aim)

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var m = of(owner(id))
	if m != null:
		m.cast(h, id, aim)

## The impact frame: the hero's own class first (a bow shot, a cane blow's skill, a skill), then the rest (each
## only answers for its own ids, so a skill still in flight right after a class change is still dealt).
static func impact(h: Hero) -> bool:
	var mine = of(h.cls)
	if mine != null and mine.impact(h):
		return true
	for m in all():
		if m != mine and m.impact(h):
			return true
	return false

static func update(h: Hero, delta: float) -> void:
	for m in all():
		m.update(h, delta)
	# the skill objects (Hero.kit): on the hero's own game only, since a partner's copy of him only shows them
	if not h.puppet:
		Skill.update_kit(h, delta)

static func rooted(h: Hero) -> bool:
	for m in all():
		if m.rooted(h):
			return true
	for sk in h.kit.values():
		if sk.rooted():
			return true
	return false

static func clear(h: Hero) -> void:
	for m in all():
		m.clear(h)
	for sk in h.kit.values():
		sk.clear()
	h.kit.clear()

static func died(h: Hero) -> void:
	for m in all():
		m.died(h)
	for sk in h.kit.values():
		sk.died()

static func sound(h: Hero, skill: String, at: float) -> bool:
	var m = of(h.cls)
	return m != null and m.sound(h, skill, at)

# ---------------------------------------------------------------- optional hooks
## A class's script may also have any of these (Hero asks; without one, nothing changes). They keep a class's
## own ways out of hero.gd: the archer's bow shot, reach, pace and bow posing are his script's answers; the Warlock's
## Drain Life channel, her shield and her body's glow are hers.

## Its own basic attack in place of the weapon swing (the archer's bow shot). True when it took it.
static func attack(h: Hero, aim: Vector3, keep_target: bool) -> bool:
	var m = of(h.cls)
	return m != null and m.has_method("attack") and m.attack(h, aim, keep_target)

## A free copy of one of the hero's skills (a rite's), when the class has skill objects (Hero.kit) and that skill
## has one. True if it was cast.
static func free_cast(h: Hero, id: String, aim: Vector3) -> bool:
	var m = of(h.cls)
	if m == null or not m.has_method("skill"):
		return false
	var s = m.skill(h, id)
	return s != null and s.free_cast(aim)

## How far its basic attack reaches (-1: the usual melee reach).
static func reach(h: Hero) -> float:
	var m = of(h.cls)
	return float(m.reach(h)) if m != null and m.has_method("reach") else -1.0

## Its walking pace, times the usual (the archer's 10% beside his wolf).
static func pace(h: Hero) -> float:
	var m = of(h.cls)
	return float(m.pace(h)) if m != null and m.has_method("pace") else 1.0

## Nothing stops or moves the hero right now: stuns and slows don't take (Doug in his clown car, the Demon's Crucible;
## Hero.take_hit, PvpStatus).
static func unstoppable(h: Hero) -> bool:
	var m = of(h.cls)
	return m != null and m.has_method("unstoppable") and bool(m.unstoppable(h))

## Its pace while attacking, times the usual (-1: everyone's slight slowing mid-swing).
static func attack_pace(h: Hero) -> float:
	var m = of(h.cls)
	return float(m.attack_pace(h)) if m != null and m.has_method("attack_pace") else -1.0

## After the body's pose each frame, on the hero and his partners' copies (the archer's bow and string).
static func posed(h: Hero, st: Dictionary) -> void:
	var m = of(h.cls)
	if m != null and m.has_method("posed"):
		m.posed(h, st)

## Every frame on a partner's copy of the hero (the archer's wolf, which every game runs).
static func puppet_update(h: Hero, delta: float) -> void:
	var m = of(h.cls)
	if m != null and m.has_method("puppet_update"):
		m.puppet_update(h, delta)

## A held channel (Hero.channel_t >= 0: Drain Life), every frame where an attack would update: it keeps it going or
## ends it (Hero.end_channel).
static func channel(h: Hero, delta: float) -> void:
	var m = of(h.cls)
	if m != null and m.has_method("channel"):
		m.channel(h, delta)
	else:
		h.channel_t = -1.0

## The channel lets go (a move, a click, another skill, a dodge, death).
static func end_channel(h: Hero) -> void:
	var m = of(h.cls)
	if m != null and m.has_method("end_channel"):
		m.end_channel(h)
	h.channel_t = -1.0

## A blow's damage after the class's own ward has soaked what it can (after armour; Hero.take_hit).
static func absorb(h: Hero, dmg: float) -> float:
	var m = of(h.cls)
	return float(m.absorb(h, dmg)) if m != null and m.has_method("absorb") else dmg

## A skill pressed again mid-skill (the Demon's Crucible ends early): true when the class took the press.
static func recast(h: Hero, id: String) -> bool:
	var m = of(h.cls)
	return m != null and m.has_method("recast") and m.recast(h, id)

## One stage of a skill of several clips has ended (Hero._update_attack): the class starts what follows it.
static func stage_done(h: Hero, style: String, skill: String) -> void:
	var m = of(h.cls)
	if m != null and m.has_method("stage_done"):
		m.stage_done(h, style, skill)

## The node the weapon hangs from, when the class holds it its own way (the ranger's bow in his left hand); else null.
static func weapon_hand(h: Hero, J: Dictionary) -> Node3D:
	var m = of(h.cls)
	return m.weapon_hand(h, J) if m != null and m.has_method("weapon_hand") else null

## Its weapon swing's blows, dealt its own way in place of Hero's (the plague doctor's cane: each blow leaves its
## mark, and in a match his blows are decided on the server). True when it dealt them.
static func swing(h: Hero, style: String) -> bool:
	var m = of(h.cls)
	return m != null and m.has_method("swing") and m.swing(h, style)

## How much of a blow on the hero gets through (the plague doctor's Transfusion soaks part of it).
static func taken(h: Hero, dmg: float) -> float:
	var m = of(h.cls)
	return float(m.taken(h, dmg)) if m != null and m.has_method("taken") else dmg

## Before the body's pose each frame, on the hero himself: a pose of its own while he stands about (the plague
## doctor peering at a vial).
static func pose(h: Hero, st: Dictionary, delta: float) -> void:
	var m = of(h.cls)
	if m != null and m.has_method("pose"):
		m.pose(h, st, delta)

## Its hands are on a skill: the weapon is put away meanwhile (the plague doctor's vials, censer and reliquary).
static func hands_busy(h: Hero) -> bool:
	var m = of(h.cls)
	return m != null and m.has_method("hands_busy") and m.hands_busy(h)

## A monster at `at` can't see the hero (the plague doctor in his fog). Asked on the game running the monsters.
static func hidden_from_monster(h: Hero, at: Vector3) -> bool:
	var m = of(h.cls)
	return m != null and m.has_method("hidden_from_monster") and m.hidden_from_monster(h, at)

## PvP: where the hero's breakable thing `oid` is (PvpObjects: the plague doctor's bloom, vat and creature), or null.
static func obj_pos(h: Hero, oid: int) -> Variant:
	var m = of(h.cls)
	return m.obj_pos(h, oid) if m != null and m.has_method("obj_pos") else null

## PvP: another player's blow on one of the hero's things, on the hero's own game (PvpObjects).
static func obj_hit(h: Hero, oid: int, attacker: int) -> void:
	var m = of(h.cls)
	if m != null and m.has_method("obj_hit"):
		m.obj_hit(h, oid, attacker)

## The weapon trail's colour for a class (a unique weapon's glow overrides it, Hero._start_attack).
static func trail_color(cls: String, skill: String) -> Color:
	match cls:
		"archer": return Archer.HUNTER
		"plague": return Plague.TOXIC
		"doug": return Doug.ACCENT
		"wraith": return WraithFx.SPIRIT
		"demon": return DemonFx.EMBER
		"warlock": return Warlock.FEL
		"wyrm": return Color(1.0, 0.42, 0.15)
		"serpent": return Color(0.55, 0.9, 1.0)
		"wyvern": return Color(0.55, 0.95, 0.9)
	return Color(1.0, 0.85, 0.5) if skill == "cleave" else Color(0.85, 0.9, 1.0)

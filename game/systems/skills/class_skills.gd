class_name ClassSkills
extends RefCounted
## The one place Hero hands a class's skills to that class's own script. Hero.use_skill, _impact, _process,
## take_hit, set_class and new_character call in here; nothing in hero.gd names a class's skill ids.
##
## Every class's skills script (KnightSkills, WraithSkills, DemonSkills, WarlockSkills, Archer, PlagueSkills) has
## the same static functions:
##   can_cast(h, id, aim) -> bool   checks before mana and the cooldown are spent (shows its own message on false)
##   cast(h, id, aim)               starts the skill: usually h._start_attack(style, id[, seconds])
##   impact(h) -> bool              the attack's impact frame; true when h.atk_skill (or a weapon style) was its own
##   update(h, delta)               every frame on the local hero, whatever his class (each looks after its own state)
##   rooted(h) -> bool              a skill of his that holds him in place right now
##   clear(h)                       drops everything of the class's (a class change, a new character)
##   died(h)                        what ends when he dies
##   sound(h, skill, at) -> bool    the cast's sound, timed to land at `at` seconds (Sfx.play_synced); true if handled
##
## Adding a class: write `scripts/<class>_skills.gd` with those functions (start from
## `tools/templates/new_class_skills.gd`) and add it to `of` and `all` below. Its effects go in `<Class>Fx.play`
## (SkillFx), its numbers and text in its codex file. See docs/content/heroes.md.

## The skills script for a class, or null. ADD NEW CLASSES HERE (and in `all`).
static func of(cls: String):
	match cls:
		"knight": return KnightSkills
		"wraith": return WraithSkills
		"demon": return DemonSkills
		"warlock": return WarlockSkills
		"archer": return Archer
		"plague": return PlagueSkills
		"doug": return Doug
		"wyrm", "serpent", "wyvern": return DragonSkills
		"any": return SharedSkills       # the shared skills (Data.SKILLS "cls": "any")
	return null

## Every class's skills script (update/clear/died run on all of them: each looks after its own state).
static func all() -> Array:
	return [KnightSkills, WraithSkills, DemonSkills, WarlockSkills, Archer, PlagueSkills, Doug, DragonSkills, SharedSkills]

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
		# a class whose skills are objects (Hero.kit) ticks them in its update: its own heroes only, so a kit is
		# ticked once a frame
		if m.has_method("skill") and m != of(h.cls):
			continue
		m.update(h, delta)

static func rooted(h: Hero) -> bool:
	for m in all():
		if m.rooted(h):
			return true
	return false

static func clear(h: Hero) -> void:
	for m in all():
		m.clear(h)

static func died(h: Hero) -> void:
	for m in all():
		m.died(h)

static func sound(h: Hero, skill: String, at: float) -> bool:
	var m = of(h.cls)
	return m != null and m.sound(h, skill, at)

# ---------------------------------------------------------------- optional hooks
## A class's script may also have any of these (Hero asks; without one, nothing changes). They keep a class's
## own ways out of hero.gd: the archer's bow shot, reach, pace and bow posing are his script's answers.

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

## A skill of its makes the hero shrug off stuns and slows right now (Doug in his clown car): Hero.take_hit.
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

## The node the weapon hangs from, when the class holds it its own way (the ranger's bow in his left hand); else null.
static func weapon_hand(h: Hero, J: Dictionary) -> Node3D:
	var m = of(h.cls)
	return m.weapon_hand(h, J) if m != null and m.has_method("weapon_hand") else null

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

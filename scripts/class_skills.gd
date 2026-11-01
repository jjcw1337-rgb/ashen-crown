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
## (SkillFx), its tuning in Data.SKILLS. See CLAUDE.md, "Adding a class".

## The skills script for a class, or null. ADD NEW CLASSES HERE (and in `all`).
static func of(cls: String):
	match cls:
		"knight": return KnightSkills
		"wraith": return WraithSkills
		"demon": return DemonSkills
		"warlock": return WarlockSkills
		"archer": return Archer
		"plague": return PlagueSkills
	return null

## Every class's skills script (update/clear/died run on all of them: each looks after its own state).
static func all() -> Array:
	return [KnightSkills, WraithSkills, DemonSkills, WarlockSkills, Archer, PlagueSkills]

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

## The weapon trail's colour for a class (a unique weapon's glow overrides it, Hero._start_attack).
static func trail_color(cls: String, skill: String) -> Color:
	match cls:
		"archer": return Archer.HUNTER
		"plague": return Plague.TOXIC
		"wraith": return WraithFx.SPIRIT
		"demon": return DemonFx.EMBER
		"warlock": return Warlock.FEL
	return Color(1.0, 0.85, 0.5) if skill == "cleave" else Color(0.85, 0.9, 1.0)

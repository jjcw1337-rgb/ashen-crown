class_name Heroes
extends RefCounted
## The hero registry: for each class, the script that is its kit (its skills, which ClassSkills routes every call to)
## and the one that draws its fx events (SkillFx). The shared code asks here and names no hero. Each is loaded the
## first time it's asked for, so nothing ties the shared code to a hero when scripts compile.
## Adding a hero: its folder (docs/content/heroes.md) and one line here.

## class -> [its kit script, its look script ("" when it has none of its own)], in the order heroes are run each frame
const HEROES := {
	"knight": ["res://game/heroes/knight/knight_skills.gd", "res://game/heroes/knight/knight_fx.gd"],
	"wraith": ["res://game/heroes/wraith/wraith.gd", "res://game/heroes/wraith/wraith_fx.gd"],
	"demon": ["res://game/heroes/demon/demon.gd", "res://game/heroes/demon/demon_fx.gd"],
	"warlock": ["res://game/heroes/warlock/warlock_skills.gd", "res://game/heroes/warlock/warlock_fx.gd"],
	"archer": ["res://game/heroes/archer/archer.gd", "res://game/heroes/archer/archer_fx.gd"],
	"plague": ["res://game/heroes/plague/plague.gd", "res://game/heroes/plague/plague_fx.gd"],
	"doug": ["res://game/heroes/doug/doug.gd", "res://game/heroes/doug/doug_fx.gd"],
	"necromancer": ["res://game/heroes/necromancer/necromancer.gd", "res://game/heroes/necromancer/necromancer_fx.gd"],
	"wyrm": ["res://game/heroes/wyrm/wyrm.gd", ""],
	"serpent": ["res://game/heroes/serpent/serpent.gd", "res://game/heroes/serpent/serpent_fx.gd"],
	"wyvern": ["res://game/heroes/wyvern/wyvern.gd", "res://game/heroes/wyvern/wyvern_fx.gd"],
}

## Classes whose lingering looks outlive a death or a class change: they clear themselves (the Plague Doctor's pools
## and blooms), so SkillFx.clear leaves them.
const KEEP_FX := ["plague"]

static var _loaded := {}

static func _script(path: String):
	if path == "":
		return null
	if not _loaded.has(path):
		_loaded[path] = load(path)
	return _loaded[path]

## The class's kit script, or null.
static func kit(cls: String):
	return _script(str(HEROES[cls][0])) if HEROES.has(cls) else null

## The script that draws the class's fx events, or null.
static func fx(cls: String):
	return _script(str(HEROES[cls][1])) if HEROES.has(cls) else null

## Every hero's kit script, in order.
static func kits() -> Array:
	var out := []
	for c in HEROES:
		out.append(kit(c))
	return out

## Every hero's look script that has one, in order (`keep`: with the ones that clear themselves).
static func fxs(keep := true) -> Array:
	var out := []
	for c in HEROES:
		var f = fx(c)
		if f != null and (keep or not KEEP_FX.has(c)):
			out.append(f)
	return out

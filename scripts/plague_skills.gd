class_name PlagueSkills
extends RefCounted
## The Plague Doctor's side of ClassSkills (see class_skills.gd). His skills live in plague.gd: the casts and
## releases are Plague.cast / Plague.impact, and everything that lingers (flasks in the air, clouds, fuses, traps,
## poison, infection, the dome) belongs to the hero's own Plague object, Hero.pd (made with his body in
## Hero._build_rig; a partner's puppet has a "ghost" one that only shows them).

static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	return true

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	Plague.cast(h, id, aim)

static func impact(h: Hero) -> bool:
	return Plague.impact(h)

static func update(h: Hero, delta: float) -> void:
	if h.pd != null:
		h.pd.update(delta)

static func rooted(_h: Hero) -> bool:
	return false

## His flasks, clouds, traps and dome go (a class change also drops Hero.pd itself, Hero.set_class).
static func clear(h: Hero) -> void:
	if h.pd != null:
		h.pd.clear()

## His clouds and poisons outlive him, as before.
static func died(_h: Hero) -> void:
	pass

## The casts' sounds, timed to their release (`at` seconds from now).
static func sound(_h: Hero, skill: String, at: float) -> bool:
	match skill:
		"toxic": Sfx.play_synced("swing_light", at - 0.05, -4.0, 0.85)
		"volatile":
			Sfx.play_synced("fuse", at * 0.5, -6.0, 1.2)
			Sfx.play_synced("swing", at - 0.05, -3.0, 0.8)
		"trap": Sfx.play_synced("equip", at, -4.0, 0.8)
		"epidemic": Sfx.play_synced("swing_heavy", at - 0.08, -3.0, 0.75)
		_: return false
	return true

class_name PlagueSkills
extends RefCounted
## The Plague Doctor's side of ClassSkills (see class_skills.gd). His skills live in plague.gd: the casts and
## releases are Plague.cast / Plague.impact, and everything that lingers (vials in the air, pools, the swarm, blooms,
## fog, the apparatus, the experiment, poison and Blight) belongs to the hero's own Plague object, Hero.pd (made with his body in
## Hero._build_rig; a partner's puppet has a "ghost" one that only shows them).

static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	return Plague.can_cast(h, id, aim)

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var t0 := FxTiming.t()
	Plague.cast(h, id, aim)
	FxTiming.done(t0, "plague cast " + id)

static func impact(h: Hero) -> bool:
	var t0 := FxTiming.t()
	var r := Plague.impact(h)
	FxTiming.done(t0, "plague impact")
	return r

static func update(h: Hero, delta: float) -> void:
	if h.pd != null:
		var t0 := FxTiming.t()
		h.pd.update(delta)
		FxTiming.done(t0, "plague update")

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
		"swarm": Sfx.play_synced("swing_light", at - 0.05, -6.0, 0.6)
		"bloom": Sfx.play_synced("equip", at, -4.0, 0.7)
		"fog": Sfx.play_synced("swing", at - 0.05, -4.0, 0.9)
		"transfusion": Sfx.play_synced("equip", at, -6.0, 1.3)
		"experiment": Sfx.play_synced("swing_heavy", at - 0.08, -3.0, 0.7)
		_: return false
	return true

## Old saves' bindings of Volatile Mixture, Pestilent Trap and The Last Epidemic become Swarmcraft, Corpse Bloom and
## The Last Experiment (Plague.OLD_IDS; Hero.from_save).
static func migrate_binds(binds: Dictionary) -> void:
	for k in binds.keys():
		var id := str(binds[k])
		if Plague.OLD_IDS.has(id):
			binds[k] = Plague.OLD_IDS[id]

class_name DemonBrand
extends DemonSkill
## The Brand, the mark his skills share (Hero.kit "brand", made by Demon.brands): Infernal Charge, Fault of the Pit
## and Brimstone Hurl brand what they strike; Molten Fists, Hellgrip and Hellbrand Detonation spend it. It is rules
## state, kept where his hits are decided: on a monster here, on a player too (the server tells them they carry it,
## PvpStatus "brand", and every game draws it from the fx event: BrandFx). Its length is Molten Fists' codex
## "brand_s".

## Who carries it: foe's instance id -> when it fades (his anim_time).
var marks := {}

func secs() -> float:
	return Skill.num("fists", "brand_s", 4.0)

## Brands a foe (shown on everyone's screen).
func mark(e) -> void:
	var h := hero
	if e == null or not is_instance_valid(e) or e.dead:
		return
	marks[e.get_instance_id()] = h.anim_time + secs()
	if PvpStatus.is_player(e):
		PvpStatus.send(h.game, e, "brand", secs())
		h.fx("fists", "brand", {"pid": int(e.pvp_pid), "x": secs()})
	else:
		h.fx("fists", "brand", {"t": [e], "x": secs()})

func has(e) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	return float(marks.get(e.get_instance_id(), -1.0)) > hero.anim_time

## Spends it (Molten Fists' bonus, Hellgrip's refund, the Detonation).
func spend(e) -> void:
	if e != null and is_instance_valid(e):
		marks.erase(e.get_instance_id())

func update(_delta: float) -> void:
	for k in marks.keys():
		if float(marks[k]) <= hero.anim_time:
			marks.erase(k)

func clear() -> void:
	marks.clear()

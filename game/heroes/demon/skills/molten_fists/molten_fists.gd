class_name MoltenFists
extends DemonSkill
## Molten Fists (Q, "fists", the burst finisher; jj, 2026-11-01): a slow, heavy two-fisted blow on the skill format
## (its timing, wedge, damage and burn are its Data.SKILLS entry, SkillSpec), with his magma on top; a Branded foe
## takes more and loses the Brand (a player: its "pvp" share). Wide Fists (fists_wide) reaches further and wider and
## burns longer. Its look: MoltenFistsFx ("Hellbrand"). Codex "k": magma (% of his magma), brand_bonus (% more on
## the Branded), brand_s (how long the Brand lasts, for every skill that brands), wide_r and wide_angle (Wide Fists'
## metres and degrees).

func cast(_aim: Vector3) -> void:
	start("fists")

## The wedge's reach and half-angle (its data's area), for the look too.
static func reach(wide: bool) -> float:
	return float(Data.skill_def("fists").get("area", {}).get("r", 3.4)) + (Skill.num("fists", "wide_r", 1.0) if wide else 0.0)

static func half_angle() -> float:
	return float(Data.skill_def("fists").get("area", {}).get("angle", 84.0)) * 0.5

## The blow lands: his own game shows it at once; its rules strike the wedge (here, or on the match server).
func impact() -> void:
	var h := hero
	var wide := h.talent("fists_wide") > 0.0
	var d := {"p": h.global_position, "d": h.aim_dir(), "y": h.rig.global_rotation.y, "x": wide}
	if not deals():
		h.fx(id, "impact", {"y": d["y"], "r": reach(wide)})      # (who it caught comes from the server: "struck")
	make("blow", d)

## Server: the blow where it has him, with his talents.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "blow" or not (d.get("p") is Vector3 and d.get("d") is Vector3):
		return false
	if (d["p"] as Vector3).distance_to(hero.global_position) > 4.0:
		return false
	d["d"] = ((d["d"] as Vector3) * Vector3(1, 0, 1)).normalized()
	d["x"] = hero.talent("fists_wide") > 0.0
	d["y"] = float(d.get("y", 0.0))
	return true

## Everything in the wedge struck and set alight; the Branded take more and lose the Brand.
func made(kind: String, d: Dictionary) -> void:
	if kind != "blow":
		return
	var h := hero
	var wide := bool(d["x"])
	var brand := Demon.brands(h)
	var lit := []
	var opts := {"r_add": Skill.num(id, "wide_r", 1.0) if wide else 0.0, "angle_add": Skill.num(id, "wide_angle", 24.0) if wide else 0.0,
		"at": d["p"], "fwd": d["d"]}
	for e in SkillSpec.targets(h, id, opts):
		if not foe(e):
			continue
		var k := 1.0
		if brand.has(e):
			k += pvp("brand_bonus", 0.2) if PvpStatus.is_player(e) else val("brand_bonus", 30.0) / 100.0
			brand.spend(e)
			if PvpStatus.is_player(e):
				h.fx(id, "consume", {"pid": int(e.pvp_pid)})
			else:
				h.fx(id, "consume", {"t": [e]})
		_strike(e, magma(h, val("magma", 50.0) / 100.0), {"mult": k, "dot_secs": 2.0 if wide else 1.0})
		if is_instance_valid(e) and not e.dead and not PvpStatus.is_player(e):
			lit.append(e)
	if h.puppet:
		h.fx(id, "struck", {"t": lit})       # (the server's copy: his game showed the blow itself)
	else:
		h.fx(id, "impact", {"y": float(d["y"]), "r": reach(wide), "t": lit})

## One foe struck (SkillSpec: its "dmg", "knock", "type" and "dot" are its data; `extra` his magma). A player's
## stand-in takes its PvP share with no knockback, and its burn through the server; a monster through SkillSpec.strike.
## opts: SkillSpec.strike's ("mult", "dot_secs").
func _strike(e, extra: float, opts := {}) -> void:
	var h := hero
	if not is_instance_valid(e) or e.dead:
		return
	if not PvpStatus.is_player(e):
		SkillSpec.strike(h, id, e, extra, opts)
		return
	var d := SkillSpec.of(id)
	var k := float(opts.get("mult", 1.0))
	hit(e, float(d.get("dmg", 0.0)) / 100.0 * k, 0.0, (extra + SkillSpec.spell_damage(h, id)) * k)
	var dt: Dictionary = d.get("dot", {})
	if str(dt.get("kind", "")) == "burn" and is_instance_valid(e) and not e.dead:
		var secs := float(dt.get("secs", 3.0))
		PvpStatus.send(h.game, e, "burn", secs * float(opts.get("dot_secs", 1.0)),
			{"dps": SkillSpec.expected(h, id, extra) * k * float(dt.get("pct", 25.0)) / 100.0 / secs})

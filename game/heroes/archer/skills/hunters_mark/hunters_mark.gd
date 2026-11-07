class_name HuntersMark
extends Skill
## Hunter's Mark (a run's skill, "a_mark"): the foe nearest the pointer is marked, taking more from everyone for a
## while, and it's the one his wolf goes for. The mark is plain data on the monster ("hunted_until", "hunted_more"),
## which Enemy.take_damage reads. Its look: ArcherFx's "a_mark" (the claw mark and the ring over the foe). Codex "k":
## secs, more (% more damage taken), reach (metres from the pointer), cast_s.

func cast(aim: Vector3) -> void:
	hero.atk_aim = aim
	hero._start_attack("cast", id)
	hero.atk_dur = val("cast_s", 0.45)

func impact() -> void:
	make("mark", {"at": hero.atk_aim})

## Server: a mark within his skill's range of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "mark" and d.get("at") is Vector3 and (d["at"] as Vector3).distance_to(hero.global_position) <= float(Data.skill_def(id).get("range", 18.0)) + 4.0

## The foe nearest the point is marked (on the match server when his skills run there; it says so to everyone).
func made(kind: String, d: Dictionary) -> void:
	if kind != "mark":
		return
	var h := hero
	var at: Vector3 = d["at"]
	var reach := val("reach", 3.5)
	var best = null
	var bd := reach
	for e in h.game.enemies_near(at, reach):
		if not foe(e) or e.pvp_obj > 0:
			continue
		var dist: float = Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length()
		if dist < bd:
			bd = dist
			best = e
	if best == null:
		h.fx(id, "impact", {"p": at})
		return
	var secs := val("secs", 8.0)
	best.set_meta("hunted_until", Time.get_ticks_msec() + int(secs * 1000.0))
	best.set_meta("hunted_more", val("more", 35.0) / 100.0)
	h.mark = best
	h.mark_t = secs
	for b in h.beasts:
		if is_instance_valid(b) and not b.dead:
			b.command("attack", best)
	h.fx(id, "impact", {"p": best.global_position, "t": [best], "x": secs})

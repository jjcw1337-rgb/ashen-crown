class_name BeastCommand
extends Skill
## The Spirit Beast skill ("beast"): it commands his wolf (companion/spirit_beast.gd, always at his side): at a foe
## near the cursor it pounces and fights it; on open ground it holds that spot; on himself it comes back to his side.
## Each command rouses the hunt: the class's battle buff. His own wolf takes the command here; a partner's copy of
## his wolf takes it from the "impact" event (ArcherFx). Codex "k": buff_s (seconds of the buff), reach (metres from
## the cursor to a foe), home (metres from him that calls it back), mark_s, cast_s.

func cast(aim: Vector3) -> void:
	hero.atk_aim = aim
	hero._start_attack("cast", id)
	hero.atk_dur = val("cast_s", 0.6)

func impact() -> void:
	var h := hero
	var aim: Vector3 = h.atk_aim
	var reach := val("reach", 3.0)
	var target = null
	var bd := reach
	for e in h.game.enemies_near(aim, reach):
		var d: float = e.global_position.distance_to(aim)
		if not e.dead and d < bd:
			bd = d
			target = e
	var home: bool = target == null and aim.distance_to(h.global_position) < val("home", 2.5)
	if target != null:
		h.mark = target
		h.mark_t = val("mark_s", 8.0)
	h.buff_t = val("buff_s", 12.0) + h.talent("buff_dur")
	command(h, target, home, aim)
	h.fx(id, "impact", {"p": aim, "t": [target] if target != null else [], "x": home})
	# his wolf runs on every game, but the one that bites, and the hunt's +damage, are where his skills deal their
	# hits: the server's copy of him hears the command too
	if not deals():
		var ids: PackedInt64Array = SkillFx.encode(h.game.net, {"t": [target] if target != null else []})["t"]
		h.game.net.send_skill_make(id, "rouse", {"p": aim, "t": ids, "x": home})

## Server: the command is near where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "rouse" and d.get("p") is Vector3 and (d["p"] as Vector3).distance_to(hero.global_position) <= float(Data.skill_def(id).get("range", 20.0)) + 6.0

## The server's copy of him is roused too, so its arrows hit as hard as his, and its wolf takes the command.
func made(kind: String, d: Dictionary) -> void:
	if kind != "rouse":
		return
	var h := hero
	h.buff_t = val("buff_s", 12.0) + h.talent("buff_dur")
	var target = null
	var ids = d.get("t", [])
	if (ids is PackedInt64Array or ids is Array) and ids.size() > 0:
		target = ServerRules.foe_of(h.game, int(ids[0]))
	if target != null and not foe(target):
		target = null
	if target != null:
		h.mark = target
		h.mark_t = val("mark_s", 8.0)
	command(h, target, bool(d.get("x", false)), d.get("p", h.global_position))

## Each of his beasts takes the command (his own here; a partner's copy, in ArcherFx).
static func command(h: Hero, target, home: bool, aim: Vector3) -> void:
	for b in h.beasts:
		if not is_instance_valid(b) or b.dead:
			continue
		if target != null:
			b.command("attack", target)
		elif home:
			b.command("follow")
		else:
			b.command("hold", null, aim)

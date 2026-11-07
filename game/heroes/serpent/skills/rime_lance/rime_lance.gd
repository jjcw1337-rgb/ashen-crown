class_name RimeLance
extends DragonSkill
## Rime Lance ("s_lance", a run skill): the serpent breathes a line of ice spikes ahead: every foe on it struck and
## chilled, one already chilled frozen solid (Spear of Winter: longer, frozen longer, harder). On the breath's impact
## frame its own game makes the "lance" from where it stands, the way it aimed; the rules (here, or on the match
## server's copy of it) strike the line. A player is chilled or frozen through the server (PvpStatus). Its look:
## rime_lance_fx.gd (RimeLanceFx: "spikes"). Codex "k": len and w (metres long, and either side), dmg (% of the
## weapon's blow), chill and chill_s, freeze_s (seconds frozen).

const KNOCK := 0.6

func cast(_aim: Vector3) -> void:
	hero._start_attack("breath", id)
	halt()

func impact() -> void:
	make("lance", {"p": hero.global_position, "d": hero.aim_dir()})

func made(kind: String, d: Dictionary) -> void:
	if kind != "lance":
		return
	var h := hero
	var me: Vector3 = d["p"]
	var dv: Vector3 = d["d"]
	var ln := val("len", 10.0) * (1.0 + h.talent("lance_len") / 100.0)
	var w := val("w", 1.3)
	var hit: Array = []
	for e in h.game.enemies_near(me + dv * ln * 0.5, ln * 0.5 + 1.5):
		if not hits(e):
			continue
		var to: Vector3 = e.global_position - me
		to.y = 0
		var along := to.dot(dv)
		if along < -0.5 or along > ln + 0.5:
			continue
		if (to - dv * along).length() > w + float(e.radius):
			continue
		var was_chilled: bool = e.chill_t > 0.0
		h._hit_enemy(e, val("dmg", 125.0) / 100.0, KNOCK, id)
		if not e.dead:
			if was_chilled:
				freeze(e, val("freeze_s", 1.0) + h.talent("lance_freeze"))
			else:
				chill(e, val("chill", 0.45), val("chill_s", 3.0))
		hit.append(e)
	h.fx(id, "spikes", {"p": me, "d": dv, "x": ln, "t": hit})

## Server: a lance from where it has the serpent, aimed flat.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "lance" and flat(d, "d") and near_me(d.get("p"), 4.0)

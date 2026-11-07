class_name GaleWings
extends DragonSkill
## Gale Wings ("v_gale", a run skill): one great beat of the wyvern's wings: everything in the cone ahead is struck,
## hurled back and slowed (Hurricane: further, harder). On the cast's impact frame its own game makes the "gust" from
## where it stands, the way it aimed; the rules (here, or on the match server's copy of it) strike the cone and show it
## ("gust"). A player is slowed through the server (PvpStatus). Its look: gale_wings_fx.gd (GaleWingsFx).
## Codex "k": r (metres), half (degrees either side), dmg (% of the weapon's blow), slow (%) and slow_s.

const KNOCK := 5.0
const CLOSE := 1.2          # metres within which a foe beside it is caught whatever the way

func cast(at: Vector3) -> void:
	hero._start_attack("cast", id)
	halt()
	aim = at

func impact() -> void:
	make("gust", {"p": hero.global_position, "d": hero.aim_dir()})

func made(kind: String, d: Dictionary) -> void:
	if kind != "gust":
		return
	var h := hero
	var me: Vector3 = d["p"]
	var dv: Vector3 = d["d"]
	var r := val("r", 6.5) * (1.0 + h.talent("gale_r") / 100.0)
	var cos_half := cos(deg_to_rad(val("half", 40.0)))
	var hit: Array = []
	for e in h.game.enemies_near(me, r):
		if not hits(e):
			continue
		var to: Vector3 = e.global_position - me
		to.y = 0
		if to.length() > CLOSE and dv.dot(to.normalized()) < cos_half:
			continue
		h._hit_enemy(e, val("dmg", 100.0) / 100.0, KNOCK, id)
		if not e.dead:
			slow(e, val("slow_s", 2.5), val("slow", 40.0) / 100.0)
		hit.append(e)
	h.fx(id, "gust", {"p": me, "d": dv, "r": r, "t": hit})

## Server: a wingbeat where it has the wyvern, aimed flat.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "gust" and flat(d, "d") and near_me(d.get("p"), 4.0)

class_name BansheeWail
extends WraithSkill
## Banshee Wail (a run's skill, "r_wail"): a scream: everything round him is hurt, frozen in terror and slowed after
## (Keening: wider, longer). The scream is seen at once ("impact") and made where his hits are decided, which shows
## whom it caught ("struck"). Its look: BansheeWailFx. Codex "k": dmg (% of the weapon's blow), radius (metres),
## fear_s (seconds frozen), slow (%) and slow_s (seconds of it after).

func cast(_aim: Vector3) -> void:
	start("night_scream")

func impact() -> void:
	var h := hero
	h.fx(id, "impact", {"r": reach()})
	make("wail", {"p": h.global_position})

## How far it carries (Keening: further).
func reach() -> float:
	return val("radius", 6.0) * (1.0 + hero.talent("wail_r") / 100.0)

## Server: from where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "wail" and near_him(d.get("p"), 4.0)

func made(kind: String, d: Dictionary) -> void:
	if kind != "wail":
		return
	var h := hero
	var secs := val("fear_s", 1.2) + h.talent("wail_t")
	var caught: Array = h.game.enemies_near(d["p"], reach()).filter(func(e) -> bool: return foe(e))
	if not caught.is_empty():
		h.fx(id, "struck", {"t": caught})
	for e in caught:
		h._hit_enemy(e, val("dmg", 60.0) / 100.0, 0.8, id)
		if not e.dead:
			stun(e, secs)
			slow(e, secs + val("slow_s", 2.0), val("slow", 50.0) / 100.0)

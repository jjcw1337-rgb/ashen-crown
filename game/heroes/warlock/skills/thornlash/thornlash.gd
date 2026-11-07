class_name Thornlash
extends WarlockSpell
## Thornlash ("w_harvest", kept for saves and rites): thorned vines lash everything around her; each foe struck heals
## her a share of her life (twice that when it's the only one). Its look: WarlockHarrowFx ("sweep"). Codex "k":
## radius, dmg (% of her spell power), heal (% of her life for each foe).

func impact() -> void:
	make("lash", {"p": hero.global_position})

func made(kind: String, d: Dictionary) -> void:
	if kind != "lash":
		return
	var h := hero
	var hx := hex()
	var r := val("radius", 5.0)
	var foes: Array = h.game.enemies_near(d["p"], r).filter(func(x) -> bool: return not x.get("pvp_obj") and foe(x))
	h.fx(id, "sweep", {"r": r, "t": foes})
	var per := val("heal", 4.0) * (2.0 if foes.size() == 1 else 1.0)
	for f in foes:
		hx.hit(f, hx.amount(id, val("dmg", 180.0) / 100.0, f), WarlockHex.SHADOW_TINT)
		hx.heal(id, h.max_life * per / 100.0)

## Server: the lash where it has her.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "lash" and d.get("p") is Vector3 and (d["p"] as Vector3).distance_to(hero.global_position) <= 4.0

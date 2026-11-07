class_name LeechJar
extends PestilenceVial
## Leech Jar (a run's skill, "p_leech"): a jar thrown like Pestilence Vial (partners see the same throw, in the leech
## recipe's colour); where it lands, the vial's hit and a pool of leeches that poisons and heals him for each foe in
## it (at most max_foes count). Its look: PlagueVialFx's "throw" with k 1 (the blood and the red ring as it lands).
## Codex "k": radius, secs (Leech Pool adds to it), heal (% of his life a second for each foe), max_foes.

const RECIPE := 2      # its colour among PlagueVialFx.RECIPES

func impact() -> void:
	var from := hand()
	var to := ground(hero.atk_aim)
	var r := pool_r()
	hero.fx(id, "throw", {"p": from, "q": to, "r": r, "n": RECIPE, "x": pool_secs(), "k": 1,
		"b": hero.talent("vial_burst") > 0.0})
	make("vial", {"p": from, "q": to, "r": r})

func pool_r() -> float:
	return val("radius", 3.0)

func pool_secs() -> float:
	return val("secs", 5.0) + hero.talent("leech_t")

func land(at: Vector3, r: float) -> PlagueCloud:
	var c := super.land(at, r)
	c.leech = val("heal", 1.5) * (1.0 + hero.talent("leech_heal") / 100.0)
	c.leech_max = int(val("max_foes", 3.0))
	return c

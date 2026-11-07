class_name FireArrow
extends ArrowSkill
## Fire Arrow: a burning arrow that tears through every foe in a line and sets each alight (Pyre: longer and hotter).
## Its numbers are its codex entry's "k" (data/codex/heroes/archer.json): dmg (% of the weapon's blow), burn (% of
## his average blow as the burn's damage a second), burn_lvl and burn_flat (added per level and flat), burn_s (how
## long it burns). What it looks like: fire_arrow_fx.gd (the draw) and ArcherArrowFx (the arrow).

const DRAW_SLOW := 1.15         # its draw is this much slower than a plain shot

func _init(h: Hero, skill_id: String) -> void:
	super(h, skill_id)
	kind = "fire"

func cast(aim: Vector3) -> void:
	super(aim)
	hero.atk_dur *= DRAW_SLOW

func impact() -> void:
	shoot(hero.atk_aim, true, val("dmg", 130.0) / 100.0, 0.0)

## Phoenix Quiver's free one, straight off the bow.
func free_cast(aim: Vector3) -> bool:
	shoot(aim, true, val("dmg", 130.0) / 100.0, 0.0)
	return true

func hit(m: Missile, e) -> void:
	strike(m, e)
	var avg: float = (hero.dmg_min + hero.dmg_max) * 0.5
	var pyre := 1.0 + hero.talent("burn_dmg") / 100.0
	var dps := avg * val("burn", 35.0) / 100.0 + hero.level * val("burn_lvl", 1.2) + val("burn_flat", 2.0)
	e.ignite(dps * pyre * hero.dmg_mult(id), val("burn_s", 3.0) * pyre, kind)
	hero.mark = e
	hero.mark_t = 6.0

func pierces() -> bool:
	return true

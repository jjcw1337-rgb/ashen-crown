class_name BlastArrow
extends ArrowSkill
## Blast Arrow (a run's skill, "a_explosive"): a fire arrow that bursts at the first foe it strikes or where its
## flight ends, hurting and burning everything round it. Codex "k": dmg (the arrow, % of the weapon's blow), blast
## (the burst's), radius (metres; the Blast Radius rite adds to it), burn (% of his average blow a second),
## burn_lvl, burn_s.

const SHOWN := 2                # the nearest this many show the simulated body fire; the rest burn on their numbers

func _init(h: Hero, skill_id: String) -> void:
	super(h, skill_id)
	kind = "fire"

func impact() -> void:
	shoot(hero.atk_aim, false, val("dmg", 60.0) / 100.0, 0.0)

## (it bursts on the first it strikes, so that one isn't marked for the wolf)
func hit(m: Missile, e) -> void:
	strike(m, e)

func ended(m: Missile) -> void:
	var h := hero
	var at := m.pos
	var avg: float = (h.dmg_min + h.dmg_max) * 0.5
	var r := val("radius", 3.5) * (1.0 + h.talent("blast_r") / 100.0)
	var burning := []
	for e in h.game.enemies_near(at, r):
		if not foe(e):
			continue
		h._hit_enemy(e, val("blast", 150.0) / 100.0, 0.6, id)
		if not e.dead:
			e.ignite((avg * val("burn", 25.0) / 100.0 + h.level * val("burn_lvl", 0.8)) * h.dmg_mult(id), val("burn_s", 3.0), "fire")
			if burning.size() < SHOWN:
				burning.append(e)
	h.fx(id, "blast", {"p": at, "r": r, "t": burning, "x": val("burn_s", 3.0)})
	if h.talent("blast_r") > 0.0:
		h.fx("run", "flare", {"p": at, "r": r, "n": 0})

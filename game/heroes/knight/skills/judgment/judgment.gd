class_name Judgment
extends KnightSkill
## Judgment (a run's skill, "k_judgment"): a pillar of holy light slams down on the pointer (Wrath of Heaven, the
## talent "judgment_more": more pillars in a ring round it). Each foe under one is struck once, harder for every Holy
## Brand on it (HolyBrands: spent), and set burning with holy fire. His game shows the pillars at once; the rules strike
## under them. Its look: JudgmentFx ("impact" {ps: the pillars}); the brands' look is HolyBrandsFx ("brand"). Codex "k":
## dmg (% of the weapon's blow), per_brand (% more for each brand), radius, burn (% of his weapon's average blow a second),
## burn_s, knock, ring_r (the ring of more pillars), and the brands' numbers (HolyBrands).

func cast(aim: Vector3) -> void:
	var h := hero
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	h.atk_aim = h.global_position + to.limit_length(float(Data.skill_def(id).get("range", 14.0)))
	h._start_attack("cast", id)     # (its length: its codex "use")

func impact() -> void:
	var g := hero.atk_aim
	g.y = hero.game.world.height_at(g.x, g.z)
	hero.fx(id, "impact", {"ps": PackedVector3Array(pillars(g))})
	make("pillar", {"g": g})

## Where the pillars come down: the one aimed at, and Wrath of Heaven's ring round it.
func pillars(g: Vector3) -> Array:
	var pts := [g]
	var more := int(hero.talent("judgment_more"))
	for i in more:
		var a := TAU * float(i) / maxf(1.0, float(more)) + 0.6
		var q := g + Vector3(cos(a), 0, sin(a)) * val("ring_r", 3.2)
		q.y = hero.game.world.height_at(q.x, q.z)
		pts.append(q)
	return pts

## The pillars its rules strike under.
func made(kind: String, d: Dictionary) -> void:
	if kind != "pillar":
		return
	var h := hero
	var avg: float = (h.dmg_min + h.dmg_max) * 0.5
	var struck := {}
	for q in pillars(d["g"]):
		for e in h.game.enemies_near(q, val("radius", 3.0)):
			if not foe(e) or struck.has(e):
				continue
			struck[e] = true
			var n := HolyBrands.spend(e)
			h._hit_enemy(e, (val("dmg", 120.0) + val("per_brand", 45.0) * n) / 100.0, val("knock", 0.5), id)
			if is_instance_valid(e) and not e.dead:
				e.ignite(avg * val("burn", 30.0) / 100.0 * h.buff_mult() * h.dmg_mult(id), val("burn_s", 3.0))

## Server: the pillar within his reach of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "pillar" and near_him(d.get("g"), float(Data.skill_def(id).get("range", 14.0)))

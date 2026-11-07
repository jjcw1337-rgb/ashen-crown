class_name HellbrandDetonation
extends DemonSkill
## Hellbrand Detonation (a run's skill, "d_detonate"): every Branded foe near him erupts, the Brand spent: hurt,
## thrown up, and the fire bursting onto those beside it (Chain Brand: Branding them). Who carries a Brand is its rules'
## (DemonBrand), so the whole of it runs where his hits are decided, and its look comes from there. Its look:
## DemonFx. Codex "k": radius (metres round him), dmg (% of the weapon's blow), magma (% of his magma), knock,
## knockup_s (monsters; players: knockup_pvp_s), splash_r (metres round each), splash (% of the weapon's blow),
## splash_knock.

func cast(_aim: Vector3) -> void:
	start("cslam", 0.9)

func impact() -> void:
	make("detonate", {"p": hero.global_position})

## Server: round where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "detonate" and d.get("p") is Vector3 and (d["p"] as Vector3).distance_to(hero.global_position) <= 4.0

func made(kind: String, d: Dictionary) -> void:
	if kind != "detonate":
		return
	var h := hero
	var brand := Demon.brands(h)
	var popped := PackedVector3Array()
	for e in h.game.enemies_near(d["p"], val("radius", 10.0)):
		if not foe(e) or not brand.has(e):
			continue
		brand.spend(e)
		popped.append(e.global_position)
		hit(e, val("dmg", 160.0) / 100.0, val("knock", 1.4), magma(h, val("magma", 50.0) / 100.0))
		if is_instance_valid(e) and not e.dead:
			cc(e, "knockup", val("knockup_s", 0.8), val("knockup_pvp_s", 0.5))
		for o in h.game.enemies_near(e.global_position, val("splash_r", 2.5)):
			if o != e and foe(o):
				hit(o, val("splash", 60.0) / 100.0, val("splash_knock", 0.6), 0.0)
				if h.talent("detonate_brand") > 0.0:
					brand.mark(o)
	h.fx(id, "impact", {"ps": popped})

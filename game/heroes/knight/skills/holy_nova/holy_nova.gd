class_name HolyNova
extends KnightSkill
## Holy Nova ("nova"): a ring of holy fire bursts out of him, burning everything within its radius (holy fire: the
## blow's fire part, no crit and no weapon roll). With Radiant Nova (the talent "nova_heal") each foe burned heals him a
## share of his life, up to heal_max of them. Its look: HolyNovaFx ("impact"). Codex "k": base, per_lvl (its fire by
## his level), weapon (% of his weapon's low and high rolls added), radius, knock, heal_max.

func cast(_aim: Vector3) -> void:
	hero._start_attack("cast", id)     # (its length: its codex "use", SkillSpec.apply_timing)

func impact() -> void:
	hero.fx(id, "impact")
	make("nova", {"p": hero.global_position})

## The ring its rules burn everything in.
func made(kind: String, d: Dictionary) -> void:
	if kind != "nova":
		return
	var h := hero
	var at: Vector3 = d["p"]
	var fire := (val("base", 18.0) + h.level * val("per_lvl", 5.0) + (h.dmg_min + h.dmg_max) * val("weapon", 40.0) / 100.0) \
		* h.buff_mult() * h.dmg_mult(id)
	var burned := 0
	for e in h.game.enemies_near(at, val("radius", 7.0)):
		if not foe(e):
			continue
		e.take_damage(0.0, fire, at, val("knock", 1.2), false)
		burned += 1
	if h.talent("nova_heal") > 0.0 and burned > 0:
		h.gain_life(h.max_life * h.talent("nova_heal") / 100.0 * mini(burned, int(val("heal_max", 5.0))))

## Server: the ring is round where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "nova" and near_him(d.get("p"), 0.0)

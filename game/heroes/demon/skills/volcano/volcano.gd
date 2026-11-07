class_name Volcano
extends DemonSkill
## Volcano (a run's skill, "d_volcano"): a volcano torn open at the pointer hurls its meteors onto the foes round it,
## one after another (Ring of Fire: more of them). The volcano is seen at once ("raise"); where its meteors fall is its
## rules', made where his hits are decided. Its look: DemonFx (the eruption, Wrath of the Pit's meteors). Codex "k":
## meteors, radius (metres round it), reach (metres from him), dmg (% of the weapon's blow), magma (% of his magma),
## burn (% of his magma a second), first and gap (seconds to the first meteor's landing and between them).

var at := Vector3.ZERO
var meteors: Array = []      # in the air: {at, t}

func cast(aim: Vector3) -> void:
	var h := hero
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	at = h.global_position + to.limit_length(val("reach", 13.0))
	at.y = h.game.world.height_at(at.x, at.z)
	start("hurl")

func impact() -> void:
	hero.fx(id, "raise", {"p": at})
	make("volcano", {"at": at})

## Server: a volcano within his reach of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "volcano" and d.get("at") is Vector3 and (d["at"] as Vector3).distance_to(hero.global_position) <= val("reach", 13.0) + 4.0

## Its meteors, each at a foe round it in turn (else scattered round it).
func made(kind: String, d: Dictionary) -> void:
	if kind != "volcano":
		return
	var h := hero
	var p0: Vector3 = d["at"]
	var r := val("radius", 6.0)
	var n := int(val("meteors", 5.0)) + int(h.talent("volcano_more"))
	var foes: Array = h.game.enemies_near(p0, r).filter(func(e) -> bool: return foe(e))
	for i in n:
		var p: Vector3
		if not foes.is_empty():
			var pick = foes[i % foes.size()]
			p = pick.global_position + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
		else:
			var ang := TAU * float(i) / n
			p = p0 + Vector3(cos(ang), 0, sin(ang)) * randf_range(2.0, r * 0.8)
		p.y = h.game.world.height_at(p.x, p.z)
		var fall := val("first", 0.6) + i * val("gap", 0.35)
		meteors.append({"at": p, "t": fall})
		h.fx("wrath", "meteor", {"p": p, "n": i, "x": fall})

func update(delta: float) -> void:
	for m in meteors.duplicate():
		m["t"] = float(m["t"]) - delta
		if float(m["t"]) <= 0.0:
			meteors.erase(m)
			land_meteor(m["at"], Skill.num("wrath", "meteor_r", 2.3), val("dmg", 85.0) / 100.0, val("magma", 55.0) / 100.0,
				val("burn", 10.0) / 100.0)

func clear() -> void:
	meteors.clear()

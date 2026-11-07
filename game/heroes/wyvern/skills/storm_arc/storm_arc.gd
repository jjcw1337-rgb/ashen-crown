class_name StormArc
extends DragonSkill
## Storm Arc ("storm_arc", the wyvern's own; jj): it rears, the lightning in its wings flaring, and breathes a bolt into
## the nearest foe ahead that leaps on to the nearest others, striking each. The first foe and the bolt's damage are
## its data entry's (SkillSpec: "area", "base", "per_lvl", "type"). On the cast's impact frame its own game makes the
## "arc" from its jaws, the way it aimed; the rules (here, or on the match server's copy of it) find the chain and
## strike it, and show it ("impact": the path). Its look: storm_arc_fx.gd (StormArcFx). Codex "k": jumps (foes it
## leaps on to after the first), hop (metres a leap reaches).

func cast(_aim: Vector3) -> void:
	hero._start_attack("cast", id)
	halt()

func impact() -> void:
	make("arc", {"p": DragonKit.jaws(hero), "d": hero.aim_dir()})

func made(kind: String, d: Dictionary) -> void:
	if kind != "arc":
		return
	var dv: Vector3 = d["d"]
	hero.fx(id, "impact", {"ps": chain(d["p"], dv), "d": dv})

## Server: a bolt from its jaws where it has the wyvern, aimed flat.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "arc" and flat(d, "d") and near_me(d.get("p"), 6.0)

## The lightning: into the first foe ahead (SkillSpec), then on to the nearest one within a hop of each, striking each.
## The path, from `from`.
func chain(from: Vector3, dv: Vector3) -> PackedVector3Array:
	var h := hero
	var first := SkillSpec.targets(h, id, {"d": dv, "ok": foe})
	var pts := PackedVector3Array([from])
	var hit: Array = []
	var jumps := int(val("jumps", 4.0))
	var hop := val("hop", 5.0)
	var at = first[0] if not first.is_empty() else null
	while at != null and hit.size() <= jumps:
		hit.append(at)
		pts.append(at.global_position + Vector3(0, 1.0, 0))
		SkillSpec.strike(h, id, at)
		var next = null
		var bd := hop
		for e in h.game.enemies_near(at.global_position, hop):
			if e.dead or hit.has(e) or not foe(e):
				continue
			var dd: float = e.global_position.distance_to(at.global_position)
			if dd < bd:
				bd = dd
				next = e
		at = next
	return pts

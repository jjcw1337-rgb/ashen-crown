class_name BananaBonanza
extends Skill
## Banana Bonanza (a run's skill, "u_bonanza"): a ring of banana peels flung down round him (a blocked spot comes in
## until it's free). They lie with his Banana Peels' (BananaPeels.lay) and slip whoever steps on one the same way;
## a foe that slipped on one of these takes double from his next blow for a while (RunTalents.hit_mult reads it off the
## foe). Its look is the Banana Peels' (each peel flung out of his hands first). Codex "k": peels (how many), ring
## (metres out), slipped_s (seconds the double blow waits).

func cast(_aim: Vector3) -> void:
	hero._start_attack("peels", id)

func impact() -> void:
	var h := hero
	# a full ring round him (no World.rng: that is the map's generator); a blocked spot comes inward until free
	var ps := PackedVector3Array()
	var w: Node = h.game.world
	var c := h.global_position
	var spin := randf() * TAU
	var n := int(val("peels", 8.0))
	var ring := val("ring", 3.2)
	for k in n:
		var a := spin + TAU * float(k) / n
		var p := c
		for rr in [ring, ring - 0.6, ring - 1.2, ring - 1.8]:
			var q := c + Vector3(cos(a), 0, sin(a)) * float(rr)
			if not w.is_blocked(q.x, q.z):
				p = q
				break
		p.y = w.height_at(p.x, p.z)
		ps.append(p)
	make("ring", {"ps": ps})
	h.fx("peels", "land", {"ps": ps, "x": Skill.num("peels", "life_s", 8.0), "q": c + Vector3(0, 1.1, 0)})

## Its ring joins the peels on the ground (his Banana Peels' rules keep them all).
func made(kind: String, d: Dictionary) -> void:
	if kind != "ring":
		return
	var ps: PackedVector3Array = d["ps"]
	var bp := Doug.skill(hero, "peels") as BananaPeels
	bp.lay(ps, true, int(Skill.num("peels", "most", 6.0)) + ps.size())

## Server: no more peels than its ring, round where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "ring" or not d.get("ps") is PackedVector3Array:
		return false
	var ps: PackedVector3Array = d["ps"]
	if ps.size() > int(val("peels", 8.0)):
		return false
	for p in ps:
		if p.distance_to(hero.global_position) > val("ring", 3.2) + 4.0:
			return false
	return true

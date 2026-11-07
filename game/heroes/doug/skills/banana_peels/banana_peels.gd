class_name BananaPeels
extends Skill
## Banana Peels ("peels"): a fan of banana peels tossed ahead, landing a few metres out. Whoever steps on one first
## slips: a monster is stunned, a player knocked down and sent sliding (Hero.take_hit "slip", through the server);
## the peel is gone. The ground holds only so many (the oldest go), and they rot away. Banana Bonanza's ring lies here
## too (`lay`). Its look: BananaPeelsFx. Codex "k": peels (how many tossed), spread (degrees between them), near and
## far (metres out they land), life_s (seconds on the ground), most (how many lie down at once), radius (metres: how
## near a step slips), slip_s (seconds a monster is down).

## The peels on the ground (its rules'): {"p", "t": seconds left, "bonanza": Banana Bonanza's}.
var peels: Array = []

func cast(_aim: Vector3) -> void:
	hero._start_attack("peels", id)

func impact() -> void:
	var h := hero
	var fwd := h.aim_dir()
	var n := int(val("peels", 3.0))
	var spread := val("spread", 25.0)
	var ps := PackedVector3Array()
	for k in n:
		var a := deg_to_rad(spread * (k - (n - 1) * 0.5))
		var d := fwd.rotated(Vector3.UP, a) * randf_range(val("near", 3.0), val("far", 6.0))
		ps.append(h.game.world.free_spot_near(h.global_position + d, 0.6))
	make("peels", {"ps": ps})
	h.fx(id, "land", {"ps": ps, "x": val("life_s", 8.0)})

## The peels its rules keep.
func made(kind: String, d: Dictionary) -> void:
	if kind == "peels":
		lay(d["ps"], false, int(val("most", 6.0)))

## Server: no more peels than it tosses, within its reach of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "peels" or not d.get("ps") is PackedVector3Array:
		return false
	var ps: PackedVector3Array = d["ps"]
	if ps.size() > int(val("peels", 3.0)):
		return false
	for p in ps:
		if p.distance_to(hero.global_position) > val("far", 6.0) + 4.0:
			return false
	return true

## Peels down on the ground (his own or Banana Bonanza's), the oldest gone past `most`.
func lay(ps: PackedVector3Array, bonanza: bool, most: int) -> void:
	for p in ps:
		var pl := {"p": p, "t": val("life_s", 8.0)}
		if bonanza:
			pl["bonanza"] = true
		peels.append(pl)
	while peels.size() > most:
		var old: Dictionary = peels.pop_front()
		hero.fx(id, "gone", {"p": old["p"]})

func update(delta: float) -> void:
	var h := hero
	var r := val("radius", 0.7)
	for i in range(peels.size() - 1, -1, -1):
		var pl: Dictionary = peels[i]
		pl["t"] = float(pl["t"]) - delta
		var gone := float(pl["t"]) <= 0.0
		if not gone:
			var p: Vector3 = pl["p"]
			for e in h.game.enemies_near(p, r + 0.5):
				if not foe(e):
					continue
				if Vector2(e.global_position.x - p.x, e.global_position.z - p.z).length() < r + e.radius * 0.5:
					Doug.cc(h, e, "slip", val("slip_s", 1.0))
					if pl.has("bonanza"):
						# (Banana Bonanza: the next blow on it doubles, RunTalents.hit_mult)
						e.set_meta("slipped_until", Time.get_ticks_msec() + int(Skill.num("u_bonanza", "slipped_s", 4.0) * 1000.0))
					h.fx(id, "slip", {"p": p, "t": [e]})
					gone = true
					break
		if gone:
			peels.remove_at(i)
			if float(pl["t"]) <= 0.0:
				h.fx(id, "gone", {"p": pl["p"]})

func clear() -> void:
	for pl in peels:
		hero.fx(id, "gone", {"p": pl["p"]})
	peels.clear()

class_name DoppelDoug
extends Skill
## Doppel-Doug ("doppel"): he ducks behind a puff of confetti and is unseen for a moment (Hero.hidden_t: monsters lose
## him; partners see him fade) while a balloon double of him runs off toward the cursor. A foe that reaches it, or its
## time running out, pops it: a confetti burst that slows whoever is near. The double its rules run is here (here, or
## on the match server's copy of him); every game's look runs its own (DoppelDougFx). Codex "k": hide_s (seconds
## unseen), double_s (seconds the double runs), speed (its pace, metres a second), touch (metres: a foe this near pops
## it), pop_r (metres its burst reaches), slow (% slower), slow_s.

var aim := Vector3.ZERO
## Its rules' double: {"p", "d": its way, "t": seconds left}.
var double := {}

func cast(at: Vector3) -> void:
	aim = at
	hero._start_attack("doppel", id)

func impact() -> void:
	var h := hero
	var dir := aim - h.global_position
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.1 else h.aim_dir()
	h.hidden_t = val("hide_s", 1.8)
	h.fx(id, "start", {"p": h.global_position, "d": dir, "x": val("hide_s", 1.8), "r": val("double_s", 3.0)})
	make("double", {"p": h.global_position, "d": dir})

## The double its rules run.
func made(kind: String, d: Dictionary) -> void:
	if kind == "double":
		double = {"p": d["p"], "d": d["d"], "t": val("double_s", 3.0)}

## Server: a double from where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "double" or not (d.get("p") is Vector3 and d.get("d") is Vector3):
		return false
	if (d["p"] as Vector3).distance_to(hero.global_position) > 4.0:
		return false
	var dir: Vector3 = d["d"] * Vector3(1, 0, 1)
	d["d"] = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	return true

func update(delta: float) -> void:
	if double.is_empty():
		return
	var h := hero
	double["t"] = float(double["t"]) - delta
	double["p"] = h.game.world.move(double["p"], (double["d"] as Vector3) * val("speed", 4.2) * delta, 0.4)
	var at: Vector3 = double["p"]
	var pop := float(double["t"]) <= 0.0
	for e in h.game.enemies_near(at, val("touch", 1.4)):
		if foe(e):
			pop = true
			break
	if pop:
		for e in h.game.enemies_near(at, val("pop_r", 3.0)):
			if foe(e):
				Doug.cc(h, e, "slow", val("slow_s", 1.5), val("slow", 45.0) / 100.0)
		h.fx(id, "pop", {"p": at})
		double = {}

func clear() -> void:
	double = {}

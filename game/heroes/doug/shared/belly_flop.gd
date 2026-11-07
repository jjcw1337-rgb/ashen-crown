class_name BellyFlop
extends Skill
## A leap of Doug's that lands in a belly-flop: Big Top Bounce and the run's Human Cannonball. The cast picks where he
## lands (within the skill's "range", on free ground) and every game marks it ("bounce" "mark": BigTopBounceFx); on
## the impact frame his own game puts him down there and shows the flop, and its rules strike everything round where
## he landed, knocking it down (`make("flop")`: here, or on the match server's copy of him). Codex "k": dmg (% of the
## weapon's blow), radius (metres), knock, stun_s (seconds a monster is down; a player is stunned through the server,
## Hero.take_hit "quake").

## His own game: the leap {"from", "to"}.
var leap := {}

func cast(aim: Vector3) -> void:
	var h := hero
	h._start_attack("bounce", id)
	var to := aim
	to.y = h.global_position.y
	var off := to - h.global_position
	var reach := float(Data.skill_def(id).get("range", 10.0))
	if off.length() > reach:
		to = h.global_position + off.normalized() * reach
	to = h.game.world.free_spot_near(to, 1.0)
	leap = {"from": h.global_position, "to": to}
	h.fx("bounce", "mark", {"p": h.global_position, "q": to, "x": h.atk_dur})

## Down where he leapt to: the flop (seen at once), and its rules strike round it.
func impact() -> void:
	var h := hero
	if not leap.is_empty():
		h.global_position = leap["to"]
	leap = {}
	h.fx("bounce", "flop", {"p": h.global_position})
	landed()
	make("flop", {"p": h.global_position})

## What else shows as he lands (the Cannonball's boom).
func landed() -> void:
	pass

## Its numbers when the codex has none (Big Top Bounce's).
func fallbacks() -> Dictionary:
	return {"dmg": 180.0, "radius": 3.0, "knock": 2.0, "stun_s": 0.8}

## Its number from the codex, else its fallback.
func k(key: String) -> float:
	return val(key, float(fallbacks()[key]))

## How far round where he lands it strikes.
func radius() -> float:
	return k("radius")

## Everything round where he landed is struck and knocked down.
func made(kind: String, d: Dictionary) -> void:
	if kind != "flop":
		return
	var h := hero
	for e in h.game.enemies_near(d["p"], radius()):
		if foe(e):
			h._hit_enemy(e, k("dmg") / 100.0, k("knock"), id)
			Doug.cc(h, e, "quake", k("stun_s"))

## Server: a landing within its range of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "flop" and d.get("p") is Vector3 and (d["p"] as Vector3).distance_to(hero.global_position) <= float(Data.skill_def(id).get("range", 10.0)) + 4.0

func died() -> void:
	leap = {}

func clear() -> void:
	leap = {}

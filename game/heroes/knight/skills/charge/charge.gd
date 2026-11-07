class_name KnightCharge
extends KnightSkill
## Charge ("charge"): a dash toward the cursor, each foe in the way smashed once, thrown aside and stunned (a player
## through the server). Relentless (the talent "charge_cdr"): each one smashed takes time off his other cooldowns.
## His own game carries him (Hero.charge_t: the dash replaces his walking, ClassSkills.dash -> `dash`); its rules run
## the same dash from where it began (`run`) and strike what it passes, so on the match server they strike from the
## server's own positions. Its look: ChargeFx ("cast" the trail, "hit" each foe, "end"). Codex "k": dmg (% of the
## weapon's blow), stun_s, knock, radius (how near the dash a foe is struck), speed (metres a second), secs (at most).

var dir := Vector3.FORWARD     # his own game: the dash's way
var run := {}                  # rules: the dash {p: where it is, d: its way, t: seconds into it, hit: who it struck}

func cast(aim: Vector3) -> void:
	var h := hero
	var d := aim - h.global_position
	d.y = 0
	dir = d.normalized() if d.length() > 0.1 else h.aim_dir()
	h.charge_t = 0.0
	h.path = PackedVector3Array()
	h.moving = false
	make("dash", {"p": h.global_position, "d": dir})

## His own game, every frame of the dash (in place of his walking): it carries him until its time is up or a wall
## stops him.
func dash(delta: float) -> void:
	var h := hero
	h.charge_t += delta
	var dist := val("speed", 18.0) * delta
	var np: Vector3 = h.game.world.move(h.global_position, dir * dist)
	var moved := np - h.global_position
	moved.y = 0
	h.global_position = np
	h._face(dir)
	h.phase += delta * 20.0
	if h.charge_t > val("secs", 0.5) or moved.length() < dist * 0.3:
		h.charge_t = -1.0
		h.fx(id, "end")

## The dash its rules run.
func made(kind: String, d: Dictionary) -> void:
	if kind == "dash":
		run = {"p": d["p"], "d": d["d"], "t": 0.0, "hit": {}}

## Server: a dash from where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "dash" or not near_him(d.get("p"), 0.0) or not d.get("d") is Vector3:
		return false
	var w: Vector3 = d["d"] * Vector3(1, 0, 1)
	if w.length() < 0.01:
		return false
	d["d"] = w.normalized()
	return true

func update(delta: float) -> void:
	if run.is_empty():
		return
	var h := hero
	run["t"] = float(run["t"]) + delta
	var dist := val("speed", 18.0) * delta
	var from: Vector3 = run["p"]
	var np: Vector3 = h.game.world.move(from, (run["d"] as Vector3) * dist)
	var moved := np - from
	moved.y = 0
	run["p"] = np
	var hit: Dictionary = run["hit"]
	for e in h.game.enemies_near(np, val("radius", 1.6)):
		if not foe(e) or hit.has(e.get_instance_id()):
			continue
		hit[e.get_instance_id()] = true
		h._hit_enemy(e, val("dmg", 130.0) / 100.0, val("knock", 2.5), id)
		stun(e, val("stun_s", 0.8))
		if h.talent("charge_cdr") > 0.0:
			give("cdr", {"s": h.talent("charge_cdr")})
		h.fx(id, "hit", {"p": e.global_position, "x": hit.size() == 1})
	if float(run["t"]) > val("secs", 0.5) or moved.length() < dist * 0.3:
		run = {}

## His own game takes what the rules gave him: Relentless's time off his other cooldowns.
func given(kind: String, d: Dictionary) -> void:
	if kind != "cdr":
		return
	var s := float(d.get("s", 0.0))
	for k in hero.cds:
		if k != id:
			hero.cds[k] = maxf(0.0, hero.cds[k] - s)

func died() -> void:
	run = {}

func clear() -> void:
	run = {}

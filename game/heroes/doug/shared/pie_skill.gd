class_name PieSkill
extends Skill
## A skill of Doug's that throws cream pies: Cream Pie and the run's Pie Barrage. The throw is seen at once (its
## "throw" event: every game's look flies its own pie, CreamPieFx); its rules keep each pie here until it lands
## (`make("pies")`: here, or on the match server's copy of him). Where a pie lands, the foe nearest it (within the Cream
## Pie's radius) takes its blow and is Pied (`pie_face`).

## Its pies in the air: {"to": where it lands, "t": seconds left}.
var pies: Array = []

## The pies its rules fly ("ps" where each lands, "ts" when).
func made(kind: String, d: Dictionary) -> void:
	if kind != "pies":
		return
	var ps: PackedVector3Array = d["ps"]
	var ts: PackedFloat32Array = d["ts"]
	for i in ps.size():
		pies.append({"to": ps[i], "t": ts[i]})

## Server: no more pies than it throws, each landing within its reach of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "pies" or not d.get("ps") is PackedVector3Array or not d.get("ts") is PackedFloat32Array:
		return false
	var ps: PackedVector3Array = d["ps"]
	var ts: PackedFloat32Array = d["ts"]
	if ps.is_empty() or ps.size() != ts.size() or ps.size() > most():
		return false
	for p in ps:
		if p.distance_to(hero.global_position) > reach() + 4.0:
			return false
	for i in ts.size():
		ts[i] = clampf(ts[i], 0.0, 2.0)
	d["ts"] = ts
	return true

## How many pies one cast throws.
func most() -> int:
	return 1

## How far from him one may land.
func reach() -> float:
	return float(Data.skill_def(id).get("range", 12.0))

## Each pie's share of the weapon's blow (its codex "dmg").
func blow() -> float:
	return val("dmg", 120.0) / 100.0

## A pie flies `flight` seconds (the Cream Pie's).
static func flight() -> float:
	return Skill.num("pie", "flight", 0.45)

func update(delta: float) -> void:
	for i in range(pies.size() - 1, -1, -1):
		var pie: Dictionary = pies[i]
		pie["t"] = float(pie["t"]) - delta
		if float(pie["t"]) > 0.0:
			continue
		pies.remove_at(i)
		_land(pie["to"])

## A pie lands: the foe nearest it takes the blow and is Pied (seen on every game: "splat").
func _land(to: Vector3) -> void:
	var h := hero
	var r := Skill.num("pie", "radius", 1.4)
	var best = null
	var bd := r
	for e in h.game.enemies_near(to, r + 1.0):
		if not foe(e):
			continue
		var d: float = Vector2(e.global_position.x - to.x, e.global_position.z - to.z).length()
		if d < bd:
			bd = d
			best = e
	h.fx("pie", "splat", {"p": to, "t": [best] if best != null else []})
	if best != null:
		h._hit_enemy(best, blow(), 0.0, id)
		pie_face(h, best)

## Pied (every pie of his: the Cream Pie's, Pie Barrage's, the Clown Car's mini clowns'): a monster stunned for a
## moment and slowed, a player's screen creamed (through the server); the same foe not again within the Cream Pie's
## lock (it keeps the lock).
static func pie_face(h: Hero, e) -> void:
	var cp := Doug.skill(h, "pie") as CreamPie
	var key := str(e.get_instance_id())
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(cp.pied.get(key, -99.0)) > Skill.num("pie", "lock_s", 6.0):
		cp.pied[key] = now
		Doug.cc(h, e, "pied", Skill.num("pie", "pied_s", 2.0), Skill.num("pie", "slow", 50.0) / 100.0)

func clear() -> void:
	pies.clear()

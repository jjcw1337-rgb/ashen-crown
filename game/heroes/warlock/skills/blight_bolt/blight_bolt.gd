class_name BlightBolt
extends WarlockSpell
## Blight Bolt ("blight"): a blight skull flies straight from her hand (two, a little apart, with Twin Skulls) and
## bursts on the first foe it meets, a wall or the end of its range, leaving a plague pool that rots whatever stands
## in it (a foe in one counts as cursed: WarlockHex.curses_on). Its rules fly the skulls (`bolts`) and keep the pools
## (`pools`); its look (WarlockFx "bolt", "burst") flies its own copies of the skulls the same way from the "bolt"
## event, and the "burst" event takes one and draws the burst and the pool. Codex "k": speed (metres a second; it
## flies its codex range), radius (the burst and pool; Spreading Rot adds to it), pool_s (Lingering Blight adds to it),
## beat (seconds between the pool's ticks), twin (radians between Twin Skulls), near (metres from a foe that bursts it),
## knock, cast_s.

var bolts: Array = []      # rules: skulls in flight [{p, d, left}]
var pools: Array = []      # rules: plague pools [{pos, t: seconds left, tick, r}]

func cast(_aim: Vector3) -> void:
	hero._start_attack("cast", id)
	hero.atk_dur = val("cast_s", 0.45) * Data.attack_pace(hero.cls)

## The skulls leave her hand toward the pointer as it was when she cast.
func impact() -> void:
	var h := hero
	var dir := h.aim_dir()
	var twin := h.talent("blight_twin") > 0.0
	h.fx(id, "bolt", {"d": dir, "x": twin})
	for dv in dirs(dir, twin):
		make("skull", {"p": h.global_position + Vector3(0, 1.3, 0) + dv * 0.6, "d": dv})

## The way each skull flies: one, or Twin Skulls' two.
static func dirs(dir: Vector3, twin: bool) -> Array:
	if not twin:
		return [dir]
	var a := Skill.num("blight", "twin", 0.14)
	return [dir.rotated(Vector3.UP, a), dir.rotated(Vector3.UP, -a)]

func made(kind: String, d: Dictionary) -> void:
	if kind == "skull":
		bolts.append({"p": d["p"], "d": d["d"], "left": reach()})

## Server: a skull from her hand where it has her.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "skull" or not (d.get("p") is Vector3 and d.get("d") is Vector3):
		return false
	d["d"] = (d["d"] as Vector3).normalized()
	return (d["p"] as Vector3).distance_to(hero.global_position) <= 4.0

## One frame of a skull's flight (its look flies its copy the same way, WarlockFx).
static func fly(world, b: Dictionary, delta: float, speed: float) -> bool:
	var step := speed * delta
	var p: Vector3 = b["p"]
	var np: Vector3 = world.move(p, (b["d"] as Vector3) * step, 0.15)
	var moved := np - p
	moved.y = 0
	np.y = lerpf(p.y, world.height_at(np.x, np.z) + 1.2, clampf(delta * 6.0, 0.0, 1.0))
	b["p"] = np
	b["left"] -= step
	return b["left"] <= 0.0 or moved.length() < step * 0.4

func update(delta: float) -> void:
	var h := hero
	for b in bolts.duplicate():
		var blocked := fly(h.game.world, b, delta, val("speed", 16.0))
		var np: Vector3 = b["p"]
		if blocked or h.game.enemies_near(np, val("near", 1.0)).any(func(e) -> bool: return foe(e)):
			bolts.erase(b)
			_burst(np)
	for bl in pools.duplicate():
		bl["t"] -= delta
		bl["tick"] -= delta
		if bl["t"] <= 0.0:
			pools.erase(bl)
			continue
		if bl["tick"] <= 0.0:
			bl["tick"] = val("beat", 0.5)
			var nd := (4.0 + h.level * 1.3 + (h.dmg_min + h.dmg_max) * 0.12) * h.buff_mult() * h.dmg_mult(id)
			for e in h.game.enemies_near(bl["pos"], float(bl.get("r", 3.0))):
				if foe(e):
					_deal(e, nd, bl["pos"], 0.0)

## The skull bursts: a plague pool where it lands, and the burst's blow on everything within it.
func _burst(p: Vector3) -> void:
	var h := hero
	var g := Vector3(p.x, h.game.world.height_at(p.x, p.z), p.z)
	var rad := val("radius", 3.0) * (1.0 + h.talent("blight_size") / 100.0)
	var dur := val("pool_s", 4.0) + h.talent("blight_dur")
	h.fx(id, "burst", {"p": g, "r": rad, "x": dur})
	pools.append({"pos": g, "t": dur, "tick": val("beat", 0.5), "r": rad})
	var nd := (14.0 + h.level * 4.0 + (h.dmg_min + h.dmg_max) * 0.35) * h.buff_mult() * h.dmg_mult(id)
	for e in h.game.enemies_near(g, rad):
		if foe(e):
			_deal(e, nd, g, val("knock", 0.8))

func _deal(e, v: float, from: Vector3, knock: float) -> void:
	var dealt: float = e.take_damage(v, 0.0, from, knock, false)
	if hero.puppet and hero.game.net.server:
		hero.game.net.tell_dealt(hero, e.global_position, dealt, false)

## e stands in one of her pools.
func in_pool(e) -> bool:
	for bl in pools:
		if e.global_position.distance_to(bl["pos"]) <= float(bl.get("r", 3.0)):
			return true
	return false

func clear() -> void:
	super.clear()
	bolts.clear()
	pools.clear()

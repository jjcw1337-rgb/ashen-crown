class_name VoidWisp
extends WarlockSpell
## Void Wisp ("w_darkwind", kept for saves and rites): a wisp that bounces from the foe she aims at to the nearest
## not yet struck, hurting and slowing each (double on the frightened or bound). Its rules keep each wisp's path
## (`winds`) and strike the next foe on it every `gap`; its look (WarlockHarrowFx "wind") flies the same path at the
## same pace. Codex "k": hops (foes at most), hop_r (metres to the next), gap (seconds a hop), dmg (% of her spell
## power), feared_k (times, on the frightened), slow_s, slow (% slower, a monster), pvp_slow (% slower, a player).

var winds: Array = []      # rules: [{t: the path, i: the next on it, next: seconds to it}]

func targeted() -> bool:
	return true

func struck(e) -> void:
	var path := _path(e)
	hero.fx(id, "wind", {"t": path})
	winds.append({"t": path, "i": 0, "next": 0.0})

## The first foe, then the nearest one not yet struck, up to `hops`.
func _path(first) -> Array:
	var path := [first]
	var at: Vector3 = first.global_position
	var hop_r := val("hop_r", 6.0)
	while path.size() < int(val("hops", 5.0)):
		var best = null
		var bd := hop_r
		for e in hero.game.enemies_near(at, hop_r):
			if path.has(e) or e.get("pvp_hidden") or e.get("pvp_obj") or not foe(e):
				continue
			var d: float = e.global_position.distance_to(at)
			if d < bd:
				bd = d
				best = e
		if best == null:
			break
		path.append(best)
		at = best.global_position
	return path

func update(delta: float) -> void:
	if winds.is_empty():
		return
	var hx := hex()
	for wd in winds.duplicate():
		wd["next"] -= delta
		if wd["next"] > 0.0:
			continue
		wd["next"] = val("gap", 0.14)
		var path: Array = wd["t"]
		if wd["i"] >= path.size():
			winds.erase(wd)
			continue
		var e = path[wd["i"]]
		wd["i"] += 1
		if not alive(e):
			continue
		var k := val("dmg", 90.0) / 100.0 * (val("feared_k", 2.0) if (hx.is_feared(e) or e.stun_t > 0.0) else 1.0)
		hx.hit(e, hx.spell() * k * hero.dmg_mult(id), WarlockHex.SHADOW_TINT)
		if PvpStatus.is_player(e):
			PvpStatus.send(hero.game, e, "slow", val("slow_s", 1.0), {"k": val("pvp_slow", 30.0) / 100.0})
		elif alive(e):
			e.slow(val("slow_s", 1.0), val("slow", 35.0) / 100.0)

func clear() -> void:
	super.clear()
	winds.clear()

class_name ProcHits
extends RefCounted
## What a rite's or gem's proc does to foes, also used by a thrown flask (Consumables) and a few skills (Storm Shot's
## chain, Glacial Shard's and the dragons' freeze). The damage goes through the usual channels (Enemy.take_damage,
## ignite, chill), so on a client the host or the match server applies it; what is seen goes out as "run" fx events
## (Hero.fx), drawn by RiteFx on every player's game.

## The proc damage being dealt now: a proc's own hit never sets off other procs (RiteProcs.on_hit), and the kills an
## area causes set off death procs only a few deep (RiteProcs.on_death reads `depth`).
static var in_proc := false
static var depth := 0

## A monster this hero's procs may work on (a player's stand-in or breakable thing takes only the plain blow).
static func monster(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead and e.pvp_pid == 0 and e.pvp_obj == 0 and e.sandbox_hero == null

## Is a foe poisoned by this hero (the Plague Doctor's own poison)?
static func poisoned(h: Hero, e) -> bool:
	return Plague.poisoned(h, e)

## Burning or rotting (an ignite from anyone: the Fire Arrow, the Demon, a blight).
static func burning(e) -> bool:
	return e.burn_t > 0.0

static func chilled(e) -> bool:
	return e.chill_t > 0.0 or e.has_meta("frozen_t")

## The hero's weapon hit, the base most proc damage is a share of.
static func weapon(h: Hero) -> float:
	return (h.dmg_min + h.dmg_max) * 0.5 * h.buff_mult() * (1.0 + h.talent("dmg") / 100.0)

## Proc damage on one foe, through the usual channel (on a client the host applies it).
static func deal(h: Hero, e, amount: float, kind: String) -> void:
	if e == null or not is_instance_valid(e) or e.dead or amount <= 0.0:
		return
	var was := in_proc
	in_proc = true
	Hero.striker = h
	e.set_meta("run_hit", [h, Time.get_ticks_msec()])
	match kind:
		"fire", "holy": e.dmg_tint = Color(1.0, 0.62, 0.25)
		"frost": e.dmg_tint = Color(0.6, 0.88, 1.0)
		"storm": e.dmg_tint = Color(0.75, 0.78, 1.0)
		"plague", "fel": e.dmg_tint = Color(0.5, 1.0, 0.35)
	e.soft_hit = true
	var dealt: float = e.take_damage(0.0, amount, h.global_position, 0.0, false)
	e.dmg_tint = Color(0, 0, 0, 0)
	e.soft_hit = false
	if h.puppet and h.game.net.server:
		h.game.net.tell_dealt(h, e.global_position, dealt, false)
	if h.ls > 0.0:
		h.gain_life(dealt * h.ls / 200.0)
	in_proc = was

## Damage in a circle (the explosions, shards and plague clouds), the dead excluded; its own kills may set off
## death procs again, a few deep.
static func area(h: Hero, at: Vector3, r: float, amount: float, kind: String, skip = null) -> void:
	depth += 1
	var n := 0
	match kind:
		"fire": h.fx("run", "flare", {"p": at, "r": r, "n": 0})
		"fel": h.fx("run", "flare", {"p": at, "r": r, "n": 1})
		"frost": h.fx("run", "shards", {"p": at, "r": r})
		"plague": h.fx("run", "cloud", {"p": at, "r": r})
	for e in h.game.enemies_near(at, r):
		if e == skip or not monster(e):
			continue
		deal(h, e, amount, kind)
		match kind:
			"frost":
				if not e.dead:
					e.chill(0.35, 2.5)
			"plague":
				if not e.dead:
					Plague.poison(h, e, "toxic", 3.0)
		n += 1
	depth -= 1

## Frozen solid: stunned (bosses a third as long, Enemy.stun) under a crust of rime.
static func freeze(h: Hero, e, secs: float) -> void:
	e.stun(secs)
	e.chill(0.6, secs + 1.0)
	h.fx("run", "freeze", {"p": e.global_position, "r": e.radius + 0.4, "x": secs})

## Lightning from `e` through the nearest others.
static func chain(h: Hero, e, jumps: int, amount: float, r: float) -> void:
	var at: Vector3 = e.global_position
	var done := {e: true}
	var pts := PackedVector3Array([at + Vector3(0, 1.2, 0)])
	for i in jumps:
		var best = null
		var bd := r
		for o in h.game.enemies_near(at, r):
			if done.has(o) or not monster(o):
				continue
			var d: float = o.global_position.distance_to(at)
			if d < bd:
				bd = d
				best = o
		if best == null:
			break
		done[best] = true
		deal(h, best, amount, "storm")
		at = best.global_position
		pts.append(at + Vector3(0, 1.2, 0))
	if pts.size() > 1:
		h.fx("run", "chain", {"ps": pts})

## A plain arrow glancing on from `e` to the next foes.
static func ricochet(h: Hero, e, bounces: int, amount: float, r: float) -> void:
	var at: Vector3 = e.global_position
	var done := {e: true}
	var pts := PackedVector3Array([at + Vector3(0, 1.3, 0)])
	for i in bounces:
		var best = null
		var bd := r
		for o in h.game.enemies_near(at, r):
			if done.has(o) or not monster(o):
				continue
			var d: float = o.global_position.distance_to(at)
			if d < bd:
				bd = d
				best = o
		if best == null:
			break
		done[best] = true
		deal(h, best, amount, "phys")
		at = best.global_position
		pts.append(at + Vector3(0, 1.3, 0))
	if pts.size() > 1:
		h.fx("run", "ricochet", {"ps": pts})

## A bolt from the sky onto `at`.
static func bolt(h: Hero, at: Vector3, amount: float, r: float) -> void:
	h.fx("run", "bolt", {"p": at, "r": r})
	area(h, at, r, amount, "storm")

## Pass the strongest of this hero's poison on `e` to the `n` nearest others.
static func spread_poison(h: Hero, e, n: int, r: float) -> void:
	if not h.is_plague():
		return
	var near := []
	for o in h.game.enemies_near(e.global_position, r):
		if o != e and monster(o):
			near.append(o)
	near.sort_custom(func(a, b): return a.global_position.distance_to(e.global_position) < b.global_position.distance_to(e.global_position))
	var pts := PackedVector3Array([e.global_position + Vector3(0, 1.0, 0)])
	for i in mini(n, near.size()):
		Plague.poison(h, near[i], "toxic", 3.5)
		pts.append(near[i].global_position + Vector3(0, 1.0, 0))
	if pts.size() > 1:
		h.fx("run", "spread", {"ps": pts})

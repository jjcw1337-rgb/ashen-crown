class_name InfernalCharge
extends DemonSkill
## Infernal Charge (E, "icharge", engage and mobility): "icharge_wind" (he paws the ground; the burning line shows
## everyone the path) -> "icharge" (the run, `speed`, up to `reach`) -> "icharge_skid" (the stop, open to
## punishment). It stops on the first champion, boss or player: staggered and Branded. Lesser monsters are bowled
## aside. He runs on his own game; its hits are dealt where his hits are decided: there as he runs, or on the match
## server, whose copy of him runs the same line (`sweeps`). Its look: InfernalChargeFx ("Hellrunner"). Codex "k": dmg
## (% of the weapon's blow), magma (% of his magma), reach and min (metres), speed (m/s), hit_r (metres), knock (the
## lesser foes'), stagger_s (the big one's, monsters; players: its "pvp" stagger), stagger_small_s.

var run := {}           # the charge in progress on his own game: {dir, dist, done, hit, stop}
var sweeps: Array = []  # the match server's runs of his line: {pos, dir, left, hit, stop}

func cast(aim: Vector3) -> void:
	var h := hero
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	var dir := to.normalized() if to.length() > 0.5 else h.aim_dir()
	var dist := clampf(to.length(), val("min", 3.0), val("reach", 9.0))
	# where he would end up (walls cut it short), so the line everyone sees is the truth
	var end: Vector3 = h.game.world.move(h.global_position, dir * dist, h.radius)
	end.y = h.game.world.height_at(end.x, end.z)
	dist = maxf(1.0, (end - h.global_position).length())
	run = {"dir": dir, "dist": dist, "done": 0.0, "hit": {}, "stop": false}
	start("icharge_wind")
	h.fx(id, "wind", {"p": h.global_position, "q": end, "d": dir, "x": h.atk_dur})

func rooted() -> bool:
	return hero.atk_t >= 0.0 and hero.atk_skill == id

func begin_stage(style: String) -> void:
	var h := hero
	match style:
		"icharge":
			if run.is_empty():
				return
			start("icharge", float(run["dist"]) / val("speed", 16.0) / Data.attack_pace(h.cls) + 0.02)
			h.fx(id, "run", {"d": run["dir"]})
			if not deals():
				make("charge", {"p": h.global_position, "d": run["dir"], "x": float(run["dist"])})
		"icharge_skid":
			start("icharge_skid")
			h.fx(id, "skid", {"p": h.global_position, "d": run.get("dir", h.aim_dir())})

func stage_done(style: String) -> void:
	match style:
		"icharge_wind":
			next = "icharge"
		"icharge":
			next = "icharge_skid"
		"icharge_skid":
			run = {}
			hero.fx(id, "end", {"p": hero.global_position})

## Server: his line from about where it has him, no longer than his reach.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "charge" or not (d.get("p") is Vector3 and d.get("d") is Vector3):
		return false
	if (d["p"] as Vector3).distance_to(hero.global_position) > 4.0:
		return false
	d["d"] = ((d["d"] as Vector3) * Vector3(1, 0, 1)).normalized()
	d["x"] = clampf(float(d.get("x", 0.0)), 0.0, val("reach", 9.0))
	return true

## The server's copy runs his line to deal its hits.
func made(kind: String, d: Dictionary) -> void:
	if kind == "charge":
		sweeps.append({"pos": d["p"], "dir": d["d"], "left": float(d["x"]), "hit": {}, "stop": false})

func step(delta: float) -> void:
	stages()
	if not run.is_empty():
		_run(delta)
	for s in sweeps.duplicate():
		_sweep(s, delta)
		if bool(s["stop"]):
			sweeps.erase(s)

## He runs the line (his own game): bowling the lesser aside, stopped by the first big one or a wall.
func _run(delta: float) -> void:
	var h := hero
	var c := run
	if h.dead or h.atk_skill != id:
		run = {}
		h.fx(id, "end", {"p": h.global_position})
		return
	if h.atk_style != "icharge" or bool(c["stop"]):
		return
	var dir: Vector3 = c["dir"]
	var left: float = float(c["dist"]) - float(c["done"])
	var d := minf(val("speed", 16.0) * delta, left)
	if d <= 0.0:
		return
	var np: Vector3 = h.game.world.move(h.global_position, dir * d, h.radius)
	var moved := np - h.global_position
	moved.y = 0
	h.global_position = np
	h._face(dir)
	c["done"] = float(c["done"]) + d
	if _contacts(h.global_position, dir, c["hit"], deals()):
		c["stop"] = true
		SkillFx.hitstop(h, 0.06)
	if moved.length() < d * 0.3:
		c["stop"] = true      # a wall
	if bool(c["stop"]) or float(c["done"]) >= float(c["dist"]) - 0.01:
		c["stop"] = true
		h.atk_t = h.atk_dur   # the run ends now: the skid follows (stage_done)

## The server's run of his line: the same pace and walls, its own positions of everyone.
func _sweep(s: Dictionary, delta: float) -> void:
	var h := hero
	var dir: Vector3 = s["dir"]
	var d := minf(val("speed", 16.0) * delta, float(s["left"]))
	if h.dead or d <= 0.0:
		s["stop"] = true
		return
	var p: Vector3 = s["pos"]
	var np: Vector3 = h.game.world.move(p, dir * d, h.radius)
	var moved := np - p
	moved.y = 0
	s["pos"] = np
	s["left"] = float(s["left"]) - d
	if _contacts(np, dir, s["hit"], true) or moved.length() < d * 0.3 or float(s["left"]) <= 0.01:
		s["stop"] = true

## Who he runs into at `pos`: each struck once (`deal`: the blow, the stagger, a big one Branded; its look). True
## when a big one stops him.
func _contacts(pos: Vector3, dir: Vector3, struck: Dictionary, deal: bool) -> bool:
	var h := hero
	var r := val("hit_r", 1.5)
	for e in h.game.enemies_near(pos + dir * 0.4, r + 0.8):
		if struck.has(e.get_instance_id()) or not foe(e):
			continue
		var to: Vector3 = e.global_position - pos
		to.y = 0
		if to.length() - e.radius > r or (to.length() > 0.3 and dir.dot(to.normalized()) < -0.2):
			continue
		struck[e.get_instance_id()] = true
		var big: bool = PvpStatus.is_player(e) or e.champion or immovable(e)
		if deal:
			hit(e, val("dmg", 120.0) / 100.0, 0.0 if big else val("knock", 2.6), magma(h, val("magma", 50.0) / 100.0))
			if is_instance_valid(e) and not e.dead:
				cc(e, "stagger", val("stagger_s", 1.0) if big else val("stagger_small_s", 0.5), pvp("stagger", 0.5))
				if big:
					Demon.brands(h).mark(e)
			h.fx(id, "hit", {"p": e.global_position + Vector3(0, 0.8 * e.height, 0), "d": dir, "x": big})
		if big:
			return true
	return false

func clear() -> void:
	if not run.is_empty():
		hero.fx(id, "end", {"p": hero.global_position})
	run = {}
	sweeps.clear()
	next = ""

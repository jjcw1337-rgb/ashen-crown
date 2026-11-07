class_name ArcherArrowFx
extends RefCounted
## What the archer's arrows look like in flight, on every game (his own and a partner's copy of him): the "loose"
## event makes the arrow of its kind (ArrowFx's layered arrows: war, fire, frost, storm) and its own Missile, flown
## here with the rules' step so it goes where the real one goes. Where it passes a foe it shows the strike, the frost
## burst or the lightning, and a Fire Arrow's flames on the body; where it ends, ArrowFx's finish. It never hurts
## anything: the hits are the skill's (ArrowSkill), on the archer's own game.
## The arrows live in Hero.arrows: {node, m (its Missile), dir, kind, pierce, src, mult, pts, ...}.

## The "loose" event: {p: from, d: direction, k: kind, x: it pierces, m: its share of the blow}.
static func loosed(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var from: Vector3 = ev["p"]
	var dir: Vector3 = ev["d"]
	var kind := str(ev.get("k", "war"))
	var pierce := bool(ev.get("x", false))
	var n := ArrowFx.projectile(kind, h.game)
	root.add_child(n)
	n.global_position = from
	n.look_at(from + dir, Vector3.UP)
	var m := Missile.new(from, dir)
	m.speed = Archer.ARROW_SPEED
	m.left = Archer.FLIGHT
	m.pierce = pierce
	# ("fresh": it was made after this frame's rules moved theirs, so it waits a frame to keep step with them)
	h.arrows.append({"node": n, "m": m, "dir": dir, "left": m.left, "pierce": pierce, "hit": m.struck,
		"mult": float(ev.get("m", 1.0)), "src": str(ev["s"]), "kind": kind, "pts": [], "fresh": true})
	ArrowFx.end_draw(h)
	h.fxs.erase("draw_fire")
	h.fxs.erase("fire_cast")
	ArrowFx.release(h, kind, from, dir)
	if kind == "frost":
		Fx.aura(n, Color(0.6, 0.88, 1.0), 16, 0.25, 0.06, 0.35, 0.0, 0.06)
		SkillFx.snd(h, "frost_loose", -4.0, 1.2)
	elif kind == "storm":
		Fx.aura(n, Color(0.75, 0.8, 1.0), 20, 0.6, 0.05, 0.25, 0.0, 0.08)
		ArcFx.charge(h, from, ArcFx.STORM, 0.25)
		SkillFx.snd(h, "storm_shot", -3.0)
	if str(ev["s"]) == "a_multishot" and Time.get_ticks_msec() - int(h.fxs.get("scatter_snd", 0)) > 300:
		h.fxs["scatter_snd"] = Time.get_ticks_msec()     # (one sound for the five arrows)
		SkillFx.snd(h, "scatter_loose", -3.0)

## Every frame (SkillFx.update): each arrow flies on, shows what it passes, and ends where the real one does.
static func update(h: Hero, delta: float) -> void:
	for a in h.arrows.duplicate():
		var n = a["node"]
		if not is_instance_valid(n):
			ArrowFx.end_flight(a)
			h.arrows.erase(a)
			continue
		if a.has("fresh"):
			a.erase("fresh")
			continue
		var m: Missile = a["m"]
		# a foe the real arrow just killed is still struck here: the sparks go with the killing blow
		m.step(h.game, delta, func(e) -> bool: return not e.dead or e.dead_t < 0.15, func(e) -> void: _struck(h, a, e))
		n.global_position = m.pos
		a["left"] = m.left
		ArrowFx.fly(a, n, delta, h.game)
		if m.done:
			ArrowFx.finish(h, str(a["kind"]), m.pos, a["dir"], m.wall)
			ArrowFx.end_flight(a)
			n.queue_free()
			h.arrows.erase(a)

## An arrow passing a foe: the entry flash, the cone out of his back and the sparks; a Glacial Shard's frost burst, a
## Storm Shot's lightning; a piercing fire arrow's flames climbing the body (Pyre: longer).
static func _struck(h: Hero, a: Dictionary, e) -> void:
	var kind: String = str(a["kind"])
	var w = h.game.world
	ArrowFx.pierce(h, kind, e, a["dir"])
	if kind == "frost":
		ElementalFx.frost_nova(h, w.fx_root, Vector3(e.global_position.x, w.height_at(e.global_position.x, e.global_position.z), e.global_position.z), 1.5)
		Sfx.play_at("ice_arrow_hit", e.global_position, -4.0, randf_range(0.95, 1.1))
	elif kind == "storm":
		ArcFx.charge(h, e.global_position + Vector3(0, 1.0, 0), ArcFx.STORM, 0.5)
	if bool(a["pierce"]) and kind == "fire":
		var k = Data.skill_def(str(a["src"])).get("k", {})
		var secs: float = float(k.get("burn_s", 3.0)) if k is Dictionary else 3.0
		FlameFx.burn(h.game, e, kind, secs * (1.0 + h.talent("burn_dmg") / 100.0))

static func clear(h: Hero) -> void:
	for a in h.arrows:
		ArrowFx.end_flight(a)
		if is_instance_valid(a["node"]):
			(a["node"] as Node3D).queue_free()
	h.arrows.clear()

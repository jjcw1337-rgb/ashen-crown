class_name SkillFx
extends RefCounted
## Co-op skill effects: every class's skill VISUALS run through here, on the caster's own game and on every
## partner's, where they play on his puppet (Hero.puppet).
##
## A skill's gameplay (damage, healing, mana, cooldowns, stuns) stays in the class's skill code. Whenever it
## wants something seen, it calls `Hero.fx(skill, event, data)`: that plays the event here at once on the local
## hero and, in co-op, sends it to every partner (one RPC, Net.pl_fx), whose game plays the same event on the
## caster's puppet. So the one handler draws it everywhere, and a partner's copy does nothing but draw: no
## damage, no healing, no sound ducking, no screen shake.
##
## An event is a small Dictionary: "s" the skill id ("attack" for the weapon), "e" the event name (a cast,
## an impact, a stage of a channel), and whatever that event needs: "p"/"q" points, "d" a direction, "y" a yaw,
## "x"/"r"/"n" numbers, "ps" a PackedVector3Array, "t" the enemies it touches (Enemy nodes here; net ids on the
## wire, `encode`/`decode`). Nothing is sent per frame: effects that run on (the Siphon tether, Drain Life's
## beams, Eternal Night, phantoms and arrows in flight) are state in `Hero.fxs` kept by `update` every frame on
## both ends, started and ended by events, and timing themselves out if an end is lost.
##
## Dispatch is by the skill's class (Data.SKILLS "cls"): KnightFx, WraithFx, DemonFx, WarlockFx, ArcherFx each
## have `play(h, ev) -> bool`. An event no class claims gets `_default`: a cast puff and an impact burst in the
## hero's colour, so a new class's skills show something to partners before it has any effects of its own.

## Plays one event on hero h (the caster himself, or his puppet on a partner's game).
static func play(h: Hero, ev: Dictionary) -> void:
	if h == null or not is_instance_valid(h) or h.game == null or h.game.world == null:
		return
	var sk: String = str(ev.get("s", ""))
	if sk == "roll":
		Dodge.fx(h, ev)       # the dodge roll, every class's
		return
	if SharedSkills.IDS.has(sk) and SharedFx.play(h, ev):
		return            # a shared skill: drawn the same whatever the hero's class
	var cls: String = str(Data.skill_def(sk).get("cls", "any"))
	if cls == "any":
		cls = h.cls
	var done := false
	match cls:
		"knight": done = KnightFx.play(h, ev)
		"wraith": done = WraithFx.play(h, ev)
		"demon": done = DemonFx.play(h, ev)
		"warlock": done = WarlockFx.play(h, ev)
		"archer": done = ArcherFx.play(h, ev)
		"doug": done = DougFx.play(h, ev)
		"wyrm", "serpent", "wyvern": done = ArcFx.play_dragon(h, ev)
	if not done:
		done = _common(h, ev)
	if not done:
		_default(h, ev)

## What every class shares: the weapon attack's sparks and the swipe finisher.
static func _common(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	if str(ev["s"]) != "attack":
		return false
	match str(ev["e"]):
		"hit":
			Fx.sparks(root, ev["p"], ev.get("c", Color(1.0, 0.75, 0.4)))
		"finisher":
			Fx.ring(root, h.global_position + Vector3(0, 0.05, 0), float(ev["r"]), h.trail_col, 0.35)
			Fx.burst(root, h.global_position + Vector3(0, 0.2, 0), Color(0.7, 0.62, 0.5, 0.5), 22, 3.5, 0.2, 0.5, false, -2.0, 180.0, Vector3.UP)
			shake(h, 0.28 if bool(ev.get("x", false)) else 0.1)
		_:
			return false
	return true

## A skill nobody draws yet: a puff of the class's colour on the cast, a burst at the impact.
static func _default(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"cast":
			Fx.flash(root, h.global_position + Vector3(0, 1.3, 0) + h.facing() * 0.4, h.trail_col, 1.5, 0.25, 3.5)
			Fx.burst(root, h.global_position + Vector3(0, 1.2, 0) + h.facing() * 0.4, h.trail_col, 12, 2.0, 0.08, 0.4, true, 0.0)
		"impact":
			var p: Vector3 = ev.get("p", h.global_position + h.facing())
			Fx.burst(root, p + Vector3(0, 0.8, 0), h.trail_col, 20, 3.5, 0.1, 0.45, true, 0.0)
			Fx.ring(root, Vector3(p.x, h.game.world.height_at(p.x, p.z), p.z), 1.8, h.trail_col, 0.35)

## Every frame, after the pose (the local hero's and the puppet's): whatever lingers moves with its hero.
static func update(h: Hero, delta: float) -> void:
	if h.game == null or h.game.world == null:
		return
	KnightFx.update(h, delta)
	WraithFx.update(h, delta)
	DemonFx.update(h, delta)
	WarlockFx.update(h, delta)
	ArcherFx.update(h, delta)
	DougFx.update(h, delta)

## Everything lingering is gone (death, a class change, a zone change).
static func clear(h: Hero) -> void:
	WraithFx.clear(h)
	DemonFx.clear(h)
	WarlockFx.clear(h)
	ArcherFx.clear(h)
	KnightFx.clear(h)
	DougFx.clear(h)
	h.fxs.clear()

# ---------------------------------------------------------------- helpers for the handlers
## The attack in progress (0..1, -1 for none) and its style, on the caster or his puppet.
static func atk(h: Hero) -> float:
	if h.puppet:
		return float(h.net_st.get("atk", -1.0))
	return (h.atk_t / h.atk_dur) if h.atk_t >= 0.0 else -1.0

static func style(h: Hero) -> String:
	if h.puppet:
		return str(h.net_st.get("style", ""))
	return h.atk_style if h.atk_t >= 0.0 else ""

## A sound of the skill: flat for the caster, from where his puppet stands for partners.
static func snd(h: Hero, nm: String, db := 0.0, pitch := 1.0) -> void:
	if h.puppet or h.bot:
		Sfx.play_at(nm, h.global_position, db - 2.0, pitch)
	else:
		Sfx.play(nm, db, pitch)

## Screen shake and hitstop belong to the caster's screen only.
static func shake(h: Hero, v: float) -> void:
	if h._mine():
		h.game.add_shake(v)

static func hitstop(h: Hero, t: float) -> void:
	if h._mine():
		h.game.hitstop(t)

static func duck(h: Hero, db: float, hold: float) -> void:
	if h._mine():
		Sfx.duck(db, hold)

## A hand of the rig (the mocap bodies carry at_hand_* followers).
static func hand(h: Hero, right: bool) -> Vector3:
	var J: Dictionary = h.rig.get_meta("j")
	var k := "hand_r" if right else "hand_l"
	return (J.get("at_" + k, J[k]) as Node3D).global_position

static func chest_of(e: Node3D, k := 0.9) -> Vector3:
	return e.global_position + Vector3(0, k * float(e.get("height")), 0)

static func free_later(n: Node, t: float) -> void:
	if n == null or not is_instance_valid(n):
		return
	var w: WeakRef = weakref(n)
	n.get_tree().create_timer(t, false).timeout.connect(func():
		var m: Node = w.get_ref() as Node
		if m != null and is_instance_valid(m):
			m.queue_free())

# ---------------------------------------------------------------- the wire
## Enemy nodes in "t" become ids: their net id in co-op, their instance id otherwise (tests round-trip them).
static func encode(net: Node, ev: Dictionary) -> Dictionary:
	var w := ev.duplicate()
	if w.has("t"):
		var ids := PackedInt64Array()
		for e in w["t"]:
			if e != null and is_instance_valid(e):
				ids.append(int(e.net_id) if net.active else e.get_instance_id())
		w["t"] = ids
	return w

static func decode(net: Node, w: Dictionary) -> Dictionary:
	var ev := w.duplicate()
	if ev.has("t"):
		var out := []
		for id in ev["t"]:
			var e = net.enemies.get(int(id)) if net.active else instance_from_id(int(id))
			if e != null and is_instance_valid(e) and e is Enemy and not e.dead:
				out.append(e)
		ev["t"] = out
	return ev

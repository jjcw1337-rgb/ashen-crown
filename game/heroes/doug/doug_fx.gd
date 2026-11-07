class_name DougFx
extends RefCounted
## What Doug's skills look like: every event (SkillFx.play -> here) is drawn on the caster and on his puppet for
## partners and PvP opponents, by his skills' own looks (skills/<skill>/<skill>_fx.gd), and the small ones here.
## Draws only: no damage, no cooldowns. Lingering things (the peels on the ground, the double, the bounce's arc, the
## car) live in Hero.fxs and are moved every frame by `update`, on the caster and on the puppet alike. His props are
## Meshy models in his skills' folders. Also here: what his looks share (the cream, the confetti, a prop's flight).
##  Cream Pie, Pie Barrage: "throw" {p, q: where it lands, x: seconds, r: its size}, "splat" {p, t} (CreamPieFx)
##  Banana Peels, Banana Bonanza: "land" {ps, x: seconds, q: flung from}, "slip" {p, t}, "gone" {p} (BananaPeelsFx)
##  Pratfall Slide: "honk"; Human Cannonball: "boom" {p, r}
##  Doppel-Doug: "start" {p, d, x: seconds unseen, r: the double's}, "pop" {p} (DoppelDougFx)
##  Pin Juggle: "pin" {ps: its path, t} (PinJuggleFx)
##  Big Top Bounce, Human Cannonball: "mark" {p, q: where he lands, x}, "flop" {p} (BigTopBounceFx)
##  Clown Car: "start" {p, x}, "ram" {p}, "burst" {p, t: the foes the clowns run at} (ClownCarFx)

const CONFETTI := [Color(1.0, 0.3, 0.35), Color(1.0, 0.85, 0.2), Color(0.35, 0.75, 1.0), Color(0.5, 1.0, 0.45)]
const CREAM := Color(1.0, 0.97, 0.88)

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev.get("s", "")):
		"pie":
			return CreamPieFx.play(h, ev)
		"peels":
			return BananaPeelsFx.play(h, ev)
		"doppel":
			return DoppelDougFx.play(h, ev)
		"juggle":
			return PinJuggleFx.play(h, ev)
		"bounce":
			return BigTopBounceFx.play(h, ev)
		"car":
			return ClownCarFx.play(h, ev)
	match str(ev.get("s", "")) + ":" + str(ev.get("e", "")):
		"slide:honk":
			SkillFx.snd(h, "doug_honk", -2.0)
			h.fxs["slide_t"] = 0.6
		"u_cannon:boom":
			var bp: Vector3 = ev["p"]
			var br: float = float(ev.get("r", 4.5))
			confetti(root, bp + Vector3(0, 0.8, 0), 2.0)
			Fx.ring(root, bp, br, Color(1.0, 0.85, 0.3), 0.5)
			Fx.burst(root, bp + Vector3(0, 0.4, 0), Color(0.6, 0.5, 0.4), 30, 5.0, 0.14, 0.6, false, -8.0)
			Fx.flash(root, bp + Vector3(0, 1.0, 0), Color(1.0, 0.8, 0.4), 4.0, 0.3, 8.0)
			SkillFx.snd(h, "boom", -2.0, 1.1)
		_:
			return false
	return true

## A prop flying from a to b along an arc (`lift` metres up at the middle), spinning, then gone; `delay` first.
static func fly(root: Node3D, prop: String, a: Vector3, b: Vector3, dur: float, lift: float, sc: float, delay := 0.0, burning := false) -> void:
	var m := ResCache.inst(prop) as Node3D
	if m == null:
		m = MeshInstance3D.new()
		(m as MeshInstance3D).mesh = Geo.sph(0.12, 8)
	var holder := Node3D.new()
	holder.add_child(m)
	m.scale = Vector3.ONE * sc
	root.add_child(holder)
	holder.global_position = a
	holder.visible = delay <= 0.0
	if burning:
		Fx.aura(holder, Color(1.0, 0.5, 0.15), 14, 0.6, 0.08, 0.4, 0.3, 0.1)
	var tw := holder.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func(): holder.visible = true)
	tw.tween_method(func(k: float):
		if not is_instance_valid(holder):
			return
		holder.global_position = a.lerp(b, k) + Vector3(0, sin(k * PI) * lift, 0)
		m.rotation = Vector3(k * TAU * 2.0, k * TAU, 0.0), 0.0, 1.0, dur)
	tw.tween_callback(holder.queue_free)

static func confetti(root: Node3D, p: Vector3, k: float) -> void:
	for c in CONFETTI:
		Fx.burst(root, p, c, int(14 * k), 4.5 * k, 0.07, 1.1, false, -3.0, 180.0)

## Every frame (caster and puppet): the peels' timers, the double running, the hiding fade, the bounce's arc, the car.
static func update(h: Hero, delta: float) -> void:
	if h.fxs.is_empty():
		return
	BananaPeelsFx.update(h, delta)
	DoppelDougFx.update(h, delta)
	BigTopBounceFx.update(h, delta)
	ClownCarFx.update(h, delta)

static func clear(h: Hero) -> void:
	BananaPeelsFx.clear(h)
	DoppelDougFx.clear(h)
	ClownCarFx.clear(h)

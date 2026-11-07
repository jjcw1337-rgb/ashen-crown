class_name ClownCarFx
extends RefCounted
## What the Clown Car looks like (DougFx hands its events here): "start" puts him in the Meshy car (car.glb) with a
## klaxon and confetti, for "x" seconds; "ram" a burst and a slam on the foe rammed; "burst" bursts the car in
## confetti and sends a mini clown (a small Doug) running at each foe in "t", a pie in its face. Draws only.

const CAR := "res://game/heroes/doug/skills/clown_car/car.glb"

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev.get("e", "")):
		"start":
			var car := ResCache.inst(CAR) as Node3D
			if car != null:
				car.name = "clown_car"
				car.scale = Vector3.ONE * 0.9
				h.add_child(car)
				car.position = Vector3(0, 0, 0)
				car.rotation.y = -PI * 0.5      # the model's bonnet is along -x: turn it to his facing (-z)
				h.fxs["car"] = car
				h.fxs["car_t"] = float(ev.get("x", 5.0))
			SkillFx.snd(h, "doug_klaxon", 0.0)
			DougFx.confetti(root, ev["p"] + Vector3(0, 0.8, 0), 0.8)
		"ram":
			Fx.burst(root, ev["p"] + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.3), 16, 4.0, 0.1, 0.4, true, -4.0)
			SkillFx.snd(h, "slam", -6.0, 1.4)
			SkillFx.shake(h, 0.15)
		"burst":
			_end_car(h)
			var p4: Vector3 = ev["p"]
			DougFx.confetti(root, p4 + Vector3(0, 1.0, 0), 2.0)
			SkillFx.snd(h, "doug_pop", 2.0, 0.8)
			for t in ev.get("t", []):
				if is_instance_valid(t):
					_mini(root, p4, t.global_position)
		_:
			return false
	return true

## A mini clown: a small Doug running from the car to his foe, then a pie in its face.
static func _mini(root: Node3D, from: Vector3, to: Vector3) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = from + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	if DougBody.model_ok():
		var d: Node3D = ResCache.inst(DougBody.GLB)
		d.scale = Vector3.ONE * 0.45
		holder.add_child(d)
		var ap := d.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null and ap.has_animation("run_fast"):
			ap.play("run_fast")
	var dir := to - holder.global_position
	dir.y = 0
	holder.rotation.y = atan2(-dir.x, -dir.z)
	var tw := holder.create_tween()
	tw.tween_property(holder, "global_position", Vector3(to.x, holder.global_position.y, to.z) - dir.normalized() * 0.6, 0.8)
	tw.tween_callback(func():
		Fx.burst(root, to + Vector3(0, 1.0, 0), DougFx.CREAM, 24, 3.0, 0.12, 0.5, false, -9.0)
		DougFx.confetti(root, holder.global_position + Vector3(0, 0.5, 0), 0.4))
	tw.tween_callback(holder.queue_free)

static func _end_car(h: Hero) -> void:
	var car = h.fxs.get("car")
	if car != null and is_instance_valid(car):
		car.queue_free()
	h.fxs.erase("car")
	h.fxs.erase("car_t")

## Every frame: the car goes by itself a moment after its time (if the burst is lost).
static func update(h: Hero, delta: float) -> void:
	if h.fxs.has("car_t"):
		h.fxs["car_t"] = float(h.fxs["car_t"]) - delta
		if float(h.fxs["car_t"]) < -1.0:
			_end_car(h)

static func clear(h: Hero) -> void:
	_end_car(h)

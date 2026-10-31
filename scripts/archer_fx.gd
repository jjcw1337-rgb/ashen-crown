class_name ArcherFx
extends RefCounted
## Visual effects for the archer's skills (SkillFx events; the gameplay is in archer.gd). What flies or lies in
## wait is raised here on the archer's own game and on his puppet on every partner's (Hero.arrows, volleys,
## snares), and Archer.update moves it on both: a puppet's arrows stop and spark on a foe but hurt nothing,
## its volley rains without hitting, its snares wait for the "spring" event instead of springing themselves.
##  the attack / Fire Arrow: "loose" {p: from, d: direction, k: "war"|"fire", x: it pierces}
##  Frost Volley: "impact" {p: the ground, r: radius}
##  Storm Snare: "impact" {p, n: how many he may keep}, "spring" {p, r, t: the foes its lightning reaches}
##  Spirit Beast: "impact" {p: the point, t: [the foe] when it was sent at one, x: called home} (the command's
##    rings and the roar; a puppet's own wolf (Archer.keep_companions) takes the same command and only shows its bites)

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match [str(ev["s"]), str(ev["e"])]:
		["pierce", "cast"], ["volley", "cast"], ["snare", "cast"], ["beast", "cast"]:
			pass
		["attack", "loose"], ["pierce", "loose"]:
			var from: Vector3 = ev["p"]
			var dir: Vector3 = ev["d"]
			var n := Archer._arrow_mesh(str(ev.get("k", "war")))
			root.add_child(n)
			n.global_position = from
			n.look_at(from + dir, Vector3.UP)
			h.arrows.append({"node": n, "dir": dir, "left": Archer.RANGE + 5.0, "pierce": bool(ev.get("x", false)), "hit": {},
				"mult": float(ev.get("m", 1.0)), "src": str(ev["s"])})
		["volley", "impact"]:
			var g: Vector3 = ev["p"]
			var r: float = float(ev.get("r", Archer.VOLLEY_R))
			h.volleys.append({"pos": g, "t": 1.3, "tick": 0.25, "r": r})
			Fx.telegraph(root, g, r, 0.25, Archer.FROST)
			# the flight going up
			for k in 5:
				var up := Archer._arrow_mesh("frost")
				root.add_child(up)
				var p0: Vector3 = h.global_position + Vector3(randf_range(-0.3, 0.3), 1.6, randf_range(-0.3, 0.3))
				up.global_position = p0
				up.look_at(p0 + Vector3(randf_range(-0.2, 0.2), 1.0, randf_range(-0.2, 0.2)), Vector3.FORWARD)
				var tw := up.create_tween()
				tw.tween_property(up, "global_position", p0 + Vector3(0, 9.0, 0), 0.3)
				tw.tween_callback(up.queue_free)
		["snare", "impact"]:
			var g: Vector3 = ev["p"]
			var mx: int = int(ev.get("n", 2))
			while h.snares.size() >= mx and not h.snares.is_empty():
				var old: Dictionary = h.snares.pop_front()
				if is_instance_valid(old["node"]):
					(old["node"] as Node3D).queue_free()
			var n := Archer._snare_mesh()
			root.add_child(n)
			n.global_position = g + Vector3(0, 0.03, 0)
			h.snares.append({"node": n, "pos": g, "t": 20.0})
			Fx.ring(root, g, 0.9, Archer.HUNTER, 0.4)
			Sfx.play_at("impact_metal", g, -8.0, 1.3)
		["snare", "spring"]:
			var pos: Vector3 = ev["p"]
			var r: float = float(ev.get("r", Archer.SNARE_R))
			var from := pos + Vector3(0, 0.4, 0)
			for e in ev.get("t", []):
				Fx.bolt(root, from, e.global_position + Vector3(0, e.height * 0.9, 0), Archer.STORM)
			Fx.flash(root, from, Archer.STORM, 4.0, 0.25, 6.0)
			Sfx.play_at("impact_metal", pos, -4.0, 1.6)
			# the trap that sprang: the one lying there
			var best = null
			var bd := 1.5
			for s in h.snares:
				var d: float = (s["pos"] as Vector3).distance_to(pos)
				if d < bd:
					bd = d
					best = s
			if best != null:
				h.snares.erase(best)
				var n: Node3D = best["node"]
				if is_instance_valid(n):
					var tw := n.create_tween().set_parallel(true)
					for j in ["jaw_l", "jaw_r"]:
						tw.tween_property(n.get_node(j), "rotation:z", 0.0, 0.08)
					tw.chain().tween_interval(0.8)
					tw.chain().tween_callback(n.queue_free)
			Fx.sparks(root, pos + Vector3(0, 0.3, 0), Color(0.9, 0.85, 0.7))
			Fx.ring(root, pos, r, Archer.HUNTER, 0.35)
			Sfx.play_at("impact_metal", pos, 0.0, 0.8)
			SkillFx.shake(h, 0.1)
		["beast", "impact"]:
			var foes: Array = ev.get("t", [])
			var foe = foes[0] if not foes.is_empty() else null
			var home: bool = bool(ev.get("x", false))
			var aim: Vector3 = ev["p"]
			for b in h.beasts:
				if not is_instance_valid(b) or b.dead:
					continue
				if foe != null:
					b.command("attack", foe)
				elif home:
					b.command("follow")
				else:
					b.command("hold", null, aim)
			if foe != null:
				Fx.ring(root, foe.global_position, 1.2, Archer.HUNTER, 0.4)
			elif not home:
				Fx.ring(root, aim, 1.5, Archer.HUNTER, 0.5)
			SkillFx.snd(h, "lion_roar", -4.0, 1.25)
			SkillFx.shake(h, 0.15)
		_:
			return false
	return true

## Arrows, volleys and snares move in Archer.update (the puppet's too).
static func update(_h: Hero, _delta: float) -> void:
	pass

static func clear(h: Hero) -> void:
	Archer.clear(h)

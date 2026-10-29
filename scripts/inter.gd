class_name Inter
extends Node3D
## Something the hero can click on: vendors, stash, waypoint, exits, shrines, chests, Sunstar Blooms.

var kind := ""
var label := ""
var radius := 1.6
var data := {}
var rig: Node3D = null
var _t := 0.0
var used := false
# a Meshy-animated shopkeeper (ForestCamp): the model, its AnimationPlayer and its clips
# ("idle", "work", "talk"); works at its trade while the hero is away, turns to face and talks when near
var model: Node3D = null
var anim: AnimationPlayer = null
var clips := {}
var home_yaw := 0.0
var _clip_t := 0.0
var _talked := 0.0

func _animate(delta: float) -> void:
	var near := false
	var want := home_yaw
	var heroes := get_tree().get_nodes_in_group("hero")
	if heroes.size() > 0:
		var d: Vector3 = (heroes[0] as Node3D).global_position - global_position
		if Vector2(d.x, d.z).length() < 6.5:
			near = true
			want = atan2(d.x, d.z)       # Meshy models face +z
	model.rotation.y = lerp_angle(model.rotation.y, want, delta * (3.0 if near else 1.2))
	_clip_t -= delta
	_talked = maxf(0.0, _talked - delta)
	var cur := anim.current_animation
	var works: Array = clips.get("work", []) if clips.get("work") is Array else [clips.get("work", "")]
	# walking up interrupts the work: greet once, then wait (idle) while the hero shops
	if near and cur in works and clips.has("talk") and _talked <= 0.0:
		_clip_t = 0.0
	if _clip_t > 0.0:
		return
	var next: String = clips.get("idle", "")
	if near:
		if clips.has("talk") and _talked <= 0.0:
			next = clips["talk"]
			_talked = 9.0
	elif not works.is_empty() and works[0] != "" and randf() < 0.8:
		next = works[randi() % works.size()]
	if next == "" or not anim.has_animation(next):
		return
	anim.play(next, 0.45)
	var a := anim.get_animation(next)
	_clip_t = a.length * (1.0 if next == clips.get("talk", "") else float(randi_range(2, 3)))

func _process(delta: float) -> void:
	_t += delta
	if anim and model:
		_animate(delta)
	if rig:
		var face := 0.0
		var heroes := get_tree().get_nodes_in_group("hero")
		if heroes.size() > 0:
			var hp: Vector3 = (heroes[0] as Node3D).global_position
			var d := hp - global_position
			if Vector2(d.x, d.z).length() < 9.0:
				var want := atan2(-d.x, -d.z)
				rig.rotation.y = lerp_angle(rig.rotation.y, want, delta * 3.0)
		var gesture := -1.0
		var cyc := fmod(_t + data.get("offset", 0.0), 9.0)
		if cyc > 7.6 and not data.get("still", false):
			gesture = (cyc - 7.6) / 1.4
		Anim.pose(rig, {"time": _t, "phase": 0.0, "move": 0.0, "atk": gesture * 0.35 if gesture >= 0.0 else -1.0, "style": "cast"})
	if kind == "flower" and not used:
		# a Sunstar Bloom's glow breathes, so it catches the eye between the trees
		var fl := get_node_or_null("Model/light") as OmniLight3D
		if fl:
			fl.light_energy = 1.5 + sin(_t * 1.8 + position.x * 0.7) * 0.5
	if kind == "waypoint":
		var c := get_node_or_null("Model/crystal")
		if c:
			c.rotation.y += delta * 0.8
			c.position.y = 1.4 + sin(_t * 1.5) * 0.08

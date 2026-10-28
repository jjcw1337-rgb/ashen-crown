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

func _process(delta: float) -> void:
	_t += delta
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
		if cyc > 7.6:
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

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
# a keeper whose work makes a sound at each blow (the smith's hammer on the anvil: clips "strike"): the hand
# bone carrying the tool, tracked to hear it land
var _hand: Node3D = null
var _hand_y := 0.0
var _hand_vy := 0.0
var _hand_top := -1e9
var _strike_cd := 0.0
var _fall := 0.0

var _walk_to := Vector3.INF
var _patrol_i := 0

## A keeper who gets about (clips "patrol": {"points": [Vector3...], "walk": clip, "speed": m/s, "face": [yaw per point],
## "chance", "works": [clips per point]}; Osric between his
## hull and the pier with a plank): after a spell of work, off to the next point at a walk, turning the way he goes;
## a hero coming near stops him, and he turns and talks as the others do. Cosmetic and local to each game.
func _patrol(delta: float, near: bool) -> bool:
	var pt: Dictionary = clips.get("patrol", {})
	if pt.is_empty():
		return false
	var pts: Array = pt.get("points", [])
	if _walk_to == Vector3.INF or near:
		return false
	var to := _walk_to - global_position
	to.y = 0
	if to.length() < 0.15:
		global_position = Vector3(_walk_to.x, global_position.y, _walk_to.z)
		_walk_to = Vector3.INF
		_clip_t = 0.0
		home_yaw = float(pt.get("face", [])[_patrol_i]) if (pt.get("face", []) as Array).size() > _patrol_i else model.rotation.y
		return false
	var step := minf(float(pt.get("speed", 1.1)) * delta, to.length())
	global_position += to.normalized() * step
	if game_world_height != null:
		global_position.y = game_world_height.call(global_position.x, global_position.z)
	model.rotation.y = lerp_angle(model.rotation.y, atan2(to.x, to.z), delta * 4.0)
	var walk := str(pt.get("walk", ""))
	if walk != "" and anim.has_animation(walk) and anim.current_animation != walk:
		anim.play(walk, 0.35)
	return true

var game_world_height: Variant = null

func _animate(delta: float) -> void:
	var near := false
	var want := home_yaw
	# a keeper who stays at his work (the smith at his anvil) greets once a visit, never turns from it
	var stay: bool = clips.get("stay", false)
	var heroes := get_tree().get_nodes_in_group("hero")
	if heroes.size() > 0:
		var d: Vector3 = (heroes[0] as Node3D).global_position - global_position
		if Vector2(d.x, d.z).length() < 6.5:
			near = true
			if not stay:
				want = atan2(d.x, d.z)       # Meshy models face +z
	if _patrol(delta, near):
		return
	model.rotation.y = lerp_angle(model.rotation.y, want, delta * (3.0 if near else 1.2))
	_clip_t -= delta
	if not (stay and near):
		_talked = maxf(0.0, _talked - delta)
	var cur := anim.current_animation
	var works: Array = clips.get("work", []) if clips.get("work") is Array else [clips.get("work", "")]
	var by_spot: Array = (clips.get("patrol", {}) as Dictionary).get("works", [])
	if by_spot.size() > _patrol_i:
		works = by_spot[_patrol_i]        # a keeper on a round has the work of the spot he's at
	# walking up interrupts the work: greet once, then wait (idle) while the hero shops
	if near and cur in works and clips.has("talk") and _talked <= 0.0:
		_clip_t = 0.0
	if _clip_t > 0.0:
		return
	var next: String = clips.get("idle", "")
	if near and clips.has("talk") and _talked <= 0.0:
		next = clips["talk"]
		_talked = 9.0
	elif near and not stay:
		pass
	elif not works.is_empty() and works[0] != "" and randf() < 0.8:
		next = works[randi() % works.size()]
	# a keeper on a round: now and then, off to the next spot instead
	var pt: Dictionary = clips.get("patrol", {})
	if not near and not pt.is_empty() and randf() < float(pt.get("chance", 0.35)):
		var pts: Array = pt.get("points", [])
		if pts.size() > 1:
			_patrol_i = (_patrol_i + 1) % pts.size()
			_walk_to = pts[_patrol_i]
			return
	if next == "" or not anim.has_animation(next):
		return
	anim.play(next, 0.45)
	var a := anim.get_animation(next)
	_clip_t = a.length * (1.0 if next == clips.get("talk", "") else float(randi_range(2, 3)))

func _process(delta: float) -> void:
	_t += delta
	if anim and model:
		_animate(delta)
		if clips.has("strike"):
			_strikes(delta)

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

## The hammer coming down on the metal: the moment the tool hand stops falling and rebounds, low in its
## swing, during a work clip. A ring of the anvil there, and a few sparks.
func _strikes(delta: float) -> void:
	_strike_cd -= delta
	if _hand == null:
		for c in model.find_children("*", "BoneAttachment3D", true, false):
			_hand = c
			break
		if _hand == null:
			return
		_hand_y = _hand.global_position.y
	var works: Array = clips.get("work", []) if clips.get("work") is Array else [clips.get("work", "")]
	var y: float = _hand.global_position.y
	var vy := (y - _hand_y) / maxf(delta, 0.001)
	_hand_y = y
	if not (anim.current_animation in works):
		_hand_top = -1e9
		_hand_vy = vy
		return
	_hand_top = maxf(_hand_top - delta * 0.5, y)
	# the fastest fall of the last moment (a high frame rate eases through the stop over several frames)
	_fall = vy if vy < _fall else move_toward(_fall, 0.0, delta * 8.0)
	# falling fast a moment ago, now stopped or rising, and well below the top of the swing
	if (_hand_vy < -1.2 or _fall < -1.2) and vy > -0.2 and _hand_top - y > 0.25 and _strike_cd <= 0.0:
		_strike_cd = 0.35
		_fall = 0.0
		var at: Vector3 = _hand.global_position
		Sfx.play_at(str(clips["strike"]), at, -2.0, randf_range(0.97, 1.08))
		if game_fx() != null and clips.get("sparks", true):
			Fx.sparks(game_fx(), at + Vector3(0, 0.05, 0), Color(1.0, 0.7, 0.3))
	_hand_vy = vy

func game_fx() -> Node3D:
	var w = get_parent()
	while w != null and not (w is World):
		w = w.get_parent()
	return (w as World).fx_root if w != null else null

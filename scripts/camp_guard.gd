class_name CampGuard
extends Node3D
## The Act I camp's guards (jj, 2026-11-04): three armoured hand-to-hand fighters keeping the Forsaken Wilds, each a
## Meshy character on the playable bodies' 24-bone rig (concept, image-to-3D, Meshy's auto-rig and clip library,
## tools/blender/guards/prep_guard.py) in assets/models/guards/<id>.glb, with the clip measurements beside it in
## <id>.json (each clip's length, its ground motion forward and to the side, a turn's angle, a strike's landing
## moments). See docs/guards.md for the sources, the clips and what's still to come.
## - Patrol: each walks his own round of posts (GUARDS "posts": a spot, what he watches there, how long), finding
##   his way with World.find_path; at a post he scans: turns in place to look another way (the turn clips, the body
##   turned by the measured angle), looks about, stands alert, warms up, his own flourish ("extra").
## - Heroes: one coming near is watched: he stops, turns to face them, stands alert and tracks them with his head
##   (HeadLook, a SkeletonModifier3D over the clips), then goes back to his round.
## - Fighting: a monster inside the camp is run down and fought hand to hand: he closes in, circles and strafes
##   round it, steps back out, and strikes from his three attack slots ("slots": a skill id to come, the clip, its
##   reach, damage and cooldown; "skill" is empty for now, a plain blow). Damage is the host's (Enemy.take_hit, no
##   xp or loot); everything else runs on every game, like the shopkeepers. Guards can't be hurt yet.
## Every move is the clip's own: the body travels by the clip's measured ground motion (World.move, so he slides
## along the stalls), so feet never slide. Shadows: the bodies cast them like the traders and the waypoint do.

const DIR := "res://assets/models/guards/"
const WATCH_R := 7.5          # a hero this near is noticed
const LOOK_R := 10.0          # ... and followed with the head out to here
const WATCH_CD := 14.0        # seconds before the same guard stops for a hero again
const AGGRO_R := 13.0         # a monster this near (and inside the camp) is fought
const LEASH := 26.0           # never chases past the camp's ring (ForestCamp.RADIUS)
const BODY_R := 0.42
const SCALE := 1.08           # a touch over life size, so they read from the game's camera like the stalls do
const RIM := 0.22             # the silhouette's rim light (RIM_SHADER), so the dark armour stands out at dusk
const FILL := 0.6             # a soft light of their own over the shoulders
const RECOVER := 0.5           # seconds of a strike's follow-through kept after its last blow
const LOOPS := ["idle", "walk", "walk_back", "walk_look", "run", "combat_idle", "walk_fight", "walk_fight_back",
	"strafe_l", "strafe_r", "alert"]
# camp coordinates (ForestCamp: CENTER (0, -2), RADIUS 25, the north gate at z -27, the west gate at x -25)
const GUARDS := [
	# the gate warden: heavy plate, the green surcoat with the ember; keeps the north gate and the forge
	{"id": "warden", "name": "Warden Bram", "dmg": 1.25, "rim": Color(1.0, 0.5, 0.2), "fill": Color(1.0, 0.72, 0.5),
		"posts": [
			{"at": Vector2(-1.2, -22.3), "look": Vector2(0, -34), "wait": [10.0, 16.0]},
			{"at": Vector2(4.4, -16.6), "look": Vector2(10, -12), "wait": [5.0, 8.0]},
			{"at": Vector2(8.4, -8.2), "look": Vector2(14, -3), "wait": [6.0, 10.0]},
			{"at": Vector2(0.4, -9.4), "look": Vector2(3.5, -5), "wait": [5.0, 8.0]}],
		"slots": [
			{"skill": "", "clip": "strike_1", "reach": 1.9, "dmg": 1.3, "cd": 1.1},    # both fists driven forward
			{"skill": "", "clip": "strike_2", "reach": 1.5, "dmg": 1.0, "cd": 0.8},    # the elbow
			{"skill": "", "clip": "strike_3", "reach": 2.0, "dmg": 1.4, "cd": 1.3}]},  # the Spartan kick
	# the sentry: lean and quick, mail and studded leather, the wolf-fur mantle; walks the whole ring
	{"id": "sentry", "name": "Sentry Kell", "dmg": 0.9, "rim": Color(0.65, 0.8, 1.0), "fill": Color(0.8, 0.88, 1.0),
		"night_lamp": true,                       # carries a lantern on his night rounds (DayNight)
		"posts": [
			{"at": Vector2(-20.4, -2.0), "look": Vector2(-34, -2), "wait": [7.0, 11.0]},
			{"at": Vector2(-13.0, -3.4), "look": Vector2(-17, -6.5), "wait": [3.0, 5.0]},
			{"at": Vector2(-9.2, -8.2), "look": Vector2(-12, -11.5), "wait": [3.0, 5.0]},
			{"at": Vector2(-2.2, -16.6), "look": Vector2(0, -27), "wait": [3.0, 6.0]},
			{"at": Vector2(9.4, -7.6), "look": Vector2(12, -11.5), "wait": [3.0, 5.0]},
			{"at": Vector2(12.2, 2.2), "look": Vector2(16, 5), "wait": [3.0, 5.0]},
			{"at": Vector2(7.0, 10.6), "look": Vector2(9.5, 13.5), "wait": [4.0, 7.0]},
			{"at": Vector2(-1.0, 13.8), "look": Vector2(0, 26), "wait": [4.0, 7.0]},
			{"at": Vector2(-13.6, 5.0), "look": Vector2(-25, 7), "wait": [3.0, 6.0]}],
		"slots": [
			{"skill": "", "clip": "strike_1", "reach": 1.6, "dmg": 0.8, "cd": 0.45},   # the left jab
			{"skill": "", "clip": "strike_2", "reach": 1.5, "dmg": 1.1, "cd": 0.7},    # the right upper hook
			{"skill": "", "clip": "strike_3", "reach": 2.0, "dmg": 1.3, "cd": 1.0}]},  # the roundhouse kick
	# the ironfist: the veteran in lamellar and the horned visor, the cestus gauntlets; the waypoint and the Vigil Gate
	{"id": "ironfist", "name": "Ironfist Varg", "dmg": 1.1, "rim": Color(1.0, 0.62, 0.3), "fill": Color(1.0, 0.7, 0.45),
		"lantern": Vector3(-0.3, 0.92, 0.06),       # the iron lantern at his right hip (model space, as modelled)
		"posts": [
			{"at": Vector2(-2.3, 0.3), "look": Vector2(-8, 6), "wait": [9.0, 14.0]},
			{"at": Vector2(-12.6, 8.8), "look": Vector2(-22, 13), "wait": [5.0, 8.0]},
			{"at": Vector2(6.2, 9.4), "look": Vector2(9.5, 13.5), "wait": [9.0, 14.0]},
			{"at": Vector2(5.6, 0.8), "look": Vector2(13, 2), "wait": [5.0, 8.0]}],
		"slots": [
			{"skill": "", "clip": "strike_1", "reach": 1.7, "dmg": 1.0, "cd": 1.2},    # the punch combo
			{"skill": "", "clip": "strike_2", "reach": 1.5, "dmg": 1.2, "cd": 0.8},    # the right uppercut
			{"skill": "", "clip": "strike_3", "reach": 1.6, "dmg": 1.3, "cd": 0.9}]},  # the stepping knee
]

var def: Dictionary
var world: World
var game: Node
var model: Node3D
var anim: AnimationPlayer
var meta := {}                 # clip -> {"len", "fwd", "side", "turn", "hits"} (prep_guard.py)
var head: HeadLook
var state := "post"            # post, walk, watch, fight
var post_i := 0
var path := PackedVector3Array()
var path_i := 0
var yaw := 0.0                 # the body's facing (Meshy models face +z)
var clip := ""
var act_left := 0.0            # seconds left of a one-shot clip (a look, a turn, a strike)
var wait_left := 0.0           # at a post: how long before moving on
var turn_from := 0.0
var turn_by := 0.0
var turn_len := 0.0
var turn_t := -1.0
var watch_cd := 0.0
var watch_left := 0.0
var watched: Node3D = null
var target: Enemy = null
var slot_i := 0
var cooldown := 0.0
var hits_left: Array = []      # the landing moments of the strike in progress (seconds left)
var per_hit := 1.0
var think_t := 0.0
var dance_left := 0.0
var _rng := RandomNumberGenerator.new()
var posts_at: Array = []       # each post's spot, nudged clear of what's solid
var rim_mat: ShaderMaterial
var fill: OmniLight3D
var night_lamp: Node3D = null  # the lantern a night-rounds guard carries ("night_lamp" in GUARDS)
var _hand_l: BoneAttachment3D = null
var _swing := 0.0
var _stuck := 0.0
var _gap := INF

static func ok(id: String) -> bool:
	return ResourceLoader.exists(DIR + id + ".glb")

## Places the guards that have their models (ForestCamp.build, after the camp is laid out).
static func place_all(w: World) -> Array:
	var out := []
	for i in GUARDS.size():
		var d: Dictionary = GUARDS[i]
		if not ok(d["id"]):
			continue
		var g := CampGuard.new()
		g.name = "Guard_" + str(d["id"])
		g.def = d
		g.world = w
		g._rng.seed = 7100 + i * 37
		w.props_root.add_child(g)
		var p0: Vector2 = (d["posts"] as Array)[0]["at"]
		g.global_position = Vector3(p0.x, w.height_at(p0.x, p0.y), p0.y)
		out.append(g)
	return out

func _ready() -> void:
	game = world.get_parent()
	model = (load(DIR + str(def["id"]) + ".glb") as PackedScene).instantiate()
	model.name = "Body"
	add_child(model)
	model.scale = Vector3.ONE * SCALE
	for n in model.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_dress()
	for pt in def["posts"]:
		var at: Vector2 = pt["at"]
		var q := world.free_spot_near(Vector3(at.x, 0, at.y), BODY_R + 0.15)
		posts_at.append(Vector2(q.x, q.z))
	var mp := DIR + str(def["id"]) + ".json"
	if ResourceLoader.exists(mp):
		var js := load(mp) as JSON         # (a JSON resource, so the export carries it)
		if js != null and js.data is Dictionary:
			meta = js.data
	anim = model.find_child("AnimationPlayer", true, false)
	for an in anim.get_animation_list():
		var a := anim.get_animation(an)
		a.loop_mode = Animation.LOOP_LINEAR if an in LOOPS else Animation.LOOP_NONE
		_unroot(a)
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	if sk != null:
		head = HeadLook.new()
		head.body = model
		sk.add_child(head)
		head.setup(sk)
	yaw = _yaw_to((def["posts"] as Array)[0]["look"])
	model.rotation.y = yaw
	_play("idle", 0.0)
	anim.seek(_rng.randf() * 2.0, true)
	wait_left = _rng.randf_range(2.0, 6.0)

## The clips walk the hips about (Meshy's library keeps the root motion on the hips): take out each clip's drift from
## its first frame to its last, keeping the sway and the bob. The body is moved by the measured motion instead.
static func _unroot(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D or not str(a.track_get_path(t)).ends_with(":Hips"):
			continue
		var n := a.track_get_key_count(t)
		if n < 2:
			continue
		var p0: Vector3 = a.track_get_key_value(t, 0)
		var p1: Vector3 = a.track_get_key_value(t, n - 1)
		var t0 := a.track_get_key_time(t, 0)
		var t1 := maxf(a.track_get_key_time(t, n - 1), t0 + 0.001)
		var drift := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
		for k in n:
			var v: Vector3 = a.track_get_key_value(t, k)
			var f := (a.track_get_key_time(t, k) - t0) / (t1 - t0)
			a.track_set_key_value(t, k, v - drift * f)

func _play(c: String, blend := 0.3, spd := 1.0) -> void:
	if not anim.has_animation(c):
		c = "idle"
	if c == clip and anim.is_playing():
		anim.speed_scale = spd
		return
	clip = c
	anim.play(c, blend)
	anim.speed_scale = spd
	if not (c in LOOPS):
		act_left = clip_len(c) / maxf(spd, 0.01)

func clip_len(c: String) -> float:
	if meta.has(c):
		return float(meta[c].get("len", 1.0))
	return anim.get_animation(c).length if anim.has_animation(c) else 1.0

func _yaw_to(p: Vector2) -> float:
	return atan2(p.x - global_position.x, p.y - global_position.z)

func _heroes() -> Array:
	return get_tree().get_nodes_in_group("hero")

func _process(delta: float) -> void:
	if anim == null:
		return
	watch_cd -= delta
	cooldown -= delta
	act_left -= delta
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.25
		_think()
	match state:
		"post": _at_post(delta)
		"walk": _walk(delta)
		"watch": _watch(delta)
		"fight": _fight(delta)
	_turning(delta)
	_root_motion(delta)
	model.rotation.y = yaw
	_look(delta)
	_night(delta)

## Every quarter second: a monster in the camp to fight, a hero coming near to watch.
func _think() -> void:
	if state != "fight":
		var e := _foe()
		if e != null:
			target = e
			state = "fight"
			turn_t = -1.0
			dance_left = 0.0
			if anim.current_animation in ["look", "look_long", "warmup", "extra"]:
				act_left = 0.0
			return
	if state == "post" or state == "walk":
		if watch_cd > 0.0 or turn_t >= 0.0:
			return
		for h in _heroes():
			var hn := h as Node3D
			if hn.global_position.distance_to(global_position) < WATCH_R:
				watched = hn
				watch_left = _rng.randf_range(3.5, 5.5)
				watch_cd = WATCH_CD
				state = "watch"
				act_left = 0.0
				_turn_toward(_yaw_to(Vector2(hn.global_position.x, hn.global_position.z)), true)
				return

func _foe() -> Enemy:
	if world == null or world.enemies_root == null:
		return null
	var best: Enemy = null
	var bd := AGGRO_R
	for e in world.enemies_root.get_children():
		if not (e is Enemy) or (e as Enemy).dead:
			continue
		var en := e as Enemy
		var d := en.global_position.distance_to(global_position)
		var c := Vector2(en.global_position.x, en.global_position.z).distance_to(ForestCamp.CENTER)
		if d < bd and c < LEASH:
			bd = d
			best = en
	return best

# --- the round ----------------------------------------------------------------------------------------------------

func _post() -> Dictionary:
	return (def["posts"] as Array)[post_i]

func _at_post(_delta: float) -> void:
	if turn_t >= 0.0 or act_left > 0.0:
		return
	if wait_left <= 0.0:
		_next_post()
		return
	# scanning: every action is a clip; between them, the idle
	var r := _rng.randf()
	var look: Vector2 = _post()["look"]
	var base := _yaw_to(look)
	if r < 0.30:
		_play("idle", 0.35)
		act_left = _rng.randf_range(1.6, 3.2)
	elif r < 0.50:
		_play("look" if _rng.randf() < 0.6 else "look_long", 0.35)
	elif r < 0.72:
		# turn to watch another way (out of his post's arc), then stand alert
		_turn_toward(base + _rng.randf_range(-1.3, 1.3), false)
	elif r < 0.84:
		_play("alert", 0.3)
		act_left = _rng.randf_range(2.0, 3.5)
	elif r < 0.92:
		_play("warmup", 0.35)
	else:
		_play("extra", 0.35)
	wait_left -= maxf(act_left, 0.5)

func _next_post() -> void:
	post_i = (post_i + 1) % (def["posts"] as Array).size()
	var at: Vector2 = posts_at[post_i]
	var to := Vector3(at.x, world.height_at(at.x, at.y), at.y)
	path = world.find_path(global_position, to)
	if path.is_empty():
		path = PackedVector3Array([to])
	path_i = 0
	state = "walk"
	wait_left = 0.0
	# a look round now and then on the way (Walk Slowly and Look Around)
	_play("walk_look" if _rng.randf() < 0.25 else "walk", 0.4)

func _walk(delta: float) -> void:
	if path_i >= path.size():
		_arrive()
		return
	var to := path[path_i] - global_position
	to.y = 0.0
	if to.length() < 0.35:
		path_i += 1
		_gap = INF
		return
	# something in the way he can't slide round: on to the next point after a moment
	if to.length() < _gap - 0.05:
		_gap = to.length()
		_stuck = 0.0
	else:
		_stuck += delta
		if _stuck > 2.0:
			_stuck = 0.0
			_gap = INF
			path_i += 1
			return
	if turn_t < 0.0:
		var want := atan2(to.x, to.z)
		var d := wrapf(want - yaw, -PI, PI)
		if absf(d) > 1.9 and clip != "walk_turn_l" and clip != "walk_turn_r":
			# a sharp corner: the walking turn
			_play("walk_turn_l" if d > 0.0 else "walk_turn_r", 0.25)
			_start_turn(d, clip_len(clip))
		else:
			yaw = lerp_angle(yaw, want, minf(1.0, delta * 3.2))
	if act_left <= 0.0 and not (clip in ["walk", "walk_look"]):
		_play("walk", 0.35)
	elif clip == "walk_look" and _rng.randf() < delta * 0.08:
		_play("walk", 0.5)
	elif clip == "walk" and _rng.randf() < delta * 0.03:
		_play("walk_look", 0.5)

func _arrive() -> void:
	state = "post"
	var p: Dictionary = _post()
	var w: Array = p.get("wait", [6.0, 9.0])
	wait_left = _rng.randf_range(float(w[0]), float(w[1]))
	_play("idle", 0.4)
	_turn_toward(_yaw_to(p["look"]), false)

# --- a hero going by ----------------------------------------------------------------------------------------------

func _watch(delta: float) -> void:
	if not is_instance_valid(watched):
		_resume()
		return
	var hp := watched.global_position
	var d := hp.distance_to(global_position)
	if turn_t < 0.0:
		var want := _yaw_to(Vector2(hp.x, hp.z))
		if absf(wrapf(want - yaw, -PI, PI)) > 1.2:
			_turn_toward(want, true)
		else:
			yaw = lerp_angle(yaw, want, minf(1.0, delta * 2.0))
			if act_left <= 0.0 or clip != "alert":
				_play("alert", 0.3)
				act_left = 99.0
	watch_left -= delta
	if watch_left <= 0.0 or d > LOOK_R:
		_resume()

func _resume() -> void:
	watched = null
	act_left = 0.0
	if path_i < path.size():
		state = "walk"
		_play("walk", 0.45)
	else:
		state = "post"
		_play("idle", 0.45)

# --- fighting -----------------------------------------------------------------------------------------------------

func _fight(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.dead \
			or target.global_position.distance_to(global_position) > AGGRO_R * 1.4 \
			or Vector2(target.global_position.x, target.global_position.z).distance_to(ForestCamp.CENTER) > LEASH:
		target = null
		hits_left.clear()
		state = "walk"
		var at: Vector2 = posts_at[post_i]
		path = world.find_path(global_position, Vector3(at.x, 0, at.y))
		path_i = 0
		_play("combat_idle", 0.3)
		act_left = 1.2
		return
	var tp := target.global_position
	var d := Vector2(tp.x - global_position.x, tp.z - global_position.z).length() - target.radius
	var want := _yaw_to(Vector2(tp.x, tp.z))
	# a strike in progress: its blows land on their moments
	if not hits_left.is_empty():
		yaw = lerp_angle(yaw, want, minf(1.0, delta * 6.0))
		for i in hits_left.size():
			hits_left[i] = float(hits_left[i]) - delta
		while not hits_left.is_empty() and float(hits_left[0]) <= 0.0:
			hits_left.pop_front()
			_land()
		return
	if act_left > 0.0 and clip.begins_with("strike"):
		return
	var slot: Dictionary = (def["slots"] as Array)[slot_i]
	var reach := float(slot["reach"])
	if d > reach + 0.2:
		# close in: a run from afar, the fighting walk near
		yaw = lerp_angle(yaw, want, minf(1.0, delta * 6.0))
		_play("run" if d > 4.0 else "walk_fight", 0.25)
		dance_left = 0.0
		return
	yaw = lerp_angle(yaw, want, minf(1.0, delta * 8.0))
	if cooldown <= 0.0 and absf(wrapf(want - yaw, -PI, PI)) < 0.45:
		_strike(slot)
		return
	# between blows: circle and strafe round it, step back out, square up
	dance_left -= delta
	if dance_left <= 0.0:
		var r := _rng.randf()
		if d < reach * 0.55:
			_play("walk_fight_back", 0.25)
		elif r < 0.35:
			_play("strafe_l", 0.25)
		elif r < 0.7:
			_play("strafe_r", 0.25)
		else:
			_play("combat_idle", 0.25)
		dance_left = _rng.randf_range(0.5, 1.1)

func _strike(slot: Dictionary) -> void:
	var c := str(slot["clip"])
	_play(c, 0.15)
	anim.seek(0.0, true)
	act_left = clip_len(c)
	var hits: Array = (meta.get(c, {}) as Dictionary).get("hits", [0.45])
	hits_left.clear()
	per_hit = 1.0 / maxf(1.0, hits.size() * 0.75)     # a combo's blows share the slot's damage (a little more in all)
	for h in hits:
		hits_left.append(float(h) * clip_len(c))
	# Meshy's strikes have a long recovery: back to his guard soon after the last blow lands
	act_left = minf(clip_len(c), float(hits_left.back()) + RECOVER)
	Sfx.play_at("swing_heavy" if float(slot["dmg"]) >= 1.2 else "swing_light", global_position + Vector3(0, 1.2, 0), -4.0, _rng.randf_range(0.92, 1.06))
	cooldown = act_left + float(slot["cd"])
	dance_left = 0.0

## A blow lands: the host deals it (a rival's blow: no xp, no loot for anyone).
func _land() -> void:
	var slot: Dictionary = (def["slots"] as Array)[slot_i]
	if target != null and is_instance_valid(target) and not target.dead:
		var d := target.global_position.distance_to(global_position) - target.radius
		if d < float(slot["reach"]) + 0.5 and not game.net.is_client():
			var lvl := float(world.level)
			var dmg := (14.0 + lvl * 3.0) * float(slot["dmg"]) * float(def.get("dmg", 1.0)) * per_hit * _rng.randf_range(0.85, 1.15)
			target.take_hit(dmg, global_position)
	if hits_left.is_empty():
		slot_i = (slot_i + 1) % (def["slots"] as Array).size()

# --- the body -----------------------------------------------------------------------------------------------------

func _turn_toward(want: float, alert: bool) -> void:
	var d := wrapf(want - yaw, -PI, PI)
	if absf(d) < 0.45:
		yaw = lerp_angle(yaw, want, 0.5)
		return
	var c := ("turn_l_combat" if d > 0.0 else "turn_r_alert") if alert else ("turn_l" if d > 0.0 else "turn_r")
	_play(c, 0.25)
	anim.seek(0.0, true)
	_start_turn(d, clip_len(c))

func _start_turn(by: float, length: float) -> void:
	turn_from = yaw
	turn_by = by
	turn_len = maxf(length * 0.85, 0.3)
	turn_t = 0.0

## The turn clips have their yaw baked out (prep_guard.py): the body turns here, eased across the clip.
func _turning(delta: float) -> void:
	if turn_t < 0.0:
		return
	turn_t += delta
	var f := clampf(turn_t / turn_len, 0.0, 1.0)
	yaw = turn_from + turn_by * (f * f * (3.0 - 2.0 * f))
	if f >= 1.0:
		turn_t = -1.0

## The clip's own ground motion (measured off its hips), through World.move so he slides along what's solid; never
## into the monster he's fighting.
func _root_motion(delta: float) -> void:
	var m: Dictionary = meta.get(clip, {})
	var fwd := float(m.get("fwd", 0.0))
	var side := float(m.get("side", 0.0))
	if clip in ["walk", "walk_look"] and absf(fwd) < 0.2:
		fwd = 1.2       # a clip without root motion
	if clip == "run" and absf(fwd) < 0.5:
		fwd = 3.6
	if absf(fwd) < 0.02 and absf(side) < 0.02:
		return
	var f := Vector3(sin(yaw), 0, cos(yaw))
	var left := Vector3(f.z, 0, -f.x)
	var v := (f * fwd + left * side) * anim.speed_scale * delta
	if state == "fight" and target != null and is_instance_valid(target):
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() - target.radius < 0.85 and v.dot(to) > 0.0:
			v -= to.normalized() * v.dot(to.normalized())
	global_position = world.move(global_position, v, BODY_R)

## The head follows a hero going by, the monster he fights.
func _look(delta: float) -> void:
	if head == null:
		return
	var tgt := Vector3.INF
	if state == "fight" and target != null and is_instance_valid(target):
		tgt = target.global_position + Vector3(0, target.height * 1.4, 0)
	else:
		for h in _heroes():
			var hn := h as Node3D
			if hn.global_position.distance_to(global_position) < LOOK_R:
				tgt = hn.global_position + Vector3(0, 1.5, 0)
				break
	head.target = tgt if tgt != Vector3.INF else head.target
	head.amount = move_toward(head.amount, 1.0 if tgt != Vector3.INF and not clip.begins_with("turn") else 0.0, delta * 2.5)

## The hour (Game.day_night): stronger rim and fill after dark; the sentry carries a lantern on his night rounds.
func _night(delta: float) -> void:
	var dn: DayNight = game.day_night if game != null and "day_night" in game else null
	var n: float = dn.night if dn != null and dn.on else 1.0
	if rim_mat != null:
		rim_mat.set_shader_parameter("strength", RIM * lerpf(0.4, 1.0, n))
	if fill != null:
		fill.light_energy = FILL * lerpf(0.35, 1.0, n)
	if not def.get("night_lamp", false):
		return
	var want: bool = n > 0.5
	if want and night_lamp == null:
		_carry_lamp()
	if night_lamp != null:
		night_lamp.visible = want
		if want and _hand_l != null:
			# hanging from his left fist, swinging with his stride
			var moving := clip in ["walk", "walk_look", "run", "walk_fight"]
			_swing += delta * (5.0 if moving else 1.6)
			var amp := 0.32 if moving else 0.08
			night_lamp.global_position = _hand_l.global_position + Vector3(0, -0.06, 0)
			night_lamp.global_rotation = Vector3(sin(_swing) * amp * 0.6, yaw, sin(_swing * 0.7) * amp * 0.3)

func _carry_lamp() -> void:
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	if sk == null or sk.find_bone("LeftHand") < 0:
		return
	_hand_l = BoneAttachment3D.new()
	_hand_l.bone_name = "LeftHand"
	sk.add_child(_hand_l)
	night_lamp = Node3D.new()
	night_lamp.name = "NightLamp"
	add_child(night_lamp)
	var ln: Node3D = ForestCamp.model("lantern") if ForestCamp.has_piece("lantern") else null
	if ln != null:
		night_lamp.add_child(ln)
		ln.scale = Vector3.ONE * 0.62
		ln.position = Vector3(0, -0.42, 0)
		for m in ln.find_children("*", "GeometryInstance3D", true, false):
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core := MeshInstance3D.new()
	core.mesh = Geo.sph(0.04, 8)
	core.material_override = Mats.glow_unique(Color(1.0, 0.75, 0.4), 4.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	night_lamp.add_child(core)
	core.position = Vector3(0, -0.27, 0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.68, 0.38)
	l.light_energy = 1.9
	l.omni_range = 7.0
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	night_lamp.add_child(l)
	l.position = Vector3(0, -0.22, 0)

## Their look in the dusk: a rim light round the silhouette in each one's colour (a pass over every surface), a soft
## light of his own over the shoulders, and the ironfist's lantern alight at his hip.
func _dress() -> void:
	var rim := ShaderMaterial.new()
	rim_mat = rim
	var sh := Shader.new()
	sh.code = RIM_SHADER
	rim.shader = sh
	rim.set_shader_parameter("rim_col", def.get("rim", Color(1.0, 0.7, 0.4)))
	rim.set_shader_parameter("strength", RIM)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null:
				continue
			var mm := m.duplicate() as Material
			mm.next_pass = rim
			mi.set_surface_override_material(i, mm)
	var fl := OmniLight3D.new()
	fl.name = "Fill"
	fl.light_color = def.get("fill", Color(1.0, 0.8, 0.6))
	fl.light_energy = FILL
	fl.omni_range = 3.4
	fl.omni_attenuation = 1.4
	fl.shadow_enabled = false
	fl.light_specular = 0.3
	fl.position = Vector3(0, 2.5, 0)
	add_child(fl)
	fill = fl
	if def.has("lantern"):
		_hang_lantern(def["lantern"])

func _hang_lantern(at: Vector3) -> void:
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	if sk == null or sk.find_bone("Hips") < 0:
		return
	await get_tree().process_frame
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Hips"
	sk.add_child(ba)
	var l := OmniLight3D.new()
	l.name = "Lantern"
	l.light_color = Color(1.0, 0.62, 0.28)
	l.light_energy = 1.6
	l.omni_range = 4.5
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	ba.add_child(l)
	l.global_position = model.to_global(at)
	l.scale = Vector3.ONE
	var glow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	glow.mesh = sm
	glow.material_override = Mats.glow(Color(1.0, 0.6, 0.25), 3.0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.add_child(glow)
	glow.global_transform = Transform3D(Basis().scaled(Vector3.ONE * SCALE), l.global_position)

const RIM_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back;
uniform vec4 rim_col : source_color = vec4(1.0, 0.7, 0.4, 1.0);
uniform float strength = 0.5;
void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	ALBEDO = rim_col.rgb * f * strength;
}
"""

## Turns the neck and head toward a point over whatever the clip does (after the AnimationPlayer, before skinning).
class HeadLook extends SkeletonModifier3D:
	var body: Node3D
	var target := Vector3.INF
	var amount := 0.0
	var _neck := -1
	var _head := -1
	const YAW_MAX := 1.15
	const PITCH_MAX := 0.45

	func setup(sk: Skeleton3D) -> void:
		_neck = sk.find_bone("neck")
		if _neck < 0:
			_neck = sk.find_bone("Neck")
		_head = sk.find_bone("Head")

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or _head < 0 or amount <= 0.001 or target == Vector3.INF or body == null:
			return
		var hp := sk.global_transform * sk.get_bone_global_pose(_head).origin
		var to := target - hp
		var fwd := body.global_basis.z
		fwd.y = 0.0
		if fwd.length() < 0.01 or Vector2(to.x, to.z).length() < 0.2:
			return
		fwd = fwd.normalized()
		var ya := clampf(atan2(fwd.cross(Vector3(to.x, 0, to.z).normalized()).y, fwd.dot(Vector3(to.x, 0, to.z).normalized())), -YAW_MAX, YAW_MAX)
		var dir := fwd.rotated(Vector3.UP, ya)
		var pa := clampf(atan2(to.y, Vector2(to.x, to.z).length()), -PITCH_MAX, PITCH_MAX)
		dir = dir.rotated(dir.cross(Vector3.UP).normalized(), pa)
		var q := Quaternion(fwd, dir.normalized())
		var sb := sk.global_basis.orthonormalized()
		for pair in [[_neck, 0.4], [_head, 0.6]]:
			var b: int = pair[0]
			if b < 0:
				continue
			var part := Quaternion.IDENTITY.slerp(q, float(pair[1]) * amount)
			var gp := sk.get_bone_global_pose(b)
			gp.basis = (sb.inverse() * Basis(part) * sb) * gp.basis
			sk.set_bone_global_pose(b, gp)

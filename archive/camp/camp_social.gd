class_name CampSocial
extends Node
## The camp's people talking to each other (jj, 2026-11-04: "the merchants should interact with one another and
## anything else along with the guards"): every couple of seconds it looks for two who are free (a guard standing at
## his post, a trader at their stall or on their round, not busy with a hero) close enough to talk, turns them to
## face each other and plays a conversation in turns: one talks (Meshy's talk and gesture clips, moved onto every
## keeper and guard by tools/blender/npc_add_clips.py), the other listens, nods, shrugs; then the other takes it up,
## and they part with a wave or a bow. Now and then a trader who strolls (Inter "patrol") walks over to another's
## stall to visit and chat, and walks home again; a trader passing a guard on his round waves to him. A hero walking
## up, a monster in the camp, or a guard's round going on ends it. Local and cosmetic, like the keepers' clips.

const TALK := ["Talk_Passionately", "Talk_with_Hands_Open", "Talk_with_Right_Hand_Open", "Talk_with_Left_Hand_on_Hip",
	"Stand_and_Chat", "Shrug", "Finger_Wag_No", "Call_Gesture", "Talk_with_Left_Hand_Raised"]
const LISTEN := ["Listening_Gesture", "Agree_Gesture", "Hand_on_Hip_Gesture", "Idle_8", "Listening_Gesture", "Agree_Gesture"]
const PART := ["Wave_One_Hand", "Big_Wave_Hello", "Formal_Bow", "Agree_Gesture"]
const NEAR := Vector2(1.5, 5.5)   # how far apart two can stand and talk
const COOLDOWN := Vector2(14.0, 30.0)
const VISIT_EVERY := Vector2(14.0, 28.0)

var world: World
var chats: Array = []            # {a, b, t, dur, turn_t, speaker}
var _cd := {}                    # person -> seconds before they'll talk again
var _scan := 12.0                # (everyone settles into their day before the talk starts)
var _visit := 16.0
var _waved := {}

static func add_to(w: World) -> CampSocial:
	var cs := CampSocial.new()
	cs.name = "social"
	cs.world = w
	w.add_child(cs)
	return cs

func _people() -> Array:
	return get_tree().get_nodes_in_group("camp_walker")

func _hero_near(p: Vector3, r: float) -> bool:
	for h in get_tree().get_nodes_in_group("hero"):
		if (h as Node3D).global_position.distance_to(p) < r:
			return true
	return false

static func _has(n: Node, c: String) -> bool:
	var ap: AnimationPlayer = n.get("anim")
	return ap != null and ap.has_animation(c)

static func _pick(n: Node, list: Array) -> String:
	var ok: Array = []
	for c in list:
		if _has(n, str(c)):
			ok.append(c)
	return str(ok[randi() % ok.size()]) if not ok.is_empty() else ""

## Free to talk: a guard idling at his post, a keeper standing (not walking, forging, or with a hero near).
func can_talk(n: Node) -> bool:
	if not is_instance_valid(n) or n.get_meta("chatting", false) or float(_cd.get(n, 0.0)) > 0.0:
		return false
	if n is CampGuard:
		var g := n as CampGuard
		# (on duty: only while he has a good while left at his post, so his round keeps going)
		return g.state == "post" and g.turn_t < 0.0 and g.target == null and g.wait_left > 6.0
	if n is Inter:
		var it := n as Inter
		if it.model == null or it.anim == null or it.has_meta("forge") or it._walk_to != Vector3.INF:
			return false
		return not _hero_near(it.global_position, 7.0)
	return false

func _pos(n: Node) -> Vector3:
	return (n as Node3D).global_position

func _process(delta: float) -> void:
	for k in _cd.keys():
		_cd[k] = float(_cd[k]) - delta
	for c in chats.duplicate():
		_run(c, delta)
	_scan -= delta
	if _scan <= 0.0:
		_scan = 1.6
		_find()
		_waves()
	_visit -= delta
	if _visit <= 0.0:
		_visit = randf_range(VISIT_EVERY.x, VISIT_EVERY.y)
		_start_visit()

func _find() -> void:
	var ppl := _people()
	ppl.shuffle()
	for i in ppl.size():
		var a: Node = ppl[i]
		if not can_talk(a):
			continue
		for j in range(i + 1, ppl.size()):
			var b: Node = ppl[j]
			if not can_talk(b):
				continue
			var d := Vector2(_pos(a).x - _pos(b).x, _pos(a).z - _pos(b).z).length()
			if d >= NEAR.x and d <= NEAR.y and randf() < 0.85:
				begin(a, b)
				return

func begin(a: Node, b: Node) -> void:
	var dur := randf_range(9.0, 17.0)
	for n in [a, b]:
		if n is CampGuard:
			dur = minf(dur, randf_range(6.0, 10.0))      # a guard keeps it short
	var c := {"a": a, "b": b, "t": 0.0, "dur": dur, "turn_t": 0.0, "speaker": a, "parted": false}
	for n in [a, b]:
		n.set_meta("chatting", true)
		_hold(n, true)
	chats.append(c)
	_turn(c)

## One of them takes up the talk, the other listens.
func _turn(c: Dictionary) -> void:
	var sp: Node = c["speaker"]
	var ls: Node = c["b"] if sp == c["a"] else c["a"]
	_clip(sp, _pick(sp, TALK))
	_clip(ls, _pick(ls, LISTEN))
	c["turn_t"] = randf_range(2.6, 4.2)

func _run(c: Dictionary, delta: float) -> void:
	var a: Node = c["a"]
	var b: Node = c["b"]
	if not is_instance_valid(a) or not is_instance_valid(b) or _broken(a) or _broken(b):
		end(c)
		return
	c["t"] = float(c["t"]) + delta
	_face(a, _pos(b), delta)
	_face(b, _pos(a), delta)
	if float(c["t"]) > float(c["dur"]):
		if not c["parted"]:
			c["parted"] = true
			_clip(a, _pick(a, PART))
			_clip(b, _pick(b, PART))
			c["dur"] = float(c["t"]) + 2.2
			return
		end(c)
		return
	if c["parted"]:
		return
	c["turn_t"] = float(c["turn_t"]) - delta
	if float(c["turn_t"]) <= 0.0:
		if randf() < 0.65:
			c["speaker"] = b if c["speaker"] == a else a
		_turn(c)

## Something else wants them: a hero walking up to a trader, a guard's fight or watch.
func _broken(n: Node) -> bool:
	if n is CampGuard:
		return (n as CampGuard).state != "post"
	if n is Inter:
		return _hero_near((n as Inter).global_position, 5.5)
	return true

func end(c: Dictionary) -> void:
	chats.erase(c)
	for n in [c["a"], c["b"]]:
		if is_instance_valid(n):
			n.set_meta("chatting", false)
			_hold(n, false)
			_cd[n] = randf_range(COOLDOWN.x, COOLDOWN.y) * (2.0 if n is CampGuard else 1.0)
	# a visitor walks home
	for n in [c["a"], c["b"]]:
		if is_instance_valid(n) and n.has_meta("visit_home"):
			var home: Vector3 = n.get_meta("visit_home")
			n.remove_meta("visit_home")
			(n as Inter).walk_to(home)

func _hold(n: Node, on: bool) -> void:
	if n is CampGuard:
		var g := n as CampGuard
		g.act_left = 1e9 if on else 0.0
		if not on:
			g.wait_left = minf(g.wait_left, 4.0)
	elif n is Inter:
		(n as Inter).social = on
		if not on:
			(n as Inter)._clip_t = 0.0

func _clip(n: Node, c: String) -> void:
	if c == "":
		return
	if n is CampGuard:
		var g := n as CampGuard
		g._play(c, 0.4)
		g.act_left = 1e9
	elif n is Inter:
		(n as Inter).anim.play(c, 0.4)

func _face(n: Node, to: Vector3, delta: float) -> void:
	var p := _pos(n)
	var want := atan2(to.x - p.x, to.z - p.z)
	if n is CampGuard:
		(n as CampGuard).yaw = lerp_angle((n as CampGuard).yaw, want, minf(1.0, delta * 3.0))
	elif n is Inter:
		var m := (n as Inter).model
		m.rotation.y = lerp_angle(m.rotation.y, want, minf(1.0, delta * 3.0))

## A strolling trader walks over to another's stall for a word, then home.
func _start_visit() -> void:
	var walkers: Array = []
	var hosts: Array = []
	for n in _people():
		if not (n is Inter) or not can_talk(n):
			continue
		var it := n as Inter
		if not (it.clips.get("patrol", {}) as Dictionary).is_empty():
			walkers.append(it)
		hosts.append(it)
	walkers.shuffle()
	for v in walkers:
		var vi := v as Inter
		hosts.shuffle()
		for h in hosts:
			var hi := h as Inter
			if hi == vi:
				continue
			var d := hi.global_position.distance_to(vi.global_position)
			if d < 6.0 or d > 20.0:
				continue
			# stand a step in front of them, on open ground
			var f := Vector3(sin(hi.home_yaw), 0, cos(hi.home_yaw))
			var spot: Vector3 = world.free_spot_near(hi.global_position + f * 2.2, 0.5)
			vi.set_meta("visit_home", vi.global_position)
			_cd[hi] = 0.0
			vi.walk_to(spot, Callable(self, "_arrived").bind(vi, hi))
			return

func _arrived(v: Inter, h: Inter) -> void:
	if can_talk(h) and not v.get_meta("chatting", false):
		_cd[v] = 0.0
		begin(v, h)
	elif v.has_meta("visit_home"):
		var home: Vector3 = v.get_meta("visit_home")
		v.remove_meta("visit_home")
		v.walk_to(home)

## A trader standing about waves to a guard walking by.
func _waves() -> void:
	for g in _people():
		if not (g is CampGuard) or (g as CampGuard).state != "walk":
			continue
		for k in _people():
			if not (k is Inter) or not can_talk(k):
				continue
			var d := _pos(g).distance_to(_pos(k))
			var key := str(g.get_instance_id()) + ":" + str(k.get_instance_id())
			if d < 6.0 and d > 2.0 and float(_waved.get(key, -1e9)) < Time.get_ticks_msec() * 0.001 - 40.0:
				_waved[key] = Time.get_ticks_msec() * 0.001
				var it := k as Inter
				var c := _pick(it, ["Wave_One_Hand", "Big_Wave_Hello", "Call_Gesture"])
				if c != "":
					it.anim.play(c, 0.35)
					it._clip_t = it.anim.get_animation(c).length
					it.set_meta("wave_to", g)

class_name SpiritBeast
extends Node3D
## The archer's Spirit Beast (archer.gd): his companion from the start, a spectral beast (the arena lion's
## body, pale and glowing; the code-built crawler without it). Not a summon on a timer: it lives with him,
## follows him like an animal, fights beside him, guards him, noses about, and comes when called.
##
## States (`state`): "follow" (settles beside or behind him, walks, trots, runs or sprints by distance, never
## glued to his back), "engage" (a hostile it chose), "command" (the one he sent it at), "protect" (whatever
## is hitting him), "investigate" (a loot drop, a chest or a spot that caught its nose), "return" (back to
## him), "hold" (stays where he told it). Targets are scored (`_score`: his command, the enemy he is
## shooting, a threat to him, the one it already has, then the nearest awake hostile) and kept for a
## while (`commit`) unless something clearly matters more, so it doesn't flick between foes. Attacks are a
## bite (the lion's maul) and a pounce (the lion's leap), each landing once on its impact frame and
## followed by a recovery. Stuck or unable to reach a foe, it tries a new path, then gives that foe up for
## a while. Monsters it bites turn on it (`Enemy.taunt`); it can be killed and rises again beside him
## (`Archer.keep_companions`). Commands: `command(kind, ...)`: "attack" (a foe; with a pounce), "hold"
## (a place), "follow"/"return". The archer's Spirit Beast skill issues them (archer.gd). Every tuning
## number is in CFG. Local to each player's game (like every class's summons): partners don't see it.

const CFG := {
	"follow_dist": 2.3,     # how far from him it likes to be
	"follow_settle": 1.0,   # within this of its spot it stops
	"follow_wake": 2.6,     # and only sets off again once it is this far from it (no jitter)
	"walk": 1.8, "trot": 4.0, "run": 6.4, "sprint": 9.0,   # m/s
	"trot_at": 3.5, "run_at": 7.0, "sprint_at": 13.0,      # distance to its spot that picks the pace
	"accel": 11.0, "decel": 14.0, "turn": 6.5,             # m/s², m/s², rad/s
	"detect": 11.0,         # hostiles this close to him (and awake) are fair game
	"protect": 8.0,         # someone hitting him within this is a threat
	"leash": 17.0,          # in a fight it won't stray further than this from him (a command lets it)
	"warp": 40.0,           # left this far behind (a portal, a waypoint), it bounds back to his side
	"bite_range": 1.15, "bite_time": 0.8, "bite_rest": [0.35, 0.6],
	"pounce_min": 3.0, "pounce_max": 7.5, "pounce_time": 0.9, "pounce_cd": 6.0,
	"commit": 2.5,          # seconds before it may switch to a target that only scores a little better
	"switch_margin": 15.0,  # how much better a new target must score to take over early
	"command_time": 15.0, "hold_time": 20.0,
	"stuck_time": 1.2,      # this long without getting anywhere: a new path
	"give_up": 3.5,         # this long stuck on a target: that target is out of reach (for 6 s)
	"think": 0.25,          # target choice runs this often
	"life": 80.0, "life_per_level": 12.0, "armor": 0.7,     # damage taken is scaled by armor
	"respawn": 18.0,
	"sniff_every": [8.0, 15.0], "sniff_time": 1.6,
}
const HEIGHT := 1.2

var master: Hero
var game: Node
var slot := 0
var rig: Node3D
var lion := false
var state := "follow"
var target = null              # the Enemy it is after
var commit_t := 0.0
var command_t := 0.0
var hold_pos := Vector3.ZERO
var poi := Vector3.ZERO        # where it is nosing about
var sniff_t := 10.0
var sniff_hold := 0.0
var vel := Vector3.ZERO
var heading := 0.0
var settled := false
var jitter := Vector2.ZERO
var jitter_t := 0.0
var atk_t := -1.0
var atk_kind := ""
var atk_dur := 0.8
var hit_done := false
var pounce_from := Vector3.ZERO
var pounce_to := Vector3.ZERO
var rest_t := 0.0
var pounce_cd_t := 0.0
var think_t := 0.0
var path := PackedVector3Array()
var path_to := Vector3.INF
var stuck_t := 0.0
var stuck_from := Vector3.ZERO
var target_stuck := 0.0
var unreachable := {}          # enemy instance id -> seconds left
var phase := 0.0
var move_amt := 0.0
var anim_time := 0.0
var hit := 0.0
var life := 80.0
var max_life := 80.0
var dead := false
var radius := 0.6
var world_ref: Node = null
var _owner_last := Vector3.ZERO
var _owner_v := Vector3.ZERO

func setup(m: Hero, g: Node, s: int) -> void:
	master = m
	game = g
	slot = s
	lion = Lion.ok()
	if lion:
		rig = Lion.build()
		rig.scale = Vector3.ONE * 0.85
	else:
		rig = Models.crawler({"skin": Color(0.5, 0.7, 0.65), "shell": Color(0.4, 0.6, 0.55), "legs": 4, "size": 1.0, "eyes": Archer.HUNTER})
	add_child(rig)
	ghostly(rig)
	var l := OmniLight3D.new()
	l.light_color = Archer.HUNTER
	l.light_energy = 0.8
	l.omni_range = 4.0
	l.position = Vector3(0, 1.0, 0)
	add_child(l)
	var trail := Fx.aura(self, Archer.HUNTER, 20, 0.4, 0.1, 0.9, 0.3, 0.5, 60.0, Vector3(0, 0.7, 0))
	trail.name = "trail"
	max_life = float(CFG["life"]) + float(CFG["life_per_level"]) * master.level
	life = max_life
	world_ref = game.world
	_owner_last = master.global_position
	heading = master.rig.rotation.y
	rig.rotation.y = heading

## The spectral look: a pale glow over the body (also used by the "spirit_beast" monster, Enemy.build_rig).
static func ghostly(r: Node3D) -> void:
	var ghost := Mats.glow(Archer.HUNTER, 0.9, 0.0, 1.0)
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = ghost
		(mi as MeshInstance3D).transparency = 0.25

func dismiss() -> void:
	if game and game.world:
		Fx.burst(game.world.fx_root, global_position + Vector3(0, 0.7, 0), Archer.HUNTER, 26, 3.0, 0.14, 0.8, true, 1.5)
	queue_free()

# ---------------------------------------------------------------- commands
## kind: "attack" (foe: an Enemy; it pounces if it can), "hold" (at: a place), "follow" / "return".
func command(kind: String, foe = null, at := Vector3.ZERO) -> void:
	match kind:
		"attack":
			if _valid(foe):
				target = foe
				state = "command"
				command_t = float(CFG["command_time"])
				commit_t = float(CFG["commit"])
				unreachable.erase(foe.get_instance_id())
				pounce_cd_t = 0.0
				_glance(foe.global_position)
		"hold":
			state = "hold"
			hold_pos = at
			command_t = float(CFG["hold_time"])
			target = null
		_:
			target = null
			state = "return"
			command_t = 0.0

# ---------------------------------------------------------------- being hit, dying
func take_hit(dmg: float, from: Vector3, _kind: String = "melee", _element: String = "phys") -> void:
	if dead:
		return
	life -= dmg * float(CFG["armor"])
	hit = 1.0
	if game and game.world:
		Fx.burst(game.world.fx_root, global_position + Vector3(0, 0.8, 0), Archer.HUNTER, 8, 2.5, 0.07, 0.3, true, -3.0)
	# whatever hit it becomes worth biting back, if it isn't busy with his command
	var e = _enemy_near(from, 2.5)
	if e != null and state != "command" and atk_t < 0.0:
		target = e
		state = "engage"
		commit_t = float(CFG["commit"])
	if life <= 0.0:
		die()

func die() -> void:
	dead = true
	master.beasts.erase(self)
	master.beast_down_t = float(CFG["respawn"])
	if game and game.world:
		Fx.burst(game.world.fx_root, global_position + Vector3(0, 0.7, 0), Archer.HUNTER, 40, 4.0, 0.16, 1.1, true, 2.0)
		Fx.flash(game.world.fx_root, global_position + Vector3(0, 1, 0), Archer.HUNTER, 3.0, 0.6, 5.0)
	game.ui.message("Your Spirit Beast fades. It will return.", Color(0.6, 0.9, 0.6))
	queue_free()

# ---------------------------------------------------------------- every frame
func _process(delta: float) -> void:
	if not is_instance_valid(master) or game == null or game.world == null or game._busy:
		return
	if dead:
		return
	anim_time += delta
	hit = maxf(0.0, hit - delta * 3.0)
	# a new zone (portal, waypoint, the party's trip): it arrives with him
	if game.world != world_ref:
		world_ref = game.world
		_reset_to_side()
	var mp: Vector3 = master.global_position
	_owner_v = _owner_v.lerp((mp - _owner_last) / maxf(delta, 0.001), clampf(delta * 6.0, 0.0, 1.0))
	_owner_last = mp
	if global_position.distance_to(mp) > float(CFG["warp"]):
		_reset_to_side()
	_tick_timers(delta)
	think_t -= delta
	if think_t <= 0.0:
		think_t = float(CFG["think"])
		_think()
	var want := Vector3.ZERO
	if atk_t >= 0.0:
		want = _attack(delta)
	else:
		match state:
			"follow":
				want = _follow(delta)
			"engage", "command", "protect":
				want = _fight(delta)
			"investigate":
				want = _investigate(delta)
			"return":
				want = _go(delta, mp, float(CFG["run"]))
				if mp.distance_to(global_position) < float(CFG["follow_dist"]) + 0.8:
					state = "follow"
			"hold":
				want = _hold(delta)
	_move(delta, want)
	_pose()

func _tick_timers(delta: float) -> void:
	commit_t -= delta
	rest_t -= delta
	pounce_cd_t -= delta
	if state in ["command", "hold"]:
		command_t -= delta
		if command_t <= 0.0:
			state = "return"
			target = null
	for k in unreachable.keys():
		unreachable[k] = float(unreachable[k]) - delta
		if float(unreachable[k]) <= 0.0:
			unreachable.erase(k)

func _valid(e) -> bool:
	return e != null and is_instance_valid(e) and e is Enemy and not e.dead

func _enemy_near(p: Vector3, r: float):
	var best = null
	var bd := r
	for e in game.enemies_near(p, r):
		var d: float = e.global_position.distance_to(p)
		if not e.dead and d < bd:
			bd = d
			best = e
	return best

# ---------------------------------------------------------------- choosing what to do
## How much a foe matters now (higher is more): his command first, then the one he is shooting at, then
## anything hurting him, then the one it already has, then the nearest awake hostile.
func _score(e) -> float:
	var mp: Vector3 = master.global_position
	var s: float = -e.global_position.distance_to(global_position) * 1.0 - e.global_position.distance_to(mp) * 0.6
	if state == "command" and e == target:
		s += 200.0
	if master.mark_t > 0.0 and e == master.mark:
		s += 45.0
	if e.aggro and game.target_for(e) == master and e.global_position.distance_to(mp) < float(CFG["protect"]):
		s += 30.0
	if e == target:
		s += 12.0
	return s

func _think() -> void:
	if state == "command" and _valid(target):
		return
	if state == "command":
		state = "return"
		target = null
	if not _valid(target):
		target = null
	if state == "hold":
		# holding: only what comes close to its spot
		var near = _enemy_near(hold_pos, 6.0)
		if near != null and target == null:
			target = near
		return
	var mp: Vector3 = master.global_position
	var best = null
	var bs := -1e9
	for e in game.enemies_near(mp, float(CFG["detect"]) + 3.0):
		if e.dead or unreachable.has(e.get_instance_id()):
			continue
		var awake: bool = e.aggro or e.global_position.distance_to(mp) < 6.0
		if not awake and not (master.mark_t > 0.0 and e == master.mark):
			continue
		var sc := _score(e)
		if sc > bs:
			bs = sc
			best = e
	if best == null:
		if state in ["engage", "protect"]:
			state = "return"
			target = null
		return
	# keep the one it has unless it's gone, the commitment has run out, or the new one clearly matters more
	if target != null and best != target:
		if commit_t > 0.0 and bs < _score(target) + float(CFG["switch_margin"]):
			return
	if best != target:
		target = best
		commit_t = float(CFG["commit"])
		_glance(best.global_position)
	var threat: bool = best.aggro and game.target_for(best) == master and best.global_position.distance_to(mp) < float(CFG["protect"])
	state = "protect" if threat else "engage"

## The head and body come round toward something it noticed.
func _glance(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0
	if d.length() > 0.1 and vel.length() < 1.0:
		heading = lerp_angle(heading, atan2(-d.x, -d.z), 0.5)

# ---------------------------------------------------------------- following him
## Its place beside or a little behind him (on its own side; two beasts take a side each), with a slow
## drift so it never looks bolted on, set by where he is heading.
func _follow_spot() -> Vector3:
	var mp: Vector3 = master.global_position
	var fwd: Vector3 = -master.rig.global_transform.basis.z
	if _owner_v.length() > 0.8:
		fwd = _owner_v.normalized()
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := Vector3(-fwd.z, 0, fwd.x) * (1.0 if slot == 0 else -1.0)
	var d: float = CFG["follow_dist"]
	# at his side; on the move it trots a little ahead of him, the way a hound does
	var ahead := 0.35 if _owner_v.length() > 1.0 else -0.15
	return mp + side * d * 0.85 + fwd * d * ahead + Vector3(jitter.x, 0, jitter.y)

func _follow(delta: float) -> Vector3:
	jitter_t -= delta
	if jitter_t <= 0.0:
		jitter_t = randf_range(3.0, 6.0)
		jitter = Vector2(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6))
	# now and then something catches its nose (only while he dawdles)
	if _owner_v.length() < 0.6:
		sniff_t -= delta
		if sniff_t <= 0.0:
			sniff_t = randf_range(float(CFG["sniff_every"][0]), float(CFG["sniff_every"][1]))
			_pick_poi()
			if state == "investigate":
				return Vector3.ZERO
	var spot := _follow_spot()
	var to := spot - global_position
	to.y = 0
	var d := to.length()
	if settled and d < float(CFG["follow_wake"]):
		# settled: just turn now and then to look at him or about
		if fmod(anim_time + slot * 3.0, 6.0) < 0.05:
			_glance(master.global_position)
		return Vector3.ZERO
	settled = d < float(CFG["follow_settle"])
	if settled:
		return Vector3.ZERO
	var pace: float = CFG["walk"]
	if d > float(CFG["sprint_at"]):
		pace = CFG["sprint"]
	elif d > float(CFG["run_at"]):
		pace = CFG["run"]
	elif d > float(CFG["trot_at"]):
		pace = CFG["trot"]
	# and it eases in to its spot rather than running into him
	pace = minf(pace, maxf(float(CFG["walk"]), d * 2.2))
	# never slower than he is going (a little quicker, to catch up)
	pace = maxf(pace, minf(_owner_v.length() * 1.2, float(CFG["sprint"])))
	return _go(delta, spot, pace)

func _pick_poi() -> void:
	var mp: Vector3 = master.global_position
	var best := Vector3.INF
	for it in game.world.items_root.get_children():
		if it is Node3D and (it as Node3D).global_position.distance_to(mp) < 10.0:
			best = (it as Node3D).global_position
			break
	if best == Vector3.INF:
		for t in game.world.interactables:
			if is_instance_valid(t) and t.global_position.distance_to(mp) < 9.0 and t.kind in ["chest", "shrine", "flower"]:
				best = t.global_position + (global_position - t.global_position).normalized() * 1.2
				break
	if best == Vector3.INF:
		var a := randf() * TAU
		best = game.world.free_spot_near(mp + Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 7.0), 1.5)
	poi = best
	sniff_hold = float(CFG["sniff_time"])
	state = "investigate"
	settled = false

func _investigate(delta: float) -> Vector3:
	var to := poi - global_position
	to.y = 0
	# he sets off: it drops the scent and goes with him
	if _owner_v.length() > 1.2:
		state = "follow"
		return _follow(delta)
	if to.length() > 0.9:
		if master.global_position.distance_to(global_position) > 10.0:
			state = "return"
		return _go(delta, poi, float(CFG["trot"]) * 0.8)
	# there: nose down a moment, then back to him
	sniff_hold -= delta
	if sniff_hold <= 0.0:
		state = "follow"
	return Vector3.ZERO

func _hold(delta: float) -> Vector3:
	if _valid(target) and target.global_position.distance_to(hold_pos) < 7.0:
		return _fight(delta)
	target = null
	var to := hold_pos - global_position
	to.y = 0
	if to.length() < 1.0:
		return Vector3.ZERO
	return _go(delta, hold_pos, float(CFG["trot"]))

# ---------------------------------------------------------------- fighting
func _fight(delta: float) -> Vector3:
	if not _valid(target):
		target = null
		if state != "hold":
			state = "return"
		return Vector3.ZERO
	var mp: Vector3 = master.global_position
	if state != "command" and state != "hold" and global_position.distance_to(mp) > float(CFG["leash"]):
		# too far from him: back to his side
		target = null
		state = "return"
		return Vector3.ZERO
	var tp: Vector3 = target.global_position
	var to := tp - global_position
	to.y = 0
	var d := to.length()
	var reach: float = float(CFG["bite_range"]) + target.radius + radius * 0.5
	if rest_t > 0.0:
		# recovering after a blow: a step back, watching it
		_glance(tp)
		return -to.normalized() * 1.2 if d < reach * 0.7 else Vector3.ZERO
	# a pounce from mid range when it can see the way (always for his command)
	if pounce_cd_t <= 0.0 and d > float(CFG["pounce_min"]) and d < float(CFG["pounce_max"]) and game.world.los(global_position, tp, 0.3):
		if state == "command" or randf() < 0.02:
			_begin("pounce", tp)
			return Vector3.ZERO
	if d <= reach:
		# lined up first: only bites what is in front of it
		var want := atan2(-to.x, -to.z)
		heading = rotate_toward(heading, want, float(CFG["turn"]) * delta)
		if absf(angle_difference(heading, want)) < 0.5:
			_begin("bite", tp)
		return Vector3.ZERO
	# closing in: to a spot just short of it, on the side facing it
	var stop := tp - to.normalized() * (reach * 0.85)
	var v := _go(delta, stop, float(CFG["run"]) if d > 4.0 else float(CFG["trot"]))
	# stuck on the way: try again, then give it up
	if _stuck(delta, true):
		unreachable[target.get_instance_id()] = 6.0
		target = null
		state = "return"
		return Vector3.ZERO
	return v

func _begin(kind: String, tp: Vector3) -> void:
	atk_kind = kind
	atk_t = 0.0
	hit_done = false
	var to := tp - global_position
	to.y = 0
	heading = atan2(-to.x, -to.z)
	if kind == "pounce":
		atk_dur = CFG["pounce_time"]
		pounce_from = global_position
		pounce_to = tp - to.normalized() * (target.radius + radius * 0.6)
		pounce_cd_t = float(CFG["pounce_cd"])
		Sfx.play_at("lion_roar", global_position, -10.0, randf_range(1.25, 1.4))
	else:
		atk_dur = CFG["bite_time"]

func _attack(delta: float) -> Vector3:
	atk_t += delta
	var a := atk_t / atk_dur
	if atk_kind == "pounce":
		var want := pounce_from.lerp(pounce_to, smoothstep(0.18, 0.62, a)) - global_position
		want.y = 0
		global_position = game.world.move(global_position, want, 0.3)
	elif _valid(target) and a < 0.3:
		var to: Vector3 = target.global_position - global_position
		to.y = 0
		heading = rotate_toward(heading, atan2(-to.x, -to.z), float(CFG["turn"]) * delta)
	var hit_at := Anim.impact_at("feral_lunge" if atk_kind == "pounce" else "feral_swipe")
	if not hit_done and a >= hit_at:
		hit_done = true
		_strike(1.6 if atk_kind == "pounce" else 1.0)
	if atk_t >= atk_dur:
		atk_t = -1.0
		rest_t = randf_range(float(CFG["bite_rest"][0]), float(CFG["bite_rest"][1])) + (0.4 if atk_kind == "pounce" else 0.0)
		vel = Vector3.ZERO
	return Vector3.ZERO

## One blow on its impact frame: only on a living foe in front of it and in reach.
func _strike(mult: float) -> void:
	if not _valid(target):
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0
	var fwd := Vector3(-sin(heading), 0, -cos(heading))
	if to.length() > float(CFG["bite_range"]) + target.radius + radius + 0.4 or (to.length() > 0.3 and fwd.dot(to.normalized()) < 0.3):
		return
	var avg: float = (master.dmg_min + master.dmg_max) * 0.5
	var d := (avg * 0.5 + master.level * 3.0 + 5.0) * master.dmg_mult("beast") * mult
	target.take_damage(d, 0.0, global_position, 0.5 if mult > 1.2 else 0.2, false)
	if mult > 1.2 and target.has_method("stun"):
		target.stun(0.6)
	# it turns on the beast
	target.taunt = self
	target.taunt_t = 4.0
	Fx.burst(game.world.fx_root, target.global_position + Vector3(0, target.height, 0), Archer.HUNTER, 12, 3.0, 0.08, 0.35, true, -3.0)

# ---------------------------------------------------------------- moving
## Toward p at pace: straight when it can see the way, along a path round things when it can't (the path
## is made again only when the goal moves or it gets stuck).
func _go(delta: float, p: Vector3, pace: float) -> Vector3:
	var goal := p
	if not game.world.los(global_position, p, 0.35):
		if path.is_empty() or path_to.distance_to(p) > 2.0:
			path = game.world.find_path(global_position, p)
			path_to = p
		while path.size() > 1 and global_position.distance_to(path[0]) < 0.7:
			path.remove_at(0)
		if not path.is_empty():
			goal = path[0]
	else:
		path = PackedVector3Array()
	var to := goal - global_position
	to.y = 0
	if to.length() < 0.05:
		return Vector3.ZERO
	if _stuck(delta, false):
		path = game.world.find_path(global_position, p)
		path_to = p
	return to.normalized() * pace

## True when it has been trying to move without getting anywhere for a while (once per stretch).
func _stuck(delta: float, for_target: bool) -> bool:
	if vel.length() < 0.5:
		stuck_t = 0.0
		stuck_from = global_position
		return false
	stuck_t += delta
	if stuck_t < float(CFG["stuck_time"]):
		return false
	var moved := global_position.distance_to(stuck_from)
	stuck_t = 0.0
	stuck_from = global_position
	if moved > 0.6:
		target_stuck = 0.0
		return false
	if for_target:
		target_stuck += float(CFG["stuck_time"])
		return target_stuck >= float(CFG["give_up"])
	return true

## Speeds up and slows down smoothly, turns at a beast's rate toward where it is going, slides round things.
func _move(delta: float, want: Vector3) -> void:
	var rate: float = CFG["accel"] if want.length() > vel.length() else CFG["decel"]
	vel = vel.move_toward(want, rate * delta)
	if vel.length() > 0.3:
		heading = rotate_toward(heading, atan2(-vel.x, -vel.z), float(CFG["turn"]) * delta)
		# it runs where it faces: a sharp turn slows it rather than sliding it sideways
		var fwd := Vector3(-sin(heading), 0, -cos(heading))
		var along := maxf(0.0, fwd.dot(vel.normalized()))
		var step := fwd * vel.length() * lerpf(0.35, 1.0, along)
		global_position = game.world.move(global_position, step * delta, 0.45)
		move_amt = move_toward(move_amt, clampf(step.length() / float(CFG["trot"]), 0.0, 1.5), delta * 5.0)
		phase += delta * step.length() * (1.6 / HEIGHT)
	else:
		move_amt = move_toward(move_amt, 0.0, delta * 5.0)
	global_position.y = game.world.height_at(global_position.x, global_position.z)
	rig.rotation.y = heading

func _pose() -> void:
	var st := {"time": anim_time, "phase": phase, "move": move_amt, "hit": hit,
		"atk": (atk_t / atk_dur) if atk_t >= 0.0 else -1.0,
		"style": "feral_lunge" if atk_kind == "pounce" else "feral_swipe"}
	if lion:
		Lion.pose(rig, st, HEIGHT)
	else:
		Anim.pose(rig, st)

func _reset_to_side() -> void:
	target = null
	state = "follow"
	path = PackedVector3Array()
	vel = Vector3.ZERO
	atk_t = -1.0
	var spot: Vector3 = game.world.free_spot_near(_follow_spot(), 1.5)
	global_position = Vector3(spot.x, game.world.height_at(spot.x, spot.z), spot.z)
	heading = master.rig.rotation.y
	_owner_last = master.global_position
	_owner_v = Vector3.ZERO
	settled = false

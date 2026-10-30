class_name Sloth
extends RefCounted
## The Hollow Sloths (Act I): three giant Forsaken sloths that roam the whole moor, each on its own long
## wander, crossing the road, stopping to sniff, rising onto their hind legs to look about. One that
## spots a hero rises, stares, roars and comes on all fours, slow to start and building into a
## lumbering run; it fights with three skills (the Rending Sweep, the Earthshaker slam, the Hollow
## Pounce), runs off when badly hurt and comes back for more, and gives up on a hero who gets away.
## Best avoided: its thudding steps and groans carry, and the corner map marks it when it's near.
## Each has an element ("element" in Data.ENEMIES) that runs through its skills and its look:
##   fire (Cinderhide): the sweep leaves burning ground, the slam a ring of fire, the pounce lands in flame;
##   cold (Rimeclaw): the sweep chills (slows), the slam freezes you solid, the pounce bursts into ice shards;
##   lightning (Thundermaw): the sweep chains to the heroes nearby, the slam calls bolts down round it,
##   the pounce is a quicker lightning dash that shocks where it lands.
## Each drops its own material ("drop"), and its model is hollow_sloth_<variant>.glb.
##
## The body is posed in code every frame from the enemy's state, like the lion (lion.gd): a skeleton
## standing upright at rest (the Meshy A-pose), turned per bone about the model's own axes. Until the
## Meshy model exists (assets/models/monsters/hollow_sloth.glb) a stand-in of capsules on the same
## skeleton is built. Host-authoritative: every timed move goes through the enemy's atk_t / atk_dur /
## atk_style, so co-op partners see it posed by the same `pose` from the synced state.

const GLB := "res://assets/models/monsters/hollow_sloth_%s.glb"
## per element: its colour (light, aura, effects) and the effect sounds
const ELEMENTS := {"fire": {"col": Color(1.0, 0.45, 0.1)}, "cold": {"col": Color(0.45, 0.85, 1.0)}, "lightning": {"col": Color(0.72, 0.45, 1.0)}}
const SCALE := 1.0
## the Meshy models are 2.5 m in their A-pose: this makes them about 3.5 m reared up
const MODEL_SCALE := 1.4
## ground the walk covers per cycle (at the stand-in's size)
const STRIDE := 2.2
const WALK := 2.2           # roaming pace (the hero walks at 4.8)
const RUN := 5.6            # its charge: faster than a walk, slower than a sprint
const FLEE := 6.2
const SEE := 15.0           # how far it notices a hero (further when standing up looking about)
const LOSE := 32.0          # beyond this, out of sight, for LOSE_T seconds: it gives up
const LOSE_T := 5.0

## the timed moves: [seconds, the moment it lands (or -1)]
const MOVES := {"sloth_rise": [1.0, -1.0], "sloth_look": [2.6, -1.0], "sloth_stare": [1.3, -1.0],
	"sloth_roar": [1.7, 0.3], "sloth_drop": [0.7, -1.0], "sloth_sniff": [2.2, -1.0],
	"sloth_sweep": [1.35, 0.47], "sloth_slam": [1.9, 0.6], "sloth_pounce": [1.25, 0.62]}

var e: Enemy
var state := "roam"         # roam, notice, hunt, flee, search
var goal := Vector3.ZERO
var goal_t := 0.0
var queue: Array = []       # the timed moves still to play in this state
var move := ""              # the timed move playing (atk_style), "" when walking or running
var chase_t := 0.0          # seconds into the hunt (the run builds up)
var lost_t := 0.0
var flees := 0
var sweep_cd := 0.0
var slam_cd := 4.0
var pounce_cd := 3.0
var pounce_to := Vector3.ZERO
var pounce_from := Vector3.ZERO
var idle_t := 0.0
var element := ""
## burning ground (fire) on the host: [pos, radius, until (anim time), damage a tick]
var hazards: Array = []
var _haz_t := 0.0
## lightning strikes called down by the storm slam: [pos, at (seconds from now)]
var strikes: Array = []
var _rng := RandomNumberGenerator.new()

func _init(enemy: Enemy) -> void:
	e = enemy
	element = str(e.def.get("element", ""))
	_rng.randomize()
	idle_t = _rng.randf_range(4.0, 12.0)

static func ok(variant: String) -> bool:
	return ResourceLoader.exists(GLB % variant)

# ---------------------------------------------------------------- the brain (host only)

## The sloth's velocity this frame. Plays its timed moves through the enemy's attack fields.
func update(delta: float, hero: Node3D, to: Vector3, dist: float, hero_gone: bool) -> Vector3:
	sweep_cd -= delta
	slam_cd -= delta
	pounce_cd -= delta
	_tick_hazards(delta)
	if e.stun_t > 0.0:
		e.stun_t -= delta
		move = ""
		queue.clear()
		return Vector3.ZERO
	# a timed move in progress (a stun or a heavy blow can cut it short: atk_t goes to -1)
	if move != "":
		if e.atk_t < 0.0:
			move = ""
			queue.clear()
		else:
			return _play(delta, hero, dist)
	if not queue.is_empty():
		_start(queue.pop_front())
		return Vector3.ZERO
	var sees: bool = not hero_gone and dist < (SEE * (1.6 if e.atk_style == "sloth_look" else 1.0)) and e.game.world.los(e.global_position, hero.global_position)
	match state:
		"roam":
			if e.aggro or sees:
				_notice(e.aggro)
				return Vector3.ZERO
			return _roam(delta)
		"hunt":
			if hero_gone:
				_give_up()
				return Vector3.ZERO
			# badly hurt: it turns and runs, twice in a fight (at half life, then a fifth)
			if (flees == 0 and e.life < e.max_life * 0.5) or (flees == 1 and e.life < e.max_life * 0.2):
				flees += 1
				_flee(hero)
				return Vector3.ZERO
			if dist > LOSE or not sees:
				lost_t += delta
				if lost_t > LOSE_T:
					_give_up()
					return Vector3.ZERO
			else:
				lost_t = 0.0
			return _hunt(delta, hero, to, dist)
		"flee":
			goal_t -= delta
			e.life = minf(e.max_life, e.life + e.max_life * 0.012 * delta)
			var d := goal - e.global_position
			d.y = 0
			if goal_t <= 0.0 or d.length() < 2.0:
				# far enough: it rises to look back, and comes again if you followed
				state = "search"
				queue = ["sloth_rise", "sloth_look"]
				return Vector3.ZERO
			e.atk_style = "sloth_run"
			return e.go_to(delta, goal, FLEE)
		"search":
			if sees:
				_notice(true)
				return Vector3.ZERO
			_drop_down()
			state = "roam"
			e.aggro = false
			goal_t = 0.0
	return Vector3.ZERO

func _start(m: String) -> void:
	if m == "":
		return
	move = m
	e.atk_style = m
	e.atk_t = 0.0
	e.atk_dur = MOVES[m][0] * (0.82 if e.enraged and m in ["sloth_sweep", "sloth_slam", "sloth_pounce"] else 1.0)
	if m == "sloth_pounce" and element == "lightning":
		e.atk_dur *= 0.75
	e.impact_done = false
	e.special = m
	match m:
		"sloth_sweep":
			e._fx("sloth_sweep_tele")
		"sloth_slam":
			e._fx("sloth_slam_tele")
		"sloth_pounce":
			e._fx("sloth_pounce_tele:%.2f,%.2f" % [pounce_to.x, pounce_to.z])
		"sloth_rise", "sloth_drop":
			e._fx("sloth_heave")

func _play(delta: float, hero: Node3D, dist: float) -> Vector3:
	e.atk_t += delta
	var a := e.atk_t / e.atk_dur
	var hit_at: float = MOVES[move][1]
	if move in ["sloth_stare", "sloth_roar", "sloth_rise"] or (move in ["sloth_sweep", "sloth_slam"] and a < hit_at * 0.75):
		e._face(hero.global_position - e.global_position)
	if move == "sloth_pounce":
		var want := pounce_from.lerp(pounce_to, smoothstep(0.28, 0.62, a)) - e.global_position
		want.y = 0
		e.global_position = e.game.world.move(e.global_position, want, e.body_r())
	if hit_at >= 0.0 and not e.impact_done and a >= hit_at:
		e.impact_done = true
		_land(hero, dist)
	if e.atk_t >= e.atk_dur:
		e.atk_t = -1.0
		e.special = ""
		var was := move
		move = ""
		if was in ["sloth_sweep", "sloth_slam", "sloth_pounce"]:
			e.cooldown = _rng.randf_range(0.5, 1.1) * (0.7 if e.enraged else 1.0)
		if was == "sloth_slam":
			# it slammed down onto all fours
			e.atk_style = "sloth_walk"
	return Vector3.ZERO

## Where each move lands: the sweep's arc, the slam's ring, the pounce's claws, each with its element.
func _land(_hero: Node3D, _dist: float) -> void:
	var fwd := -e.rig.global_transform.basis.z
	var el := element if element != "" else "phys"
	match move:
		"sloth_roar":
			e._fx("sloth_roar")
		"sloth_sweep":
			e._fx("sloth_sweep")
			var hit: Array = []
			for h in e.game.all_heroes():
				var to: Vector3 = h.global_position - e.global_position
				to.y = 0
				if not h.dead and to.length() < e.radius + 2.6 and (to.length() < 1.2 or fwd.dot(to.normalized()) > -0.25):
					h.take_hit(e._roll() * 1.1, e.global_position, "chill" if el == "cold" else "sweep", el)
					hit.append(h)
			match element:
				"fire":
					# the claws leave a trail of burning ground across the arc
					for k in 3:
						var a := (float(k) - 1.0) * 0.7
						_hazard(e.global_position + fwd.rotated(Vector3.UP, a) * (e.radius + 1.4), 1.3, 4.0, e._roll() * 0.18)
				"lightning":
					# it jumps from each hero struck to the others near them
					for h in hit:
						for o in e.game.all_heroes():
							if o != h and not o.dead and not hit.has(o) and o.global_position.distance_to(h.global_position) < 6.0:
								e._fx("sloth_chain:%.2f,%.2f,%.2f,%.2f" % [h.global_position.x, h.global_position.z, o.global_position.x, o.global_position.z])
								o.take_hit(e._roll() * 0.6, h.global_position, "melee", "lightning")
		"sloth_slam":
			e._fx("sloth_slam")
			var at := e.global_position + fwd * 1.6
			for h in e.game.all_heroes():
				if not h.dead and h.global_position.distance_to(at) < 5.0:
					h.take_hit(e._roll() * 1.4, at, "freeze" if el == "cold" else "quake", el)
			match element:
				"fire":
					_hazard(at, 4.0, 3.5, e._roll() * 0.22)
				"lightning":
					# bolts called down round it: one on each hero near, the rest at random, a moment apart
					var spots: Array = []
					for h in e.game.all_heroes():
						if not h.dead and h.global_position.distance_to(at) < 10.0:
							spots.append(h.global_position)
					while spots.size() < 6:
						var a := _rng.randf() * TAU
						spots.append(at + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(2.0, 7.5))
					for k in spots.size():
						var p: Vector3 = spots[k]
						strikes.append([p, 0.7 + k * 0.12])
						e._fx("sloth_strike_tele:%.2f,%.2f,%.2f" % [p.x, p.z, 0.7 + k * 0.12])
		"sloth_pounce":
			e._fx("sloth_land")
			for h in e.game.all_heroes():
				if not h.dead and h.global_position.distance_to(e.global_position) < e.radius + (2.4 if el == "cold" else 1.6):
					h.take_hit(e._roll() * 1.3, e.global_position, {"cold": "chill", "lightning": "shock"}.get(el, "sweep"), el)
			if element == "fire":
				_hazard(e.global_position, 2.4, 3.0, e._roll() * 0.2)

## Burning ground (host): it hurts any hero standing in it every half second until it dies down.
func _hazard(at: Vector3, r: float, dur: float, dmg: float) -> void:
	at.y = 0.0
	hazards.append([at, r, e.anim_time + dur, dmg])
	e._fx("sloth_burn:%.2f,%.2f,%.2f,%.2f" % [at.x, at.z, r, dur])

func _tick_hazards(delta: float) -> void:
	_haz_t -= delta
	if _haz_t <= 0.0 and not hazards.is_empty():
		_haz_t = 0.5
		for hz in hazards.duplicate():
			if e.anim_time > float(hz[2]):
				hazards.erase(hz)
				continue
			for h in e.game.all_heroes():
				var d := Vector2(h.global_position.x - hz[0].x, h.global_position.z - hz[0].z).length()
				if not h.dead and d < float(hz[1]):
					h.take_hit(float(hz[3]), hz[0], "burn", "fire")
	for st in strikes.duplicate():
		st[1] = float(st[1]) - delta
		if float(st[1]) <= 0.0:
			strikes.erase(st)
			var p: Vector3 = st[0]
			e._fx("sloth_strike:%.2f,%.2f" % [p.x, p.z])
			for h in e.game.all_heroes():
				if not h.dead and Vector2(h.global_position.x - p.x, h.global_position.z - p.z).length() < 1.7:
					h.take_hit(e._roll() * 0.9, p, "shock", "lightning")

## It has seen (or felt) a hero: up on its hind legs, a long stare, the roar, and down to come for them.
func _notice(angry: bool) -> void:
	state = "hunt"
	e.aggro = true
	chase_t = 0.0
	lost_t = 0.0
	var standing := e.atk_style in ["sloth_look", "sloth_stare", "sloth_roar", "sloth_rise"]
	queue = ([] if standing else ["sloth_rise"]) + (["sloth_roar"] if angry else ["sloth_stare", "sloth_roar"]) + ["sloth_drop"]

func _give_up() -> void:
	state = "search"
	e.aggro = false
	e.f_calm = 6.0
	queue = ["sloth_rise", "sloth_look"]

func _flee(hero: Node3D) -> void:
	state = "flee"
	var away := e.global_position - hero.global_position
	away.y = 0
	away = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
	goal = _spot(e.global_position + away * 38.0, 10.0)
	goal_t = 9.0
	queue = ["sloth_roar"] if e.atk_style in ["sloth_stare", "sloth_look"] else []
	e._fx("sloth_hurt")

## Down onto all fours if it's standing.
func _drop_down() -> void:
	if e.atk_style in ["sloth_look", "sloth_stare", "sloth_roar", "sloth_rise"]:
		queue.push_front("sloth_drop")

## The long wander: a far point anywhere on the moor, walked at its own pace with stops to sniff and to
## rise and look about.
func _roam(delta: float) -> Vector3:
	if e.atk_style in ["sloth_look", "sloth_stare", "sloth_roar", "sloth_rise"]:
		_drop_down()
		return Vector3.ZERO
	goal_t -= delta
	idle_t -= delta
	var d := goal - e.global_position
	d.y = 0
	if goal_t <= 0.0 or d.length() < 3.0:
		goal = _far_goal()
		goal_t = 70.0
	if idle_t <= 0.0:
		idle_t = _rng.randf_range(7.0, 16.0)
		queue = ["sloth_sniff"] if _rng.randf() < 0.55 else ["sloth_rise", "sloth_look", "sloth_drop"]
		return Vector3.ZERO
	e.atk_style = "sloth_walk"
	return e.go_to(delta, goal, WALK)

func _hunt(delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	if e.atk_style in ["sloth_look", "sloth_stare", "sloth_roar", "sloth_rise"]:
		_drop_down()
		return Vector3.ZERO
	chase_t += delta
	if not e.enraged and e.life < e.max_life * 0.3:
		e.enraged = true
		e._fx("sloth_enrage")
	var reach := e.radius + 1.7
	if e.cooldown <= 0.0:
		if dist < 4.6 and slam_cd <= 0.0 and _rng.randf() < 0.5:
			slam_cd = _rng.randf_range(8.0, 11.0) * (0.75 if e.enraged else 1.0)
			e._face(to)
			_start("sloth_slam")
			return Vector3.ZERO
		if dist > 5.5 and dist < 11.0 and pounce_cd <= 0.0 and e.game.world.los(e.global_position, hero.global_position):
			pounce_cd = _rng.randf_range(8.0, 12.0) * (0.75 if e.enraged else 1.0)
			e._face(to)
			e.rig.rotation.y = atan2(-to.x, -to.z)
			pounce_from = e.global_position
			# it lands short of the hero, claws first
			pounce_to = hero.global_position - to.normalized() * (e.radius + 0.6)
			_start("sloth_pounce")
			return Vector3.ZERO
		if dist < reach + hero.radius:
			e._face(to)
			_start("sloth_sweep")
			return Vector3.ZERO
	if dist < reach + hero.radius - 0.4:
		return Vector3.ZERO
	# slow to start, building into a lumbering run
	var spd := lerpf(WALK, RUN, smoothstep(0.0, 2.2, chase_t))
	e.atk_style = "sloth_run" if spd > WALK * 1.6 else "sloth_walk"
	return e.go_to(delta, hero.global_position, spd)

## A far free point to wander to: somewhere else on the moor, kept off the camp's doorstep.
func _far_goal() -> Vector3:
	var b: Rect2 = e.game.world.bounds.grow(-6.0)
	for i in 30:
		var p := Vector3(_rng.randf_range(b.position.x, b.end.x), 0, _rng.randf_range(b.position.y, b.end.y))
		if p.distance_to(e.global_position) < 45.0 or Vector2(p.x, p.z).distance_to(Vector2(0, -6)) < 28.0:
			continue
		if not e.game.world.is_blocked(p.x, p.z):
			return p
	return e.home

func _spot(p: Vector3, r: float) -> Vector3:
	var b: Rect2 = e.game.world.bounds.grow(-4.0)
	p.x = clampf(p.x, b.position.x, b.end.x)
	p.z = clampf(p.z, b.position.y, b.end.y)
	return e.game.world.free_spot_near(p, r)

# ---------------------------------------------------------------- what everyone sees and hears

## Its presence, on every peer: heavy footfalls (dust, a thud, the ground shaking when it's near) and
## a low groan now and then.
static func presence(en: Enemy, delta: float, last_phase: float) -> void:
	var g = en.game
	var d: float = g.hero.global_position.distance_to(en.global_position)
	if d > 45.0:
		return
	var walking := en.atk_style in ["sloth_walk", "sloth_run"] and en.move_amt > 0.2
	# four footfalls a cycle
	var per := STRIDE * 1.6 / maxf(en.height, 0.3) * 0.25
	if walking and floorf(en.phase / per) != floorf(last_phase / per):
		var side := 1.0 if int(floorf(en.phase / per)) % 2 == 0 else -1.0
		var foot := en.global_position + en.rig.global_transform.basis.x * side * 0.6
		if d < 25.0:
			Fx.burst(g.world.fx_root, foot + Vector3(0, 0.08, 0), Color(0.36, 0.32, 0.27, 0.6), 7, 1.3, 0.25, 0.6, false, -1.0, 70.0)
		Sfx.play_at("slam", foot, -16.0 if en.atk_style == "sloth_walk" else -11.0, randf_range(0.42, 0.55))
		if d < 16.0:
			g.add_shake((0.05 if en.atk_style == "sloth_walk" else 0.09) * (1.0 - d / 16.0))
	if not en.has_meta("groan_t"):
		en.set_meta("groan_t", randf_range(3.0, 9.0))
	var gt: float = float(en.get_meta("groan_t")) - delta
	if gt <= 0.0:
		gt = randf_range(7.0, 14.0)
		Sfx.play_at("growl", en.global_position + Vector3(0, 2.0, 0), -6.0, randf_range(0.42, 0.52))
	en.set_meta("groan_t", gt)

## The visible side of its moves, on every peer (Enemy.special_fx sends these here).
static func fx(en: Enemy, ev: String) -> void:
	var g = en.game
	var root: Node3D = g.world.fx_root
	var fwd := -en.rig.global_transform.basis.z
	var d: float = g.hero.global_position.distance_to(en.global_position)
	var el := str(en.def.get("element", ""))
	var col := _col(en)
	if ev.contains(":") and _elem_fx(en, ev, el, col, root, d):
		return
	if ev.begins_with("sloth_pounce_tele:"):
		var xz := ev.get_slice(":", 1).split(",")
		var at := Vector3(float(xz[0]), 0, float(xz[1]))
		at.y = g.world.height_at(at.x, at.z)
		Fx.telegraph(root, at, en.radius + 1.6, MOVES["sloth_pounce"][0] * MOVES["sloth_pounce"][1])
		Sfx.play_at("growl", en.global_position, -2.0, 0.5)
		return
	match ev:
		"sloth_sweep_tele":
			Sfx.play_at("swing_heavy", en.global_position + Vector3(0, 2.0, 0), -2.0, 0.55)
		"sloth_slam_tele":
			Fx.telegraph(root, en.global_position + fwd * 1.6, 5.0, MOVES["sloth_slam"][0] * MOVES["sloth_slam"][1])
			_elem_charge(en, el)
		"sloth_heave":
			Sfx.play_at("growl", en.global_position + Vector3(0, 2.0, 0), -9.0, randf_range(0.5, 0.6))
		"sloth_roar":
			Sfx.play_at("roar", en.global_position + Vector3(0, 3.0, 0), 4.0, 0.62)
			Sfx.play_at("lion_roar", en.global_position + Vector3(0, 3.0, 0), -2.0, 0.55)
			if d < 30.0:
				g.add_shake(0.5 * (1.0 - d / 30.0) + 0.1)
				g.ui.message("%s has seen you" % en.display_name, _col(en))
			# the forest's birds take off from the trees about it
			for i in 3:
				var a := randf() * TAU
				var p := en.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(6.0, 14.0)
				Fx.burst(root, p + Vector3(0, 5.5, 0), Color(0.08, 0.07, 0.06, 0.9), 9, 4.0, 0.12, 1.6, false, 1.5, 50.0)
		"sloth_sweep":
			Fx.burst(root, en.global_position + fwd * 2.0 + Vector3(0, 0.6, 0), Color(0.35, 0.3, 0.24, 0.7), 24, 5.0, 0.25, 0.7, false, -3.0, 90.0)
			_elem_burst(root, en.global_position + fwd * 2.2, el, 2.5)
			if d < 12.0:
				g.add_shake(0.25)
		"sloth_slam":
			var at := en.global_position + fwd * 1.6
			Fx.ring(root, at, 5.0, col, 0.55)
			_elem_burst(root, at, el, 5.0)
			Fx.burst(root, at + Vector3(0, 0.3, 0), Color(0.42, 0.37, 0.3, 0.85), 50, 7.0, 0.35, 1.0, false, -4.0, 80.0)
			Sfx.play_at("slam", at, 6.0, 0.6)
			Sfx.play_at("boom", at, 0.0, 0.7)
			if d < 25.0:
				g.add_shake(0.7 * (1.0 - d / 25.0) + 0.15)
		"sloth_land":
			Fx.burst(root, en.global_position + Vector3(0, 0.3, 0), Color(0.4, 0.35, 0.28, 0.8), 30, 5.0, 0.3, 0.8, false, -4.0, 80.0)
			_elem_burst(root, en.global_position, el, 2.6)
			Sfx.play_at("slam", en.global_position, 2.0, 0.55)
			if d < 15.0:
				g.add_shake(0.35)
		"sloth_hurt":
			Sfx.play_at("growl", en.global_position + Vector3(0, 2.5, 0), 0.0, 0.7)
			if d < 30.0:
				g.ui.message("%s flees, wounded" % en.display_name, _col(en))
		"sloth_enrage":
			Sfx.play_at("roar", en.global_position + Vector3(0, 3.0, 0), 2.0, 0.55)

static func _col(en: Enemy) -> Color:
	return ELEMENTS.get(str(en.def.get("element", "")), {"col": Color(0.55, 0.9, 0.95)})["col"]

## Its element bursting out where a blow lands: flames, ice shards and frost, or a crackle of sparks.
static func _elem_burst(root: Node3D, at: Vector3, el: String, r: float) -> void:
	match el:
		"fire":
			Fx.burst(root, at + Vector3(0, 0.3, 0), Color(1.0, 0.38, 0.05, 0.9), 46, r * 1.4, 0.2, 0.7, false, 2.0, 70.0)
			Fx.burst(root, at + Vector3(0, 0.5, 0), Color(1.0, 0.7, 0.2, 0.9), 24, r, 0.09, 0.5, false, 4.0, 40.0)
			Sfx.play_at("fire_erupt", at, 0.0, randf_range(0.9, 1.05))
		"cold":
			Fx.burst(root, at + Vector3(0, 0.3, 0), Color(0.25, 0.42, 0.6), 45, r * 1.5, 0.1, 0.8, true, -6.0, 75.0)
			Fx.burst(root, at + Vector3(0, 0.2, 0), Color(0.85, 0.95, 1.0, 0.5), 18, r * 0.5, 0.6, 1.4, false, 0.2, 90.0)
			_ice_spikes(root, at, r)
			Sfx.play_at("ice_shatter", at, 0.0, randf_range(0.9, 1.05))
		"lightning":
			Fx.burst(root, at + Vector3(0, 0.4, 0), Color(0.45, 0.32, 0.6), 40, r * 2.0, 0.06, 0.35, true, 0.0, 180.0)
			for k in 4:
				var a := randf() * TAU
				_bolt(root, at + Vector3(0, 0.3, 0), at + Vector3(cos(a) * r * 0.8, 0.1, sin(a) * r * 0.8), Color(0.8, 0.6, 1.0))
			Sfx.play_at("thunder_strike", at, -4.0, randf_range(1.0, 1.2))

## Jagged ice spikes thrust up out of the ground in a ring, then sink.
static func _ice_spikes(root: Node3D, at: Vector3, r: float) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = at
	var mat := Mats.mat(Color(0.7, 0.88, 1.0, 0.85), 0.08, 0.0, Color(0.35, 0.65, 1.0), 0.6)
	for k in 9:
		var a := TAU * k / 9.0 + randf() * 0.4
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = randf_range(0.12, 0.22)
		cm.height = randf_range(0.7, 1.4)
		c.mesh = cm
		c.material_override = mat
		var d := r * randf_range(0.45, 0.85)
		c.position = Vector3(cos(a) * d, cm.height * 0.35, sin(a) * d)
		c.rotation = Vector3(randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35))
		holder.add_child(c)
	var tw := holder.create_tween()
	holder.scale = Vector3(1, 0.05, 1)
	tw.tween_property(holder, "scale", Vector3.ONE, 0.12)
	tw.tween_interval(1.6)
	tw.tween_property(holder, "position:y", -1.2, 0.8)
	tw.tween_callback(holder.queue_free)

## A short-lived jagged lightning bolt from a to b.
static func _bolt(root: Node3D, a: Vector3, b: Vector3, col: Color) -> void:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = Mats.glow(col, 2.2, 0.0, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var n := 8
	var side := (b - a).cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var pts := []
	for k in n + 1:
		var t := float(k) / n
		var p := a.lerp(b, t)
		if k > 0 and k < n:
			p += side * randf_range(-0.25, 0.25) + Vector3(0, randf_range(-0.2, 0.2), 0)
		pts.append(p)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n:
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var w := 0.03 if col.r < 0.95 else 0.015
		var up := Vector3(0, w, 0)
		var sw := side * w
		for q in [[p0 - sw, p1 - sw, p1 + sw], [p0 - sw, p1 + sw, p0 + sw], [p0 - up, p1 - up, p1 + up], [p0 - up, p1 + up, p0 + up]]:
			for v in q:
				im.surface_add_vertex(v)
	im.surface_end()
	var tw := mi.create_tween()
	tw.tween_interval(0.18)
	tw.tween_callback(mi.queue_free)

## Its element gathering while it rears up to slam (the casting motion in `pose`): embers and a glow
## swelling from its chest (fire), frost mist curling round its crossed claws (cold), or arcs leaping
## between its raised claws and up into the sky (lightning).
static func _elem_charge(en: Enemy, el: String) -> void:
	var root: Node3D = en.game.world.fx_root
	var dur: float = MOVES["sloth_slam"][0] * 0.5
	var tw := root.create_tween()
	for k in 6:
		tw.tween_interval(dur / 6.0)
		tw.tween_callback(func():
			if not is_instance_valid(en) or en.dead:
				return
			var c := en.global_position + Vector3(0, 2.6, 0) - en.rig.global_transform.basis.z * 0.3
			match el:
				"fire":
					Fx.burst(root, c, Color(1.0, 0.45, 0.08, 0.9), 16, 2.0, 0.09, 0.6, false, 3.0, 50.0)
					Fx.flash(root, c, Color(1.0, 0.45, 0.1), 2.5, 0.3, 5.0)
				"cold":
					Fx.burst(root, c - Vector3(0, 0.4, 0), Color(0.8, 0.93, 1.0, 0.6), 10, 0.6, 0.5, 1.0, false, 0.3, 120.0)
				"lightning":
					var hand_y := 4.2
					var l := en.global_position + en.rig.global_transform.basis.x * 0.7 + Vector3(0, hand_y, 0)
					var r := en.global_position - en.rig.global_transform.basis.x * 0.7 + Vector3(0, hand_y, 0)
					_bolt(root, l, r, Color(0.85, 0.7, 1.0))
					if randf() < 0.5:
						_bolt(root, (l + r) * 0.5, (l + r) * 0.5 + Vector3(randf_range(-2, 2), 8.0, randf_range(-2, 2)), Color(0.9, 0.85, 1.0))
		)
	if el == "lightning":
		Sfx.play_at("thunder_strike", en.global_position + Vector3(0, 4, 0), -8.0, 0.8)

## The element effects that carry a place in their event string.
static func _elem_fx(en: Enemy, ev: String, el: String, col: Color, root: Node3D, d: float) -> bool:
	var g = en.game
	var args := ev.get_slice(":", 1).split(",")
	var nm := ev.get_slice(":", 0)
	match nm:
		"sloth_burn":
			# burning ground: flames licking up from the patch until it dies down
			var at := Vector3(float(args[0]), 0, float(args[1]))
			at.y = g.world.height_at(at.x, at.z)
			var r := float(args[2])
			var dur := float(args[3])
			var patch := Node3D.new()
			root.add_child(patch)
			patch.global_position = at + Vector3(0, 0.1, 0)
			var fl := Fx.aura(patch, Color(1.0, 0.36, 0.04, 0.85), int(14 + r * 16), 1.4, 0.2, 0.8, 1.5, r * 0.8, 20.0, Vector3.ZERO, false)
			(fl.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			(fl.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(r * 0.75, 0.05, r * 0.75)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.5, 0.15)
			l.light_energy = 1.5
			l.omni_range = r * 1.8
			l.position = Vector3(0, 0.5, 0)
			patch.add_child(l)
			Fx.ring(root, at, r, Color(1.0, 0.4, 0.1), 0.5)
			var tw := patch.create_tween()
			tw.tween_interval(dur)
			tw.tween_callback(func(): fl.emitting = false)
			tw.tween_property(l, "light_energy", 0.0, 0.8)
			tw.tween_callback(patch.queue_free)
			return true
		"sloth_chain":
			var a := Vector3(float(args[0]), 1.1, float(args[1]))
			var b := Vector3(float(args[2]), 1.1, float(args[3]))
			_bolt(root, a, b, Color(0.8, 0.6, 1.0))
			_bolt(root, a, b, Color(0.95, 0.9, 1.0))
			Sfx.play_at("thunder_strike", b, -6.0, 1.3)
			return true
		"sloth_strike_tele":
			var at := Vector3(float(args[0]), 0, float(args[1]))
			at.y = g.world.height_at(at.x, at.z)
			Fx.telegraph(root, at, 1.7, float(args[2]), Color(0.7, 0.45, 1.0))
			return true
		"sloth_strike":
			var at := Vector3(float(args[0]), 0, float(args[1]))
			at.y = g.world.height_at(at.x, at.z)
			_bolt(root, at + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), at, Color(0.85, 0.7, 1.0))
			_bolt(root, at + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), at, Color(1.0, 1.0, 1.0))
			Fx.flash(root, at + Vector3(0, 1.0, 0), Color(0.75, 0.55, 1.0), 6.0, 0.25, 9.0)
			Fx.burst(root, at + Vector3(0, 0.2, 0), Color(0.45, 0.32, 0.6), 26, 5.0, 0.06, 0.35, true, -2.0, 80.0)
			Fx.ring(root, at, 1.7, Color(0.75, 0.5, 1.0), 0.35)
			Sfx.play_at("thunder_strike", at, 0.0, randf_range(0.9, 1.1))
			if d < 20.0:
				g.add_shake(0.25)
			return true
	return false

## Its element about its body, on every peer: a light in its colour, and embers rising (fire), frost
## mist falling (cold) or sparks crackling off it (lightning).
static func dress(rig: Node3D, el: String) -> void:
	if not ELEMENTS.has(el):
		return
	var col: Color = ELEMENTS[el]["col"]
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 1.4
	l.omni_range = 5.0
	l.position = Vector3(0, 2.0, 0)
	rig.add_child(l)
	rig.set_meta("sloth_light", l)
	rig.set_meta("element", el)
	match el:
		"fire":
			Fx.aura(rig, Color(1.0, 0.45, 0.08, 0.9), 40, 1.2, 0.07, 1.4, 1.2, 0.7, 30.0, Vector3(0, 1.8, 0), false)
		"cold":
			Fx.aura(rig, Color(0.8, 0.92, 1.0, 0.5), 22, 0.2, 0.45, 2.2, -0.25, 0.8, 90.0, Vector3(0, 1.4, 0))
		"lightning":
			Fx.aura(rig, Color(0.45, 0.32, 0.6), 30, 2.2, 0.05, 0.25, 0.0, 0.9, 180.0, Vector3(0, 1.6, 0))

## Flicker of its light, and the storm's arcs across its body (Enemy._process, every peer).
static func idle_fx(en: Enemy, delta: float) -> void:
	var el := str(en.def.get("element", ""))
	if not en.rig.has_meta("sloth_light"):
		return
	var l: OmniLight3D = en.rig.get_meta("sloth_light")
	var t := en.anim_time
	match el:
		"fire":
			l.light_energy = 1.3 + 0.35 * sin(t * 9.0) + 0.2 * sin(t * 23.0)
		"cold":
			l.light_energy = 1.1 + 0.15 * sin(t * 1.3)
		"lightning":
			l.light_energy = 0.9 + (2.5 if fmod(t, 0.9) < 0.08 else 0.0)
			var gt: float = float(en.get_meta("arc_t", 0.0)) - delta
			if gt <= 0.0:
				gt = randf_range(0.4, 1.1)
				var c := en.global_position + Vector3(0, 1.6, 0)
				_bolt(en.game.world.fx_root, c + Vector3(randf_range(-0.8, 0.8), randf_range(-0.6, 0.8), randf_range(-0.6, 0.6)),
					c + Vector3(randf_range(-1.1, 1.1), randf_range(-1.0, 0.6), randf_range(-0.6, 0.6)), Color(0.85, 0.7, 1.0))
			en.set_meta("arc_t", gt)

# ---------------------------------------------------------------- the body

## bone: [parent, head position at rest (skeleton space: upright, facing +z, y up), radius of its
## capsule in the stand-in, the child it reaches to (for the capsule)]
const BONES := {
	"hips": ["", Vector3(0, 1.3, 0), 0.5, "spine"],
	"spine": ["hips", Vector3(0, 1.6, 0), 0.55, "chest"],
	"chest": ["spine", Vector3(0, 2.1, 0.02), 0.6, "neck"],
	"neck": ["chest", Vector3(0, 2.7, 0.08), 0.26, "head"],
	"head": ["neck", Vector3(0, 2.95, 0.14), 0.3, ""],
	"arm_l": ["chest", Vector3(0.5, 2.5, 0.05), 0.26, "forearm_l"],
	"forearm_l": ["arm_l", Vector3(1.05, 1.95, 0.05), 0.22, "hand_l"],
	"hand_l": ["forearm_l", Vector3(1.52, 1.48, 0.05), 0.17, ""],
	"arm_r": ["chest", Vector3(-0.5, 2.5, 0.05), 0.26, "forearm_r"],
	"forearm_r": ["arm_r", Vector3(-1.05, 1.95, 0.05), 0.22, "hand_r"],
	"hand_r": ["forearm_r", Vector3(-1.52, 1.48, 0.05), 0.17, ""],
	"thigh_l": ["hips", Vector3(0.36, 1.25, 0), 0.3, "shin_l"],
	"shin_l": ["thigh_l", Vector3(0.42, 0.68, 0.05), 0.24, "foot_l"],
	"foot_l": ["shin_l", Vector3(0.44, 0.14, 0), 0.17, ""],
	"thigh_r": ["hips", Vector3(-0.36, 1.25, 0), 0.3, "shin_r"],
	"shin_r": ["thigh_r", Vector3(-0.42, 0.68, 0.05), 0.24, "foot_r"],
	"foot_r": ["shin_r", Vector3(-0.44, 0.14, 0), 0.17, ""],
	"tail": ["hips", Vector3(0, 1.1, -0.4), 0.16, ""],
}

static func build(variant := "", tint := Color(0.52, 0.56, 0.47)) -> Node3D:
	var root := Node3D.new()
	var body: Node3D
	if variant != "" and ok(variant):
		body = (load(GLB % variant) as PackedScene).instantiate()
	else:
		body = _standin(tint)
	body.name = "Body"
	body.rotation.y = PI          # the model faces +z; monsters face -z
	body.scale = Vector3.ONE * (MODEL_SCALE if variant != "" and ok(variant) else SCALE)
	root.add_child(body)
	var sks := body.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return root
	var sk: Skeleton3D = sks[0]
	# as the lion: per bone its index, rest rotation and the model's side, up and back axes in its frame
	var info := {}
	for i in sk.get_bone_count():
		var gb := sk.get_bone_global_rest(i).basis.orthonormalized()
		var gi := gb.inverse()
		info[sk.get_bone_name(i)] = [i, sk.get_bone_rest(i).basis.get_rotation_quaternion(), (gi * Vector3.RIGHT).normalized(), (gi * Vector3.UP).normalized(), (gi * Vector3.BACK).normalized()]
	root.set_meta("sloth", sk)
	root.set_meta("sloth_bones", info)
	root.set_meta("sloth_body", body)
	# a dark outline and a cool rim (the Feral's), so the great shape reads against the forest floor
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_overlay = Feral.rim_mat()
		var shell := MeshInstance3D.new()
		shell.mesh = m.mesh
		shell.skin = m.skin
		shell.material_override = outline_mat()
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.get_parent().add_child(shell)
		if m.skin != null:
			shell.skeleton = shell.get_path_to(m.get_node(m.skeleton))
		shell.transform = m.transform
	return root

static var _outline: ShaderMaterial

## As the Feral's outline, a little thicker for its size.
static func outline_mat() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
void vertex(){ VERTEX += NORMAL * 0.03; }
void fragment(){ ALBEDO = vec3(0.02, 0.018, 0.016); }
"""
		_outline.shader = sh
	return _outline

## The stand-in body: the skeleton with a capsule along each bone, mossy grey-green, claws and cyan eyes.
static func _standin(tint: Color) -> Node3D:
	var body := Node3D.new()
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	body.add_child(sk)
	var names := BONES.keys()
	for n in names:
		sk.add_bone(n)
	for n in names:
		var b: Array = BONES[n]
		var i := sk.find_bone(n)
		var par := -1 if b[0] == "" else sk.find_bone(b[0])
		sk.set_bone_parent(i, par)
		var at: Vector3 = b[1]
		var rel: Vector3 = at - (Vector3.ZERO if b[0] == "" else (BONES[b[0]][1] as Vector3))
		sk.set_bone_rest(i, Transform3D(Basis(), rel))
	sk.reset_bone_poses()
	var fur := Mats.mat(tint, 0.95)
	var bare := Mats.mat(Color(0.55, 0.42, 0.38), 0.8)
	var claw := Mats.mat(Color(0.05, 0.05, 0.05), 0.35)
	var eye := Mats.glow(Color(0.45, 0.95, 1.0), 3.0, 0.0, 1.0)
	for n in names:
		var b: Array = BONES[n]
		var att := BoneAttachment3D.new()
		att.bone_name = n
		sk.add_child(att)
		var from: Vector3 = b[1]
		var to: Vector3 = from + Vector3(0, 0.5, 0)
		if b[3] != "":
			to = BONES[b[3]][1]
		elif n.begins_with("hand"):
			to = from + (from - (BONES["forearm" + n.substr(4)][1] as Vector3)).normalized() * 0.3
		elif n.begins_with("foot"):
			to = from + Vector3(0, -0.06, 0.34)
		elif n == "head":
			to = from + Vector3(0, 0.12, 0.42)
		elif n == "tail":
			to = from + Vector3(0, -0.35, -0.3)
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		var r: float = b[2]
		cm.radius = r
		cm.height = maxf(from.distance_to(to) + r * 1.4, r * 2.0)
		mi.mesh = cm
		mi.material_override = bare if n in ["chest", "hand_l", "hand_r"] else fur
		att.add_child(mi)
		# capsules run along local y: aim them from the bone's head toward its end (in the bone's rest frame)
		var dir := (to - from).normalized()
		var bas := Basis(Quaternion(Vector3.UP, dir)) if absf(dir.dot(Vector3.UP)) < 0.999 else (Basis() if dir.y > 0 else Basis(Vector3.RIGHT, PI))
		mi.transform = Transform3D(bas, (to - from) * 0.5)
		if n.begins_with("hand") or n.begins_with("foot"):
			for k in 3:
				var c := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.05 if n.begins_with("hand") else 0.04
				cone.height = 0.55 if n.begins_with("hand") else 0.22
				c.mesh = cone
				c.material_override = claw
				var side := (float(k) - 1.0) * 0.09
				var cb := bas * Basis(Vector3.RIGHT, 0.5)
				c.transform = Transform3D(cb, (to - from) + bas * Vector3(side, cone.height * 0.4, 0.0))
				att.add_child(c)
		if n == "head":
			for s in [-1.0, 1.0]:
				var ey := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.06
				sm.height = 0.12
				ey.mesh = sm
				ey.material_override = eye
				ey.position = Vector3(s * 0.13, 0.12, 0.34)
				att.add_child(ey)
	return body

## Turn a bone from its rest about the model's side (ax: + tips an upward bone's end forward, a
## downward one's back), up (ay: + swings it to the sloth's left) and back (az: + raises its left arm,
## lowers its right) axes.
static func _turn(sk: Skeleton3D, info: Dictionary, bone: String, r: Vector3) -> void:
	if not info.has(bone):
		return
	var b: Array = info[bone]
	var q: Quaternion = b[1]
	if r.x != 0.0:
		q = q * Quaternion(b[2], r.x)
	if r.y != 0.0:
		q = q * Quaternion(b[3], r.y)
	if r.z != 0.0:
		q = q * Quaternion(b[4], r.z)
	sk.set_bone_pose_rotation(b[0], q)

## Standing upright on its hind legs (u = 1): a hunch, arms hanging heavy and a little forward.
const UPRIGHT := {"hips": Vector3(0, 0, 0), "spine": Vector3(0.12, 0, 0), "chest": Vector3(0.12, 0, 0),
	"neck": Vector3(-0.1, 0, 0), "head": Vector3(-0.08, 0, 0),
	"arm_l": Vector3(-0.15, 0, -0.3), "forearm_l": Vector3(-0.35, 0, 0), "hand_l": Vector3(-0.2, 0, 0),
	"arm_r": Vector3(-0.15, 0, 0.3), "forearm_r": Vector3(-0.35, 0, 0), "hand_r": Vector3(-0.2, 0, 0),
	"thigh_l": Vector3(-0.1, 0, 0), "shin_l": Vector3(0.12, 0, 0), "foot_l": Vector3(0, 0, 0),
	"thigh_r": Vector3(-0.1, 0, 0), "shin_r": Vector3(0.12, 0, 0), "foot_r": Vector3(0, 0, 0),
	"tail": Vector3(0.35, 0, 0)}
## On all fours (u = 0): the back pitched forward, the long arms reaching down to the ground on the
## knuckles, head up and looking ahead, hind legs a little bent.
const FOURS := {"hips": Vector3(0.3, 0, 0), "spine": Vector3(0.75, 0, 0), "chest": Vector3(0.3, 0, 0),
	"neck": Vector3(-0.85, 0, 0), "head": Vector3(-0.35, 0, 0),
	"arm_l": Vector3(-1.2, 0, -0.55), "forearm_l": Vector3(-0.1, 0, 0), "hand_l": Vector3(0.7, 0, 0),
	"arm_r": Vector3(-1.2, 0, 0.55), "forearm_r": Vector3(-0.1, 0, 0), "hand_r": Vector3(0.7, 0, 0),
	"thigh_l": Vector3(-0.55, 0, 0), "shin_l": Vector3(0.45, 0, 0), "foot_l": Vector3(-0.2, 0, 0),
	"thigh_r": Vector3(-0.55, 0, 0), "shin_r": Vector3(0.45, 0, 0), "foot_r": Vector3(-0.2, 0, 0),
	"tail": Vector3(0.6, 0, 0)}
## how far the body sinks on all fours (the hips come down with the bent legs)
const FOURS_DROP := -0.22

## How upright it is (0 on all fours, 1 standing) in a move at progress k.
static func upright(style: String, k: float) -> float:
	match style:
		"sloth_rise":
			return smoothstep(0.0, 1.0, k)
		"sloth_drop":
			return 1.0 - smoothstep(0.0, 1.0, k)
		"sloth_look", "sloth_stare", "sloth_roar":
			return 1.0
		"sloth_sweep":
			return 0.55 * smoothstep(0.0, 0.3, k) * (1.0 - smoothstep(0.7, 1.0, k))
		"sloth_slam":
			return smoothstep(0.0, 0.35, k) * (1.0 - smoothstep(0.5, 0.6, k))
	return 0.0

## Poses the body from the enemy's state (Enemy._pose, on every peer).
static func pose(rig: Node3D, st: Dictionary, height: float) -> void:
	if not rig.has_meta("sloth"):
		return
	var sk: Skeleton3D = rig.get_meta("sloth")
	var info: Dictionary = rig.get_meta("sloth_bones")
	var body: Node3D = rig.get_meta("sloth_body")
	var t: float = st.get("time", 0.0)
	var mv := clampf(float(st.get("move", 0.0)), 0.0, 1.0)
	var style: String = st.get("style", "")
	var k: float = st.get("atk", -1.0)
	var hit: float = st.get("hit", 0.0)
	if st.has("dead"):
		style = ""
		mv = 0.0
	# between moves it holds the last one's posture (standing after a rise, a look, a stare or a roar)
	var u := upright(style, k) if k >= 0.0 else (1.0 if style in ["sloth_rise", "sloth_look", "sloth_stare", "sloth_roar"] else 0.0)
	var p := {}
	for bn in UPRIGHT:
		p[bn] = (FOURS[bn] as Vector3).lerp(UPRIGHT[bn], u)
	var lift := FOURS_DROP * (1.0 - u)
	# breathing
	var br := sin(t * 1.4)
	p["chest"] += Vector3(br * 0.025, 0, 0)
	p["neck"] += Vector3(-br * 0.02, 0, 0)
	# the gait: a slow diagonal walk, or a heavy bounding run (fore pair then hind pair)
	var run := style == "sloth_run"
	if style in ["sloth_walk", "sloth_run"] and mv > 0.01:
		var per_cycle := STRIDE * 1.6 / maxf(height, 0.3) * (1.5 if run else 1.0)
		var ph := fposmod(float(st.get("phase", 0.0)) / per_cycle, 1.0)
		var offs := {"l_f": 0.0, "r_b": 0.08, "r_f": 0.5, "l_b": 0.58} if not run else {"l_f": 0.0, "r_f": 0.1, "l_b": 0.5, "r_b": 0.6}
		var amp := (0.42 if not run else 0.7) * mv
		for leg in offs:
			var a := TAU * (ph + float(offs[leg]))
			var swing := sin(a) * amp
			var up := maxf(0.0, cos(a)) * amp * 1.2
			var s: String = leg.substr(0, 1)
			if leg.ends_with("f"):
				p["arm_" + s] += Vector3(-swing, 0, 0)
				p["forearm_" + s] += Vector3(-up * 0.9, 0, 0)
				p["hand_" + s] += Vector3(up * 0.6, 0, 0)
			else:
				p["thigh_" + s] += Vector3(-swing, 0, 0)
				p["shin_" + s] += Vector3(up * 1.1, 0, 0)
				p["foot_" + s] += Vector3(-up * 0.4, 0, 0)
		# the heavy body rolls with the steps; the run rocks it fore and aft
		var rock := sin(TAU * ph * (1.0 if run else 2.0))
		p["spine"] += Vector3(rock * (0.12 if run else 0.04) * mv, 0, sin(TAU * ph) * 0.06 * mv)
		p["chest"] += Vector3(0, sin(TAU * ph) * 0.08 * mv, 0)
		p["neck"] += Vector3(-rock * (0.1 if run else 0.04) * mv, 0, 0)
		lift += absf(sin(TAU * ph * 2.0)) * (0.06 if not run else 0.16) * mv
		p["tail"] += Vector3(0, sin(TAU * ph) * 0.3, 0)
	else:
		# standing about: the head moves, slowly
		p["neck"] += Vector3(0, sin(t * 0.5) * 0.15, 0)
	if k >= 0.0:
		match style:
			"sloth_sniff":
				# nose to the ground, snuffling side to side
				var dn := smoothstep(0.0, 0.2, k) * (1.0 - smoothstep(0.82, 1.0, k))
				p["neck"] += Vector3(0.8 * dn, sin(k * 9.0) * 0.35 * dn, 0)
				p["head"] += Vector3(0.35 * dn + sin(t * 9.0) * 0.06 * dn, 0, 0)
				p["chest"] += Vector3(0.12 * dn, 0, 0)
			"sloth_look":
				# up on its hind legs, looking about: left, right, and up to the canopy
				p["neck"] += Vector3(-0.15 * sin(k * PI), sin(k * TAU) * 0.7, 0)
				p["head"] += Vector3(-0.15 * sin(k * TAU * 1.5), sin(k * TAU) * 0.3, 0)
				p["chest"] += Vector3(0, sin(k * TAU) * 0.2, 0)
			"sloth_stare":
				# dead still, head low and forward, arms spread a little: watching you
				p["neck"] += Vector3(0.18, 0, 0)
				p["head"] += Vector3(0.1, 0, 0)
				p["arm_l"] += Vector3(-0.2, 0, 0.25)
				p["arm_r"] += Vector3(-0.2, 0, -0.25)
			"sloth_roar":
				# chest out, arms flung wide, head thrown up and forward
				var r := smoothstep(0.0, 0.25, k) * (1.0 - smoothstep(0.8, 1.0, k))
				p["spine"] += Vector3(-0.25 * r, 0, 0)
				p["chest"] += Vector3(-0.2 * r, 0, 0)
				p["neck"] += Vector3(0.1 * r, sin(k * 30.0) * 0.04 * r, 0)
				p["head"] += Vector3(-0.45 * r, 0, 0)
				p["arm_l"] += Vector3(-0.5 * r, 0, 0.95 * r)
				p["arm_r"] += Vector3(-0.5 * r, 0, -0.95 * r)
				p["forearm_l"] += Vector3(-0.5 * r, 0, 0)
				p["forearm_r"] += Vector3(-0.5 * r, 0, 0)
			"sloth_sweep":
				# Rending Sweep: it sinks and twists away, the right arm cocked far back (anticipation, to 0.36),
				# the whole body unwinds hips first and the claws rake round in a wide arc (lands ~0.47), the
				# weight carries it on past (overshoot to 0.62), and it settles back onto all fours
				var crouch := smoothstep(0.0, 0.3, k) * (1.0 - smoothstep(0.38, 0.5, k))
				var wind := smoothstep(0.05, 0.36, k)
				var rake := smoothstep(0.38, 0.5, k)
				var over := smoothstep(0.46, 0.62, k) * (1.0 - smoothstep(0.62, 0.95, k))
				var back := 1.0 - smoothstep(0.66, 1.0, k)
				var sw := (lerpf(1.0, -1.0, rake) - over * 0.35) * wind * back
				p["hips"] += Vector3(0, -0.2 * sw, 0)
				p["spine"] += Vector3(0.1 * crouch, -0.3 * sw, 0.06 * sw)
				p["chest"] += Vector3(-0.1 * rake * back, -0.55 * sw, 0)
				p["neck"] += Vector3(0.1 * crouch, 0.35 * sw, 0)        # the head stays on the target
				p["arm_r"] += Vector3(-1.2 * wind * back - 0.3 * over, 1.0 * sw, 0.95 * wind * back)
				p["forearm_r"] += Vector3(-0.6 * (1.0 - rake) * wind - 0.15 * rake * back, 0, 0)
				p["hand_r"] += Vector3(0.4 * (1.0 - rake) * wind - 0.5 * rake * back, 0, 0)
				p["arm_l"] += Vector3(-0.5 * wind * back, -0.3 * sw, -0.35 * wind * back)
				for leg in ["l", "r"]:
					p["thigh_" + leg] += Vector3(-0.25 * crouch, 0, 0)
					p["shin_" + leg] += Vector3(0.35 * crouch, 0, 0)
				p["tail"] += Vector3(0, 0.5 * sw, 0)
				lift -= 0.14 * crouch
			"sloth_slam":
				# Earthshaker: up to its full height and a casting motion of its element (to ~0.5), then both
				# arms crash down (0.6) with the weight following through, and it hauls itself back up
				var el: String = rig.get_meta("element", "")
				var cast := smoothstep(0.15, 0.4, k) * (1.0 - smoothstep(0.48, 0.56, k))
				var up := smoothstep(0.42, 0.5, k) * (1.0 - smoothstep(0.52, 0.58, k))
				var crash := smoothstep(0.52, 0.6, k) * (1.0 - smoothstep(0.78, 1.0, k))
				var quiver := sin(t * 38.0) * 0.04 * cast
				match el:
					"fire":
						# a great heave of breath: back arched, chest thrown out, arms flung wide, head up
						p["spine"] += Vector3(-0.35 * cast, 0, 0)
						p["chest"] += Vector3(-0.3 * cast + quiver, 0, 0)
						p["head"] += Vector3(-0.5 * cast, 0, 0)
						for s2 in ["l", "r"]:
							var sg := 1.0 if s2 == "l" else -1.0
							p["arm_" + s2] += Vector3(-0.4 * cast, 0, 1.1 * sg * cast)
							p["forearm_" + s2] += Vector3(-0.7 * cast, 0, 0)
					"cold":
						# claws crossed over its chest, hunched and shivering as the cold gathers
						p["spine"] += Vector3(0.2 * cast, 0, 0)
						p["chest"] += Vector3(0.15 * cast, quiver * 2.0, 0)
						p["head"] += Vector3(0.25 * cast, 0, 0)
						for s2 in ["l", "r"]:
							var sg := 1.0 if s2 == "l" else -1.0
							p["arm_" + s2] += Vector3(-1.1 * cast, -0.9 * sg * cast, -0.5 * sg * cast)
							p["forearm_" + s2] += Vector3(-1.3 * cast + quiver, 0, 0)
					_:
						# both arms raised to the sky, head thrown back, crackling, calling the storm down
						p["spine"] += Vector3(-0.25 * cast, 0, 0)
						p["chest"] += Vector3(-0.2 * cast, 0, 0)
						p["head"] += Vector3(-0.6 * cast, quiver, 0)
						for s2 in ["l", "r"]:
							var sg := 1.0 if s2 == "l" else -1.0
							p["arm_" + s2] += Vector3(-2.7 * cast + quiver, 0, 0.35 * sg * cast)
							p["forearm_" + s2] += Vector3(-0.3 * cast, 0, 0)
				# the last heave up, then the crash and its follow-through
				for s2 in ["l", "r"]:
					var sg := 1.0 if s2 == "l" else -1.0
					p["arm_" + s2] += Vector3(-2.4 * up - 0.6 * crash, 0, -0.15 * sg * up)
					p["forearm_" + s2] += Vector3(-0.4 * up + 0.2 * crash, 0, 0)
				p["spine"] += Vector3(-0.2 * up + 0.35 * crash, 0, 0)
				p["chest"] += Vector3(-0.15 * up + 0.2 * crash, 0, 0)
				p["head"] += Vector3(-0.2 * up + 0.3 * crash, 0, 0)
				p["tail"] += Vector3(-0.3 * crash, 0, 0)
				lift += 0.12 * (cast + up) * 0.6 - 0.16 * crash
			"sloth_pounce":
				# Hollow Pounce: it gathers low, rump up and tail lifting, head down on the target (to 0.3),
				# springs off the hind legs with the arms reaching out (0.3-0.6), lands claws first (0.62),
				# its weight driving it down, and pushes back up
				var coil := smoothstep(0.0, 0.26, k) * (1.0 - smoothstep(0.28, 0.36, k))
				var fly := smoothstep(0.28, 0.4, k) * (1.0 - smoothstep(0.56, 0.66, k))
				var land := smoothstep(0.6, 0.66, k) * (1.0 - smoothstep(0.75, 1.0, k))
				var wag := sin(t * 14.0) * 0.06 * coil
				lift += -0.36 * coil + sin(clampf((k - 0.28) / 0.34, 0.0, 1.0) * PI) * 1.2 - 0.22 * land
				p["hips"] += Vector3(-0.15 * coil, wag, 0)
				p["spine"] += Vector3(0.2 * coil - 0.3 * fly + 0.15 * land, 0, 0)
				p["neck"] += Vector3(0.25 * coil - 0.35 * fly + 0.25 * land, 0, 0)
				p["head"] += Vector3(-0.2 * coil, 0, 0)
				for s2 in ["l", "r"]:
					p["arm_" + s2] += Vector3(0.35 * coil - 1.1 * fly + 0.25 * land, 0, 0)
					p["forearm_" + s2] += Vector3(-0.25 * fly + 0.2 * land, 0, 0)
					p["hand_" + s2] += Vector3(-0.4 * fly, 0, 0)
					p["thigh_" + s2] += Vector3(-0.6 * coil + 1.0 * fly, 0, 0)
					p["shin_" + s2] += Vector3(0.7 * coil - 0.25 * fly + 0.3 * land, 0, 0)
				p["tail"] += Vector3(-0.5 * coil - 0.3 * fly, wag * 3.0, 0)
	# a blow rocks it back a little
	p["chest"] += Vector3(-hit * 0.15, 0, 0)
	p["neck"] += Vector3(-hit * 0.2, 0, 0)
	body.position.y = lift
	for bn in p:
		_turn(sk, info, bn, p[bn])

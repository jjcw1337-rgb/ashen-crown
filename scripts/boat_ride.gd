class_name BoatRide
extends Node3D
## A boat in the water you can sail (Data.BOATS, model Boat.model): moored alongside a pier or a jetty
## (clickable: an Inter "boat"), or sailing with the hero aboard at the tiller.
##
## Sailing (Game feeds `drive` every frame from the keys and mouse):
## - W builds speed toward the boat's cruise and holds it when let go; S eases off, then backs her
##   slowly; Space heaves to (stops); A / D steer; holding the left mouse button on the water sails her
##   toward that point at full speed. She turns faster with way on (and slowly even at rest, so she
##   can always come about).
## - Rides the sea's real waves (Ocean.surface_y / surface_normal): bobs, pitches over the swell, rolls,
##   heels into turns, lifts her bow as she gathers speed.
## - Can't go aground: probes at the bow, the bow quarters and the stern stop her where the water gets
##   shallower than her draft, at sea rocks (World meta "sea_rocks") and at piers (World.decks), and she
##   only ever moves to deeper water from where she is, so she can never be stuck for good. The open
##   sea past the zone's edge pushes her back.
## - Leaves a wake of foam from her stern and throws spray at the bow, both with her speed.
## - Docking: at a dock (the coast's pier or any island's jetty) and slow, `dock_near` names it; Game
##   lands the hero there (Game.land_boat): on the coast she moors at the pier, at an island the
##   island's zone loads with her moored at its jetty.

var DRAFT := 1.0                   # metres of water she needs under her (Data.BOATS "need", else from her draft)
var DECK := Vector3(0.15, Boat.SHEER - 0.22, 2.25)     # where the hero stands, by the tiller (Data.BOATS "deck")
var kl := 1.0                      # her length and beam against the Gull's: the probes, wake and spray scale by them
var kb := 1.0
const DOCK_REACH := 10.0           # how close to a dock's mooring she must be to land
const DOCK_SPEED := 3.5            # and how slow
const ASTERN := -2.0               # her best speed going backward

var id := "gull"
var spec: Dictionary
var game
var model: Node3D
var inter: Inter
var sailing := false
var yaw := 0.0                     # heading: she moves along (-sin yaw, -cos yaw), like a node's -z
var speed := 0.0
var target := 0.0                  # the speed she holds (cruise control)
var rudder := 0.0
var drive := {"throttle": 0, "steer": 0.0, "stop": false, "point": null}
var docks: Array = []              # [{name, pos: Vector2, yaw, kind: "pier"|"isle", id}]
var _roll := 0.0
var _pitch := 0.0
var _y := 0.0
var _wake: GPUParticles3D
var _spray: GPUParticles3D
var _bump_t := 0.0

func setup(g, boat_id: String) -> BoatRide:
	game = g
	id = boat_id
	spec = Data.BOATS.get(id, Data.BOATS["gull"])
	var dm := Boat.dims(id)
	kl = float(dm["length"]) / Boat.LENGTH
	kb = float(dm["beam"]) / Boat.BEAM
	DRAFT = float(spec.get("need", maxf(1.0, float(dm["draft"]) * 1.8)))
	DECK = spec.get("deck", Vector3(0.15, float(dm["sheer"]) - 0.22, 2.25 * kl))
	name = "boat_ride"
	model = Boat.model(id)
	add_child(model)
	_wake = _make_wake()
	_spray = _make_spray()
	return self

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))

func side() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))

## Moors her at p heading `y` (alongside a pier or jetty), clickable to board.
func moor(p: Vector3, y: float) -> void:
	sailing = false
	speed = 0.0
	target = 0.0
	yaw = y
	global_position = Vector3(p.x, 0.0, p.z)
	var spot := global_position
	# the moorings are spaced for the Gull: a longer boat eases out along her heading until she can swing
	# right round there without her hull touching the pier or jetty (her probes, scaled to her size)
	if kl > 1.01:
		for i in 60:
			if _swing_clear(global_position):
				break
			global_position += forward() * 0.5
	p = global_position
	var out := spot.distance_to(p)     # how far she lies out from the mooring: the hero still reaches her from the deck
	_float(0.0)
	if inter == null or not is_instance_valid(inter):
		inter = game.world._inter("boat", str(spec["name"]), Vector3(p.x, 0, p.z), 4.2 * kl, null, {"boat": id})
		inter.set_meta("pick", 3.6 * kl)
		inter.set_meta("pick_y", 1.2)
	inter.global_position = Vector3(p.x, 0.0, p.z)
	inter.radius = 4.2 * kl + out

## Whether she could turn through every heading at p and stay clear (clearance >= 0) the whole way.
func _swing_clear(p: Vector3) -> bool:
	var y0 := yaw
	var ok := true
	for k in 12:
		yaw = y0 + TAU * k / 12.0
		if _clearance(p) < 0.0:
			ok = false
			break
	yaw = y0
	return ok

# ---------------------------------------------------------------- a partner's boat (co-op)
## A partner sailing: his boat as his game sends it (Net._boat_packet, in his state packet), drawn under his
## puppet and gliding to where he says she is; she rides this game's own waves, leaves her wake and creaks,
## but deals with nothing (no docking, no clicking, no sea loop: that's the sailor's own).
var puppet := false
var net_to := Vector3.ZERO
var net_yaw := 0.0

static func puppet_update(h: Hero, delta: float) -> void:
	var w: World = h.game.world if h.game else null
	if h.net_boat_st == null or w == null or not w.sea or h.dead:
		if h.net_boat and is_instance_valid(h.net_boat):
			h.net_boat.queue_free()
		h.net_boat = null
		return
	var st: Vector4 = h.net_boat_st
	var b := h.net_boat
	if b != null and is_instance_valid(b) and b.id != h.net_boat_id:
		b.queue_free()            # he sails another boat now (bought a better one)
		b = null
	if b == null or not is_instance_valid(b) or b.get_parent() != w:
		b = BoatRide.new()
		w.add_child(b)
		b.setup(h.game, h.net_boat_id)
		b.name = "partner_boat"
		b.puppet = true
		b.sailing = true
		b.global_position = Vector3(st.x, 0.0, st.y)
		b.yaw = st.z
		b._float(0.0)
		h.net_boat = b
	b.net_to = Vector3(st.x, 0.0, st.y)
	b.net_yaw = st.z
	b.speed = st.w
	b._place_hero(h)

func _follow_net(delta: float) -> void:
	var p := Vector3(global_position.x, 0.0, global_position.z)
	if p.distance_to(net_to) > 12.0:
		p = net_to
	else:
		p = p.lerp(net_to, clampf(delta * 8.0, 0.0, 1.0))
	global_position = Vector3(p.x, global_position.y, p.z)
	yaw = lerp_angle(yaw, net_yaw, clampf(delta * 8.0, 0.0, 1.0))

## The hero steps aboard and takes the tiller.
func board(hero: Hero) -> void:
	sailing = true
	speed = 0.0
	target = 0.0
	hero.aboard = true
	hero.target = null
	hero.path = PackedVector3Array()
	hero.moving = false
	if inter and is_instance_valid(inter):
		game.world.interactables.erase(inter)
		inter.queue_free()
		inter = null
	_place_hero(hero)

func leave(hero: Hero) -> void:
	sailing = false
	hero.aboard = false

## The nearest dock she can land at now (within reach and slow enough), or {}.
func dock_near() -> Dictionary:
	if not sailing or absf(speed) > DOCK_SPEED:
		return {}
	var p := Vector2(global_position.x, global_position.z)
	var best := {}
	var bd := DOCK_REACH * kl          # a longer boat lands from further out, before her hull reaches the jetty
	for d in docks:
		var dd := p.distance_to(d["pos"])
		if dd < bd:
			bd = dd
			best = d
	return best

func _process(delta: float) -> void:
	if game == null or game.world == null:
		return
	if puppet:
		_follow_net(delta)
	elif sailing:
		_sail(delta)
	_float(delta)
	_effects(delta)
	if sailing and game.hero and not puppet:
		_place_hero(game.hero)

func _place_hero(hero: Hero) -> void:
	hero.global_position = global_transform * DECK
	hero.rig.rotation.y = yaw + PI * 0.06

# ---------------------------------------------------------------- sailing
func _sail(delta: float) -> void:
	var cruise := float(spec["speed"])
	var accel := float(spec["accel"])
	var thr: int = drive["throttle"]
	var steer: float = drive["steer"]
	var pt: Variant = drive["point"]
	if pt != null:
		# sail toward the point held under the mouse, at full speed
		var to: Vector3 = (pt as Vector3) - global_position
		to.y = 0
		if to.length() > 3.0:
			var want := atan2(-to.x, -to.z)
			steer = clampf(-wrapf(want - yaw, -PI, PI) * 2.2, -1.0, 1.0)
			target = cruise
	if thr > 0:
		target = move_toward(target, cruise, accel * delta * 1.4)
	elif thr < 0:
		target = move_toward(target, ASTERN, accel * delta * 1.1)
	if drive["stop"]:
		target = 0.0
	var rate := accel if target > speed else accel * (1.6 if target == 0.0 else 1.2)
	speed = move_toward(speed, target, rate * delta)
	rudder = move_toward(rudder, steer, delta * 3.0)
	# she turns with way on; a little even at rest (the hero sculls her round)
	var way := clampf(absf(speed) / 3.0, 0.0, 1.0)
	var turn := float(spec["turn"]) * (0.3 + 0.7 * way) * signf(speed if absf(speed) > 0.3 else 1.0)
	yaw = wrapf(yaw - rudder * turn * delta, -PI, PI)
	_move(forward() * speed * delta)

## Moves her by d unless that takes her onto the shallows, a rock or a pier; from wherever she is she
## may always move to deeper water. The zone's open-sea edge turns her back.
func _move(d: Vector3) -> void:
	var p := global_position
	var now := _clearance(p)
	var np := p + d
	var then := _clearance(np)
	if then < DRAFT and then < now - 0.001:
		# glancing: slide along the shore (try the course turned a little either way, slower)
		var slid := false
		var best_c := -INF
		var best_a := 0.0
		for a in [0.35, -0.35, 0.75, -0.75, 1.2, -1.2]:
			var dd := d.rotated(Vector3.UP, a) * (1.0 - absf(a) * 0.4)
			var c := _clearance(p + dd) - absf(a) * 0.05
			if (c >= DRAFT or c > now) and c > best_c:
				best_c = c
				best_a = a
				np = p + dd
				slid = true
		if slid:
			yaw = wrapf(yaw + signf(best_a) * 0.6 * get_process_delta_time() * (1.0 if speed >= 0.0 else -1.0), -PI, PI)
			speed *= 0.985
		if not slid:
			speed *= -0.25
			target = minf(target, 0.0) if speed < 0.0 else 0.0
			_bump_t -= get_process_delta_time()
			if _bump_t <= 0.0:
				_bump_t = 2.5
				game.ui.message("Too shallow: turn her away", Color(0.75, 0.88, 1.0))
			return
	var sr: Rect2 = game.world.get_meta("sea_rect") if game.world.has_meta("sea_rect") else Rect2(-1e5, -1e5, 2e5, 2e5)
	var inner := sr.grow(-30.0)
	if not inner.has_point(Vector2(np.x, np.z)):
		var c := inner.get_center()
		var back := Vector3(c.x - np.x, 0, c.y - np.z).normalized()
		np = p + d.slide(Vector3.UP) + back * 0.05
		if not inner.grow(6.0).has_point(Vector2(np.x, np.z)):
			np = p
			speed *= 0.5
			_bump_t -= get_process_delta_time()
			if _bump_t <= 0.0:
				_bump_t = 3.0
				game.ui.message("The open sea beyond is too rough. Turn back.", Color(0.75, 0.88, 1.0))
	global_position = Vector3(np.x, global_position.y, np.z)

## The least water under her probes (bow, bow quarters, stern) at p: depth, minus rocks and piers.
func _clearance(p: Vector3) -> float:
	var oc: Ocean = game.world.get_node_or_null("Ocean")
	if oc == null:
		return 99.0
	var f := forward() * kl
	var s := side() * kb
	var least := 99.0
	for off in [Vector3.ZERO, f * 3.9, f * 2.4 + s * 1.05, f * 2.4 - s * 1.05, -f * 3.6, s * 1.15, -s * 1.15, -f * 2.2 + s * 1.0, -f * 2.2 - s * 1.0]:
		var q: Vector3 = p + off
		var dep := oc.depth_at(q.x, q.z)
		# inside a rock or a pier counts as less water the deeper in, so backing out always helps
		for r in (game.world.get_meta("sea_rocks") if game.world.has_meta("sea_rocks") else []):
			var pen: float = float(r[1]) + 0.3 - Vector2(q.x, q.z).distance_to(r[0])
			if pen > 0.0:
				dep = minf(dep, -pen)
		for dk in game.world.decks:
			var lp := (Vector2(q.x, q.z) - (dk[0] as Vector2)).rotated(float(dk[2]))
			var half: Vector2 = dk[1]
			var pen2 := minf(half.x + 0.3 - absf(lp.x), half.y + 0.3 - absf(lp.y))
			if pen2 > 0.0:
				dep = minf(dep, -pen2)
		least = minf(least, dep)
	return least

# ---------------------------------------------------------------- floating
## Rides the waves: height from the sea under her bow and stern, pitch over the swell, roll from her
## sides and a heel into the turn, the bow lifting as she gathers way.
func _float(delta: float) -> void:
	var oc: Ocean = game.world.get_node_or_null("Ocean") if game and game.world else null
	var f := forward()
	var s := side()
	var p := global_position
	var yb := 0.0
	var ys := 0.0
	var yp := 0.0
	var yst := 0.0
	if oc:
		yb = oc.surface_y(p.x + f.x * 2.8, p.z + f.z * 2.8)
		ys = oc.surface_y(p.x - f.x * 2.8, p.z - f.z * 2.8)
		yp = oc.surface_y(p.x - s.x * 1.1, p.z - s.z * 1.1)
		yst = oc.surface_y(p.x + s.x * 1.1, p.z + s.z * 1.1)
	var k := clampf(delta * 5.0, 0.0, 1.0) if delta > 0.0 else 1.0
	_y = lerpf(_y, (yb + ys + yp + yst) * 0.25 - 0.05, k)
	var lift := clampf(speed / 8.0, -0.3, 1.0) * 0.035
	_pitch = lerp_angle(_pitch, atan2(yb - ys, 5.6) + lift, k)
	var heel := -rudder * clampf(speed / 8.0, 0.0, 1.0) * 0.09
	_roll = lerp_angle(_roll, atan2(yst - yp, 2.2) * 0.7 + heel, k)
	global_position.y = _y
	basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, _roll)

# ---------------------------------------------------------------- wake and spray
func _effects(delta: float) -> void:
	_sounds(delta)
	var v := absf(speed)
	_wake.emitting = v > 0.6
	_wake.amount_ratio = clampf(v / 8.0, 0.15, 1.0)
	_wake.global_position = global_position - forward() * 3.7 * kl + Vector3(0, -global_position.y + 0.12, 0)
	_wake.global_rotation = Vector3(0, yaw, 0)
	_spray.emitting = speed > 3.0
	_spray.amount_ratio = clampf((speed - 3.0) / 5.0, 0.2, 1.0)
	_spray.global_position = global_position + forward() * 3.6 * kl + Vector3(0, 0.3, 0)
	_spray.global_rotation = Vector3(0, yaw, 0)

## Under sail: the open sea round her (the `sea` bed, louder with speed), her planks creaking as she works
## in the swell (more as she pitches and rolls) and the bow slapping into the waves at speed. The loop is
## the Sfx autoload's child, so it's freed with her (_exit_tree).
var _sea_loop: AudioStreamPlayer
var _creak_t := 1.5
var _slap_t := 2.0
func _sounds(dt: float) -> void:
	if not sailing:
		if _sea_loop:
			_sea_loop.volume_db -= dt * 30.0
			if _sea_loop.volume_db < -60.0:
				_end_loop()
		return
	if _sea_loop == null and not puppet:
		_sea_loop = Sfx.start_loop("sea", -40.0)
	if _sea_loop:
		var want := -16.0 + clampf(absf(speed) / 8.0, 0.0, 1.0) * 7.0
		_sea_loop.volume_db = move_toward(_sea_loop.volume_db, want, dt * 20.0)
	var work := absf(_pitch) * 9.0 + absf(_roll) * 7.0 + absf(speed) / 8.0
	_creak_t -= dt * (0.5 + work)
	if _creak_t <= 0.0:
		_creak_t = randf_range(2.0, 5.0)
		Sfx.play_at("hull_creak", global_position + Vector3(0, 0.6, 0), -12.0 + clampf(work * 3.0, 0.0, 6.0), randf_range(0.88, 1.12))
	if speed > 2.0:
		_slap_t -= dt * (speed / 8.0)
		if _slap_t <= 0.0:
			_slap_t = randf_range(1.4, 3.6)
			Sfx.play_at("hull_slap", global_position + forward() * 3.0, -10.0 + (speed - 2.0) * 0.8, randf_range(0.9, 1.1))

func _end_loop() -> void:
	if _sea_loop and is_instance_valid(_sea_loop):
		_sea_loop.queue_free()
	_sea_loop = null

func _exit_tree() -> void:
	_end_loop()

static func _foam_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Mats.soft_dot()
	m.disable_receive_shadows = true
	return m

## Foam spreading behind her stern: flat patches on the water that widen and fade.
func _make_wake() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "wake"
	p.amount = 160
	p.lifetime = 5.0
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.0, 0.3)
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.6))
	sc.add_point(Vector2(1.0, 3.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.75))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.15, Color(0.95, 0.98, 1.0, 0.6))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.4)
	q.orientation = PlaneMesh.FACE_Y
	q.material = _foam_mat()
	p.draw_pass_1 = q
	p.custom_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 4, 60))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.top_level = true
	return p

## Spray thrown up from the bow when she has way on.
func _make_spray() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "spray"
	p.amount = 90
	p.lifetime = 0.9
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.6, 0.1, 0.2)
	pm.direction = Vector3(0, 0.8, -0.4)
	pm.spread = 50.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.25
	pm.scale_max = 0.6
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.8))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := _foam_mat()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	p.custom_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 8, 20))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.top_level = true
	return p

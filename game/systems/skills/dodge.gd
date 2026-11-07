class_name Dodge
## The dodge roll on Space, Path of Exile 2 style (every class): he rolls the way the movement keys point, or toward
## the pointer when no key is held. It cancels what he's doing (a swing not yet landed, a channel, the guard), and
## for the first part of it blows go past him (`IFRAME`, monsters, missiles and other players alike). It costs a
## little stamina (none left, no roll); holding Space after the roll runs on into a sprint (Game._process).
## Seen by partners: the "roll" fx event (SkillFx.play hands it here); the puppet's position comes from the net, its
## tumble from `pose`.

const DIST := 3.8          # metres covered
const DUR := 0.5           # seconds of rolling
const IFRAME := 0.32       # seconds from the start during which nothing hits him
const RECOVER := 0.12      # after the roll before the next one
const STAMINA := 12.0
const PIVOT := 0.75        # height the body tumbles round (m)

static func can_roll(h: Hero) -> bool:
	return not h.dead and h.roll_t < 0.0 and h.roll_cd <= 0.0 and h.charge_t < 0.0 and h.daze_t <= 0.0 \
		and not ClassSkills.rooted(h) and not SkillSpec.uncancellable(h) and (h.stamina >= h.roll_cost() or h.game.test_stamina or h.free_roll())

## Starts a roll along dir (flat). False if he can't roll now.
static func start(h: Hero, dir: Vector3) -> bool:
	if not can_roll(h):
		if not h.dead and h.stamina < h.roll_cost() and not h.game.test_stamina:
			h.game.ui.message("Out of stamina", Color(1.0, 0.8, 0.3))
		return false
	dir.y = 0
	if dir.length() < 0.05:
		dir = h.facing()
	dir = dir.normalized()
	h.atk_t = -1.0            # a swing not yet landed is dropped
	h.atk_skill = ""
	h.end_channel()
	h.target = null
	h.moving = false
	h.path = PackedVector3Array()
	h.blocking = false
	h.roll_t = 0.0
	h.roll_dir = dir
	if h.free_roll():
		h.free_roll_t = float(h.pvp_roll_s)      # an item's free roll (the Battlegrounds): no stamina, then it recharges
	elif not h.game.test_stamina:
		h.stamina -= h.roll_cost()
		h.stamina_rest = 0.0
	if int(h.stats.get("dash", 0)) > 0:
		h.dash_t = 2.0          # a unique's burst of speed after the roll
	h.rig.rotation.y = atan2(-dir.x, -dir.z)
	h.fx("roll", "start", {"d": dir})
	return true

## The step this frame (a velocity), fast at first and easing out; ends the roll.
static func step(h: Hero, delta: float) -> Vector3:
	var s0 := h.roll_t / DUR
	h.roll_t += delta
	var s1 := minf(h.roll_t / DUR, 1.0)
	var d := DIST * (_ease(s1) - _ease(s0))
	if h.roll_t >= DUR:
		h.roll_t = -1.0
		h.roll_cd = RECOVER
	return h.roll_dir * (d / maxf(delta, 0.0001))

static func _ease(s: float) -> float:
	return 1.0 - pow(1.0 - s, 2.2)

static func dodging(h: Hero) -> bool:
	return h.roll_t >= 0.0 and h.roll_t < IFRAME

## A blow that went past him: "Dodged" over him on every screen (an fx event, so the one who swung sees why it
## missed; jj: "a lot of missed attacks in PvP, I never saw the roll").
static func dodged(h: Hero) -> void:
	var now := Time.get_ticks_msec()
	if now - int(h.get_meta("dodged_at", 0)) < 300:
		return                    # (a pack's blows in one roll: one "Dodged", one event)
	h.set_meta("dodged_at", now)
	h.fx("roll", "dodged", {})

## The event's effect (on the roller and on his puppet): dust where he set off, the sound, the tumble; "Dodged".
static func fx(h: Hero, ev: Dictionary) -> void:
	if str(ev.get("e", "")) == "dodged":
		Fx.number(h.game.world.fx_root, h.global_position + Vector3(0, 2.2, 0), "Dodged", Color(0.85, 0.9, 1.0))
		SkillFx.snd(h, "swing_light", -8.0, 1.4)
		return
	if str(ev.get("e", "")) != "start":
		return
	if h.puppet:
		h.roll_t = 0.0
		var d: Vector3 = ev.get("d", h.facing())
		h.roll_dir = d
	var root: Node3D = h.game.world.fx_root
	# dust kicked up off the ground: the noise-eroded wisps of the shared skills' dust, not soft dots
	ElementalFx._dust(root, h.global_position + Vector3(0, 0.15, 0), Color(0.55, 0.5, 0.42), 0.8, 0.42, {"amount": 4,
		"life": 0.6, "explosive": 0.9, "shape": "sphere", "r": 0.2, "dir": Vector3.UP, "spread": 70.0, "vel": [0.3, 0.9],
		"damping": [1.5, 2.5], "scale": [0.7, 1.1], "grow": [0.5, 1.4]})
	SkillFx.snd(h, "swing_light", -4.0, 0.7)

## After the pose: the body tumbles forward once round its middle (the Wraith, who has no legs, swoops low instead;
## a dragon lunges low).
## The puppet's roll runs on its own clock here.
static func pose(h: Hero, delta: float) -> void:
	if h.puppet and h.roll_t >= 0.0:
		h.roll_t += delta
		if h.roll_t >= DUR:
			h.roll_t = -1.0
	if h.roll_t < 0.0:
		if h.has_meta("rolled"):
			h.remove_meta("rolled")
			if h.has_meta("fly_dust"):
				h.remove_meta("fly_dust")
			if h.rig.has_meta("fly"):
				h.rig.remove_meta("fly")
			if not h.is_wraith():
				h.rig.rotation.x = 0.0
				h.rig.position = Vector3.ZERO
		return
	h.set_meta("rolled", true)
	var s := clampf(h.roll_t / DUR, 0.0, 1.0)
	var yaw := atan2(-h.roll_dir.x, -h.roll_dir.z)
	h.rig.rotation.y = yaw
	if h.is_wraith():
		h.rig.rotation.x = -0.5 * sin(PI * s)
		h.rig.position.y = 0.2 - 0.25 * sin(PI * s)
		return
	if h.is_dragon() and str(h.rig.get_meta("dragon", "")) == "wyvern":
		# the Storm Wyvern flies it (jj): a crouch, a leap up on its beating wings, a glide over and a landing that
		# drops into its legs; Dragon.pose beats the wings and tucks the legs by the rig's "fly" meta
		var up := sin(PI * smoothstep(0.08, 0.92, s))
		var crouch := smoothstep(0.0, 0.08, s) * (1.0 - smoothstep(0.08, 0.16, s)) + smoothstep(0.88, 0.96, s) * (1.0 - smoothstep(0.96, 1.0, s))
		h.rig.rotation.x = 0.18 * sin(PI * s) - 0.1 * up * (1.0 - s)
		h.rig.position = Vector3(0, FLY_H * up - 0.22 * crouch, 0)
		h.rig.set_meta("fly", s)
		if not h.has_meta("fly_dust") and s > 0.05:
			h.set_meta("fly_dust", 1)
			_wing_gust(h, 1.0)
		if s > 0.92 and int(h.get_meta("fly_dust", 0)) == 1:
			h.set_meta("fly_dust", 2)
			_wing_gust(h, 1.4)
		return
	if h.is_dragon():
		# a dragon is far too long to tumble: it lunges low, nose down, and rises out of it
		h.rig.rotation.x = -0.12 * sin(PI * s)
		h.rig.position = Vector3(0, -0.15 * sin(PI * s), 0)
		return
	var a := -TAU * smoothstep(0.05, 0.9, s)
	var p := Vector3(0, PIVOT, 0)
	var off := p - Basis(Vector3.RIGHT, a) * p
	off.y -= 0.12 * sin(PI * s)       # tucked low
	h.rig.rotation.x = a
	h.rig.position = Basis(Vector3.UP, yaw) * off

const FLY_H := 2.3          # metres the Storm Wyvern rises on its flight (in place of the roll)

## The wyvern's wings throwing the dust up (taking off, k 1; landing, k 1.4): a ring of dust and torn grass blown out,
## the grass flattened, a thump.
static func _wing_gust(h: Hero, k: float) -> void:
	var root: Node3D = h.game.world.fx_root
	var g := h.global_position
	ElementalFx._dust(root, g + Vector3(0, 0.15, 0), Color(0.5, 0.45, 0.38), 1.1 * k, 0.45, {"amount": int(6 * k),
		"life": 0.9, "explosive": 1.0, "shape": "ring", "r": 0.8, "r_in": 0.4, "dir": Vector3.UP, "spread": 15.0,
		"vel": [0.2, 0.5], "radial": [3.0 * k, 5.0 * k], "damping": [2.5, 3.5], "scale": [0.8, 1.2], "grow": [0.6, 1.8]})
	GrassField.impulse(g, 3.5 * k, 0.8, 0.45)
	SkillFx.snd(h, "wyvern_flap", -2.0 if k > 1.2 else -4.0, 0.9 if k > 1.2 else 1.0)
	if k > 1.2:
		SkillFx.snd(h, "wyvern_step", -1.0, 0.8)
		SkillFx.shake(h, 0.12)

## Death (or anything else) mid-roll: the body is set straight.
static func cancel(h: Hero) -> void:
	h.roll_t = -1.0
	if h.has_meta("rolled"):
		h.remove_meta("rolled")
		if not h.is_wraith():
			h.rig.rotation.x = 0.0
			h.rig.position = Vector3.ZERO

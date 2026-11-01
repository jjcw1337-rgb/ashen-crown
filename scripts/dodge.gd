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
		and not ClassSkills.rooted(h) and not SkillSpec.uncancellable(h) and (h.stamina >= STAMINA or h.game.test_stamina)

## Starts a roll along dir (flat). False if he can't roll now.
static func start(h: Hero, dir: Vector3) -> bool:
	if not can_roll(h):
		if not h.dead and h.stamina < STAMINA and not h.game.test_stamina:
			h.game.ui.message("Out of stamina", Color(1.0, 0.8, 0.3))
		return false
	dir.y = 0
	if dir.length() < 0.05:
		dir = h.facing()
	dir = dir.normalized()
	h.atk_t = -1.0            # a swing not yet landed is dropped
	h.atk_skill = ""
	h.end_drain()
	h.stop_chop()
	h.target = null
	h.moving = false
	h.path = PackedVector3Array()
	h.blocking = false
	h.roll_t = 0.0
	h.roll_dir = dir
	if not h.game.test_stamina:
		h.stamina -= STAMINA
		h.stamina_rest = 0.0
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

## A blow that went past him.
static func dodged(h: Hero) -> void:
	Fx.number(h.game.world.fx_root, h.global_position + Vector3(0, 2.2, 0), "Dodged", Color(0.85, 0.9, 1.0))

## The event's effect (on the roller and on his puppet): dust where he set off, the sound, the tumble.
static func fx(h: Hero, ev: Dictionary) -> void:
	if str(ev.get("e", "")) != "start":
		return
	if h.puppet:
		h.roll_t = 0.0
		var d: Vector3 = ev.get("d", h.facing())
		h.roll_dir = d
	var root: Node3D = h.game.world.fx_root
	Fx.burst(root, h.global_position + Vector3(0, 0.15, 0), Color(0.55, 0.5, 0.42, 0.55), 10, 1.6, 0.12, 0.45, false, 0.6)
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

## Death (or anything else) mid-roll: the body is set straight.
static func cancel(h: Hero) -> void:
	h.roll_t = -1.0
	if h.has_meta("rolled"):
		h.remove_meta("rolled")
		if not h.is_wraith():
			h.rig.rotation.x = 0.0
			h.rig.position = Vector3.ZERO

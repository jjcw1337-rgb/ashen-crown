class_name ShadowStep
extends WraithSkill
## Shadowstep ("step", R): the dodge's spin. A third of the way round he comes apart into mist (an afterimage stays)
## and re-forms up to its range away (walls stop him short: the landing is walked with world.move); the spin's end
## is a claw strike round where he lands, stunning. For a moment after he is still mist: blows pass through him
## (Hero.veil_t; Lingering Mist: longer, and the strike stuns longer). The shade he left collapses a moment later and
## hurts. The blink and the mist are his own game's; the strike and the shade are made where his hits are decided.
## Its look: ShadowStepFx. Codex "k": dmg and spirit (the strike's: % of the weapon's blow and of the spirit-light),
## radius (the strike's), stun_s, veil_s (seconds he stays mist), shade and shade_spirit (the shade's), shade_r
## (its reach), shade_s (seconds before it collapses).

const BLINK_AT := 0.35      # a third of the way round the spin he goes

var step_from := Vector3.ZERO
var step_to := Vector3.ZERO
var blinking := false       # cast, not yet gone (his own game)
var shades: Array = []      # the rules': the shades left behind, collapsing (DelayedArea)

func cast(aim: Vector3) -> void:
	var h := hero
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	var dist := minf(to.length(), reach_m(9.0))
	var dir := to.normalized() if to.length() > 0.5 else h.aim_dir()
	if dist < 0.5:
		dist = 4.0
	# walk the way there in steps that slide round anything solid, so the landing is a real spot
	var p := h.global_position
	var travelled := 0.0
	while travelled < dist:
		var np: Vector3 = h.game.world.move(p, dir * minf(0.4, dist - travelled), h.radius)
		var moved := np - p
		moved.y = 0
		if moved.length() < 0.12:
			break
		p = np
		travelled += moved.length()
	p.y = h.game.world.height_at(p.x, p.z)
	step_from = h.global_position
	step_to = p
	blinking = true
	start("wstep")

## The blink a third of the way into the spin (his own game); the shades' collapse wherever they were made.
func tick(delta: float) -> void:
	_collapse(delta)
	var h := hero
	if not blinking:
		return
	if not playing():
		blinking = false
		return
	if h.atk_t / h.atk_dur >= BLINK_AT:
		blinking = false
		_blink()

## An afterimage stays where he was, he goes out in mist and comes back in it at the landing, mist for a moment.
func _blink() -> void:
	var h := hero
	h.fx(id, "blink", {"p": step_from, "q": step_to})
	h.global_position = step_to
	h.target = null
	h.path = PackedVector3Array()
	h.moving = false
	h.veil_t = maxf(h.veil_t, val("veil_s", 0.6) + h.talent("veil"))
	# the shade left behind caves in a moment later (the "blink" event collapses it at the same time)
	make("shade", {"p": step_from})

## The spin's end: the claws tear round where he landed.
func impact() -> void:
	var h := hero
	var near: bool = not h.game.enemies_near(h.global_position, val("radius", 2.9)).is_empty()
	h.fx(id, "strike", {"y": h.rig.global_rotation.y, "x": near})
	make("strike", {"p": h.global_position})

## Server: the shade where he was, the strike where he landed: both within a step of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return (kind == "shade" or kind == "strike") and near_him(d.get("p"), reach_m(9.0) + 4.0)

func made(kind: String, d: Dictionary) -> void:
	var h := hero
	var at: Vector3 = d["p"]
	match kind:
		"shade":
			shades.append(DelayedArea.new(at, val("shade_r", 2.6), val("shade_s", 0.45)))
		"strike":
			for e in h.game.enemies_near(at, val("radius", 2.9)):
				if not foe(e):
					continue
				h._hit_enemy(e, val("dmg", 130.0) / 100.0, 1.0, id, spirit(val("spirit", 70.0)))
				if is_instance_valid(e) and not e.dead:
					stun(e, val("stun_s", 0.7) + h.talent("step_stun"))

func _collapse(delta: float) -> void:
	var h := hero
	for s in shades.duplicate():
		if s.tick(delta):
			for e in h.game.enemies_near(s.pos, s.r):
				if foe(e):
					h._hit_enemy(e, val("shade", 80.0) / 100.0, 0.8, id, spirit(val("shade_spirit", 40.0)))
		if s.over():
			shades.erase(s)

## Mid-spin his feet are the blink's.
func rooted() -> bool:
	return playing()

func clear() -> void:
	super()
	blinking = false
	shades.clear()

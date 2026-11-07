class_name SpectralRend
extends WraithSkill
## Spectral Rend ("rend", Q): the claws grow out as he lunges at the foe ahead, and claw2's two strikes rake across
## in front, the right claw then the left, each tearing souls out of what it strikes that fly back and heal him
## (Soul Harvest: more; Harvest Moon: the claws tear all the way round). The lunge is his own game's; each rake is
## seen at once ("rake") and struck where his hits are decided (`make`). Its look: SpectralRendFx. Codex "k": dmg
## and spirit (each rake's: % of the weapon's blow and of the spirit-light), radius and arc (a rake's reach and
## half-angle in degrees), lunge (metres at most), heal (% of his life for each soul).

const SECOND := 0.72        # the second rake lands this far into the clip

var lunge := 0.0            # metres the lunge covers through the wind-up (his own game)
var lunge_a := 0.0          # how far into the clip it had carried him last frame
var second := true          # the second rake has landed (this cast)

func cast(aim: Vector3) -> void:
	var h := hero
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	var most := val("lunge", 3.0)
	# the lunge: up to `most` toward the foe aimed at, stopping a claw's length short of him
	lunge = 0.0
	var target = null
	var fd := reach_m(4.5)
	for e in h.game.enemies_near(aim, 1.5):
		var d: float = e.global_position.distance_to(h.global_position)
		if foe(e) and d < fd:
			fd = d
			target = e
	if target != null:
		lunge = clampf(fd - target.radius - 1.0, 0.0, most)
	elif to.length() > 1.5:
		lunge = minf(to.length() - 1.2, most)
	lunge_a = 0.0
	second = false
	start("rend", true)

## The first rake, the right claw.
func impact() -> void:
	rake(true)

## The lunge through the wind-up, the second rake (his own game).
func tick(_delta: float) -> void:
	var h := hero
	if not playing():
		return
	var a: float = h.atk_t / h.atk_dur
	if lunge > 0.0:
		var f0 := smoothstep(0.05, 0.4, lunge_a)
		var f1 := smoothstep(0.05, 0.4, a)
		lunge_a = a
		var d := (f1 - f0) * lunge
		if d > 0.0:
			h.global_position = h.game.world.move(h.global_position, h.aim_dir() * d, h.radius)
	if a >= SECOND and not second:
		second = true
		rake(false)

## A rake: seen at once on every game, struck where his hits are decided.
func rake(first: bool) -> void:
	var h := hero
	h.fx(id, "rake", {"y": h.rig.global_rotation.y, "l": not first, "x": h.talent("rend_full") > 0.0})
	make("rake", {"p": h.global_position, "d": h.aim_dir(), "l": not first})

## Server: a rake where it has him (a lunge's length off at most), facing a flat way.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "rake" or not near_him(d.get("p"), val("lunge", 3.0) + 3.0):
		return false
	d["d"] = flat(d.get("d"))
	d["l"] = bool(d.get("l", false))
	return true

## The rake's blow on everything in front (all round with Harvest Moon); a soul out of each, healing him as it arrives.
func made(kind: String, d: Dictionary) -> void:
	if kind != "rake":
		return
	var h := hero
	var at: Vector3 = d["p"]
	var fwd: Vector3 = d["d"]
	var first := not bool(d.get("l", false))
	var full := h.talent("rend_full") > 0.0
	var arc := cos(deg_to_rad(val("arc", 75.0)))
	var souls := PackedVector3Array()
	for e in h.game.enemies_near(at, val("radius", 3.3)):
		if not foe(e):
			continue
		var to: Vector3 = e.global_position - at
		to.y = 0
		if full or to.length() < 0.5 or fwd.dot(to.normalized()) > arc:
			h._hit_enemy(e, val("dmg", 90.0) / 100.0, 0.4 if first else 0.7, id, spirit(val("spirit", 20.0)))
			if is_instance_valid(e):
				souls.append(e.global_position + Vector3(0, 1.0 * e.height, 0))
	if souls.is_empty():
		return
	h.fx(id, "souls", {"ps": souls})
	var pct := val("heal", 2.0) + h.talent("rend_heal")
	for i in souls.size():
		heal_later(wisp_time(i), pct)

func clear() -> void:
	super()
	lunge = 0.0
	second = true

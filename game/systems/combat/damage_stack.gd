class_name DamageStack
extends Label3D
## The red damage number over a hero's head (every class, partners too). Hits close together stack
## into one running total: the number counts up smoothly to the new total, punches bigger and redder
## with each hit, sways a little, and once the hits stop (HOLD seconds) it drifts up and fades out.
## The next hit after that starts a fresh total.

const HOLD := 1.1           # seconds after the last hit before the total fades
const FADE := 0.6           # the drift up and fade out
const COUNT_RATE := 14.0    # how fast the shown number catches the total (per second, exponential)
const HEAD := 2.25          # metres above the hero's feet

var total := 0.0            # damage in this stack
var shown := 0.0            # the number on screen, catching up to total
var since := 99.0           # seconds since the last hit
var punch := 0.0            # 1 on a hit, decays: scale and colour pop
var hits := 0

func _init() -> void:
	font_size = 52
	outline_size = 14
	pixel_size = 0.006
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	render_priority = 10
	outline_modulate = Color(0, 0, 0, 0.85)
	modulate = Color(1.0, 0.3, 0.25, 0.0)
	position = Vector3(0, HEAD, 0)
	visible = false

## A hit for dmg: adds to the running total (or starts a new one once the old has faded).
func add(dmg: float) -> void:
	if since > HOLD + FADE:
		total = 0.0
		shown = 0.0
		hits = 0
	total += dmg
	hits += 1
	since = 0.0
	punch = 1.0
	visible = true

func _process(delta: float) -> void:
	if not visible:
		return
	since += delta
	shown = lerpf(shown, total, 1.0 - exp(-delta * COUNT_RATE))
	if total - shown < 0.5:
		shown = total
	text = str(int(round(shown)))
	punch = maxf(0.0, punch - delta * 5.0)
	# bigger stacks read bigger (gently), each hit pops it
	var grow := clampf(1.0 + log(1.0 + total) * 0.06, 1.0, 1.45)
	var s := grow * (1.0 + punch * 0.35)
	scale = Vector3(s, s, s)
	var rise := 0.0
	var a := 1.0
	if since > HOLD:
		var f := clampf((since - HOLD) / FADE, 0.0, 1.0)
		rise = f * f * 0.6
		a = 1.0 - f
		if f >= 1.0:
			visible = false
			return
	position = Vector3(sin(since * 3.0) * 0.03 * a, HEAD + rise + punch * 0.06, 0)
	# a fresh hit flashes it bright, then it settles to the deep red
	modulate = Color(1.0, 0.3 + punch * 0.45, 0.25 + punch * 0.35, a)
	outline_modulate = Color(0, 0, 0, 0.85 * a * a)

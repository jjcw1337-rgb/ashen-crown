class_name GroundZone
extends RefCounted
## A patch of ground that strikes what stands in it at a steady beat (a rain of arrows, a storm): where, how wide,
## how long it beats, when the first beat falls and how often after that, and how many. Plain data, no nodes: the
## rules keep one to deal its beats, and the look keeps its own from the same event to show them in step
## (docs/content/skills.md).

var pos: Vector3
var r: float
var left: float          # seconds it beats for (a beat still falls up to `grace` past it)
var next: float          # seconds to the next beat
var every: float         # seconds between beats
var beats := -1          # beats left (-1: as many as its time allows)
var grace := 0.05
var age := 0.0
var data := {}           # what the skill keeps with it

func _init(at: Vector3, radius: float, secs: float, first: float, gap: float, count := -1) -> void:
	pos = at
	r = radius
	left = secs
	next = first
	every = gap
	beats = count

## One frame: true when a beat falls in it.
func beat(delta: float) -> bool:
	left -= delta
	next -= delta
	age += delta
	if next <= 0.0 and left > -grace and beats != 0:
		next = every
		if beats > 0:
			beats -= 1
		return true
	return false

## Its beating time is up.
func over() -> bool:
	return left <= 0.0

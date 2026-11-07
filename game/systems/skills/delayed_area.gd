class_name DelayedArea
extends RefCounted
## A spot that goes off after a fuse (a sigil, a trap, a mine), once or a few times with a gap between. Plain data,
## no nodes: the rules keep one and act when it goes off; the look shows it from the skill's own events
## (docs/content/skills.md).

var pos: Vector3
var r: float
var fuse: float          # seconds to the next blast
var blasts: int          # blasts left
var again: float         # seconds between blasts
var count := 0           # blasts so far
var data := {}           # what the skill keeps with it

func _init(at: Vector3, radius: float, arm: float, n := 1, gap := 0.8) -> void:
	pos = at
	r = radius
	fuse = arm
	blasts = n
	again = gap

## One frame: true when it goes off in it.
func tick(delta: float) -> bool:
	fuse -= delta
	if fuse > 0.0 or blasts <= 0:
		return false
	count += 1
	blasts -= 1
	fuse = again
	return true

## It has no blasts left.
func over() -> bool:
	return blasts <= 0

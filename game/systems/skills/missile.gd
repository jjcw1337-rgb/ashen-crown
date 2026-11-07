class_name Missile
extends RefCounted
## A skill's projectile in flight: where it is, where it's going, how far it has left and what it has struck. Plain
## data, no nodes: the rules fly one to deal the hits, and the look flies its own copy from the same "loose" event
## with the same `step`, so what is seen and what hits agree (docs/content/skills.md). A monster's thrown or spat
## projectile is `Projectile` (game/systems/combat/projectile.gd), not this.

var pos: Vector3
var dir: Vector3
var speed := 34.0
var left := 18.0
var pierce := false
var height := 1.3          # above the ground it flies over
var reach := 0.35          # how close to a foe's edge counts as a hit
var struck := {}           # every foe it has hit
var wall := false          # it stopped against something solid
var done := false
var data := {}             # what the skill that loosed it keeps with it (its share of the blow, its kind)

func _init(from: Vector3, direction: Vector3) -> void:
	pos = from
	dir = direction

## One frame of flight. Each foe it passes, nearest first along the way, goes to `on_hit` (the rules: the blow; the
## look: the sparks) as long as `alive` says it can still be struck; a piercing one goes on through them, any other
## stops at the first. It is `done` at the end of its range, against a wall, or on that first foe.
func step(game, delta: float, alive: Callable, on_hit: Callable) -> void:
	if done:
		return
	var w = game.world
	var dist := speed * delta
	var p := pos
	var np: Vector3 = w.move(p, dir * dist, 0.05)
	var moved := np - p
	moved.y = 0
	np.y = w.height_at(np.x, np.z) + height
	pos = np
	left -= dist
	wall = moved.length() < dist * 0.4
	var stop := left <= 0.0 or wall
	# the whole swept segment: a long frame may cross several foes
	var near: Array = game.enemies_near((p + np) * 0.5, moved.length() * 0.5 + 1.6)
	near.sort_custom(func(a, b): return (a.global_position - p).dot(moved) < (b.global_position - p).dot(moved))
	for e in near:
		if struck.has(e) or not alive.call(e):
			continue
		var d := _seg_dist(Vector2(e.global_position.x, e.global_position.z), Vector2(p.x, p.z), Vector2(np.x, np.z))
		if d < e.radius + reach:
			struck[e] = true
			on_hit.call(e)
			if not pierce:
				stop = true
				break
	done = stop

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (a + ab * t).distance_to(p)

class_name BigTopBounce
extends BellyFlop
## Big Top Bounce ("bounce"): he slams down a trampoline and bounces to the cursor in an arc (his feet are the
## leap's), landing in a belly-flop that launches the foes round him (BellyFlop). Its look: BigTopBounceFx (the
## trampoline, the shadow and whistle where he'll land, the arc, the flop).

## The arc carries him from this share of the move to this one (its "bounce" clip: up off the trampoline, down on
## its impact frame).
const ARC_FROM := 0.15
const ARC_TO := 0.78

## Mid-bounce his feet are the leap's.
func rooted() -> bool:
	return hero.atk_skill == id and hero.atk_t >= 0.0

## His own game: the arc to where he lands (the impact frame puts him down).
func update(_delta: float) -> void:
	var h := hero
	if leap.is_empty() or h.puppet or h.atk_skill != id or h.atk_t < 0.0:
		return
	var a := clampf((h.atk_t / maxf(h.atk_dur, 0.01) - ARC_FROM) / (ARC_TO - ARC_FROM), 0.0, 1.0)
	var p: Vector3 = (leap["from"] as Vector3).lerp(leap["to"], a)
	h.global_position = Vector3(p.x, h.global_position.y, p.z)

func landed() -> void:
	hero.game.add_shake(0.35)

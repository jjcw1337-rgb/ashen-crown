class_name DrumstickSmack
extends Skill
## Drumstick Smack ("attack"): the blows of his roast drumstick. The swing itself is Hero's, every melee hero's (the
## right-click combo, Hero.swipe_attack: the smack, the backhand and the belly-bump that hits all round; the free
## swing, Hero.free_attack), and so are its numbers; what it hits is his skill's (Doug.impact hands its impact frame
## here), so in a match the server's copy of him deals it like his other skills. Extra Gravy ("dmg:attack") adds to it.

## Each blow's share of the weapon's (the same as Hero._swipe_impact's: the finisher hits hardest).
const MULT := {"swipe1": 1.0, "swipe2": 1.15, "swipe3": 1.7}

func impact() -> void:
	var h := hero
	make("swing", {"st": h.atk_style, "p": h.global_position, "d": h.aim_dir(), "c": h.trail_col.lerp(Color(1.0, 0.75, 0.4), 0.5)})

## The blow its rules land (here, or on the match server's copy of him).
func made(kind: String, d: Dictionary) -> void:
	if kind != "swing":
		return
	var st := str(d["st"])
	if st.begins_with("swipe"):
		_swipe(st, d["p"], d["d"], d["c"])
	else:
		_free(d["p"], d["d"])

## Server: a blow where it has him, one of the drumstick's.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "swing" or not (d.get("p") is Vector3 and d.get("d") is Vector3) or not Doug.SWING_STYLES.has(str(d.get("st", ""))):
		return false
	if (d["p"] as Vector3).distance_to(hero.global_position) > 4.0:
		return false
	d["d"] = (d["d"] as Vector3).normalized()
	if not d.get("c") is Color:
		d["c"] = Doug.ACCENT
	return true

## The combo's blow: the foes in its arc ahead (all round for the finisher).
func _swipe(st: String, at: Vector3, fwd: Vector3, col: Color) -> void:
	var h := hero
	var fin := st == "swipe3"
	var rng := h.reach() + (1.0 if fin else 0.55)
	var arc := 181.0 if fin else 70.0
	var any := false
	for e in h.game.enemies_near(at, rng + 1.5):
		if not foe(e):
			continue
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius > rng:
			continue
		if to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(arc)):
			h._hit_enemy(e, float(MULT[st]), 0.9 if fin else 0.2, "attack")
			h.fx("attack", "hit", {"p": e.global_position + Vector3(0, 1.1 * e.height, 0), "c": col})
			any = true
	if fin:
		h.fx("attack", "finisher", {"r": rng, "x": any})
		if any and h._mine():
			h.game.hitstop(0.06)

## The free swing: the nearest foe in front.
func _free(at: Vector3, fwd: Vector3) -> void:
	var h := hero
	var best = null
	var bd := 99.0
	for e in h.game.enemies_near(at, h.reach() + 1.6):
		if not foe(e):
			continue
		var to: Vector3 = e.global_position - at
		to.y = 0
		var dd: float = to.length() - e.radius
		if dd <= h.reach() + 0.4 and (to.length() < 0.4 or fwd.dot(to.normalized()) > cos(deg_to_rad(60.0))) and dd < bd:
			bd = dd
			best = e
	if best != null:
		h._hit_enemy(best, 1.0, 0.15, "attack")
		h.fx("attack", "hit", {"p": best.global_position + Vector3(0, 1.1 * best.height, 0)})

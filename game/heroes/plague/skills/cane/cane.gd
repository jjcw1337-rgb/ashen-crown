class_name PlagueCane
extends PlagueSkill
## His cane ("attack"): the three-blow combo of Hero's swing (swipe1..3: its reach, arc and weight), dealt here
## (ClassSkills.swing) so that it is decided where his rules run, and each blow leaving its own mark: Crow's Peck
## (swipe1) poisons what it struck, Vial Flick (swipe2) flings poison in a fan onto what it struck, Censer Slam
## (swipe3) cracks a vial into a little cloud that poisons what stands in it.
## Its look: the swing's own "hit" and "finisher" (SkillFx), and PlagueFx "cane" {n: 1 peck | 2 flick | 3 slam,
## p: the slam's spot, d: his facing, t: the foes struck, r, x: the cloud's size and seconds}. Its numbers are
## constants here: the codex has no entry for a hero's basic attack.

const PECK_S := 2.0          # seconds of poison from a peck or the slam
const FLICK_S := 3.0         # ... from the flick
const SLAM_R := 2.0          # the slam's cloud
const SLAM_S := 2.5
const LINGER := 3.0          # the cloud's poison stays this long after a foe steps out
const STYLES := {"swipe1": 1, "over": 1, "swipe2": 2, "back": 2, "swipe3": 3, "thrust": 3}

var clouds: Array = []       # the slams' clouds (PlagueCloud)

## A swing's impact frame, on his own game: the blow is made where his rules run.
func swing(style: String) -> void:
	reveal_if_fogged()
	make("blow", {"s": style, "d": hero.aim_dir()})

## Server: a swing of his (its style sets its reach and arc; only the cane's styles, STYLES, leave a mark) and his facing.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "blow" or not d.get("s") is String or not d.get("d") is Vector3:
		return false
	d["d"] = ((d["d"] as Vector3) * Vector3(1, 0, 1)).normalized()
	return true

## The blow: everything in the swing's reach struck (Hero._hit_enemy: the weapon's roll, his rites), then its mark.
func made(kind: String, d: Dictionary) -> void:
	if kind != "blow":
		return
	var h := hero
	var style := str(d["s"])
	var fwd: Vector3 = d["d"]
	var fin := style == "swipe3"
	var mult := 1.0 if style == "swipe1" else (1.15 if style == "swipe2" else 1.7)
	var struck := _swing_foes(style, fwd)
	for e in struck:
		h._hit_enemy(e, mult, 0.9 if fin else 0.2, "attack")
		h.fx("attack", "hit", {"p": e.global_position + Vector3(0, 1.1 * e.height, 0), "c": h.trail_col.lerp(Color(1.0, 0.75, 0.4), 0.5)})
	_mark(int(STYLES.get(style, 0)), fwd, struck)
	if fin:
		h.fx("attack", "finisher", {"r": _reach(fin), "x": not struck.is_empty()})
		if not struck.is_empty() and h._mine():
			h.game.hitstop(0.06)

## What each blow leaves: poison on what it struck, and the slam's cloud.
func _mark(n: int, fwd: Vector3, struck: Array) -> void:
	if n == 0:
		return
	var h := hero
	var at := ground(h.global_position + fwd * 1.3)
	var alive := struck.filter(func(e) -> bool: return is_instance_valid(e) and not e.dead)
	h.fx(id, "cane", {"n": n, "p": at, "d": fwd, "t": alive, "r": SLAM_R, "x": SLAM_S})
	var a := aff()
	if n == 3:
		clouds.append(cloud(at, SLAM_R, SLAM_S, "cane", LINGER))
	for e in alive:
		a.poison(e, "cane", FLICK_S if n == 2 else PECK_S)

func _reach(fin: bool) -> float:
	return hero.reach() + (1.0 if fin else 0.55)

## The foes a swing of this style reaches (its arc: wide on the finisher).
func _swing_foes(style: String, fwd: Vector3) -> Array:
	var h := hero
	var fin := style == "swipe3"
	var rng := _reach(fin)
	var arc := 181.0 if fin else 70.0
	var out := []
	for e in h.game.enemies_near(h.global_position, rng + 1.5):
		if not foe(e):
			continue
		var to: Vector3 = e.global_position - h.global_position
		to.y = 0
		if to.length() - e.radius > rng:
			continue
		if to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(arc)):
			out.append(e)
	return out

func update(delta: float) -> void:
	for c in clouds.duplicate():
		if tick_cloud(c, delta):
			clouds.erase(c)

func clear() -> void:
	clouds.clear()

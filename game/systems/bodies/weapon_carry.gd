class_name WeaponCarry
extends RefCounted
## Drawing and holstering a character's weapon. One per character; the character calls update() each
## frame and merges anim_state() into what it hands to Anim.pose, which plays the motion.
##
## Kept apart, as layers:
##  - threat (threatened): is anything targeting or attacking this character right now?
##  - decision: draw at once when threatened or when the character acts; holster only after `disengage`
##    seconds of real safety (never while a foe targets them; never because of a step out of reach)
##  - motion (Anim, by the profile's "motion"): the reach, the grab, the pull, the settle; the same
##    clock runs backwards when interrupted, so a half draw reverses smoothly, nothing pops
##  - where the weapon is (the "grab" moment of the motion): in the hand, or in storage ("hilt": the
##    body model's own scabbard hilt shows and the weapon model hides; "back": the weapon rides on the
##    back, visible)
## Per character: Data.WEAPON_PROFILES (by class / rig kind); missing keys fall back to DEFAULT and a
## missing profile warns once and uses DEFAULT, so nothing breaks.

const DEFAULT := {
	"motion": "back",        # Anim draw motion: "knight" (cross-body from the left hip) | "back" (over the shoulder)
	"store": "back",         # "hilt" (the model's own sheathed hilt) | "back" (weapon on the back)
	"draw_time": 0.7,        # seconds for the full draw
	"holster_time": 0.75,    # seconds for the full holster
	"grab": 0.4,             # fraction of the motion at which the hand has the weapon
	"threat_range": 16.0,    # metres: a foe targeting you within this keeps you ready
	"disengage": 4.0,        # seconds of safety before putting it away
	"town": "holster",       # in town: always put away
}

var p: Dictionary = DEFAULT
var state := "sheathed"      # sheathed | drawing | drawn | sheathing
var t := 0.0                 # 0 = sheathed .. 1 = drawn, along the motion
var safe_t := 99.0           # how long nothing has threatened us (starts long: arriving is not a threat)
var _scan := 0.0
var _threat := false
var _warned := false

## Sets the profile for this character (Data.WEAPON_PROFILES[key], else DEFAULT with a warning).
func configure(key: String) -> void:
	var prof: Dictionary = Data.WEAPON_PROFILES.get(key, {})
	if prof.is_empty() and not _warned:
		push_warning("WeaponCarry: no Data.WEAPON_PROFILES entry for '%s'; using the default draw" % key)
		_warned = true
	p = DEFAULT.merged(prof, true)

func drawn_amount() -> float:
	return t

func is_armed() -> bool:
	return state == "drawn"

## Is the weapon in the hand (past the grab point of the motion)?
func in_hand() -> bool:
	return t >= float(p["grab"]) if state != "sheathed" else false

## Threat: a living foe that is hunting `h` within range, a hit taken just now, or the character acting.
func threatened(h: Node3D, delta: float) -> bool:
	var game = h.game
	if game == null or game.world == null:
		return false
	if str(game.cur_zone) == "town" and p["town"] == "holster":
		return false
	if h.atk_t >= 0.0 or h.blocking or h.hit_t > 0.05:
		return true
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.2      # foes are checked five times a second, not every frame
		_threat = false
		for e in game.enemies_near(h.global_position, float(p["threat_range"])):
			if e.aggro and not e.dead and game.target_for(e) == h:
				_threat = true
				break
	return _threat

## Advance the state. Call once per frame, before posing.
func update(h: Node3D, delta: float) -> void:
	var in_town: bool = h.game != null and str(h.game.cur_zone) == "town" and p["town"] == "holster"
	var acting: bool = h.atk_t >= 0.0 or h.blocking
	if threatened(h, delta):
		safe_t = 0.0
	else:
		safe_t += delta
	var want := safe_t < float(p["disengage"]) and not in_town
	if acting and not in_town:
		want = true
		# an attack or a block can't wait for the draw: snap through it (the swing hides the cut)
		if state != "drawn":
			t = 1.0
			state = "drawn"
	if in_town and state == "drawn" and safe_t > 0.5:
		want = false
	match state:
		"sheathed":
			if want:
				state = "drawing"
		"drawn":
			if not want:
				state = "sheathing"
		"drawing":
			if not want:
				state = "sheathing"      # interrupted: run the same motion back from here
		"sheathing":
			if want:
				state = "drawing"
	if state == "drawing":
		t = minf(1.0, t + delta / float(p["draw_time"]))
		if t >= 1.0:
			state = "drawn"
	elif state == "sheathing":
		t = maxf(0.0, t - delta / float(p["holster_time"]))
		if t <= 0.0:
			state = "sheathed"

## Keys for Anim.pose: where along the motion we are, and which way.
func anim_state() -> Dictionary:
	return {"draw": t, "draw_motion": p["motion"], "draw_dir": 1.0 if state == "drawing" else (-1.0 if state == "sheathing" else 0.0)}

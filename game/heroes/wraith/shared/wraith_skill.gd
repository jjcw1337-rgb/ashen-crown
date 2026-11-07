class_name WraithSkill
extends Skill
## A skill of the Wraith's (docs/content/skills.md; every one of his is one, skills/): what they share. The spirit-
## light in his blows, his whole-body clips, crowd control on a monster or a player, a blow with its own roll, foes
## named over the wire, souls that heal him when they reach him, and an update that runs once a frame.
##
## What a skill does on his own game alone (his lunge, his blink, the night's stages, his mist) is its cast state,
## set by `cast` and `impact`, which never run on the match server. What its rules act on is made (`make`): here, or
## on the server's copy of him in a match (ServerRules), whose `tick` then deals it.

## Each clip's length in seconds (times the class's pace, Data.ATTACK_PACE; Spectral Rend's also by attack speed).
## The clips themselves: WraithBody.SHOTS.
const DUR := {"rend": 0.8, "siphon": 0.7, "wstep": 0.75, "grasp": 0.95, "phantom": 1.0,
	"night_rise": 0.9, "night_scream": 0.9, "night_hold": 2.4, "night_fall": 1.3}

var _frame := -1
var _heals: Array = []       # souls on their way back to him: [seconds left, % of his life]

## The spirit-light in his blows: a part by level on top of the weapon (the same curve as the other classes' spells),
## so the skills keep their weight while the weapon is still small. `share` is the skill's part of it (its codex
## "spirit" and the like, in %).
func spirit(share: float) -> float:
	var h := hero
	return (16.0 + h.level * 3.6 + (h.dmg_min + h.dmg_max) * 0.6) * share / 100.0

## Starts its clip (`style`: one of DUR's) and holds him where he is; `quick`: attack speed shortens it too.
func start(style: String, quick := false) -> void:
	var h := hero
	h._start_attack(style, id)
	var d: float = DUR[style] * Data.attack_pace(h.cls)
	if quick:
		d /= h.aspd
	h.atk_dur = d
	h.moving = false
	h.path = PackedVector3Array()

## Its clip is playing.
func playing() -> bool:
	return hero.atk_t >= 0.0 and hero.atk_skill == id

## Once a frame, whoever asks (ClassSkills runs every class's update on every hero, and some run any kit's).
func update(delta: float) -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return
	_frame = f
	_souls(delta)
	tick(delta)

## Every frame: its cast state on his own game, its rules wherever they were made.
func tick(_delta: float) -> void:
	pass

## A foe held fast for `secs`: a monster here, a player through the server (PvpStatus "stagger", with its
## diminishing returns).
func stun(e, secs: float) -> void:
	if PvpStatus.is_player(e):
		PvpStatus.send(hero.game, e, "stagger", secs)
	elif is_instance_valid(e) and not e.dead:
		e.stun(secs)

## A foe slowed by `k` (0..1) for `secs`: a monster here, a player through the server (PvpStatus "slow").
func slow(e, secs: float, k: float) -> void:
	if PvpStatus.is_player(e):
		PvpStatus.send(hero.game, e, "slow", secs, {"k": k})
	elif is_instance_valid(e) and not e.dead:
		e.slow(secs, k)

## A blow with its own roll (not through Hero._hit_enemy, so no rite rides it): what it dealt. On the match server
## its number goes to his screen.
func blow(e, phys: float, fire: float, from: Vector3, knock: float, crit: bool) -> float:
	var h := hero
	Hero.striker = h
	var dealt: float = e.take_damage(phys, fire, from, knock, crit)
	if h.puppet and h.game.net.server:
		h.game.net.tell_dealt(h, e.global_position, dealt, crit)
	return dealt

## Server: a point a player's game sent is within `slack` metres of where the server has him.
func near_him(p, slack: float) -> bool:
	return p is Vector3 and (p as Vector3).distance_to(hero.global_position) <= slack

## A direction a player's game sent, flat and of unit length (his facing if it has none).
func flat(d) -> Vector3:
	var v := Vector3.ZERO
	if d is Vector3:
		var dv: Vector3 = d
		v = dv * Vector3(1, 0, 1)
	return v.normalized() if v.length() > 0.001 else hero.facing()

## Its skill's reach (its codex "range").
func reach_m(fallback: float) -> float:
	return float(Data.skill_def(id).get("range", fallback))

## A soul torn out flies back to him and heals him `pct` % of his life when it arrives, `t` seconds from now (as
## long as its wisp flies, SpiritFx.soul_wisp). Life back from his own blows (Hero.gain_life: from the server's
## copy of him it goes to his game).
func heal_later(t: float, pct: float) -> void:
	_heals.append([t, pct])

func _souls(delta: float) -> void:
	if _heals.is_empty():
		return
	for s in _heals.duplicate():
		s[0] = float(s[0]) - delta
		if float(s[0]) > 0.0:
			continue
		_heals.erase(s)
		if not hero.dead:
			hero.gain_life(hero.max_life * float(s[1]) / 100.0)
			hero.stats_changed.emit()

## How long the i-th soul torn out takes to fly back to him (its wisp, and the heal that waits for it).
static func wisp_time(i: int) -> float:
	return 0.45 + 0.25 * fposmod(float(i) * 0.618, 1.0)

func rooted() -> bool:
	return false

func clear() -> void:
	_heals.clear()

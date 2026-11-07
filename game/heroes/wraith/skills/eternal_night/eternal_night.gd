class_name EternalNight
extends WraithSkill
## Eternal Night ("night", V, the ultimate): four stages chained as attacks. He rises (cast: the arms up, the night
## falling over everything round him), screams (scream: terror, damage and a knockback over the night), hangs in the
## night (cast's gathering: beats of damage while he is mist to every blow) and falls (the slam: the night collapses
## into a burst). The battle buff (+40% damage) for a while after (Eternal: longer; Fourth Rider: harder). The stages
## and his mist are his own game's; the scream, each beat and the fall are made where his hits are decided. Its look:
## EternalNightFx. Codex "k": radius (the night's), scream and scream_spirit (% of the weapon's blow and of the
## spirit-light), fear_s (seconds frozen with fear), beat and beat_spirit (each beat's, within the night less a
## metre), every (seconds between beats), fall and fall_spirit, fall_r, buff_s (seconds of the battle buff).

const STAGES := ["night_rise", "night_scream", "night_hold", "night_fall"]

var night := {}             # the stages under way (his own game): {stage, t, tick}
var screamed := -1.0        # the rules': seconds since the scream (the beats and the fall come after one)
var beats := 0              # the rules': beats since it

func cast(_aim: Vector3) -> void:
	var h := hero
	end(false)
	# the night itself (the dark coming down, the rise, his glow) is the "cast" event's look (EternalNightFx)
	night = {"stage": 0, "t": 0.0, "tick": 0.0}
	h.veil_t = 99.0        # mist to every blow until the night ends
	start("night_rise")

## The night is under way.
func active() -> bool:
	return not night.is_empty()

## The night lifts (`finished`: it ran its course).
func end(finished: bool) -> void:
	if night.is_empty():
		return
	hero.veil_t = 0.0
	night = {}
	hero.fx(id, "end", {"x": finished})

## Seconds of the battle buff after (Eternal: longer).
func buff_s() -> float:
	return val("buff_s", 12.0) + hero.talent("buff_dur")

func impact() -> void:
	var h := hero
	if night.is_empty():
		return
	match h.atk_style:
		"night_rise":
			h.fx(id, "rise")
		"night_scream":
			# the terror: damage, hurled back and frozen with fear over the whole night
			h.buff_t = buff_s()
			h.fx(id, "scream")
			make("scream", {"p": h.global_position})
		"night_fall":
			# the night collapses into the slam
			h.fx(id, "fall")
			make("fall", {"p": h.global_position})
			end(true)

## The stages, chained as attacks; the beats through the hold (his own game). The dark coming down through the
## rise, his glow and the fall's descent follow the attack's progress in EternalNightFx, on his puppet too.
func tick(delta: float) -> void:
	if screamed >= 0.0:
		screamed += delta
	var h := hero
	if night.is_empty():
		return
	if h.dead or h.atk_skill != id and h.atk_t >= 0.0:
		end(false)
		return
	night["t"] = float(night["t"]) + delta
	var stage: int = night["stage"]
	if stage == 2:
		night["tick"] = float(night["tick"]) - delta
		if float(night["tick"]) <= 0.0:
			night["tick"] = val("every", 0.5)
			make("beat", {"p": h.global_position})
	if h.atk_t < 0.0:
		# this stage is over: the next
		stage += 1
		if stage >= STAGES.size():
			end(true)
			return
		night["stage"] = stage
		start(STAGES[stage])
		if stage == 1:
			Sfx.play_synced("wail", Anim.impact_at("night_scream") * h.atk_dur, -2.0, 0.9)
		elif stage == 3:
			Sfx.play_synced("slam", Anim.impact_at("night_fall") * h.atk_dur, -3.0, 0.8)

## Server: where it has him (he hangs where he rose); the beats and the fall only after a scream, no more beats
## than its hold has, no later than its stages take.
func server_ok(kind: String, d: Dictionary) -> bool:
	if not near_him(d.get("p"), 4.0):
		return false
	var pace := Data.attack_pace(hero.cls)
	match kind:
		"scream":
			return true
		"beat":
			var most := int(ceil(DUR["night_hold"] * pace / val("every", 0.5))) + 1
			return screamed >= 0.0 and screamed <= (DUR["night_scream"] + DUR["night_hold"]) * pace + 1.0 and beats < most
		"fall":
			return screamed >= 0.0 and screamed <= (DUR["night_scream"] + DUR["night_hold"] + DUR["night_fall"]) * pace + 1.5
	return false

func made(kind: String, d: Dictionary) -> void:
	var h := hero
	var p: Vector3 = d["p"]
	match kind:
		"scream":
			# (its own battle buff here too: on the server's copy of him the blows that follow are as hard as his)
			h.buff_t = buff_s()
			screamed = 0.0
			beats = 0
			for e in h.game.enemies_near(p, val("radius", 9.0)):
				if not foe(e):
					continue
				h._hit_enemy(e, val("scream", 150.0) / 100.0, 2.2, id, spirit(val("scream_spirit", 120.0)))
				if is_instance_valid(e) and not e.dead:
					stun(e, val("fear_s", 2.5))
		"beat":
			beats += 1
			var any := false
			for e in h.game.enemies_near(p, val("radius", 9.0) - 1.0):
				if not foe(e):
					continue
				h._hit_enemy(e, val("beat", 30.0) / 100.0, 0.0, id, spirit(val("beat_spirit", 25.0)))
				any = true
			if any:
				h.fx(id, "tick")
		"fall":
			screamed = -1.0
			for e in h.game.enemies_near(p, val("fall_r", 6.5)):
				if foe(e):
					h._hit_enemy(e, val("fall", 200.0) / 100.0, 1.6, id, spirit(val("fall_spirit", 160.0)))

## Through its stages he hangs where he rose.
func rooted() -> bool:
	return playing()

func clear() -> void:
	super()
	end(false)
	screamed = -1.0

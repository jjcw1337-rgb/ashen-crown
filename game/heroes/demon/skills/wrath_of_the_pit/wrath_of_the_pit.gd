class_name WrathOfThePit
extends DemonSkill
## Wrath of the Pit (V, "wrath", the defensive counter): "crucible" (wings folded, up to `hold` s, recast to end it:
## `dr` less damage taken, nothing moves or stops him, the damage stored as heat) -> "wrath_roar" (the eruption round
## him: the blow plus the heat, terror) -> Pit-born: `pit_s` s of the battle buff (+40%), and meteors raining on the
## foes round him (Wrath's Rain: longer; Twin Meteors: two at a time). The Crucible and the stages are his own game's
## (it keeps his life); the eruption's blows and the rain are dealt where his hits are decided, the server's copy of
## him roused too so its blows carry the buff. Its look: WrathOfThePitFx (the Crucible, the eruption), DemonFx (the
## white heat, the meteors). Codex "k": dmg (% of the weapon's blow), magma (% of his magma), hold and min (seconds:
## the Crucible's longest, and before a recast ends it), dr (% less damage), heat (% of it stored) and heat_cap (% of
## his life), radius (metres), knock, fear_s (monsters; players: its "pvp" fear), pit_s (seconds), every (seconds
## between meteors), rain_r (metres), fall and fall_pvp (seconds in the air), meteor_r (metres), meteor and
## meteor_magma (its blow), meteor_burn (% of his magma a second, monsters).

## The wrath in progress: his own game's {t, heat, rain (-1 before the eruption), next}, plus the rain's on the side
## that deals it {n, pvp_n, last}.
var wrath := {}
## Pit-born: the PvP share of his blows takes the wrath's bonus in place of the battle buff (DemonSkill.hit).
var pit := false
var meteors: Array = []      # in the air: {at, t}

func cast(_aim: Vector3) -> void:
	_end(false)
	wrath = {"t": 0.0, "heat": 0.0, "rain": -1.0, "next": 0.0, "n": 0, "pvp_n": 0}
	start("crucible", val("hold", 2.0))
	hero.fx(id, "crucible", {"x": hero.atk_dur})

func rooted() -> bool:
	return hero.atk_t >= 0.0 and hero.atk_skill == id

## In the Crucible right now.
func holding() -> bool:
	var h := hero
	return not wrath.is_empty() and h.atk_skill == id and h.atk_style == "crucible" and h.atk_t >= 0.0

## Pressing it again in the Crucible ends it early.
func recast() -> bool:
	if holding() and hero.atk_t >= val("min", 0.35) * Data.attack_pace(hero.cls):
		_erupt_now()
		return true
	return false

## Hero.take_hit: the Crucible takes its share of the blow and stores what gets through as heat.
func absorb(dmg: float) -> float:
	if not holding():
		return dmg
	var h := hero
	var left := dmg * (1.0 - val("dr", 50.0) / 100.0)
	var share := val("heat", 50.0) / 100.0
	var cap := h.max_life * val("heat_cap", 30.0) / 100.0
	wrath["heat"] = minf(float(wrath["heat"]) + left, cap / share)
	h.fx(id, "heat", {"x": clampf(float(wrath["heat"]) * share / maxf(cap, 1.0), 0.0, 1.0)})
	return left

func _erupt_now() -> void:
	start("wrath_roar")

func stage_done(style: String) -> void:
	if style == "crucible":
		next = "wrath_roar"

func begin_stage(style: String) -> void:
	if style == "wrath_roar":
		_erupt_now()

## The eruption on his game's impact frame: what it does to him here, its blows where his hits are decided.
func impact() -> void:
	var h := hero
	if wrath.is_empty() or h.atk_style != "wrath_roar":
		return
	var cap := h.max_life * val("heat_cap", 30.0) / 100.0
	var heat: float = minf(float(wrath["heat"]) * val("heat", 50.0) / 100.0, cap)
	var d := {"p": h.global_position, "x": heat}
	if not deals():
		_pit_born()
		h.fx(id, "erupt", {"p": d["p"], "x": float(wrath["rain"]), "r": clampf(heat / maxf(cap, 1.0), 0.0, 1.0)})
	make("erupt", d)

## Server: the eruption where it has him, with no more heat than his life allows.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "erupt" or not d.get("p") is Vector3 or (d["p"] as Vector3).distance_to(hero.global_position) > 4.0:
		return false
	d["x"] = clampf(float(d.get("x", 0.0)), 0.0, hero.max_life * val("heat_cap", 30.0) / 100.0)
	return true

func made(kind: String, d: Dictionary) -> void:
	if kind != "erupt":
		return
	var h := hero
	if wrath.is_empty():
		wrath = {"t": 0.0, "heat": 0.0, "rain": -1.0, "next": 0.0}
	wrath["n"] = 0
	wrath["pvp_n"] = 0
	var heat := float(d["x"])
	var at: Vector3 = d["p"]
	var r := val("radius", 6.0)
	var struck := []
	for e in h.game.enemies_near(at, r + 0.6):
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius > r or not foe(e):
			continue
		struck.append(e)
		hit(e, val("dmg", 100.0) / 100.0, val("knock", 1.8), magma(h, val("magma", 80.0) / 100.0) + heat)
		if is_instance_valid(e) and not e.dead:
			cc(e, "fear", val("fear_s", 1.5), pvp("fear", 0.75))
	_pit_born()
	var lit := struck.filter(func(x) -> bool: return not PvpStatus.is_player(x))
	if h.puppet:
		h.fx(id, "struck", {"t": lit})        # (the server's copy: his game showed the eruption itself)
	else:
		var cap := h.max_life * val("heat_cap", 30.0) / 100.0
		h.fx(id, "erupt", {"p": at, "x": float(wrath["rain"]), "r": clampf(heat / maxf(cap, 1.0), 0.0, 1.0), "t": lit})

## Pit-born: the battle buff, and the rain begins.
func _pit_born() -> void:
	var h := hero
	h.buff_t = val("pit_s", 6.0) + h.talent("buff_dur")
	pit = true
	wrath["rain"] = val("pit_s", 6.0) + h.talent("wrath_dur")
	wrath["next"] = 0.35

func step(delta: float) -> void:
	var h := hero
	stages()
	for m in meteors.duplicate():
		m["t"] = float(m["t"]) - delta
		if float(m["t"]) <= 0.0:
			meteors.erase(m)
			land_meteor(m["at"], val("meteor_r", 2.3), val("meteor", 110.0) / 100.0, val("meteor_magma", 55.0) / 100.0, val("meteor_burn", 10.0) / 100.0)
	# the Crucible: nothing moves or stops him
	if holding():
		h.daze_t = 0.0
		h.shove = Vector3.ZERO
		h.knock_v = Vector3.ZERO
	_rain(delta)

## The wrath's rain, which runs while he fights on (the meteors where his hits are decided).
func _rain(delta: float) -> void:
	var h := hero
	if wrath.is_empty():
		return
	if h.dead:
		_end(false)
		return
	wrath["t"] = float(wrath["t"]) + delta
	if float(wrath["rain"]) < 0.0:
		if h.atk_skill != id and next == "":
			_end(false)       # cut short (death, a zone change) before the eruption
		return
	var rain: float = float(wrath["rain"])
	if rain <= 0.0:
		_end(true)
		return
	wrath["rain"] = rain - delta
	wrath["next"] = float(wrath["next"]) - delta
	if float(wrath["next"]) <= 0.0:
		wrath["next"] = val("every", 0.45)
		if deals():
			_call_meteor()
			if h.talent("wrath_double") > 0.0:
				_call_meteor()

## A meteor: aimed at a foe within rain_r (the one struck least recently), else near him. At a player (PvP) it falls
## slower under a glowing circle, and only its "pvp" meteors of them a cast.
func _call_meteor() -> void:
	var h := hero
	var n := wrath
	var foes: Array = h.game.enemies_near(h.global_position, val("rain_r", 9.0)).filter(func(x) -> bool: return foe(x))
	if int(n.get("pvp_n", 0)) >= int(pvp("meteors", 3.0)):
		foes = foes.filter(func(x) -> bool: return not PvpStatus.is_player(x))
	var at: Vector3
	var fall := val("fall", 0.55)
	if foes.is_empty():
		var ang := randf() * TAU
		var r := randf_range(2.5, val("rain_r", 9.0) * 0.7)
		at = h.global_position + Vector3(cos(ang) * r, 0, sin(ang) * r)
	else:
		var last: Dictionary = n.get("last", {})
		foes.sort_custom(func(a, b) -> bool: return float(last.get(a.get_instance_id(), -9.0)) < float(last.get(b.get_instance_id(), -9.0)))
		var pick = foes[0]
		last[pick.get_instance_id()] = float(n["t"])
		n["last"] = last
		at = pick.global_position + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		if PvpStatus.is_player(pick):
			n["pvp_n"] = int(n.get("pvp_n", 0)) + 1
			fall = val("fall_pvp", 0.8)
	at.y = h.game.world.height_at(at.x, at.z)
	var k: int = int(n.get("n", 0))
	n["n"] = k + 1
	meteors.append({"at": at, "t": fall})
	h.fx(id, "meteor", {"p": at, "n": k, "x": fall})

## The wrath ends (its rain over, or cut short): his game shows it.
func _end(finished: bool) -> void:
	pit = false
	if wrath.is_empty():
		return
	wrath = {}
	if not hero.puppet:
		hero.fx(id, "end", {"x": finished})

func clear() -> void:
	_end(false)
	meteors.clear()
	next = ""

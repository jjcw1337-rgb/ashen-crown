class_name Swarmcraft
extends PlagueSkill
## E Swarmcraft ("swarm"): a swarm of plague flies sent to a point (never homing), hovering there; recast twice to send
## it on (free). Inside: light damage, Harried (attacks and casts slower), revealed through fog, Blight. A dodge roll
## through it, or any area blow that reaches it (Fx.area_hit), scatters it for a moment. Its cooldown starts when it
## goes back to its reliquary.
## His own game keeps whether it is out and how often it may still be sent on (`out_t`, `sends`: its cast and its
## cooldown); the swarm itself is the rules' (`swarm`), here or on the match server's copy of him.
## Its look: PlagueSwarmFx ("swarm" {p: from, q: to, r, x: seconds}, "swarm_to" {q}, "scatter", "bite" {t},
## "home"): every game flies its own swarm at the same pace. Codex "k": cast_s, radius (Bigger Swarm adds to it),
## secs, speed, redirects, scatter_s, harried (% slower), harried_s, reveal_s, bite_flat/lvl/wpn (a second's bites,
## times two).

var swarm := {}        # the rules': {pos, to, t, left, tick, scatter, r}
var out_t := 0.0       # his game: seconds until it goes home
var sends := 0         # his game: times it may still be sent on

func radius() -> float:
	return val("radius", 3.0) * (1.0 + hero.talent("swarm_size") / 100.0)

func secs() -> float:
	return val("secs", 6.0) + hero.talent("swarm_dur")

## While it is out, using it again sends it on (free: nothing is spent, so it refuses the cast).
func can_cast(aim: Vector3) -> bool:
	if out_t <= 0.0:
		return true
	if sends <= 0:
		hero.game.ui.message("The swarm won't be turned again", Color(0.8, 0.8, 0.6))
		return false
	sends -= 1
	var to := ground(within_range(aim, 13.0))
	hero.fx(id, "swarm_to", {"q": to})
	make("redirect", {"q": to})
	return false

func cast(aim: Vector3) -> void:
	hero.atk_aim = within_range(aim, 13.0)
	hero._start_attack("pd_swarm", id)
	hero.atk_dur = cast_secs(0.8)
	hero.cds[id] = 0.0      # its cooldown starts when the swarm goes home (`update`)

func impact() -> void:
	var from := hand(1.4)
	var to := ground(hero.atk_aim)
	reveal_if_fogged()
	out_t = secs()
	sends = int(val("redirects", 2.0)) + int(hero.talent("swarm_redirect"))
	hero.fx(id, "swarm", {"p": from, "q": to, "r": radius(), "x": out_t})
	make("swarm", {"p": from, "q": to})

## Server: from his hand, to within its range; sent on while it is out and may be.
func server_ok(kind: String, d: Dictionary) -> bool:
	var reach := float(Data.skill_def(id).get("range", 13.0)) + 4.0
	match kind:
		"swarm":
			return near_him(d.get("p"), 4.0) and near_him(d.get("q"), reach)
		"redirect":
			return near_him(d.get("q"), reach) and not swarm.is_empty() and int(swarm["left"]) > 0
	return false

func made(kind: String, d: Dictionary) -> void:
	match kind:
		"swarm":
			_end()
			var r := radius()
			swarm = {"pos": d["p"], "to": d["q"], "t": secs(), "left": int(val("redirects", 2.0)) + int(hero.talent("swarm_redirect")),
				"tick": 0.0, "scatter": 0.0, "r": r}
			# any area blow (a nova, a slam, a shockwave ring) that reaches it scatters it: where its rules run, which
			# plays every partner's and foe's effects too
			var cb := Callable(self, "_area_hit")
			if not Fx.area_listeners.has(cb):
				Fx.area_listeners.append(cb)
		"redirect":
			if not swarm.is_empty() and int(swarm["left"]) > 0:
				swarm["to"] = d["q"]
				swarm["left"] = int(swarm["left"]) - 1

func update(delta: float) -> void:
	if out_t > 0.0:
		out_t -= delta
		if out_t <= 0.0 and not hero.puppet and hero.cds.has(id):
			hero.cds[id] = hero.skill_cd(id)        # home: the cooldown starts
	if swarm.is_empty():
		return
	# it flies at its own speed toward its point (never chasing anyone) and hangs there
	var pos: Vector3 = swarm["pos"]
	var to: Vector3 = swarm["to"]
	pos += (to - pos).limit_length(val("speed", 6.0) * delta)
	swarm["pos"] = pos
	swarm["t"] = float(swarm["t"]) - delta
	swarm["scatter"] = maxf(float(swarm["scatter"]) - delta, 0.0)
	if float(swarm["t"]) <= 0.0:
		_end()
		hero.fx(id, "home")
		return
	var r: float = swarm["r"]
	var net = hero.game.net
	# a dodge roll through it scatters it for a moment (another player rolling, as this game has him)
	if float(swarm["scatter"]) <= 0.0 and net != null and net.active:
		for pid in net.players.keys():
			var ph = net.players[pid].get("hero")
			if ph != null and is_instance_valid(ph) and ph != hero and Dodge.dodging(ph) and ph.global_position.distance_to(pos) < r:
				_scatter()
				break
	swarm["tick"] = float(swarm["tick"]) - delta
	if float(swarm["tick"]) > 0.0 or float(swarm["scatter"]) > 0.0:
		return
	var a := aff()
	swarm["tick"] = a.tick()
	var dmg := base_k("bite", 5.0, 0.77, 0.1) * a.tick() * 2.0
	var heals := hero.talent("swarm_heal")
	var bit: Array = []
	for e in foes(pos, r):
		damage(e, dmg, pos, false)
		if heals > 0.0:
			heal(hero.max_life * heals / 100.0 * a.tick())
		PvpStatus.send(hero.game, e, "harried", val("harried_s", 0.8), val("harried", 25.0) / 100.0)
		if e.pvp_pid > 0:
			PvpStatus.send(hero.game, e, "reveal", val("reveal_s", 0.8), 1.0)
		a.blight(e, id)
		bit.append(e)
	if not bit.is_empty():
		hero.fx(id, "bite", {"t": bit})

func _scatter() -> void:
	swarm["scatter"] = val("scatter_s", 1.5)
	hero.fx(id, "scatter")

## An area blow somewhere (Fx.area_hit): if it reaches the swarm, the swarm scatters.
func _area_hit(pos: Vector3, radius_: float) -> void:
	if swarm.is_empty() or float(swarm["scatter"]) > 0.0:
		return
	var sp: Vector3 = swarm["pos"]
	if Vector2(sp.x - pos.x, sp.z - pos.z).length() > radius_ + float(swarm["r"]) * 0.6:
		return
	_scatter()

func _end() -> void:
	swarm = {}
	Fx.area_listeners.erase(Callable(self, "_area_hit"))

func clear() -> void:
	_end()
	out_t = 0.0
	sends = 0

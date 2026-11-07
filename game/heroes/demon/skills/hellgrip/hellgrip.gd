class_name Hellgrip
extends DemonSkill
## Hellgrip (G, "grip", pick and pull): "grip_throw" flings the chain (`len` at `speed`; the first body in its line is
## hooked, monsters block it) -> "grip_haul" (the victim dragged to him, or he to a boss or to a monster his game
## doesn't own) -> "grip" (hoisted and smashed into the ground, a shockwave round it). A miss hauls back an empty
## chain (the recovery). A Branded victim gives back `refund` of the cooldown. The chain and the stages are his own
## game's; what they do to the victim (the pull, the hold, the smash) is dealt where his hits are decided, the victim
## named by his game (make_at). Its look: HellgripFx ("Chain of the Pit"), the hold over his head DemonFx's. Codex
## "k": dmg (% of the weapon's blow), magma (% of his magma), len (metres), speed (m/s), hit_w (metres either side),
## refund (% of the cooldown), shock_r (metres), shock and shock_magma (the shockwave's blow), knock, shock_knock,
## burn (% of his magma a second) and burn_s, stun_s (after the smash), lift and hold_in (metres: how high he holds
## them, where a dragged one ends up).

var chain := {}        # in flight or hauling, his own game's: {from, dir, len, state, t, dur, self, start, goal}
var victim = null      # who his chain hooked (his game)
var grabbed := false   # the hold has begun
var held = null        # its rules' victim (here, or on the match server)

func cast(_aim: Vector3) -> void:
	chain = {}
	victim = null
	grabbed = false
	start("grip_throw")

func rooted() -> bool:
	return hero.atk_t >= 0.0 and hero.atk_skill == id

func impact() -> void:
	match hero.atk_style:
		"grip_throw":
			_fling()
		"grip":
			_smash()

## The chain flies out of his hand.
func _fling() -> void:
	var h := hero
	var from := h.global_position + Vector3(0, 1.3, 0)
	var dir := h.aim_dir()
	chain = {"from": from, "dir": dir, "len": 0.0, "state": "out", "t": 0.0}
	h.fx(id, "fling", {"p": from, "d": dir, "x": val("len", 7.5) / val("speed", 24.0), "r": val("len", 7.5)})

func step(delta: float) -> void:
	var h := hero
	stages()
	if not chain.is_empty():
		_chain(delta)
	if victim != null and h.atk_skill != id:
		victim = null
	# the victim is held up over his head until the smash (shown by DemonFx)
	if h.atk_skill == id and h.atk_style == "grip" and not grabbed and h.atk_t >= 0.0:
		grabbed = true
		if victim != null and is_instance_valid(victim) and not victim.dead:
			make("grab", {})
			var pl := PvpStatus.is_player(victim)
			h.fx(id, "grab", {"t": [] if pl else [victim], "pid": int(victim.pvp_pid) if pl else 0, "x": Anim.impact_at("grip") * h.atk_dur})

func _chain(delta: float) -> void:
	var h := hero
	var c := chain
	if h.dead or h.atk_skill != id:
		chain = {}
		return
	c["t"] = float(c["t"]) + delta
	match str(c["state"]):
		"out":
			var l0: float = float(c["len"])
			var full := val("len", 7.5)
			var l1 := minf(l0 + val("speed", 24.0) * delta, full)
			c["len"] = l1
			var dir: Vector3 = c["dir"]
			var base := h.global_position
			var hook = null
			var bd := 99.0
			for e in h.game.enemies_near(base + dir * (l1 * 0.5), l1 * 0.5 + 1.5):
				if not foe(e):
					continue
				var to: Vector3 = e.global_position - base
				to.y = 0
				var along := to.dot(dir)
				if along < l0 - 0.6 or along > l1 + e.radius:
					continue
				var off := (to - dir * along).length()
				if off - e.radius > val("hit_w", 0.55):
					continue
				if along < bd:
					bd = along
					hook = e
			# the chain stops on stone too
			var tip := base + dir * l1
			var free: Vector3 = h.game.world.move(base, dir * l1, 0.2)
			var wall := (free - base).length() < l1 - 0.3
			if hook != null:
				_hooked(hook)
			elif wall or l1 >= full:
				c["state"] = "back"
				h.fx(id, "miss", {"p": tip if not wall else free})
				next_now("grip_haul")
		"drag":
			var v = victim
			if v == null or not is_instance_valid(v) or v.dead:
				c["state"] = "back"
				return
			var u: float = clampf(float(c["dt"]) + delta / maxf(float(c["dur"]), 0.05), 0.0, 1.0)
			c["dt"] = u
			var k := 1.0 - pow(1.0 - u, 2.0)
			if bool(c["self"]):
				# he is dragged to it
				var want: Vector3 = (c["start"] as Vector3).lerp(c["goal"], k)
				h.global_position = h.game.world.move(h.global_position, (want - h.global_position) * Vector3(1, 0, 1), h.radius)
			elif not PvpStatus.is_player(v) and not bool(v.remote):
				var want2: Vector3 = (c["start"] as Vector3).lerp(c["goal"], k)
				v.global_position = h.game.world.move(v.global_position, (want2 - v.global_position) * Vector3(1, 0, 1), v.radius)

## The claw bites: the haul begins (the victim to him, or he to a boss or to a monster his game doesn't own).
func _hooked(e) -> void:
	var h := hero
	var c := chain
	c["state"] = "drag"
	c["dt"] = 0.0
	var dur: float = float(Demon.DUR["grip_haul"]) * Data.attack_pace(h.cls)
	c["dur"] = dur
	var me := h.global_position
	var to: Vector3 = (e.global_position - me) * Vector3(1, 0, 1)
	var dir := to.normalized() if to.length() > 0.1 else h.aim_dir()
	var self_pull: bool = immovable(e) or (not PvpStatus.is_player(e) and bool(e.remote))
	c["self"] = self_pull
	if self_pull:
		c["start"] = me
		c["goal"] = e.global_position - dir * (e.radius + h.radius + 0.6)
	else:
		c["start"] = e.global_position
		c["goal"] = me + dir * val("hold_in", 1.5)
	victim = e
	make_at("hook", e, {"x": dur, "n": self_pull})
	var pl := PvpStatus.is_player(e)
	h.fx(id, "hook", {"t": [] if pl else [e], "pid": int(e.pvp_pid) if pl else 0,
		"p": e.global_position + Vector3(0, e.height * 0.6, 0), "x": dur, "n": 1 if self_pull else 0})
	next_now("grip_haul")

## Server: the foe it names is within his chain of where it has him; the hold and the smash follow a hook.
func server_ok(kind: String, d: Dictionary) -> bool:
	match kind:
		"hook":
			var e = foe_in(d)
			if e == null or (e as Node3D).global_position.distance_to(hero.global_position) > val("len", 7.5) + 4.0:
				return false
			d["x"] = clampf(float(d.get("x", 0.0)), 0.0, float(Demon.DUR["grip_haul"]) * Data.attack_pace(hero.cls))
			return true
		"grab":
			return held != null and is_instance_valid(held)
		"smash":
			return d.get("at") is Vector3 and (d["at"] as Vector3).distance_to(hero.global_position) <= val("hold_in", 1.5) + 4.0
	return false

func made(kind: String, d: Dictionary) -> void:
	var h := hero
	match kind:
		"hook":
			# one hard status for the whole hold on a player (dragged over the haul, then held till the smash); a
			# monster stunned through it
			var e = foe_in(d)
			if e == null:
				return
			held = e
			var dur := float(d["x"])
			if PvpStatus.is_player(e):
				if not bool(d.get("n", false)):
					PvpStatus.send(h.game, e, "pull", pvp("hold", 1.1), {"m": dur})
			else:
				e.stun(dur + 1.4)
			var brand := Demon.brands(h)
			if brand.has(e):
				cut_cooldown(val("refund", 30.0) / 100.0)
				brand.spend(e)
		"grab":
			if held != null and is_instance_valid(held) and not held.dead and not PvpStatus.is_player(held):
				held.stun(2.0)
		"smash":
			_dealt(d["at"])

## The smash on his game's impact frame: shown at once, dealt by its rules.
func _smash() -> void:
	var h := hero
	var v = victim
	var at := h.global_position + h.aim_dir() * val("hold_in", 1.5)
	var is_held: bool = v != null and is_instance_valid(v) and not v.dead
	if is_held:
		at = v.global_position
	at.y = h.game.world.height_at(at.x, at.z)
	var look := {"p": at, "t": [v] if is_held and not PvpStatus.is_player(v) else [], "x": is_held}
	if deals():
		_dealt(at)
	else:
		h.game.net.send_skill_make(id, "smash", {"at": at})
	h.fx(id, "smash", look)
	if is_held:
		SkillFx.hitstop(h, 0.07)

## The held foe driven into the ground and set alight, a shockwave through the rest.
func _dealt(at: Vector3) -> void:
	var h := hero
	var v = held
	var is_held: bool = v != null and is_instance_valid(v) and not v.dead
	if is_held:
		at = v.global_position
		at.y = h.game.world.height_at(at.x, at.z)
		hit(v, val("dmg", 320.0) / 100.0, val("knock", 0.3), magma(h, val("magma", 160.0) / 100.0))
		if is_instance_valid(v) and not v.dead:
			var dps: float = magma(h, val("burn", 20.0) / 100.0) * h.dmg_mult(id)
			if PvpStatus.is_player(v):
				PvpStatus.send(h.game, v, "burn", 3.0, {"dps": dps})
			else:
				v.ignite(dps, val("burn_s", 4.0))
				v.stun(val("stun_s", 0.6))
	for e in foes_round(at, val("shock_r", 2.6)):
		if e != v:
			hit(e, val("shock", 70.0) / 100.0, val("shock_knock", 1.5), magma(h, val("shock_magma", 40.0) / 100.0))
	held = null

func stage_done(style: String) -> void:
	var h := hero
	match style:
		"grip_throw":
			if not chain.is_empty() and str(chain["state"]) == "out":
				# the clip ended with the chain still out (it hooks nothing now): hauled back empty
				chain["state"] = "back"
				h.fx(id, "miss", {"p": h.global_position + (chain["dir"] as Vector3) * float(chain["len"])})
				next = "grip_haul"
			elif chain.is_empty():
				h.fx(id, "end", {})
		"grip_haul":
			if str(chain.get("state", "")) == "drag":
				next = "grip"
			else:
				chain = {}
				h.fx(id, "end", {})

func begin_stage(style: String) -> void:
	var h := hero
	match style:
		"grip_haul":
			var dur: float = float(chain.get("dur", Demon.DUR["grip_haul"])) if str(chain.get("state", "")) == "drag" else 0.5
			start("grip_haul", dur / Data.attack_pace(h.cls))
		"grip":
			var v = victim
			chain = {}
			if v == null or not is_instance_valid(v) or v.dead:
				return
			start("grip")

func clear() -> void:
	chain = {}
	victim = null
	held = null
	grabbed = false
	next = ""

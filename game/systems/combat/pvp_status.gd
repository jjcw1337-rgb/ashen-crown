class_name PvpStatus
extends RefCounted
## Crowd control between players in the Battlegrounds. Damage between players already goes through the server
## (Enemy.take_damage -> Net.sv_pvp_hit); this is the same road for what a blow does besides hurt: a stagger, being
## thrown up, dragged, frozen with fear, slowed, set burning or Branded.
##
##   caster's game:  PvpStatus.send(game, stand_in, kind, secs, data)   (the stand-in is the victim's Enemy with pvp_pid)
##   server:         Net.sv_pvp_status -> Battlegrounds.pvp_status: the raid is on, both alive, within reach, and the
##                   diminishing returns (DR) on hard crowd control; then Net.cl_pvp_status to the victim only
##   victim's game:  PvpStatus.apply(hero, kind, secs, data); PvpStatus.update(hero, delta) runs it from Hero._process
##
## The Demon's and the Plague Doctor's skills and the Archer's Thunderstep send it (other classes' stuns stay PvE-only
## until each is reviewed for PvP). What the victim's partners see: the Demon's come from his own fx events (DemonFx draws them on the victim's
## puppet); the Plague Doctor's ride in the victim's state packet (PvpStatusFx, Net._flags).
##
## Kinds: "stagger" (no acting or moving), "knockup" (thrown up and down again, no acting), "pull" {p: where to, m: seconds of dragging}
## (dragged there, no acting), "fear" {p: what to flee} (runs away on its own, no acting), "slow" {k: how much
## slower}, "burn" {dps} (fire ticks), "brand" (the Demon's mark: shown on him; the caster keeps the real state).
## The Plague Doctor's (kept in `Hero.pvs` {kind: [seconds, k]}, ceilings MAX/MAX_K): "snare" (rooted: can't walk,
## can still act), "harried" {k} (attacks and casts take 1 + k longer, `act_mult`), "reveal" (seen through his Fog),
## "blight" {k: stacks} (Fever at 3: healing -40%). His calls pass a number for k (`send`, `apply` take either).
## Hard kinds are the ones DR counts: within DR_WINDOW s of the first, the second lasts half, then none for DR_IMMUNE s.

const HARD := ["stagger", "knockup", "pull", "fear", "snare"]
const DR_WINDOW := 8.0
const DR_IMMUNE := 3.0
const MAX_SECS := 3.0          # no hard status the server passes lasts longer (Thunderstep's stun: 3 s, Blaine)
const SOFT_MAX := 6.0          # nor a slow, burn or Brand
const BURN_TICK := 0.5
const FEAR_SPEED := 3.2
const KNOCKUP_H := 1.1
## the Plague Doctor's kinds: ceilings on seconds and strength (the server clamps what a client asks for)
const MAX := {"snare": 1.0, "harried": 3.0, "reveal": 4.0, "blight": 6.0}
const MAX_K := {"snare": 1.0, "harried": 0.35, "reveal": 1.0, "blight": 3.0}
## Tests: every status that landed on this game's hero, [kind, seconds] (tools/demon_pvp_test.gd)
static var landed: Array = []

static func _data(data) -> Dictionary:
	if data is Dictionary:
		return data
	return {"k": float(data), "src": "pd"}     # (a number is the Plague Doctor's call)

## Caster's game: a status for the player behind this stand-in, through the server. `data` is a Dictionary, or a
## number (k) for the Plague Doctor's; his on a monster (a number) become the nearest thing it has (slow and
## harried = a chill, snare = a short stun). Returns true when it went to a player.
static func send(game, e, kind: String, secs: float, data = {}) -> bool:
	if e == null or not is_instance_valid(e) or e.dead or int(e.get("pvp_obj")) > 0:
		return false      # (a player's thing, PvpObjects, only counts blows)
	if int(e.get("pvp_pid")) > 0:
		if game.net != null:
			game.net.send_pvp_status(int(e.pvp_pid), kind, secs, _data(data))
		return true
	if data is Dictionary:
		return false
	var k := float(data)
	match kind:
		"slow", "harried":
			var kk := k if kind == "slow" else k * 0.5
			if e.remote:
				e.chill(kk, secs)
			else:
				e.chill_k = maxf(e.chill_k if e.chill_t > 0.0 else 0.0, kk)
				e.chill_t = maxf(e.chill_t, secs)
		"snare":
			e.stun(secs)
	return false

## Server: a Plague Doctor's kind clamped to its ceiling (secs, and k in data). Other kinds pass unchanged.
static func clamp_status(kind: String, secs: float, data: Dictionary) -> float:
	if MAX.has(kind):
		data["k"] = clampf(float(data.get("k", 1.0)), 0.0, float(MAX_K[kind]))
		return clampf(secs, 0.0, float(MAX[kind]))
	return secs

## Is this enemy a player's stand-in (a PvP target)?
static func is_player(e) -> bool:
	return e != null and is_instance_valid(e) and e.get("pvp_pid") != null and int(e.pvp_pid) > 0

## Server: the diminishing returns for one target. Returns the seconds to apply (0 = refused).
## dr: {target: {"t0": raid time of the window's first, "n": hard statuses in it, "imm": immune until}}
static func diminish(dr: Dictionary, target: int, kind: String, secs: float, now: float) -> float:
	if not kind in HARD:
		return clampf(secs, 0.0, SOFT_MAX)
	secs = clampf(secs, 0.0, MAX_SECS)
	var d: Dictionary = dr.get(target, {"t0": -99.0, "n": 0, "imm": -1.0})
	if now < float(d["imm"]):
		return 0.0
	if now - float(d["t0"]) > DR_WINDOW:
		d = {"t0": now, "n": 0, "imm": -1.0}
	var n: int = int(d["n"]) + 1
	d["n"] = n
	var out := secs
	if n == 2:
		out = secs * 0.5
	elif n >= 3:
		out = 0.0
		d["imm"] = now + DR_IMMUNE
		d["t0"] = -99.0
		d["n"] = 0
	dr[target] = d
	return out

## Victim's game: the status lands (unless he is out of reach of it: rolling, mist, the Crucible, dead).
static func apply(h: Hero, kind: String, secs: float, data = {}) -> void:
	if h == null or h.dead or h.puppet or secs <= 0.0:
		return
	data = _data(data)
	if MAX.has(kind):
		_apply_pd(h, kind, secs, data)
		return
	if h.game.test_immortal or h.phased:
		return
	if kind in HARD and (Dodge.dodging(h) or h.veil_t > 0.0 or unstoppable(h)):
		return
	if kind in HARD or kind == "slow":
		secs *= h.cc_k()          # tenacity ("ten" on gear, Blaine's items rework) shortens stuns and slows
	var cc: Dictionary = h.cc
	landed.append([kind, secs])
	match kind:
		"stagger":
			h.daze_t = maxf(h.daze_t, secs)
			_word(h, "Staggered", Color(1.0, 0.55, 0.3))
		"knockup":
			h.daze_t = maxf(h.daze_t, secs)
			cc["up"] = {"t": 0.0, "dur": secs}
			_word(h, "Thrown", Color(1.0, 0.55, 0.3))
		"pull":
			h.daze_t = maxf(h.daze_t, secs)
			# dragged over "m" s (the rest of secs he is held where he lands)
			cc["pull"] = {"t": 0.0, "dur": minf(float(data.get("m", secs)), secs), "from": h.global_position, "to": data.get("p", h.global_position)}
			_stop(h)
		"fear":
			h.daze_t = maxf(h.daze_t, secs)
			cc["fear"] = {"t": secs, "from": data.get("p", h.global_position)}
			_stop(h)
			_word(h, "Terrified", Color(0.95, 0.35, 0.25))
		"slow":
			cc["slow"] = {"t": maxf(secs, float(cc.get("slow", {}).get("t", 0.0))), "k": clampf(float(data.get("k", 0.35)), 0.0, 0.6),
				"src": str(data.get("src", ""))}     # ("pd": the Plague Doctor's, shown as his mist, PvpStatusFx)
		"burn":
			cc["burn"] = {"t": secs, "dps": maxf(0.0, float(data.get("dps", 0.0))), "tick": BURN_TICK}
		"brand":
			cc["brand"] = secs
			BrandFx.mark(h, secs)

## The Plague Doctor's kinds on the hero (Hero.pvs). A snare is shortened by tenacity like any hard status and
## missed by a roll in progress.
static func _apply_pd(h: Hero, kind: String, secs: float, data: Dictionary) -> void:
	secs = minf(secs, float(MAX[kind]))
	var k := clampf(float(data.get("k", 1.0)), 0.0, float(MAX_K[kind]))
	if kind == "snare":
		if Dodge.dodging(h) or h.veil_t > 0.0 or unstoppable(h):
			return
		secs *= h.cc_k()
	if secs <= 0.0:
		return
	var cur: Array = h.pvs.get(kind, [0.0, 0.0])
	if kind == "blight":
		h.pvs[kind] = [secs, k]
	else:
		h.pvs[kind] = [maxf(float(cur[0]), secs), maxf(float(cur[1]) if float(cur[0]) > 0.0 else 0.0, k)]
	if kind == "snare":
		h.game.ui.message("Rooted", Color(0.6, 0.95, 0.4))

## Is a status on him now? ("slow" is the shared one in `Hero.cc`; the Plague Doctor's in `Hero.pvs`.)
static func has(h: Hero, kind: String) -> bool:
	if kind == "slow":
		return h.cc.has("slow")
	return h.pvs.has(kind) and float((h.pvs[kind] as Array)[0]) > 0.0

static func strength(h: Hero, kind: String) -> float:
	if kind == "slow":
		return float(h.cc["slow"]["k"]) if h.cc.has("slow") else 0.0
	return float((h.pvs[kind] as Array)[1]) if has(h, kind) else 0.0

## How long his attacks and casts take, harried (Hero._start_attack).
static func act_mult(h: Hero) -> float:
	return 1.0 + strength(h, "harried")

## Drops slows, snares, harrying and Blight (the Plague Doctor's Transfusion). Returns how many it removed.
static func cleanse(h: Hero) -> int:
	var n := 0
	for kind in ["snare", "harried", "blight"]:
		if h.pvs.has(kind):
			h.pvs.erase(kind)
			n += 1
	if h.cc.has("slow"):
		h.cc.erase("slow")
		n += 1
	if h.chill_t > 0.0:
		h.chill_t = 0.0
		n += 1
	return n

## The Demon in his Crucible can't be stopped or moved.
static func unstoppable(h: Hero) -> bool:
	return h.is_demon() and DemonSkills.in_crucible(h)

static func _stop(h: Hero) -> void:
	h.moving = false
	h.path = PackedVector3Array()
	h.target = null
	if h.atk_t >= 0.0:
		h.atk_t = -1.0
		h.atk_skill = ""

static func _word(h: Hero, w: String, c: Color) -> void:
	Fx.number(h.game.world.fx_root, h.global_position + Vector3(0, 2.6, 0), w, c)

## Every frame on the victim's own game (Hero._process, after his own speed is worked out). Returns the speed
## factor the slow leaves him.
static func update(h: Hero, delta: float) -> float:
	var k := 1.0
	for kind in h.pvs.keys():
		var v: Array = h.pvs[kind]
		v[0] = float(v[0]) - delta
		if float(v[0]) <= 0.0:
			h.pvs.erase(kind)
	if has(h, "snare"):
		k = 0.0          # rooted: no walking (acting is still his)
	var cc: Dictionary = h.cc
	if cc.is_empty():
		return k
	if h.dead:
		clear(h)
		return 1.0
	if cc.has("up"):
		var u: Dictionary = cc["up"]
		u["t"] = float(u["t"]) + delta
		var f := clampf(float(u["t"]) / maxf(float(u["dur"]), 0.05), 0.0, 1.0)
		if h.rig != null:
			h.rig.position.y = 4.0 * f * (1.0 - f) * KNOCKUP_H
		if f >= 1.0:
			if h.rig != null:
				h.rig.position.y = 0.0
			h.game.add_shake(0.15)
			cc.erase("up")
	if cc.has("pull"):
		var p: Dictionary = cc["pull"]
		p["t"] = float(p["t"]) + delta
		var f := clampf(float(p["t"]) / maxf(float(p["dur"]), 0.05), 0.0, 1.0)
		var want: Vector3 = (p["from"] as Vector3).lerp(p["to"], 1.0 - pow(1.0 - f, 2.0))
		var step := want - h.global_position
		step.y = 0.0
		h.global_position = h.game.world.move(h.global_position, step, h.radius)
		if f >= 1.0:
			cc.erase("pull")
	if cc.has("fear"):
		var fr: Dictionary = cc["fear"]
		fr["t"] = float(fr["t"]) - delta
		var away: Vector3 = h.global_position - (fr["from"] as Vector3)
		away.y = 0.0
		away = away.normalized() if away.length() > 0.05 else -h.facing()
		h.global_position = h.game.world.move(h.global_position, away * FEAR_SPEED * delta, h.radius)
		h._face(away)
		h.move_amt = 1.0
		h.phase += delta * 9.0
		if float(fr["t"]) <= 0.0:
			cc.erase("fear")
	if cc.has("slow"):
		var s: Dictionary = cc["slow"]
		s["t"] = float(s["t"]) - delta
		k *= 1.0 - float(s["k"])
		if float(s["t"]) <= 0.0:
			cc.erase("slow")
	if cc.has("burn"):
		var b: Dictionary = cc["burn"]
		b["t"] = float(b["t"]) - delta
		b["tick"] = float(b["tick"]) - delta
		if float(b["tick"]) <= 0.0:
			b["tick"] = BURN_TICK
			h.take_hit(float(b["dps"]) * BURN_TICK, h.global_position, "burn", "fire")
		if float(b["t"]) <= 0.0:
			cc.erase("burn")
	if cc.has("brand"):
		cc["brand"] = float(cc["brand"]) - delta
		if float(cc["brand"]) <= 0.0:
			cc.erase("brand")
	return k

## Moving him himself is refused while a drag or fear has him (his input would fight it).
static func held(h: Hero) -> bool:
	return h.cc.has("pull") or h.cc.has("fear") or h.cc.has("up")

static func clear(h: Hero) -> void:
	if h.cc.has("up") and h.rig != null:
		h.rig.position.y = 0.0
	h.cc.clear()
	h.pvs.clear()
	BrandFx.unmark(h)

class_name PvpStatus
extends RefCounted
## Statuses one player puts on another in the Battlegrounds (PvP), and the same effects on the local hero.
##
## Until now only damage reached another player (Net.sv_pvp_hit). A skill that slows, snares or harries a player's
## stand-in (an Enemy with `pvp_pid`) calls `PvpStatus.send(game, enemy, kind, secs, k)`; the server checks it
## (`Battlegrounds.pvp_status`: distance, the kind's ceiling, diminishing returns) and sends it to that player's
## game (`Net.cl_pvp_status`), which applies it to the local hero (`apply`). The hero keeps them in `Hero.pvs`
## ({kind: [seconds, strength]}), ticked by `update`, read by `speed_mult` (walking) and `act_mult` (how long attacks
## and casts take). A cleanse (`cleanse`) drops them.
##
## Kinds:
##   slow     walk speed x (1 - k) (k at most 0.6)
##   snare    rooted: can't walk, can still attack and cast (at most 1.0 s)
##   harried  attacks and casts take 1 + k longer (k at most 0.35)
##   reveal   seen through concealment (Fog of the Forgotten) for its time
##   blight   a stack count in k (the Plague Doctor's Blight; Fever at 3), for the HUD and the glow
## Diminishing returns on the same player within DR_WINDOW s, per kind: 100%, then 50%, then immune for DR_IMMUNE s
## (slow and snare only; reveal and blight have none).

const MAX := {"slow": 3.0, "snare": 1.0, "harried": 3.0, "reveal": 4.0, "blight": 6.0}
const MAX_K := {"slow": 0.6, "snare": 1.0, "harried": 0.35, "reveal": 1.0, "blight": 3.0}
const DR_KINDS := ["slow", "snare"]
const DR_WINDOW := 8.0
const DR_IMMUNE := 3.0

## Clamp what a client asked for to what the kind allows.
static func clamp_status(kind: String, secs: float, k: float) -> Array:
	if not MAX.has(kind):
		return []
	return [clampf(secs, 0.0, float(MAX[kind])), clampf(k, 0.0, float(MAX_K[kind]))]

## Diminishing returns, kept per target by whoever deals them (the server): `dr` = {kind: [count, window_left,
## immune_left]}. Returns the scale for this application (1, 0.5 or 0).
static func dr_scale(dr: Dictionary, kind: String) -> float:
	if not DR_KINDS.has(kind):
		return 1.0
	var e: Array = dr.get(kind, [0, 0.0, 0.0])
	if float(e[2]) > 0.0:
		return 0.0
	var n: int = int(e[0]) if float(e[1]) > 0.0 else 0
	var s := 1.0 if n == 0 else (0.5 if n == 1 else 0.0)
	n += 1
	e = [n, DR_WINDOW, DR_IMMUNE if n >= 3 else 0.0]
	dr[kind] = e
	return s

static func dr_tick(dr: Dictionary, delta: float) -> void:
	for k in dr.keys():
		var e: Array = dr[k]
		e[1] = maxf(float(e[1]) - delta, 0.0)
		e[2] = maxf(float(e[2]) - delta, 0.0)
		if float(e[1]) <= 0.0 and float(e[2]) <= 0.0:
			dr.erase(k)

# ---------------------------------------------------------------- the hero
static func apply(h: Hero, kind: String, secs: float, k: float) -> void:
	var c := clamp_status(kind, secs, k)
	if c.is_empty() or h.dead or float(c[0]) <= 0.0:
		return
	var cur: Array = h.pvs.get(kind, [0.0, 0.0])
	if kind == "blight":
		h.pvs[kind] = [float(c[0]), float(c[1])]
	else:
		h.pvs[kind] = [maxf(float(cur[0]), float(c[0])), maxf(float(cur[1]) if float(cur[0]) > 0.0 else 0.0, float(c[1]))]
	if kind == "snare" or kind == "slow":
		h.game.ui.message({"snare": "Rooted", "slow": "Slowed"}[kind], Color(0.6, 0.95, 0.4))

static func update(h: Hero, delta: float) -> void:
	for kind in h.pvs.keys():
		var v: Array = h.pvs[kind]
		v[0] = float(v[0]) - delta
		if float(v[0]) <= 0.0:
			h.pvs.erase(kind)

static func has(h: Hero, kind: String) -> bool:
	return h.pvs.has(kind) and float((h.pvs[kind] as Array)[0]) > 0.0

static func strength(h: Hero, kind: String) -> float:
	return float((h.pvs[kind] as Array)[1]) if has(h, kind) else 0.0

static func speed_mult(h: Hero) -> float:
	if has(h, "snare"):
		return 0.0
	return 1.0 - strength(h, "slow")

static func act_mult(h: Hero) -> float:
	return 1.0 + strength(h, "harried")

## Drops slows, snares, harrying and Blight (Transfusion). Returns how many it removed.
static func cleanse(h: Hero) -> int:
	var n := 0
	for kind in ["slow", "snare", "harried", "blight"]:
		if h.pvs.has(kind):
			h.pvs.erase(kind)
			n += 1
	if h.chill_t > 0.0:
		h.chill_t = 0.0
		n += 1
	return n

# ---------------------------------------------------------------- sending
## A skill's status on a foe: a player's stand-in goes to the server; a monster gets the nearest thing it has
## (slow = chill, snare = a short stun, harried = a light chill). Returns true when it went to a player.
static func send(game: Node, e: Enemy, kind: String, secs: float, k: float) -> bool:
	if e == null or not is_instance_valid(e) or e.dead:
		return false
	if e.pvp_pid > 0:
		if game.net != null and game.net.active:
			game.net.send_pvp_status(e.pvp_pid, kind, secs, k)
		return true
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

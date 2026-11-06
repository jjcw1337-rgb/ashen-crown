class_name DougSkills
extends RefCounted
## Doug's skills (docs/characters/doug.md; tuning in Data.SKILLS "cls": "doug", timing by SkillSpec): the gameplay.
## Everything seen is an fx event drawn by DougFx (on his puppet for partners and PvP opponents too). State lives on
## the hero (meta "doug": pies in flight, peels on the ground, the slide, the bounce, the double, the car).
##   pie     Cream Pie: a lobbed pie; the first foe near where it lands takes the hit and is Pied
##   peels   Banana Peels: three on the ground ahead, each a slip for the first to step on it
##   slide   Pratfall Slide: 7 m belly-slide, shoving and hitting foes in the way
##   doppel  Doppel-Doug: he is unseen for 1.8 s (monsters lose him, partners see him fade) while a double runs off
##   juggle  Pin Juggle: five flaming pins, each bouncing on to two more foes
##   bounce  Big Top Bounce: a leap to the cursor and a belly-flop that launches
##   car     Clown Car: 5 s of driving, ramming; then six mini clowns pie the nearest foes
## Crowd control on another player (Battlegrounds PvP: an Enemy stand-in with pvp_pid) goes to the server as a
## Net.send_pvp_effect; on monsters it's Enemy.stun / slow (host-relayed like everyone's).

const PIE_FLIGHT := 0.45
const PIE_R := 1.4
const PIED_LOCK := 6.0
const PEEL_LIFE := 8.0
const PEEL_MAX := 6
const PEEL_R := 0.7
const SLIDE_LEN := 7.0
const HIDE_SECS := 1.8
const DOUBLE_SECS := 3.0
const PIN_BOUNCES := 2
const BOUNCE_R := 3.0
const CAR_SECS := 5.0
const CAR_SPEED := 2.3          # times his run
const MINIS := 6

static func st(h: Hero) -> Dictionary:
	if not h.has_meta("doug"):
		h.set_meta("doug", {"pies": [], "peels": [], "pied": {}, "slide": {}, "bounce": {}, "car_t": 0.0, "rammed": {}, "pins": []})
	return h.get_meta("doug")

static func can_cast(h: Hero, id: String, _aim: Vector3) -> bool:
	if id == "car" and float(st(h)["car_t"]) > 0.0:
		return false
	return true

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var s := st(h)
	match id:
		"pie", "peels", "doppel", "juggle", "car":
			h._start_attack(id, id)
		# a run's skills (Data.RUN_SKILLS), on his own moves
		"u_barrage":
			h._start_attack("pie", "u_barrage")
		"u_bonanza":
			h._start_attack("peels", "u_bonanza")
		"u_cannon":
			h._start_attack("bounce", "u_cannon")
			var to2 := aim
			to2.y = h.global_position.y
			var off2 := to2 - h.global_position
			if off2.length() > 14.0:
				to2 = h.global_position + off2.normalized() * 14.0
			to2 = h.game.world.free_spot_near(to2, 1.0)
			s["bounce"] = {"from": h.global_position, "to": to2}
			h.fx("bounce", "mark", {"p": h.global_position, "q": to2, "x": h.atk_dur})
		"slide":
			h._start_attack("slide", "slide")
			s["slide"] = {"from": h.global_position, "dir": h.aim_dir(), "hit": {}}
		"bounce":
			h._start_attack("bounce", "bounce")
			var to := aim
			to.y = h.global_position.y
			var off := to - h.global_position
			if off.length() > 10.0:
				to = h.global_position + off.normalized() * 10.0
			to = h.game.world.free_spot_near(to, 1.0)
			s["bounce"] = {"from": h.global_position, "to": to}
			h.fx("bounce", "mark", {"p": h.global_position, "q": to, "x": h.atk_dur})
	s["aim"] = aim

static func impact(h: Hero) -> bool:
	var s := st(h)
	match h.atk_skill:
		"pie":
			var to: Vector3 = s.get("aim", h.global_position + h.aim_dir() * 6.0)
			var off := to - h.global_position
			off.y = 0
			if off.length() > 12.0:
				to = h.global_position + off.normalized() * 12.0
			(s["pies"] as Array).append({"to": to, "t": PIE_FLIGHT})
			h.fx("pie", "throw", {"p": h.global_position + Vector3(0, 1.2, 0), "q": to, "x": PIE_FLIGHT})
		"peels":
			var fwd := h.aim_dir()
			var ps := PackedVector3Array()
			for k in 3:
				var a := deg_to_rad(-25.0 + 25.0 * k)
				var d := fwd.rotated(Vector3.UP, a) * randf_range(3.0, 6.0)
				var p: Vector3 = h.game.world.free_spot_near(h.global_position + d, 0.6)
				(s["peels"] as Array).append({"p": p, "t": PEEL_LIFE})
				ps.append(p)
			while (s["peels"] as Array).size() > PEEL_MAX:
				var old: Dictionary = (s["peels"] as Array).pop_front()
				h.fx("peels", "gone", {"p": old["p"]})
			h.fx("peels", "land", {"ps": ps, "x": PEEL_LIFE})
		"slide":
			h.fx("slide", "honk", {"p": h.global_position, "d": (s["slide"] as Dictionary).get("dir", h.aim_dir())})
		"doppel":
			var to: Vector3 = s.get("aim", h.global_position + h.aim_dir() * 8.0)
			var dir := to - h.global_position
			dir.y = 0
			dir = dir.normalized() if dir.length() > 0.1 else h.aim_dir()
			h.hidden_t = HIDE_SECS
			s["double"] = {"p": h.global_position, "d": dir, "t": DOUBLE_SECS, "popped": false}
			h.fx("doppel", "start", {"p": h.global_position, "d": dir, "x": HIDE_SECS, "r": DOUBLE_SECS})
		"juggle":
			(s["pins"] as Array).append_array([0.0, 0.14, 0.28, 0.42, 0.56])
		"bounce":
			var b: Dictionary = s["bounce"]
			if not b.is_empty():
				h.global_position = b["to"]
			var hit := []
			for e in h.game.enemies_near(h.global_position, BOUNCE_R):
				h._hit_enemy(e, 1.8, 2.0, "bounce")
				_cc(h, e, "quake", 0.8)
				hit.append(e)
			h.fx("bounce", "flop", {"p": h.global_position, "t": hit})
			h.game.add_shake(0.35)
			s["bounce"] = {}
		"car":
			s["car_t"] = CAR_SECS
			s["rammed"] = {}
			h.fx("car", "start", {"p": h.global_position, "x": CAR_SECS})
		"u_barrage":
			var at: Vector3 = s.get("aim", h.global_position + h.aim_dir() * 6.0)
			var off := at - h.global_position
			off.y = 0
			if off.length() > 12.0:
				at = h.global_position + off.normalized() * 12.0
			var foes: Array = h.game.enemies_near(at, 5.0).filter(func(e): return not e.dead)
			var n := 6 + int(h.talent("barrage_more"))
			for i in n:
				var to: Vector3
				if i < foes.size():
					to = foes[i].global_position
				else:
					var a := TAU * float(i) / n
					to = at + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 3.5)
				var t := PIE_FLIGHT + i * 0.05
				(s["pies"] as Array).append({"to": to, "t": t, "src": "u_barrage"})
				h.fx("pie", "throw", {"p": h.global_position + Vector3(0, 1.2, 0), "q": to, "x": t, "r": 1.1})
		"u_bonanza":
			# a full ring round him (no World.rng: that is the map's generator); a blocked spot comes inward until free
			var ps := PackedVector3Array()
			var w: Node = h.game.world
			var c := h.global_position
			var spin := randf() * TAU
			for k in 8:
				var a2 := spin + TAU * float(k) / 8.0
				var p := c
				for rr in [3.2, 2.6, 2.0, 1.4]:
					var q := c + Vector3(cos(a2), 0, sin(a2)) * float(rr)
					if not w.is_blocked(q.x, q.z):
						p = q
						break
				p.y = w.height_at(p.x, p.z)
				(s["peels"] as Array).append({"p": p, "t": PEEL_LIFE, "bonanza": true})
				ps.append(p)
			while (s["peels"] as Array).size() > PEEL_MAX + 8:
				var old: Dictionary = (s["peels"] as Array).pop_front()
				h.fx("peels", "gone", {"p": old["p"]})
			h.fx("peels", "land", {"ps": ps, "x": PEEL_LIFE, "q": c + Vector3(0, 1.1, 0)})
		"u_cannon":
			var b2: Dictionary = s["bounce"]
			if not b2.is_empty():
				h.global_position = b2["to"]
			var r := CANNON_R * (1.0 + h.talent("cannon_r") / 100.0)
			var hit2 := []
			for e in h.game.enemies_near(h.global_position, r):
				h._hit_enemy(e, 2.6, 2.4, "u_cannon")
				_cc(h, e, "quake", 1.0)
				hit2.append(e)
			h.fx("bounce", "flop", {"p": h.global_position, "t": hit2})
			h.fx("u_cannon", "boom", {"p": h.global_position, "r": r})
			h.game.add_shake(0.5)
			s["bounce"] = {}
		_:
			return false
	return true

const CANNON_R := 4.5

## A crowd-control effect on a foe: a monster stunned or slowed, another player told through the server.
static func _cc(h: Hero, e, kind: String, secs: float) -> void:
	if not is_instance_valid(e) or e.dead:
		return
	if int(e.get("pvp_pid")) > 0:
		h.game.net.send_pvp_effect(int(e.pvp_pid), kind, h.global_position)
		return
	match kind:
		"slip", "quake":
			e.stun(secs)
		"pied":
			e.stun(0.4)
			e.slow(secs, 0.5)
		"slow":
			e.slow(secs, 0.45)

static func update(h: Hero, delta: float) -> void:
	if not h.has_meta("doug"):
		return
	var s := st(h)
	# pies in flight: the first foe near where it lands (a target can't be Pied twice in PIED_LOCK)
	var pies: Array = s["pies"]
	for i in range(pies.size() - 1, -1, -1):
		var pie: Dictionary = pies[i]
		pie["t"] = float(pie["t"]) - delta
		if float(pie["t"]) > 0.0:
			continue
		pies.remove_at(i)
		var best = null
		var bd := PIE_R
		for e in h.game.enemies_near(pie["to"], PIE_R + 1.0):
			var d: float = Vector2(e.global_position.x - pie["to"].x, e.global_position.z - pie["to"].z).length()
			if d < bd:
				bd = d
				best = e
		h.fx("pie", "splat", {"p": pie["to"], "t": [best] if best != null else []})
		if best != null:
			h._hit_enemy(best, 0.8 if str(pie.get("src", "")) == "u_barrage" else 1.2, 0.0, str(pie.get("src", "pie")))
			var key := str(best.get_instance_id())
			var now := Time.get_ticks_msec() / 1000.0
			if now - float((s["pied"] as Dictionary).get(key, -99.0)) > PIED_LOCK:
				s["pied"][key] = now
				_cc(h, best, "pied", 2.0)
	# peels on the ground: the first foe that steps on one slips (a peel is gone once it's slipped on, or expired)
	var peels: Array = s["peels"]
	for i in range(peels.size() - 1, -1, -1):
		var pl: Dictionary = peels[i]
		pl["t"] = float(pl["t"]) - delta
		var gone := float(pl["t"]) <= 0.0
		if not gone:
			for e in h.game.enemies_near(pl["p"], PEEL_R + 0.5):
				if Vector2(e.global_position.x - pl["p"].x, e.global_position.z - pl["p"].z).length() < PEEL_R + e.radius * 0.5:
					_cc(h, e, "slip", 1.0)
					if pl.has("bonanza"):
						e.set_meta("slipped_until", Time.get_ticks_msec() + 4000)     # (Banana Bonanza: the next blow doubles)
					h.fx("peels", "slip", {"p": pl["p"], "t": [e]})
					gone = true
					break
		if gone:
			peels.remove_at(i)
			if float(pl["t"]) <= 0.0:
				h.fx("peels", "gone", {"p": pl["p"]})
	# the slide: along its line, the foes in the way shoved and struck once
	var sl: Dictionary = s["slide"]
	if not sl.is_empty():
		if h.atk_skill == "slide" and h.atk_t >= 0.0:
			var a := h.atk_t / maxf(h.atk_dur, 0.01)
			var want: Vector3 = sl["from"] + (sl["dir"] as Vector3) * SLIDE_LEN * smoothstep(0.08, 0.75, a)
			var step := want - h.global_position
			step.y = 0
			h.global_position = h.game.world.move(h.global_position, step, h.radius)
			for e in h.game.enemies_near(h.global_position, 1.3):
				var k := str(e.get_instance_id())
				if not (sl["hit"] as Dictionary).has(k):
					sl["hit"][k] = true
					h._hit_enemy(e, 0.9, 3.0, "slide")
		else:
			s["slide"] = {}
	# the bounce: the arc to where he lands (the impact frame puts him down)
	var bo: Dictionary = s["bounce"]
	if not bo.is_empty() and h.atk_skill == "bounce" and h.atk_t >= 0.0:
		var a2 := clampf((h.atk_t / maxf(h.atk_dur, 0.01) - 0.15) / 0.63, 0.0, 1.0)
		var p: Vector3 = (bo["from"] as Vector3).lerp(bo["to"], a2)
		h.global_position = Vector3(p.x, h.global_position.y, p.z)
	# the double: runs on; a monster that reaches it pops it (a confetti burst that slows those round it)
	if s.has("double"):
		var dbl: Dictionary = s["double"]
		dbl["t"] = float(dbl["t"]) - delta
		dbl["p"] = h.game.world.move(dbl["p"], (dbl["d"] as Vector3) * 4.2 * delta, 0.4)
		var pop := float(dbl["t"]) <= 0.0
		for e in h.game.enemies_near(dbl["p"], 1.4):
			pop = true
		if pop:
			for e in h.game.enemies_near(dbl["p"], 3.0):
				_cc(h, e, "slow", 1.5)
			h.fx("doppel", "pop", {"p": dbl["p"]})
			s.erase("double")
	# the pins: thrown one by one, each landing on the foe nearest the cursor, then bouncing on
	var pins: Array = s["pins"]
	if not pins.is_empty():
		for i in range(pins.size() - 1, -1, -1):
			pins[i] = float(pins[i]) - delta
			if float(pins[i]) <= 0.0:
				pins.remove_at(i)
				_pin(h, s.get("aim", h.global_position + h.aim_dir() * 6.0))
	# the car: he drives (Hero moves him at CAR_SPEED, car_mult), rams whatever he meets, then the mini clowns
	if float(s["car_t"]) > 0.0:
		s["car_t"] = float(s["car_t"]) - delta
		for e in h.game.enemies_near(h.global_position, 1.6):
			var k2 := str(e.get_instance_id())
			var last := float((s["rammed"] as Dictionary).get(k2, -99.0))
			var now2 := Time.get_ticks_msec() / 1000.0
			if now2 - last > 0.8:
				s["rammed"][k2] = now2
				h._hit_enemy(e, 1.4, 4.0, "car")
				h.fx("car", "ram", {"p": e.global_position})
		if float(s["car_t"]) <= 0.0:
			_minis(h)

static func _pin(h: Hero, aim: Vector3) -> void:
	var first = null
	var bd := 3.5
	for e in h.game.enemies_near(aim, 4.0):
		var d: float = e.global_position.distance_to(aim)
		if d < bd:
			bd = d
			first = e
	var ps := PackedVector3Array([h.global_position + Vector3(0, 1.3, 0)])
	var hit := []
	if first == null:
		ps.append(aim)
	else:
		var cur = first
		for b in PIN_BOUNCES + 1:
			if cur == null:
				break
			hit.append(cur)
			ps.append(cur.global_position + Vector3(0, 1.0, 0))
			h._hit_enemy(cur, 0.6, 0.0, "juggle")
			var nxt = null
			var nd := 6.0
			for e in h.game.enemies_near(cur.global_position, 6.0):
				if hit.has(e):
					continue
				var d2: float = e.global_position.distance_to(cur.global_position)
				if d2 < nd:
					nd = d2
					nxt = e
			cur = nxt
	h.fx("juggle", "pin", {"ps": ps, "t": hit})

## The car bursts: six mini clowns, each to one of the nearest foes, a pie in the face.
static func _minis(h: Hero) -> void:
	var foes: Array = h.game.enemies_near(h.global_position, 12.0)
	foes.sort_custom(func(a, b) -> bool: return a.global_position.distance_to(h.global_position) < b.global_position.distance_to(h.global_position))
	var tgt := foes.slice(0, MINIS)
	h.fx("car", "burst", {"p": h.global_position, "t": tgt})
	var s := st(h)
	for e in tgt:
		h._hit_enemy(e, 0.8, 0.0, "car")
		var key := str(e.get_instance_id())
		var now := Time.get_ticks_msec() / 1000.0
		if now - float((s["pied"] as Dictionary).get(key, -99.0)) > PIED_LOCK:
			s["pied"][key] = now
			_cc(h, e, "pied", 2.0)

## The car's speed on him (Hero's movement multiplies by it) and its unstoppability (no stuns, no slows).
static func car_mult(h: Hero) -> float:
	return CAR_SPEED if h.has_meta("doug") and float(st(h)["car_t"]) > 0.0 else 1.0

static func driving(h: Hero) -> bool:
	return h.has_meta("doug") and float(st(h)["car_t"]) > 0.0

static func rooted(h: Hero) -> bool:
	return h.atk_skill in ["slide", "bounce"] and h.atk_t >= 0.0

static func clear(h: Hero) -> void:
	if h.has_meta("doug"):
		for pl in st(h)["peels"]:
			h.fx("peels", "gone", {"p": pl["p"]})
		h.remove_meta("doug")
	h.hidden_t = 0.0

static func died(h: Hero) -> void:
	if h.has_meta("doug"):
		var s := st(h)
		s["car_t"] = 0.0
		s["slide"] = {}
		s["bounce"] = {}
		s["pins"] = []
	h.hidden_t = 0.0

static func sound(h: Hero, skill: String, at: float) -> bool:
	match skill:
		"pie": Sfx.play_synced("swing_light", at, -2.0)
		"peels": Sfx.play_synced("swing_light", at, -4.0)
		"slide": Sfx.play("swing_heavy" if Sfx.bank.has("swing_heavy") else "swing_light", -4.0, 0.8)
		"juggle": Sfx.play_synced("swing_light", at, -3.0)
		"bounce": Sfx.play_synced("doug_flop", at, 0.0)
		"doppel", "car": return true
		_: return false
	return true

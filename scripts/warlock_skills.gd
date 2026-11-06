class_name WarlockSkills
extends RefCounted
## The Warlock's skills (tuning in Data.SKILLS, effects in WarlockFx). ClassSkills calls in; see class_skills.gd.
##  - Drain Life (Q, "drain"): a channel, not an attack: a beam latches onto the foe nearest the cursor and forks
##    to the ones near it; every 0.3 s each loses life and he gains part of it. It runs while Q is held (at least
##    DRAIN_MIN s; past that it costs mana); any move, target click or other skill ends it (Hero.end_drain).
##    Hero._process calls `update_drain` where the attack would update.
##  - Blight Bolt (E, "blight"): a skull that bursts into a plague pool where it lands (WarlockFx flies it and
##    calls Hero._blight_burst); the pool rots whatever stands in it.
##  - Shackles (R, "shackles"): everything near is hit and bound in place.
##  - Fel Covenant (F, "covenant"): +40% damage for 12 s, and Drain Life forks further and heals double.
## His state on the hero: drain_t, drain_tick, drain_main, drain_victims, drain_heal(_t), blights, covenant_t.

const DRAIN_RANGE := 11.0     # how far away a beam can latch on
const DRAIN_LEASH := 13.0     # a latched victim that gets further away than this breaks free
const DRAIN_FORK := 5.5       # forks reach enemies this close to the main victim
const DRAIN_MIN := 1.0        # a tap of Q still channels this long

static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	if id == "drain" and drain_pick(h, aim) == null:
		h.game.ui.message("No enemy in reach", Color(0.8, 0.8, 0.8))
		return false
	return true

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	match id:
		"drain":
			drain_start(h, drain_pick(h, aim))
		"blight":
			h._start_attack("cast", "blight")
			h.atk_dur = 0.45 * Data.attack_pace(h.cls)
		"shackles":
			h._start_attack("cast", "shackles")
			h.atk_dur = 0.5 * Data.attack_pace(h.cls)
		"covenant":
			h._start_attack("cast", "covenant")
			h.atk_dur = 0.6 * Data.attack_pace(h.cls)
		# a run's skills (Data.RUN_SKILLS)
		"w_corruption", "w_hellfire":
			var to := (aim - h.global_position) * Vector3(1, 0, 1)
			h.atk_aim = h.global_position + to.limit_length(14.0)
			h._start_attack("cast", id)
		"w_soulrend":
			h._start_attack("cast", "w_soulrend")
			h.atk_dur = 0.5 * Data.attack_pace(h.cls)

## The impact frame of one of his skills (Hero then refreshes the stats); false when it isn't his.
static func impact(h: Hero) -> bool:
	var fwd := h.aim_dir()
	match h.atk_skill:
		"blight":
			var dir := fwd      # toward the pointer as it was when he cast
			# Twin Skulls: two, a little apart
			h.fx("blight", "bolt", {"d": dir, "x": h.talent("blight_twin") > 0.0})
		"shackles":
			var reach_s := 7.0 + h.talent("shackle_range")
			var bind_t := 2.5 + h.talent("shackle_dur")
			var bound: Array = h.game.enemies_near(h.global_position, reach_s)
			h.fx("shackles", "impact", {"r": reach_s, "x": bind_t, "t": bound})
			for e in bound:
				h._hit_enemy(e, 0.8, 0.0)
				if not e.dead:
					e.stun(bind_t)
		"covenant":
			h.buff_t = 12.0 + h.talent("buff_dur")
			h.covenant_t = h.buff_t
			h.fx("covenant", "impact")
		"w_corruption":
			var g := _ground(h, h.atk_aim)
			var r := CORRUPT_R * (1.0 + h.talent("corrupt_r") / 100.0)
			var hit: Array = h.game.enemies_near(g, r).filter(func(e): return not e.dead)
			h.fx("w_corruption", "impact", {"p": g, "r": r, "t": hit})
			for e in hit:
				h._hit_enemy(e, 0.4, 0.0, "w_corruption")
				if not e.dead:
					e.ignite(_weapon(h) * 0.45 * h.dmg_mult("w_corruption"), 6.0, "fel")
		"w_soulrend":
			var foes: Array = h.game.enemies_near(h.global_position, REND_R).filter(func(e): return not e.dead)
			h.fx("w_soulrend", "impact", {"r": REND_R, "t": foes})
			var healed := 0
			for e in foes:
				h._hit_enemy(e, 0.9, 0.0, "w_soulrend")
				if healed < 5:
					healed += 1
					h.life = minf(h.max_life, h.life + h.max_life * 0.04 * (1.0 + h.talent("rend_heal") / 100.0))
		"w_hellfire":
			var g2 := _ground(h, h.atk_aim)
			var n := 3 + int(h.talent("hellfire_more"))
			h.fx("w_hellfire", "impact", {"p": g2, "n": n})
			for i in n:
				var at := g2 + Vector3(randf_range(-1.6, 1.6), 0, randf_range(-1.6, 1.6))
				h.get_tree().create_timer(0.3 + i * 0.3).timeout.connect(func():
					if not is_instance_valid(h) or h.dead or h.game == null or h.game.world == null:
						return
					Hero.striker = h
					for e in h.game.enemies_near(at, HELLFIRE_R):
						if not e.dead:
							h._hit_enemy(e, 0.7, 0.2, "w_hellfire")
							if not e.dead:
								e.ignite(_weapon(h) * 0.25 * h.dmg_mult("w_hellfire"), 3.0, "fel"))
		_:
			return false
	return true

const CORRUPT_R := 3.2
const REND_R := 6.0
const HELLFIRE_R := 3.0

static func _ground(h: Hero, p: Vector3) -> Vector3:
	return Vector3(p.x, h.game.world.height_at(p.x, p.z), p.z)

static func _weapon(h: Hero) -> float:
	return (h.dmg_min + h.dmg_max) * 0.5 * h.buff_mult()

# ---------------------------------------------------------------- Drain Life
## The enemy Drain Life latches onto: the one nearest the aim point, else the nearest in reach.
static func drain_pick(h: Hero, aim: Vector3):
	var best = null
	var bd := 3.0
	for e in h.game.enemies_near(aim, 3.0):
		var d: float = Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length()
		if d < bd and e.global_position.distance_to(h.global_position) <= DRAIN_RANGE:
			bd = d
			best = e
	if best == null:
		best = _drain_nearest(h, h.global_position, DRAIN_RANGE, null)
	return best

static func _drain_nearest(h: Hero, p: Vector3, r: float, skip):
	var best = null
	var bd := r
	for e in h.game.enemies_near(p, r):
		if e == skip:
			continue
		var d: float = e.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best

static func _drain_valid(h: Hero, e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead and e.global_position.distance_to(h.global_position) <= DRAIN_LEASH

## The main victim first, then the enemies the beam forks to (nearest the main victim).
static func drain_victims(h: Hero) -> Array:
	if not _drain_valid(h, h.drain_main):
		return []
	var main = h.drain_main
	var mp: Vector3 = main.global_position
	var near: Array = h.game.enemies_near(mp, DRAIN_FORK).filter(func(e): return e != main)
	near.sort_custom(func(a, b): return a.global_position.distance_to(mp) < b.global_position.distance_to(mp))
	var forks := (5 if h.covenant_t > 0.0 else 3) + int(h.talent("drain_fork"))
	return [main] + near.slice(0, forks)

static func drain_start(h: Hero, foe) -> void:
	h.drain_t = 0.0
	h.drain_tick = 0.1
	h.drain_main = foe
	h.target = null
	h.path = PackedVector3Array()
	h.moving = false
	h.drain_heal = 0.0
	h.drain_heal_t = 0.0
	h._face(foe.global_position - h.global_position)
	h.drain_victims = [foe]
	h.fx("drain", "start", {"t": h.drain_victims})
	h.game.add_shake(0.08)

static func end_drain(h: Hero) -> void:
	var was := h.drain_t >= 0.0
	h.drain_t = -1.0
	h.drain_main = null
	h.drain_victims = []
	if was:
		h.fx("drain", "end")
	_show_drain_heal(h)

## Healing from the beam shows as one green "+N" about once a second rather than every tick.
static func _show_drain_heal(h: Hero) -> void:
	if h.drain_heal >= 1.0 and h.game and h.game.world:
		Fx.number(h.game.world.fx_root, h.global_position + Vector3(0, 2.3, 0), "+%d" % int(h.drain_heal), Color(0.45, 1.0, 0.4))
	h.drain_heal = 0.0
	h.drain_heal_t = 0.0

## Drain Life: every 0.3 s each victim loses life and the Warlock gains some of it back.
## If the main victim dies the beam jumps to the nearest enemy still in reach.
static func update_drain(h: Hero, delta: float) -> void:
	h.drain_t += delta
	if not _drain_valid(h, h.drain_main):
		var from: Vector3 = h.drain_main.global_position if h.drain_main != null and is_instance_valid(h.drain_main) else h.global_position
		h.drain_main = _drain_nearest(h, from, DRAIN_FORK, null)
		if not _drain_valid(h, h.drain_main):
			h.drain_main = _drain_nearest(h, h.global_position, DRAIN_RANGE, null)
		if h.drain_main == null:
			end_drain(h)
			return
	if h.drain_t >= DRAIN_MIN and not h.game.skill_held("drain"):
		end_drain(h)
		return
	h._face_smooth(h.drain_main.global_position - h.global_position, delta)
	h.drain_tick -= delta
	if h.drain_tick > 0.0:
		return
	h.drain_tick = 0.3
	if h.drain_t >= DRAIN_MIN:
		# past the first second the channel costs mana (about 6.5 a second)
		if h.mana < 2.0:
			h.game.ui.message("Not enough mana", Color(0.4, 0.5, 1.0))
			end_drain(h)
			return
		h.mana -= 2.0 * (1.0 - h.talent("cost:drain") / 100.0)
	var dmg := (6.0 + h.level * 2.4 + (h.dmg_min + h.dmg_max) * 0.6) * 0.3 * h.buff_mult() * h.dmg_mult("drain")
	var heal := 0.0
	drain_victims_changed(h)
	var victims: Array = h.drain_victims
	for i in victims.size():
		var e = victims[i]
		e.dmg_tint = Color(0.55, 1.0, 0.45)
		# the main victim is dragged a little toward the Warlock
		var dealt: float = e.take_damage(dmg * (1.0 if i == 0 else 0.6), 0.0, h.global_position, -0.25 if i == 0 else 0.0, false)
		e.dmg_tint = Color(0, 0, 0, 0)
		heal += dealt * (0.3 if i == 0 else 0.15)
	h.fx("drain", "tick")
	if h.covenant_t > 0.0:
		heal *= 2.0
	heal *= 1.0 + h.talent("drain_heal") / 100.0
	# Soul Glut: what would heal past full life fills mana instead
	if h.talent("drain_glut") > 0.0 and h.life + heal > h.max_life:
		h.mana = minf(h.max_mana, h.mana + (h.life + heal - h.max_life) * h.talent("drain_glut") / 100.0)
	h.life = minf(h.max_life, h.life + heal)
	h.drain_heal += heal
	h.drain_heal_t += 0.3
	if h.drain_heal_t >= 0.9:
		_show_drain_heal(h)
	h.stats_changed.emit()

## The beam's victims this frame (the main one and its forks); when the set changes, everyone is told
## (a "victims" event, never more often than the enemies move in and out of the fork's reach).
static func drain_victims_changed(h: Hero) -> void:
	if h.drain_t < 0.0:
		return
	var now := drain_victims(h)
	if now != h.drain_victims:
		h.drain_victims = now
		h.fx("drain", "victims", {"t": now})

# ---------------------------------------------------------------- Blight Bolt
## Blight Bolt bursts where it lands (WarlockFx.update flies it): a plague pool that rots whatever stands in it.
static func blight_burst(h: Hero, p: Vector3) -> void:
	var g := Vector3(p.x, h.game.world.height_at(p.x, p.z), p.z)
	var rad := 3.0 * (1.0 + h.talent("blight_size") / 100.0)
	var dur := 4.0 + h.talent("blight_dur")
	h.fx("blight", "burst", {"p": g, "r": rad, "x": dur})
	h.blights.append({"pos": g, "t": dur, "tick": 0.5, "r": rad})
	h.game.add_shake(0.18)
	var nd := (14.0 + h.level * 4.0 + (h.dmg_min + h.dmg_max) * 0.35) * h.buff_mult() * h.dmg_mult("blight")
	for e in h.game.enemies_near(g, rad):
		e.take_damage(nd, 0.0, g, 0.8, false)

## Plague pools rot whatever stands in them every half second.
static func _update_blights(h: Hero, delta: float) -> void:
	for bl in h.blights.duplicate():
		bl["t"] -= delta
		bl["tick"] -= delta
		if bl["t"] <= 0.0:
			h.blights.erase(bl)
			continue
		if bl["tick"] <= 0.0:
			bl["tick"] = 0.5
			var nd := (4.0 + h.level * 1.3 + (h.dmg_min + h.dmg_max) * 0.12) * h.buff_mult() * h.dmg_mult("blight")
			for e in h.game.enemies_near(bl["pos"], float(bl.get("r", 3.0))):
				e.take_damage(nd, 0.0, bl["pos"], 0.0, false)

# ---------------------------------------------------------------- housekeeping
static func update(h: Hero, delta: float) -> void:
	h.covenant_t = maxf(0.0, h.covenant_t - delta)
	_update_blights(h, delta)

static func rooted(_h: Hero) -> bool:
	return false

static func clear(h: Hero) -> void:
	end_drain(h)
	WarlockFx.clear(h)
	h.blights.clear()
	h.covenant_t = 0.0

static func died(h: Hero) -> void:
	end_drain(h)

static func sound(_h: Hero, skill: String, at: float) -> bool:
	if skill == "blight":
		Sfx.play_synced("blight_cast", at, -2.0)
		return true
	return false

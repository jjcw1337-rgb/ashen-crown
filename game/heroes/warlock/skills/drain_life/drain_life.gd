class_name DrainLife
extends WarlockSpell
## Drain Life ("drain"): a channel, not an attack. A beam latches onto the foe nearest the pointer and forks to the
## ones near it; every beat each loses life and she gains part of it back. It runs while its key is held (at least
## min_s; past that each beat costs mana); a move, a click, another skill, a dodge or death ends it
## (Hero.end_channel). If the foe it holds dies or breaks away, it jumps to the nearest one still in reach.
## Split as every skill of hers is:
##   her own game holds the channel (Hero.channel_t, `channel` every frame where an attack would update): the key,
##     the mana, turning to the foe, and the "start" and "end" events; it makes the "latch" (and "end") for the rules;
##   the rules (`main`, `victims`, `beat`: here, or on the match server's copy of her) pick the foes and drain them
##     each beat, show the beams' "victims" and "tick", and `give` her what the beat drank: her own game adds
##     the Covenant's and her rites' more, heals her and shows a green "+N" about once a second.
## Codex "k": leash (metres before a held foe breaks free), fork_r (metres from the held foe the forks reach), forks,
## first and beat (seconds to the first beat and between them), min_s, mana (a beat, past min_s), fork_dmg (% of the
## beat on a fork), heal and fork_heal (% of what each drains), gorge_at (% life below which Gorge doubles it), drag.

var main = null            # the foe the beam holds (her own game: the one she turns to; the rules: the one drained)
var victims: Array = []    # the rules: the held foe, then its forks
var latched := false       # the rules: the beam is on
var tick := 0.0            # seconds to the next beat (her own game: also the mana's)
var rtick := 0.0           # the server's copy: seconds to its next beat
var heal_sum := 0.0        # her own game: healing gathered since the last "+N"
var heal_t := 0.0

func can_cast(aim: Vector3) -> bool:
	if _pick(aim) == null:
		hero.game.ui.message("No enemy in reach", Color(0.8, 0.8, 0.8))
		return false
	return true

## The foe the beam latches onto: the one nearest the aim point, else the nearest in reach.
func _pick(aim: Vector3):
	var h := hero
	var best = null
	var bd := PICK_R
	for e in h.game.enemies_near(aim, PICK_R):
		if not foe(e):
			continue
		var d: float = Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length()
		if d < bd and e.global_position.distance_to(h.global_position) <= reach():
			bd = d
			best = e
	if best == null:
		best = _nearest(h.global_position, reach(), null)
	return best

func _nearest(p: Vector3, r: float, skip):
	var best = null
	var bd := r
	for e in hero.game.enemies_near(p, r):
		if e == skip or not foe(e):
			continue
		var d: float = e.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best

func _valid(e) -> bool:
	return alive(e) and e.global_position.distance_to(hero.global_position) <= val("leash", 13.0)

## The held foe dead or out of reach: the nearest to it, else the nearest to her (null: nothing left to drain).
func _rehold() -> void:
	var from: Vector3 = main.global_position if main != null and is_instance_valid(main) else hero.global_position
	main = _nearest(from, val("fork_r", 5.5), null)
	if not _valid(main):
		main = _nearest(hero.global_position, reach(), null)

# ---------------------------------------------------------------- her own game: the channel
func cast(aim: Vector3) -> void:
	var h := hero
	var e = _pick(aim)
	h.channel_t = 0.0
	tick = val("first", 0.1)
	main = e
	h.target = null
	h.path = PackedVector3Array()
	h.moving = false
	heal_sum = 0.0
	heal_t = 0.0
	h._face(e.global_position - h.global_position)
	victims = [e]
	h.fx(id, "start", {"t": victims})
	make("latch", {"at": (e as Node3D).global_position, "id": net_id(e)})

## Every frame of the channel (ClassSkills.channel, from Hero._process): the key, the mana, the facing; the rules'
## beat too when they run here.
func channel(delta: float) -> void:
	var h := hero
	h.channel_t += delta
	if not _valid(main):
		_rehold()
		if main == null:
			end()
			return
	if h.channel_t >= val("min_s", 1.0) and not h.game.skill_held(id):
		end()
		return
	h._face_smooth(main.global_position - h.global_position, delta)
	if deals():
		_victims_changed()
	tick -= delta
	if tick > 0.0:
		return
	tick = val("beat", 0.3)
	if h.channel_t >= val("min_s", 1.0):
		# past the first second the channel costs mana
		var cost := val("mana", 2.0)
		if h.mana < cost:
			h.game.ui.message("Not enough mana", Color(0.4, 0.5, 1.0))
			end()
			return
		h.mana -= cost * (1.0 - h.talent("cost:drain") / 100.0)
	if deals():
		_beat()
	h.stats_changed.emit()

## The channel lets go (Hero.end_channel).
func end() -> void:
	var h := hero
	var was := h.channel_t >= 0.0
	h.channel_t = -1.0
	main = null
	victims = []
	if was:
		h.fx(id, "end")
		make("end", {})
	_show_heal()

## What the beat drank comes back to her: the Covenant doubles it, Dark Thirst and Undying Hunger add to it, Soul
## Glut turns what would heal past full life into mana; healed (past full life, the shield: WarlockHex.healed).
func given(kind: String, data: Dictionary) -> void:
	if kind != "drink":
		super.given(kind, data)
		return
	var h := hero
	var heal := float(data.get("v", 0.0))
	var fc = h.kit.get("covenant")
	if fc != null and fc.active():
		heal *= fc.val("heal_k", 2.0)
	heal *= 1.0 + h.talent("drain_heal") / 100.0
	var hx := hex()
	if hx.shield > 0.0 and h.talent("shield_fork") > 0.0:
		heal *= 1.25      # Undying Hunger
	# Soul Glut: what would heal past full life fills mana instead
	if h.talent("drain_glut") > 0.0 and h.life + heal > h.max_life:
		h.mana = minf(h.max_mana, h.mana + (h.life + heal - h.max_life) * h.talent("drain_glut") / 100.0)
	hx.healed(heal)
	heal_sum += heal
	heal_t += val("beat", 0.3)
	if heal_t >= 0.9:
		_show_heal()
	h.stats_changed.emit()

## Healing from the beam shows as one green "+N" about once a second rather than every beat (its look).
func _show_heal() -> void:
	if heal_sum >= 1.0:
		hero.fx(id, "healed", {"x": heal_sum})
	heal_sum = 0.0
	heal_t = 0.0

# ---------------------------------------------------------------- the rules
func made(kind: String, d: Dictionary) -> void:
	match kind:
		"latch":
			var e = target_of(d)
			if e == null:
				e = _nearest(hero.global_position, reach(), null)
			if e == null:
				return
			main = e
			victims = [e]
			latched = true
			rtick = val("first", 0.1)
		"end":
			latched = false
			if hero.puppet:
				main = null
				victims = []
		"ward":
			hex().shield = 1.0 if bool(d.get("on", false)) else 0.0

## Server: a latch within her reach of where it has her; the end; whether she has a shield (her game's word).
func server_ok(kind: String, d: Dictionary) -> bool:
	match kind:
		"latch":
			return d.get("at") is Vector3 and (d["at"] as Vector3).distance_to(hero.global_position) <= reach() + 4.0
		"end", "ward":
			return true
	return false

## The held foe first, then the foes the beam forks to (nearest the held one).
func victims_now() -> Array:
	if not _valid(main):
		return []
	var h := hero
	var m = main
	var mp: Vector3 = m.global_position
	var near: Array = h.game.enemies_near(mp, val("fork_r", 5.5)).filter(func(e) -> bool: return e != m and foe(e))
	near.sort_custom(func(a, b) -> bool: return a.global_position.distance_to(mp) < b.global_position.distance_to(mp))
	var fc = h.kit.get("covenant")
	var forks := int(fc.val("forks", 5.0) if fc != null and fc.active() else val("forks", 3.0)) + int(h.talent("drain_fork"))
	if hex().shield > 0.0:
		forks += int(h.talent("shield_fork"))      # Undying Hunger
	return [m] + near.slice(0, forks)

## When the beam's foes change, everyone is told (a "victims" event, never more often than foes move in and out
## of the forks' reach).
func _victims_changed() -> void:
	var now := victims_now()
	if now != victims:
		victims = now
		hero.fx(id, "victims", {"t": now})

## A beat: each foe on the beam loses life (the held one dragged a little toward her) and she drinks part of it.
func _beat() -> void:
	var h := hero
	var dmg := (6.0 + h.level * 2.4 + (h.dmg_min + h.dmg_max) * 0.6) * 0.3 * h.buff_mult() * h.dmg_mult(id)
	var heal := 0.0
	_victims_changed()
	var fork_k := val("fork_dmg", 60.0) / 100.0
	for i in victims.size():
		var e = victims[i]
		e.dmg_tint = Color(0.55, 1.0, 0.45)
		var dealt: float = e.take_damage(dmg * (1.0 if i == 0 else fork_k), 0.0, h.global_position, -val("drag", 0.25) if i == 0 else 0.0, false)
		e.dmg_tint = Color(0, 0, 0, 0)
		if h.puppet and h.game.net.server:
			h.game.net.tell_dealt(h, e.global_position, dealt, false)
		var part := dealt * (val("heal", 30.0) / 100.0 if i == 0 else val("fork_heal", 15.0) / 100.0)
		if h.talent("drain_execute") > 0.0 and e.max_life > 0.0 and e.life < e.max_life * (val("gorge_at", 30.0) / 100.0):
			part *= 2.0      # Gorge
		heal += part
	h.fx(id, "tick")
	give("drink", {"v": heal})

## The server's copy of her: the rules beat on their own (her game holds the channel and says when it ends).
func update(delta: float) -> void:
	if not latched or not hero.puppet:
		return
	if not _valid(main):
		_rehold()
		if main == null:
			latched = false
			victims = []
			hero.fx(id, "end")
			return
	_victims_changed()
	rtick -= delta
	if rtick > 0.0:
		return
	rtick = val("beat", 0.3)
	_beat()

func clear() -> void:
	super.clear()
	end()
	latched = false

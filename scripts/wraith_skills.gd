class_name WraithSkills
extends RefCounted
## The Wraith's skills: their casts, the frames their blows land on, what runs every frame, and their state on
## the hero (`Hero.wr`, a dictionary, cleared by `clear`). Hero.use_skill, _impact, _process and take_hit call in.
##
## Every skill is a whole-body motion-capture clip of his (SHOTS: the clip and how the attack's progress 0..1
## maps onto its seconds, so the blow lands on Anim.impact_at's frame at any attack speed; KnightMocapRig "shots").
## Nothing here draws: every effect is an fx event (`Hero.fx`, SkillFx) that WraithFx plays on his own game and on
## his puppet on every partner's; the damage, healing, stuns and the hero's own movement stay here.
##  - Spectral Rend (Q, "rend"): the claws grow out as he lunges at the foe ahead (REND_LUNGE), and claw2's two
##    strikes rake across in front, each tearing souls out that fly back and heal him.
##  - Soul Siphon (E, "siphon"): cast2's reach: the hand thrust out latches a tether into one foe; it holds
##    SIPHON_DUR s whatever he does next (it breaks past SIPHON_LEASH), ticking damage, healing him part of it and
##    slowing the victim; a victim it kills gives up its soul to him.
##  - Shadowstep (R, "step"): the dodge's spin: a third of the way round he comes apart into mist (an afterimage
##    stays), re-forms up to STEP_RANGE away (walls stop him short: the landing is walked with world.move), and
##    the spin's end is a claw strike round where he lands. For VEIL_STEP s after he is still mist: blows pass
##    through him (Hero.veil_t). The shade he left collapses a moment later and hurts.
##  - Haunting Grasp (F, "grasp"): the slam: spectral hands burst out of the ground round the cursor (GRASP_R),
##    drag everything there inward and hold it GRASP_HOLD s.
##  - Phantom Assault (G, "phantom"): claw1's wind-up splits three phantoms (afterimages) off him that streak
##    through the foes ahead in a fan, each tearing everything in its path once, and the clip's own strike lands
##    in front of him.
##  - Eternal Night (V, "night"): the ultimate, four stages chained as attacks (update): he rises (cast: the arms
##    up, the night falling over everything round him), screams (scream: terror, damage and a knockback over
##    NIGHT_R), hangs in the night (cast's gathering: ticks of damage, phantoms wheeling round him, mist to any
##    blow) and falls (the slam: the night collapses into a burst). +40% damage for the 12 s after.

## The clips per attack style are Wraith.SHOTS (the rig's "shots").
## Each attack's length in seconds (before Data.ATTACK_PACE; Spectral Rend also by attack speed)
const DUR := {"rend": 0.8, "siphon": 0.7, "wstep": 0.75, "grasp": 0.95, "phantom": 1.0,
	"night_rise": 0.9, "night_scream": 0.9, "night_hold": 2.4, "night_fall": 1.3}
## The attack style each skill starts with
const STYLE := {"rend": "rend", "siphon": "siphon", "step": "wstep", "grasp": "grasp", "phantom": "phantom", "night": "night_rise"}
const NIGHT_STAGES := ["night_rise", "night_scream", "night_hold", "night_fall"]
## Old saves: the skills these replaced, so their bindings carry over
const OLD_IDS := {"reap": "rend", "wail": "siphon", "shade": "step", "host": "grasp"}

const REND_RANGE := 4.5       # he lunges at a foe this far ahead
const REND_LUNGE := 3.0       # at most this far
const SIPHON_RANGE := 9.0
const SIPHON_LEASH := 13.0
const SIPHON_DUR := 2.5
const SIPHON_TICK := 0.25
const STEP_RANGE := 9.0
const VEIL_STEP := 0.6
const GRASP_RANGE := 10.0
const GRASP_R := 3.5
const GRASP_HOLD := 2.5
const PHANTOM_RANGE := 8.0
const PHANTOM_SPEED := 15.0
const NIGHT_R := 9.0
const NIGHT_TICK := 0.5
const NIGHT_HOVER := 1.0      # how high he rises for the night (on top of Wraith.HOVER)

static func active(h: Hero) -> bool:
	return h.is_wraith()

## The spirit-light in his blows: a part by level on top of the weapon (the same curve as the other classes' spells),
## so the skills keep their weight while the weapon is still small. k is the skill's share of it.
static func spirit(h: Hero, k: float) -> float:
	return (16.0 + h.level * 4.5 + (h.dmg_min + h.dmg_max) * 0.35) * k

## Can he be told to walk right now? The blink, the slam and the night root him.
static func rooted(h: Hero) -> bool:
	return h.atk_t >= 0.0 and h.atk_skill in ["step", "grasp", "night"]

## The foe Soul Siphon latches onto: the one nearest the aim point, else the best in the cone ahead.
static func siphon_pick(h: Hero, aim: Vector3):
	var best = null
	var bd := 3.0
	for e in h.game.enemies_near(aim, 3.0):
		var d: float = Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length()
		if d < bd and e.global_position.distance_to(h.global_position) <= SIPHON_RANGE:
			bd = d
			best = e
	if best == null:
		var p := h.aim_ahead(SIPHON_RANGE)
		for e in h.game.enemies_near(p, 0.5):
			best = e
			break
	return best

static func _start(h: Hero, style: String, skill: String) -> void:
	h._start_attack(style, skill)
	var d: float = DUR[style] * Data.attack_pace(h.cls)
	if skill == "rend":
		d /= h.aspd
	h.atk_dur = d
	h.moving = false
	h.path = PackedVector3Array()

# ---------------------------------------------------------------- casts
static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var w: Dictionary = h.wr
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	match id:
		"rend":
			# the lunge: up to REND_LUNGE toward the foe aimed at, stopping a claw's length short of him
			var lunge := 0.0
			var foe = null
			var fd := REND_RANGE
			for e in h.game.enemies_near(aim, 1.5):
				var d: float = e.global_position.distance_to(h.global_position)
				if d < fd:
					fd = d
					foe = e
			if foe != null:
				lunge = clampf(fd - foe.radius - 1.0, 0.0, REND_LUNGE)
			elif to.length() > 1.5:
				lunge = minf(to.length() - 1.2, REND_LUNGE)
			w["lunge"] = lunge
			w["lunge_a"] = 0.0
			w["rend2"] = false
			w["rend_n"] = int(w.get("rend_n", 0)) + 1
			_start(h, "rend", "rend")
		"siphon":
			w["siphon_victim"] = siphon_pick(h, aim)
			_start(h, "siphon", "siphon")
		"step":
			var dist := minf(to.length(), STEP_RANGE)
			var dir := to.normalized() if to.length() > 0.5 else h.facing()
			if dist < 0.5:
				dist = 4.0
			# walk the way there in steps that slide round anything solid, so the landing is a real spot
			var p := h.global_position
			var travelled := 0.0
			while travelled < dist:
				var np: Vector3 = h.game.world.move(p, dir * minf(0.4, dist - travelled), h.radius)
				var moved := np - p
				moved.y = 0
				if moved.length() < 0.12:
					break
				p = np
				travelled += moved.length()
			p.y = h.game.world.height_at(p.x, p.z)
			w["step_to"] = p
			w["step_from"] = h.global_position
			w["step_done"] = false
			_start(h, "wstep", "step")
		"grasp":
			var at := h.global_position + to.limit_length(GRASP_RANGE)
			at.y = h.game.world.height_at(at.x, at.z)
			w["grasp_at"] = at
			_start(h, "grasp", "grasp")
		"phantom":
			w["phantom_go"] = false
			_start(h, "phantom", "phantom")
		"night":
			end_night(h, false)
			# the night itself (the dark coming down, the rise, his glow) is the "cast" event's effect (WraithFx)
			w["night"] = {"stage": 0, "t": 0.0, "tick": 0.0}
			h.veil_t = 99.0        # mist to every blow until the night ends
			_start(h, "night_rise", "night")

# ---------------------------------------------------------------- the blows
## Called from Hero._impact on the attack's impact frame; true when it was one of his.
static func impact(h: Hero) -> bool:
	if not active(h):
		return false
	var w: Dictionary = h.wr
	match h.atk_skill:
		"rend":
			_rend_hit(h, true)
		"siphon":
			_siphon_latch(h)
		"step":
			# the spin's end: the claws tear round where he landed
			var any := false
			for e in h.game.enemies_near(h.global_position, 2.9):
				h._hit_enemy(e, 1.3, 1.0, "step", spirit(h, 0.7))
				if is_instance_valid(e) and not e.dead:
					e.stun(0.7 + h.talent("step_stun"))
				any = true
			h.fx("step", "strike", {"y": h.rig.global_rotation.y, "x": any})
		"grasp":
			var at: Vector3 = w.get("grasp_at", h.global_position)
			var hold := GRASP_HOLD + h.talent("grasp_hold")
			h.fx("grasp", "impact", {"p": at, "x": hold})
			var any := false
			for e in h.game.enemies_near(at, GRASP_R + 0.3):
				# seized: the blow, then dragged toward the middle and held
				var dr := h.roll_damage(1.1 * h.dmg_mult("grasp"))
				dr["phys"] += spirit(h, 0.9) * h.buff_mult() * h.dmg_mult("grasp")
				var dealt: float = e.take_damage(dr["phys"], dr["fire"], at, -1.4, dr["crit"])
				if h.ls > 0.0:
					h.life = minf(h.max_life, h.life + dealt * h.ls / 100.0)
				if is_instance_valid(e) and not e.dead:
					e.stun(hold)
				any = true
			if any:
				h.game.hitstop(0.05)
		"phantom":
			# his own strike, after the phantoms have gone
			var fwd := h.facing()
			h.fx("phantom", "strike", {"y": h.rig.global_rotation.y})
			for e in h.game.enemies_near(h.global_position, 3.1):
				var to: Vector3 = e.global_position - h.global_position
				to.y = 0
				if to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(70.0)):
					h._hit_enemy(e, 1.0, 0.5, "phantom", spirit(h, 0.3))
		"night":
			_night_impact(h)
		_:
			return false
	return true

## Spectral Rend's rake: the right claw on the first strike, the left on the second. Souls torn out heal him
## as their wisps arrive (WraithFx flies them; the heal waits the same time here).
static func _rend_hit(h: Hero, first: bool) -> void:
	var fwd := h.facing()
	var full := h.talent("rend_full") > 0.0
	var souls := PackedVector3Array()
	for e in h.game.enemies_near(h.global_position, 3.3):
		var to: Vector3 = e.global_position - h.global_position
		to.y = 0
		if full or to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(75.0)):
			h._hit_enemy(e, 0.9, 0.4 if first else 0.7, "rend", spirit(h, 0.2))
			if is_instance_valid(e):
				souls.append(e.global_position + Vector3(0, 1.0 * e.height, 0))
	h.fx("rend", "rake", {"y": h.rig.global_rotation.y, "l": not first, "x": full, "n": souls.size()})
	if not souls.is_empty():
		h.fx("rend", "souls", {"ps": souls})
		for i in souls.size():
			h.get_tree().create_timer(WraithFx.wisp_time(i), false).timeout.connect(func():
				if is_instance_valid(h) and not h.dead:
					Sfx.play("soul_return", -9.0)
					h.life = minf(h.max_life, h.life + h.max_life * (0.02 + h.talent("rend_heal") / 100.0))
					h.stats_changed.emit())

## Soul Siphon's latch: the tether bites into the victim picked at the cast (or the nearest one ahead now).
static func _siphon_latch(h: Hero) -> void:
	var w: Dictionary = h.wr
	var v = w.get("siphon_victim")
	if v == null or not is_instance_valid(v) or v.dead:
		v = siphon_pick(h, h.aim_ahead(SIPHON_RANGE))
	end_siphon(h)
	if v == null:
		return
	var hold := SIPHON_DUR + h.talent("siphon_dur")
	w["tether"] = {"victim": v, "t": 0.0, "tick": 0.05, "heal": 0.0}
	h.fx("siphon", "latch", {"t": [v], "x": hold})
	# the body stands rigid while its soul is pulled at: held for the hold (a boss shakes it off sooner), then slowed
	v.stun(hold)
	v.slow(hold + 1.5, 0.5)

## The tether lets go: its hold is up (`spent`), the victim is lost, or he is cut short.
static func end_siphon(h: Hero, spent := false) -> void:
	var w: Dictionary = h.wr
	if not w.has("tether"):
		return
	var t: Dictionary = w["tether"]
	w.erase("tether")
	h.fx("siphon", "end", {"x": spent})
	if float(t["heal"]) >= 1.0 and h.game.world:
		Fx.number(h.game.world.fx_root, h.global_position + Vector3(0, 2.3, 0), "+%d" % int(t["heal"]), Color(0.55, 0.95, 1.0))

# ---------------------------------------------------------------- Eternal Night
static func night_active(h: Hero) -> bool:
	return h.wr.has("night")

static func end_night(h: Hero, finished: bool) -> void:
	var w: Dictionary = h.wr
	if not w.has("night"):
		return
	h.veil_t = 0.0
	w.erase("night")
	h.fx("night", "end", {"x": finished})

static func _night_impact(h: Hero) -> void:
	var w: Dictionary = h.wr
	if not w.has("night"):
		return
	match h.atk_style:
		"night_rise":
			h.fx("night", "rise")
		"night_scream":
			# the terror: damage, hurled back and frozen with fear over the whole night
			h.buff_t = 12.0 + h.talent("buff_dur")
			h.fx("night", "scream")
			for e in h.game.enemies_near(h.global_position, NIGHT_R):
				h._hit_enemy(e, 1.5, 2.2, "night", spirit(h, 1.2))
				if is_instance_valid(e) and not e.dead:
					e.stun(2.5)
		"night_fall":
			# the night collapses into the slam
			h.fx("night", "fall")
			for e in h.game.enemies_near(h.global_position, 6.5):
				h._hit_enemy(e, 2.0, 1.6, "night", spirit(h, 1.6))
			end_night(h, true)

# ---------------------------------------------------------------- every frame
static func update(h: Hero, delta: float) -> void:
	var w: Dictionary = h.wr
	if h.veil_t > 0.0 and not w.has("night"):
		h.veil_t = maxf(0.0, h.veil_t - delta)
	if not active(h):
		return
	var a: float = (h.atk_t / h.atk_dur) if h.atk_t >= 0.0 else -1.0
	# (the claws grow and shrink with the attack in WraithFx.update, on his puppet too)
	# Spectral Rend: the lunge through the wind-up, the second rake
	if a >= 0.0 and h.atk_skill == "rend":
		var lunge: float = w.get("lunge", 0.0)
		if lunge > 0.0:
			var l0: float = w.get("lunge_a", 0.0)
			var f0 := smoothstep(0.05, 0.4, l0)
			var f1 := smoothstep(0.05, 0.4, a)
			w["lunge_a"] = a
			var d := (f1 - f0) * lunge
			if d > 0.0:
				var fwd := h.facing()
				var np: Vector3 = h.game.world.move(h.global_position, fwd * d, h.radius)
				h.global_position = np
		if a >= 0.72 and not bool(w.get("rend2", false)):
			w["rend2"] = true
			_rend_hit(h, false)
	# Shadowstep: the blink a third of the way into the spin
	if a >= 0.0 and h.atk_skill == "step" and a >= 0.35 and not bool(w.get("step_done", false)):
		w["step_done"] = true
		_blink(h)
	# Phantom Assault: the split as the wind-up ends
	if a >= 0.0 and h.atk_skill == "phantom" and a >= 0.3 and not bool(w.get("phantom_go", false)):
		w["phantom_go"] = true
		_launch_phantoms(h)
	_update_phantoms(h)
	_update_tether(h, delta)
	_update_night(h, delta)

## Shadowstep's blink: an afterimage stays where he was, he goes out in mist and comes back in it at the landing.
static func _blink(h: Hero) -> void:
	var w: Dictionary = h.wr
	var from: Vector3 = w.get("step_from", h.global_position)
	var to: Vector3 = w.get("step_to", h.global_position)
	h.fx("step", "blink", {"p": from, "q": to})
	h.global_position = to
	h.target = null
	h.path = PackedVector3Array()
	h.moving = false
	h.veil_t = maxf(h.veil_t, VEIL_STEP + h.talent("veil"))
	# the shade left behind caves in a moment later (the "blink" event collapses it at the same time)
	var tree := h.get_tree()
	tree.create_timer(WraithFx.SHADE_DELAY, false).timeout.connect(func():
		if not is_instance_valid(h) or h.game.world == null:
			return
		for e in h.game.enemies_near(from, 2.6):
			h._hit_enemy(e, 0.8, 0.8, "step", spirit(h, 0.4)))

## Phantom Assault: three (four with Fourth Rider) ghosts of him streak out ahead in a fan. They are the "split"
## event's effect: WraithFx raises them (h.fxs["phantoms"]) and flies them, here and on every partner's game;
## only here do they tear what they pass through.
static func _launch_phantoms(h: Hero) -> void:
	h.fx("phantom", "split", {"d": h.facing(), "n": 3 + int(h.talent("phantoms"))})

static func _update_phantoms(h: Hero) -> void:
	if not h.fxs.has("phantoms"):
		return
	for p in h.fxs["phantoms"]:
		var g = p["node"]
		if not is_instance_valid(g):
			continue
		var np: Vector3 = g.global_position
		for e in h.game.enemies_near(np, 1.6):
			if e.dead or (p["hit"] as Dictionary).has(e.get_instance_id()):
				continue
			var d := Vector2(e.global_position.x - np.x, e.global_position.z - np.z).length()
			if d < e.radius + 1.0:
				p["hit"][e.get_instance_id()] = true
				h._hit_enemy(e, 1.2, 0.5, "phantom", spirit(h, 0.5))
				h.fx("phantom", "hit", {"p": e.global_position + Vector3(0, 1.0 * e.height, 0), "d": p["dir"]})

## Soul Siphon's hold: every SIPHON_TICK the victim loses life, part of it comes back to the Wraith.
static func _update_tether(h: Hero, delta: float) -> void:
	var w: Dictionary = h.wr
	if not w.has("tether"):
		return
	var t: Dictionary = w["tether"]
	var v = t["victim"]
	if v == null or not is_instance_valid(v) or v.dead or v.global_position.distance_to(h.global_position) > SIPHON_LEASH or h.dead:
		if v != null and is_instance_valid(v) and v.dead and not h.dead:
			# the soul leaves the body and comes to him
			h.fx("siphon", "soul", {"p": v.global_position + Vector3(0, 0.9 * v.height, 0)})
			h.get_tree().create_timer(WraithFx.wisp_time(0), false).timeout.connect(func():
				if is_instance_valid(h) and not h.dead:
					Sfx.play("soul_return", -6.0)
					h.life = minf(h.max_life, h.life + h.max_life * 0.06)
					h.stats_changed.emit())
		end_siphon(h)
		return
	t["t"] += delta
	t["tick"] -= delta
	var dur: float = SIPHON_DUR + h.talent("siphon_dur")
	if t["t"] >= dur:
		end_siphon(h, true)
		return
	if t["tick"] > 0.0:
		return
	t["tick"] = SIPHON_TICK
	var ticks := dur / SIPHON_TICK
	# about 180% of weapon damage over the hold plus twice a spell's worth of spirit-light, in cold light (no blood)
	var per := (spirit(h, 2.0) + (h.dmg_min + h.dmg_max) * 0.9) / ticks * h.buff_mult() * h.dmg_mult("siphon")
	v.dmg_tint = Color(0.6, 0.9, 1.0)
	var dealt: float = v.take_damage(per, 0.0, h.global_position, 0.0, false)
	v.dmg_tint = Color(0, 0, 0, 0)
	h.fx("siphon", "tick")
	var heal := dealt * 0.35
	h.life = minf(h.max_life, h.life + heal)
	t["heal"] = float(t["heal"]) + heal
	if h.ls > 0.0:
		h.life = minf(h.max_life, h.life + dealt * h.ls / 100.0)
	h.stats_changed.emit()

## The night's stages, chained as attacks; the ticks run through the hold. (The dark coming down through the
## rise, his glow and the fall's descent follow the attack's progress in WraithFx.update, on the puppet too.)
static func _update_night(h: Hero, delta: float) -> void:
	var w: Dictionary = h.wr
	if not w.has("night"):
		return
	var n: Dictionary = w["night"]
	if h.dead or h.atk_skill != "night" and h.atk_t >= 0.0:
		end_night(h, false)
		return
	n["t"] = float(n["t"]) + delta
	var stage: int = n["stage"]
	if stage == 2:
		n["tick"] = float(n["tick"]) - delta
		if float(n["tick"]) <= 0.0:
			n["tick"] = NIGHT_TICK
			var any := false
			for e in h.game.enemies_near(h.global_position, NIGHT_R - 1.0):
				h._hit_enemy(e, 0.3, 0.0, "night", spirit(h, 0.25))
				any = true
			if any:
				h.fx("night", "tick")
	if h.atk_t < 0.0:
		# this stage is over: the next
		stage += 1
		if stage >= NIGHT_STAGES.size():
			end_night(h, true)
			return
		n["stage"] = stage
		_start(h, NIGHT_STAGES[stage], "night")
		if stage == 1:
			Sfx.play_synced("wail", Anim.impact_at("night_scream") * h.atk_dur, -2.0, 0.9)
		elif stage == 3:
			Sfx.play_synced("slam", Anim.impact_at("night_fall") * h.atk_dur, -3.0, 0.8)

# ---------------------------------------------------------------- housekeeping
## Everything of his that lingers: the tether, phantoms in flight, the night (a class change, a new character, death).
static func clear(h: Hero) -> void:
	var w: Dictionary = h.wr
	end_siphon(h)
	end_night(h, false)
	WraithFx.clear(h)
	if h.atk_t >= 0.0 and h.atk_skill in STYLE:
		# a skill of his in progress is cut off (a class change, death)
		h.atk_t = -1.0
		h.atk_skill = ""
	w.clear()
	h.veil_t = 0.0

## Old saves bound the skills these replaced: the binding carries over.
static func migrate_binds(binds: Dictionary) -> void:
	for k in binds.keys():
		var id := str(binds[k])
		if OLD_IDS.has(id):
			binds[k] = OLD_IDS[id]

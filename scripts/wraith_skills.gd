class_name WraithSkills
extends RefCounted
## The Wraith's skills: their casts, the frames their blows land on, what runs every frame, and their state on
## the hero (`Hero.wr`, a dictionary, cleared by `clear`). Hero.use_skill, _impact, _process and take_hit call in.
##
## Every skill is a whole-body motion-capture clip of his (SHOTS: the clip and how the attack's progress 0..1
## maps onto its seconds, so the blow lands on Anim.impact_at's frame at any attack speed; KnightMocapRig "shots"),
## with its effects in WraithFx:
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
##    up, the night falling as a dome of dark over everything round him), screams (scream: terror, damage and a
##    knockback over NIGHT_R), hangs in the night (cast's gathering: ticks of damage, phantoms wheeling round him,
##    mist to any blow) and falls (the slam: the night collapses into a burst). +40% damage for the 12 s after.

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
			var root: Node3D = h.game.world.fx_root
			var grade: ShaderMaterial = h.game.vignette.material if h.game.get("vignette") != null else null
			w["night"] = {"stage": 0, "t": 0.0, "tick": 0.0, "node": WraithFx.night(root, h.global_position, NIGHT_R * 0.8, grade), "ghosts": [], "veil": true}
			_set_hover(h, NIGHT_HOVER)
			h.veil_t = 99.0        # mist to every blow until the night ends
			_start(h, "night_rise", "night")
			Sfx.play("host_summon", -4.0, 0.8)
			Sfx.duck(-6.0, 1.5)

# ---------------------------------------------------------------- the blows
## Called from Hero._impact on the attack's impact frame; true when it was one of his.
static func impact(h: Hero) -> bool:
	if not active(h):
		return false
	var w: Dictionary = h.wr
	var root: Node3D = h.game.world.fx_root
	match h.atk_skill:
		"rend":
			_rend_hit(h, true)
		"siphon":
			_siphon_latch(h)
		"step":
			# the spin's end: the claws tear round where he landed
			var yaw := h.rig.global_rotation.y
			WraithFx.rake(root, h.global_position, yaw, 2.6, true)
			WraithFx.rake(root, h.global_position, yaw + PI, 2.6, false)
			var any := false
			for e in h.game.enemies_near(h.global_position, 2.9):
				h._hit_enemy(e, 1.3, 1.0, "step", spirit(h, 0.7))
				if is_instance_valid(e) and not e.dead:
					e.stun(0.7 + h.talent("step_stun"))
				any = true
			Sfx.play("reap_swing", -3.0, 1.1)
			h.game.add_shake(0.22 if any else 0.1)
		"grasp":
			var at: Vector3 = w.get("grasp_at", h.global_position)
			var hold := GRASP_HOLD + h.talent("grasp_hold")
			WraithFx.grasp(root, at, GRASP_R, hold)
			Sfx.play_at("slam", at, -4.0, 0.85)
			Sfx.play_at("shackles", at, -8.0, 1.15)
			h.game.add_shake(0.3)
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
			var yaw := h.rig.global_rotation.y
			var fwd := h.facing()
			WraithFx.rake(root, h.global_position, yaw, 2.8, true)
			for e in h.game.enemies_near(h.global_position, 3.1):
				var to: Vector3 = e.global_position - h.global_position
				to.y = 0
				if to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(70.0)):
					h._hit_enemy(e, 1.0, 0.5, "phantom", spirit(h, 0.3))
			h.game.add_shake(0.15)
		"night":
			_night_impact(h)
		_:
			return false
	return true

## Spectral Rend's rake: the right claw on the first strike, the left on the second. Souls torn out heal him.
static func _rend_hit(h: Hero, first: bool) -> void:
	var root: Node3D = h.game.world.fx_root
	var yaw := h.rig.global_rotation.y
	var fwd := h.facing()
	var full := h.talent("rend_full") > 0.0
	WraithFx.rake(root, h.global_position, yaw, 3.0, not first)
	if full:
		WraithFx.rake(root, h.global_position, yaw + PI, 3.0, first)
	var any := false
	for e in h.game.enemies_near(h.global_position, 3.3):
		var to: Vector3 = e.global_position - h.global_position
		to.y = 0
		if full or to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(75.0)):
			h._hit_enemy(e, 0.9, 0.4 if first else 0.7, "rend", spirit(h, 0.2))
			any = true
			if is_instance_valid(e):
				Fx.sparks(root, e.global_position + Vector3(0, 1.0 * e.height, 0), WraithFx.PALE)
				WraithFx.soul_wisp(root, e.global_position + Vector3(0, 1.0 * e.height, 0), h, func():
					if not h.dead:
						Sfx.play("soul_return", -9.0)
						h.life = minf(h.max_life, h.life + h.max_life * (0.02 + h.talent("rend_heal") / 100.0))
						h.stats_changed.emit())
	if not first:
		Sfx.play("swing_light", -4.0, 0.9)
	h.game.add_shake(0.14 if any else 0.05)

## Soul Siphon's latch: the tether bites into the victim picked at the cast (or the nearest one ahead now).
static func _siphon_latch(h: Hero) -> void:
	var w: Dictionary = h.wr
	var v = w.get("siphon_victim")
	if v == null or not is_instance_valid(v) or v.dead:
		v = siphon_pick(h, h.aim_ahead(SIPHON_RANGE))
	end_siphon(h)
	if v == null:
		return
	var root: Node3D = h.game.world.fx_root
	var chest: Vector3 = v.global_position + Vector3(0, 0.9 * v.height, 0)
	WraithFx.latch(root, chest)
	w["tether"] = {"victim": v, "t": 0.0, "tick": 0.05, "node": WraithFx.tether(root), "heal": 0.0, "hum": Sfx.start_loop("drain_loop", -16.0, 0.72)}
	v.set_drained(true, WraithFx.SPIRIT)
	# the body stands rigid while its soul is pulled at: held for the hold (a boss shakes it off sooner), then slowed
	var hold := SIPHON_DUR + h.talent("siphon_dur")
	v.stun(hold)
	v.slow(hold + 1.5, 0.5)
	Sfx.play("spirit_dart", -4.0, 0.8)
	h.game.add_shake(0.08)

static func end_siphon(h: Hero) -> void:
	var w: Dictionary = h.wr
	if not w.has("tether"):
		return
	var t: Dictionary = w["tether"]
	var v = t["victim"]
	if v != null and is_instance_valid(v):
		v.set_drained(false)
	var n = t["node"]
	if n != null and is_instance_valid(n):
		# the tether lets go: it thins and is gone
		var tw: Tween = n.create_tween()
		tw.tween_property(n, "fade", 0.0, 0.25)
		tw.tween_callback(n.queue_free)
	var hum = t["hum"]
	if hum != null and is_instance_valid(hum):
		hum.stop()
		hum.queue_free()
	if float(t["heal"]) >= 1.0 and h.game.world:
		Fx.number(h.game.world.fx_root, h.global_position + Vector3(0, 2.3, 0), "+%d" % int(t["heal"]), Color(0.55, 0.95, 1.0))
	w.erase("tether")

# ---------------------------------------------------------------- Eternal Night
static func _set_hover(h: Hero, extra: float) -> void:
	if h.rig != null and h._floats():
		h.rig.set("hover", Wraith.HOVER + extra)

static func night_active(h: Hero) -> bool:
	return h.wr.has("night")

static func end_night(h: Hero, finished: bool) -> void:
	var w: Dictionary = h.wr
	if not w.has("night"):
		return
	var n: Dictionary = w["night"]
	_set_hover(h, 0.0)
	h.veil_t = 0.0
	var node = n["node"]
	if node != null and is_instance_valid(node):
		var tw: Tween = node.create_tween()
		tw.tween_method(func(v: float): WraithFx.set_night(node, v), 1.0 if finished else 0.6, 0.0, 0.5 if finished else 0.3)
		tw.tween_callback(node.queue_free)
	elif h.game.get("vignette") != null:
		(h.game.vignette.material as ShaderMaterial).set_shader_parameter("night", 0.0)
	for g in n["ghosts"]:
		if is_instance_valid(g):
			(g as Node).queue_free()
	_set_glow(h, 1.0)
	w.erase("night")

static func _set_glow(h: Hero, g: float) -> void:
	if h.rig != null and h.rig.has_meta("spectral_mats"):
		for m in h.rig.get_meta("spectral_mats"):
			(m as ShaderMaterial).set_shader_parameter("glow", g)
	if h.rig != null and h.rig.has_meta("eye_light"):
		var l := h.rig.get_meta("eye_light") as OmniLight3D
		if l != null:
			l.light_energy = 0.45 * g

static func _night_impact(h: Hero) -> void:
	var w: Dictionary = h.wr
	if not w.has("night"):
		return
	var n: Dictionary = w["night"]
	var root: Node3D = h.game.world.fx_root
	match h.atk_style:
		"night_rise":
			Fx.flash(root, h.global_position + Vector3(0, 2.0, 0), WraithFx.VIOLET, 3.0, 0.6, 9.0)
		"night_scream":
			# the terror: damage, hurled back and frozen with fear over the whole night
			h.buff_t = 12.0 + h.talent("buff_dur")
			WraithFx.scream(root, h.global_position, NIGHT_R)
			Sfx.play("wail", 0.0, 0.9)
			Sfx.duck(-8.0, 1.0)
			h.game.add_shake(0.5)
			h.game.hitstop(0.06)
			for e in h.game.enemies_near(h.global_position, NIGHT_R):
				h._hit_enemy(e, 1.5, 2.2, "night", spirit(h, 1.2))
				if is_instance_valid(e) and not e.dead:
					e.stun(2.5)
			# four phantoms wheel round him for the rest of the night
			for i in 4:
				var g := WraithFx.afterimage(h.rig, root, WraithFx.VIOLET, 20.0, 0.25)
				if g != null:
					g.set_meta("phase", TAU * i / 4.0)
					(n["ghosts"] as Array).append(g)
		"night_fall":
			# the night collapses into the slam
			WraithFx.collapse(root, h.global_position, 6.5)
			Sfx.play("slam", -2.0, 0.8)
			Sfx.play("phase_erupt", -4.0, 0.9)
			Sfx.duck(-8.0, 1.0)
			h.game.add_shake(0.6)
			h.game.hitstop(0.08)
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
	# the claws: out for the rakes, grown as the arm draws back, gone soon after the last strike
	var want := 0.0
	if a >= 0.0 and h.atk_skill == "rend":
		want = Anim.kf(a, [[0.0, 0.0], [0.3, 1.0], [0.85, 1.0], [1.0, 0.0]])
	elif a >= 0.0 and h.atk_skill == "phantom":
		want = Anim.kf(a, [[0.0, 0.0], [0.25, 1.0], [0.8, 1.0], [1.0, 0.0]])
	elif a >= 0.0 and h.atk_skill == "step":
		want = Anim.kf(a, [[0.35, 0.0], [0.6, 1.0], [0.9, 1.0], [1.0, 0.0]])
	var ck: float = w.get("claw_k", 0.0)
	ck = lerpf(ck, want, clampf(delta * 18.0, 0.0, 1.0)) if want < ck else want
	w["claw_k"] = ck
	if h.rig != null and h._floats() and (ck > 0.001 or w.get("claw_shown", false)):
		WraithFx.set_claws(h.rig, ck)
		w["claw_shown"] = ck > 0.001
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
	_update_phantoms(h, delta)
	_update_tether(h, delta)
	_update_night(h, delta)

## Shadowstep's blink: an afterimage stays where he was, he goes out in mist and comes back in it at the landing.
static func _blink(h: Hero) -> void:
	var w: Dictionary = h.wr
	var root: Node3D = h.game.world.fx_root
	var from: Vector3 = w.get("step_from", h.global_position)
	var to: Vector3 = w.get("step_to", h.global_position)
	WraithFx.afterimage(h.rig, root, WraithFx.VIOLET, 0.55, 0.3)
	WraithFx.mist_out(root, from)
	Sfx.play_at("shade_out", from, -2.0)
	# a trail of fainter shades along the way
	var dist := from.distance_to(to)
	var steps := clampi(int(dist / 1.6), 1, 5)
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / steps)
		Fx.burst(root, p + Vector3(0, 1.0, 0), Color(0.3, 0.26, 0.42, 0.55), 8, 1.2, 0.35, 0.5, false, 0.8)
	h.global_position = to
	h.target = null
	h.path = PackedVector3Array()
	h.moving = false
	WraithFx.mist_in(root, to)
	Sfx.play("shade_in", -2.0)
	h.veil_t = maxf(h.veil_t, VEIL_STEP + h.talent("veil"))
	h.game.add_shake(0.15)
	# the shade left behind caves in a moment later
	var tree := h.get_tree()
	tree.create_timer(0.45, false).timeout.connect(func():
		if not is_instance_valid(h) or h.game.world == null:
			return
		WraithFx.shade_collapse(h.game.world.fx_root, from)
		Sfx.play_at("shade_implode", from, -1.0)
		for e in h.game.enemies_near(from, 2.6):
			h._hit_enemy(e, 0.8, 0.8, "step", spirit(h, 0.4)))

## Phantom Assault: three (four with Fourth Rider) ghosts of him streak out ahead in a fan.
static func _launch_phantoms(h: Hero) -> void:
	var w: Dictionary = h.wr
	var root: Node3D = h.game.world.fx_root
	var fwd := h.facing()
	var count := 3 + int(h.talent("phantoms"))
	var spread := deg_to_rad(22.0)
	var ps: Array = w.get("phantoms", [])
	for i in count:
		var ang := (float(i) - (count - 1) * 0.5) * spread
		var dir := fwd.rotated(Vector3.UP, ang)
		var g := WraithFx.afterimage(h.rig, root, WraithFx.VIOLET.lerp(WraithFx.SPIRIT, 0.3), PHANTOM_RANGE / PHANTOM_SPEED + 0.25, 0.2)
		if g == null:
			continue
		g.rotation.y = atan2(-dir.x, -dir.z)
		g.rotation.x = 0.0
		var tr := WraithFx._trail(WraithFx.VIOLET, 0.16, 30, 0.45)
		tr.position = Vector3(0, 1.0, 0)
		g.add_child(tr)
		ps.append({"node": g, "dir": dir, "left": PHANTOM_RANGE, "hit": {}, "lean": 0.0})
	w["phantoms"] = ps
	WraithFx.split(root, h.global_position)
	Sfx.play("host_summon", -5.0, 1.15)
	h.game.add_shake(0.18)

static func _update_phantoms(h: Hero, delta: float) -> void:
	var w: Dictionary = h.wr
	if not w.has("phantoms"):
		return
	var ps: Array = w["phantoms"]
	var world = h.game.world
	for p in ps.duplicate():
		var g = p["node"]
		if not is_instance_valid(g):
			ps.erase(p)
			continue
		var step := PHANTOM_SPEED * delta
		var pos: Vector3 = g.global_position
		var np: Vector3 = world.move(pos, (p["dir"] as Vector3) * step, 0.3)
		var moved := np - pos
		moved.y = 0
		np.y = world.height_at(np.x, np.z)
		g.global_position = np
		# leans into its flight
		p["lean"] = lerpf(float(p["lean"]), 0.45, clampf(delta * 8.0, 0.0, 1.0))
		g.rotation.x = -float(p["lean"])
		p["left"] -= step
		for e in h.game.enemies_near(np, 1.6):
			if e.dead or (p["hit"] as Dictionary).has(e.get_instance_id()):
				continue
			var d := Vector2(e.global_position.x - np.x, e.global_position.z - np.z).length()
			if d < e.radius + 1.0:
				p["hit"][e.get_instance_id()] = true
				h._hit_enemy(e, 1.2, 0.5, "phantom", spirit(h, 0.5))
				WraithFx.phantom_hit(world.fx_root, e.global_position + Vector3(0, 1.0 * e.height, 0), p["dir"])
				Sfx.play_at("spirit_dart", e.global_position, -5.0)
		if p["left"] <= 0.0 or moved.length() < step * 0.3:
			ps.erase(p)
			# it comes apart where it stops
			for m in g.get_meta("mats", []):
				(m as ShaderMaterial).set_shader_parameter("phase_amt", 1.0)
			Fx.burst(world.fx_root, np + Vector3(0, 1.0, 0), WraithFx.VIOLET, 12, 2.5, 0.1, 0.4, true, 0.0)
	if ps.is_empty():
		w.erase("phantoms")

## Soul Siphon's hold: every SIPHON_TICK the victim loses life, part of it comes back to the Wraith.
static func _update_tether(h: Hero, delta: float) -> void:
	var w: Dictionary = h.wr
	if not w.has("tether"):
		return
	var t: Dictionary = w["tether"]
	var v = t["victim"]
	var root: Node3D = h.game.world.fx_root
	if v == null or not is_instance_valid(v) or v.dead or v.global_position.distance_to(h.global_position) > SIPHON_LEASH or h.dead:
		if v != null and is_instance_valid(v) and v.dead and not h.dead:
			# the soul leaves the body and comes to him
			WraithFx.pulse(root, v.global_position + Vector3(0, 0.9 * v.height, 0), WraithFx.PALE, 1.6, 0.35)
			WraithFx.soul_wisp(root, v.global_position + Vector3(0, 0.9 * v.height, 0), h, func():
				if not h.dead:
					Sfx.play("soul_return", -6.0)
					h.life = minf(h.max_life, h.life + h.max_life * 0.06)
					h.stats_changed.emit())
		end_siphon(h)
		return
	t["t"] += delta
	t["tick"] -= delta
	var dur: float = SIPHON_DUR + h.talent("siphon_dur")
	if t["t"] >= dur:
		WraithFx.pulse(root, v.global_position + Vector3(0, 0.9 * v.height, 0), WraithFx.VIOLET, 1.2, 0.3)
		end_siphon(h)
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
	if is_instance_valid(v) and not v.dead:
		v.drain_flash(WraithFx.SPIRIT)
	var heal := dealt * 0.35
	h.life = minf(h.max_life, h.life + heal)
	t["heal"] = float(t["heal"]) + heal
	if h.ls > 0.0:
		h.life = minf(h.max_life, h.life + dealt * h.ls / 100.0)
	Sfx.play("drain_tick", -12.0, 1.3)
	h.stats_changed.emit()

## Drawn after the pose, so the tether leaves the hand where it is this frame.
static func draw(h: Hero) -> void:
	var w: Dictionary = h.wr
	if w.has("tether"):
		var t: Dictionary = w["tether"]
		var v = t["victim"]
		var n = t["node"]
		if v != null and is_instance_valid(v) and n != null and is_instance_valid(n):
			var J: Dictionary = h.rig.get_meta("j")
			var hand: Vector3 = (J.get("at_hand_r", J["hand_r"]) as Node3D).global_position
			(n as WraithFx.Tether).draw(hand, v.global_position + Vector3(0, 0.9 * v.height, 0), h.anim_time)
	if w.has("night"):
		var n: Dictionary = w["night"]
		var ghosts: Array = n["ghosts"]
		var c := h.global_position
		for g in ghosts:
			if not is_instance_valid(g):
				continue
			var ph: float = float(g.get_meta("phase")) + h.anim_time * 2.2
			var r := 3.2
			(g as Node3D).global_position = c + Vector3(cos(ph) * r, 0.25 + sin(ph * 2.0) * 0.3, sin(ph) * r)
			(g as Node3D).rotation = Vector3(-0.35, -ph + PI * 0.5, 0.0)

## The night's stages, chained as attacks; the dark comes down through the rise and the ticks run through the hold.
static func _update_night(h: Hero, delta: float) -> void:
	var w: Dictionary = h.wr
	if not w.has("night"):
		return
	var n: Dictionary = w["night"]
	if h.dead or h.atk_skill != "night" and h.atk_t >= 0.0:
		end_night(h, false)
		return
	n["t"] = float(n["t"]) + delta
	var node = n["node"]
	var stage: int = n["stage"]
	var a: float = (h.atk_t / h.atk_dur) if h.atk_t >= 0.0 else 1.0
	if stage == 0:
		WraithFx.set_night(node, smoothstep(0.0, 0.85, a))
		_set_glow(h, 1.0 + a * 2.5)
	if stage == 2:
		n["tick"] = float(n["tick"]) - delta
		if float(n["tick"]) <= 0.0:
			n["tick"] = NIGHT_TICK
			var any := false
			for e in h.game.enemies_near(h.global_position, NIGHT_R - 1.0):
				h._hit_enemy(e, 0.3, 0.0, "night", spirit(h, 0.25))
				any = true
			if any:
				Fx.burst(h.game.world.fx_root, h.global_position + Vector3(0, 1.2, 0), WraithFx.VIOLET, 10, 6.0, 0.1, 0.4, true, 0.0, 180.0)
	if stage == 3 and a > 0.2:
		_set_hover(h, NIGHT_HOVER * (1.0 - smoothstep(0.2, 0.5, a)))
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
	if w.has("phantoms"):
		for p in w["phantoms"]:
			if is_instance_valid(p["node"]):
				(p["node"] as Node).queue_free()
		w.erase("phantoms")
	if h.rig != null and h.rig.has_meta("claws"):
		WraithFx.set_claws(h.rig, 0.0)
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

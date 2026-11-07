class_name BgBoss
extends RefCounted
## The Battlegrounds' bosses' brains (Blaine's overhaul): Hrimgar the Frostbound (ice_troll, the Frozen Depths) and
## Old Mossbeard (hermit, the Overgrown Vault), and the hermit's poison mushrooms (spore_shroom). Host-side like
## the Hollow Sloth's brain (sloth.gd): Enemy._process hands this the frame (`vel = brain.update(...)`); every timed
## move is an atk_t / atk_dur / atk_style (so its pose plays on every peer), and everything seen is an Enemy fx
## event ("bb_*", BgBoss.fx on every game) sent before it lands, so a player can read it and answer it.
##
## Hrimgar: heavy and slow, every blow wound up where you can see it.
##   Glacial Slam   both fists down: a ring 6 m round him (1.0 s warning), freezes those in it.
##   Frost Lances   a line of ice spears bursting out of the floor toward his target (crack line, 0.9 s), chills.
##   Rime Roar      a cone of frozen breath, 9 m (0.8 s), chills and pushes back.
##   Avalanche      under half life, every 16 s: ice falls on marked circles round the hall and under each hero.
##   (in reach)     a clubbing swing.
## Mossbeard: keeps his distance and makes the ground itself dangerous.
##   Spore Bolt     a poison bolt (his basic, the "poison" projectile).
##   Sprouting      his signature: 3 poison mushrooms burst up round the heroes (max 6); each breathes a cloud of
##                  poison (POISON_R) every 1.5 s: where you can stand changes, until you cut them down.
##   Thorn Snare    roots erupt under his target after a green ring (1.0 s): rooted and hurt.
##   Spore Step     under 60% life he vanishes in spores and steps out of one of his mushrooms.
##   Bramble Burst  under 30%: thorns lash out round him (4.5 m), throwing heroes back.

const POISON_R := 3.0
const MAX_SHROOMS := 6

var e: Enemy
var kind := ""
var move := ""
var cds := {}
var aim := Vector3.ZERO
var aim_dir := Vector3.FORWARD
var marks: Array = []          # avalanche circles (positions)
var _pulse := 0.0
var _had_maker := false        # a mushroom: a hermit of its pack was seen (see _shroom)

const MOVES := {
	# move: [seconds, impact at (0..1), style]
	"bb_slam": [1.9, 0.55, "slam"], "bb_lances": [1.6, 0.6, "smash"], "bb_roar": [1.5, 0.55, "cast"],
	"bb_avalanche": [2.4, 0.6, "cast"], "bb_swing": [1.25, 0.5, "over"],
	"bb_bolt": [1.0, 0.55, "cast"], "bb_sprout": [1.5, 0.6, "cast"], "bb_snare": [1.3, 0.75, "cast"],
	"bb_step": [0.9, 0.5, "cast"], "bb_burst": [1.4, 0.6, "slam"],
}

func _init(en: Enemy) -> void:
	e = en
	kind = en.kind
	for m in MOVES:
		cds[m] = randf_range(1.0, 3.0)

func _target() -> Hero:
	var best: Hero = null
	var bd := 1e9
	for h in e.game.all_heroes():
		if not is_instance_valid(h) or h.dead or h.get("phased") == true:
			continue
		var d: float = h.global_position.distance_to(e.global_position)
		if d < bd and d < 30.0:
			bd = d
			best = h
	return best

func _heroes_in(at: Vector3, r: float) -> Array:
	return e.game.all_heroes().filter(func(h) -> bool: return is_instance_valid(h) and not h.dead and Vector2(h.global_position.x - at.x, h.global_position.z - at.z).length() < r)

## The frame: returns the velocity (Enemy._process moves it with the usual separation and collision).
func update(delta: float, _hero: Node3D, _to: Vector3, _dist: float, _gone: bool) -> Vector3:
	for m in cds:
		cds[m] = float(cds[m]) - delta
	if kind == "spore_shroom":
		return _shroom(delta)
	var tgt := _target()
	if e.stun_t > 0.0:
		e.stun_t -= delta
		return Vector3.ZERO
	if move != "":
		if e.atk_t < 0.0:
			move = ""
		elif tgt != null:
			return _play(delta, tgt)
		else:
			e.atk_t = -1.0
			move = ""
	if tgt == null:
		e.aggro = false
		return Vector3.ZERO
	if not e.aggro:
		if tgt.global_position.distance_to(e.global_position) > float(e.def.get("aggro", 15.0)):
			return Vector3.ZERO
		e.aggro = true
		e.game.on_boss_aggro(e)
		e._fx("bear_roar")          # (its roar, and the intro card with it)
	var to := tgt.global_position - e.global_position
	to.y = 0
	var dist := to.length()
	var pick := _choose(tgt, dist)
	if pick != "":
		_start(pick, tgt)
		return Vector3.ZERO
	# close in (the troll) or keep a casting distance (the hermit)
	var want := 2.4 if kind == "ice_troll" else 8.0
	if dist > want:
		return to.normalized() * e.speed
	if kind == "hermit" and dist < 5.0:
		return -to.normalized() * e.speed * 0.8
	e._face(to)
	return Vector3.ZERO

func _ready(m: String) -> bool:
	return float(cds.get(m, 0.0)) <= 0.0

func _choose(tgt: Hero, dist: float) -> String:
	var frac := e.life / maxf(e.max_life, 1.0)
	if kind == "ice_troll":
		if frac < 0.5 and _ready("bb_avalanche"):
			return "bb_avalanche"
		if dist < 5.5 and _ready("bb_slam"):
			return "bb_slam"
		if dist < 8.5 and _ready("bb_roar"):
			return "bb_roar"
		if dist > 4.0 and dist < 13.0 and _ready("bb_lances"):
			return "bb_lances"
		if dist < 3.4 and _ready("bb_swing"):
			return "bb_swing"
		return ""
	# the hermit
	if frac < 0.3 and dist < 4.5 and _ready("bb_burst"):
		return "bb_burst"
	if frac < 0.6 and _ready("bb_step") and _shrooms().size() > 0 and dist < 6.0:
		return "bb_step"
	if _ready("bb_sprout") and _shrooms().size() < MAX_SHROOMS:
		return "bb_sprout"
	if _ready("bb_snare") and dist < 12.0:
		return "bb_snare"
	if _ready("bb_bolt") and dist < 12.0:
		return "bb_bolt"
	return ""

func _start(m: String, tgt: Hero) -> void:
	move = m
	var spec: Array = MOVES[m]
	e.atk_style = spec[2]
	e.atk_t = 0.0
	e.atk_dur = float(spec[0]) * (0.85 if e.life < e.max_life * 0.3 else 1.0)
	e.impact_done = false
	e.special = m
	aim = tgt.global_position
	aim_dir = tgt.global_position - e.global_position
	aim_dir.y = 0
	aim_dir = aim_dir.normalized() if aim_dir.length() > 0.01 else -e.rig.global_transform.basis.z
	e._face(aim_dir)
	var warn: float = e.atk_dur * float(spec[1])
	match m:
		"bb_slam":
			cds[m] = 7.0
			e._fx("bb_slam_tele:%.2f" % warn)
		"bb_lances":
			cds[m] = 6.0
			e._fx("bb_lances_tele:%.2f,%.2f,%.2f,%.2f" % [aim_dir.x, aim_dir.z, warn, 12.0])
		"bb_roar":
			cds[m] = 10.0
			e._fx("bb_roar_tele:%.2f,%.2f,%.2f" % [aim_dir.x, aim_dir.z, warn])
		"bb_avalanche":
			cds[m] = 16.0
			marks = []
			for h in _heroes_in(e.global_position, 30.0):
				marks.append(h.global_position)
			for k in 6:
				var a := randf() * TAU
				var p := e.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 12.0)
				marks.append(e.game.world.free_spot_near(p, 1.0))
			var txt := ""
			for p in marks:
				txt += "%.1f,%.1f;" % [p.x, p.z]
			e._fx("bb_aval_tele:%.2f:%s" % [warn, txt])
		"bb_swing":
			cds[m] = 1.6
		"bb_bolt":
			cds[m] = 1.8
		"bb_sprout":
			cds[m] = 12.0
			e._fx("bb_sprout_tele")
		"bb_snare":
			cds[m] = 7.0
			e._fx("bb_snare_tele:%.1f,%.1f,%.2f" % [aim.x, aim.z, warn])
		"bb_step":
			cds[m] = 10.0
		"bb_burst":
			cds[m] = 9.0
			e._fx("bb_burst_tele:%.2f" % warn)

func _play(delta: float, tgt: Hero) -> Vector3:
	e.atk_t += delta
	var a := e.atk_t / e.atk_dur
	var hit_at: float = MOVES[move][1]
	if move in ["bb_swing", "bb_bolt"] and a < hit_at * 0.8:
		e._face(tgt.global_position - e.global_position)
		aim = tgt.global_position
	if not e.impact_done and a >= hit_at:
		e.impact_done = true
		_land(tgt)
	if e.atk_t >= e.atk_dur:
		e.atk_t = -1.0
		e.special = ""
		move = ""
		e.cooldown = 0.4
	return Vector3.ZERO

func _land(tgt: Hero) -> void:
	var at := e.global_position
	match move:
		"bb_slam":
			e._fx("bb_slam")
			for h in _heroes_in(at, 6.0):
				h.take_hit(e._roll() * 1.4, at, "freeze", "cold")
		"bb_lances":
			e._fx("bb_lances:%.2f,%.2f" % [aim_dir.x, aim_dir.z])
			for h in e.game.all_heroes():
				if not is_instance_valid(h) or h.dead:
					continue
				var rel: Vector3 = h.global_position - at
				rel.y = 0
				var along := rel.dot(aim_dir)
				if along > 0.5 and along < 12.5 and (rel - aim_dir * along).length() < 1.4:
					h.take_hit(e._roll() * 1.2, at, "chill", "cold")
		"bb_roar":
			e._fx("bb_roar:%.2f,%.2f" % [aim_dir.x, aim_dir.z])
			for h in _heroes_in(at, 9.0):
				var rel: Vector3 = h.global_position - at
				rel.y = 0
				if rel.length() < 0.1 or rel.normalized().dot(aim_dir) > cos(deg_to_rad(35.0)):
					h.take_hit(e._roll() * 0.7, at, "chill", "cold")
		"bb_avalanche":
			e._fx("bb_aval")
			for p in marks:
				for h in _heroes_in(p, 2.2):
					h.take_hit(e._roll() * 1.5, p, "quake", "cold")
		"bb_swing":
			if tgt.global_position.distance_to(at) < 3.6:
				tgt.take_hit(e._roll(), at, "sweep", "phys")
		"bb_bolt":
			e._shoot(aim, "poison")
		"bb_sprout":
			var n := 0
			for h in _heroes_in(at, 26.0):
				if n >= 3 or _shrooms().size() >= MAX_SHROOMS:
					break
				var a2 := randf() * TAU
				var p: Vector3 = e.game.world.free_spot_near(h.global_position + Vector3(cos(a2), 0, sin(a2)) * randf_range(2.5, 4.5), 1.0)
				_sprout(p)
				n += 1
			while n < 3 and _shrooms().size() < MAX_SHROOMS:
				var a3 := randf() * TAU
				_sprout(e.game.world.free_spot_near(at + Vector3(cos(a3), 0, sin(a3)) * randf_range(4.0, 9.0), 1.0))
				n += 1
		"bb_snare":
			e._fx("bb_snare:%.1f,%.1f" % [aim.x, aim.z])
			for h in _heroes_in(aim, 2.0):
				h.take_hit(e._roll() * 0.9, aim, "root", "poison")
		"bb_step":
			var ss := _shrooms()
			if not ss.is_empty():
				var to: Vector3 = ss[randi() % ss.size()].global_position
				e._fx("bb_step:%.1f,%.1f" % [at.x, at.z])
				e.global_position = e.game.world.free_spot_near(to + Vector3(1.2, 0, 0), 1.0)
				e._fx("bb_step:%.1f,%.1f" % [e.global_position.x, e.global_position.z])
		"bb_burst":
			e._fx("bb_burst")
			for h in _heroes_in(at, 4.5):
				h.take_hit(e._roll() * 1.3, at, "sweep", "poison")

## His own mushrooms (his camp's and the ones he sprouted: his pack), never another camp's.
func _shrooms() -> Array:
	return e.game.world.enemies_root.get_children().filter(func(x) -> bool: return x is Enemy and not x.dead and x.kind == "spore_shroom" and x.pack_id == e.pack_id)

func _sprout(p: Vector3) -> void:
	var s: Enemy = e.game.spawn_enemy("spore_shroom", p, e.level, false, "", e.pack_id)
	if s != null:
		s.aggro = true
		s._fx("bb_shroom_up")

## A poison mushroom: stands where it sprang up, breathing its cloud every 1.5 s.
func _shroom(delta: float) -> Vector3:
	_pulse -= delta
	if _pulse <= 0.0:
		_pulse = 1.5
		# its maker gone, it withers: only Mossbeard's own (his camp's, or sprouted by him, same pack). A mushroom of a camp
		# with no hermit (Sporefall Dell, Rootknot Hollow) is just a monster. `_had_maker` remembers he was there: once he
		# is dead his body leaves the tree, and "no hermit in the pack" must not read as "never had one"
		var kin: Array = e.game.world.enemies_root.get_children().filter(func(x) -> bool: return x is Enemy and x.kind == "hermit" and x.pack_id == e.pack_id)
		if not kin.is_empty():
			_had_maker = true
		var maker: bool = (not _had_maker) or kin.any(func(x) -> bool: return not x.dead and x.global_position.distance_to(e.global_position) < 40.0)
		if not maker:
			e.take_damage(99999.0, 0.0, e.global_position, 0.0, false)
			return Vector3.ZERO
		e._fx("bb_cloud")
		for h in _heroes_in(e.global_position, POISON_R):
			h.take_hit(e._roll(), e.global_position, "burn", "poison")
	return Vector3.ZERO

# ---------------------------------------------------------------- what is seen (every game)
static func fx(en: Enemy, ev: String) -> void:
	var root: Node3D = en.game.world.fx_root
	var at := en.global_position
	var parts := ev.split(":")
	var name := parts[0]
	var args: PackedFloat64Array = PackedFloat64Array()
	if parts.size() > 1:
		for v in parts[1].split(","):
			if v.is_valid_float():
				args.append(float(v))
	var ice := Color(0.6, 0.9, 1.0)
	var tox := Color(0.45, 1.0, 0.3)
	match name:
		"bb_slam_tele":
			Fx.telegraph(root, at, 6.0, args[0] if args.size() > 0 else 1.0, ice)
		"bb_slam":
			Fx.ring(root, at, 6.0, ice, 0.6)
			Fx.burst(root, at + Vector3(0, 0.4, 0), Color(0.85, 0.95, 1.0), 60, 7.0, 0.18, 1.0, true, -6.0, 80.0)
			_spikes(root, at, 10, 2.0, 5.5)
			Sfx.play_at("slam", at, 2.0, 0.7)
			en.game.add_shake(0.6)
		"bb_lances_tele":
			var d := Vector3(args[0], 0, args[1]).normalized()
			for k in 6:
				Fx.telegraph(root, at + d * (1.5 + k * 2.0), 1.3, args[2], ice)
		"bb_lances":
			var d2 := Vector3(args[0], 0, args[1]).normalized()
			for k in 6:
				_spikes(root, at + d2 * (1.5 + k * 2.0), 3, 0.2, 1.0)
			Sfx.play_at("slam", at + d2 * 6.0, -2.0, 1.3)
		"bb_roar_tele":
			Fx.arc_telegraph(root, at, Vector3(args[0], 0, args[1]), 9.0, 35.0, args[2], ice)
			Sfx.play_at("trex_roar" if Sfx.bank.has("trex_roar") else "roar", at + Vector3(0, 3, 0), 0.0, 0.7)
		"bb_roar":
			var d3 := Vector3(args[0], 0, args[1]).normalized()
			Fx.burst(root, at + Vector3(0, 2.6, 0) + d3 * 1.0, Color(0.8, 0.95, 1.0, 0.8), 80, 9.0, 0.25, 1.0, true, -1.0, 30.0, d3)
		"bb_aval_tele":
			var w := float(parts[1]) if parts.size() > 1 else 1.4
			if parts.size() > 2:
				for pt in parts[2].split(";"):
					var xy := pt.split(",")
					if xy.size() == 2:
						Fx.telegraph(root, Vector3(float(xy[0]), 0, float(xy[1])), 2.2, w, ice)
			Sfx.play_at("roar", at, 0.0, 0.6)
		"bb_aval":
			Sfx.play_at("slam", at, 3.0, 0.6)
			en.game.add_shake(0.8)
			Fx.burst(root, at + Vector3(0, 6.0, 0), Color(0.85, 0.95, 1.0), 120, 6.0, 0.25, 1.4, true, -14.0, 180.0)
		"bb_sprout_tele":
			Fx.burst(root, at + Vector3(0, 1.2, 0), tox, 40, 3.0, 0.15, 1.0, true, 1.0)
			Sfx.play_at("summon", at, -2.0, 0.8)
		"bb_shroom_up":
			Fx.burst(root, at + Vector3(0, 0.3, 0), Color(0.35, 0.25, 0.15, 0.8), 30, 4.0, 0.2, 0.8, false, -6.0, 60.0)
			Fx.ring(root, at, POISON_R, tox, 0.5)
		"bb_cloud":
			Fx.ring(root, at, POISON_R, Color(0.45, 1.0, 0.3, 0.6), 0.9, 0.6)
			Fx.burst(root, at + Vector3(0, 0.8, 0), Color(0.5, 1.0, 0.35, 0.35), 26, 1.6, 0.6, 1.4, false, 0.4, 180.0)
		"bb_snare_tele":
			Fx.telegraph(root, Vector3(args[0], 0, args[1]), 2.0, args[2], tox)
		"bb_snare":
			var p := Vector3(args[0], 0, args[1])
			_thorns(root, p, 8, 2.0)
			Sfx.play_at("slam", p, -4.0, 1.5)
		"bb_step":
			Fx.burst(root, Vector3(args[0], 1.0, args[1]), tox, 60, 3.5, 0.2, 1.0, true, 0.6)
			Sfx.play_at("portal", Vector3(args[0], 1.0, args[1]), -6.0, 1.3)
		"bb_burst_tele":
			Fx.telegraph(root, at, 4.5, args[0] if args.size() > 0 else 1.0, tox)
		"bb_burst":
			_thorns(root, at, 16, 4.5)
			Fx.ring(root, at, 4.5, tox, 0.5)
			Sfx.play_at("slam", at, 0.0, 1.1)

## Ice spears out of the floor (a burst that rises fast, holds, sinks and is gone): n of them over radius r0..r1.
static func _spikes(root: Node3D, at: Vector3, n: int, r0: float, r1: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.92, 1.0, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.3, 0.7, 1.0)
	m.emission_energy_multiplier = 1.2
	m.roughness = 0.1
	for i in n:
		var a := TAU * i / n + randf() * 0.4
		var r := randf_range(r0, r1)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = randf_range(0.18, 0.32)
		cm.height = randf_range(1.0, 1.9)
		mi.mesh = cm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.global_position = at + Vector3(cos(a) * r, -cm.height * 0.5, sin(a) * r)
		mi.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
		var tw := mi.create_tween()
		tw.tween_property(mi, "position:y", mi.position.y + cm.height * 0.85, 0.12)
		tw.tween_interval(0.9)
		tw.tween_property(mi, "position:y", mi.position.y - 0.3, 0.5)
		tw.tween_callback(mi.queue_free)

## Thorny roots lashing up (the snare, the burst): dark curved spikes that whip up and sink.
static func _thorns(root: Node3D, at: Vector3, n: int, r: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.15, 0.08)
	m.roughness = 0.9
	for i in n:
		var a := TAU * i / n + randf() * 0.5
		var rr := randf_range(0.3, r)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.08
		cm.height = randf_range(0.8, 1.6)
		mi.mesh = cm
		mi.material_override = m
		root.add_child(mi)
		mi.global_position = at + Vector3(cos(a) * rr, -cm.height * 0.5, sin(a) * rr)
		mi.rotation = Vector3(randf_range(-0.6, 0.6), randf() * TAU, randf_range(-0.6, 0.6))
		var tw := mi.create_tween()
		tw.tween_property(mi, "position:y", mi.position.y + cm.height * 0.8, 0.1)
		tw.tween_interval(1.1)
		tw.tween_property(mi, "position:y", mi.position.y - 0.4, 0.4)
		tw.tween_callback(mi.queue_free)

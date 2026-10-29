class_name Enemy
extends Node3D
## Monster AI: melee, ranged and boss behaviours.

var game: Node
var kind := ""
var def: Dictionary
var display_name := ""
var level := 1
var max_life := 10.0
var life := 10.0
var dmg := [1, 2]
var armor := 0
var speed := 3.0
var xp := 10
var radius := 0.5
var height := 1.0
var champion := false
var boss := false
var rig: Node3D
var dead := false
var dead_t := 0.0
var aggro := false
var atk_t := -1.0
var atk_dur := 1.0
var atk_style := "over"
var impact_done := false
var cooldown := 0.0
var hit_t := 0.0
var stun_t := 0.0
var flash_t := 0.0
var knock := Vector3.ZERO
var phase := 0.0
var move_amt := 0.0
var anim_time := 0.0
var path := PackedVector3Array()
var repath := 0.0
var wander_t := 0.0
var wander_to := Vector3.ZERO
var home := Vector3.ZERO
var meshes: Array = []
var flash_mat: StandardMaterial3D
var special := ""
var summon_t := 8.0
var slam_t := 5.0
var volley_t := 4.0
var nova_t := 9.0
var enraged := false
## King Grubb's fight (hoard.gd): on the king and on each of his Gold Grabbers (host side).
var hoard: Hoard = null
## Factions (Data.ENEMIES "faction"): goblins and the undead fight each other on sight (and both fight you).
var rival: Enemy = null
var rival_t := 0.0
var _by_rival := false        # set while a rival's blow lands
var killed_by_rival := false  # no xp or loot for a kill the heroes didn't make
var pack_id := 0
# co-op: on a joining player's game every monster is remote and follows the host
var net_id := 0
var remote := false
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_atk := -1.0
var net_hit := 0.0
var _net_phase_rate := 0.0
var _net_t := 0.0
## The Feral (feral.gd): clinging to a trunk (perch_dir points from the trunk out at him; perch_h > 0 while
## he is up there), and its fight: lunge, back off ("back"), come in for the claws.
var perch_h := 0.0
var perch_dir := Vector3.ZERO
var f_state := ""
var f_t := 0.0
var lunge_cd := 1.5
var f_n := 0
var f_chase := 0.0     # seconds the hero has kept out of reach; at 6 it gives up and goes home
var f_calm := 0.0      # after giving up it won't notice you again for a while (unless hit)
var lunge_from := Vector3.ZERO
var lunge_to := Vector3.ZERO
var slot_a := 0.0

func setup(g: Node, k: String, lvl: int, champ := false, champ_name := "") -> void:
	game = g
	kind = k
	def = Data.ENEMIES[k]
	level = lvl
	champion = champ
	boss = def.get("boss", false)
	var lf := 1.0 + 0.3 * (lvl - 1)
	var df := 1.0 + 0.17 * (lvl - 1)
	var hard: float = g.run_mult("boss_life" if boss else "life")
	var hit: float = g.run_mult("dmg")
	max_life = def["life"] * lf * (2.4 if champ else 1.0) * hard
	life = max_life
	dmg = [def["dmg"][0] * df * (1.4 if champ else 1.0) * hit, def["dmg"][1] * df * (1.4 if champ else 1.0) * hit]
	armor = int(def.get("armor", 0) * (1.0 + 0.1 * lvl) * hard)
	speed = def["speed"] * (1.15 if champ else 1.0)
	xp = int(def["xp"] * (1.0 + 0.12 * (lvl - 1)) * (3.0 if champ else 1.0) * g.xp_mult())
	radius = def.get("radius", 0.5)
	display_name = champ_name if champ_name != "" else def["name"]
	atk_style = def["atk"]
	atk_dur = def["atk_time"]
	var look: Dictionary = def["look"]
	height = look.get("height", look.get("size", 1.0))
	if def.get("mesh", "") == "feral" and Feral.ok():
		rig = Feral.build()
		slot_a = randf_range(-1.6, 1.6)
		lunge_cd = randf_range(0.3, 3.0)
	elif def.has("mesh") and MeshyMonster.ok(def["mesh"]):
		rig = MeshyMonster.build(def["mesh"], look)
	elif def.has("model"):
		rig = Goblin.build(def["model"])
	elif def.has("skin"):
		rig = SkeletonModel.build(def["skin"])
		if absf(height - 1.0) > 0.01:
			rig.scale = Vector3.ONE * height
	else:
		rig = Models.crawler(look) if def["rig"] == "crawler" else Models.humanoid(look)
	add_child(rig)
	var pers := "warrior"
	match k:
		"zombie", "mummy": pers = "zombie"
		"skel_archer": pers = "skeleton"
		"fallen", "imp", "fetish": pers = "fallen"
		"grabber", "goblin_guard": pers = "goblin"
	if boss:
		pers = "boss"
	rig.set_meta("pers", pers)
	if champ:
		rig.scale = Vector3.ONE * 1.15
	_collect_meshes(rig)
	flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.albedo_color = Color(1, 1, 1, 0)
	if champ:
		var rimm := Mats.glow(Color(0.35, 0.55, 1.0), 1.2, 0.0, 1.0)
		for m in meshes:
			(m as MeshInstance3D).material_overlay = rimm
	if boss:
		var l := OmniLight3D.new()
		l.light_color = look.get("eyes", Color(1, 0.3, 0.1))
		l.light_energy = 1.2
		l.omni_range = 6.0
		l.position = Vector3(0, height * 1.7, -0.3)
		add_child(l)
		if def.has("model"):
			# a boss gets lit like one: a warm key from the front and a cold rim from behind
			var key := OmniLight3D.new()
			key.light_color = Color(1.0, 0.78, 0.5)
			key.light_energy = 1.6
			key.omni_range = 5.5
			key.position = Vector3(1.2, height * 2.2, -2.2)
			rig.add_child(key)
			var rim := OmniLight3D.new()
			rim.light_color = Color(0.45, 0.6, 1.0)
			rim.light_energy = 2.2
			rim.omni_range = 4.5
			rim.position = Vector3(-0.6, height * 2.0, 1.8)
			rig.add_child(rim)
	rig.rotation.y = randf() * TAU
	home = global_position
	if def.get("hoard", false):
		hoard = Hoard.new(self)
		hoard.call_deferred("start")

func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	for c in n.get_children():
		_collect_meshes(c)

func _set_flash(v: float) -> void:
	flash_mat.albedo_color = Color(1, 0.95, 0.9, v * 0.6)
	if champion:
		return
	var rest: Material = soul_mat() if _soul_lit else (drain_mat() if _drained else (Feral.rim_mat() if rig.has_meta("feral") else null))
	for m in meshes:
		if is_instance_valid(m):
			(m as MeshInstance3D).material_overlay = flash_mat if v > 0.01 else rest

## A softer, coloured hit flash (Drain Life ticks), so a held beam doesn't strobe the victim white.
func drain_flash(col: Color) -> void:
	flash_mat.albedo_color = Color(col.r, col.g, col.b, 0.3)

## Held in a Warlock's Drain Life beam: a green rim-light for as long as the beam holds on.
static var _drain_mat: Material
var _drained := false
## Damage numbers in this colour, and no blood (set around a Drain Life tick). Alpha 0 = normal.
var dmg_tint := Color(0, 0, 0, 0)

static func drain_mat() -> Material:
	if _drain_mat == null:
		_drain_mat = Mats.glow(Color(0.25, 1.0, 0.2), 0.75, 0.0, 1.0)
	return _drain_mat

func set_drained(on: bool) -> void:
	if on == _drained or champion:
		return
	_drained = on
	_set_flash(0.0)

## Seen from the Underworld (Demon's Phase) every monster burns with a crimson soul-outline.
static var _soul_mat: Material
var _soul_lit := false

static func soul_mat() -> Material:
	if _soul_mat == null:
		_soul_mat = Mats.glow(Color(1.0, 0.15, 0.25), 1.6, 0.0, 1.0)
	return _soul_mat

func set_soul_lit(on: bool) -> void:
	if on == _soul_lit or champion:
		return
	_soul_lit = on
	_set_flash(0.0)

func stun(t: float) -> void:
	if remote:
		game.net.send_enemy_stun(self, t)
		return
	if boss:
		t *= 0.3
	stun_t = maxf(stun_t, t)
	atk_t = -1.0

func take_damage(phys: float, fire: float, from: Vector3, knockback: float, crit: bool) -> float:
	if dead:
		return 0.0
	aggro = true
	if game.test_onehit:
		phys = maxf(phys, life * 10.0 + 1000000.0)   # testing switch (F8): any hit kills
	var p := phys * 100.0 / (100.0 + armor * 0.6)
	var total := p + fire
	if remote:
		# the host applies the real damage; show the hit straight away
		game.net.send_enemy_hit(self, phys, fire, from, knockback, crit)
		flash_t = 0.12
		_set_flash(1.0)
		var c2 := Color(1.0, 0.95, 0.8) if not crit else Color(1.0, 0.75, 0.2)
		if fire > p:
			c2 = Color(1.0, 0.55, 0.15)
		if dmg_tint.a > 0.0:
			c2 = dmg_tint
		Fx.number(game.world.fx_root, global_position + Vector3(0, height * 1.9 + 0.3, 0), str(int(total)) + ("!" if crit else ""), c2, crit)
		if dmg_tint.a <= 0.0:
			Fx.blood(game.world.fx_root, global_position + Vector3(0, height * 1.0, 0), def.get("blood", Color(0.5, 0.0, 0.0)))
		_hit_sound(phys, knockback, crit)
		return total
	life -= total
	killed_by_rival = _by_rival
	hit_t = 1.0 if not boss else 0.3
	flash_t = 0.12
	_set_flash(1.0)
	var away := global_position - from
	away.y = 0
	if away.length() > 0.01:
		knock += away.normalized() * knockback * (0.25 if boss else 1.0)
	var col := Color(1.0, 0.95, 0.8) if not crit else Color(1.0, 0.75, 0.2)
	if fire > p:
		col = Color(1.0, 0.55, 0.15)
	if dmg_tint.a > 0.0:
		col = dmg_tint
	Fx.number(game.world.fx_root, global_position + Vector3(0, height * 1.9 + 0.3, 0), str(int(total)) + ("!" if crit else ""), col, crit)
	if dmg_tint.a <= 0.0:
		Fx.blood(game.world.fx_root, global_position + Vector3(0, height * 1.0, 0), def.get("blood", Color(0.5, 0.0, 0.0)))
	_hit_sound(phys, knockback, crit)
	if fire > 0.0:
		Fx.burst(game.world.fx_root, global_position + Vector3(0, height, 0), Color(1.0, 0.5, 0.1), 8, 2.0, 0.15, 0.5, true, 2.0)
	if life <= 0.0:
		_die()
	elif not boss and atk_t >= 0.0 and atk_t / atk_dur < Anim.impact_at(atk_style) * 0.6 and total > max_life * 0.25:
		atk_t = -1.0
	return total

## The nearest living enemy of another faction within sight range.
func _find_rival() -> Enemy:
	var best: Enemy = null
	var bd := 13.0
	for e in game.enemies_near(global_position, 13.0):
		if e == self or e.dead or not e.def.has("faction") or e.def["faction"] == def["faction"]:
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = e
	return best

## A blow from a rival monster (the same call a hero's take_hit gets, so the attack code works on both).
func take_hit(amount: float, from: Vector3, _kind := "melee", _elem := "") -> void:
	_by_rival = true
	take_damage(amount, 0.0, from, 0.5, false)
	_by_rival = false

## What this monster is made of, for its hit and death sounds: bone (skeletons) or flesh.
func material() -> String:
	return def.get("material", "bone" if def.has("skin") or kind == "skel_archer" else "flesh")

## A blow landing: the impact for its body (from where it stands), and a sting on a crit. Burning,
## draining and pool ticks (no blow: no knockback, no physical damage) stay quiet.
func _hit_sound(phys: float, knockback: float, crit: bool) -> void:
	if dmg_tint.a > 0.0 or (knockback <= 0.0 and phys <= 0.0 and not crit):
		return
	var pos := global_position + Vector3(0, height, 0)
	Sfx.play_at("impact_" + material(), pos, 0.0 if boss else -2.0)
	if crit:
		Sfx.play_at("crit_sting", pos, -4.0)

func _die() -> void:
	if hoard != null:
		if hoard.boss == self:
			hoard.on_death()
		else:
			hoard.on_grabber_died(self)
	die_visual()
	game.net.enemy_died(self)
	if not killed_by_rival:
		game.on_enemy_killed(self)

func die_visual() -> void:
	dead = true
	dead_t = 0.0
	atk_t = -1.0
	life = 0.0
	_drained = false
	_set_flash(0.0)
	if boss:
		Sfx.play("boss_die", 0.0, randf_range(0.85, 1.15))
	else:
		Sfx.play_at("kill_" + material(), global_position + Vector3(0, height, 0), -1.0)
	Fx.splat(game.world.fx_root, global_position, def.get("blood", Color(0.4, 0, 0)), 0.6 + radius)
	Fx.burst(game.world.fx_root, global_position + Vector3(0, height * 0.8, 0), def.get("blood", Color(0.4, 0, 0)), 26, 4.0, 0.14, 0.8, false, -9.0)

func apply_net_state(x: float, z: float, yaw: float, mv: float, ph: float, atk: float, style: String, hit: float, lf: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var dt := clampf(now - _net_t, 0.02, 0.3)
	_net_t = now
	if absf(ph - phase) < 6.0:
		_net_phase_rate = (ph - phase) / dt
	else:
		phase = ph
	net_pos = Vector3(x, 0, z)
	net_yaw = yaw
	move_amt = mv
	if atk >= 0.0 and net_atk < 0.0:
		_swing_sound()
	net_atk = atk
	atk_style = style
	net_hit = hit
	life = lf

func _remote_process(delta: float) -> void:
	var k := clampf(delta * 12.0, 0.0, 1.0)
	var p := global_position
	p.x = lerpf(p.x, net_pos.x, k)
	p.z = lerpf(p.z, net_pos.z, k)
	if Vector2(net_pos.x - global_position.x, net_pos.z - global_position.z).length() > 8.0:
		p = net_pos
	p.y = game.world.height_at(p.x, p.z)
	if rig.has_meta("feral"):
		p.y += Feral.perch_pose(rig, atk_style, net_atk)
	global_position = p
	rig.rotation.y = lerp_angle(rig.rotation.y, net_yaw, k)
	phase += _net_phase_rate * delta
	_pose({"time": anim_time, "phase": phase, "move": move_amt, "atk": net_atk,
		"style": atk_style, "hit": net_hit, "zombie": kind in ["zombie", "mummy"], "aggro": aggro})

## Visual and sound side of the special attacks, run on every player's game.
func special_fx(ev: String) -> void:
	if hoard != null and hoard.boss == self and hoard.fx(ev):
		return
	var col := Color(0.4, 1.0, 0.3) if def.get("nova", "") == "poison" else Color(1.0, 0.4, 0.1)
	match ev:
		"slam_tele":
			Fx.telegraph(game.world.fx_root, global_position, 4.2, atk_dur * Anim.impact_at("slam"))
		"nova_tele":
			Fx.telegraph(game.world.fx_root, global_position, 7.0, atk_dur * Anim.impact_at("cast"), col)
		"slam":
			Fx.ring(game.world.fx_root, global_position, 4.5, Color(1.0, 0.5, 0.2), 0.45)
			Fx.burst(game.world.fx_root, global_position + Vector3(0, 0.3, 0), Color(0.45, 0.4, 0.35, 0.8), 40, 6.0, 0.35, 0.9, false, -4.0, 80.0)
			Sfx.play("slam")
			game.add_shake(0.6)
		"summon":
			Fx.ring(game.world.fx_root, global_position, 5.0, Color(0.7, 0.2, 1.0), 0.6)
			Sfx.play("summon")
		"nova":
			Fx.ring(game.world.fx_root, global_position, 7.0, col, 0.6)
			Fx.burst(game.world.fx_root, global_position + Vector3(0, 1, 0), col, 50, 8.0, 0.2, 0.7, true, 0.0)
			Sfx.play("nova")
			game.add_shake(0.4)
		"enrage":
			game.ui.message(display_name + " is enraged!", Color(1.0, 0.3, 0.2))
			Sfx.play("roar")
		"boss_hit":
			game.add_shake(0.2)
			var front := global_position - rig.global_transform.basis.z * (radius + 1.0)
			Fx.burst(game.world.fx_root, front + Vector3(0, 0.15, 0), Color(0.4, 0.35, 0.3, 0.8), 22, 3.0, 0.25, 0.7, false, -3.0, 80.0)
		# a Gold Grabber hauling a pile back to King Grubb
		"carry_on":
			rig.set_meta("carry", true)
		"carry_off":
			rig.remove_meta("carry")

func _fx(ev: String) -> void:
	special_fx(ev)
	game.net.enemy_fx(self, ev)

func _process(delta: float) -> void:
	if game == null or game.hero == null or game.world == null or not is_inside_tree():
		return
	anim_time += delta
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			_set_flash(0.0)
	if dead:
		dead_t += delta
		var f := clampf(dead_t / 0.6, 0.0, 1.0)
		if rig.has_meta("crawler"):
			rig.rotation.z = f * PI
			rig.position.y = f * 0.4 * height
		elif rig.has_meta("feral"):
			rig.rotation.x = 0.0
			rig.rotation.z = f * f * 1.35      # rolls onto his side
		elif rig.has_meta("goblin"):
			# knees buckle, then he topples forward onto his belly with a bounce
			rig.rotation.x = -Anim.kf(dead_t, [[0.0, 0.0], [0.5, 0.08], [1.1, 1.3], [1.25, 1.18], [1.4, 1.28]])
			if dead_t > 1.1 and dead_t - delta <= 1.1 and boss:
				game.add_shake(0.5)
				Fx.burst(game.world.fx_root, global_position - rig.global_transform.basis.z * 1.5, Color(0.4, 0.35, 0.3, 0.8), 40, 4.0, 0.3, 0.9, false, -3.0, 80.0)
		else:
			rig.rotation.x = f * f * 1.45
		_pose({"time": anim_time, "hit": 1.0 - f, "dead": minf(dead_t, 1.0)})
		if dead_t > 8.0:
			rig.position.y -= delta * 0.4
		if dead_t > 11.0:
			queue_free()
		return
	if hoard != null and hoard.boss == self:
		hoard.murmur(delta)
	if remote:
		_remote_process(delta)
		return
	var hero: Node3D = game.target_for(self)
	if def.has("faction"):
		rival_t -= delta
		if rival_t <= 0.0:
			rival_t = 0.4 + randf() * 0.2
			rival = _find_rival()
		if rival != null and (not is_instance_valid(rival) or rival.dead):
			rival = null
		# a rival close by (closer than the hero) is fought first
		if rival != null and (hero.dead or rival.global_position.distance_to(global_position) < hero.global_position.distance_to(global_position) * 0.85):
			hero = rival
			aggro = true
	var to := hero.global_position - global_position
	to.y = 0
	var dist := to.length()
	if perch_h > 0.0:
		_feral_perch(delta, hero, dist)
		return
	if dist > 50.0 and not boss:
		return
	hit_t = maxf(0.0, hit_t - delta * 4.0)
	if knock.length() > 0.01:
		global_position = game.world.move(global_position, knock * delta * 6.0, body_r())
		knock = knock.lerp(Vector3.ZERO, clampf(delta * 8.0, 0.0, 1.0))
	cooldown = maxf(0.0, cooldown - delta)
	f_calm = maxf(0.0, f_calm - delta)
	if hoard != null and hoard.boss == self and aggro:
		hoard.update(delta)
	var vel := Vector3.ZERO
	# a Demon phased into the Underworld cannot be seen
	var hero_dead: bool = hero.dead or hero.get("phased") == true
	if stun_t > 0.0:
		stun_t -= delta
	elif atk_t >= 0.0:
		_update_attack(delta, hero, dist)
	else:
		if not aggro and f_calm <= 0.0 and dist < def.get("aggro", 12.0) and not hero_dead and game.world.los(global_position, hero.global_position):
			aggro = true
			if boss:
				game.on_boss_aggro(self)
			for e in game.enemies_near(global_position, 8.0):
				if e.pack_id == pack_id:
					e.aggro = true
		if hero_dead:
			aggro = false
		if aggro:
			vel = _think_combat(delta, hero, to, dist)
		else:
			vel = _wander(delta)
	# separation
	for e in game.enemies_near(global_position, radius * 2.0 + 0.6):
		if e == self or e.dead:
			continue
		var away: Vector3 = global_position - e.global_position
		away.y = 0
		var dd := away.length()
		if dd < 0.01:
			away = Vector3(randf() - 0.5, 0, randf() - 0.5)
			dd = 0.1
		var push: float = (radius + e.radius - dd)
		if push > 0.0:
			vel += away / dd * push * 4.0
	if not hero_dead and dist < radius + hero.radius:
		vel -= to.normalized() * (radius + hero.radius - dist) * 4.0
	if vel.length() > 0.01:
		global_position = game.world.move(global_position, vel * delta, body_r())
		if aggro or vel.length() > 0.5:
			if atk_t < 0.0:
				_face(to if aggro and (dist <= 3.0 or f_state in ["back", "out"]) else vel)
		move_amt = move_toward(move_amt, clampf(vel.length() / maxf(speed, 0.1), 0.0, 1.0), delta * 5.0)
		var was := phase
		phase += delta * vel.length() * (1.6 / maxf(height, 0.5)) * (-1.0 if f_state in ["back", "out"] else 1.0)
		if boss and rig.has_meta("goblin") and floorf(phase / PI) != floorf(was / PI) and move_amt > 0.4:
			_footstep()
	else:
		move_amt = move_toward(move_amt, 0.0, delta * 5.0)
	global_position.y = game.world.height_at(global_position.x, global_position.z)
	_pose({"time": anim_time, "phase": phase, "move": move_amt, "atk": (atk_t / atk_dur) if atk_t >= 0.0 else -1.0,
		"style": atk_style, "hit": hit_t, "zombie": kind in ["zombie", "mummy"], "aggro": aggro})

func _pose(st: Dictionary) -> void:
	if rig.has_meta("feral"):
		Feral.pose(rig, st, height)
	else:
		Anim.pose(rig, st)

## A heavy boss's footfall: a puff of dust under the planted foot, and the ground shakes a
## little if you're close.
func _footstep() -> void:
	var side := 1.0 if int(floorf(phase / PI)) % 2 == 0 else -1.0
	var foot := global_position + rig.global_transform.basis.x * side * 0.35
	Fx.burst(game.world.fx_root, foot + Vector3(0, 0.08, 0), Color(0.38, 0.33, 0.28, 0.6), 8, 1.2, 0.2, 0.6, false, -1.0, 70.0)
	if game.hero.global_position.distance_to(global_position) < 7.0:
		game.add_shake(0.06)

## The radius it collides with props and walls at: a boss's real bulk (so a 3.5 m King Grubb
## doesn't wade through pillars), everyone else the usual body size (they fit through gaps).
func body_r() -> float:
	return clampf(radius * 0.75, World.BODY_R, 1.1) if boss else World.BODY_R

## How tall it stands, in metres (mouse picking).
func top() -> float:
	return height * 1.8 * (1.15 if champion else 1.0)

func _face(d: Vector3) -> void:
	d.y = 0
	if d.length() > 0.01:
		var want := atan2(-d.x, -d.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, want, 0.25)

func _think_combat(delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	var ai: String = def["ai"]
	if hoard != null:
		var v: Variant = hoard.steer(self, delta)
		if v != null:
			return v
	if ai == "feral":
		return _feral_combat(delta, hero, to, dist)
	var rng_atk: float = def["range"]
	if boss:
		if not enraged and life < max_life * 0.35 and hoard == null:
			enraged = true
			speed *= 1.3
			atk_dur *= 0.8
			_fx("enrage")
		summon_t -= delta
		slam_t -= delta
		volley_t -= delta
		nova_t -= delta
		if summon_t <= 0.0 and def.get("summon", "") != "":
			summon_t = 16.0 if not enraged else 11.0
			_begin_special("summon")
			return Vector3.ZERO
		if slam_t <= 0.0 and def.get("slam", false) and dist < 6.0:
			slam_t = 7.0 if not enraged else 5.0
			_begin_special("slam")
			return Vector3.ZERO
		if volley_t <= 0.0 and def.get("proj", "") != "" and dist > 4.0:
			volley_t = 5.0
			_begin_special("volley")
			return Vector3.ZERO
		if nova_t <= 0.0 and def.get("nova", "") != "" and dist < 7.0:
			nova_t = 9.0
			_begin_special("nova")
			return Vector3.ZERO
	if ai == "ranged":
		var can_see: bool = game.world.los(global_position, hero.global_position)
		if dist < 4.0:
			return -to.normalized() * speed * 0.8
		if dist <= rng_atk and can_see:
			if cooldown <= 0.0:
				_face(to)
				_begin_attack("")
			return Vector3.ZERO
		return _chase(delta, hero, dist)
	if dist <= rng_atk + hero.radius * 0.5:
		if cooldown <= 0.0:
			_face(to)
			_begin_attack("")
		return Vector3.ZERO
	return _chase(delta, hero, dist)

func _chase(delta: float, hero: Node3D, _dist: float) -> Vector3:
	return go_to(delta, hero.global_position, speed)

## Velocity toward p at spd: straight when in sight, else along an A* path.
func go_to(delta: float, p: Vector3, spd: float) -> Vector3:
	if game.world.los(global_position, p):
		path = PackedVector3Array()
		var d := p - global_position
		d.y = 0
		return Vector3.ZERO if d.length() < 0.05 else d.normalized() * spd
	repath -= delta
	if repath <= 0.0 or path.is_empty():
		repath = 0.6 + randf() * 0.4
		path = game.world.find_path(global_position, p)
	if path.is_empty():
		return Vector3.ZERO
	var nxt := path[0]
	var dv := Vector3(nxt.x - global_position.x, 0, nxt.z - global_position.z)
	if dv.length() < 0.4:
		path.remove_at(0)
	return dv.normalized() * spd

func _wander(delta: float) -> Vector3:
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = randf_range(2.0, 5.0)
		wander_to = game.world.free_spot_near(home, 4.0) if randf() < 0.6 else global_position
	var d := wander_to - global_position
	d.y = 0
	if d.length() < 0.3:
		return Vector3.ZERO
	return d.normalized() * speed * 0.35

func _begin_attack(sp: String) -> void:
	special = sp
	atk_t = 0.0
	impact_done = false
	if sp == "":
		atk_style = def["atk"]
	_swing_sound()

## A monster's swing, from where it stands: a heavy whoosh for big ones; a boss growls.
func _swing_sound() -> void:
	if boss:
		Sfx.play("growl", -8.0, randf_range(0.6, 0.8))
	else:
		Sfx.play_at("swing_heavy" if height > 1.4 else "swing_light", global_position + Vector3(0, height, 0), -6.0, randf_range(0.9, 1.15) / maxf(height, 0.6))

func _begin_special(sp: String) -> void:
	match sp:
		"slam":
			atk_style = "slam"
			_begin_attack("slam")
			_fx("slam_tele")
		"summon", "nova", "volley":
			atk_style = "cast"
			_begin_attack(sp)
			if sp == "nova":
				_fx("nova_tele")
		"feral_lunge":
			atk_style = sp
			atk_dur = 0.9
			_begin_attack(sp)
		# King Grubb (hoard.gd): a lobbed bomb, scooping gold, staggering, cackling
		"bomb", "scoop", "burst", "cackle":
			atk_style = "lob" if sp == "bomb" else sp
			_begin_attack(sp)

func _update_attack(delta: float, hero: Node3D, dist: float) -> void:
	atk_t += delta
	var a := atk_t / atk_dur
	if special == "feral_lunge":
		# airborne from the launch to the landing: over whatever is in the way (other monsters too)
		var want := lunge_from.lerp(lunge_to, smoothstep(0.18, 0.62, a)) - global_position
		want.y = 0
		global_position = game.world.move(global_position, want, body_r())
	if a < Anim.impact_at(atk_style) * 0.8 and special in ["", "volley", "bomb"]:
		_face(hero.global_position - global_position)
	if not impact_done and a >= Anim.impact_at(atk_style):
		impact_done = true
		_impact(hero, dist)
	if atk_t >= atk_dur:
		atk_t = -1.0
		cooldown = randf_range(0.3, 0.8) * (0.5 if boss else 1.0)
		if special == "feral_lunge":
			# after the leap he backs off a few steps, watching, before coming in for the claws
			f_state = "back"
			f_t = randf_range(0.7, 1.1)
			atk_dur = def["atk_time"]
		special = ""

func _roll() -> float:
	return randf_range(dmg[0], dmg[1])

func _impact(hero: Node3D, dist: float) -> void:
	var fwd := -rig.global_transform.basis.z
	match special:
		"":
			if def["ai"] == "ranged":
				_shoot(hero.global_position, def.get("proj", "arrow"))
			else:
				var to: Vector3 = hero.global_position - global_position
				to.y = 0
				if dist <= def["range"] + hero.radius + 0.8 and fwd.dot(to.normalized()) > 0.2:
					hero.take_hit(_roll(), global_position, "melee")
				if boss:
					_fx("boss_hit")
		"slam":
			_fx("slam")
			for h in game.all_heroes():
				if not h.dead and h.global_position.distance_to(global_position) < 4.4:
					h.take_hit(_roll() * 1.5, global_position, "slam")
		"summon":
			_fx("summon")
			for i in 3:
				var p: Vector3 = game.world.free_spot_near(global_position, 5.0)
				game.spawn_enemy(def["summon"], p, level - 2, false, "", pack_id)
				Fx.burst(game.world.fx_root, p + Vector3(0, 0.5, 0), Color(0.6, 0.2, 1.0), 20, 3.0, 0.2, 0.8, true, 1.0)
		"bomb":
			hoard.throw_bomb(hero.global_position)
		"scoop":
			hoard.scooped(self)
		"volley":
			var base := hero.global_position - global_position
			for i in 5:
				var ang := (i - 2) * 0.22
				var dir := base.rotated(Vector3.UP, ang)
				_shoot(global_position + dir, def.get("proj", "fireball"))
		"nova":
			_fx("nova")
			for h in game.all_heroes():
				if not h.dead and h.global_position.distance_to(global_position) < 7.0:
					h.take_hit(_roll() * 1.2, global_position, "nova", "fire")
		"feral_lunge":
			# the claws come down where he lands
			if hero.global_position.distance_to(global_position) < radius + hero.radius + 1.1:
				hero.take_hit(_roll() * 1.5, global_position, "melee")

func _shoot(at: Vector3, pkind: String) -> void:
	var pr := Projectile.new()
	game.world.fx_root.add_child(pr)
	var from := global_position + Vector3(0, height * 1.35, 0) + (-rig.global_transform.basis.z) * 0.5
	pr.launch(game, pkind, from, at + Vector3(0, 1.1, 0), _roll())
	game.net.projectile(pkind, from, at + Vector3(0, 1.1, 0))
	Sfx.play_at("bow" if pkind in ["arrow", "dart"] else "fireball", global_position, -2.0, randf_range(0.9, 1.1))

# ---------------------------------------------------------------- the Feral (feral.gd)
## Clinging head-down to a trunk until someone comes close, then down it in a skitter, and the rest of
## its pack with it.
func perch_on(trunk: Vector3, out_dir: Vector3, h := Feral.PERCH_H) -> void:
	perch_dir = Vector3(out_dir.x, 0, out_dir.z).normalized()
	perch_h = h
	rig.rotation.y = atan2(-perch_dir.x, -perch_dir.z)
	atk_style = "perch"
	atk_t = 0.0
	atk_dur = 1.0
	global_position = Vector3(global_position.x, game.world.height_at(global_position.x, global_position.z) + Feral.perch_pose(rig, "perch", 0.0), global_position.z)

func _feral_perch(delta: float, hero: Node3D, dist: float) -> void:
	if atk_style == "perch":
		var near: bool = dist < 10.0 and not hero.dead and hero.get("phased") != true and game.world.los(global_position, hero.global_position)
		if near or aggro:
			_feral_drop()
			for e in game.enemies_near(global_position, 32.0):
				if e != self and e.pack_id == pack_id and e.perch_h > 0.0 and e.atk_style == "perch":
					e.f_t = -randf_range(0.1, 0.6)      # a beat apart, not all at once
					e._feral_drop()
	else:
		atk_t += delta
		if atk_t >= atk_dur:
			perch_h = 0.0
			atk_t = -1.0
			atk_dur = def["atk_time"]
			atk_style = def["atk"]
			rig.rotation.x = 0.0
			# off the bark and clear of the trunk's footprint
			global_position = game.world.free_spot_near(global_position + perch_dir * 0.9, 1.2)
			global_position.y = game.world.height_at(global_position.x, global_position.z)
			aggro = true
			cooldown = 0.4
			return
	var a := maxf(atk_t, 0.0) / atk_dur
	var y: float = game.world.height_at(global_position.x, global_position.z)
	global_position.y = y + Feral.perch_pose(rig, atk_style, a)
	_pose({"time": anim_time, "atk": a, "style": atk_style, "phase": phase})

func _feral_drop() -> void:
	atk_style = "descend"
	atk_dur = Feral.DESCEND_T
	atk_t = minf(f_t, 0.0)
	f_t = 0.0
	aggro = true
	Sfx.play_at("growl", global_position, -10.0, randf_range(1.15, 1.35))

## Fast, and coming at you from its own side. The pack circles about 4.5 m out; one at a time lunges,
## backs off a few steps ("back"), darts in for a rake or two with its claws ("in"), then backs out to
## the circle again ("out") for the next one's turn.
func _feral_combat(delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	lunge_cd -= delta
	# outrun for 6 s: it gives up and slinks back to its tree
	f_chase = f_chase + delta if dist > 9.0 else 0.0
	if f_chase > 6.0:
		f_chase = 0.0
		f_state = ""
		aggro = false
		f_calm = 8.0
		wander_to = home
		wander_t = 4.0
		return Vector3.ZERO
	match f_state:
		"back", "out":
			f_t -= delta
			if f_t <= 0.0:
				f_state = "in" if f_state == "back" else ""
				f_n = 0
			return -to.normalized() * speed * 0.5
		"in":
			if dist <= def["range"] + hero.radius * 0.5:
				if cooldown <= 0.0:
					if f_n >= 2 or (f_n >= 1 and randf() < 0.5):
						f_state = "out"
						f_t = randf_range(0.8, 1.2)
						return Vector3.ZERO
					f_n += 1
					_face(to)
					atk_dur = def["atk_time"]
					_begin_attack("")
				return Vector3.ZERO
			return go_to(delta, hero.global_position, speed)
	# circling: anyone who ends up right on top of you claws anyway
	if dist <= def["range"] + hero.radius * 0.5 and cooldown <= 0.0:
		f_state = "in"
		f_n = 0
		return Vector3.ZERO
	if lunge_cd <= 0.0 and dist > 3.2 and dist < 7.5 and not _pack_lunging() and game.world.los(global_position, hero.global_position):
		lunge_cd = 5.0
		_face(to)
		rig.rotation.y = atan2(-to.x, -to.z)
		lunge_from = global_position
		lunge_to = hero.global_position - to.normalized() * (radius + hero.radius + 0.3)
		_begin_special("feral_lunge")
		return Vector3.ZERO
	var from_hero := (-to).normalized().rotated(Vector3.UP, slot_a)
	return go_to(delta, hero.global_position + from_hero * 4.5, speed)

func _pack_lunging() -> bool:
	for e in game.enemies_near(global_position, 16.0):
		if e != self and e.pack_id == pack_id and e.special == "feral_lunge" and e.atk_t >= 0.0:
			return true
	return false

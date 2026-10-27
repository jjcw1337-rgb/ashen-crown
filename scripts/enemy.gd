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
## The Hollow Matron's heart mechanic (matron.gd); on a Mourner, the Matron it belongs to.
var heart: Matron = null
var heart_owner: Matron = null
## Mourners walk to where the Matron puts them.
var goto := Vector3.ZERO
var goto_speed := 1.2
## Damage taken multiplier (hollow / exposed Matron), set on every peer from fx events.
var taken := 1.0
var _exposed := false
## A Mourner carrying the heart: "on" beats faintly, "hush" is silent (shuffling).
var beat := ""
var beat_t := 0.0
var heart_light: OmniLight3D
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
	if def.has("skin"):
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
	rig.rotation.y = randf() * TAU
	home = global_position
	if def.get("heart", false):
		heart = Matron.new(self)

func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	for c in n.get_children():
		_collect_meshes(c)

func _set_flash(v: float) -> void:
	flash_mat.albedo_color = Color(1, 0.95, 0.9, v * 0.6)
	if champion:
		return
	var rest: Material = soul_mat() if _soul_lit else (drain_mat() if _drained else (exposed_mat() if _exposed else null))
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

## The Hollow Matron with her heart back in her chest: a red glow while she's exposed.
static var _exposed_mat: Material

static func exposed_mat() -> Material:
	if _exposed_mat == null:
		_exposed_mat = Mats.glow(Color(1.0, 0.12, 0.08), 0.9, 0.0, 1.0)
	return _exposed_mat

## A Mourner's hidden heart: a red pulse under the veil and a heartbeat that carries.
func _beat(delta: float) -> void:
	if heart_light == null:
		heart_light = OmniLight3D.new()
		heart_light.light_color = Color(1.0, 0.1, 0.08)
		heart_light.light_energy = 0.0
		heart_light.omni_range = 3.2
		heart_light.position = Vector3(0, height * 1.15, 0)
		add_child(heart_light)
	if beat != "on":
		return
	beat_t -= delta
	if beat_t <= 0.0:
		beat_t = 2.2
		_pulse(1.6)

func _pulse(strength: float) -> void:
	if heart_light == null:
		_beat(0.0)
	var tw := heart_light.create_tween()
	tw.tween_property(heart_light, "light_energy", strength, 0.06)
	tw.tween_property(heart_light, "light_energy", strength * 0.15, 0.14)
	tw.tween_property(heart_light, "light_energy", strength * 0.75, 0.06)
	tw.tween_property(heart_light, "light_energy", 0.0, 0.3)
	var d: float = game.hero.global_position.distance_to(global_position)
	Sfx.play("heartbeat", clampf(-2.0 - d * 0.9, -30.0, 0.0) + (strength - 1.6) * 2.0)

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
	var p := phys * 100.0 / (100.0 + armor * 0.6) * taken
	fire *= taken
	var total := p + fire
	if heart != null:
		if taken < 1.0:
			heart.hollow_hit()
		if not remote:
			var capped := heart.cap(total)
			if capped < total:
				p *= capped / maxf(total, 0.001)
				fire *= capped / maxf(total, 0.001)
				total = capped
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
		return total
	life -= total
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
	if fire > 0.0:
		Fx.burst(game.world.fx_root, global_position + Vector3(0, height, 0), Color(1.0, 0.5, 0.1), 8, 2.0, 0.15, 0.5, true, 2.0)
	if life <= 0.0:
		_die()
	elif not boss and atk_t >= 0.0 and atk_t / atk_dur < Anim.impact_at(atk_style) * 0.6 and total > max_life * 0.25:
		atk_t = -1.0
	return total

func _die() -> void:
	if heart_owner != null:
		heart_owner.on_mourner_died(self)
	if heart != null:
		heart.clear()
	die_visual()
	game.net.enemy_died(self)
	game.on_enemy_killed(self)

func die_visual() -> void:
	dead = true
	dead_t = 0.0
	atk_t = -1.0
	life = 0.0
	_drained = false
	_set_flash(0.0)
	Sfx.play("boss_die" if boss else "die", 0.0, randf_range(0.85, 1.15))
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
		Sfx.play("growl" if boss else "swing", -8.0, randf_range(0.6, 0.8) if height > 1.4 else randf_range(0.9, 1.2))
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
	global_position = p
	rig.rotation.y = lerp_angle(rig.rotation.y, net_yaw, k)
	phase += _net_phase_rate * delta
	Anim.pose(rig, {"time": anim_time, "phase": phase, "move": move_amt, "atk": net_atk,
		"style": atk_style, "hit": net_hit, "zombie": kind in ["zombie", "mummy"]})

## Visual and sound side of the special attacks, run on every player's game.
func special_fx(ev: String) -> void:
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
		# the Hollow Matron (matron.gd)
		"rip":
			Fx.burst(game.world.fx_root, global_position + Vector3(0, height * 1.45, 0), Color(0.5, 0.02, 0.04), 30, 3.0, 0.14, 0.9, true, -2.0)
			Sfx.play("roar", -4.0, 0.7)
			game.add_shake(0.3)
		"hollow":
			taken = Matron.HOLLOW_TAKEN
			_exposed = false
			_set_flash(0.0)
		"exposed":
			taken = Matron.EXPOSED_TAKEN
			_exposed = true
			_set_flash(0.0)
			Fx.ring(game.world.fx_root, global_position, 3.0, Color(1.0, 0.15, 0.1), 0.6)
		"heart_flare":
			beat = "hush"
			_beat(0.0)
			_pulse(5.0)
			Fx.burst(game.world.fx_root, global_position + Vector3(0, height * 1.2, 0), Color(1.0, 0.1, 0.08), 24, 2.5, 0.12, 0.6, true, 0.0)
		"heart_on":
			beat = "on"
			beat_t = 1.0
		"wail":
			Fx.ring(game.world.fx_root, global_position, 3.5, Color(0.7, 0.75, 1.0), 0.5)
			Fx.burst(game.world.fx_root, global_position + Vector3(0, 1.0, 0), Color(0.75, 0.8, 1.0, 0.8), 36, 6.0, 0.16, 0.7, true, 0.0)
			Sfx.play("cry", -2.0, 1.6)
			game.add_shake(0.35)

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
		else:
			rig.rotation.x = f * f * 1.45
		Anim.pose(rig, {"time": anim_time, "hit": 1.0 - f})
		if dead_t > 8.0:
			rig.position.y -= delta * 0.4
		if dead_t > 11.0:
			queue_free()
		return
	if beat != "":
		_beat(delta)
	if remote:
		_remote_process(delta)
		return
	var hero: Node3D = game.target_for(self)
	var to := hero.global_position - global_position
	to.y = 0
	var dist := to.length()
	if dist > 50.0 and not boss:
		return
	hit_t = maxf(0.0, hit_t - delta * 4.0)
	if knock.length() > 0.01:
		global_position = game.world.move(global_position, knock * delta * 6.0)
		knock = knock.lerp(Vector3.ZERO, clampf(delta * 8.0, 0.0, 1.0))
	cooldown = maxf(0.0, cooldown - delta)
	if heart != null and aggro:
		heart.update(delta)
	var vel := Vector3.ZERO
	# a Demon phased into the Underworld cannot be seen
	var hero_dead: bool = hero.dead or hero.get("phased") == true
	if stun_t > 0.0:
		stun_t -= delta
	elif atk_t >= 0.0:
		_update_attack(delta, hero, dist)
	else:
		if not aggro and dist < def.get("aggro", 12.0) and not hero_dead and game.world.los(global_position, hero.global_position):
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
		global_position = game.world.move(global_position, vel * delta)
		if aggro or vel.length() > 0.5:
			if atk_t < 0.0:
				_face(vel if not aggro or dist > 3.0 else to)
		move_amt = move_toward(move_amt, clampf(vel.length() / maxf(speed, 0.1), 0.0, 1.0), delta * 5.0)
		phase += delta * vel.length() * (1.6 / maxf(height, 0.5))
	else:
		move_amt = move_toward(move_amt, 0.0, delta * 5.0)
	global_position.y = game.world.height_at(global_position.x, global_position.z)
	Anim.pose(rig, {"time": anim_time, "phase": phase, "move": move_amt, "atk": (atk_t / atk_dur) if atk_t >= 0.0 else -1.0,
		"style": atk_style, "hit": hit_t, "zombie": kind in ["zombie", "mummy"]})

func _face(d: Vector3) -> void:
	d.y = 0
	if d.length() > 0.01:
		var want := atan2(-d.x, -d.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, want, 0.25)

func _think_combat(delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	var ai: String = def["ai"]
	if ai == "mourner":
		var gd := goto - global_position
		gd.y = 0
		return Vector3.ZERO if gd.length() < 0.15 else gd.normalized() * minf(goto_speed, gd.length() * 6.0)
	var rng_atk: float = def["range"]
	if boss:
		if not enraged and life < max_life * 0.35:
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

func _chase(delta: float, hero: Node3D, dist: float) -> Vector3:
	var hp: Vector3 = hero.global_position
	if game.world.los(global_position, hp):
		path = PackedVector3Array()
		var d := hp - global_position
		d.y = 0
		return d.normalized() * speed
	repath -= delta
	if repath <= 0.0 or path.is_empty():
		repath = 0.6 + randf() * 0.4
		path = game.world.find_path(global_position, hp)
	if path.is_empty():
		return Vector3.ZERO
	var nxt := path[0]
	var dv := Vector3(nxt.x - global_position.x, 0, nxt.z - global_position.z)
	if dv.length() < 0.4:
		path.remove_at(0)
	return dv.normalized() * speed

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
	Sfx.play("growl" if boss else "swing", -8.0, randf_range(0.6, 0.8) if height > 1.4 else randf_range(0.9, 1.2))

func _begin_special(sp: String) -> void:
	match sp:
		"slam":
			atk_style = "slam"
			_begin_attack("slam")
			_fx("slam_tele")
		"summon", "nova", "volley", "rip":
			atk_style = "cast"
			_begin_attack(sp)
			if sp == "nova":
				_fx("nova_tele")
			elif sp == "rip":
				_fx("rip")

func _update_attack(delta: float, hero: Node3D, dist: float) -> void:
	atk_t += delta
	var a := atk_t / atk_dur
	if a < Anim.impact_at(atk_style) * 0.8 and special in ["", "volley"]:
		_face(hero.global_position - global_position)
	if not impact_done and a >= Anim.impact_at(atk_style):
		impact_done = true
		_impact(hero, dist)
	if atk_t >= atk_dur:
		atk_t = -1.0
		cooldown = randf_range(0.3, 0.8) * (0.5 if boss else 1.0)
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
		"rip":
			if heart != null:
				heart.launch()
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

func _shoot(at: Vector3, pkind: String) -> void:
	var pr := Projectile.new()
	game.world.fx_root.add_child(pr)
	var from := global_position + Vector3(0, height * 1.35, 0) + (-rig.global_transform.basis.z) * 0.5
	pr.launch(game, pkind, from, at + Vector3(0, 1.1, 0), _roll())
	game.net.projectile(pkind, from, at + Vector3(0, 1.1, 0))
	Sfx.play("bow" if pkind in ["arrow", "dart"] else "fireball", -4.0, randf_range(0.9, 1.1))

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
var scripted := 0.0             # seconds something else drives this monster (the champion's charge, games.gd)
var leap_t := -1.0              # springing from an ambush (leap_from): 0..1 through the leap
var leap_a := Vector3.ZERO
var leap_b := Vector3.ZERO
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
## The Hollow Sloth's brain (sloth.gd), when this is one
var sloth: Sloth = null
var _sloth_phase := 0.0
## Factions (Data.ENEMIES "faction"): goblins and the undead fight each other on sight (and both fight you).
var rival: Enemy = null
# burning (the archer's Fire Arrow, his wolf's Ember Fangs): fire damage every half second; chilled (Frost
# Volley, Winter Howl): slower on its feet. Burning is ticked by whoever set it (take_damage routes to the host);
# a chill from a partner reaches the host through Net.send_enemy_chill.
var burn_t := 0.0
var burn_dps := 0.0
var burn_tick := 0.0
var chill_t := 0.0
var chill_k := 0.0
var taunt: Node3D = null      # a companion that bit it (the archer's Spirit Beast): it turns on it for a while
var taunt_t := 0.0
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
# the three Fallen (fallen_skirmisher / fallen_reaver / fallen_stalker): an attack that moves the body along a
# path (atk_path: [from fraction, to fraction, from, to]), the Reaver's warning shown once, his slow start,
# the Stalker's chosen side and weave
var atk_path: Array = []
var atk_aim := Vector3.ZERO
var tele_done := false
var rv_spd := 0.0
var fv_side := 1.0
var fv_flip := 1.5
var fv_weave := 0.0
# the Forsaken Bear (bear.gd): roars once on noticing you, roars now and then while it wanders
var b_roared := false
var b_idle_t := 0.0

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
	rig = build_rig(k, Feral.variant_at(global_position))
	if rig.has_meta("feral"):
		slot_a = randf_range(-1.6, 1.6)
		lunge_cd = randf_range(0.3, 3.0)
	elif rig.has_meta("sloth"):
		Sloth.dress(rig, str(def.get("element", "")))
		sloth = Sloth.new(self)
		atk_style = "sloth_walk"
		add_to_group("sloth")
	elif rig.has_meta("lion"):
		slot_a = randf_range(-1.6, 1.6)
		lunge_cd = randf_range(0.5, 2.5)
	add_child(rig)
	var pers := "warrior"
	match k:
		"zombie", "mummy": pers = "zombie"
		"skel_archer": pers = "skeleton"
		"fallen", "fallen_skirmisher", "fallen_stalker", "imp", "fetish": pers = "fallen"
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

func ignite(dps: float, t: float) -> void:
	if dead:
		return
	burn_dps = maxf(burn_dps if burn_t > 0.0 else 0.0, dps)
	burn_t = maxf(burn_t, t)
	if game and game.world:
		DemonFx.ignite(game.world.fx_root, self)

func chill(k: float, t: float) -> void:
	if remote:
		game.net.send_enemy_chill(self, k, t)
	if boss:
		k *= 0.5
	chill_k = maxf(chill_k if chill_t > 0.0 else 0.0, k)
	chill_t = maxf(chill_t, t)
	if game and game.world and not has_node("frost"):
		var f := Fx.aura(self, Color(0.6, 0.85, 1.0), 14, 0.3, 0.07, 0.8, -0.2, 0.4 * radius + 0.2, 60.0, Vector3(0, height * 0.8, 0))
		f.name = "frost"

## Burning and chill wearing off (every peer: a burn ticks where it was set, a chill slows the host's AI).
func _statuses(delta: float) -> void:
	if burn_t > 0.0:
		burn_t -= delta
		burn_tick -= delta
		if burn_tick <= 0.0:
			burn_tick = 0.5
			take_damage(0.0, burn_dps * 0.5, global_position, 0.0, false)
			if game and game.world and randf() < 0.5:
				DemonFx.ignite(game.world.fx_root, self)
	if chill_t > 0.0:
		chill_t -= delta
		if chill_t <= 0.0:
			chill_k = 0.0
			var f := get_node_or_null("frost")
			if f:
				f.queue_free()

func stun(t: float) -> void:
	if remote:
		game.net.send_enemy_stun(self, t)
		return
	if boss or sloth != null:
		t *= 0.3
	stun_t = maxf(stun_t, t)
	atk_t = -1.0

func take_damage(phys: float, fire: float, from: Vector3, knockback: float, crit: bool) -> float:
	if dead:
		return 0.0
	aggro = true
	if sloth != null:
		sloth.on_hit(from)
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
		knock += away.normalized() * knockback * (0.25 if boss else (0.12 if sloth != null else 1.0))
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
	if atk >= 0.0 and net_atk < 0.0 and sloth == null:
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
	if ev.begins_with("sloth"):
		Sloth.fx(self, ev)
		return
	var col := Color(0.4, 1.0, 0.3) if def.get("nova", "") == "poison" else Color(1.0, 0.4, 0.1)
	match ev:
		"slam_tele":
			Fx.telegraph(game.world.fx_root, global_position, 4.2, atk_dur * Anim.impact_at("slam"))
		"reaver_tele":
			Fx.arc_telegraph(game.world.fx_root, global_position, -rig.global_transform.basis.z, 2.6 + radius * 0.5, 60.0, atk_dur * (Anim.impact_at("reaver_cleave") - 0.15))
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
		"bear_tele":
			# the danger zone: a ring where the paws will land
			Fx.telegraph(game.world.fx_root, global_position - rig.global_transform.basis.z * 1.6, 1.9, atk_dur * Bear.MAUL_HIT, Color(0.6, 1.0, 0.4))
		"bear_roar":
			Bear.sound("bear_roar", global_position + Vector3(0, 2.0, 0))
			Fx.burst(game.world.fx_root, global_position + Vector3(0, 2.4, 0) - rig.global_transform.basis.z * 0.9, Color(0.75, 0.8, 0.75, 0.35), 18, 1.6, 0.35, 0.9, false, 0.4, 35.0, -rig.global_transform.basis.z)
			if game.hero.global_position.distance_to(global_position) < 16.0:
				game.add_shake(0.25)
		"bear_maul":
			Bear.sound("bear_maul", global_position)
			var paws := global_position - rig.global_transform.basis.z * 1.6
			Fx.ring(game.world.fx_root, paws, 2.6, Color(0.45, 0.4, 0.33), 0.4)
			Fx.burst(game.world.fx_root, paws + Vector3(0, 0.2, 0), Color(0.38, 0.33, 0.28, 0.8), 30, 4.5, 0.3, 0.8, false, -4.0, 80.0)
			if game.hero.global_position.distance_to(global_position) < 10.0:
				game.add_shake(0.45)
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
		elif rig.has_meta("feral") or rig.has_meta("lion") or rig.has_meta("bear") or rig.has_meta("sloth"):
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
	if sloth != null:
		Sloth.presence(self, delta, _sloth_phase)
		Sloth.idle_fx(self, delta)
		_sloth_phase = phase
	_statuses(delta)
	if dead:
		return
	if remote:
		_remote_process(delta)
		return
	var hero: Node3D = game.target_for(self)
	# bitten by a companion: it goes for the beast while that is the nearer threat
	if taunt != null:
		taunt_t -= delta
		if not is_instance_valid(taunt) or taunt.dead or taunt_t <= 0.0:
			taunt = null
		elif hero == null or hero.dead or taunt.global_position.distance_to(global_position) < hero.global_position.distance_to(global_position) * 0.9:
			hero = taunt
			aggro = true
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
	if leap_t >= 0.0:
		_update_leap(delta, hero)
		return
	if scripted > 0.0:
		scripted -= delta
		return
	var to := hero.global_position - global_position
	to.y = 0
	var dist := to.length()
	if perch_h > 0.0:
		_feral_perch(delta, hero, dist)
		return
	if dist > 50.0 and not boss and sloth == null:
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
	if sloth != null:
		vel = sloth.update(delta, hero, to, dist, hero_dead)
	elif stun_t > 0.0:
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
		elif def["ai"] == "bear":
			vel = _bear_idle(delta)
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
		global_position = game.world.move(global_position, vel * delta * (1.0 - chill_k), body_r())
		if aggro or vel.length() > 0.5:
			if atk_t < 0.0:
				_face(to if aggro and sloth == null and (dist <= 3.0 or f_state in ["back", "out"]) else vel)
		move_amt = move_toward(move_amt, clampf(vel.length() / maxf(speed, 0.1), 0.0, 1.0), delta * 5.0)
		var was := phase
		phase += delta * vel.length() * (1.6 / maxf(height, 0.5)) * (-1.0 if f_state in ["back", "out"] else 1.0) * (float(rig.get_meta("stride")) if rig.has_meta("stride") else 1.0)
		if boss and rig.has_meta("goblin") and floorf(phase / PI) != floorf(was / PI) and move_amt > 0.4:
			_footstep()
	else:
		move_amt = move_toward(move_amt, 0.0, delta * 5.0)
	global_position.y = game.world.height_at(global_position.x, global_position.z)
	_pose({"time": anim_time, "phase": phase, "move": move_amt, "atk": (atk_t / atk_dur) if atk_t >= 0.0 else -1.0,
		"style": atk_style, "hit": hit_t, "zombie": kind in ["zombie", "mummy"], "aggro": aggro})

func _pose(st: Dictionary) -> void:
	pose_rig(rig, st, height)

## A monster kind's body (its Meshy model, sculpted goblin, skeleton or code-built figure), as setup gives
## it; also used to draw the arena's crowd (games.gd). variant: the Feral's model.
static func build_rig(kind: String, variant := 1) -> Node3D:
	var d: Dictionary = Data.ENEMIES[kind]
	var look: Dictionary = d["look"]
	var h: float = look.get("height", look.get("size", 1.0))
	if d.get("mesh", "") == "feral" and Feral.ok():
		return Feral.build(variant)
	if d.get("mesh", "") == "lion" and Lion.ok():
		return Lion.build()
	if d.get("mesh", "") == "bear" and Bear.ok():
		return Bear.build()
	if d.get("mesh", "") == "sloth":
		return Sloth.build(str(d.get("variant", "")), look.get("skin", Color(0.52, 0.56, 0.47)))
	if d.get("mesh", "") == "wolf" and ResourceLoader.exists(SpiritBeast.WOLF_GLB):
		return Lion.build(SpiritBeast.WOLF_GLB, 1.0)
	if d.has("mesh") and MeshyMonster.ok(d["mesh"]):
		return MeshyMonster.build(d["mesh"], look)
	if d.has("model"):
		return Goblin.build(d["model"])
	if d.has("skin"):
		var r := SkeletonModel.build(d["skin"])
		if absf(h - 1.0) > 0.01:
			r.scale = Vector3.ONE * h
		return r
	return Models.crawler(look) if d["rig"] == "crawler" else Models.humanoid(look)

## Poses any monster body from the enemy state (see `_pose`).
static func pose_rig(r: Node3D, st: Dictionary, height: float) -> void:
	if r.has_meta("feral"):
		Feral.pose(r, st, height)
	elif r.has_meta("lion"):
		Lion.pose(r, st, height)
	elif r.has_meta("bear"):
		Bear.pose(r, st, height)
	elif r.has_meta("sloth"):
		Sloth.pose(r, st, height)
	else:
		Anim.pose(r, st)

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
	return clampf(radius * 0.75, World.BODY_R, 1.1) if boss or sloth != null else World.BODY_R

## How tall it stands, in metres (mouse picking).
func top() -> float:
	return height * 1.8 * (1.15 if champion else 1.0)

func _face(d: Vector3) -> void:
	d.y = 0
	if d.length() > 0.01:
		var want := atan2(-d.x, -d.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, want, float(def.get("turn", 0.25)))

func _think_combat(delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	var ai: String = def["ai"]
	if hoard != null:
		var v: Variant = hoard.steer(self, delta)
		if v != null:
			return v
	if ai == "feral":
		return _feral_combat(delta, hero, to, dist)
	if ai == "skirmisher":
		return _skirm_combat(delta, hero, to, dist)
	if ai == "reaver":
		return _reaver_combat(delta, hero, to, dist)
	if ai == "stalker":
		return _stalk_combat(delta, hero, to, dist)
	if ai == "bear":
		return _bear_combat(delta, hero, to, dist)
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
			if kind == "lion":
				Sfx.play_at("lion_roar", global_position, -3.0, randf_range(0.92, 1.08))
		# the Fallen: each signature attack moves the body along its own path (no snapping into range)
		"skirm_lunge", "reaver_cleave", "stalk_hook":
			atk_style = sp
			atk_dur = def["atk_time"]
			tele_done = false
			_begin_attack(sp)
			_fallen_path(sp)
		# the Forsaken Bear: rear up and roar; rear and slam both forepaws down
		"bear_roar":
			atk_style = sp
			atk_dur = Bear.ROAR_T
			_begin_attack(sp)
		"bear_maul":
			atk_style = sp
			atk_dur = Bear.MAUL_T
			_begin_attack(sp)
			_fx("bear_tele")
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
	if not atk_path.is_empty():
		for sg in atk_path:
			if a >= float(sg[0]) and a <= float(sg[1]) + 0.08:
				var p: Vector3 = (sg[2] as Vector3).lerp(sg[3], smoothstep(float(sg[0]), float(sg[1]), a))
				var step := p - global_position
				step.y = 0
				global_position = game.world.move(global_position, step, body_r())
				break
	match special:
		"skirm_lunge":
			if a < 0.3:
				_face(hero.global_position - global_position)
		"reaver_cleave":
			if a < 0.15:
				_face(hero.global_position - global_position)
			elif not tele_done:
				tele_done = true
				_fx("reaver_tele")
		"stalk_hook":
			if a > 0.22 and a < 0.45:
				_face(hero.global_position - global_position)
	if a < Anim.impact_at(atk_style) * 0.8 and special in ["", "volley", "bomb"]:
	if a < Anim.impact_at(atk_style) * 0.8 and special in ["", "volley", "bomb", "bear_maul"]:
		_face(hero.global_position - global_position)
	if not impact_done and a >= Anim.impact_at(atk_style):
		impact_done = true
		_impact(hero, dist)
	if atk_t >= atk_dur:
		atk_t = -1.0
		cooldown = randf_range(0.3, 0.8) * (0.5 if boss else 1.0)
		atk_path = []
		match special:
			"skirm_lunge":
				# committed: a real opening after the leap
				cooldown = randf_range(1.3, 1.7)
				f_state = "recover"
				f_t = randf_range(0.45, 0.65)
			"reaver_cleave":
				cooldown = randf_range(1.1, 1.5)
				f_state = "rest"
				f_t = 1.0
				rv_spd = speed * 0.3
			"stalk_hook":
				cooldown = randf_range(1.6, 2.2)
				f_t = 1.0
				fv_side = -fv_side if randf() < 0.5 else fv_side
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
		"skirm_lunge", "stalk_hook":
			# one blow, on the target, only if it is still there and in front
			if is_instance_valid(hero) and not hero.dead:
				var th: Vector3 = hero.global_position - global_position
				th.y = 0
				var reach: float = radius + hero.radius + (1.0 if special == "skirm_lunge" else 1.1)
				if th.length() <= reach and fwd.dot(th.normalized()) > (0.3 if special == "skirm_lunge" else 0.2):
					hero.take_hit(_roll(), global_position, "melee")
			return
		"reaver_cleave":
			# everyone in the 120-degree arc out to 2.6 m is caught
			for h in game.all_heroes():
				if h.dead:
					continue
				var tc: Vector3 = h.global_position - global_position
				tc.y = 0
				if tc.length() < 2.6 + radius * 0.5 and (tc.length() < 0.3 or fwd.dot(tc.normalized()) > 0.5):
					h.take_hit(_roll(), global_position, "melee")
			game.add_shake(0.15)
			return
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
		"bear_roar":
			_fx("bear_roar")
		"bear_maul":
			# both forepaws come down in front: everyone in a 3 m arc ahead is hit and knocked back
			_fx("bear_maul")
			for h in game.all_heroes():
				if h.dead:
					continue
				var to_h: Vector3 = h.global_position - global_position
				to_h.y = 0
				if to_h.length() < 3.0 + radius * 0.5 and fwd.dot(to_h.normalized()) > 0.2:
					h.take_hit(_roll(), global_position, "maul")
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
## An ambusher (Via's bandits): leaps from where it hid, over the rocks, down onto the road, and is in
## the fight as it lands.
func leap_from(a: Vector3, b: Vector3) -> void:
	leap_a = a
	leap_b = Vector3(b.x, game.world.height_at(b.x, b.z), b.z)
	leap_t = randf_range(-0.35, 0.0)     # not all at once
	aggro = true

func _update_leap(delta: float, hero: Node3D) -> void:
	leap_t += delta / 0.75
	var k := clampf(leap_t, 0.0, 1.0)
	var p := leap_a.lerp(leap_b, smoothstep(0.0, 1.0, k))
	p.y = lerpf(game.world.height_at(leap_a.x, leap_a.z), leap_b.y, k) + sin(k * PI) * 2.6
	global_position = p
	var d := leap_b - leap_a
	if d.length() > 0.1:
		rig.rotation.y = atan2(-d.x, -d.z)
	_pose({"time": anim_time, "phase": phase, "move": 1.0 - k, "atk": 0.25 + k * 0.5, "style": "over", "hit": 0.0})
	if leap_t >= 1.0:
		leap_t = -1.0
		home = global_position
		Fx.burst(game.world.fx_root, global_position + Vector3(0, 0.2, 0), Color(0.45, 0.38, 0.28, 0.7), 14, 2.5, 0.25, 0.6, false, 0.5)
		if is_instance_valid(hero) and hero is Node3D:
			rig.rotation.y = atan2(-(hero.global_position.x - global_position.x), -(hero.global_position.z - global_position.z))

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

# ---------------------------------------------------------------- the three Fallen
## Each signature attack's path, from where it starts toward its target: the Skirmisher launches at you and
## stumbles on through; the Reaver plants his feet (no path); the Stalker shifts sideways, darts in at an
## angle and pulls back out.
func _fallen_path(sp: String) -> void:
	atk_path = []
	var hero: Node3D = game.target_for(self)
	if hero == null:
		return
	var hp: Vector3 = hero.global_position
	var p0 := global_position
	var to := hp - p0
	to.y = 0
	var dir := to.normalized() if to.length() > 0.05 else -rig.global_transform.basis.z
	var reach: float = radius + hero.radius
	match sp:
		"skirm_lunge":
			var land := p0 + dir * clampf(to.length() - reach - 0.15, 0.0, 4.5)
			atk_path = [[0.3, 0.5, p0, land], [0.5, 0.62, land, land + dir * 0.45]]
		"stalk_hook":
			var side := Vector3(-dir.z, 0, dir.x) * fv_side
			var p1 := p0 + side * 1.5
			var from_h := (p1 - hp)
			from_h.y = 0
			var app := from_h.normalized().rotated(Vector3.UP, fv_side * 0.7) if from_h.length() > 0.05 else -dir
			var p2 := hp + app * (reach + 0.3)
			var out := (p2 - hp)
			out.y = 0
			var p3 := p2 + (out.normalized() if out.length() > 0.05 else -dir) * 1.5
			atk_path = [[0.0, 0.25, p0, p1], [0.25, 0.44, p1, p2], [0.55, 1.0, p2, p3]]

## The Skirmisher: comes straight in, fast; from about 5 m it coils and launches the Savage Lunge, then
## stands a moment (the opening); too close to lunge, it hops back a step first.
func _skirm_combat(delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	if f_state == "recover":
		f_t -= delta
		if f_t > 0.0:
			_face(to)
			return Vector3.ZERO
		f_state = ""
	var reach: float = radius + hero.radius
	if cooldown <= 0.0 and dist < 5.2 and dist > reach + 0.5 and game.world.los(global_position, hero.global_position):
		_face(to)
		_begin_special("skirm_lunge")
		return Vector3.ZERO
	if dist < reach + 0.5:
		return -to.normalized() * speed * 0.7
	return go_to(delta, hero.global_position, speed * 1.1)

## The Reaver: walks in steadily, slow to get going and slow to turn; in reach he plants and cleaves, then
## stands for a second with the axe low.
func _reaver_combat(delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	if f_state == "rest":
		f_t -= delta
		if f_t > 0.0:
			return Vector3.ZERO
		f_state = ""
	if dist <= 2.4 + hero.radius * 0.5 and cooldown <= 0.0:
		_begin_special("reaver_cleave")
		return Vector3.ZERO
	if dist < radius + hero.radius + 0.2:
		return Vector3.ZERO
	rv_spd = move_toward(rv_spd, speed, delta * 1.8)
	return go_to(delta, hero.global_position, rv_spd)

## The Stalker: circles 4-6 m out on a side it picks (switching now and then), weaving as it goes, edging in
## on an arc; when ready it shifts, darts in at an angle and hooks, then pulls out and circles again.
func _stalk_combat(delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	fv_flip -= delta
	if fv_flip <= 0.0:
		fv_flip = randf_range(1.0, 2.0)
		if randf() < 0.45:
			fv_side = -fv_side
	f_t -= delta
	var reach: float = radius + hero.radius
	if cooldown <= 0.0 and f_t <= 0.0 and dist < 6.0 and dist > reach + 0.3 and game.world.los(global_position, hero.global_position):
		_begin_special("stalk_hook")
		return Vector3.ZERO
	var ring := 5.0 if (cooldown > 0.0 or f_t > 0.0) else 3.8
	var from_h := global_position - hero.global_position
	from_h.y = 0
	var base := atan2(from_h.z, from_h.x)
	var want := base + fv_side * 0.55
	var tgt: Vector3 = hero.global_position + Vector3(cos(want), 0, sin(want)) * ring
	var v := go_to(delta, tgt, speed)
	# the weave: a smooth sideways sway over the arc (its side flips with fv_side, so it reads as intent)
	fv_weave += delta * 2.6
	var side := Vector3(-to.z, 0, to.x).normalized() if to.length() > 0.05 else Vector3.ZERO
	return v + side * sin(fv_weave) * speed * 0.3 * fv_side
# ---------------------------------------------------------------- the Forsaken Bear (bear.gd)
## Ambling about its home ground (wider than most monsters'), stopping every so often to rear up and roar.
func _bear_idle(delta: float) -> Vector3:
	b_idle_t -= delta
	if b_idle_t <= 0.0:
		b_idle_t = randf_range(14.0, 26.0)
		if move_amt < 0.3 and global_position.distance_to(home) < 12.0:
			_begin_special("bear_roar")
			return Vector3.ZERO
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = randf_range(3.0, 7.0)
		wander_to = game.world.free_spot_near(home, 9.0) if randf() < 0.7 else global_position
	var d := wander_to - global_position
	d.y = 0
	if d.length() < 0.4:
		return Vector3.ZERO
	return d.normalized() * speed * (0.45 if d.length() > 12.0 else 0.32)

## On noticing a hero it rears and roars once, then charges and mauls, and keeps at it until one of them dies;
## it gives up only when led more than 30 m from home.
func _bear_combat(delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	if not b_roared:
		b_roared = true
		_face(to)
		rig.rotation.y = atan2(-to.x, -to.z)
		_begin_special("bear_roar")
		return Vector3.ZERO
	if global_position.distance_to(home) > 30.0:
		aggro = false
		b_roared = false
		f_calm = 6.0
		wander_to = home
		wander_t = 8.0
		return Vector3.ZERO
	if dist <= def["range"] + hero.radius * 0.5:
		if cooldown <= 0.0:
			_face(to)
			_begin_special("bear_maul")
		return Vector3.ZERO
	return go_to(delta, hero.global_position, speed * 1.5)

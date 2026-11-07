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
var scripted := 0.0             # seconds something else drives this monster (a tool holding it still for the camera)
var atk_t := -1.0
var atk_dur := 1.0
var atk_style := "over"
var impact_done := false
var cooldown := 0.0
var hit_t := 0.0
var stun_t := 0.0
var slow_t := 0.0               # slowed (Soul Siphon): seconds left and how much of its pace is lost
var slow_amt := 0.0
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
var flash_mat: ShaderMaterial
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
## It shambles (the zombie personality's gait flag in Anim's pose state).
var shamble := false
## A boss's brain (BossBrain, from Monsters.brain_for): Hrimgar, Mossbeard and his poison mushrooms
var brain: BossBrain = null
var _sloth_phase := 0.0
## Factions (Data.ENEMIES "faction"): goblins and the undead fight each other on sight (and both fight you).
## Not inside a camp (pack_id from Camps.FIRST_PACK): a camp's monsters are one encounter, whatever their factions.
var rival: Enemy = null
# burning (the archer's Fire Arrow, his wolf's Ember Fangs): fire damage every half second; chilled (Frost
# Volley, Winter Howl): slower on its feet. Burning is ticked by whoever set it (take_damage routes to the host);
# a chill from a partner reaches the host through Net.send_enemy_chill.
var burn_t := 0.0
var burn_look := ""            # who draws the burn (Enemy.ignite)
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
## Battlegrounds PvP: this is no monster but the invisible stand-in for player `pvp_pid` on this client
## (Battlegrounds.sync_proxies keeps it on their puppet); a blow on it goes to that player through the server.
var pvp_pid := 0
var pvp_hidden := false    # that player is hidden in a Plague Doctor's fog: not picked by the pointer or aim help
## ... or the stand-in for something another player made that can be broken (`PvpObjects`: a Corpse Bloom, a vat, a
## creature): its id in its owner's game and the owner's peer id. Blows on it count on the owner's game.
var pvp_obj := 0
var pvp_owner := 0
## The admins' sandbox (Sandbox): the invisible stand-in for this hero (a bot, or the player); blows on it are dealt
## to them as a raid's PvP is (Battlegrounds.PVP_MULT), stuns and slows reach them, its own hero's never land.
var sandbox_hero: Hero = null
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
	max_life = def["life"] * lf * (2.4 if champ else 1.0)
	life = max_life
	dmg = [def["dmg"][0] * df * (1.4 if champ else 1.0), def["dmg"][1] * df * (1.4 if champ else 1.0)]
	armor = int(def.get("armor", 0) * (1.0 + 0.1 * lvl))
	speed = def["speed"] * (1.15 if champ else 1.0)
	xp = int(def["xp"] * (1.0 + 0.12 * (lvl - 1)) * (3.0 if champ else 1.0))
	radius = def.get("radius", 0.5)
	display_name = champ_name if champ_name != "" else def["name"]
	atk_style = def["atk"]
	atk_dur = def["atk_time"]
	var look: Dictionary = def["look"]
	height = look.get("height", look.get("size", 1.0))
	rig = Monsters.build_rig(k, Feral.variant_at(global_position))
	brain = Monsters.brain_for(self)
	Monsters.on_setup(self)      # (its family's own start: a Feral's place in the pack, a Sloth's dress and brain)
	add_child(rig)
	rig.set_meta("pers", "boss" if boss else Monsters.personality(k))
	shamble = Monsters.personality(k) == "zombie"
	if champ:
		rig.scale = Vector3.ONE * 1.15
	_collect_meshes(rig)
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER
	flash_mat = ShaderMaterial.new()
	flash_mat.shader = _flash_shader
	flash_mat.set_shader_parameter("col", Color(1, 1, 1, 0))
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
	Monsters.on_placed(self)     # (once it stands where it lives: King Grubb's fight begins)

func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	for c in n.get_children():
		_collect_meshes(c)

## The hit flash: light added over the body for FLASH_T, strongest at the silhouette's rim and under half as strong
## where the surface faces the camera, so the body keeps its shape and reads as struck (the old flat, unshaded white
## at 60% turned every foe into a paper cut-out for those frames); it fades as it goes.
const FLASH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_back;
uniform vec4 col : source_color = vec4(1.0, 0.95, 0.9, 0.0);
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = col.rgb;
	ALPHA = clamp(col.a * (0.38 + 1.1 * f * f), 0.0, 1.0);
}
"""
const FLASH_T := 0.12
const FLASH_WHITE := Color(1, 0.95, 0.9, 0.6)
static var _flash_shader: Shader
var _flash_col := FLASH_WHITE      # this hit's flash colour and peak strength (alpha)
var _flash_on := false

func _set_flash(v: float) -> void:
	if v >= 1.0:
		_flash_col = FLASH_WHITE
	flash_mat.set_shader_parameter("col", Color(_flash_col.r, _flash_col.g, _flash_col.b, v * _flash_col.a))
	if champion:
		return
	var on := v > 0.01
	if on == _flash_on and not (v <= 0.0):
		return
	_flash_on = on
	var rest: Material = soul_mat() if _soul_lit else (drain_mat() if _drained else (_frost_mat if _frosted else Monsters.rest_overlay(self)))
	for m in meshes:
		if is_instance_valid(m):
			(m as MeshInstance3D).material_overlay = flash_mat if on else rest

## This hit's flash in another colour (alpha = its strength), e.g. Molten Fists' molten flash.
func flash_color(c: Color) -> void:
	_flash_col = c
	flash_mat.set_shader_parameter("col", c)

## A softer, coloured hit flash (Drain Life ticks), so a held beam doesn't strobe the victim white.
func drain_flash(col: Color) -> void:
	flash_color(Color(col.r, col.g, col.b, 0.3))

## Held in a Warlock's Drain Life beam: a green rim-light for as long as the beam holds on.
static var _drain_mats := {}
var _drained := false
var _drain_col := Color(0.25, 1.0, 0.2)
## Damage numbers in this colour, and no blood (set around a Drain Life tick). Alpha 0 = normal.
var dmg_tint := Color(0, 0, 0, 0)
var seared := false            # a burning arrow's hit: the wound is seared, no blood (Archer.update)
## a damage tick (the plague doctor's poison): the number shows, but no white flash and no flinch
var soft_hit := false

## The rim of a drained victim: the Warlock's fel green, or the Wraith's cold cyan (Soul Siphon).
func drain_mat() -> Material:
	var key := _drain_col.to_html()
	if not _drain_mats.has(key):
		_drain_mats[key] = Mats.glow(_drain_col, 0.75, 0.0, 1.0)
	return _drain_mats[key]

func set_drained(on: bool, col := Color(0.25, 1.0, 0.2)) -> void:
	if on == _drained or champion:
		return
	_drained = on
	_drain_col = col
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

## Frost Volley's rime (FrostFx.frost_body): a rest overlay crawling up the body from the feet, v 0..1 of the
## way to the head (0 takes it off). Cosmetic, on every game.
var _frost_mat: ShaderMaterial
var _frosted := false

func set_frost(v: float) -> void:
	if champion or rig == null:
		return
	if _frost_mat == null:
		if v <= 0.0:
			return
		_frost_mat = ShaderMaterial.new()
		_frost_mat.shader = FrostFx.shader("body")
		_frost_mat.set_shader_parameter("noise_tex", InfernalFx.noise())
	_frost_mat.set_shader_parameter("amt", v)
	_frost_mat.set_shader_parameter("base_y", global_position.y)
	_frost_mat.set_shader_parameter("height", maxf(height, 0.8) * 1.8)
	var on := v > 0.001
	if on != _frosted:
		_frosted = on
		_set_flash(0.0)

## `look` names who draws the burn: "" = the Demon's ember flames (DemonFx.ignite, here and as it ticks);
## an arrow kind (FlameFx.burn, the archer's own body flames) draws its own and these are skipped.
func ignite(dps: float, t: float, look := "") -> void:
	if dead:
		return
	# a player's stand-in: the burn goes to them (the sandbox's hero, or a raid's player through the server)
	if sandbox_hero != null:
		var who: Hero = Hero.striker
		if who != sandbox_hero and not sandbox_hero.dead:
			var k := Data.pvp_scale(who.cls if who != null else "", sandbox_hero.cls, who.level if who != null else 20, sandbox_hero.level)
			sandbox_hero.take_hit(minf(dps, Battlegrounds.PVP_BURN_CAP) * Battlegrounds.PVP_MULT * k, global_position, "burn", "fire")
		return
	if pvp_pid > 0:
		game.net.send_pvp_dot(pvp_pid, dps, global_position)
		return
	# a run's talents and gems: the striker's burns hotter and longer (RunTalents: Kindling, the Ember Ruby)
	var who: Hero = Hero.striker
	if who != null and is_instance_valid(who) and who.run != null:
		RunTalents.mark(who, self)
		dps *= 1.0 + who.talent("burn_pct") / 100.0
		t *= 1.0 + who.talent("burn_dur") / 100.0
	burn_dps = maxf(burn_dps if burn_t > 0.0 else 0.0, dps)
	burn_t = maxf(burn_t, t)
	burn_look = look
	if game and game.world and look == "":
		DemonFx.ignite(game.world.fx_root, self)

func chill(k: float, t: float) -> void:
	if pvp_pid > 0:
		game.net.send_pvp_effect(pvp_pid, "chill", global_position)
		return
	if sandbox_hero != null:
		if Hero.striker != sandbox_hero and not sandbox_hero.dead:
			sandbox_hero.chill_t = maxf(sandbox_hero.chill_t, t * sandbox_hero.cc_k())
		return
	var who: Hero = Hero.striker
	if who != null and is_instance_valid(who) and who.run != null and who.talent("chill_pct") > 0.0:
		var more := who.talent("chill_pct") / 100.0
		t *= 1.0 + more
		k = minf(0.75, k * (1.0 + more * 0.5))
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
			# a burn drawn by its source (the Fire Arrow's flames) ticks as fire: amber numbers, no blood, no flash
			if burn_look != "":
				dmg_tint = Color(1.0, 0.6, 0.25)
				soft_hit = true          # no flash, no flinch on each tick
			take_damage(0.0, burn_dps * 0.5, global_position, 0.0, false)
			if burn_look != "":
				dmg_tint = Color(0, 0, 0, 0)
				soft_hit = false
			if game and game.world and randf() < 0.5 and burn_look == "":
				DemonFx.ignite(game.world.fx_root, self)
	if chill_t > 0.0:
		chill_t -= delta
		if chill_t <= 0.0:
			chill_k = 0.0
			var f := get_node_or_null("frost")
			if f:
				f.queue_free()

func stun(t: float) -> void:
	if sandbox_hero != null:
		if Hero.striker != sandbox_hero and not sandbox_hero.dead:
			if t < 0.0:
				sandbox_hero.chill_t = maxf(sandbox_hero.chill_t, -t * sandbox_hero.cc_k())
			else:
				sandbox_hero.daze_t = maxf(sandbox_hero.daze_t, minf(t, 1.5) * sandbox_hero.cc_k())
		return
	if t < 0.0:
		# a slow rides the stun RPC as a negative time (the Wraith's Soul Siphon), so the RPC set stays as it is
		slow(-t, 0.5)
		return
	if remote:
		game.net.send_enemy_stun(self, t)
		return
	if boss or sloth != null:
		t *= 0.3
	stun_t = maxf(stun_t, t)
	atk_t = -1.0

## Slowed to (1 - amt) of its pace for t seconds (host-side, like every movement).
func slow(t: float, amt: float) -> void:
	if sandbox_hero != null:
		if Hero.striker != sandbox_hero and not sandbox_hero.dead:
			sandbox_hero.chill_t = maxf(sandbox_hero.chill_t, t * sandbox_hero.cc_k())
		return
	if remote:
		game.net.send_enemy_stun(self, -t)
		return
	slow_t = maxf(slow_t, t)
	slow_amt = amt

func take_damage(phys: float, fire: float, from: Vector3, knockback: float, crit: bool) -> float:
	if dead:
		return 0.0
	if sandbox_hero != null:
		# the sandbox: a hero, hit as in a raid (never by its own blows)
		var who: Hero = Hero.striker
		if who == sandbox_hero or sandbox_hero.dead:
			return 0.0
		var dealt := (phys + fire) * Battlegrounds.PVP_MULT * Data.pvp_scale(who.cls if who != null else "", sandbox_hero.cls, who.level if who != null else 20, sandbox_hero.level)
		var l0 := sandbox_hero.life
		sandbox_hero.take_hit(dealt, from, "pvp", "phys")
		var landed := maxf(0.0, l0 - sandbox_hero.life)
		if game.sandbox != null:
			game.sandbox.note_hit(who, sandbox_hero, landed)
		Fx.number(game.world.fx_root, global_position + Vector3(0, 2.2, 0), str(int(landed)) + ("!" if crit else ""), Color(1.0, 0.4, 0.35), crit)
		return landed
	if pvp_pid > 0:
		# another player: the server scales it and deals it to them; the number shows here at once
		var total0 := phys + fire
		game.net.send_pvp_hit(pvp_pid, total0, from)
		Fx.number(game.world.fx_root, global_position + Vector3(0, 2.2, 0), str(int(total0 * Battlegrounds.PVP_MULT)) + ("!" if crit else ""), Color(1.0, 0.4, 0.35), crit)
		Fx.blood(game.world.fx_root, global_position + Vector3(0, 1.0, 0), Color(0.5, 0.0, 0.0))
		return total0 * Battlegrounds.PVP_MULT
	if pvp_obj > 0:
		# another player's thing: a blow, counted on its owner's game
		PvpObjects.struck(self, from)
		return 0.0
	aggro = true
	if sloth != null:
		sloth.on_hit(from)
	if game.test_onehit:
		phys = maxf(phys, life * 10.0 + 1000000.0)   # testing switch (F8): any hit kills
	var p := phys * 100.0 / (100.0 + armor * 0.6)
	if has_meta("hunted_until") and Time.get_ticks_msec() < int(get_meta("hunted_until")):
		# marked (a mark skill sets these): it takes more from everyone
		var more: float = float(get_meta("hunted_more", 0.0))
		p *= 1.0 + more
		fire *= 1.0 + more
	var total := p + fire
	if remote:
		# the host applies the real damage; show the hit straight away
		game.net.send_enemy_hit(self, phys, fire, from, knockback, crit)
		if not soft_hit:
			flash_t = 0.12
			_set_flash(1.0)
		var c2 := Color(1.0, 0.95, 0.8) if not crit else Color(1.0, 0.75, 0.2)
		if fire > p:
			c2 = Color(1.0, 0.55, 0.15)
		if dmg_tint.a > 0.0:
			c2 = dmg_tint
		Fx.number(game.world.fx_root, global_position + Vector3(0, height * 1.9 + 0.3, 0), str(int(total)) + ("!" if crit else ""), c2, crit)
		if dmg_tint.a <= 0.0 and not seared:
			Fx.blood(game.world.fx_root, global_position + Vector3(0, height * 1.0, 0), def.get("blood", Color(0.5, 0.0, 0.0)))
		_hit_sound(phys, knockback, crit)
		return total
	life -= total
	killed_by_rival = _by_rival
	if not soft_hit:
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
	if dmg_tint.a <= 0.0 and not seared:
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
	return def.get("material", "bone" if def.has("skin") else "flesh")

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
	RunTalents.on_death(self)     # (a run's talents: the explosions, spreads and kills' rewards of who struck it last)
	game.camp_check(self)     # (its camp's last? Camps)
	if boss:
		Sfx.play("boss_die", 0.0, randf_range(0.85, 1.15))
		game.guard_fell(kind)
	else:
		Sfx.play_at("kill_" + material(), global_position + Vector3(0, height, 0), -1.0)
	Fx.splat(game.world.fx_root, global_position, def.get("blood", Color(0.4, 0, 0)), 0.6 + radius)
	Fx.gore(game.world.fx_root, global_position + Vector3(0, height * 0.7, 0), def.get("blood", Color(0.4, 0, 0)), radius)

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
	p.y += Monsters.net_lift(self)      # (a perched Feral sits up in its tree)
	global_position = p
	rig.rotation.y = lerp_angle(rig.rotation.y, net_yaw, k)
	phase += _net_phase_rate * delta
	_pose({"time": anim_time, "phase": phase, "move": move_amt, "atk": net_atk,
		"style": atk_style, "hit": net_hit, "zombie": shamble, "aggro": aggro})

## Visual and sound side of the special attacks, run on every player's game.
func special_fx(ev: String) -> void:
	if hoard != null and hoard.boss == self and hoard.fx(ev):
		return
	if Monsters.fx(self, ev):
		return      # (a monster's own look: game/monsters/<monster>/)
	var col := Color(0.4, 1.0, 0.3) if def.get("nova", "") == "poison" else Color(1.0, 0.4, 0.1)
	match ev:
		"slam_tele":
			Fx.telegraph(game.world.fx_root, global_position, 4.2, atk_dur * Anim.impact_at("slam"))
		"nova_tele":
			Fx.telegraph(game.world.fx_root, global_position, 7.0, atk_dur * Anim.impact_at("cast"), col)
		"slam":
			ElementalFx.ground_slam(game, game.world.fx_root, global_position, 4.5)
			Sfx.play("slam")
			game.add_shake(0.6)
		"summon":
			ElementalFx.summon_circle(game, game.world.fx_root, global_position, 3.2)
			Sfx.play("summon")
		"nova":
			ElementalFx.fire_nova(game, game.world.fx_root, global_position, 7.0, col)
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
	if pvp_pid > 0 or pvp_obj > 0 or sandbox_hero != null:
		return          # a player's stand-in (Battlegrounds.sync_proxies / Sandbox moves it), or a thing of a player's (its ghost does)
	anim_time += delta
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			_set_flash(0.0)
		else:
			var k := clampf(flash_t / FLASH_T, 0.0, 1.0)
			flash_mat.set_shader_parameter("col", Color(_flash_col.r, _flash_col.g, _flash_col.b, _flash_col.a * (0.3 + 0.7 * k)))
	if dead:
		dead_t += delta
		var f := clampf(dead_t / 0.6, 0.0, 1.0)
		Monsters.fall(self, f, delta)      # (how its body goes down: game/monsters/monsters.gd)
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
	# (a camp's monsters (Camps, the Battlegrounds) never fight each other or the next camp: a camp mixing factions
	# fought itself from the start, and the whole map rang with their blows and kills (Blaine, 2026-11-06))
	if def.has("faction") and pack_id < Camps.FIRST_PACK:
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
	if scripted > 0.0:
		scripted -= delta
		return
	var to := hero.global_position - global_position
	to.y = 0
	var dist := to.length()
	if perch_h > 0.0:
		FeralBrain.perch(self, delta, hero, dist)
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
	# a Demon phased into the Underworld cannot be seen, nor a partner under a Shadow Phial (his state's bit,
	# Net._hero_packet), nor a hero gone unseen (Hero.hidden_t), nor a Plague Doctor in his fog from beyond its reach
	# (ClassSkills.hidden_from_monster; bosses and the Sloths see through the fog)
	var hero_dead: bool = hero.dead or hero.get("phased") == true or hero.get("net_invis") == true or float(hero.get("hidden_t") if hero.get("hidden_t") != null else 0.0) > 0.0
	if not hero_dead and not boss and sloth == null and hero is Hero:
		hero_dead = ClassSkills.hidden_from_monster(hero, global_position)
	if sloth != null:
		vel = sloth.update(delta, hero, to, dist, hero_dead)
	elif brain != null:
		vel = brain.update(delta, hero, to, dist, hero_dead)
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
		else:
			var idle: Variant = Monsters.idle(self, delta)      # (its own idle, or the shared wander)
			vel = idle if idle != null else _wander(delta)
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
	if slow_t > 0.0:
		slow_t -= delta
		vel *= 1.0 - slow_amt * (0.3 if boss else 1.0)
	if vel.length() > 0.01:
		global_position = game.world.move(global_position, vel * delta * (1.0 - chill_k), body_r())
		if aggro or vel.length() > 0.5:
			if atk_t < 0.0:
				_face(to if aggro and sloth == null and (dist <= 3.0 or f_state in ["back", "out"]) else vel)
		move_amt = move_toward(move_amt, clampf(vel.length() / maxf(speed, 0.1), 0.0, 1.0), delta * 5.0)
		var was := phase
		phase += delta * vel.length() * (1.6 / maxf(height, 0.5)) * (-1.0 if f_state in ["back", "out"] else 1.0) * (float(rig.get_meta("stride")) if rig.has_meta("stride") else 1.0)
		if Monsters.heavy_steps(self) and floorf(phase / PI) != floorf(was / PI) and move_amt > 0.4:
			_footstep()
	else:
		move_amt = move_toward(move_amt, 0.0, delta * 5.0)
	global_position.y = game.world.height_at(global_position.x, global_position.z)
	_pose({"time": anim_time, "phase": phase, "move": move_amt, "atk": (atk_t / atk_dur) if atk_t >= 0.0 else -1.0,
		"style": atk_style, "hit": hit_t, "zombie": shamble, "aggro": aggro})

## A dedicated server doesn't pose the bodies of its monsters and players: nobody sees them, and posing was half of a
## busy server's CPU (Battlegrounds, 6 players fighting: 18.1% of a core -> 8.2%, with the 30 Hz tick 4.8%; Blaine's
## capacity audit, 2026-11-05). Bones then stay in their rest pose (Grubb's bombs leave from a resting hand).
## `-- --server --pose` poses them again.
static var server_nopose := false

func _pose(st: Dictionary) -> void:
	if Enemy.server_nopose:
		return
	Monsters.pose_rig(rig, st, height)

## A heavy boss's footfall: a puff of dust under the planted foot, and the ground shakes a
## little if you're close.
func _footstep() -> void:
	var side := 1.0 if int(floorf(phase / PI)) % 2 == 0 else -1.0
	var foot := global_position + rig.global_transform.basis.x * side * 0.35
	Fx.burst(game.world.fx_root, foot + Vector3(0, 0.08, 0), Color(0.38, 0.33, 0.28, 0.6), 8, 1.2, 0.2, 0.6, false, -1.0, 70.0)
	var d: float = game.hero.global_position.distance_to(global_position)
	if d < 7.0:
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
	var own: Variant = Monsters.combat(self, delta, hero, to, dist)
	if own != null:
		return own      # (a monster with its own brain: game/monsters/<monster>/)
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
				begin_attack("")
			return Vector3.ZERO
		return _chase(delta, hero, dist)
	if dist <= rng_atk + hero.radius * 0.5:
		if cooldown <= 0.0:
			_face(to)
			begin_attack("")
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

func begin_attack(sp: String) -> void:
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
			begin_attack("slam")
			_fx("slam_tele")
		"summon", "nova", "volley":
			atk_style = "cast"
			begin_attack(sp)
			if sp == "nova":
				_fx("nova_tele")
		_:
			Monsters.begin_move(self, sp)      # (a family's own move: game/monsters/<monster>/)

func _update_attack(delta: float, hero: Node3D, dist: float) -> void:
	atk_t += delta
	var a := atk_t / atk_dur
	if not atk_path.is_empty():
		for sg in atk_path:
			if a >= float(sg[0]) and a <= float(sg[1]) + 0.08:
				var p: Vector3 = (sg[2] as Vector3).lerp(sg[3], smoothstep(float(sg[0]), float(sg[1]), a))
				var step := p - global_position
				step.y = 0
				global_position = game.world.move(global_position, step, body_r())
				break
	Monsters.during_move(self, a, hero)
	if a < Anim.impact_at(atk_style) * 0.8 and special in ["", "volley"]:
		_face(hero.global_position - global_position)
	if not impact_done and a >= Anim.impact_at(atk_style):
		impact_done = true
		_impact(hero, dist)
	if atk_t >= atk_dur:
		atk_t = -1.0
		cooldown = randf_range(0.3, 0.8) * (0.5 if boss else 1.0)
		atk_path = []
		Monsters.finish_move(self)      # (a family's own recovery after its move)
		special = ""

func roll() -> float:
	return randf_range(dmg[0], dmg[1])

func _impact(hero: Node3D, dist: float) -> void:
	if Monsters.impact_move(self, hero, dist):
		return      # (a family's own move landed)
	var fwd := -rig.global_transform.basis.z
	match special:
		"":
			if def["ai"] == "ranged":
				_shoot(hero.global_position, def.get("proj", "arrow"))
			else:
				var to: Vector3 = hero.global_position - global_position
				to.y = 0
				if dist <= def["range"] + hero.radius + 0.8 and fwd.dot(to.normalized()) > 0.2:
					hero.take_hit(roll(), global_position, "melee")
				if boss:
					_fx("boss_hit")
		"slam":
			_fx("slam")
			for h in game.all_heroes():
				if not h.dead and h.global_position.distance_to(global_position) < 4.4:
					h.take_hit(roll() * 1.5, global_position, "slam")
		"summon":
			_fx("summon")
			for i in 3:
				var p: Vector3 = game.world.free_spot_near(global_position, 5.0)
				game.spawn_enemy(def["summon"], p, level - 2, false, "", pack_id)
				Fx.burst(game.world.fx_root, p + Vector3(0, 0.5, 0), Color(0.6, 0.2, 1.0), 20, 3.0, 0.2, 0.8, true, 1.0)
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
					h.take_hit(roll() * 1.2, global_position, "nova", "fire")

func _shoot(at: Vector3, pkind: String) -> void:
	var pr := Projectile.new()
	game.world.fx_root.add_child(pr)
	var from := global_position + Vector3(0, height * 1.35, 0) + (-rig.global_transform.basis.z) * 0.5
	pr.launch(game, pkind, from, at + Vector3(0, 1.1, 0), roll())
	game.net.projectile(pkind, from, at + Vector3(0, 1.1, 0))
	Sfx.play_at(str(def.get("cast_sound", "bow" if pkind in ["arrow", "dart"] else "fireball")), global_position, -2.0, randf_range(0.9, 1.1))

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





# ---------------------------------------------------------------- the three Fallen



# ---------------------------------------------------------------- the Forsaken Bear (bear.gd)


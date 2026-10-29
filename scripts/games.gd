class_name Games
extends Node3D
## The games in Aurelia's arena: A2's boss fight. Varro the lanista opens the Gate of Life (begin); once a
## hero steps onto the sand the gate drops behind them (partners still outside are brought in) and the
## stages run, each announced to the roaring crowd: the lions, the gladiators, the beasts of the pit,
## then the champion (the act's boss, Data.ENEMIES "champion"), who calls more beasts and fighters onto
## the sand as he weakens. His fall ends the act as any boss's does (Game.on_enemy_killed).
##
## Host-authoritative like the Hoard: the state machine and every spawn run on the host; what everyone
## sees (gates, the crowd, the announcements) are event strings (fx) sent with Net.games_event. If every
## hero is down or gone from the arena for a while, the games stop and the gate opens again (reset).

const STAGES := [
	{"title": "The Lions", "sub": "Starved three days for your sake.", "spawns": [["lion", 3, "beast"]]},
	{"title": "The Gladiators", "sub": "Aurelia's finest. And its cheapest.", "spawns": [["gladiator", 3, "side"]]},
	{"title": "The Beasts of the Pit", "sub": "Everything Varro could catch, and one he couldn't.", "spawns": [["lion", 2, "beast"], ["gladiator", 2, "side"], ["lion", 1, "champion", true]]},
	{"title": "The Champion", "sub": "Aurelius has never lost.", "boss": "champion"},
]
const PACK := 820

var w: World
var game: Node
var state := "closed"           # closed, open, intro, stage, between, boss, won
var stage := -1
var t := 0.0
var away_t := 0.0
var foes: Array = []
var boss = null
var adds := 0
var lanista: Inter
var gate_box := -1              # the Gate of Life's bars in World.obstacles
var gate_half := Vector2.ZERO
var gate_at := Vector2.ZERO
var gates := {}                 # gate name -> portcullis
var crowd_mat: ShaderMaterial
var excite := 0.15
var excite_to := 0.15
var roar: AudioStreamPlayer     # the crowd's roar while the games run
var spike_t := 4.0              # the pit's spike traps (stage 3 and the champion's bout)
var spikes: Array = []          # host: [[points, seconds to the burst]]
var alive := 0                  # fighters on the sand last frame (a kill makes the crowd cheer)
var bursts := 0                 # spike bursts so far (tests)
var charge_t := 6.0             # the champion's shield charge: seconds to the next
var charge := {}                # host, while charging: {phase: wind|dash, t, dir, hit}
var charges := 0                # (tests)

func setup(world: World) -> void:
	w = world
	game = w.get_parent()
	for k in Aurelia.GATES:
		_portcullis(k, Aurelia.GATES[k])
	for k in ["west", "east"]:
		_portcullis(k, PI if k == "west" else 0.0)
	_crowd()

## After the zone's walk grid is made: the Gate of Life's bars become solid (A* still sees a way through,
## so paths cross the gate when it's open).
func after_raster(world: World) -> void:
	var p := Aurelia.floor_pt(Aurelia.GATES["life"], 1.04)
	gate_half = Vector2(3.4, 0.6)
	gate_at = p
	world.add_box(Vector3(p.x, 0, p.y), gate_half, PI * 0.5)
	gate_box = world.obstacles.size() - 1

func _host() -> bool:
	return game != null and not game.net.is_client()

# ---------------------------------------------------------------- the host's state machine
## Varro's deal is struck: the Gate of Life opens.
func begin() -> void:
	if not _host() or state not in ["closed"]:
		return
	state = "open"
	_event("open")

func _process(delta: float) -> void:
	_update_look(delta)
	if not _host() or game.world != w:
		return
	match state:
		"open":
			for h in game.all_heroes():
				if is_instance_valid(h) and not h.dead and Aurelia.floor_t(Vector2(h.global_position.x, h.global_position.z)) < 0.8:
					state = "intro"
					t = 3.5
					_event("shut")
					_bring_in_partners()
					break
		"intro", "between":
			t -= delta
			if t <= 0.0:
				_next_stage()
		"stage":
			foes = foes.filter(func(e): return is_instance_valid(e) and not e.dead)
			if foes.size() < alive and not foes.is_empty():
				_event("kill")
			alive = foes.size()
			if foes.is_empty():
				state = "between"
				t = 4.5
				_event("cheer")
		"boss":
			if boss == null or not is_instance_valid(boss) or boss.dead:
				state = "won"
				_event("won")
			else:
				_charge(delta)
				var f: float = boss.life / boss.max_life
				if adds == 0 and f < 0.6:
					adds = 1
					_event("adds:0")
					_spawn("lion", 2, "beast", false)
				elif adds == 1 and f < 0.3:
					adds = 2
					_event("adds:1")
					_spawn("gladiator", 2, "side", false)
	if (state == "stage" and stage >= 2) or state == "boss":
		_spike_traps(delta)
	if state in ["intro", "stage", "between", "boss"]:
		var anyone := false
		for h in game.all_heroes():
			if is_instance_valid(h) and not h.dead and Aurelia.floor_t(Vector2(h.global_position.x, h.global_position.z)) < 1.3:
				anyone = true
		away_t = 0.0 if anyone else away_t + delta
		if away_t > 8.0:
			_reset()

func _next_stage() -> void:
	stage += 1
	if stage >= STAGES.size():
		return
	var st: Dictionary = STAGES[stage]
	_event("stage:%d" % stage)
	if st.has("boss"):
		state = "boss"
		var p := Aurelia.floor_pt(Aurelia.GATES["champion"], 0.82)
		boss = game.spawn_enemy(st["boss"], Vector3(p.x, 0, p.y), w.level + 3, false, "", 999)
		return
	state = "stage"
	for sp in st["spawns"]:
		_spawn(sp[0], sp[1], sp[2], sp.size() > 3)
	alive = foes.size()

## Fighters onto the sand from a gate ("beast": the two beast gates, "side": west and east, or a gate's name).
func _spawn(kind: String, n: int, where: String, champ: bool) -> void:
	var names: Array = ["beast_w", "beast_e"] if where == "beast" else (["west", "east"] if where == "side" else [where])
	for i in n:
		var g: String = names[i % names.size()]
		var a: float = Aurelia.GATES.get(g, PI if g == "west" else 0.0)
		var p := Aurelia.floor_pt(a, 0.86) + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
		var cn := ""
		if champ:
			cn = "Old Scar, the Pit Lion" if kind == "lion" else "the Undefeated"
		var e = game.spawn_enemy(kind, Vector3(p.x, 0, p.y), w.level + 1 + stage, champ, cn, PACK + stage)
		if e != null:
			e.aggro = true
			foes.append(e)
		_event("gate:%s" % g)

## The pit's traps: every few seconds the sand glows in a handful of places (some under the heroes) and
## a moment later iron spikes burst up there, hurting heroes and beasts alike (never the champion).
func _spike_traps(delta: float) -> void:
	spike_t -= delta
	if spike_t <= 0.0:
		var enraged: bool = boss != null and is_instance_valid(boss) and boss.enraged
		spike_t = randf_range(3.5, 5.0) if enraged else randf_range(5.5, 8.0)
		var pts := []
		for h in game.all_heroes():
			if is_instance_valid(h) and not h.dead:
				pts.append(Vector2(h.global_position.x, h.global_position.z) + Vector2(randf_range(-1.2, 1.2), randf_range(-1.2, 1.2)))
		while pts.size() < 6:
			var a := randf() * TAU
			pts.append(Aurelia.floor_pt(a, sqrt(randf()) * 0.78))
		spikes.append([pts, 1.3])
		_event("spikes:" + "|".join(pts.map(func(q): return "%.1f,%.1f" % [q.x, q.y])))
	for sp in spikes.duplicate():
		sp[1] -= delta
		if sp[1] > 0.0:
			continue
		spikes.erase(sp)
		bursts += 1
		var dmg := (8.0 + w.level * 2.0) * float(game.run_mult("dmg"))
		for q in sp[0]:
			var at := Vector3(q.x, 0, q.y)
			for h in game.all_heroes():
				if is_instance_valid(h) and not h.dead and Vector2(h.global_position.x - q.x, h.global_position.z - q.y).length() < 1.7:
					h.take_hit(dmg, at, "nova", "phys")
			for e in game.enemies_near(at, 1.9):
				if not e.boss and not e.dead:
					e.take_damage(dmg * 0.6, 0.0, at, 0.6, false)

## Aurelius's shield charge: a line glows across the sand from him to a hero, he braces behind his shield,
## then barrels down it, smashing anyone in the way (once each). He is driven from here meanwhile
## (Enemy.scripted).
func _charge(delta: float) -> void:
	if charge.is_empty():
		charge_t -= delta
		if charge_t > 0.0 or boss.atk_t >= 0.0 or boss.stun_t > 0.0:
			return
		var target = null
		var bd := 99.0
		for h in game.all_heroes():
			if is_instance_valid(h) and not h.dead:
				var d: float = h.global_position.distance_to(boss.global_position)
				if d < bd:
					bd = d
					target = h
		if target == null or bd < 4.5 or bd > 17.0:
			charge_t = 1.0
			return
		var dir: Vector3 = target.global_position - boss.global_position
		dir.y = 0
		dir = dir.normalized()
		charge = {"phase": "wind", "t": 0.8, "dir": dir, "hit": {}}
		boss.scripted = 3.0
		boss.rig.rotation.y = atan2(-dir.x, -dir.z)
		charges += 1
		var b: Vector3 = boss.global_position
		_event("charge:%.1f,%.1f,%.2f,%.2f" % [b.x, b.z, dir.x, dir.z])
		return
	var dir: Vector3 = charge["dir"]
	charge["t"] -= delta
	if charge["phase"] == "wind":
		boss._pose({"time": boss.anim_time, "phase": boss.phase, "move": 0.0, "atk": 0.15, "style": "over", "hit": 0.0})
		if charge["t"] <= 0.0:
			charge["phase"] = "dash"
			charge["t"] = 0.95
		return
	var before: Vector3 = boss.global_position
	boss.global_position = w.move(boss.global_position, dir * 15.0 * delta, boss.body_r())
	boss.global_position.y = w.height_at(boss.global_position.x, boss.global_position.z)
	boss.phase += delta * 15.0 * 1.6 / maxf(boss.height, 0.3)
	boss._pose({"time": boss.anim_time, "phase": boss.phase, "move": 1.4, "atk": -1.0, "style": "", "hit": 0.0})
	for h in game.all_heroes():
		if is_instance_valid(h) and not h.dead and not charge["hit"].has(h.get_instance_id()) and h.global_position.distance_to(boss.global_position) < 1.8:
			charge["hit"][h.get_instance_id()] = true
			h.take_hit(boss._roll() * 1.6, boss.global_position - dir, "melee")
	var stuck: bool = boss.global_position.distance_to(before) < 15.0 * delta * 0.3
	if charge["t"] <= 0.0 or stuck or Aurelia.floor_t(Vector2(boss.global_position.x, boss.global_position.z)) > 0.92:
		charge = {}
		boss.scripted = 0.0
		charge_t = randf_range(6.5, 9.5) if not boss.enraged else randf_range(4.5, 6.5)
		_event("charge_end")

## Partners still outside when the gate drops are brought onto the sand.
func _bring_in_partners() -> void:
	var p: Vector3 = w.spawns["arena"]
	for h in game.all_heroes():
		if h == game.hero or not is_instance_valid(h):
			continue
		if Aurelia.floor_t(Vector2(h.global_position.x, h.global_position.z)) > 0.95:
			game.net.place_player(h.peer_id, p + Vector3(randf_range(-2, 2), 0, randf_range(-1, 1)))

func _reset() -> void:
	for e in foes:
		if is_instance_valid(e) and not e.dead:
			e.queue_free()
	foes.clear()
	if boss != null and is_instance_valid(boss) and not boss.dead:
		boss.queue_free()
	boss = null
	stage = -1
	adds = 0
	away_t = 0.0
	state = "closed"
	_event("reset")

func _event(ev: String) -> void:
	fx(ev)
	if game.net.active and game.net.is_host:
		game.net.games_event(ev)

# ---------------------------------------------------------------- what everyone sees
func fx(ev: String) -> void:
	var ui = game.ui
	var parts := ev.split(":")
	match parts[0]:
		"open":
			_gate("life", true)
			ui.message("The Gate of Life grinds open. Step onto the sand.", Color(1.0, 0.85, 0.5), 4.0)
			excite_to = 0.35
		"shut":
			_gate("life", false)
			ui.big_message("The Games of Aurelia")
			Sfx.play("arena_horn", -2.0)
			excite_to = 0.6
			if roar == null:
				roar = Sfx.start_loop("crowd_roar", -10.0)
		"stage":
			var st: Dictionary = STAGES[int(parts[1])]
			ui.big_message(st["title"])
			ui.message(st["sub"], Color(1.0, 0.85, 0.5), 4.0)
			Sfx.play("arena_horn", -4.0, 1.05)
			excite_to = 0.8
			if st.has("boss"):
				_gate("champion", true)
				get_tree().create_timer(3.0, false).timeout.connect(func(): _gate("champion", false))
		"gate":
			_gate(parts[1], true)
			if gates.has(parts[1]) and (parts[1].begins_with("beast") or parts[1] == "champion"):
				Sfx.play_at("lion_roar", (gates[parts[1]] as Node3D).global_position, 0.0, randf_range(0.9, 1.05))
			get_tree().create_timer(2.6, false).timeout.connect(func(): _gate(parts[1], false))
		"charge":
			var v := parts[1].split(",")
			_show_charge(Vector3(float(v[0]), 0, float(v[1])), Vector3(float(v[2]), 0, float(v[3])))
		"charge_end":
			excite = minf(1.0, excite + 0.25)
		"kill":
			excite = minf(1.0, excite + 0.35)
			Sfx.play("crowd_cheer", -12.0, randf_range(0.95, 1.08))
		"spikes":
			var pts := []
			for q in parts[1].split("|"):
				var xy := q.split(",")
				pts.append(Vector2(float(xy[0]), float(xy[1])))
			_show_spikes(pts)
		"cheer":
			ui.message("The crowd roars for more!", Color(1.0, 0.85, 0.5), 3.0)
			Sfx.play("crowd_cheer", -2.0)
			excite = 1.0
			excite_to = 0.55
		"adds":
			ui.message(["Aurelius calls for the lions!", "Aurelius calls his brothers onto the sand!"][int(parts[1])], Color(1.0, 0.6, 0.4), 3.5)
			Sfx.play("crowd_cheer", -4.0, 0.9)
			excite = 1.0
		"won":
			_gate("life", true)
			Sfx.play("crowd_cheer", 0.0)
			excite = 1.0
			excite_to = 0.9
		"reset":
			_gate("life", true)
			ui.message("The games are over. Varro will take another wager.", Color(0.85, 0.75, 0.6), 4.0)
			excite_to = 0.15
			_stop_roar()

func _stop_roar() -> void:
	if roar != null and is_instance_valid(roar):
		roar.queue_free()
	roar = null

func _exit_tree() -> void:
	_stop_roar()

func _update_look(delta: float) -> void:
	excite = move_toward(excite, excite_to, delta * 0.25)
	if crowd_mat:
		crowd_mat.set_shader_parameter("excite", excite)

## The charge's telegraph: a red streak along the sand where he'll run, a shout, then the dash's sound.
func _show_charge(from: Vector3, dir: Vector3) -> void:
	var line := MeshInstance3D.new()
	line.mesh = Geo.box(1.4, 0.02, 14.0)
	line.material_override = Mats.glow_unique(Color(0.75, 0.1, 0.03), 0.4)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.fx_root.add_child(line)
	line.position = Vector3(from.x, w.height_at(from.x, from.z) + 0.04, from.z) + dir * 7.5
	line.rotation.y = atan2(dir.x, dir.z)
	line.scale = Vector3(1, 1, 0.1)
	var tw := line.create_tween()
	tw.tween_property(line, "scale", Vector3(1, 1, 1), 0.7)
	tw.tween_interval(0.3)
	tw.tween_callback(line.queue_free)
	Sfx.play_at("battle_cry", from, -6.0, 0.7)
	get_tree().create_timer(0.8, false).timeout.connect(func(): Sfx.play_at("charge_dash", from, 0.0, 0.85))
	excite = minf(1.0, excite + 0.2)

## Glowing warnings on the sand, then iron spikes bursting up through it with dust, sinking again.
func _show_spikes(pts: Array) -> void:
	for q in pts:
		var p := Vector3(q.x, w.height_at(q.x, q.y), q.y)
		var warn := MeshInstance3D.new()
		warn.mesh = Geo.cyl(1.6, 1.6, 0.02, 24)
		warn.material_override = Mats.glow_unique(Color(0.75, 0.12, 0.03), 0.45)
		warn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.fx_root.add_child(warn)
		warn.position = p + Vector3(0, 0.03, 0)
		warn.scale = Vector3(0.2, 1, 0.2)
		var tw := warn.create_tween()
		tw.tween_property(warn, "scale", Vector3(1, 1, 1), 1.2)
		tw.tween_callback(func():
			warn.queue_free()
			if not is_instance_valid(w) or not w.is_inside_tree():
				return
			var trap := Node3D.new()
			w.fx_root.add_child(trap)
			trap.position = p + Vector3(0, -1.2, 0)
			var iron := Props.iron()
			for k in 7:
				var a := TAU * k / 7.0
				var r := 0.25 + (k % 3) * 0.4
				Models.P(trap, Geo.cone(0.09, 1.1, 6), iron, Vector3(cos(a) * r, 0.55, sin(a) * r), Vector3(randf_range(-12, 12), 0, randf_range(-12, 12)))
			var up := trap.create_tween()
			up.tween_property(trap, "position:y", p.y, 0.08)
			up.tween_interval(1.4)
			up.tween_property(trap, "position:y", p.y - 1.3, 0.5)
			up.tween_callback(trap.queue_free)
			Fx.burst(w.fx_root, p + Vector3(0, 0.3, 0), Color(0.6, 0.5, 0.35, 0.7), 18, 3.0, 0.25, 0.6, false, -2.0)
			Sfx.play_at("impact_metal", p, -3.0, randf_range(0.8, 0.95))
			game.add_shake(0.08))

# ---------------------------------------------------------------- gates
## An iron portcullis in the podium wall at angle a, a dark passage behind it (the Gate of Life's is
## the real gap in the wall; the others lead nowhere you can go).
func _portcullis(name: String, a: float) -> void:
	var p := Aurelia.floor_pt(a, 1.04)
	var root := Models.N(w.props_root, "gate_" + name)
	root.position = Vector3(p.x, 0, p.y)
	var tang := Aurelia.floor_pt(a + 0.01, 1.04) - p
	root.rotation.y = atan2(-tang.y, tang.x)
	var width := 6.0 if name == "life" or name == "champion" else 3.6
	var h := 3.2
	if name != "life":
		Models.P(root, Geo.box(width + 0.4, h + 0.2, 0.1), Mats.mat(Color(0.02, 0.015, 0.01), 1.0), Vector3(0, (h + 0.2) * 0.5, 0.0))
		Models.P(root, Geo.box(width + 1.0, 0.5, 1.4), Roman.marble(), Vector3(0, h + 0.45, 0))
	var bars := Models.N(root, "bars")
	var iron := Props.iron()
	var n := int(width / 0.42)
	for i in n + 1:
		Models.seg(bars, Vector3(-width * 0.5 + i * width / n, 0, -0.65 if name != "life" else 0.0), Vector3(-width * 0.5 + i * width / n, h, -0.65 if name != "life" else 0.0), 0.045, 0.045, iron, 5)
	for k in 4:
		Models.seg(bars, Vector3(-width * 0.5, 0.5 + k * 0.85, -0.65 if name != "life" else 0.0), Vector3(width * 0.5, 0.5 + k * 0.85, -0.65 if name != "life" else 0.0), 0.04, 0.04, iron, 5)
	gates[name] = bars

func _gate(name: String, up: bool) -> void:
	if not gates.has(name):
		return
	var bars: Node3D = gates[name]
	var tw := create_tween()
	tw.tween_property(bars, "position:y", 3.0 if up else 0.0, 1.2 if up else 0.5)
	Sfx.play_at("portcullis", bars.global_position if bars.is_inside_tree() else Vector3.ZERO, -2.0)
	if name == "life" and gate_box >= 0 and gate_box < w.obstacles.size():
		# open: the bars' footprint moves far off (World's buckets still list it here, it just never touches)
		(w.obstacles[gate_box] as Array)[0] = gate_at + (Vector2(0, 5000) if up else Vector2.ZERO)

# ---------------------------------------------------------------- the crowd
## The bandits' crowd on the standing stands (north and the sides): figures in rough colours that sway,
## then jump and wave as the games excite them (shader, `excite`).
func _crowd() -> void:
	var bodies: Array = []
	var cols: Array = []
	var pal := [Color(0.45, 0.3, 0.18), Color(0.3, 0.26, 0.2), Color(0.5, 0.12, 0.08), Color(0.62, 0.55, 0.42), Color(0.25, 0.3, 0.18), Color(0.38, 0.2, 0.36), Color(0.7, 0.62, 0.5)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for k in 4:
		var kk := float(k) / 3.0
		var rx := lerpf(Aurelia.FLOOR_RX * 1.04 + 1.8, Aurelia.OUTER_RX - 3.0, kk)
		var rz := lerpf(Aurelia.FLOOR_RZ * 1.04 + 1.8, Aurelia.OUTER_RZ - 3.0, kk)
		var top := Aurelia.PODIUM_H + 0.4 + k * 1.7
		for row in 2:
			var rr := 1.0 + (row - 0.5) * 0.06
			var steps := int(TAU * (rx + rz) * 0.5 / 0.95)
			for i in steps:
				var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / steps
				if sin(a) > -0.05 and absf(cos(a)) < 0.82:
					continue     # the fallen south stands: nobody there
				if rng.randf() < 0.12:
					continue
				var p := Aurelia.CENTRE + Vector2(cos(a) * rx * rr, sin(a) * rz * rr)
				var face := atan2(Aurelia.CENTRE.x - p.x, Aurelia.CENTRE.y - p.y)
				var s := rng.randf_range(0.85, 1.1)
				bodies.append(Transform3D(Basis(Vector3.UP, face).scaled(Vector3(s, s, s)), Vector3(p.x, top + row * 0.25, p.y)))
				cols.append(pal[rng.randi() % pal.size()])
	crowd_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CROWD_SHADER
	crowd_mat.shader = sh
	var body := _person_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = body
	mm.instance_count = bodies.size()
	for i in bodies.size():
		mm.set_instance_transform(i, bodies[i])
		mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = crowd_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "crowd"
	w.props_root.add_child(mi)

## One spectator: a body and a head in one mesh; the head is marked by UV.y > 0.5 so the shader skins it.
func _person_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [[CapsuleMesh.new(), Vector3(0, 0.55, 0), 0.0], [SphereMesh.new(), Vector3(0, 1.28, 0), 1.0]]
	(parts[0][0] as CapsuleMesh).radius = 0.22
	(parts[0][0] as CapsuleMesh).height = 1.1
	(parts[0][0] as CapsuleMesh).radial_segments = 8
	(parts[0][0] as CapsuleMesh).rings = 2
	(parts[1][0] as SphereMesh).radius = 0.15
	(parts[1][0] as SphereMesh).height = 0.3
	(parts[1][0] as SphereMesh).radial_segments = 8
	(parts[1][0] as SphereMesh).rings = 4
	for part in parts:
		var arr: Array = (part[0] as PrimitiveMesh).get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx:
			st.set_normal(nrm[i])
			st.set_uv(Vector2(0, part[2]))
			st.add_vertex(v[i] + part[1])
	return st.commit()

const CROWD_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float excite = 0.2;
varying float head;
void vertex() {
	head = UV.y;
	float ph = float(INSTANCE_ID) * 1.618;
	float jump = max(0.0, sin(TIME * (5.0 + fract(ph) * 3.0) + ph * 6.28));
	float sway = sin(TIME * 1.3 + ph * 6.28) * 0.04;
	VERTEX.x += sway * VERTEX.y;
	VERTEX.y += jump * jump * excite * 0.35;
	// arms up when the crowd is roaring: the shoulders lift
	VERTEX.y += step(0.8, VERTEX.y) * excite * jump * 0.12;
}
void fragment() {
	vec3 skin = vec3(0.62, 0.46, 0.34);
	ALBEDO = mix(COLOR.rgb, skin, step(0.5, head));
	ROUGHNESS = 0.9;
}
"""

class_name GraveyardSite
extends Node3D
## One graveyard as it is seen (GraveyardFx): the old waypoint's rune-carved stone ring rising out of the ground as its
## floor, its rune rings burning soul green; the waypoint's hooded guardian at its head, two of its broken pillars,
## gravestones round the edge (Meshy) and two braziers of green soul fire; and the risen dead, the game's own zombies
## and bone archers (Monsters.build_rig), clawing up out of the earth between the graves. Each strike turns one of
## them to where it struck and plays its attack; at the end they crumble to bone dust and everything sinks.
## Its pieces are this skill's props (props/: the waypoint's from archive/camp/props/waypoint/, the gravestones from
## Meshy). It draws only.

const PROPS := "res://game/heroes/necromancer/skills/graveyard/props/"
const SOUL := Color(0.4, 1.0, 0.55)
const FIRE := Color(0.12, 0.85, 0.3, 0.75)      # the braziers' soul fire (deep: additive specks wash to white)
const RISE_T := 0.9          # seconds the place takes to tear up out of the ground
const SINK_T := 1.2          # and to sink back
const ATK_T := 0.6           # one of the dead's strike
## the dead, in turn: two zombies, then a bone archer, ... (Data.ENEMIES kinds)
const DEAD := ["zombie", "skel_archer", "zombie", "skel_archer", "zombie", "skel_archer"]

var game: Node
var r := 6.0
var secs := 8.0
var t := 0.0
var ending := false
var _end_t := 0.0
var props: Array = []        # [node, its resting y]
var dead: Array = []         # {rig, h, at, atk: seconds into a strike (-1), yaw}
var glow: OmniLight3D
var runes: MeshInstance3D

func setup(g: Node, at: Vector3, radius: float, life: float, n: int) -> void:
	game = g
	r = radius
	secs = life
	_build(n)

func _build(n: int) -> void:
	# the floor: the waypoint's dais, flush with the ground once risen
	var dais := _prop("dais.glb", 0.0, r * 2.0 / 10.0, true)      # (props/dais.glb: 10 m across)
	if dais != null:
		# (the dais has no material of its own: the camp dressed it in the game's stone, as here, darker for a grave)
		var stone := Mats.world(Color(0.2, 0.2, 0.21), Color(0.11, 0.11, 0.12), 0.92, 1.8, 0.35, Props.MOSS)
		for mi in dais.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = stone
		_add(dais, Vector3.ZERO, 0.0, -0.08)
	runes = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(r * 1.9, r * 1.9)
	q.orientation = PlaneMesh.FACE_Y
	runes.mesh = q
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(SOUL.r, SOUL.g, SOUL.b, 0.0)
	if ResourceLoader.exists(PROPS + "rune_rings.png"):
		rm.albedo_texture = load(PROPS + "rune_rings.png")
	runes.material_override = rm
	runes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(runes)
	runes.position = Vector3(0, 0.12, 0)
	# the guardian at its head, two broken pillars at its sides
	var g := _prop("guardian.glb", 2.3)
	if g != null:
		_add(g, Vector3(0, 0, -r * 0.92), 0.0)
	for side in [-1.0, 1.0]:
		var p := _prop("pillar.glb", 1.3)
		if p != null:
			_add(p, Vector3(side * r * 0.9, 0, -r * 0.35), randf() * TAU)
	# gravestones round the rim
	var stones := ["grave_a.glb", "grave_b.glb", "grave_d.glb"]
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.15
		var s := _prop(stones[i % stones.size()], 1.05 + 0.25 * float(i % 2))
		if s != null:
			var at := Vector3(cos(a), 0, sin(a)) * r * 0.82
			_add(s, at, atan2(-at.x, -at.z) + randf_range(-0.3, 0.3))
			s.rotation.z = randf_range(-0.12, 0.12)       # (old graves lean)
	# two braziers of soul fire either side of the guardian
	for side in [-1.0, 1.0]:
		var b := _prop("brazier.glb", 1.1)
		if b != null:
			var at := Vector3(side * r * 0.4, 0, -r * 0.78)
			_add(b, at, 0.0)
			var fire := Node3D.new()
			b.add_child(fire)
			fire.position = Vector3(0, 1.05 / maxf(b.scale.y, 0.01), 0)
			Fx.aura(fire, FIRE, 16, 0.4, 0.11, 0.7, 1.4, 0.07)
			var fl := OmniLight3D.new()
			fl.light_color = SOUL
			fl.light_energy = 0.9
			fl.omni_range = 3.5
			fire.add_child(fl)
	glow = OmniLight3D.new()
	glow.light_color = SOUL
	glow.light_energy = 0.0
	glow.omni_range = r * 1.6
	glow.shadow_enabled = false
	add_child(glow)
	glow.position = Vector3(0, 1.6, 0)
	# the risen dead, below the ground until they claw up
	for i in n:
		var kind: String = DEAD[i % DEAD.size()]
		if not Data.ENEMIES.has(kind):
			continue
		var rig := Monsters.build_rig(kind)
		rig.set_meta("pers", Monsters.personality(kind))
		add_child(rig)
		var at: Vector3 = Graveyard.risen_spot(Vector3.ZERO, r, i, n)
		var look: Dictionary = Data.ENEMIES[kind]["look"]
		var yaw := atan2(at.x, at.z)       # (facing out of the middle)
		rig.position = at + Vector3(0, -2.2, 0)
		rig.rotation.y = yaw
		dead.append({"rig": rig, "h": float(look.get("height", 1.0)), "at": at, "atk": -1.0, "yaw": yaw, "phase": randf() * TAU,
			"delay": 0.25 + 0.12 * float(i), "kind": kind})

## A prop of this skill, scaled to `height` metres tall (or by `scale` when given).
func _prop(file: String, height: float, scale := 0.0, flat := false) -> Node3D:
	var path := PROPS + file
	if not ResourceLoader.exists(path):
		return null
	var n := ResCache.inst(path) as Node3D
	if n == null:
		return null
	var k := scale
	if k <= 0.0:
		var hgt := _height(n)
		k = height / hgt if hgt > 0.01 else 1.0
	n.scale = Vector3.ONE * k
	if flat:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

static func _height(n: Node3D) -> float:
	var top := -INF
	var bot := INF
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var bb: AABB = m.transform * m.mesh.get_aabb()
		top = maxf(top, bb.end.y)
		bot = minf(bot, bb.position.y)
	return top - bot if top > bot else 0.0

func _add(n: Node3D, at: Vector3, yaw: float, rest_y := 0.0) -> void:
	add_child(n)
	n.position = Vector3(at.x, rest_y - 2.5, at.z)
	n.rotation.y = yaw
	props.append([n, rest_y, at])

## One of the dead strikes where `at` is (world space): it turns to it and swings.
func strike(i: int, at) -> void:
	if i < 0 or i >= dead.size() or not at is Vector3 or ending:
		return
	var d: Dictionary = dead[i]
	var to: Vector3 = (at as Vector3) - (global_position + d["at"])
	d["yaw"] = atan2(-to.x, -to.z)
	d["atk"] = 0.0
	Fx.burst(game.world.fx_root, (at as Vector3) + Vector3(0, 1.0, 0), Color(SOUL.r, SOUL.g, SOUL.b, 0.7), 8, 2.5, 0.05, 0.3, true, 0.0)

## The end: the dead crumble to bone dust, the graves and the floor sink.
func crumble() -> void:
	if ending:
		return
	ending = true
	_end_t = 0.0
	for d in dead:
		var p: Vector3 = global_position + d["at"]
		Fx.burst(game.world.fx_root, p + Vector3(0, 0.9, 0), Color(0.85, 0.82, 0.72, 0.7), 18, 2.0, 0.06, 0.6, false, -4.0, 160.0)

func _process(delta: float) -> void:
	if game == null or game.world == null:
		queue_free()
		return
	t += delta
	var up := clampf(t / RISE_T, 0.0, 1.0)
	var down := clampf(_end_t / SINK_T, 0.0, 1.0) if ending else 0.0
	if ending:
		_end_t += delta
	elif t > secs + 1.5:
		crumble()        # (the "end" event never came: a dropped one, or the caster gone)
	var shown := ease(up, 0.4) * (1.0 - ease(down, 2.0))
	for p in props:
		var n: Node3D = p[0]
		n.position.y = lerpf(float(p[1]) - 2.5, float(p[1]), shown)
	(runes.material_override as StandardMaterial3D).albedo_color.a = 0.85 * shown * (0.8 + 0.2 * sin(t * 3.0))
	glow.light_energy = 1.4 * shown
	for d in dead:
		_pose_dead(d, delta, shown)
	if ending and _end_t > SINK_T:
		queue_free()

func _pose_dead(d: Dictionary, delta: float, shown: float) -> void:
	var rig: Node3D = d["rig"]
	var rise := clampf((t - float(d["delay"])) / 0.8, 0.0, 1.0)
	var y := lerpf(-2.2, 0.0, ease(rise, 0.5))
	if ending:
		y = lerpf(0.0, -2.4, 1.0 - shown)
	rig.position.y = y
	rig.rotation.y = lerp_angle(rig.rotation.y, float(d["yaw"]), clampf(delta * 8.0, 0.0, 1.0))
	d["phase"] = float(d["phase"]) + delta * 2.0
	var atk := -1.0
	if float(d["atk"]) >= 0.0:
		d["atk"] = float(d["atk"]) + delta
		atk = float(d["atk"]) / ATK_T
		if atk >= 1.0:
			d["atk"] = -1.0
			atk = -1.0
	var style := "bow" if str(d["kind"]) == "skel_archer" else "claw"
	Monsters.pose_rig(rig, {"time": t, "phase": float(d["phase"]), "move": 0.0, "atk": atk, "style": style,
		"zombie": str(d["kind"]) == "zombie", "aggro": true, "hit": 0.0}, float(d["h"]))

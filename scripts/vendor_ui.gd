class_name VendorUI
extends RefCounted
## The town's people on screen: nameplates over the vendors (and Varro) and the live portrait of
## whoever you trade with, shown at the head of the trade window (ui.gd `_build_shop`).

const ROLE_TITLES := {"smith": "Blacksmith", "armor": "Armourer", "alch": "Alchemist", "gamble": "Gambler",
	"elder": "Keeper of the Camp", "lanista": "Master of the Games"}

static func title_for(it: Inter) -> String:
	if it.kind == "lanista":
		return ROLE_TITLES["lanista"]
	return str(ROLE_TITLES.get(str(it.data.get("role", "")), ""))

## Head height of an NPC above its feet (measured once) for the plate and the portrait.
static func height_of(it: Inter) -> float:
	if not it.has_meta("plate_h"):
		var body: Node3D = it.model if it.model else it.rig
		it.set_meta("plate_h", head_top(body, it.global_transform) if body and body.is_inside_tree() else 1.9)
	return float(it.get_meta("plate_h"))

## The top of a body's head in base's frame: from its skeleton's head bone when it has one (a skinned
## mesh's bounds are in the armature's units), else from its meshes' bounds.
static func head_top(body: Node3D, base: Transform3D) -> float:
	var sk := body.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk:
		for bn in ["HeadTop_End", "head_end", "Head", "head"]:
			var b := sk.find_bone(bn)
			if b >= 0:
				var p: Vector3 = base.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(b).origin)
				return p.y + (0.04 if bn.ends_with("nd") else 0.2)
	var ab := _aabb(body, base.affine_inverse())
	return ab.end.y if ab.size.y > 0.3 else 1.9

## The meshes' bounds in to's frame (rest pose for skinned ones, which is near enough).
static func _aabb(n: Node, to: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if not vi.is_visible_in_tree() or vi is Light3D:
			continue
		var xf: Transform3D = to * vi.global_transform if vi.is_inside_tree() else Transform3D()
		var b: AABB = xf * vi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

## Gold-trimmed nameplates that float over the town's people, fading with distance and brightening
## under the cursor. Click-through (the NPC under it is still the one clicked).
class Plates extends Control:
	var ui
	var plates := {}     # Inter -> PanelContainer
	var marks := {}      # Inter -> Label: the quest giver's "!" (work on offer) or "?" (a quest to hand in)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _plate(it: Inter) -> PanelContainer:
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.045, 0.035, 0.025, 0.82)
		sb.border_color = Color(0.55, 0.43, 0.24, 0.9)
		sb.set_border_width_all(1)
		sb.border_width_bottom = 2
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 3
		sb.content_margin_bottom = 4
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 5
		p.add_theme_stylebox_override("panel", sb)
		var vb := VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", -2)
		p.add_child(vb)
		var nm := Label.new()
		nm.name = "name"
		nm.text = "◆  %s  ◆" % it.label
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_override("font", ui.font_title)
		nm.add_theme_font_size_override("font_size", 16)
		nm.add_theme_color_override("font_color", Color(0.96, 0.8, 0.45))
		nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		nm.add_theme_constant_override("outline_size", 4)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(nm)
		var t := VendorUI.title_for(it)
		if t != "":
			var tl := Label.new()
			var fv := FontVariation.new()
			fv.base_font = ui.font_body
			fv.spacing_glyph = 2
			tl.text = t.to_upper()
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tl.add_theme_font_override("font", fv)
			tl.add_theme_font_size_override("font_size", 10)
			tl.add_theme_color_override("font_color", Color(0.74, 0.66, 0.52))
			tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(tl)
		add_child(p)
		p.reset_size()
		return p

	func _process(_d: float) -> void:
		var g = ui.game
		var cam: Camera3D = get_viewport().get_camera_3d()
		if g == null or g.world == null or g.hero == null or cam == null or not g.playing:
			visible = false
			return
		visible = true
		var live := {}
		for it in g.world.interactables:
			if not is_instance_valid(it) or not (it.kind == "vendor" or it.kind == "lanista") or not it.is_inside_tree():
				continue
			live[it] = true
			var p: PanelContainer = plates.get(it)
			if p == null:
				p = _plate(it)
				plates[it] = p
			var head: Vector3 = it.global_position + Vector3(0, VendorUI.height_of(it) + 0.35, 0)
			var d: float = g.hero.global_position.distance_to(it.global_position)
			if cam.is_position_behind(head) or d > 18.0:
				p.visible = false
				if marks.has(it):
					(marks[it] as Label).visible = false
				continue
			var hov: bool = g.hovered == it
			p.visible = true
			p.modulate.a = clampf((18.0 - d) / 5.0, 0.0, 1.0) * (1.0 if hov else 0.9)
			var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
			sb.border_color = Color(1.0, 0.84, 0.45) if hov else Color(0.55, 0.43, 0.24, 0.9)
			p.scale = Vector2.ONE * (1.07 if hov else 1.0)
			p.pivot_offset = Vector2(p.size.x * 0.5, p.size.y)
			var sp: Vector2 = cam.unproject_position(head)
			p.position = (sp - Vector2(p.size.x * 0.5, p.size.y)).round()
			_mark(it, p, g)
		for it in plates.keys():
			if not live.has(it):
				var p: PanelContainer = plates[it]
				if is_instance_valid(p):
					p.queue_free()
				plates.erase(it)
				if marks.has(it):
					(marks[it] as Label).queue_free()
					marks.erase(it)

	## A gold "!" or "?" over the plate of someone with a quest (Quests.mark), bobbing gently.
	func _mark(it: Inter, p: PanelContainer, g) -> void:
		var mk: String = g.quests.mark(str(it.data.get("role", ""))) if g.quests != null and it.kind == "vendor" else ""
		var l: Label = marks.get(it)
		if mk == "":
			if l != null:
				l.visible = false
			return
		if l == null:
			l = Label.new()
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_font_override("font", ui.font_title)
			l.add_theme_font_size_override("font_size", 34)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
			l.add_theme_constant_override("outline_size", 7)
			l.size = Vector2(40, 44)
			add_child(l)
			marks[it] = l
		l.text = mk
		l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3) if mk == "!" else Color(0.75, 0.9, 1.0))
		l.visible = p.visible
		l.modulate.a = p.modulate.a
		var bob := sin(Time.get_ticks_msec() / 260.0) * 3.0
		l.position = (p.position + Vector2(p.size.x * 0.5 - 20.0, -46.0 + bob)).round()

## A live, lit bust of the trader: a copy of their model in its own little world, playing their
## talk and idle clips.
class Portrait extends SubViewportContainer:
	var vp := SubViewport.new()
	var ap: AnimationPlayer
	var clips := {}
	var _talk_left := 0.0

	func setup(it: Inter) -> void:
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_2X
		vp.size = Vector2i(132, 156)
		add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.07, 0.05, 0.035)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.5, 0.45, 0.4)
		env.ambient_light_energy = 0.6
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-25, 35, 0)
		key.light_energy = 1.3
		key.light_color = Color(1.0, 0.86, 0.68)
		vp.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-15, 200, 0)
		rim.light_energy = 1.6
		rim.light_color = Color(1.0, 0.55, 0.25)
		vp.add_child(rim)
		# their own copy of the body (a duplicate of the town's would drag its runtime extras along badly)
		var body: Node3D
		if it.has_meta("npc_file"):
			body = (load(str(it.get_meta("npc_file"))) as PackedScene).instantiate()
			vp.add_child(body)
			if it.has_meta("hold"):
				ForestCamp.hold(body, it.get_meta("hold"))
			body.rotation.y = 0.35                 # Meshy models face +z
		elif it.has_meta("look"):
			body = Models.humanoid(it.get_meta("look"))
			vp.add_child(body)
			body.rotation.y = PI + 0.35            # the game's humanoids face -z
			Anim.pose(body, {"time": 0.0, "phase": 0.0, "move": 0.0, "atk": -1.0, "style": "cast"})
		else:
			return
		ap = body.find_child("AnimationPlayer", true, false) as AnimationPlayer
		clips = it.clips
		if ap:
			var talk: String = clips.get("talk", "")
			if ap.has_animation(talk):
				ap.play(talk)
				_talk_left = ap.get_animation(talk).length
			else:
				_play_idle()
		var h := VendorUI.head_top(body, Transform3D())
		var cam := Camera3D.new()
		cam.fov = 28
		var look := Vector3(0, h - 0.32, 0)
		var span := 0.8                          # head and shoulders
		var dist := span * 0.5 / tan(deg_to_rad(cam.fov * 0.5))
		vp.add_child(cam)
		cam.look_at_from_position(look + Vector3(0, 0.08, dist), look)

	# they greet you once, then stand at ease (the clips are the town keeper's, which loop)
	func _process(delta: float) -> void:
		if _talk_left > 0.0:
			_talk_left -= delta
			if _talk_left <= 0.0:
				_play_idle()

	func _play_idle() -> void:
		var idle: String = clips.get("idle", "")
		if ap and ap.has_animation(idle):
			ap.play(idle, 0.4)

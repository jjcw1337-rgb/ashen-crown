class_name IconRenderer
extends Node
## Renders 3D item models into textures for the inventory, belt and shops.

var vp: SubViewport
var cam: Camera3D
var holder: Node3D
var cache := {}
var queue: Array = []
var waiting := {}
var busy := false

func _ready() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("web") else Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -30, 0)
	key.light_energy = 1.6
	vp.add_child(key)
	var rimlight := DirectionalLight3D.new()
	rimlight.rotation_degrees = Vector3(-20, 150, 0)
	rimlight.light_energy = 1.0
	rimlight.light_color = Color(0.8, 0.85, 1.0)
	vp.add_child(rimlight)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(0, 0, 3)
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)

static func key_of(it: Dictionary) -> String:
	return "%s|%d|%s" % [it["base"], int(it.get("rarity", 0)), it.get("unique", "")]

func get_icon(it: Dictionary, cb: Callable) -> Texture2D:
	var k := key_of(it)
	if cache.has(k):
		return cache[k]
	if not waiting.has(k):
		waiting[k] = []
		queue.append(it)
	waiting[k].append(cb)
	return null

func _process(_d: float) -> void:
	if busy or queue.is_empty():
		return
	busy = true
	var it: Dictionary = queue.pop_front()
	await _render(it)
	busy = false

func _render(it: Dictionary) -> void:
	for c in holder.get_children():
		c.queue_free()
	var m := Models.item_model(it)
	holder.add_child(m)
	var slot: String = Data.BASES[it["base"]]["slot"]
	var size := 0.8
	m.rotation_degrees = Vector3.ZERO
	match slot:
		"weapon":
			var sh: Dictionary = Data.BASES[it["base"]].get("shape", {})
			var l: float = sh.get("len", sh.get("haft", 0.7)) + 0.2
			var dir := Vector3(0.62, 0.78, 0.0).normalized()
			m.basis = Basis.looking_at(dir, Vector3(0, 0, 1))
			m.position = -dir * l * 0.42
			size = l * 1.0
		"shield":
			m.rotation_degrees = Vector3(0, 200, 0)
			size = 0.95 if Data.BASES[it["base"]]["kind"] == "tower" else 0.75
			m.position = Vector3.ZERO
		"helm":
			m.rotation_degrees = Vector3(10, 200, 0)
			m.position = Vector3(0, -0.05, 0)
			size = 0.42
		"armor":
			m.rotation_degrees = Vector3(0, 200, 0)
			m.position = Vector3(0, -0.02, 0)
			size = 0.78
		"gloves", "boots":
			m.rotation_degrees = Vector3(25, 30, 0)
			m.position = Vector3(0, -0.08, 0)
			size = 0.42
		"belt":
			m.rotation_degrees = Vector3(35, 20, 0)
			size = 0.42
		"ring":
			m.rotation_degrees = Vector3(20, 30, 0)
			m.position = Vector3(0, -0.02, 0)
			size = 0.13
		"amulet":
			m.rotation_degrees = Vector3(0, 20, 0)
			m.position = Vector3(0, 0.03, 0)
			size = 0.3
		"potion":
			m.position = Vector3(0, -0.08, 0)
			size = 0.22
		"gold":
			m.rotation_degrees = Vector3(40, 0, 0)
			size = 0.22
	cam.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var k := key_of(it)
	var tex: Texture2D = null
	if img:
		tex = ImageTexture.create_from_image(img)
	cache[k] = tex
	for cb in waiting.get(k, []):
		if cb.is_valid():
			cb.call(tex)
	waiting.erase(k)

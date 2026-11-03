class_name FireFx
extends RefCounted
## Real fire for the whole game. Every fire (torches, campfires, bonfires, braziers, burning buildings and ground,
## magic, enchanted weapons, burning foes) is built here from flipbooks of simulated fire (Blender Mantaflow,
## tools/blender/fx/fire_flipbook.py; the pipeline is in the project doc "fire pipeline"), played on particles so
## no two flames are ever in step: each flame starts on its own frame, at its own speed, mirrored at random, and
## the two variants of a book interleave. Layers give it depth: wide dim back flames, the main flames, a hot core;
## then embers that detach and drift up, occasional sparks, smoke, heat haze over big fires (Forward+, High+), and a
## light that flickers with it (Game's "flicker" loop, meta "fire"), fading out with distance.
##
## `make(parent, pos, kind, size, col, light, shadow, smoke)`; Props.fire calls it, so every old call site gets it.
## Books: "body" (a full fire: campfires, bonfires, braziers), "tongue" (tall thin flames: torches, candles,
## weapons, burning foes), "spread" (low and wide: burning ground, buildings). A missing book falls back to
## "body", then to the procedural flame (InfernalFx's tongue shader).

const BOOKS := {
	"body": "res://assets/textures/fx/fire_body.png",
	"tongue": "res://assets/textures/fx/fire_tongue.png",
	"spread": "res://assets/textures/fx/fire_spread.png",
	"smoke": "res://assets/textures/fx/smoke_body.png",
	"spirit": "res://assets/textures/fx/fire_spirit.png",   # blue spirit-fire (FIRE_KIND=spirit), already coloured
}
const LEGACY_BOOK := "res://assets/textures/fx/fire_flipbook.png"
const GRID := Vector2(6, 6)          # frames per book unless GRIDS says otherwise
const GRIDS := {"body": Vector2(8, 8), "spirit": Vector2(8, 8)}   # these books hold 64 frames (spirit: 256 x 512 each)
const FPS := 30.0

## Each kind of fire: its book, how many flames per second (per metre of size), their life, how wide and tall a
## flame is (x size), the back layer, embers, sparks, smoke, the light (energy and range per metre) and haze.
const PRESETS := {
	"torch":    {"book": "tongue", "rate": 12.0, "life": 0.55, "w": 0.85, "h": 1.6, "back": 0.0, "core": 1.0, "embers": 6.0, "sparks": 0.0, "smoke": 0.4, "light": 1.8, "range": 6.5, "haze": false, "jitter": 0.12},
	"candle":   {"book": "tongue", "rate": 6.0, "life": 0.5, "w": 0.4, "h": 1.0, "back": 0.0, "core": 0.0, "embers": 0.0, "sparks": 0.0, "smoke": 0.0, "light": 0.9, "range": 3.0, "haze": false, "jitter": 0.05},
	"campfire": {"book": "body", "rate": 7.0, "life": 0.75, "w": 0.95, "h": 1.15, "back": 0.6, "core": 1.0, "embers": 10.0, "sparks": 0.25, "smoke": 1.0, "light": 2.4, "range": 7.5, "haze": true, "jitter": 0.18},
	"bonfire":  {"book": "body", "rate": 9.0, "life": 0.85, "w": 1.0, "h": 1.25, "back": 0.8, "core": 1.0, "embers": 16.0, "sparks": 0.4, "smoke": 1.3, "light": 2.8, "range": 8.0, "haze": true, "jitter": 0.22},
	"brazier":  {"book": "body", "rate": 7.0, "life": 0.6, "w": 0.85, "h": 1.0, "back": 0.4, "core": 1.0, "embers": 8.0, "sparks": 0.15, "smoke": 0.6, "light": 2.2, "range": 7.0, "haze": false, "jitter": 0.14},
	"building": {"book": "spread", "rate": 8.0, "life": 0.9, "w": 1.8, "h": 0.9, "back": 0.9, "core": 0.7, "embers": 14.0, "sparks": 0.3, "smoke": 1.6, "light": 2.6, "range": 9.0, "haze": true, "jitter": 0.3},
	"ground":   {"book": "spread", "rate": 7.0, "life": 0.7, "w": 1.5, "h": 0.75, "back": 0.5, "core": 0.6, "embers": 8.0, "sparks": 0.1, "smoke": 0.8, "light": 2.0, "range": 6.5, "haze": false, "jitter": 0.35},
	"magic":    {"book": "tongue", "rate": 12.0, "life": 0.5, "w": 0.95, "h": 1.6, "back": 0.3, "core": 1.0, "embers": 10.0, "sparks": 0.3, "smoke": 0.0, "light": 2.0, "range": 6.0, "haze": false, "jitter": 0.15},
	"weapon":   {"book": "tongue", "rate": 14.0, "life": 0.42, "w": 0.9, "h": 1.5, "back": 0.0, "core": 0.0, "embers": 8.0, "sparks": 0.0, "smoke": 0.0, "light": 0.0, "range": 0.0, "haze": false, "jitter": 0.1},
	# the camp waypoint's blue spirit-fire braziers: the spirit book plays as rendered (violet tips, electric blue,
	# a cyan-white heart), blue embers and sparks, a cold light, no soot
	# "anchored": a few long-lived flames standing in the bowl ("count", whatever the graphics tier), each playing a
	# long run of the simulation at full strength (brief "fades"), never wrapping past the book's end ("seamless"),
	# so the simulated tongues read whole instead of many short faded flames blurring into a cloud. Overlapping
	# light adds and the tonemapper bleaches what passes 1: no hot core layer, "hot" per flame and "cool" (the shader
	# keeps red and green low, and cuts each flame's faint haze) so they sum to blue with dark gaps between tongues.
	"spirit":   {"book": "spirit", "rate": 0.0, "life": 1.3, "w": 0.95, "h": 1.35, "back": 0.0, "core": 0.0, "embers": 14.0, "sparks": 0.2, "smoke": 0.0, "light": 2.0, "range": 6.5, "haze": false, "jitter": 0.035, "pal": "spirit", "hot": 0.6, "cool": 1.0,
		"anchored": true, "count": 3, "fades": Vector2(0.1, 0.86), "seamless": true},
	"burning":  {"book": "tongue", "rate": 12.0, "life": 0.5, "w": 1.1, "h": 1.7, "back": 0.3, "core": 0.0, "embers": 8.0, "sparks": 0.1, "smoke": 0.5, "light": 0.0, "range": 0.0, "haze": false, "jitter": 0.2},
}
## Flames per preset scale with the graphics budget (InfernalFx.tier: Low, Medium, High, Ultra).
const TIER_K := [0.5, 0.75, 1.0, 1.25]

static var _books := {}
static var _mats := {}

## Which kind an old call meant, from its size (Props.fire's callers that don't say).
static func guess(size: float, light: bool) -> String:
	if size >= 2.0:
		return "bonfire"
	if size >= 1.0:
		return "campfire" if light else "building"
	if size >= 0.55:
		return "brazier" if light else "torch"
	return "weapon" if not light else "torch"

static func grid_of(name: String) -> Vector2:
	if name != "body" and not ResourceLoader.exists(BOOKS.get(name, "")):
		return grid_of("body")        # a missing book plays the body book
	if name == "body" and not ResourceLoader.exists(BOOKS["body"]):
		return GRID                   # the legacy flipbook is 6 x 6
	return GRIDS.get(name, GRID)

static func book(name: String) -> Texture2D:
	if not _books.has(name):
		var t: Texture2D = null
		var p: String = BOOKS.get(name, "")
		if p != "" and ResourceLoader.exists(p):
			t = load(p)
		elif name != "body" and name != "smoke":
			t = book("body")
		elif name == "body" and ResourceLoader.exists(LEGACY_BOOK):
			t = load(LEGACY_BOOK)
		_books[name] = t
	return _books[name]

## A flame material for a book (shared per book and look, so fires batch). life = the particle's lifetime.
static func flame_mat(bk: String, life: float, hot: float, tint: float, cool := 0.0, fades := Vector2(0.12, 0.55), seamless := false) -> ShaderMaterial:
	var key := "%s_%.2f_%.2f_%.2f_%.2f_%.2f_%.2f_%s" % [bk, life, hot, tint, cool, fades.x, fades.y, seamless]
	if _mats.has(key):
		return _mats[key]
	var tex := book(bk)
	var m: ShaderMaterial
	if tex == null:
		m = InfernalFx.tongue_mat(life)
		m.set_shader_parameter("hot", hot)
	else:
		m = ShaderMaterial.new()
		m.shader = InfernalFx.shader("flipfire")
		m.set_shader_parameter("flip_tex", tex)
		m.set_shader_parameter("grid", grid_of(bk))
		m.set_shader_parameter("frames_per_life", FPS * life)
		m.set_shader_parameter("hot", hot)
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("cool", cool)
		m.set_shader_parameter("fade_in", fades.x)
		m.set_shader_parameter("fade_out", fades.y)
		m.set_shader_parameter("seamless", 1.0 if seamless else 0.0)
		m.set_shader_parameter("crimson", InfernalFx.CRIMSON)
		m.set_shader_parameter("molten", InfernalFx.MOLTEN)
		m.set_shader_parameter("whitehot", InfernalFx.WHITEHOT)
	_mats[key] = m
	return m

## How much a colour asks for hellfire (a red, dark colour) rather than natural fire: the shader's tint.
static func _tint_for(col: Color) -> float:
	return clampf((col.r - col.g * 1.6) * 0.9, 0.0, 0.7)

## Builds a fire. size is in the old Props.fire units (1 = a brazier's fire, about a metre tall).
static func make(parent: Node3D, pos: Vector3, kind := "", size := 1.0, col := Color(1.0, 0.55, 0.2), light := true, shadow := false, smoke := true) -> Node3D:
	if kind == "" or not PRESETS.has(kind):
		kind = guess(size, light)
	var P: Dictionary = PRESETS[kind]
	var root := Node3D.new()
	root.name = "Fire"
	root.position = pos
	parent.add_child(root)
	root.set_meta("fire_kind", kind)
	var ml := Engine.get_main_loop() as SceneTree
	var game = ml.root.get_node_or_null("Game") if ml != null else null
	var tr := InfernalFx.tier(game) if game != null else 2
	var k: float = TIER_K[tr]
	var bk: String = P["book"]
	var tint := _tint_for(col)
	var pal: String = P.get("pal", "")
	if pal == "spirit":
		tint = 0.0       # the spirit book is already blue: no pull toward hellfire
	var height: float = float(P["h"]) * size
	var width: float = float(P["w"]) * size
	var life: float = float(P["life"]) * (0.85 + 0.15 * size)
	# the back layer: bigger, dimmer, slower flames behind, so the fire has depth
	if float(P["back"]) > 0.0 and tr >= 1:
		_flames(root, "back", bk, life * 1.3, width * 1.35, height * 1.15, maxf(2.0, float(P["rate"]) * float(P["back"]) * 0.6 * size * k), 0.5 * float(P.get("hot", 1.0)), tint, float(P["jitter"]) * size * 1.4, size, float(P.get("cool", 0.0)))
	# the main flames
	var hot := float(P.get("hot", 1.0))
	if bool(P.get("anchored", false)):
		_anchored(root, bk, life, width, height, int(P.get("count", 3)), hot, tint, float(P["jitter"]) * size, float(P.get("cool", 0.0)), P.get("fades", Vector2(0.1, 0.86)), bool(P.get("seamless", true)))
	else:
		_flames(root, "flames", bk, life, width, height, maxf(3.0, float(P["rate"]) * size * k), hot, tint, float(P["jitter"]) * size, size, float(P.get("cool", 0.0)))
	# the hot core: small, bright, low
	if float(P["core"]) > 0.0:
		_flames(root, "core", bk, life * 0.6, width * 0.55, height * 0.5, maxf(2.0, float(P["rate"]) * 0.6 * size * k), 0.95 * float(P["core"]), tint, float(P["jitter"]) * size * 0.5, size, float(P.get("cool", 0.0)))
	if float(P["embers"]) > 0.0:
		_embers(root, height, maxi(2, int(float(P["embers"]) * size * k)), size, pal)
	if float(P["sparks"]) > 0.0 and tr >= 1:
		_sparks(root, height, float(P["sparks"]) * size * k, pal)
	if smoke and float(P["smoke"]) > 0.0 and tr >= 1:
		_smoke(root, height, float(P["smoke"]) * size * k, size)
	if bool(P["haze"]) and game != null and InfernalFx.haze_ok(game) and size >= 0.9:
		var hz := InfernalFx.glow(root, root.global_position + Vector3(0, height * 1.1, 0), height * 1.2, InfernalFx.haze_mat(0.012, true)) if root.is_inside_tree() else null
		if hz != null:
			hz.position = Vector3(0, height * 1.1, 0)
	if light and float(P["light"]) > 0.0:
		var l := OmniLight3D.new()
		l.name = "FireLight"
		l.light_color = col if pal == "spirit" else col.lerp(Color(1.0, 0.5, 0.18), 0.4)
		l.light_energy = float(P["light"]) * size
		l.omni_range = float(P["range"]) * size
		l.omni_attenuation = 1.3
		l.shadow_enabled = shadow
		if shadow:
			# omni shadows are six extra passes each: a shadow-casting fire joins the shadow budget (Grade.pick_shadows,
			# the nearest 1/2/4/6 lights by preset) instead of always casting, e.g. the fort's dozen cookfires
			l.add_to_group(Grade.SHADOW_GROUP)
		l.light_volumetric_fog_energy = 1.5
		l.distance_fade_enabled = true
		l.distance_fade_begin = 38.0
		l.distance_fade_length = 12.0
		l.position = Vector3(0, height * 0.45, 0)
		l.add_to_group("flicker")
		l.set_meta("base", l.light_energy)
		l.set_meta("fire", size)
		root.add_child(l)
	return root

## One layer of flames: flipbook particles standing on their spot, rising a little, nudged by turbulence.
static func _flames(root: Node3D, nm: String, bk: String, life: float, w: float, h: float, rate: float, hot: float, tint: float, jitter: float, size: float, cool := 0.0) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.center_offset = Vector3(0, h * 0.42, 0)
	# every particle is a whole flame and their light adds up: share the brightness out over how many overlap,
	# so a fire stays orange and yellow and never sums to white
	var n := maxi(2, int(rate * life))
	var share := clampf(1.45 / sqrt(float(n)), 0.22, 0.9)
	q.material = flame_mat(bk, snappedf(life, 0.05), snappedf(hot * share, 0.05), snappedf(tint, 0.1), cool)
	var p := InfernalFx.particles(root, root.global_position if root.is_inside_tree() else root.position, {
		"amount": n, "life": life, "one_shot": false, "randomness": 0.4,
		"shape": "sphere", "r": maxf(jitter, 0.01), "dir": Vector3.UP, "spread": 8.0,
		"vel": [size * 0.05, size * 0.35], "gravity": size * 0.6, "scale": [0.8, 1.15], "angle": true,
		"turb": size * 0.4, "mesh": q,
		"colors": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 1)]]})
	p.name = nm
	p.position = Vector3.ZERO
	p.preprocess = life

## A few long-lived flames standing still on their spot (no drift or turbulence: the simulation is the motion),
## emitted evenly so they take over from one another; each plays a long, unbroken run of the book.
static func _anchored(root: Node3D, bk: String, life: float, w: float, h: float, count: int, hot: float, tint: float, jitter: float, cool: float, fades: Vector2, seamless: bool) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.center_offset = Vector3(0, h * 0.42, 0)
	var share := clampf(1.45 / sqrt(float(maxi(count, 1))), 0.22, 0.9)
	q.material = flame_mat(bk, snappedf(life, 0.05), snappedf(hot * share, 0.05), snappedf(tint, 0.1), cool, fades, seamless)
	var p := InfernalFx.particles(root, root.global_position if root.is_inside_tree() else root.position, {
		"amount": maxi(1, count), "life": life, "one_shot": false, "randomness": 0.15,
		"shape": "sphere", "r": maxf(jitter, 0.005), "dir": Vector3.UP, "spread": 0.0,
		"vel": [0.0, 0.0], "gravity": 0.0, "scale": [0.9, 1.08], "angle": true, "mesh": q,
		"colors": [[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 1)]]})
	p.name = "flames"
	p.position = Vector3.ZERO
	p.local_coords = true          # they stand in the bowl even if it moves
	p.preprocess = life

## Embers that detach and drift up on the heat, wandering.
## Ember and spark colours by palette ("" = natural fire, "spirit" = the blue spirit-fire's sparkle).
const EMBER_COLS := {
	"": [[0.0, Color(1.0, 0.86, 0.62)], [0.25, Color(1.0, 0.55, 0.12)], [0.75, Color(0.9, 0.18, 0.03)], [1.0, Color(0.6, 0.05, 0.0, 0.0)]],
	"spirit": [[0.0, Color(0.85, 0.95, 1.0)], [0.25, Color(0.35, 0.65, 1.0)], [0.75, Color(0.25, 0.15, 0.95)], [1.0, Color(0.2, 0.05, 0.6, 0.0)]],
}
const SPARK_COLS := {
	"": [[0.0, Color(1.0, 0.95, 0.75)], [0.4, Color(1.0, 0.6, 0.15)], [1.0, Color(1.0, 0.25, 0.0, 0.0)]],
	"spirit": [[0.0, Color(0.9, 0.97, 1.0)], [0.4, Color(0.3, 0.6, 1.0)], [1.0, Color(0.3, 0.1, 0.9, 0.0)]],
}

static func _embers(root: Node3D, h: float, n: int, size: float, pal := "") -> void:
	var e := InfernalFx.particles(root, root.position, {"amount": n, "life": 2.0, "one_shot": false, "randomness": 0.7,
		"shape": "sphere", "r": 0.18 * size, "dir": Vector3.UP, "spread": 25.0, "vel": [0.6 * size + 0.3, 1.8 * size + 0.4],
		"gravity": 0.5, "damping": [0.3, 0.8], "scale": [0.4, 1.0], "size": clampf(0.04 * size, 0.02, 0.06), "turb": 1.4,
		"colors": EMBER_COLS.get(pal, EMBER_COLS[""])})
	e.name = "embers"
	e.position = Vector3(0, h * 0.35, 0)
	e.preprocess = 2.0

## Now and then a pop of sparks flying out.
static func _sparks(root: Node3D, h: float, k: float, pal := "") -> void:
	var s := InfernalFx.particles(root, root.position, {"amount": maxi(3, int(10 * k)), "life": 0.7, "one_shot": false,
		"explosive": 0.85, "randomness": 0.6, "shape": "sphere", "r": 0.1, "dir": Vector3.UP, "spread": 55.0,
		"vel": [2.0, 4.5], "gravity": -6.0, "scale": [0.3, 0.8], "size": 0.03,
		"colors": SPARK_COLS.get(pal, SPARK_COLS[""])})
	s.name = "sparks"
	s.position = Vector3(0, h * 0.3, 0)

## Smoke over the fire: dark, rising, spreading, lit from below while young; its density and drift vary.
static func _smoke(root: Node3D, h: float, k: float, size: float) -> void:
	var q := QuadMesh.new()
	var s := 0.9 * size + 0.3
	q.size = Vector2(s, s)
	q.material = InfernalFx.smoke_mat(0.6, 0.5)
	var sm := InfernalFx.particles(root, root.position, {"amount": maxi(3, int(6 * k) + 2), "life": 3.2, "one_shot": false,
		"randomness": 0.6, "shape": "sphere", "r": 0.15 * size, "dir": Vector3(0.12, 1.0, 0.05), "spread": 14.0,
		"vel": [0.4 + 0.3 * size, 0.9 + 0.5 * size], "gravity": 0.15, "damping": [0.1, 0.4], "scale": [0.7, 1.3],
		"grow": [0.5, 2.0], "angle": true, "spin": 20.0, "turb": 0.8, "mesh": q,
		"colors": [[0.0, Color(1, 1, 1, 0.0)], [0.2, Color(1, 1, 1, 0.55)], [0.6, Color(1, 1, 1, 0.3)], [1.0, Color(1, 1, 1, 0.0)]]})
	sm.name = "smoke"
	sm.position = Vector3(0, h * 0.85, 0)
	sm.preprocess = 3.0

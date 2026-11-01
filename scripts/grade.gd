class_name Grade
extends RefCounted
## Screen grading and the light budget for a zone's mood (Phase 1 of the Act I graphics plan).
##
## - `lut(look)`: a colour-grading LUT (Environment.adjustment_color_correction) built in code, split-toned:
##   the shadows pushed toward one colour, the highlights toward another, plus a gentle S-curve.
## - `LOOKS`: one entry per mood. Only Act I's forest camp has one so far; a zone without a look gets no LUT.
## - Shadow budget: lights in the group `SHADOW_GROUP` are candidates; every `PICK_EVERY` seconds the ones
##   nearest the hero (meta `shadow_pri` puts one first, e.g. the bonfire) get shadows, up to the preset's
##   `SHADOW_BUDGET`. Omni shadows are the expensive part, so the rest stay unshadowed.
## - Rim light: a cool light behind the hero (seen from the camera) that only lights the hero's own meshes
##   (its cull mask is `RIM_LAYER`, which `tag_hero` adds to every mesh under the hero), so he reads against
##   dark ground without a pool of light on the floor.

const SHADOW_GROUP := "shadow_light"
const SHADOW_BUDGET := [1, 2, 4, 6]   # Low, Medium, High, Ultra
const PICK_EVERY := 0.4
const RIM_LAYER := 1 << 19            # render layer 20: only the hero's meshes carry it

const LOOKS := {
	# Act I's camp at dusk under the canopy: teal-blue shadows, warm firelit highlights, a little crushed black
	"forest_camp": {"shadow": Color(0.0, 0.05, 0.07), "high": Color(0.07, 0.03, -0.03), "curve": 0.12, "lift": 0.012,
		"sat": 0.97, "vignette": 0.55, "grain": 0.03,
		"rim": {"color": Color(0.55, 0.72, 1.0), "energy": 2.2, "range": 4.5}},
}

static var _luts := {}

static func look(name: String) -> Dictionary:
	return LOOKS.get(name, {})

## A 3D LUT (size³ texels) for the look. Cached per look.
static func lut(name: String, size := 24) -> Texture3D:
	if _luts.has(name):
		return _luts[name]
	var lk: Dictionary = LOOKS[name]
	var sh: Color = lk["shadow"]
	var hi: Color = lk["high"]
	var curve: float = lk["curve"]
	var lift: float = lk["lift"]
	var sat: float = lk["sat"]
	var layers: Array[Image] = []
	for b in size:
		var img := Image.create(size, size, false, Image.FORMAT_RGB8)
		for g in size:
			for r in size:
				var c := Vector3(float(r), float(g), float(b)) / float(size - 1)
				var l := c.dot(Vector3(0.2126, 0.7152, 0.0722))
				# split tone: shadows toward `shadow`, highlights toward `high`
				var ws := pow(1.0 - l, 2.0)
				var wh := l * l
				c += Vector3(sh.r, sh.g, sh.b) * ws + Vector3(hi.r, hi.g, hi.b) * wh
				# saturation about the luminance
				c = Vector3(l, l, l).lerp(c, sat)
				# S-curve (smoothstep blend) and a small lift/crush of the blacks
				var s := Vector3(_scurve(c.x), _scurve(c.y), _scurve(c.z))
				c = c.lerp(s, curve) + Vector3(lift, lift, lift)
				img.set_pixel(r, g, Color(clampf(c.x, 0.0, 1.0), clampf(c.y, 0.0, 1.0), clampf(c.z, 0.0, 1.0)))
		layers.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, size, size, size, false, layers)
	_luts[name] = tex
	return tex

static func _scurve(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Shadows for the lights nearest `at`, within the preset's budget; returns how many are shadowed.
static func pick_shadows(tree: SceneTree, at: Vector3, quality: int) -> int:
	var lights := tree.get_nodes_in_group(SHADOW_GROUP)
	if lights.is_empty():
		return 0
	var ranked := []
	for n in lights:
		var l := n as Light3D
		if l == null or not l.is_inside_tree() or not l.is_visible_in_tree():
			continue
		var d := l.global_position.distance_to(at)
		if l.has_meta("shadow_pri"):
			d -= 1000.0
		ranked.append([d, l])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var budget: int = SHADOW_BUDGET[clampi(quality, 0, SHADOW_BUDGET.size() - 1)]
	var on := 0
	for i in ranked.size():
		var l: Light3D = ranked[i][1]
		var want := i < budget
		if l.shadow_enabled != want:
			l.shadow_enabled = want
		if want:
			on += 1
	return on

## Adds the rim layer to every mesh under `root` (the hero), keeping their other layers.
static func tag_hero(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n
		if gi.layers & RIM_LAYER == 0:
			gi.layers |= RIM_LAYER

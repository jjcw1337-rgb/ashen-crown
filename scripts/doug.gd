class_name Doug
extends RefCounted
## Doug (docs/characters/doug.md; Blaine's tier-1 character and the pilot of the character workflow): the stubby
## circus brawler. His body is the Meshy clown (concept from Blaine's reference, image-to-3D, Meshy auto-rig and
## library clips merged by tools/blender/doug/prep_doug_mocap.py into assets/models/doug.glb) on the knight's mocap
## system, like the ranger and the plague doctor; without the glb, the knight's procedural body. His skills are
## doug_skills.gd (DougSkills), their effects doug_fx.gd (DougFx); his props are Meshy pieces in assets/models/doug/.

const GLB := "res://assets/models/doug.glb"
const PROP_DIR := "res://assets/models/doug/%s.glb"
const ACCENT := Color(1.0, 0.82, 0.2)          # his colour: the suit's mustard yellow
const HEIGHT := 1.25

## Whole-body clips per attack style (Knight.build_mocap "acts"): style -> clip, and the attack's progress mapped to
## the clip's time (fractions of the clip, "frac": true), so each blow and each skill lands on its impact frame.
const ACTS := {
	# the drumstick combo: smack, backhand, belly-bump
	"swipe1": {"clip": "smack", "frac": true, "keys": [[0.0, 0.1], [0.42, 0.45], [1.0, 0.8]]},
	"swipe2": {"clip": "backhand", "frac": true, "keys": [[0.0, 0.1], [0.45, 0.5], [1.0, 0.85]]},
	"swipe3": {"clip": "belly_bump", "frac": true, "keys": [[0.0, 0.25], [0.5, 0.7], [1.0, 1.0]]},
	"over": {"clip": "smack", "frac": true, "keys": [[0.0, 0.1], [0.5, 0.45], [1.0, 0.8]]},
	"back": {"clip": "backhand", "frac": true, "keys": [[0.0, 0.1], [0.5, 0.5], [1.0, 0.85]]},
	"thrust": {"clip": "belly_bump", "frac": true, "keys": [[0.0, 0.25], [0.52, 0.7], [1.0, 1.0]]},
	"chop": {"clip": "belly_bump", "frac": true, "keys": [[0.0, 0.25], [0.55, 0.7], [1.0, 1.0]]},
	# the skills
	"pie": {"clip": "throw_pie", "frac": true, "keys": [[0.0, 0.2], [0.5, 0.55], [1.0, 0.9]]},
	"peels": {"clip": "throw_peels", "frac": true, "keys": [[0.0, 0.25], [0.55, 0.6], [1.0, 0.95]]},
	"slide": {"clip": "slide", "frac": true, "keys": [[0.0, 0.05], [0.2, 0.25], [1.0, 0.95]]},
	"doppel": {"clip": "doppel", "frac": true, "keys": [[0.0, 0.1], [0.5, 0.5], [1.0, 0.95]]},
	"juggle": {"clip": "cheer", "frac": true, "keys": [[0.0, 0.0], [1.0, 1.0]]},
	"bounce": {"clip": "bounce", "frac": true, "keys": [[0.0, 0.15], [0.78, 0.8], [1.0, 1.0]]},
	"car": {"clip": "taunt", "frac": true, "keys": [[0.0, 0.0], [1.0, 1.0]]},
}

## His skills' attack styles (no weapon trail on a throw or a trick; partners see the style, not the skill)
const SKILL_STYLES := ["pie", "peels", "slide", "doppel", "juggle", "bounce", "car"]

static var _props := {}

static func model_ok() -> bool:
	return ResourceLoader.exists(GLB)

static func prop(name: String) -> Node3D:
	if not _props.has(name):
		var path := PROP_DIR % name
		_props[name] = load(path) if ResourceLoader.exists(path) else null
	var ps: PackedScene = _props[name]
	return ps.instantiate() if ps else null

static func build_body() -> Node3D:
	if not model_ok():
		var k := Knight.build(Knight.default_gear())
		k.set_meta("doug", true)
		k.scale = Vector3.ONE * 0.75
		return k
	var r := Knight.build_mocap(GLB, {
		"relaxed": ["idle", 0.0, "walk", 0.5, "run", 3.6, "run_fast", 5.6],
		"combat": ["combat_idle", 0.0, "walk", 0.5, "run", 3.6, "run_fast", 5.6],
		"acts": ACTS, "meta": "doug"})
	r.set_meta("doug", true)
	r.set_meta("stride", 1.25)          # short legs: quick steps
	r.remove_meta("knight")
	return r

## The roast drumstick he fights with (a Meshy prop; held like a club).
static func drumstick_model() -> Node3D:
	var root := Node3D.new()
	var m := prop("drumstick")
	if m != null:
		m.rotation_degrees = Vector3(90, 0, 0)
		root.add_child(m)
		return root
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.sph(0.09, 10)
	mi.scale = Vector3(1.0, 1.0, 1.8)
	mi.position = Vector3(0, 0, -0.2)
	mi.material_override = Mats.mat(Color(0.55, 0.3, 0.1), 0.6, 0.0)
	root.add_child(mi)
	return root

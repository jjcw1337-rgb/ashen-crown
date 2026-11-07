class_name NecromancerBody
extends RefCounted
## The Necromancer's body: the Meshy lich-priest (concept take 2, its edits to empty hands and no mist; image-to-3D,
## Meshy's auto-rig, 17 library clips merged onto it in Blender by build/prep_necromancer_mocap.py), played by the
## knight's mocap player (Knight.build_mocap), like Doug's and the Plague Doctor's. His scythe-staff is its own prop
## (weapon/grave_scythe.glb), held in the right hand.

const GLB := "res://game/heroes/necromancer/body/necromancer.glb"
const STAFF := "res://game/heroes/necromancer/weapon/grave_scythe.glb"
## the staff in the hand: held a third of the way up, upright (weapon/grave_scythe.glb stands 1.9 m, base at 0)
const STAFF_AT := Vector3(0, -0.62, 0)
const STAFF_TURN := Vector3(0, 0, 0)

## His moves (Hero's attack styles -> his clips): the staff's three blows are his spell casts' thrusts; Bone Bolt the
## quick flung hand; Graveyard the staff driven into the ground; any other cast the gathered one.
const ACTS := {
	"swipe1": {"clip": "cast", "frac": true, "keys": [[0.0, 0.12], [0.4, 0.45], [1.0, 0.8]]},
	"swipe2": {"clip": "cast_sweep", "frac": true, "keys": [[0.0, 0.12], [0.42, 0.45], [1.0, 0.8]]},
	"swipe3": {"clip": "cast_hard", "frac": true, "keys": [[0.0, 0.15], [0.47, 0.5], [1.0, 0.85]]},
	"over": {"clip": "cast", "frac": true, "keys": [[0.0, 0.12], [0.5, 0.45], [1.0, 0.8]]},
	"back": {"clip": "cast_sweep", "frac": true, "keys": [[0.0, 0.12], [0.48, 0.45], [1.0, 0.8]]},
	"thrust": {"clip": "cast_hard", "frac": true, "keys": [[0.0, 0.15], [0.52, 0.5], [1.0, 0.85]]},
	"chop": {"clip": "cast_hard", "frac": true, "keys": [[0.0, 0.15], [0.55, 0.5], [1.0, 0.85]]},
	"cast": {"clip": "cast_charged", "frac": true, "keys": [[0.0, 0.1], [0.5, 0.5], [1.0, 0.85]]},
	"bone_bolt": {"clip": "cast_quick", "frac": true, "keys": [[0.0, 0.15], [0.45, 0.45], [1.0, 0.8]]},
	"grave_slam": {"clip": "slam", "frac": true, "keys": [[0.0, 0.05], [0.55, 0.6], [1.0, 0.95]]},
}

static func model_ok() -> bool:
	return ResourceLoader.exists(GLB)

static func build() -> Node3D:
	if not model_ok():
		var k := Knight.build(Knight.default_gear())
		k.set_meta("necromancer", true)
		return k
	var r := Knight.build_mocap(GLB, {
		"relaxed": ["idle", 0.0, "walk", 0.5, "run", 3.6, "run_fast", 5.6],
		"combat": ["combat_idle", 0.0, "walk_fight", 0.5, "run", 3.6, "run_fast", 5.6],
		"acts": ACTS, "meta": "necromancer"})
	r.set_meta("necromancer", true)
	r.remove_meta("knight")
	return r

## His scythe-staff, as Models.item_model hands it to the grip (or a plain black staff without the file).
static func staff_model() -> Node3D:
	var root := Node3D.new()
	var m := ResCache.inst(STAFF) as Node3D if ResourceLoader.exists(STAFF) else null
	if m == null:
		var mi := MeshInstance3D.new()
		mi.mesh = Geo.cyl(0.018, 0.022, 1.9, 8)
		mi.position = Vector3(0, 0.95, 0)
		mi.material_override = Mats.mat(Color(0.08, 0.07, 0.07), 0.6, 0.0)
		m = mi
	root.add_child(m)
	m.position = STAFF_AT
	m.rotation_degrees = STAFF_TURN
	return root

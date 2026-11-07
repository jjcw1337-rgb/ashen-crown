class_name MeshyMonster
## Act I monsters made with Meshy (a concept image, then image-to-3D), decimated and rigged in Blender by
## tools/blender/act1/rig_monster.py, which measures each model's joints; layout_to_gd.py writes them
## here. They stay in their A-pose: MeshyRig.build's aim turns each arm's rest down the limb so
## the shared animation (Anim.pose) hangs them naturally. A monster in Data.ENEMIES with "mesh" uses
## its model when the glb is there (and its old procedural body otherwise). Each model's rig lives on its monster's card
## (game/monsters/<monster>/monster.gd RIGS); this builds a body from one.

const AIM := {"sh_r": "el_r", "el_r": "hand_r", "hand_r": "=el_r", "sh_l": "el_l", "el_l": "hand_l", "hand_l": "=el_l"}
## A human-sized monster (look height 1.0) stands this tall, like the knight.
const HUMAN := 1.8

## A rig's model is on disk. rig: {"glb", "height" (the model's own), "layout" (joints in Godot axes, model space:
## feet on y = 0, facing -z)}, from the monster's card (game/monsters/<monster>/monster.gd RIGS).
static func ok(rig: Dictionary) -> bool:
	return ResourceLoader.exists(str(rig.get("glb", "")))

## kind: its key (the def's "mesh"), for its cached meshes.
static func build(kind: String, m: Dictionary, look: Dictionary) -> Node3D:
	var root := MeshyRig.build(m["layout"], m["glb"], "monster_" + kind, AIM)
	var J: Dictionary = root.get_meta("j")
	var mh: float = m["height"]
	# grips and mounts in the model's units, sized to its hands
	var g := mh / HUMAN
	J["grip_r"] = Models.N(J["hand_r"], "grip_r", Vector3(0, -0.07 * g, -0.005), Vector3(-28, 0, 0))
	J["grip_l"] = Models.N(J["hand_l"], "grip_l", Vector3(0, -0.07 * g, 0))
	J["mount_l"] = Models.N(J["el_l"], "mount_l", Vector3(-0.075 * g, -0.14 * g, 0), Vector3(0, 70, 0))
	# a run of its own (Anim's Fallen gaits) and its stride: shorter legs step quicker
	if look.has("gait"):
		root.set_meta("gait", look["gait"])
	if look.has("stride"):
		root.set_meta("stride", look["stride"])
	var target: float = float(look.get("height", 1.0)) * HUMAN
	var s := target / mh
	for k in ["grip_r", "grip_l", "mount_l"]:
		(J[k] as Node3D).scale = Vector3.ONE / s * float(look.get("height", 1.0))
	match str(look.get("weapon", "")):
		"":
			pass
		"bow":
			var lb := SkeletonModel.longbow(SkeletonModel.VARIANTS["archer"])
			(J["grip_l"] as Node3D).add_child(lb)
			J["bow_l"] = lb
		_:
			var w := Models.enemy_weapon(look["weapon"])
			(J["grip_r"] as Node3D).add_child(w)
			J["weapon"] = w
	root.scale = Vector3.ONE * s
	root.set_meta("h", g)
	root.set_meta("meshy_monster", kind)
	return root

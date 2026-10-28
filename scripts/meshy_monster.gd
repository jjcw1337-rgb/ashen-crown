class_name MeshyMonster
## Act I monsters made with Meshy (a concept image, then image-to-3D), decimated and rigged in Blender by
## tools/blender/act1/rig_monster.py, which measures each model's joints; layout_to_gd.py writes them
## here. They stay in their A-pose: Goblin.imported_rig's aim turns each arm's rest down the limb so
## the shared animation (Anim.pose) hangs them naturally. A monster in Data.ENEMIES with "mesh" uses
## its model when the glb is there (and its old procedural body otherwise).

## Joints in Godot axes, model space (feet on y = 0, facing -z); height is the model's own.
const MODELS := {
	# monster models begin
	"fallen": {"glb": "res://assets/models/monsters/fallen.glb", "height": 1.1, "layout": {"hips": ["", Vector3(0.0, 0.3191, -0.0193)], "torso": ["hips", Vector3(0.0, 0.3851, -0.0193)], "head": ["torso", Vector3(0.0, 0.8472, -0.0266)], "sh_r": ["torso", Vector3(0.0689, 0.7482, -0.0127)], "el_r": ["sh_r", Vector3(0.193, 0.6116, -0.0358)], "hand_r": ["el_r", Vector3(0.3075, 0.4856, -0.0572)], "sh_l": ["torso", Vector3(-0.0689, 0.7482, -0.0272)], "el_l": ["sh_l", Vector3(-0.1933, 0.6141, -0.0434)], "hand_l": ["el_l", Vector3(-0.308, 0.4903, -0.0584)], "leg_r": ["hips", Vector3(0.0753, 0.3191, 0.0057)], "knee_r": ["leg_r", Vector3(0.098, 0.1651, 0.0297)], "leg_l": ["hips", Vector3(-0.0644, 0.3191, 0.0023)], "knee_l": ["leg_l", Vector3(-0.0852, 0.1691, 0.0239)]}},
	"zombie": {"glb": "res://assets/models/monsters/zombie.glb", "height": 1.749, "layout": {"hips": ["", Vector3(0.0, 0.6559, -0.0259)], "torso": ["hips", Vector3(0.0, 0.7608, -0.0259)], "head": ["torso", Vector3(0.0, 1.5129, 0.1218)], "sh_r": ["torso", Vector3(0.1438, 1.3555, 0.1099)], "el_r": ["sh_r", Vector3(0.3111, 1.1491, 0.0486)], "hand_r": ["el_r", Vector3(0.4655, 0.9587, -0.0079)], "sh_l": ["torso", Vector3(-0.1438, 1.3555, -0.0145)], "el_l": ["sh_l", Vector3(-0.3074, 1.15, -0.0255)], "hand_l": ["el_l", Vector3(-0.4584, 0.9603, -0.0357)], "leg_r": ["hips", Vector3(0.102, 0.6559, -0.0311)], "knee_r": ["leg_r", Vector3(0.147, 0.3475, 0.0745)], "leg_l": ["hips", Vector3(-0.0875, 0.6559, -0.0454)], "knee_l": ["leg_l", Vector3(-0.1473, 0.3463, 0.0155)]}},
	"archer": {"glb": "res://assets/models/monsters/archer.glb", "height": 1.801, "layout": {"hips": ["", Vector3(0.0, 0.5762, -0.0498)], "torso": ["hips", Vector3(0.0, 0.6843, -0.0498)], "head": ["torso", Vector3(0.0, 1.542, 0.0)], "sh_r": ["torso", Vector3(0.16, 1.38, -0.0272)], "el_r": ["sh_r", Vector3(0.3479, 1.1941, -0.043)], "hand_r": ["el_r", Vector3(0.5214, 1.0225, -0.0575)], "sh_l": ["torso", Vector3(-0.16, 1.38, -0.0313)], "el_l": ["sh_l", Vector3(-0.3472, 1.189, -0.0437)], "hand_l": ["el_l", Vector3(-0.52, 1.0128, -0.0552)], "leg_r": ["hips", Vector3(0.09, 0.5762, -0.0436)], "knee_r": ["leg_r", Vector3(0.1175, 0.293, -0.011)], "leg_l": ["hips", Vector3(-0.0944, 0.5762, -0.0334)], "knee_l": ["leg_l", Vector3(-0.1801, 0.3054, 0.0)]}},
	"goblin_guard": {"glb": "res://assets/models/monsters/goblin_guard.glb", "height": 1.0, "layout": {"hips": ["", Vector3(0.0, 0.2499, 0.0291)], "torso": ["hips", Vector3(0.0, 0.3099, 0.0291)], "head": ["torso", Vector3(0.0, 0.72, 0.0316)], "sh_r": ["torso", Vector3(0.125, 0.63, 0.009)], "el_r": ["sh_r", Vector3(0.2766, 0.4952, 0.0108)], "hand_r": ["el_r", Vector3(0.4166, 0.3708, 0.0125)], "sh_l": ["torso", Vector3(-0.125, 0.63, 0.0563)], "el_l": ["sh_l", Vector3(-0.2854, 0.5772, 0.0334)], "hand_l": ["el_l", Vector3(-0.4335, 0.5285, 0.0124)], "leg_r": ["hips", Vector3(0.0795, 0.2499, -0.0322)], "knee_r": ["leg_r", Vector3(0.173, 0.1343, 0.0472)], "leg_l": ["hips", Vector3(-0.05, 0.2499, 0.0091)], "knee_l": ["leg_l", Vector3(-0.0781, 0.1322, 0.0468)]}},
	# monster models end
}
const AIM := {"sh_r": "el_r", "el_r": "hand_r", "hand_r": "=el_r", "sh_l": "el_l", "el_l": "hand_l", "hand_l": "=el_l"}
## A human-sized monster (look height 1.0) stands this tall, like the knight.
const HUMAN := 1.8

static func ok(kind: String) -> bool:
	return MODELS.has(kind) and ResourceLoader.exists(MODELS[kind]["glb"])

static func build(kind: String, look: Dictionary) -> Node3D:
	var m: Dictionary = MODELS[kind]
	var root := Goblin.imported_rig(m["layout"], m["glb"], "monster_" + kind, AIM)
	var J: Dictionary = root.get_meta("j")
	var mh: float = m["height"]
	# grips and mounts in the model's units, sized to its hands
	var g := mh / HUMAN
	J["grip_r"] = Models.N(J["hand_r"], "grip_r", Vector3(0, -0.07 * g, -0.005), Vector3(-28, 0, 0))
	J["grip_l"] = Models.N(J["hand_l"], "grip_l", Vector3(0, -0.07 * g, 0))
	J["mount_l"] = Models.N(J["el_l"], "mount_l", Vector3(-0.075 * g, -0.14 * g, 0), Vector3(0, 70, 0))
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

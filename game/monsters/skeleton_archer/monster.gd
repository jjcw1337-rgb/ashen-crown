extends RefCounted
## The Bone Archer: its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["skel_archer"]
## How its body carries itself (Anim's personalities).
const PERSONALITY := "skeleton"

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"archer": {"glb": "res://game/monsters/skeleton_archer/archer.glb", "height": 1.801, "layout": {"hips": ["", Vector3(0.0, 0.5762, -0.0498)], "torso": ["hips", Vector3(0.0, 0.6843, -0.0498)], "head": ["torso", Vector3(0.0, 1.542, 0.0)], "sh_r": ["torso", Vector3(0.16, 1.38, -0.0272)], "el_r": ["sh_r", Vector3(0.3479, 1.1941, -0.043)], "hand_r": ["el_r", Vector3(0.5214, 1.0225, -0.0575)], "sh_l": ["torso", Vector3(-0.16, 1.38, -0.0313)], "el_l": ["sh_l", Vector3(-0.3472, 1.189, -0.0437)], "hand_l": ["el_l", Vector3(-0.52, 1.0128, -0.0552)], "leg_r": ["hips", Vector3(0.09, 0.5762, -0.0436)], "knee_r": ["leg_r", Vector3(0.1175, 0.293, -0.011)], "leg_l": ["hips", Vector3(-0.0944, 0.5762, -0.0334)], "knee_l": ["leg_l", Vector3(-0.1801, 0.3054, 0.0)]}},
	# rigs end
}

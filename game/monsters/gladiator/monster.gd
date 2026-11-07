extends RefCounted
## The Gladiator (the Arena): its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["gladiator"]

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"gladiator": {"glb": "res://game/monsters/gladiator/gladiator.glb", "height": 1.85, "layout": {"hips": ["", Vector3(0.0, 0.925, -0.1039)], "torso": ["hips", Vector3(0.0, 1.036, -0.1039)], "head": ["torso", Vector3(0.0, 1.554, -0.0353)], "sh_r": ["torso", Vector3(0.175, 1.3875, 0.1073)], "el_r": ["sh_r", Vector3(0.3175, 1.1975, 0.0277)], "hand_r": ["el_r", Vector3(0.4491, 1.0221, -0.0458)], "sh_l": ["torso", Vector3(-0.175, 1.3875, -0.0324)], "el_l": ["sh_l", Vector3(-0.3225, 1.1873, -0.0571)], "hand_l": ["el_l", Vector3(-0.4587, 1.0025, -0.0799)], "leg_r": ["hips", Vector3(0.0925, 0.925, -0.0127)], "knee_r": ["leg_r", Vector3(0.1283, 0.4912, -0.0084)], "leg_l": ["hips", Vector3(-0.0925, 0.925, -0.0752)], "knee_l": ["leg_l", Vector3(-0.144, 0.4882, 0.0026)]}},
	# rigs end
}

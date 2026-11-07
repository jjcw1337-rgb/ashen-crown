extends RefCounted
## The Zombie: its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["zombie"]
## How its body carries itself (Anim's personalities).
const PERSONALITY := "zombie"

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"zombie": {"glb": "res://game/monsters/zombie/zombie.glb", "height": 1.749, "layout": {"hips": ["", Vector3(0.0, 0.6559, -0.0259)], "torso": ["hips", Vector3(0.0, 0.7608, -0.0259)], "head": ["torso", Vector3(0.0, 1.5129, 0.1218)], "sh_r": ["torso", Vector3(0.1438, 1.3555, 0.1099)], "el_r": ["sh_r", Vector3(0.3111, 1.1491, 0.0486)], "hand_r": ["el_r", Vector3(0.4655, 0.9587, -0.0079)], "sh_l": ["torso", Vector3(-0.1438, 1.3555, -0.0145)], "el_l": ["sh_l", Vector3(-0.3074, 1.15, -0.0255)], "hand_l": ["el_l", Vector3(-0.4584, 0.9603, -0.0357)], "leg_r": ["hips", Vector3(0.102, 0.6559, -0.0311)], "knee_r": ["leg_r", Vector3(0.147, 0.3475, 0.0745)], "leg_l": ["hips", Vector3(-0.0875, 0.6559, -0.0454)], "knee_l": ["leg_l", Vector3(-0.1473, 0.3463, 0.0155)]}},
	# rigs end
}

extends RefCounted
## The Goblin Guard: its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["goblin_guard"]
## How its body carries itself (Anim's personalities).
const PERSONALITY := "goblin"

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"goblin_guard": {"glb": "res://game/monsters/goblin_guard/goblin_guard.glb", "height": 1.0, "layout": {"hips": ["", Vector3(0.0, 0.2499, 0.0291)], "torso": ["hips", Vector3(0.0, 0.3099, 0.0291)], "head": ["torso", Vector3(0.0, 0.72, 0.0316)], "sh_r": ["torso", Vector3(0.125, 0.63, 0.009)], "el_r": ["sh_r", Vector3(0.2766, 0.4952, 0.0108)], "hand_r": ["el_r", Vector3(0.4166, 0.3708, 0.0125)], "sh_l": ["torso", Vector3(-0.125, 0.63, 0.0563)], "el_l": ["sh_l", Vector3(-0.2854, 0.5772, 0.0334)], "hand_l": ["el_l", Vector3(-0.4335, 0.5285, 0.0124)], "leg_r": ["hips", Vector3(0.0795, 0.2499, -0.0322)], "knee_r": ["leg_r", Vector3(0.173, 0.1343, 0.0472)], "leg_l": ["hips", Vector3(-0.05, 0.2499, 0.0091)], "knee_l": ["leg_l", Vector3(-0.0781, 0.1322, 0.0468)]}},
	# rigs end
}

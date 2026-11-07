extends RefCounted
## The Champion (the Arena's boss): its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["champion"]

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"champion": {"glb": "res://game/monsters/champion/champion.glb", "height": 1.9, "layout": {"hips": ["", Vector3(0.0, 0.9025, -0.0457)], "torso": ["hips", Vector3(0.0, 1.0165, -0.0457)], "head": ["torso", Vector3(0.0, 1.526, -0.0335)], "sh_r": ["torso", Vector3(0.2, 1.355, -0.0242)], "el_r": ["sh_r", Vector3(0.3476, 1.1359, -0.0549)], "hand_r": ["el_r", Vector3(0.4839, 0.9336, -0.0833)], "sh_l": ["torso", Vector3(-0.2, 1.355, -0.0528)], "el_l": ["sh_l", Vector3(-0.3472, 1.135, -0.0722)], "hand_l": ["el_l", Vector3(-0.483, 0.9319, -0.0902)], "leg_r": ["hips", Vector3(0.095, 0.9025, 0.015)], "knee_r": ["leg_r", Vector3(0.1859, 0.4772, -0.04)], "leg_l": ["hips", Vector3(-0.0994, 0.9025, -0.0164)], "knee_l": ["leg_l", Vector3(-0.18, 0.4842, -0.0399)]}},
	# rigs end
}

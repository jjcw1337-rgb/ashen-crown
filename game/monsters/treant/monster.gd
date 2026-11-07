extends RefCounted
## The Treant: its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["treant"]

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"treant": {"glb": "res://game/monsters/treant/treant.glb", "height": 2.8, "layout": {"hips": ["", Vector3(0.0, 1.218, 0.2098)], "torso": ["hips", Vector3(0.0, 1.386, 0.2098)], "head": ["torso", Vector3(0.0, 1.708, -0.4133)], "sh_r": ["torso", Vector3(0.5333, 1.456, 0.1551)], "el_r": ["sh_r", Vector3(0.881, 1.3168, 0.2782)], "hand_r": ["el_r", Vector3(1.202, 1.1884, 0.3918)], "sh_l": ["torso", Vector3(-0.5333, 1.456, 0.1228)], "el_l": ["sh_l", Vector3(-0.8845, 1.3349, 0.2596)], "hand_l": ["el_l", Vector3(-1.2087, 1.2231, 0.3857)], "leg_r": ["hips", Vector3(0.2177, 1.218, 0.0519)], "knee_r": ["leg_r", Vector3(0.4084, 0.6483, 0.0649)], "leg_l": ["hips", Vector3(-0.1619, 1.218, 0.0272)], "knee_l": ["leg_l", Vector3(-0.3198, 0.6461, 0.0555)]}},
	# rigs end
}

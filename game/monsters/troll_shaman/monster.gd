extends RefCounted
## The Troll Beast-Tamer: its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["troll_shaman"]

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"troll_shaman": {"glb": "res://game/monsters/troll_shaman/troll_shaman.glb", "height": 2.3, "layout": {"hips": ["", Vector3(0.0, 0.5405, 0.0887)], "torso": ["hips", Vector3(0.0, 0.6785, 0.0887)], "head": ["torso", Vector3(0.0, 1.817, -0.0509)], "sh_r": ["torso", Vector3(0.1082, 1.61, -0.074)], "el_r": ["sh_r", Vector3(0.378, 1.3927, -0.1044)], "hand_r": ["el_r", Vector3(0.6271, 1.1921, -0.1325)], "sh_l": ["torso", Vector3(-0.1082, 1.61, -0.0861)], "el_l": ["sh_l", Vector3(-0.3759, 1.395, -0.1165)], "hand_l": ["el_l", Vector3(-0.6229, 1.1966, -0.1445)], "leg_r": ["hips", Vector3(0.1333, 0.5405, 0.1082)], "knee_r": ["leg_r", Vector3(0.1795, 0.2943, 0.0967)], "leg_l": ["hips", Vector3(-0.1222, 0.5405, 0.0721)], "knee_l": ["leg_l", Vector3(-0.1753, 0.2877, 0.0837)]}},
	# rigs end
}

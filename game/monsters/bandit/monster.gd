extends RefCounted
## The Bandits (blade and bow): its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["bandit", "bandit_archer"]

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"bandit": {"glb": "res://game/monsters/bandit/bandit.glb", "height": 1.8, "layout": {"hips": ["", Vector3(0.0, 0.567, 0.0603)], "torso": ["hips", Vector3(0.0, 0.675, 0.0603)], "head": ["torso", Vector3(0.0, 1.575, -0.0609)], "sh_r": ["torso", Vector3(0.1962, 1.413, -0.0821)], "el_r": ["sh_r", Vector3(0.3192, 1.1941, -0.0979)], "hand_r": ["el_r", Vector3(0.4328, 0.9921, -0.1126)], "sh_l": ["torso", Vector3(-0.1962, 1.413, -0.0435)], "el_l": ["sh_l", Vector3(-0.3148, 1.1959, -0.0727)], "hand_l": ["el_l", Vector3(-0.4242, 0.9954, -0.0997)], "leg_r": ["hips", Vector3(0.1379, 0.567, 0.0007)], "knee_r": ["leg_r", Vector3(0.1977, 0.3017, -0.0051)], "leg_l": ["hips", Vector3(-0.118, 0.567, -0.0109)], "knee_l": ["leg_l", Vector3(-0.1595, 0.3012, 0.0044)]}},
	# rigs end
}

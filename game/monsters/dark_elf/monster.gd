extends RefCounted
## The Dark Elves (blade and bow): its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["dark_elf", "dark_elf_archer"]

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"dark_elf": {"glb": "res://game/monsters/dark_elf/dark_elf.glb", "height": 1.85, "layout": {"hips": ["", Vector3(0.0, 0.9343, -0.0948)], "torso": ["hips", Vector3(0.0, 1.0453, -0.0948)], "head": ["torso", Vector3(0.0, 1.3875, -0.1768)], "sh_r": ["torso", Vector3(0.2909, 1.221, -0.0706)], "el_r": ["sh_r", Vector3(0.3959, 1.1009, -0.042)], "hand_r": ["el_r", Vector3(0.4928, 0.9901, -0.0155)], "sh_l": ["torso", Vector3(-0.2909, 1.221, -0.0003)], "el_l": ["sh_l", Vector3(-0.387, 1.1041, -0.0546)], "hand_l": ["el_l", Vector3(-0.4757, 0.9962, -0.1046)], "leg_r": ["hips", Vector3(0.0925, 0.9343, -0.1174)], "knee_r": ["leg_r", Vector3(0.182, 0.4952, -0.0491)], "leg_l": ["hips", Vector3(-0.1208, 0.9343, -0.0582)], "knee_l": ["leg_l", Vector3(-0.2055, 0.4952, -0.0574)]}},
	# rigs end
}

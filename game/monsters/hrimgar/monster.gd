extends RefCounted
## Hrimgar the Frostbound (boss): its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["ice_troll"]

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"ice_troll": {"glb": "res://game/monsters/hrimgar/ice_troll.glb", "height": 3.4, "layout": {"hips": ["", Vector3(0.0, 0.799, -0.0101)], "torso": ["hips", Vector3(0.0, 1.003, -0.0101)], "head": ["torso", Vector3(0.0, 2.414, -0.171)], "sh_r": ["torso", Vector3(0.8708, 2.108, 0.2569)], "el_r": ["sh_r", Vector3(1.0781, 1.6645, 0.1575)], "hand_r": ["el_r", Vector3(1.2695, 1.2551, 0.0658)], "sh_l": ["torso", Vector3(-0.8708, 2.108, 0.3119)], "el_l": ["sh_l", Vector3(-1.0715, 1.6566, 0.1778)], "hand_l": ["el_l", Vector3(-1.2567, 1.2399, 0.054)], "leg_r": ["hips", Vector3(0.4472, 0.799, 0.2423)], "knee_r": ["leg_r", Vector3(0.5982, 0.4282, 0.2438)], "leg_l": ["hips", Vector3(-0.3883, 0.799, 0.1992)], "knee_l": ["leg_l", Vector3(-0.5664, 0.4236, 0.2237)]}},
	# rigs end
}

## His brain (BossBrain).
static func brain(e: Enemy) -> BossBrain:
	return Hrimgar.new(e)

## His look: the bb_* events his brain sends.
static func fx(e: Enemy, ev: String) -> bool:
	if not ev.begins_with("bb_"):
		return false
	HrimgarFx.fx(e, ev)
	return true

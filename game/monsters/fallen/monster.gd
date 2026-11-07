extends RefCounted
## The Fallen (the plain one, the Skirmisher, the Reaver, the Stalker): its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["fallen", "fallen_skirmisher", "fallen_reaver", "fallen_stalker"]
## How its body carries itself (Anim's personalities).
const PERSONALITY := {"fallen_reaver": "warrior", "*": "fallen"}

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"fallen": {"glb": "res://game/monsters/fallen/fallen.glb", "height": 1.1, "layout": {"hips": ["", Vector3(0.0, 0.3191, -0.0193)], "torso": ["hips", Vector3(0.0, 0.3851, -0.0193)], "head": ["torso", Vector3(0.0, 0.8472, -0.0266)], "sh_r": ["torso", Vector3(0.0689, 0.7482, -0.0127)], "el_r": ["sh_r", Vector3(0.193, 0.6116, -0.0358)], "hand_r": ["el_r", Vector3(0.3075, 0.4856, -0.0572)], "sh_l": ["torso", Vector3(-0.0689, 0.7482, -0.0272)], "el_l": ["sh_l", Vector3(-0.1933, 0.6141, -0.0434)], "hand_l": ["el_l", Vector3(-0.308, 0.4903, -0.0584)], "leg_r": ["hips", Vector3(0.0753, 0.3191, 0.0057)], "knee_r": ["leg_r", Vector3(0.098, 0.1651, 0.0297)], "leg_l": ["hips", Vector3(-0.0644, 0.3191, 0.0023)], "knee_l": ["leg_l", Vector3(-0.0852, 0.1691, 0.0239)]}},
	"fallen_skirmisher": {"glb": "res://game/monsters/fallen/fallen_skirmisher.glb", "height": 1.25, "layout": {"hips": ["", Vector3(0.0, 0.3187, 0.0292)], "torso": ["hips", Vector3(0.0, 0.3937, 0.0292)], "head": ["torso", Vector3(0.0, 0.925, -0.1134)], "sh_r": ["torso", Vector3(0.1464, 0.8125, -0.0156)], "el_r": ["sh_r", Vector3(0.2449, 0.6775, -0.0338)], "hand_r": ["el_r", Vector3(0.3358, 0.5529, -0.0506)], "sh_l": ["torso", Vector3(-0.1464, 0.8125, -0.0619)], "el_l": ["sh_l", Vector3(-0.2517, 0.7364, -0.0368)], "hand_l": ["el_l", Vector3(-0.3489, 0.6662, -0.0136)], "leg_r": ["hips", Vector3(0.1433, 0.3187, 0.0912)], "knee_r": ["leg_r", Vector3(0.1782, 0.1695, 0.1075)], "leg_l": ["hips", Vector3(-0.1371, 0.3187, 0.2504)], "knee_l": ["leg_l", Vector3(-0.1161, 0.1633, 0.0875)]}},
	"fallen_reaver": {"glb": "res://game/monsters/fallen/fallen_reaver.glb", "height": 1.75, "layout": {"hips": ["", Vector3(0.0, 0.4113, 0.0076)], "torso": ["hips", Vector3(0.0, 0.5163, 0.0076)], "head": ["torso", Vector3(0.0, 1.5225, -0.0052)], "sh_r": ["torso", Vector3(0.3, 1.365, 0.1185)], "el_r": ["sh_r", Vector3(0.4369, 1.1669, 0.0432)], "hand_r": ["el_r", Vector3(0.5634, 0.984, -0.0263)], "sh_l": ["torso", Vector3(-0.3, 1.365, -0.0636)], "el_l": ["sh_l", Vector3(-0.4506, 1.1663, -0.0378)], "hand_l": ["el_l", Vector3(-0.5896, 0.9828, -0.014)], "leg_r": ["hips", Vector3(0.2363, 0.4113, 0.0516)], "knee_r": ["leg_r", Vector3(0.3246, 0.2153, 0.0375)], "leg_l": ["hips", Vector3(-0.1898, 0.4113, 0.0447)], "knee_l": ["leg_l", Vector3(-0.2585, 0.2129, 0.0483)]}},
	"fallen_stalker": {"glb": "res://game/monsters/fallen/fallen_stalker.glb", "height": 1.7, "layout": {"hips": ["", Vector3(0.0, 0.5185, -0.0972)], "torso": ["hips", Vector3(0.0, 0.6205, -0.0972)], "head": ["torso", Vector3(0.0, 1.4195, -0.0163)], "sh_r": ["torso", Vector3(0.1081, 1.2665, 0.0594)], "el_r": ["sh_r", Vector3(0.3104, 0.9922, -0.0042)], "hand_r": ["el_r", Vector3(0.4971, 0.739, -0.0628)], "sh_l": ["torso", Vector3(-0.1081, 1.2665, 0.0116)], "el_l": ["sh_l", Vector3(-0.3072, 0.9838, -0.0855)], "hand_l": ["el_l", Vector3(-0.4909, 0.7228, -0.1751)], "leg_r": ["hips", Vector3(0.1442, 0.5185, -0.0197)], "knee_r": ["leg_r", Vector3(0.17, 0.2748, 0.0)], "leg_l": ["hips", Vector3(-0.136, 0.5185, 0.0)], "knee_l": ["leg_l", Vector3(-0.17, 0.2748, 0.0)]}},
	# rigs end
}

const MOVES := ["skirm_lunge", "reaver_cleave", "stalk_hook"]

## The Reaver's slow start; the Stalker's chosen side, when it flips, and its weave.
static func on_setup(e: Enemy) -> void:
	e.mem = {"rv_spd": 0.0, "side": 1.0, "flip": 1.5, "weave": 0.0}

## Their brains, by the def's "ai" (the plain Fallen fights the shared way).
static func combat(e: Enemy, delta: float, hero: Node3D, to: Vector3, dist: float) -> Variant:
	match str(e.def.get("ai", "")):
		"skirmisher": return FallenBrain.skirmisher(e, delta, hero, to, dist)
		"reaver": return FallenBrain.reaver(e, delta, hero, to, dist)
		"stalker": return FallenBrain.stalker(e, delta, hero, to, dist)
	return null

static func begin(e: Enemy, sp: String) -> void:
	FallenBrain.begin(e, sp)

static func during(e: Enemy, a: float, hero: Node3D) -> void:
	FallenBrain.during(e, a, hero)

static func impact(e: Enemy, hero: Node3D, dist: float) -> void:
	FallenBrain.impact(e, hero, dist)

static func finish(e: Enemy) -> void:
	FallenBrain.finish(e)

static func fx(e: Enemy, ev: String) -> bool:
	if ev != "reaver_tele":
		return false
	FallenFx.fx(e, ev)
	return true

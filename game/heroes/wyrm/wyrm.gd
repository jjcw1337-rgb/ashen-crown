class_name Wyrm
extends RefCounted
## The Obsidian Wyrm's skills script (docs/content/heroes.md): its kit (Hero.kit, skills/<skill>/) and its answers to
## ClassSkills' calls and hooks. It has no skills of its own yet: only the common Attack (the three-swipe combo, which
## its body shows as a raking foreclaw, a bite and a tail spin) and Block. Its body is the shared dragon body
## (game/systems/dragons/dragon.gd: its model is body/wyrm.glb); what every dragon's script shares is DragonKit. Its
## class runs on the match server like the other dragons' (ServerRules.CLASSES), so a skill it gains is written as
## theirs are (a DragonSkill making what its rules act on).

## Its skill ids (none yet).
const IDS: Array = []

# ---------------------------------------------------------------- its kit
static func skill(_h: Hero, _id: String) -> Skill:
	return null

# ---------------------------------------------------------------- the ClassSkills calls
static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	return true

static func cast(_h: Hero, _id: String, _aim: Vector3) -> void:
	pass

static func impact(_h: Hero) -> bool:
	return false

static func update(_h: Hero, _delta: float) -> void:
	pass

static func rooted(_h: Hero) -> bool:
	return false

static func clear(_h: Hero) -> void:
	pass

static func died(h: Hero) -> void:
	if h.cls == "wyrm":
		DragonKit.died(h)

## Its claw, bite and tail spin, each on its impact frame.
static func sound(h: Hero, skill_id: String, at: float) -> bool:
	return DragonKit.attack_sound(h, skill_id, at)

# ---------------------------------------------------------------- its ways (ClassSkills' optional hooks)
static func reach(h: Hero) -> float:
	return DragonKit.reach(h)

class_name Serpent
extends RefCounted
## The Frost Serpent's skills script (docs/content/heroes.md): which skill object handles which id (its kit, Hero.kit,
## skills/<skill>/) and its answers to ClassSkills' calls and hooks. Its own skill is Frost Breath; a run's chests
## give it Glacial Tomb, Crushing Coil and Rime Lance. Its body is the shared dragon body
## (game/systems/dragons/dragon.gd) with its own pose (body/serpent_body.gd: SerpentBody); its effects:
## serpent_fx.gd (SerpentFx); its numbers and text: data/codex/heroes/serpent.json. What every dragon's script shares
## is DragonKit; what every dragon's skill shares, DragonSkill. Its skills run on the match server (ServerRules).

const IDS := ["frost_breath", "s_tomb", "s_coil", "s_lance"]
## Its colour (the swing's trail, ClassSkills.trail_color): glacier blue.
const ACCENT := Color(0.55, 0.9, 1.0)

# ---------------------------------------------------------------- its kit
## Its skill objects (docs/content/skills.md): one per hero, made the first time it's needed, kept in Hero.kit.
static func skill(h: Hero, id: String) -> Skill:
	if not h.kit.has(id):
		var s := _make(h, id)
		if s == null:
			return null
		h.kit[id] = s
	return h.kit[id]

static func _make(h: Hero, id: String) -> Skill:
	match id:
		"frost_breath": return FrostBreath.new(h, id)
		"s_tomb": return GlacialTomb.new(h, id)
		"s_coil": return CrushingCoil.new(h, id)
		"s_lance": return RimeLance.new(h, id)
	return null

# ---------------------------------------------------------------- the ClassSkills calls
static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	var s := skill(h, id)
	return s == null or s.can_cast(aim)

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var s := skill(h, id)
	if s != null:
		s.cast(aim)

## The impact frame of one of its skills; false when it isn't its.
static func impact(h: Hero) -> bool:
	if not IDS.has(h.atk_skill):
		return false
	skill(h, h.atk_skill).impact()
	return true

## (its skill objects beat in ClassSkills; nothing else of its does)
static func update(_h: Hero, _delta: float) -> void:
	pass

static func rooted(_h: Hero) -> bool:
	return false

## (ClassSkills clears its skill objects; SkillFx its look)
static func clear(_h: Hero) -> void:
	pass

static func died(h: Hero) -> void:
	if h.cls == "serpent":
		DragonKit.died(h)

## A skill's sound, timed to land on its impact frame; its claw, bite and tail spin.
static func sound(h: Hero, skill_id: String, at: float) -> bool:
	match skill_id:
		"s_tomb":
			DragonKit.roar(h, -8.0, 1.1)
			Sfx.play_synced("ice_form", at, -1.0)
			return true
		"s_coil":
			Sfx.play_synced(h.cls + "_tail", at, -1.0, 0.85)
			DragonKit.roar(h, -10.0, 0.9)
			return true
		"s_lance":
			DragonKit.roar(h, -9.0, 1.2)
			Sfx.play_synced("frost_spread", at, -2.0, 1.1)
			return true
	return DragonKit.attack_sound(h, skill_id, at)

# ---------------------------------------------------------------- its ways (ClassSkills' optional hooks)
static func reach(h: Hero) -> float:
	return DragonKit.reach(h)

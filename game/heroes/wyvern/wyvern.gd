class_name Wyvern
extends RefCounted
## The Storm Wyvern's skills script (docs/content/heroes.md): which skill object handles which id (its kit, Hero.kit,
## skills/<skill>/) and its answers to ClassSkills' calls and hooks. Its own skill is Storm Arc (jj: chain lightning
## from its jaws); a run's chests give it Thunder Dive, Thunderhead and Gale Wings. Its body is the shared dragon body
## (game/systems/dragons/dragon.gd; it flies its dodge, DragonFlight); its effects: wyvern_fx.gd (WyvernFx); its
## numbers and text: data/codex/heroes/wyvern.json. What every dragon's script shares is DragonKit; what every dragon's
## skill shares, DragonSkill. Its skills run on the match server (ServerRules).

const IDS := ["storm_arc", "v_dive", "v_cloud", "v_gale"]

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
		"storm_arc": return StormArc.new(h, id)
		"v_dive": return ThunderDive.new(h, id)
		"v_cloud": return Thunderhead.new(h, id)
		"v_gale": return GaleWings.new(h, id)
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
	if h.cls == "wyvern":
		DragonKit.died(h)

## A skill's sound, timed to land on its impact frame; its claw, bite and tail spin.
static func sound(h: Hero, skill_id: String, at: float) -> bool:
	match skill_id:
		"storm_arc":
			DragonKit.roar(h, -8.0, 1.15)
			Sfx.play_synced("arc_zap", at, -2.0)
			return true
		"v_dive":
			DragonKit.roar(h, -6.0, 1.05)
			Sfx.play_synced("wyvern_dive", at, -1.0)
			return true
		"v_cloud":
			DragonKit.roar(h, -8.0, 0.9)
			Sfx.play_synced("sigil_charge", at, -4.0)
			return true
		"v_gale":
			Sfx.play_synced("wyvern_flap", at, -3.0, 0.75)
			DragonKit.roar(h, -9.0, 1.0)
			return true
	return DragonKit.attack_sound(h, skill_id, at)

# ---------------------------------------------------------------- its ways (ClassSkills' optional hooks)
static func reach(h: Hero) -> float:
	return DragonKit.reach(h)

class_name Necromancer
extends RefCounted
## The Necromancer's skills script (docs/content/heroes.md): which skill object handles which id (his kit, Hero.kit,
## skills/<skill>/), and his answers to ClassSkills' calls and hooks (jj, 2026-11-07: "a necromancer... a graveyard
## summon skill, use the waypoint resources"). His body and staff: body/necromancer_body.gd (NecromancerBody); his
## effects: necromancer_fx.gd (NecromancerFx); his numbers and text: data/codex/heroes/necromancer.json. His staff's
## three blows are Hero's plain melee swing.
##   bone_bolt  Bone Bolt (right mouse): a shard of bone that pierces one foe (BoneBolt)
##   graveyard  Graveyard (Q): a graveyard torn up at the pointer; its risen dead strike what's inside (Graveyard)
## In a Battlegrounds, Arena or Sandbox match his skills run on the server (ServerRules), as every hero's do.

const ACCENT := Color(0.45, 1.0, 0.6)          # his colour: the soul-lantern's green
## His skills' attack styles (no weapon trail on a cast)
const SKILL_STYLES := ["bone_bolt", "grave_slam"]
const IDS := ["bone_bolt", "graveyard"]

# ---------------------------------------------------------------- his kit
static func skill(h: Hero, id: String) -> Skill:
	if not h.kit.has(id):
		var s := _make(h, id)
		if s == null:
			return null
		h.kit[id] = s
	return h.kit[id]

static func _make(h: Hero, id: String) -> Skill:
	match id:
		"bone_bolt": return BoneBolt.new(h, id)
		"graveyard": return Graveyard.new(h, id)
	return null

# ---------------------------------------------------------------- ClassSkills
static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	var s := skill(h, id)
	return s == null or s.can_cast(aim)

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var s := skill(h, id)
	if s != null:
		s.cast(aim)

## The impact frame (Hero._impact): true when it was one of his skills (a plain swing is Hero's).
static func impact(h: Hero) -> bool:
	if not IDS.has(h.atk_skill):
		return false
	skill(h, h.atk_skill).impact()
	return true

## (his skill objects beat in ClassSkills; nothing else of his does)
static func update(_h: Hero, _delta: float) -> void:
	pass

static func rooted(_h: Hero) -> bool:
	return false

static func clear(_h: Hero) -> void:
	pass

static func died(_h: Hero) -> void:
	pass

## The cast's sound, timed to land on its impact frame.
static func sound(_h: Hero, skill_id: String, at: float) -> bool:
	match skill_id:
		"bone_bolt": Sfx.play_synced("swing_light", at, -6.0)
		"graveyard": Sfx.play_synced("slam", at, -3.0)
		_: return false
	return true

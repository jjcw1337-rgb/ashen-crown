class_name KnightSkills
extends RefCounted
## The Knight's skills script (docs/content/heroes.md): which skill object handles which id (his kit, Hero.kit,
## skills/<skill>/), and his answers to ClassSkills' calls and hooks. His bodies: body/knight_body.gd (KnightBody); his
## effects: knight_fx.gd (KnightFx) and each skill's look; his numbers and text: data/codex/heroes/knight.json.
## What his skills share: KnightSkill (shared/knight_skill.gd: his stuns, his leaps) and Holy Brands
## (shared/holy_brands.gd: every blow of a run knight with Judgment marks its foe; Judgment spends them).
##   cleave      Holy Slam: a leap at the cursor and a blow all round where the blade lands, stunning
##   nova        Holy Nova: a ring of holy fire round him
##   charge      Charge: a dash through enemies, each smashed once and stunned
##   cry         Battle Cry: the class's battle buff, and everything near stunned
##   k_whirl, k_aegis, k_judgment, k_rites: a run's Blade Storm, Aegis, Judgment and Last Rites
## In a Battlegrounds, Arena or Sandbox match his skills run on the server (ServerRules): his game moves him and shows
## the cast at once, and the server's copy of him deals the hits (Skill.make) and the stuns (players' through the
## server: PvpStatus). His battle buff and Aegis's ward stay on his own game, which owns his life. His weapon's own
## swing is Hero's (every melee hero's).

const IDS := ["cleave", "nova", "charge", "cry", "k_whirl", "k_aegis", "k_judgment", "k_rites"]

# ---------------------------------------------------------------- his kit
## His skill objects (docs/content/skills.md): one per skill id, made the first time it's needed, kept in Hero.kit.
static func skill(h: Hero, id: String) -> Skill:
	if not h.kit.has(id):
		var s := _make(h, id)
		if s == null:
			return null
		h.kit[id] = s
	return h.kit[id]

static func _make(h: Hero, id: String) -> Skill:
	match id:
		"cleave": return HolySlam.new(h, id)
		"nova": return HolyNova.new(h, id)
		"charge": return KnightCharge.new(h, id)
		"cry": return BattleCry.new(h, id)
		"k_whirl": return BladeStorm.new(h, id)
		"k_aegis": return Aegis.new(h, id)
		"k_judgment": return Judgment.new(h, id)
		"k_rites": return LastRites.new(h, id)
	return null

# ---------------------------------------------------------------- the ClassSkills calls
static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	var s := skill(h, id)
	return s == null or s.can_cast(aim)

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var s := skill(h, id)
	if s != null:
		s.cast(aim)

## The impact frame of one of his skills (Hero then refreshes the stats); false when it isn't his.
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
		"cleave":
			Sfx.play_synced("cleave_swing", at, -2.0)
		"nova":
			Sfx.play_synced("holy_nova", at, 0.0)
			Sfx.duck(-8.0, 1.0)
		_:
			return false
	return true

# ---------------------------------------------------------------- his ways (ClassSkills' optional hooks)
## Charge: the dash carries him in place of his walking (Hero, while charge_t >= 0).
static func dash(h: Hero, delta: float) -> void:
	var s = h.kit.get("charge")
	if s != null:
		s.dash(delta)
	else:
		h.charge_t = -1.0

## A blow of his landed (wherever his hits are decided): with Judgment in his run, it brands its foe (Judgment's own
## blows spend them instead).
static func struck(h: Hero, e, src: String) -> void:
	if src != "k_judgment" and h.run != null and h.run.skills.has("k_judgment"):
		HolyBrands.add(h, e)

## The match server's copy of him (ServerRules.update): fallen, what ends with him ends there too (his own game: died).
static func server_update(h: Hero, _delta: float) -> void:
	if h.dead:
		for sk in h.kit.values():
			sk.died()

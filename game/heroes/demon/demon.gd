class_name Demon
extends RefCounted
## The Demon's skills script (docs/content/heroes.md): which skill object handles which id (his kit, Hero.kit,
## skills/<skill>/), and his answers to ClassSkills' calls and hooks. His body: body/demon_body.gd (DemonBody); his
## effects: demon_fx.gd (DemonFx) and each skill's own look; his numbers and text: data/codex/heroes/demon.json. Every
## skill of his is a DemonSkill (shared/demon_skill.gd); the Brand they share is DemonBrand (shared/), first in his kit.
## One job per skill (PvP first, PvE kept strong; the "pvp" shares in Data.SKILLS apply to players only):
##  - Molten Fists (Q, "fists"): the heavy wedge punch, the burst finisher; spends a Brand for more.
##  - Infernal Charge (E, "icharge"): paw, run, skid; stops on the first champion, boss or player, staggered and Branded.
##  - Fault of the Pit (R, "cslam"): a line across his aim erupts after a warning (thrown up, Branded), then stays
##    molten, burning and slowing.
##  - Brimstone Hurl (F, "hurl"): a boulder lobbed at the pointer; its core Brands and burns, then it shatters.
##  - Hellgrip (G, "grip"): a chain flung down a line hooks the first foe, hauls it in, hoists it and smashes it.
##  - Wrath of the Pit (V, "wrath"): the Crucible (half the damage, unstoppable, stored as heat), the eruption, then
##    Pit-born (the battle buff and a rain of meteors).
## A run's: Volcano ("d_volcano"), Hellbrand Detonation ("d_detonate"), Blood Pact ("d_pact").
## In a Battlegrounds, Arena or Sandbox match his skills' rules run on the match server (ServerRules): his game moves
## him, runs his stages and shows his casts; what they strike is made and dealt by the server's copy of him.

const IDS := ["fists", "icharge", "cslam", "hurl", "grip", "wrath", "d_volcano", "d_detonate", "d_pact"]
## His six skills (a clear stops one mid-swing).
const MAIN := ["fists", "icharge", "cslam", "hurl", "grip", "wrath"]
## Each stage's length in seconds (before Data.ATTACK_PACE; the charge's run is set by its distance). A skill with a
## "use" in its Data.SKILLS entry (SkillSpec) takes that instead: Molten Fists is a heavy blow the Path of Exile way
## (jj, 2026-11-01: its "use" 2 s, "hit" 0.75 and damage are its data; DUR["fists"] is only the fallback), and so are
## Fault of the Pit and Brimstone Hurl (their "use" and "power").
const DUR := {"fists": 1.67, "icharge_wind": 0.32, "icharge": 0.6, "icharge_skid": 0.38, "cslam": 1.15, "hurl": 0.95,
	"hurl2": 1.0, "grip_throw": 0.55, "grip_haul": 0.45, "grip": 1.25, "crucible": 2.0, "wrath_roar": 1.1}
## The stages after a skill's first (DemonBody.SHOTS has their clips).
const STAGES := ["icharge_wind", "icharge", "icharge_skid", "grip_throw", "grip_haul", "grip", "crucible", "wrath_roar"]
## Old saves: the skills these replaced, so their bindings carry over
const OLD_IDS := {"hellclaw": "fists", "summon": "icharge", "phase": "cslam", "pact": "hurl"}

# ---------------------------------------------------------------- his kit
## His skill objects (docs/content/skills.md): one per hero, made the first time it's needed, kept in Hero.kit after
## the Brand they share.
static func skill(h: Hero, id: String) -> Skill:
	if not h.kit.has(id):
		var s := _make(h, id)
		if s == null:
			return null
		brands(h)
		h.kit[id] = s
	return h.kit[id]

static func _make(h: Hero, id: String) -> Skill:
	match id:
		"fists": return MoltenFists.new(h, id)
		"icharge": return InfernalCharge.new(h, id)
		"cslam": return FaultOfThePit.new(h, id)
		"hurl": return BrimstoneHurl.new(h, id)
		"grip": return Hellgrip.new(h, id)
		"wrath": return WrathOfThePit.new(h, id)
		"d_volcano": return Volcano.new(h, id)
		"d_detonate": return HellbrandDetonation.new(h, id)
		"d_pact": return BloodPact.new(h, id)
	return null

## The Brand his skills share: first in his kit, so it fades before they look.
static func brands(h: Hero) -> DemonBrand:
	if not h.kit.has("brand"):
		h.kit["brand"] = DemonBrand.new(h, "brand")
	return h.kit["brand"]

## Pit-born (Wrath of the Pit's eruption until its rain is over).
static func pit_born(h: Hero) -> bool:
	var w = h.kit.get("wrath")
	return w != null and w.pit

# ---------------------------------------------------------------- the ClassSkills calls
static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	return true

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var s := skill(h, id)
	if s != null:
		s.cast(aim)

## The impact frame of one of his skills' stages; false when it isn't his.
static func impact(h: Hero) -> bool:
	if not h.is_demon() or not IDS.has(h.atk_skill):
		return false
	skill(h, h.atk_skill).impact()
	return true

## (his skill objects beat in ClassSkills; nothing else of his does)
static func update(_h: Hero, _delta: float) -> void:
	pass

## (held in place mid-skill: his skill objects' `rooted`)
static func rooted(_h: Hero) -> bool:
	return false

## Everything of his that lingers (a class change, a new character, a zone change, death), and a skill of his
## mid-swing stops.
static func clear(h: Hero) -> void:
	for sk in h.kit.values():
		if sk is DemonSkill:
			sk.clear()
	DemonFx.clear(h)
	if h.atk_t >= 0.0 and h.atk_skill in MAIN:
		h.atk_t = -1.0
		h.atk_skill = ""

static func died(h: Hero) -> void:
	clear(h)

## His casts' sounds are played by his skills' looks themselves, none at the cast's start.
static func sound(_h: Hero, _skill: String, _at: float) -> bool:
	return false

# ---------------------------------------------------------------- his ways (ClassSkills' optional hooks)
## Pressing Wrath of the Pit again in the Crucible ends it early.
static func recast(h: Hero, id: String) -> bool:
	var w = h.kit.get("wrath")
	return id == "wrath" and w != null and w.recast()

## Hero._update_attack ended one of his stages: what follows it (the run after the paw, the skid; the haul, the
## smash; the eruption after the Crucible).
static func stage_done(h: Hero, style: String, skill_id: String) -> void:
	var s = h.kit.get(skill_id)
	if s is DemonSkill and not h.dead:
		s.stage_done(style)

## The Crucible takes its share of a blow and stores it as heat.
static func absorb(h: Hero, dmg: float) -> float:
	var w = h.kit.get("wrath")
	return w.absorb(dmg) if w != null else dmg

## In the Crucible nothing stops or moves him (PvpStatus).
static func unstoppable(h: Hero) -> bool:
	var w = h.kit.get("wrath")
	return w != null and w.holding()

## The match server's copy of him: Blood Pact's buff runs out here too (its game's runs in Hero._process_body), and
## when he falls what his skills had going goes with him.
static func server_update(h: Hero, delta: float) -> void:
	RunTalents.tick(h, delta)
	if h.dead and not h.kit.is_empty():
		for sk in h.kit.values():
			sk.clear()

## Old saves bound the skills these replaced: the binding carries over.
static func migrate_binds(binds: Dictionary) -> void:
	for k in binds.keys():
		var id := str(binds[k])
		if OLD_IDS.has(id):
			binds[k] = OLD_IDS[id]

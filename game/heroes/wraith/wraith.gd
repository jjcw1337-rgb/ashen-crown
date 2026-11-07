class_name Wraith
extends RefCounted
## The Wraith (class "wraith"): a horned spirit in chains that never touches the ground. His skills (Data.SKILLS
## "cls": "wraith", and a run's in Data.RUN_SKILLS), each a Skill object in Hero.kit made by the table below, with
## its rules and its look in its own folder (skills/<skill>/; docs/content/skills.md):
##   Spectral Rend (Q, "rend"): the lunge and two rakes of the claws, souls torn out that heal him;
##   Soul Siphon (E, "siphon"): a tether that holds a foe and drains it;
##   Shadowstep (R, "step"): he goes out in mist and re-forms in a claw strike; the shade he left collapses;
##   Haunting Grasp (F, "grasp"): hands out of the ground that seize and hold;
##   Phantom Assault (G, "phantom"): phantoms of him streaking through the foes ahead;
##   Eternal Night (V, "night"): the ultimate: he rises, screams, hangs in the night as it feeds, and falls;
##   a run's: Death Mark, Banshee Wail, Reaping Crescent.
## Every skill is a whole-body clip of his (WraithBody.SHOTS: the clip and how the attack's progress maps onto its
## seconds, so the blow lands on Anim.impact_at's frame at any attack speed; KnightMocapRig "shots"). In a match his
## skills run on the server (ServerRules). His weapon swing is everyone's (Hero). What is seen goes through fx events
## (Hero.fx -> WraithFx and each skill's look). His body: body/wraith_body.gd (WraithBody).

## The attack style each of his own skills starts with (one of them in progress is cut off by `clear`).
const STYLE := {"rend": "rend", "siphon": "siphon", "step": "wstep", "grasp": "grasp", "phantom": "phantom", "night": "night_rise"}
## Old saves: the skills these replaced, so their bindings carry over
const OLD_IDS := {"reap": "rend", "wail": "siphon", "shade": "step", "host": "grasp"}

# ---------------------------------------------------------------- his kit
## His skills' objects (docs/content/skills.md): one per skill, made the first time it's needed, kept in Hero.kit.
static func skill(h: Hero, id: String) -> Skill:
	if not h.kit.has(id):
		var s := _make(h, id)
		if s == null:
			return null
		h.kit[id] = s
	return h.kit[id]

static func _make(h: Hero, id: String) -> Skill:
	match id:
		"rend": return SpectralRend.new(h, id)
		"siphon": return SoulSiphon.new(h, id)
		"step": return ShadowStep.new(h, id)
		"grasp": return HauntingGrasp.new(h, id)
		"phantom": return PhantomAssault.new(h, id)
		"night": return EternalNight.new(h, id)
		"r_deathmark": return DeathMark.new(h, id)
		"r_wail": return BansheeWail.new(h, id)
		"r_reap": return ReapingCrescent.new(h, id)
	return null

# ---------------------------------------------------------------- ClassSkills
## Checks before anything is spent (Soul Siphon needs a foe to latch onto).
static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	var s := skill(h, id)
	return s == null or s.can_cast(aim)

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var s := skill(h, id)
	if s != null:
		s.cast(aim)

## The attack's impact frame: true when it was one of his skills (his weapon swing is Hero's own).
static func impact(h: Hero) -> bool:
	if not h.is_wraith() or h.atk_skill == "":
		return false
	var s := skill(h, h.atk_skill)
	if s == null:
		return false
	s.impact()
	return true

## Every frame on the local hero, whatever his class: his mist wears off (not while the night holds it), and his
## skills run (their cast state and, where they were made, their rules).
static func update(h: Hero, delta: float) -> void:
	var n = h.kit.get("night")
	if h.veil_t > 0.0 and not (n is EternalNight and (n as EternalNight).active()):
		h.veil_t = maxf(0.0, h.veil_t - delta)
	if not h.is_wraith():
		return
	for sk in h.kit.values():
		if sk is WraithSkill:
			sk.update(delta)

## The blink, the slam and the night hold him in place.
static func rooted(h: Hero) -> bool:
	for sk in h.kit.values():
		if sk is WraithSkill and sk.rooted():
			return true
	return false

## Everything of his that lingers: the tether, phantoms in flight, the night, the marks (a class change, a new
## character, death).
static func clear(h: Hero) -> void:
	for id in h.kit.keys():
		var sk = h.kit[id]
		if sk is WraithSkill:
			sk.clear()
			h.kit.erase(id)
	WraithFx.clear(h)
	if h.atk_t >= 0.0 and h.atk_skill in STYLE:
		# a skill of his in progress is cut off (a class change, death)
		h.atk_t = -1.0
		h.atk_skill = ""
	h.veil_t = 0.0

static func died(h: Hero) -> void:
	clear(h)

## The casts' sounds, timed to their impact frame (`at` seconds from now; ClassSkills.sound).
static func sound(h: Hero, skill_id: String, at: float) -> bool:
	match skill_id:
		"rend": Sfx.play_synced("reap_swing", at, -2.0, 1.05)
		"siphon": Sfx.play_synced("shade_in", at, -6.0, 0.8)
		"step": Sfx.play_synced("shade_out", ShadowStep.BLINK_AT * h.atk_dur, -4.0, 1.1)
		"grasp": Sfx.play_synced("slam", at, -2.0, 0.9)
		"phantom": Sfx.play_synced("reap_swing", at, -3.0, 0.9)
		"r_reap": Sfx.play_synced("reap_swing", at, -1.0, 0.75)
		_: return false
	return true

## Old saves bound the skills these replaced: the binding carries over.
static func migrate_binds(binds: Dictionary) -> void:
	for k in binds.keys():
		var id := str(binds[k])
		if OLD_IDS.has(id):
			binds[k] = OLD_IDS[id]

# ---------------------------------------------------------------- his body, for the Warlock's
## The Warlock's body floats and glows like his (Warlock.build_mocap): what it borrows, from WraithBody.
const FLOAT_SPEED := WraithBody.FLOAT_SPEED
const HOVER := WraithBody.HOVER

static func _spectral(r: Node3D, gear: Dictionary) -> void:
	WraithBody._spectral(r, gear)

static func _mocap_extras(r: Node3D, gear: Dictionary) -> void:
	WraithBody._mocap_extras(r, gear)

class_name SharedSkills
extends RefCounted
## The shared skills: Data.SKILLS entries with "cls": "any", which every class can put on its bar (jj, 2026-11-01:
## class-free skills, the Path of Exile way). Same functions as a class's skills script (ClassSkills); the tuning is
## their data (SkillSpec: use, dmg / base, type, knock, area, dot), the effects SharedFx. They play on the shared
## animation styles every body has ("slam", "cast", "thrust"), so they keep those styles' own impact frames (no
## "hit" in their data: a style's "hit" is every user's).
##  - Earthshatter: a heavy slam; the ground cracks in a wide wedge ahead (the wedge is shown through the wind-up).
##  - Frost Nova: a ring of ice bursts out round him, chilling what it hits.
##  - Arc: lightning into the nearest foe ahead that jumps on to ARC_JUMPS more.
##  - War Cry (the team skill, utility: a cooldown): the battle buff for CRY_BUFF s for him and every teammate within
##    CRY_R (co-op partners, through Net.send_team_buff: each partner's own game buffs its hero if it stands near; the
##    Battlegrounds has no teams yet, so there it is his alone), and the monsters near turn on him.

const IDS := ["earthshatter", "frost_nova", "arc", "war_cry"]
const ARC_JUMPS := 3
const ARC_JUMP_R := 5.0
const CRY_R := 8.0
const CRY_BUFF := 6.0
const CRY_TAUNT := 4.0

static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	return true

static func cast(h: Hero, id: String, _aim: Vector3) -> void:
	if not IDS.has(id):
		return
	h._start_attack(str(Data.skill_def(id)["style"]), id)
	h.moving = false
	h.path = PackedVector3Array()
	if id == "earthshatter":
		# the tell: the wedge it will crack, shown until the blow
		h.fx(id, "windup", {"d": h.aim_dir(), "x": SkillSpec.use_time(h, id) * Anim.impact_at("slam")})

static func impact(h: Hero) -> bool:
	var id := h.atk_skill
	if not IDS.has(id):
		return false
	match id:
		"arc":
			var pts := chain(h, id, SkillFx.hand(h, true), ARC_JUMPS)
			h.fx(id, "impact", {"ps": pts, "d": h.aim_dir()})
		"war_cry":
			h.buff_t = maxf(h.buff_t, CRY_BUFF)
			h.game.net.send_team_buff(CRY_BUFF, h.global_position)
			for e in h.game.enemies_near(h.global_position, CRY_R):
				if not e.dead and not e.remote:
					e.taunt = h
					e.taunt_t = CRY_TAUNT
			h.fx(id, "impact", {"p": h.global_position})
		_:
			var hit := SkillSpec.targets(h, id)
			for e in hit:
				SkillSpec.strike(h, id, e)
			h.fx(id, "impact", {"p": h.global_position, "d": h.aim_dir(), "r": float(Data.skill_def(id)["area"]["r"])})
	return true

## Arc's lightning (and the Storm Wyvern's): into the first target the skill finds ahead, then on to the nearest one
## within ARC_JUMP_R of each, `jumps` more times, striking each (SkillSpec.strike). Returns the path, from `from`.
static func chain(h: Hero, id: String, from: Vector3, jumps: int) -> PackedVector3Array:
	var first := SkillSpec.targets(h, id)
	var pts := PackedVector3Array([from])
	var hit := []
	var at = first[0] if not first.is_empty() else null
	while at != null and hit.size() <= jumps:
		hit.append(at)
		pts.append(at.global_position + Vector3(0, 1.0, 0))
		SkillSpec.strike(h, id, at)
		var next = null
		var bd := ARC_JUMP_R
		for e in h.game.enemies_near(at.global_position, ARC_JUMP_R):
			if e.dead or hit.has(e):
				continue
			var d: float = e.global_position.distance_to(at.global_position)
			if d < bd:
				bd = d
				next = e
		at = next
	return pts

static func update(_h: Hero, _delta: float) -> void:
	pass

static func rooted(_h: Hero) -> bool:
	return false

static func clear(_h: Hero) -> void:
	pass

static func died(_h: Hero) -> void:
	pass

static func sound(_h: Hero, _skill: String, _at: float) -> bool:
	return false

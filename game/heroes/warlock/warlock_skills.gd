class_name WarlockSkills
extends RefCounted
## The Warlock's skills script (docs/content/heroes.md): which skill object handles which id (her kit, Hero.kit,
## skills/<skill>/), and her answers to ClassSkills' calls and hooks. Her body: body/warlock_body.gd (Warlock); her
## effects: warlock_fx.gd (WarlockFx) and shared/warlock_harrow_fx.gd (WarlockHarrowFx); her numbers and text:
## data/codex/heroes/warlock.json. What her skills share (curses, fears, the shield) is WarlockHex (shared/), first in
## her kit; every skill of hers is a WarlockSpell (shared/warlock_spell.gd).
## Her first skills: Drain Life (a held channel), Blight Bolt, Soul Shackles, Fel Covenant; her three directions
## (WarlockHex): Corruption's curses, Fear's frights and Drain's leeches.

const IDS := ["drain", "blight", "shackles", "covenant", "w_corruption", "w_malediction", "w_unending", "w_festering",
	"w_leeching", "w_reckoning", "w_terrify", "w_effigy", "w_darkwind", "w_crowstorm", "w_leechbolt", "w_harvest",
	"w_soulfeast"]

# ---------------------------------------------------------------- her kit
## Her skill objects (docs/content/skills.md): one per hero, made the first time it's needed, kept in Hero.kit
## after her shared state (`hex`).
static func skill(h: Hero, id: String) -> Skill:
	if not h.kit.has(id):
		var s := _make(h, id)
		if s == null:
			return null
		hex(h)
		h.kit[id] = s
	return h.kit[id]

static func _make(h: Hero, id: String) -> Skill:
	match id:
		"drain": return DrainLife.new(h, id)
		"blight": return BlightBolt.new(h, id)
		"shackles": return SoulShackles.new(h, id)
		"covenant": return FelCovenant.new(h, id)
		"w_corruption": return Corruption.new(h, id)
		"w_malediction": return Malediction.new(h, id)
		"w_unending": return UnendingRot.new(h, id)
		"w_festering": return FesteringHex.new(h, id)
		"w_leeching": return LeechingCurse.new(h, id)
		"w_reckoning": return Reckoning.new(h, id)
		"w_terrify": return Terrify.new(h, id)
		"w_effigy": return DreadTotem.new(h, id)
		"w_darkwind": return VoidWisp.new(h, id)
		"w_crowstorm": return EclipseBloom.new(h, id)
		"w_leechbolt": return LeechBolt.new(h, id)
		"w_harvest": return Thornlash.new(h, id)
		"w_soulfeast": return SoulFeast.new(h, id)
	return null

## What her skills share (curses, fears, the shield): first in her kit, so it beats before them.
static func hex(h: Hero) -> WarlockHex:
	if not h.kit.has("hex"):
		h.kit["hex"] = WarlockHex.new(h, "hex")
	return h.kit["hex"]

# ---------------------------------------------------------------- the ClassSkills calls
static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	var s := skill(h, id)
	return s == null or s.can_cast(aim)

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var s := skill(h, id)
	if s != null:
		s.cast(aim)

## The impact frame of one of her skills (Hero then refreshes the stats); false when it isn't hers.
static func impact(h: Hero) -> bool:
	if not IDS.has(h.atk_skill):
		return false
	skill(h, h.atk_skill).impact()
	return true

## (her skill objects beat in ClassSkills; nothing else of hers does)
static func update(_h: Hero, _delta: float) -> void:
	pass

## (held in place: Eclipse Bloom's and Soul Feast's casts, their objects' `rooted`)
static func rooted(_h: Hero) -> bool:
	return false

static func clear(h: Hero) -> void:
	end_channel(h)
	WarlockFx.clear(h)

static func died(h: Hero) -> void:
	end_channel(h)

# ---------------------------------------------------------------- her ways (ClassSkills' optional hooks)
## Drain Life's channel, every frame it's held.
static func channel(h: Hero, delta: float) -> void:
	var s = h.kit.get("drain")
	if s != null:
		s.channel(delta)
	else:
		h.channel_t = -1.0

static func end_channel(h: Hero) -> void:
	var s = h.kit.get("drain")
	if s != null:
		s.end()

## Her shield soaks a blow first (Blood Ward, the Soul Feast).
static func absorb(h: Hero, dmg: float) -> float:
	var hx = h.kit.get("hex")
	return hx.absorb(dmg) if hx != null else dmg

## After the body's pose: her fel light swells with the Covenant (a partner's copy of her: with her battle buff), and
## her hands' fire and wisps follow what she's doing (Warlock.animate).
static func posed(h: Hero, st: Dictionary) -> void:
	var fc = h.kit.get("covenant")
	var power := 1.0 if (fc != null and fc.active()) or (h.puppet and h.net_buff) else 0.0
	Warlock.animate(h.rig, h.anim_time, h.move_amt, power, h.phase, (h.puppet or float(st.get("atk", -1.0)) < 0.0) and h.channel_t < 0.0)

## The cast's sound, timed to land on its impact frame.
static func sound(_h: Hero, skill_id: String, at: float) -> bool:
	if skill_id == "blight":
		Sfx.play_synced("blight_cast", at, -2.0)
		return true
	if not WarlockHex.has(skill_id):
		return false
	var nm := {"w_corruption": "curse_cast", "w_unending": "curse_cast", "w_festering": "curse_cast", "w_leeching": "curse_cast",
		"w_reckoning": "reckoning", "w_malediction": "malediction", "w_terrify": "terrify", "w_effigy": "effigy_plant",
		"w_darkwind": "crow_caw", "w_crowstorm": "crowstorm", "w_leechbolt": "leech_bolt", "w_harvest": "harvest_sweep",
		"w_soulfeast": "soul_feast"}
	var s := str(nm.get(skill_id, ""))
	if s != "" and (Sfx.bank.has(s) or Sfx.streams.has(s)):
		Sfx.play_synced(s, at, -3.0)
	else:
		Sfx.play_synced("blight_cast", at, -4.0)
	return true

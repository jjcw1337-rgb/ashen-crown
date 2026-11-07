class_name HolyBrands
extends RefCounted
## Holy Brands (a run knight's mark, Judgment's fuel): while his run has Judgment, every blow of his (but Judgment's own)
## leaves a brand on its foe, up to brand_max (Searing Brands, the talent "brand_max": more), each lasting brand_s from
## the last; Judgment spends them for more. Searing Brands ("brand_burn") also burns the foe a little for each one.
## The brands are plain data on the foe ("brand", "brand_until"), kept where his hits are decided (Hero._hit_enemy ->
## ClassSkills.struck -> KnightSkills.struck), so on the match server they are on its monsters and stand-ins. Their look
## is an event (Judgment's "brand" {t: [the foe]}: HolyBrandsFx's gold motes over it), sent once for each brand_s it
## shows. Their numbers are Judgment's codex "k": brand_max, brand_s, brand_burn (% of his weapon's low and high rolls
## a second, for each brand), brand_burn_s.

const SKILL := "k_judgment"

## A blow of his landed on e: one more brand on it.
static func add(h: Hero, e) -> void:
	if e == null or not is_instance_valid(e) or e.dead or int(e.get("pvp_obj")) > 0:
		return
	var now := Time.get_ticks_msec()
	var secs := Skill.num(SKILL, "brand_s", 6.0)
	var most := int(Skill.num(SKILL, "brand_max", 5.0)) + int(h.talent("brand_max"))
	var n := mini(most, count(e) + 1)
	e.set_meta("brand", n)
	e.set_meta("brand_until", now + int(secs * 1000.0))
	if h.talent("brand_burn") > 0.0:
		e.ignite((h.dmg_min + h.dmg_max) * Skill.num(SKILL, "brand_burn", 4.0) / 100.0 * n, Skill.num(SKILL, "brand_burn_s", 2.0))
	if now >= int(e.get_meta("brand_shown", 0)):
		e.set_meta("brand_shown", now + int(secs * 1000.0))
		h.fx(SKILL, "brand", {"t": [e]})

## The brands on a foe now.
static func count(e) -> int:
	if not e.has_meta("brand") or Time.get_ticks_msec() > int(e.get_meta("brand_until", 0)):
		return 0
	return int(e.get_meta("brand"))

## Judgment spends a foe's brands: how many it had.
static func spend(e) -> int:
	var n := count(e)
	e.set_meta("brand", 0)
	return n

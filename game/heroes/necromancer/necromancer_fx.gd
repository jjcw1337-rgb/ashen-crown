class_name NecromancerFx
extends RefCounted
## What the Necromancer's skills look like: every event (SkillFx.play -> here) is drawn on the caster and on his
## puppet for partners and PvP opponents, by his skills' own looks. Draws only: no damage, no cooldowns.
##  Bone Bolt: "loose" {p, d} (BoneBoltFx: the shard flies its own copy of the rules' Missile)
##  Graveyard: "rise" {g, r, x, n}, "strike" {g, t}, "end" {g} (GraveyardFx, GraveyardSite)

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev.get("s", "")):
		"bone_bolt":
			return BoneBoltFx.play(h, ev)
		"graveyard":
			return GraveyardFx.play(h, ev)
	return false

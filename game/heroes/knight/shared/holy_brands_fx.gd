class_name HolyBrandsFx
extends RefCounted
## Holy Brands' look (HolyBrands' "brand" {t: [the foe]}, sent as Judgment's): gold motes turning over the branded foe
## for as long as its brands last (on a player aimed at, over their hero on their own screen).

const NODE := "brand_fx"

static func play(h: Hero, ev: Dictionary) -> void:
	for e in ev.get("t", []):
		if e == null or not is_instance_valid(e) or e.has_node(NODE):
			continue
		var a := Fx.aura(e, HolyFx.GOLD, 10, 0.2, 0.07, 0.9, 0.4, 0.35, 30.0, Vector3(0, SkillFx.height_of(e) * 2.0 + 0.3, 0))
		a.name = NODE
		Fx._free_later(a, Skill.num(HolyBrands.SKILL, "brand_s", 6.0))

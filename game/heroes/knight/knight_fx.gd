class_name KnightFx
extends RefCounted
## The Knight's effects (SkillFx events): each skill's look draws its own (skills/<skill>/<skill>_fx.gd), from its
## rules' events (skills/<skill>/<skill>.gd). They only draw. His holy language (the seal, holy fire rings, the light
## column, the shockwave) is HolyFx's (game/systems/fx/), which other heroes borrow pieces of.
##  Holy Slam: "slam" {p}, "struck" {ps}            HolySlamFx
##  Holy Nova: "impact"                             HolyNovaFx
##  Charge: "cast", "hit" {p, x}, "end"             ChargeFx (its trail follows him in `update`)
##  Battle Cry: "impact"                            BattleCryFx
##  Blade Storm: "impact" {n}                       BladeStormFx
##  Aegis: "impact", "burst" {p, x}                 AegisFx
##  Judgment: "impact" {ps}, "brand" {t}            JudgmentFx, HolyBrandsFx
##  Last Rites: "impact" {p}, "kill" {p}            LastRitesFx

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["s"]):
		"cleave": return HolySlamFx.play(h, ev)
		"nova": return HolyNovaFx.play(h, ev)
		"charge": return ChargeFx.play(h, ev)
		"cry": return BattleCryFx.play(h, ev)
		"k_whirl": return BladeStormFx.play(h, ev)
		"k_aegis": return AegisFx.play(h, ev)
		"k_judgment": return JudgmentFx.play(h, ev)
		"k_rites": return LastRitesFx.play(h, ev)
	return false

## Every frame, on the caster and on his puppet: his holy shaders warmed once per zone, the Charge's trail.
static func update(h: Hero, delta: float) -> void:
	if h.cls == "knight":
		HolyFx.warm(h)
	ChargeFx.update(h, delta)

static func clear(h: Hero) -> void:
	ChargeFx.clear(h)

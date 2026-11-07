class_name ChargeFx
extends RefCounted
## Charge's look (KnightCharge's events): "cast" a trail of light and dust that follows him for the dash (`update`, on
## the caster and on his puppet), "hit" {p, x: the first one} a radiant flash on each foe he smashes, "end" a seal and a
## ring of dust where he stops (HolyFx's charge pieces).

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"cast":
			h.fxs["charge"] = Skill.num("charge", "secs", 0.5)
			HolyFx.charge_start(h, root)
			SkillFx.snd(h, "charge_dash", -2.0)
		"hit":
			var p: Vector3 = ev["p"]
			var first := bool(ev.get("x", false))
			if first:
				Sfx.play_at("charge_impact", p, 0.0)
			HolyFx.charge_hit(h, root, p, first)
		"end":
			h.fxs.erase("charge")
			HolyFx.charge_end(h, root, h.global_position)
			SkillFx.shake(h, 0.25)
		_:
			return false
	return true

## The trail follows him for as long as the dash lasts (timing itself out if its end is lost).
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("charge"):
		if h.fxs.has("charge_trail"):
			HolyFx.charge_clear(h)
		return
	var left: float = float(h.fxs["charge"]) - delta
	if left <= 0.0:
		h.fxs.erase("charge")
		HolyFx.charge_clear(h)
		return
	h.fxs["charge"] = left
	HolyFx.charge_follow(h)

static func clear(h: Hero) -> void:
	h.fxs.erase("charge")
	HolyFx.charge_clear(h)

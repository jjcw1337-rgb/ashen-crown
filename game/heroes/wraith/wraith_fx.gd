class_name WraithFx
extends RefCounted
## The Wraith's look (docs/systems/effects.md): his skills' fx events, played the same on his own game and on his
## puppet on every partner's (SkillFx), each handed to its skill's own look (skills/<skill>/<skill>_fx.gd); what
## they share is SpiritFx (shared/spirit_fx.gd). Everything one-shot is parented to the zone's FX node; what rides
## the body (the spectral claws) hangs on the rig's hands. `update` runs what lingers (h.fxs: the claws growing with
## the rakes, the tether, the phantoms in flight, the night), `clear` takes it all away. Draws only: the rules are
## his skills' (Wraith, skills/).

## His colours (SpiritFx's): the cold cyan spirit-light, the violet of the dark, the pale core of a soul.
const SPIRIT := SpiritFx.SPIRIT
const VIOLET := SpiritFx.VIOLET
const PALE := SpiritFx.PALE
const NIGHT := SpiritFx.NIGHT

## The skills' events (SkillFx), to each skill's look.
static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["s"]):
		"rend": return SpectralRendFx.play(h, ev)
		"siphon": return SoulSiphonFx.play(h, ev)
		"step": return ShadowStepFx.play(h, ev)
		"grasp": return HauntingGraspFx.play(h, ev)
		"phantom": return PhantomAssaultFx.play(h, ev)
		"night": return EternalNightFx.play(h, ev)
		# a run's skills (Data.RUN_SKILLS)
		"r_deathmark": return DeathMarkFx.play(h, ev)
		"r_wail": return BansheeWailFx.play(h, ev)
		"r_reap": return ReapingCrescentFx.play(h, ev)
	return false

## Every frame after the pose (the caster's and the puppet's): the claws, the tether, the phantoms, the night.
static func update(h: Hero, delta: float) -> void:
	if not h.is_wraith():
		return
	SpiritFx.update_claws(h, delta)
	SoulSiphonFx.update(h, delta)
	PhantomAssaultFx.update(h, delta)
	EternalNightFx.update(h, delta)

## Everything of his that lingers is gone (death, a class change, a zone change).
static func clear(h: Hero) -> void:
	SoulSiphonFx.clear(h)
	EternalNightFx.clear(h)
	PhantomAssaultFx.clear(h)
	SpiritFx.clear_claws(h)

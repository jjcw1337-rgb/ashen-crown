class_name WyvernFx
extends RefCounted
## The Storm Wyvern's effects. Draws only; on the wyvern's own game and everyone else's copy of it. Its skills' looks
## are in their folders (skills/<skill>/<skill>_fx.gd): Storm Arc (the shared lightning, ArcFx, its wings crackling),
## Thunder Dive, Thunderhead and Gale Wings; `play`, `update` and `clear` hand their events on (SkillFx). Its flight
## (the dodge) and its wingbeats' dust are every dragon's (DragonFlight).

## Its lightning's palette: core, glow (ArcFx).
const ARC := [Color(0.92, 1.0, 0.98), Color(0.3, 0.9, 1.0)]

## One of its skills' events (SkillFx.play): true when it was drawn.
static func play(h: Hero, ev: Dictionary) -> bool:
	if not Wyvern.IDS.has(str(ev["s"])):
		return false
	match str(ev["s"]):
		"storm_arc": return StormArcFx.play(h, ev)
		"v_dive": return ThunderDiveFx.play(h, ev)
		"v_cloud": return ThunderheadFx.play(h, ev)
		"v_gale": return GaleWingsFx.play(h, ev)
	return false

## Every frame, on every hero (each look keeps its own state in Hero.fxs): the dive's height, the clouds' end.
static func update(h: Hero, delta: float) -> void:
	ThunderDiveFx.update(h, delta)
	ThunderheadFx.update(h, delta)

## Everything of its that lingers is let go.
static func clear(h: Hero) -> void:
	ThunderDiveFx.clear(h)
	ThunderheadFx.clear(h)

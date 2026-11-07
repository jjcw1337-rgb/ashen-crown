class_name GraveyardFx
extends RefCounted
## What Graveyard looks like, on every game (GraveyardSite draws the place): "rise" {g, r, x, n} tears the graveyard up
## out of the ground at g; "strike" {g, t: [[which of the dead, where it struck], ...]} has each of those dead lunge at
## where it struck; "end" {g} crumbles the dead and sinks the graves. It hurts nothing (Graveyard: the rules).

static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev.get("e", "")):
		"rise":
			var site := GraveyardSite.new()
			site.setup(h.game, ev["g"], float(ev.get("r", 6.0)), float(ev.get("x", 8.0)), int(ev.get("n", 4)))
			h.game.world.fx_root.add_child(site)
			site.global_position = ev["g"]
			SkillFx.snd(h, "graveyard_rise" if Sfx.bank.has("graveyard_rise") else "slam", -2.0, 0.8)
			SkillFx.shake(h, 0.35)
			return true
		"strike":
			var site := _site(h, ev["g"])
			if site != null:
				for s in ev.get("t", []):
					if s is Array and s.size() == 2:
						site.strike(int(s[0]), s[1])
			return true
		"end":
			var site := _site(h, ev["g"])
			if site != null:
				site.crumble()
			return true
	return false

## The graveyard standing at `g` (the newest one there).
static func _site(h: Hero, g) -> GraveyardSite:
	if not g is Vector3 or h.game.world == null:
		return null
	for n in h.game.world.fx_root.get_children():
		if n is GraveyardSite and not n.ending and (n as Node3D).global_position.distance_to(g) < 0.5:
			return n
	return null

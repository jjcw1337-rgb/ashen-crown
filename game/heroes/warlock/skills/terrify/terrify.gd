class_name Terrify
extends WarlockSpell
## Terrify ("w_terrify"): a shriek that freezes one foe in terror (a monster cowers, stunned; a player runs, through
## the server: WarlockHex.fear). Frightened foes take more from all her spells, so the fears' shared numbers live
## here. Its look: WarlockHarrowFx ("scream", "fear"). Codex "k": secs, and for every fear of hers: feared_more (%
## more from her spells), pvp_k (% of a fear's seconds a player gets), pvp_max (seconds, at most).

func targeted() -> bool:
	return true

func struck(e) -> void:
	hero.fx(id, "scream", {"t": [e]})
	hex().fear(id, e, val("secs", 1.5))

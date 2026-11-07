class_name WarlockCurse
extends WarlockSpell
## One of the Warlock's curses (Corruption, Unending Rot, Festering Hex, Leeching Curse, Reckoning): a targeted
## spell whose rules put a damage-over-time on the foe (WarlockHex.curse; recast, it refreshes). WarlockHex keeps
## every curse on every foe and ticks them; each curse says what its tick deals (`tick_amount`), what follows a tick
## (`ticked`) and what else it does every frame (`beat`). Codex "k": dmg (% of her spell power over the whole
## curse), secs, tick (seconds between ticks), and each curse's own.

func targeted() -> bool:
	return true

func struck(e) -> void:
	hex().curse(self, e)

## One tick of dot d: its share, and Lingering Rot's flat more.
func tick_amount(d: Dictionary) -> float:
	return float(d["per"]) + hero.talent("dot_flat")

## After a tick that dealt `dealt`.
func ticked(_d: Dictionary, _dealt: float) -> void:
	pass

## Every frame its dot is on a living foe.
func beat(_d: Dictionary, _delta: float) -> void:
	pass

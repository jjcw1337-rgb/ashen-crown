class_name LeechingCurse
extends WarlockCurse
## Leeching Curse ("w_leeching"): part of what each tick deals heals her. Codex "k": dmg, secs, tick, heal (% of a
## tick's damage).

func ticked(_d: Dictionary, dealt: float) -> void:
	hex().heal(id, dealt * (val("heal", 50.0) / 100.0))

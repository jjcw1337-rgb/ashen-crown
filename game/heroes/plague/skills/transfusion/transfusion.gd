class_name Transfusion
extends PlagueSkill
## G Transfusion ("transfusion"): the needle of his back apparatus in his arm: for a moment he takes less damage and
## moves slower, and is cleansed of slows, snares and Blight; damage soaked fills the tanks and heals him after (at
## most `cap` % of his life). Another skill ends it early. No CC immunity.
## It makes nothing his rules act on: it is all his own (his life, his statuses, his pace), kept on his own game.
## Its look: PlagueTransfusionFx ("on", "soak" {x: how full the tanks are}, "off" {x: what it heals}). Codex "k":
## cast_s, secs (Longer Transfusion adds to it), cut (% of each blow soaked), move (% of his pace), cap.

var trans := {}       # his game: {t, soaked}

func cast(_aim: Vector3) -> void:
	hero.atk_aim = hero.global_position
	hero._start_attack("pd_transfuse", id)
	hero.atk_dur = cast_secs(0.55)

func impact() -> void:
	var n := PvpStatus.cleanse(hero)
	hero.fx(id, "on")
	trans = {"t": val("secs", 2.0) + hero.talent("trans_dur"), "soaked": 0.0}
	if n > 0 and hero._mine():
		hero.game.ui.message("Cleansed", Color(0.7, 1.0, 0.6))

func _cap() -> float:
	return hero.max_life * (val("cap", 15.0) + hero.talent("trans_cap")) / 100.0

## Hero.take_hit asks: how much of this blow gets through? The rest fills the tanks.
func absorb(dmg: float) -> float:
	if trans.is_empty():
		return dmg
	var cut := dmg * (val("cut", 45.0) + hero.talent("trans_dr")) / 100.0
	trans["soaked"] = float(trans["soaked"]) + cut
	hero.fx(id, "soak", {"x": float(trans["soaked"]) / maxf(_cap(), 1.0)})
	return dmg - cut

## With the needle in his arm he moves slower (ClassSkills.pace).
func pace() -> float:
	return val("move", 70.0) / 100.0 if not trans.is_empty() else 1.0

func update(delta: float) -> void:
	if trans.is_empty():
		return
	trans["t"] = float(trans["t"]) - delta
	if float(trans["t"]) <= 0.0:
		_end()

## He used another skill before the window ran out: it ends now (what was soaked still heals).
func end_early() -> void:
	if not trans.is_empty():
		_end()

func _end() -> void:
	var heal_amt := minf(float(trans["soaked"]), _cap())
	trans = {}
	hero.fx(id, "off", {"x": heal_amt})
	if heal_amt > 0.0:
		hero.heal_pool += heal_amt

func clear() -> void:
	trans = {}

class_name BladeStorm
extends KnightSkill
## Blade Storm (a run's skill, "k_whirl"): he spins with the sword out, striking everything round him on each turn
## (Unending Spin, the talent "whirl_more": more turns). Every blow brands its foe for Judgment (HolyBrands). The
## turns are the rules' (`turns`), round wherever he is on each one. Its look: BladeStormFx ("impact" {n: the turns}).
## Codex "k": dmg (% of the weapon's blow, each turn), radius, spins, beat (seconds between turns), knock.

var turns := {}        # rules: {left: turns still to come, t: seconds to the next}

func cast(_aim: Vector3) -> void:
	hero._start_attack("swipe3", id)     # (its length: its codex "use")

func impact() -> void:
	var n := int(val("spins", 2.0)) + int(hero.talent("whirl_more"))
	hero.fx(id, "impact", {"n": n})
	make("whirl", {"n": n})

## The spin its rules turn: the first turn now, the rest a beat apart.
func made(kind: String, d: Dictionary) -> void:
	if kind != "whirl":
		return
	_turn()
	turns = {"left": int(d["n"]) - 1, "t": val("beat", 0.22)}

## Server: no more turns than his build gives.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "whirl":
		return false
	d["n"] = clampi(int(d.get("n", 1)), 1, int(val("spins", 2.0)) + int(hero.talent("whirl_more")))
	return true

func update(delta: float) -> void:
	if turns.is_empty():
		return
	if int(turns["left"]) <= 0 or hero.dead:
		turns = {}
		return
	turns["t"] = float(turns["t"]) - delta
	if float(turns["t"]) > 0.0:
		return
	turns["t"] = float(turns["t"]) + val("beat", 0.22)
	turns["left"] = int(turns["left"]) - 1
	_turn()

## One turn: everything round him.
func _turn() -> void:
	var h := hero
	for e in h.game.enemies_near(h.global_position, val("radius", 3.2)):
		if foe(e):
			h._hit_enemy(e, val("dmg", 70.0) / 100.0, val("knock", 0.3), id)

func died() -> void:
	turns = {}

func clear() -> void:
	turns = {}

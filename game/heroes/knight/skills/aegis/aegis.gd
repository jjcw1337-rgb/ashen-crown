class_name Aegis
extends KnightSkill
## Aegis (a run's skill, "k_aegis"): a holy ward worth a share of his life for its time (the run's buff "aegis": the
## ward's size, Hero.ward), and everything near turns on him (a monster's taunt). When the ward breaks or its time is
## up it bursts: everything near takes all it soaked (Bastion, the talent "aegis_pct": a bigger ward, and its burst
## bastion_k times as hard). The ward is his own game's (it owns his life, like the Warlock's shield): it raises it,
## watches it (`held`) and says when it bursts and for how much; the rules taunt and burst (on the match server, from
## its positions, its monsters turning on its copy of him). Its look: AegisFx ("impact", "burst" {p, x: soaked}).
## Codex "k": ward (% of his life), secs, radius (the taunt's and the burst's), taunt_s, bastion_k, cast_s.

var held := {}         # his own game: the ward up {ward0: what it held, t: seconds left}

func cast(_aim: Vector3) -> void:
	hero._start_attack("cast", id)
	hero.atk_dur = val("cast_s", 0.5) * Data.attack_pace(hero.cls)

func impact() -> void:
	var h := hero
	var secs := val("secs", 5.0)
	RunTalents.buff(h, "aegis", {"ward_bonus": val("ward", 35.0) + h.talent("aegis_pct")}, secs)
	h.ward = h.ward_max
	held = {"ward0": h.ward, "t": secs}
	h.fx(id, "impact")
	make("taunt", {"p": h.global_position})

## His own game, every frame: the ward broken or run out bursts for what it soaked.
func update(delta: float) -> void:
	if held.is_empty() or hero.puppet:
		return
	var h := hero
	held["t"] = float(held["t"]) - delta
	if float(held["t"]) > 0.0 and h.ward > 0.5:
		return
	var soaked := maxf(0.0, float(held["ward0"]) - h.ward) * (val("bastion_k", 2.0) if h.talent("aegis_pct") > 0.0 else 1.0)
	held = {}
	h.fx(id, "burst", {"p": h.global_position, "x": soaked})
	make("burst", {"p": h.global_position, "x": soaked})

## Its rules: the monsters near turn on him; the burst hurts everything near.
func made(kind: String, d: Dictionary) -> void:
	var h := hero
	match kind:
		"taunt":
			for e in h.game.enemies_near(d["p"], val("radius", 5.0)):
				if foe(e) and not PvpStatus.is_player(e):
					e.taunt = h
					e.taunt_t = val("taunt_s", 4.0)
		"burst":
			var amount := float(d["x"]) * h.buff_mult()
			for e in h.game.enemies_near(d["p"], val("radius", 5.0)):
				if foe(e):
					e.take_damage(0.0, amount, d["p"], 1.0, false)

## Server: where it has him, and no more soaked than his ward could hold.
func server_ok(kind: String, d: Dictionary) -> bool:
	if not near_him(d.get("p"), 0.0):
		return false
	if kind == "burst":
		var h := hero
		var most := h.max_life * (val("ward", 35.0) + h.talent("aegis_pct") + h.talent("ward_bonus") + float(h.stats.get("ward", 0))) / 100.0
		d["x"] = clampf(float(d.get("x", 0.0)), 0.0, most * val("bastion_k", 2.0))
		return true
	return kind == "taunt"

func died() -> void:
	held = {}

func clear() -> void:
	held = {}

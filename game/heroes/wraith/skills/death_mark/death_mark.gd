class_name DeathMark
extends WraithSkill
## Death Mark (a run's skill, "r_deathmark"): the foe nearest the pointer is marked. When the mark runs out it tears
## out a share of everything he dealt it meanwhile (Hero._hit_enemy adds to the mark's store), at least a floor of his
## average blow, as a soul he drinks back (Marked Soul: more, and sooner). The mark is made where his hits are
## decided. Its look: DeathMarkFx. Codex "k": secs (how long the mark lasts), share (% of the store torn out), least
## (% of his average blow, at the least), reach (metres from the pointer it finds its foe), drink (% of what it tears
## out that comes back to him as life).

var marks: Array = []       # the rules': {e: the foe, t: seconds left}

func cast(aim: Vector3) -> void:
	hero.atk_aim = aim
	start("siphon")

func impact() -> void:
	make("mark", {"at": hero.atk_aim})

## Server: a mark within its range of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "mark" and near_him(d.get("at"), reach_m(12.0) + 4.0)

## The foe nearest the point is marked (never a player's thing); everyone sees which.
func made(kind: String, d: Dictionary) -> void:
	if kind != "mark":
		return
	var h := hero
	var at: Vector3 = d["at"]
	var best = null
	var bd := val("reach", 3.5)
	for e in h.game.enemies_near(at, bd):
		var dist: float = e.global_position.distance_to(at)
		if foe(e) and e.pvp_obj == 0 and dist < bd:
			bd = dist
			best = e
	var secs := val("secs", 3.0)
	if best != null:
		best.set_meta("deathmark", {"h": h, "stored": 0.0})
		marks.append({"e": best, "t": secs})
	h.fx(id, "mark", {"p": at, "t": [best] if best != null else [], "x": secs})

## The marks running out: what each tears out of its foe.
func tick(delta: float) -> void:
	var h := hero
	for m in marks.duplicate():
		m["t"] = float(m["t"]) - delta
		var e = m["e"]
		if not is_instance_valid(e) or e.dead:
			marks.erase(m)
			continue
		if float(m["t"]) > 0.0:
			continue
		marks.erase(m)
		var rec: Dictionary = e.get_meta("deathmark", {})
		e.remove_meta("deathmark")
		var avg: float = (h.dmg_min + h.dmg_max) * 0.5
		var amount: float = maxf(float(rec.get("stored", 0.0)) * (val("share", 50.0) + h.talent("mark_pct")) / 100.0,
			avg * val("least", 150.0) / 100.0 * h.buff_mult())
		e.dmg_tint = SpiritFx.VIOLET
		blow(e, 0.0, amount, h.global_position, 0.6, true)
		e.dmg_tint = Color(0, 0, 0, 0)
		h.fx(id, "pop", {"p": e.global_position, "x": amount})
		h.gain_life(amount * val("drink", 15.0) / 100.0)

func clear() -> void:
	super()
	marks.clear()

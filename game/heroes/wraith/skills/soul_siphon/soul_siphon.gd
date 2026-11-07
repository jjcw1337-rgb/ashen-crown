class_name SoulSiphon
extends WraithSkill
## Soul Siphon ("siphon", E): cast2's reach: the hand thrust out hooks a tether into one foe, which stands rigid while
## the tether drains it, healing him part of what it takes, and is slowed after. It holds whatever he does next and
## breaks past its leash; a victim it kills gives up its soul to him (Long Grip: longer; Hungry Tether: more). The
## foe is picked on his own game; the tether is made where his hits are decided (`make_at`), and its rules drain it.
## Its look: SoulSiphonFx. Codex "k": secs (the hold), tick (seconds between drains), weapon and spirit (% of the
## weapon's average blow and of the spirit-light drained over the hold), heal (% of what it drains back to him),
## slow (%) and slow_s (seconds of it after the hold), leash (metres), soul (% of his life when a soul comes to him),
## pick (metres round the pointer it looks for its foe).

var victim = null           # the foe picked at the cast (his own game)
var tether := {}            # the rules': {victim, t: seconds held, tick: to the next drain, heal: life drained back}

## The foe it latches onto: the one nearest the aim point within its reach, else the first right ahead.
func pick(aim: Vector3):
	var h := hero
	var reach := reach_m(9.0)
	var best = null
	var bd := val("pick", 3.0)
	for e in h.game.enemies_near(aim, bd):
		var d: float = Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length()
		if foe(e) and d < bd and e.global_position.distance_to(h.global_position) <= reach:
			bd = d
			best = e
	if best == null:
		var p := h.aim_ahead(reach)
		for e in h.game.enemies_near(p, 0.5):
			if foe(e):
				best = e
				break
	return best

## A foe to latch onto, before anything is spent.
func can_cast(aim: Vector3) -> bool:
	if pick(aim) == null:
		hero.game.ui.message("No enemy in reach", Color(0.8, 0.8, 0.8))
		return false
	return true

func cast(aim: Vector3) -> void:
	victim = pick(aim)
	start("siphon")

## The latch: the tether bites into the foe picked at the cast (or the nearest one ahead now).
func impact() -> void:
	var h := hero
	var v = victim
	victim = null
	if v == null or not is_instance_valid(v) or v.dead:
		v = pick(h.aim_ahead(reach_m(9.0)))
	if v == null:
		if deals():
			let_go(false)
		return
	h.fx(id, "latch", {"t": [v], "x": hold()})
	make_at("latch", {"t": [v]})

## Seconds it holds (Long Grip: longer).
func hold() -> float:
	return val("secs", 2.5) + hero.talent("siphon_dur")

## Server: a foe within its reach of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "latch":
		return false
	var vs := foes(d)
	if vs.is_empty() or not near_him((vs[0] as Node3D).global_position, reach_m(9.0) + 4.0):
		return false
	d["t"] = [vs[0]]
	return true

## The tether: its victim stands rigid while its soul is pulled at (a boss shakes it off sooner), then is slowed.
func made(kind: String, d: Dictionary) -> void:
	if kind != "latch":
		return
	var vs := foes(d)
	if vs.is_empty():
		return
	var v = vs[0]
	var secs := hold()
	tether = {"victim": v, "t": 0.0, "tick": 0.05, "heal": 0.0}
	stun(v, secs)
	slow(v, secs + val("slow_s", 1.5), val("slow", 50.0) / 100.0)

## The hold: every tick the victim loses life (in cold light, no blood) and part of it comes back to him.
func tick(delta: float) -> void:
	if tether.is_empty():
		return
	var h := hero
	var v = tether["victim"]
	if v == null or not is_instance_valid(v) or v.dead or v.global_position.distance_to(h.global_position) > val("leash", 13.0) or h.dead:
		if v != null and is_instance_valid(v) and v.dead and not h.dead:
			# the soul leaves the body and comes to him
			h.fx(id, "soul", {"p": v.global_position + Vector3(0, 0.9 * v.height, 0)})
			heal_later(wisp_time(0), val("soul", 6.0))
		let_go(false)
		return
	tether["t"] = float(tether["t"]) + delta
	tether["tick"] = float(tether["tick"]) - delta
	var dur := hold()
	if float(tether["t"]) >= dur:
		let_go(true)
		return
	if float(tether["tick"]) > 0.0:
		return
	var every := val("tick", 0.25)
	tether["tick"] = every
	# its share of the weapon's average blow and of the spirit-light over the hold
	var per := (spirit(val("spirit", 200.0)) + (h.dmg_min + h.dmg_max) * 0.5 * val("weapon", 180.0) / 100.0) / (dur / every) * h.buff_mult() * h.dmg_mult(id)
	v.dmg_tint = Color(0.6, 0.9, 1.0)
	var dealt := blow(v, per, 0.0, h.global_position, 0.0, false)
	v.dmg_tint = Color(0, 0, 0, 0)
	h.fx(id, "tick")
	var heal := dealt * val("heal", 35.0) / 100.0
	h.gain_life(heal)
	tether["heal"] = float(tether["heal"]) + heal
	if h.ls > 0.0:
		h.gain_life(dealt * h.ls / 100.0)
	h.stats_changed.emit()

## The tether lets go: its hold is up (`spent`), its victim is lost, or he is cut short. Its look shows what it
## drained back to him.
func let_go(spent: bool) -> void:
	if tether.is_empty():
		return
	var heal := float(tether["heal"])
	tether = {}
	hero.fx(id, "end", {"x": spent, "n": int(heal)})

func clear() -> void:
	super()
	let_go(false)
	victim = null

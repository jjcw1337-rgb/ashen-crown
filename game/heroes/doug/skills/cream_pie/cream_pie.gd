class_name CreamPie
extends PieSkill
## Cream Pie ("pie"): a cream pie lobbed at the cursor (no further than its "range"); where it lands, the foe nearest
## it takes the splat and is Pied: a monster stunned a moment and slowed, a player's screen creamed and their aim
## help gone (Hero.take_hit "pied", through the server). The same foe can't be Pied again for a while, by any of his
## pies (PieSkill.pie_face keeps that here). Its look: CreamPieFx. Codex "k": dmg (% of the weapon's blow), flight
## (seconds in the air), radius (metres from where it lands to the foe it finds), pied_s and slow (% slower: a Pied
## monster), stun_s (the moment it's stunned first), lock_s (seconds before the same foe can be Pied again).

## Foes Pied by any of his pies, and when (instance id -> seconds): PieSkill.pie_face.
var pied := {}
var aim := Vector3.ZERO

func cast(at: Vector3) -> void:
	aim = at
	hero._start_attack("pie", id)

func impact() -> void:
	var h := hero
	var to := aim
	var off := to - h.global_position
	off.y = 0
	if off.length() > reach():
		to = h.global_position + off.normalized() * reach()
	var t := flight()
	h.fx(id, "throw", {"p": h.global_position + Vector3(0, 1.2, 0), "q": to, "x": t})
	make("pies", {"ps": PackedVector3Array([to]), "ts": PackedFloat32Array([t])})

func clear() -> void:
	super.clear()
	pied.clear()

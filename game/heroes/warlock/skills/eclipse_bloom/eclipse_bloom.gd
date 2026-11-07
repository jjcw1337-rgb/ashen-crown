class_name EclipseBloom
extends WarlockSpell
## Eclipse Bloom ("w_crowstorm", kept for saves and rites; the Fear ultimate): she blinks toward the pointer (her own
## game moves her) into a storm of void petals: every foe near where she lands is frightened, and for its time the
## storm hurts whatever is near her. She is held in place while she casts it. Its rules keep the storm (`storm`);
## its look is WarlockHarrowFx ("blink", "storm"). Codex "k": blink (metres at most), radius, secs, dmg (% of her
## spell power a beat), first and beat (seconds to the first beat and between them), fear_s.

var to := Vector3.ZERO     # her own game: where the cast was aimed
var storm := {}            # rules: {t: seconds left, tick: seconds to the next beat}

func cast(aim: Vector3) -> void:
	super.cast(aim)
	to = aim

func impact() -> void:
	_blink(to)
	var secs := val("secs", 5.0)
	hero.fx(id, "storm", {"x": secs, "r": val("radius", 5.0)})
	make("storm", {"p": hero.global_position})

## The blink (her own game: she moves; the look is the "blink" event).
func _blink(at: Vector3) -> void:
	var h := hero
	var d := at - h.global_position
	d.y = 0.0
	d = d.limit_length(val("blink", 8.0))
	var from := h.global_position
	var end: Vector3 = h.game.world.move(from, d, h.radius)
	end.y = h.game.world.height_at(end.x, end.z)
	h.fx(id, "blink", {"p": from, "q": end})
	h.global_position = end
	h.path = PackedVector3Array()
	h.moving = false
	h.target = null

## The storm, and the fright of everything near where she landed.
func made(kind: String, d: Dictionary) -> void:
	if kind != "storm":
		return
	storm = {"t": val("secs", 5.0), "tick": val("first", 0.25)}
	var hx := hex()
	for f in hero.game.enemies_near(d["p"], val("radius", 5.0)):
		if foe(f):
			hx.fear(id, f, val("fear_s", 1.0))

## Server: she lands within a blink of where it has her.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "storm" and d.get("p") is Vector3 and (d["p"] as Vector3).distance_to(hero.global_position) <= val("blink", 8.0) + 4.0

## Held in place while she casts it.
func rooted() -> bool:
	return hero.atk_t >= 0.0 and hero.atk_skill == id

func update(delta: float) -> void:
	if storm.is_empty():
		return
	storm["t"] -= delta
	storm["tick"] -= delta
	if storm["t"] <= 0.0:
		storm = {}
		return
	if storm["tick"] <= 0.0:
		storm["tick"] = val("beat", 0.5)
		var hx := hex()
		for e in hero.game.enemies_near(hero.global_position, val("radius", 5.0)):
			if not e.get("pvp_obj") and foe(e):
				hx.hit(e, hx.amount(id, val("dmg", 80.0) / 100.0, e), WarlockHex.SHADOW_TINT, true)

func clear() -> void:
	super.clear()
	storm = {}

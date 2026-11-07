class_name FrostVolleyRainFx
extends RefCounted
## Frost Volley's rain on every game: on its "impact" event the flight goes up and the storm gathers (FrostVolleyFx),
## then at the rain's own beat (the codex's numbers, the same the rules read) glacier arrows drop round the mark,
## each sticking in with its burst (FrostVolleyFx.strike). Draws only; the hits are FrostVolley's.

const PER_BEAT := 6        # arrows seen falling each beat

static func start(h: Hero, ev: Dictionary) -> void:
	var g: Vector3 = ev["p"]
	var r: float = float(ev.get("r", Skill.num("volley", "radius", 4.0)))
	var z := GroundZone.new(g, r, Skill.num("volley", "rain_s", 1.3), Skill.num("volley", "first", 0.25), Skill.num("volley", "beat", 0.2))
	z.data["fresh"] = true     # (made after this frame's rules moved theirs: it waits a frame to keep step)
	var rains: Array = h.fxs.get("volley_rain", [])
	rains.append(z)
	h.fxs["volley_rain"] = rains
	FrostVolleyFx.release(h, g, r)

static func update(h: Hero, delta: float) -> void:
	var rains: Array = h.fxs.get("volley_rain", [])
	for z in rains.duplicate():
		if z.data.has("fresh"):
			z.data.erase("fresh")
			continue
		if z.beat(delta):
			for k in PER_BEAT:
				var a := randf() * TAU
				var d: float = sqrt(randf()) * z.r
				var p: Vector3 = z.pos + Vector3(cos(a) * d, 0, sin(a) * d)
				p.y = h.game.world.height_at(p.x, p.z)
				FrostVolleyFx.strike(h, p)
		if z.left <= -z.grace:
			rains.erase(z)

static func clear(h: Hero) -> void:
	h.fxs.erase("volley_rain")

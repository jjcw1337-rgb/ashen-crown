class_name BrimstoneHurl
extends DemonSkill
## Brimstone Hurl (F, "hurl", ranged pressure; no cooldown, its "use" time is its limit, the Path of Exile way):
## "hurl" and "hurl2" alternate arms; the boulder lands at the aim after its flight (the mark on the ground shows
## where): its core Brands and burns, its edge hurts less, then it shatters into burning shards. Twin Boulders
## (hurl_twin) tears a second one loose with it, landing beside the first. Its look: BrimstoneHurlFx
## ("Shatterstone"). Codex "k": dmg and edge (% of the weapon's blow, core and edge), magma and edge_magma (% of his
## magma), knock and edge_knock, reach and min (metres), flight (seconds) and per_m (seconds more a metre), core and
## radius (metres), burn (% of his magma a second) and burn_s, shards, shard_r, shard and shard_magma (each shard's
## blow), twin_gap (metres) and twin_late (seconds).

var at := Vector3.ZERO      # where this throw lands
var alt := false            # the next throw is the other arm's
var boulders: Array = []    # in the air, its rules': {at, t}

func cast(aim: Vector3) -> void:
	var h := hero
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	at = h.global_position + to.limit_length(val("reach", 14.0))
	if to.length() < val("min", 3.0):
		at = h.global_position + h.aim_dir() * val("min", 3.0)
	at.y = h.game.world.height_at(at.x, at.z)
	var second := alt
	alt = not second
	start("hurl2" if second else "hurl")

func rooted() -> bool:
	return hero.atk_t >= 0.0 and hero.atk_skill == id

## The throw: seen at once; its rules keep the boulder until it lands.
func impact() -> void:
	var h := hero
	var hand := SkillFx.hand(h, true) if h.rig != null else h.global_position + Vector3(0, 1.8, 0)
	var flight := val("flight", 0.55) + at.distance_to(h.global_position) * val("per_m", 0.025)
	var n := 1 if h.atk_style == "hurl2" else 0
	h.fx(id, "throw", {"p": hand, "q": at, "x": flight, "n": n})
	make("boulder", {"at": at, "x": flight})
	if h.talent("hurl_twin") > 0.0:
		# Twin Boulders: a second one torn loose with it, landing beside the first (on the side of the throwing arm)
		var side := (at - h.global_position).cross(Vector3.UP) * Vector3(1, 0, 1)
		side = side.normalized() if side.length() > 0.1 else h.aim_dir().cross(Vector3.UP)
		var gap := val("twin_gap", 2.2)
		var at2: Vector3 = h.game.world.move(at, side * (gap if h.atk_style == "hurl" else -gap), 0.3)
		at2.y = h.game.world.height_at(at2.x, at2.z)
		var late := flight + val("twin_late", 0.12)
		h.fx(id, "throw", {"p": hand, "q": at2, "x": late, "n": n})
		make("boulder", {"at": at2, "x": late})

## Server: a boulder within his throw of where it has him, in the air no longer than his.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "boulder" or not d.get("at") is Vector3:
		return false
	var far := val("reach", 14.0) + val("twin_gap", 2.2) + 4.0
	if (d["at"] as Vector3).distance_to(hero.global_position) > far:
		return false
	d["x"] = clampf(float(d.get("x", 0.0)), 0.0, val("flight", 0.55) + far * val("per_m", 0.025) + val("twin_late", 0.12))
	return true

func made(kind: String, d: Dictionary) -> void:
	if kind == "boulder":
		boulders.append({"at": d["at"], "t": float(d["x"])})

func step(delta: float) -> void:
	for b in boulders.duplicate():
		b["t"] = float(b["t"]) - delta
		if float(b["t"]) <= 0.0:
			boulders.erase(b)
			_splash(b["at"])

## It lands: the core Branded and burning, the edge hurt less, four burning shards skittering out to catch whoever
## stands where they stop.
func _splash(p: Vector3) -> void:
	var h := hero
	var lit := []
	var r := val("radius", 2.6)
	for e in h.game.enemies_near(p, r + 0.8):
		var to: Vector3 = e.global_position - p
		to.y = 0
		var dd: float = to.length() - e.radius
		if dd > r or not foe(e):
			continue
		var core := dd <= val("core", 1.3)
		hit(e, val("dmg", 180.0) / 100.0 if core else val("edge", 90.0) / 100.0, val("knock", 1.4) if core else val("edge_knock", 0.6),
			magma(h, val("magma", 100.0) / 100.0 if core else val("edge_magma", 50.0) / 100.0))
		if is_instance_valid(e) and not e.dead and core:
			Demon.brands(h).mark(e)
			burn(e, magma(h, val("burn", 10.0) / 100.0) * h.dmg_mult(id), val("burn_s", 3.0))
			if not PvpStatus.is_player(e):
				lit.append(e)
	var stops := PackedVector3Array()
	var base := randf() * TAU
	var n := int(val("shards", 4.0))
	var sr := val("shard_r", 0.9)
	for i in n:
		var ang := base + TAU * float(i) / n + randf_range(-0.3, 0.3)
		var q := p + Vector3(cos(ang), 0, sin(ang)) * randf_range(1.8, 2.4)
		q = h.game.world.move(p, q - p, 0.2)
		q.y = h.game.world.height_at(q.x, q.z)
		stops.append(q)
		for e in h.game.enemies_near(q, sr + 0.6):
			var to: Vector3 = e.global_position - q
			to.y = 0
			if to.length() - e.radius <= sr and foe(e):
				hit(e, val("shard", 25.0) / 100.0, 0.0, magma(h, val("shard_magma", 15.0) / 100.0))
	h.fx(id, "splash", {"p": p, "ps": stops, "t": lit})
	SkillFx.hitstop(h, 0.04 if not lit.is_empty() else 0.0)

func clear() -> void:
	boulders.clear()

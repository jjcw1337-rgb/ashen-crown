class_name ThunderheadFx
extends RefCounted
## Thunderhead's look (Thunderhead): the ash cloud book darkened to a storm over the point ("form"; kept in Hero.fxs
## "drg_clouds", timing itself out), its bolts down into the foes ("bolt"), and gone ("end"). Draws only.

const STORM_TINT := Color(0.3, 0.33, 0.42)
const CLOUD_Y := 8.5

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var game = h.game
	match str(ev["e"]):
		"form":
			var p: Vector3 = ev["p"]
			var secs: float = float(ev.get("x", 4.0))
			var clouds: Array = h.fxs.get("drg_clouds", [])
			var c1 := DemonKitFx.smoke(root, p + Vector3(0, CLOUD_Y, 0), "ash", 11.0, secs + 1.0, true, STORM_TINT)
			var c2 := DemonKitFx.smoke(root, p + Vector3(1.5, CLOUD_Y + 0.6, -1.0), "ash", 8.0, secs + 1.0, true, STORM_TINT * 0.8)
			clouds.append({"p": p, "n": [c1, c2], "t": secs + 1.0})
			h.fxs["drg_clouds"] = clouds
			ArcFx.bolt(root, p + Vector3(0, CLOUD_Y, 0), p + Vector3(randf_range(-3, 3), CLOUD_Y - 2.0, randf_range(-3, 3)), 0.3, 0.8, WyvernFx.ARC, game)
			SkillFx.snd(h, "thunderhead", -2.0)
		"bolt":
			var q: Vector3 = ev["q"]
			var top: Vector3 = (ev["p"] as Vector3) + Vector3(randf_range(-2, 2), CLOUD_Y - 0.5, randf_range(-2, 2))
			ArcFx.bolt(root, top, q + Vector3(0, 1.0, 0), 0.25, 1.1, WyvernFx.ARC, game)
			ArcFx._struck(h, root, q + Vector3(0, 1.0, 0), WyvernFx.ARC)
			ArcFx._flash(root, q + Vector3(0, 2.0, 0), WyvernFx.ARC[1], 3.0, 0.18, 7.0)
			SkillFx.snd(h, "arc_zap", -5.0, randf_range(0.8, 0.95))
		"end":
			var p2: Vector3 = ev["p"]
			var clouds2: Array = h.fxs.get("drg_clouds", [])
			for i in range(clouds2.size() - 1, -1, -1):
				if (clouds2[i]["p"] as Vector3).distance_to(p2) < 0.5:
					_out(clouds2[i])
					clouds2.remove_at(i)
		_:
			return false
	return true

## Every frame (caster and everyone else's copy): a cloud whose end was lost goes by itself.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("drg_clouds"):
		return
	var clouds: Array = h.fxs["drg_clouds"]
	for i in range(clouds.size() - 1, -1, -1):
		clouds[i]["t"] = float(clouds[i]["t"]) - delta
		if float(clouds[i]["t"]) <= 0.0:
			_out(clouds[i])
			clouds.remove_at(i)

static func clear(h: Hero) -> void:
	for cl in h.fxs.get("drg_clouds", []):
		_out(cl)
	h.fxs.erase("drg_clouds")

static func _out(cl: Dictionary) -> void:
	for n in cl["n"]:
		if is_instance_valid(n):
			DemonKitFx.smoke_out(n, 0.8)

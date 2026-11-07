class_name WraithSwipe
extends WraithSkill
## His weapon swing ("attack") in a match where his skills run on the server (ServerRules.on): his game swings it
## and sends the swing, and the server's copy of him strikes with it, so its blows and the rites that ride them are
## decided there with the rest (Hero.decides). Out of a match his swing is everyone's (Hero._swipe_impact), whose arcs
## and weights these are.

## Each swing of the combo: [its share of the weapon's blow, half-angle in degrees, reach past his own, knockback].
const SWING := {"swipe1": [1.0, 70.0, 0.55, 0.2], "swipe2": [1.15, 70.0, 0.55, 0.2], "swipe3": [1.7, 181.0, 1.0, 0.9]}

func impact() -> void:
	var h := hero
	make("swipe", {"p": h.global_position, "d": h.aim_dir(), "s": h.atk_style})

## Server: a swing of his combo, from where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "swipe" or not SWING.has(str(d.get("s", ""))) or not near_him(d.get("p"), 4.0):
		return false
	d["d"] = flat(d.get("d"))
	return true

func made(kind: String, d: Dictionary) -> void:
	if kind != "swipe":
		return
	var h := hero
	var w: Array = SWING[str(d["s"])]
	var at: Vector3 = d["p"]
	var fwd: Vector3 = d["d"]
	var rng := h.reach() + float(w[2])
	var arc := cos(deg_to_rad(float(w[1])))
	var any := false
	for e in h.game.enemies_near(at, rng + 1.5):
		if not foe(e):
			continue
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius > rng:
			continue
		if to.length() < 0.5 or fwd.dot(to.normalized()) > arc:
			h._hit_enemy(e, float(w[0]), float(w[3]), "attack")
			h.fx("attack", "hit", {"p": e.global_position + Vector3(0, 1.1 * e.height, 0), "c": h.trail_col.lerp(Color(1.0, 0.75, 0.4), 0.5)})
			any = true
	if str(d["s"]) == "swipe3":
		h.fx("attack", "finisher", {"r": rng, "x": any})

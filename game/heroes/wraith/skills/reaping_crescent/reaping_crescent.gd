class_name ReapingCrescent
extends WraithSkill
## Reaping Crescent (a run's skill, "r_reap"): a great crescent of soul-fire sweeps out in front of him, and each
## foe it reaps heals him (Harvest of Souls: harder, more). It is seen at once ("impact") and made where his hits are
## decided, which shows the souls it reaped ("reaped"). Its look: ReapingCrescentFx. Codex "k": dmg (% of the
## weapon's blow), radius (metres), arc (half-angle, degrees), heal (% of his life for each it reaps), most (no more
## than this many count toward the heal).

func cast(aim: Vector3) -> void:
	var h := hero
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	h.atk_aim = h.global_position + (to.normalized() if to.length() > 0.3 else h.aim_dir()) * 3.0
	start("phantom")

func impact() -> void:
	var h := hero
	var yaw: float = h.rig.global_rotation.y
	h.fx(id, "impact", {"y": yaw})
	make("reap", {"p": h.global_position, "d": h.aim_dir(), "y": yaw})

## Server: from where it has him, a flat way.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "reap" or not near_him(d.get("p"), 4.0):
		return false
	d["d"] = flat(d.get("d"))
	d["y"] = float(d.get("y", 0.0))
	return true

func made(kind: String, d: Dictionary) -> void:
	if kind != "reap":
		return
	var h := hero
	var at: Vector3 = d["p"]
	var fwd: Vector3 = d["d"]
	var arc := cos(deg_to_rad(val("arc", 80.0)))
	var reaped := 0
	for e in h.game.enemies_near(at, val("radius", 5.0) + 0.6):
		if not foe(e):
			continue
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() < 1.0 or fwd.dot(to.normalized()) > arc:
			h._hit_enemy(e, val("dmg", 170.0) / 100.0, 0.6, id)
			reaped += 1
	if reaped > 0:
		h.gain_life(h.max_life * (val("heal", 2.0) + h.talent("reap_heal")) / 100.0 * mini(reaped, int(val("most", 6.0))))
		h.fx(id, "reaped", {"y": float(d.get("y", 0.0)), "n": reaped})

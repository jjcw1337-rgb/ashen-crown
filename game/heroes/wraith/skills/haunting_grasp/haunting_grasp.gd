class_name HauntingGrasp
extends WraithSkill
## Haunting Grasp ("grasp", F): the slam. Spectral hands burst out of the ground round the cursor, seize everything
## there, drag it inward and hold it fast (Eternal: longer; Legion: harder). Its blow is its own roll (`blow`, not
## Hero._hit_enemy). The hands are made where his hits are decided. Its look: HauntingGraspFx. Codex "k": dmg and
## spirit (% of the weapon's blow and of the spirit-light), radius (metres), hold (seconds held).

const DRAG := -1.4          # the blow's knockback: a pull toward the middle

var at := Vector3.ZERO      # where the hands burst out (his own game)

func cast(aim: Vector3) -> void:
	var h := hero
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	at = h.global_position + to.limit_length(reach_m(10.0))
	at.y = h.game.world.height_at(at.x, at.z)
	start("grasp")

func impact() -> void:
	hero.fx(id, "impact", {"p": at, "x": hold(), "r": val("radius", 3.5)})
	make("grasp", {"p": at})

## Seconds they are held (Eternal: longer).
func hold() -> float:
	return val("hold", 2.5) + hero.talent("grasp_hold")

## Server: hands within his reach of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "grasp" and near_him(d.get("p"), reach_m(10.0) + 4.0)

## Seized: the blow, then dragged toward the middle and held.
func made(kind: String, d: Dictionary) -> void:
	if kind != "grasp":
		return
	var h := hero
	var p: Vector3 = d["p"]
	var secs := hold()
	var any := false
	for e in h.game.enemies_near(p, val("radius", 3.5) + 0.3):
		if not foe(e):
			continue
		var dr := h.roll_damage(val("dmg", 110.0) / 100.0 * h.dmg_mult(id))
		var phys: float = float(dr["phys"]) + spirit(val("spirit", 90.0)) * h.buff_mult() * h.dmg_mult(id)
		var dealt := blow(e, phys, float(dr["fire"]), p, DRAG, bool(dr["crit"]))
		if h.ls > 0.0:
			h.gain_life(dealt * h.ls / 100.0)
		if is_instance_valid(e) and not e.dead:
			stun(e, secs)
		any = true
	if any:
		SkillFx.hitstop(h, 0.05)

## Mid-slam he stands.
func rooted() -> bool:
	return playing()

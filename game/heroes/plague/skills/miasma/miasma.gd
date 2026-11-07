class_name Miasma
extends PlagueSkill
## Miasma (a run's skill, "p_miasma"): the censer smashed at his feet, a wide cloud of plague: everything in it is
## poisoned and Blighted at once, and while the cloud hangs (Choking Miasma: it slows too). Its look: PlagueVialFx's
## "miasma" {p, r, x: seconds} (Pestilence Vial's burst and pool, as wide as the cloud). Codex "k": radius (Wider
## Miasma adds to it), secs.

var clouds: Array = []

func cast(_aim: Vector3) -> void:
	hero.atk_aim = hero.global_position
	hero._start_attack("pd_slam", id)

func impact() -> void:
	var at := ground(hero.global_position)
	var r := radius()
	hero.fx(id, "miasma", {"p": at, "r": r, "x": val("secs", 4.0)})
	make("miasma", {"g": at, "r": r})

func radius() -> float:
	return val("radius", 4.5) * (1.0 + hero.talent("miasma_r") / 100.0)

## Server: at his feet, no wider than his.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "miasma" or not near_him(d.get("g"), 4.0):
		return false
	d["r"] = clampf(float(d.get("r", 0.0)), 0.0, radius())
	return true

func made(kind: String, d: Dictionary) -> void:
	if kind != "miasma":
		return
	var at: Vector3 = d["g"]
	var r := float(d["r"])
	var secs := val("secs", 4.0)
	var c := cloud(at, r, secs, "toxic", PestilenceVial.vk("linger_s", 2.0))
	c.blight = "toxic"
	if hero.talent("miasma_slow") > 0.0:
		c.slow = 0.3        # Choking Miasma
	clouds.append(c)
	var a := aff()
	for e in foes(at, r):
		a.poison(e, "toxic", secs)
		a.blight(e, id)

func update(delta: float) -> void:
	for c in clouds.duplicate():
		if tick_cloud(c, delta):
			clouds.erase(c)

func clear() -> void:
	clouds.clear()

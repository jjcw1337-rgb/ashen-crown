class_name PestilenceVial
extends PlagueSkill
## Q Pestilence Vial ("toxic"): a lobbed glass vial (a landing ring for everyone); where it lands, a small hit and a
## contaminated pool that poisons (and Blights) what stands in it. Double Dose (a run's talent): a second vial beside
## the first; Volatile Reagents: the vial bursts for a share of his weapon's blow across the whole pool. Leech Jar
## (LeechJar) throws the same way.
## Its look: PlagueVialFx (the "throw" event {p: from, q: where it lands, r, n: the recipe's colour, x: the pool's
## seconds, k: 1 for a leech jar, b: it bursts}: every game flies its own vial and lands it on the same beat,
## `flight_s`). Codex "k": cast_s, radius, pool_s, linger_s (the poison after stepping out), hit_flat/lvl/wpn and
## hit_core (the landing's hit and the share of the pool it reaches), burst_wpn; and the poison's own numbers
## (PlagueAffliction).

var flights: Array = []      # vials in the air (DelayedArea: lands when its fuse runs out)
var clouds: Array = []       # pools (PlagueCloud)

## The vial's numbers (Leech Jar's land with the same).
static func vk(key: String, fallback: float) -> float:
	return Skill.num("toxic", key, fallback)

## How long a vial is in the air from `a` to `b` (the rules land it then; every game's look flies it that long).
static func flight_s(a: Vector3, b: Vector3) -> float:
	var dist := Vector2(b.x - a.x, b.z - a.z).length()
	return clampf(0.45 + dist * 0.03, 0.45, 0.8)

func cast(aim: Vector3) -> void:
	hero.atk_aim = within_range(aim, 12.0)
	hero._start_attack("pd_flask", id)
	hero.atk_dur = cast_secs(0.85)

func impact() -> void:
	var h := hero
	var from := hand()
	var to := ground(h.atk_aim)
	var r := pool_r()
	reveal_if_fogged()
	_throw(from, to, r)
	if h.talent("vial_twin") > 0.0:
		# Double Dose (a run's talent): a second vial beside the first
		var side := (to - from).cross(Vector3.UP).normalized() * (r * 1.3)
		_throw(from, ground(to + side), r)

func pool_r() -> float:
	return val("radius", 2.6) * (1.0 + hero.talent("cloud_size") / 100.0)

## One vial thrown: seen by everyone at once, flown by the rules.
func _throw(from: Vector3, to: Vector3, r: float) -> void:
	hero.fx(id, "throw", {"p": from, "q": to, "r": r, "n": PlagueVialFx.next_recipe(hero), "x": pool_secs(),
		"b": hero.talent("vial_burst") > 0.0})
	make("vial", {"p": from, "q": to, "r": r})

## How long its pool lasts.
func pool_secs() -> float:
	return val("pool_s", 3.5) + hero.talent("cloud_dur")

## The vial its rules fly (here, or on the match server's copy of him).
func made(kind: String, d: Dictionary) -> void:
	if kind != "vial":
		return
	var v := DelayedArea.new(d["q"], float(d["r"]), flight_s(d["p"], d["q"]))
	flights.append(v)

## Server: a vial from his hand, landing within the skill's range of where it has him, no wider than his.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "vial" or not near_him(d.get("p"), 4.0) or not near_him(d.get("q"), float(Data.skill_def(id).get("range", 12.0)) + 8.0):
		return false
	d["r"] = clampf(float(d.get("r", 0.0)), 0.0, pool_r())
	return true

func update(delta: float) -> void:
	for v in flights.duplicate():
		if v.tick(delta):
			flights.erase(v)
			land(v.pos, v.r)
	for c in clouds.duplicate():
		if tick_cloud(c, delta):
			clouds.erase(c)

## The vial lands: a small hit (on everything in the pool with Volatile Reagents), and the pool.
func land(at: Vector3, r: float) -> PlagueCloud:
	var h := hero
	var dmg := base(vk("hit_flat", 12.0), vk("hit_lvl", 1.65), vk("hit_wpn", 0.24), "toxic")
	var burst := h.talent("vial_burst")
	if burst > 0.0:
		# Volatile Reagents (a run's talent): the vial bursts for a share of his weapon's blow across the whole pool
		dmg += (h.dmg_min + h.dmg_max) * vk("burst_wpn", 0.5) * h.buff_mult() * burst / 100.0 * h.dmg_mult("toxic")
	for e in foes(at, r * (vk("hit_core", 0.6) if burst <= 0.0 else 1.0)):
		damage(e, dmg, at, true)
	var c := cloud(at, r, pool_secs(), "toxic", vk("linger_s", 2.0))
	c.blight = "toxic"
	clouds.append(c)
	return c

func clear() -> void:
	flights.clear()
	clouds.clear()

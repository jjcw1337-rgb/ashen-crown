class_name PratfallSlide
extends Skill
## Pratfall Slide ("slide"): a honking belly-slide the way he faces. His own game carries him along it (his feet are
## the slide's); its rules strike each foe he passes once, shoving it aside, from where they have him (here, or on
## the match server's copy of him). Its look: DougFx ("honk"). Codex "k": dmg (% of the weapon's blow), len (metres),
## radius (metres round him that he strikes), knock.

## His own game: the slide carrying him {"from", "dir"}.
var slide := {}
## Its rules: the slides striking what he passes {"t": seconds left, "hit": the foes struck}.
var sweeps: Array = []

func cast(_aim: Vector3) -> void:
	var h := hero
	h._start_attack("slide", id)
	slide = {"from": h.global_position, "dir": h.aim_dir()}
	# as long as the move (its data's use time, which Hero sets once this returns: SkillSpec.apply_timing)
	var dur: float = SkillSpec.use_time(h, id) if SkillSpec.of(id).has("use") else h.atk_dur
	make("slide", {"p": h.global_position, "d": h.aim_dir(), "x": dur})

func impact() -> void:
	hero.fx(id, "honk", {"p": hero.global_position, "d": slide.get("dir", hero.aim_dir())})

func made(kind: String, d: Dictionary) -> void:
	if kind == "slide":
		sweeps.append({"t": float(d["x"]), "hit": {}})

## Server: a slide from where it has him, no longer than the move.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "slide" or not d.get("p") is Vector3:
		return false
	if (d["p"] as Vector3).distance_to(hero.global_position) > 4.0:
		return false
	d["x"] = clampf(float(d.get("x", 0.0)), 0.0, 2.0 * float(Data.skill_def(id).get("use", 0.7)))
	return true

## Mid-slide his feet are the slide's.
func rooted() -> bool:
	return hero.atk_skill == id and hero.atk_t >= 0.0

func update(delta: float) -> void:
	var h := hero
	var own := not h.puppet
	var going := own and h.atk_skill == id and h.atk_t >= 0.0
	if not slide.is_empty():
		if going:
			_carry()
		else:
			slide = {}
	# what he passes is struck once (his own game: while the move lasts; the server's copy: for its length)
	for sw in sweeps.duplicate():
		sw["t"] = float(sw["t"]) - delta
		if (own and not going) or (not own and float(sw["t"]) < 0.0):
			sweeps.erase(sw)
			continue
		for e in h.game.enemies_near(h.global_position, val("radius", 1.3)):
			if not foe(e):
				continue
			var k := str(e.get_instance_id())
			if not (sw["hit"] as Dictionary).has(k):
				sw["hit"][k] = true
				h._hit_enemy(e, val("dmg", 90.0) / 100.0, val("knock", 3.0), id)

## Along its line, eased out (his own game: he is where the slide has him).
func _carry() -> void:
	var h := hero
	var a := h.atk_t / maxf(h.atk_dur, 0.01)
	var want: Vector3 = slide["from"] + (slide["dir"] as Vector3) * val("len", 7.0) * smoothstep(0.08, 0.75, a)
	var step := want - h.global_position
	step.y = 0
	h.global_position = h.game.world.move(h.global_position, step, h.radius)

func died() -> void:
	slide = {}
	sweeps.clear()

func clear() -> void:
	slide = {}
	sweeps.clear()

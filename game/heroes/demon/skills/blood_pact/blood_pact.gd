class_name BloodPact
extends DemonSkill
## Blood Pact (a run's skill, "d_pact"): he pays a share of his life to the pit for a while of more damage and life
## from the damage he deals (Blood Price: more damage). His game pays the life (it keeps it); the buff is his there
## and on the match server's copy of him too, whose blows it powers (its life steal comes back to his game). Its
## look: DemonFx. Codex "k": cost (% of his life), secs, dmg (% more damage), ls (% of the damage dealt healed).

var last := -100.0     # the server's copy: when it last took a pact (one a cooldown)

func cast(_aim: Vector3) -> void:
	start("wrath_stomp", 0.8)

func impact() -> void:
	var h := hero
	h.life = maxf(1.0, h.life - h.max_life * val("cost", 15.0) / 100.0)
	_buff()
	h.fx(id, "impact", {"x": val("secs", 8.0)})
	if not deals():
		make("pact", {})

func _buff() -> void:
	RunTalents.buff(hero, "blood_pact", {"dmg": val("dmg", 35.0) + hero.talent("pact_pow"), "ls": val("ls", 6.0)}, val("secs", 8.0))

## Server: a pact for a run that has it, no more often than its cooldown.
func server_ok(kind: String, _d: Dictionary) -> bool:
	var h := hero
	return kind == "pact" and h.run != null and h.anim_time - last >= h.skill_cd(id) - 1.0

func made(kind: String, _d: Dictionary) -> void:
	if kind == "pact":
		last = hero.anim_time
		_buff()

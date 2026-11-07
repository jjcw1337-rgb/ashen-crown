class_name FelCovenant
extends WarlockSpell
## Fel Covenant ("covenant"): the class's battle buff (Hero.buff_t: more damage) for its time, while Drain Life forks
## further and heals more. Her own game takes it at once; when her skills' rules run on the match server its copy of
## her is told too ("pact"), so its Drain Life forks and its spells hit as hard as hers. Its look: WarlockFx
## ("impact"); her body glows with it (WarlockSkills.posed). Codex "k": secs, forks (Drain Life's, under it), heal_k
## (times Drain Life's healing), cast_s.

var left := 0.0            # seconds of the covenant left (her own game; on the server's copy, what she told it)

func cast(_aim: Vector3) -> void:
	hero._start_attack("cast", id)
	hero.atk_dur = val("cast_s", 0.6) * Data.attack_pace(hero.cls)

func impact() -> void:
	_pact()
	hero.fx(id, "impact")
	if not deals():
		make("pact", {})

func _pact() -> void:
	hero.buff_t = val("secs", 12.0) + hero.talent("buff_dur")
	left = hero.buff_t

func made(kind: String, _d: Dictionary) -> void:
	if kind == "pact":
		_pact()

func server_ok(kind: String, _d: Dictionary) -> bool:
	return kind == "pact"

func active() -> bool:
	return left > 0.0

func update(delta: float) -> void:
	left = maxf(0.0, left - delta)
	if hero.puppet:
		hero.buff_t = left      # (the server's copy of her: nothing else counts its buff down)

func clear() -> void:
	super.clear()
	left = 0.0

class_name BoneBolt
extends Skill
## Bone Bolt ("bone_bolt", his right mouse): a shard of bone hurled from his hand toward the pointer. It strikes the
## first foe it meets and flies on through to one more (codex "pierce": how many it passes through), and ends at a
## wall or the end of its range. Its rules fly the shards (`shards`, plain Missiles); its look (BoneBoltFx) flies its
## own copy of each from the "loose" event, so what is seen and what hits agree. Codex "k": dmg (% of the weapon's
## blow), speed (metres a second; it flies its codex range), pierce.

var shards: Array = []      # rules: Missiles in flight, each with data {"hits": foes struck so far}

func cast(_aim: Vector3) -> void:
	hero._start_attack("bone_bolt", id)

## The shard leaves his hand toward the pointer as it was when he cast.
func impact() -> void:
	var h := hero
	var dir := h.aim_dir()
	var from := h.global_position + Vector3(0, 1.3, 0) + dir * 0.6
	h.fx(id, "loose", {"p": from, "d": dir})
	make("shard", {"p": from, "d": dir})

func made(kind: String, d: Dictionary) -> void:
	if kind != "shard":
		return
	shards.append(flight(d["p"], d["d"]))

## A shard's flight, the same for the rules and the look.
static func flight(from: Vector3, dir: Vector3) -> Missile:
	var m := Missile.new(from, (dir * Vector3(1, 0, 1)).normalized())
	m.speed = Skill.num("bone_bolt", "speed", 26.0)
	m.left = float(Data.skill_def("bone_bolt").get("range", 16.0))
	m.pierce = true
	m.data = {"hits": 0}
	return m

## Server: a shard from his hand where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	if kind != "shard" or not (d.get("p") is Vector3 and d.get("d") is Vector3):
		return false
	d["d"] = (d["d"] as Vector3).normalized()
	return (d["p"] as Vector3).distance_to(hero.global_position) <= 4.0

func update(delta: float) -> void:
	var pierce := int(val("pierce", 1.0))
	for m in shards.duplicate():
		m.step(hero.game, delta, foe, func(e):
			hero._hit_enemy(e, val("dmg", 110.0) / 100.0, 0.08, id)
			m.data["hits"] = int(m.data["hits"]) + 1
			if int(m.data["hits"]) > pierce:
				m.done = true)
		if m.done:
			shards.erase(m)

func clear() -> void:
	shards.clear()

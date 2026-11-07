class_name DreadTotem
extends WarlockSpell
## Dread Totem ("w_effigy", kept for saves and rites): she plants a totem toward the pointer (no further than its
## range); for its time it frightens the first few foes to come near it, once each. Its rules keep each totem
## (`totems`); its look (WarlockHarrowFx "plant", "caw", "gone"; the model dread_totem.glb here) is the idol. Codex
## "k": secs, rite_s (seconds more for each second of Haunting), radius, charges (foes it frightens), fear_s, first and
## beat (seconds to its first look round and between them).

var totems: Array = []     # rules: [{p, t: seconds left, left: charges, check, hit: foes it has frightened}]

func impact() -> void:
	var h := hero
	var to := h.atk_aim - h.global_position
	to.y = 0.0
	var at := h.global_position + to.limit_length(reach())
	at.y = h.game.world.height_at(at.x, at.z)
	h.fx(id, "plant", {"p": at, "x": _secs()})
	make("totem", {"p": at})

func _secs() -> float:
	return val("secs", 8.0) + hero.talent("fear_dur") * val("rite_s", 4.0)

func made(kind: String, d: Dictionary) -> void:
	if kind == "totem":
		totems.append({"p": d["p"], "t": _secs(), "left": int(val("charges", 3.0)), "check": val("first", 0.3), "hit": {}})

## Server: a totem within her reach of where it has her.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "totem" and d.get("p") is Vector3 and (d["p"] as Vector3).distance_to(hero.global_position) <= reach() + 4.0

func update(delta: float) -> void:
	if totems.is_empty():
		return
	var h := hero
	for ef in totems.duplicate():
		ef["t"] -= delta
		ef["check"] -= delta
		if ef["t"] <= 0.0:
			totems.erase(ef)
			h.fx(id, "gone", {"p": ef["p"]})
			continue
		if ef["check"] > 0.0 or ef["left"] <= 0:
			continue
		ef["check"] = val("beat", 0.2)
		var caught := []
		for e in h.game.enemies_near(ef["p"], val("radius", 4.0)):
			if ef["left"] <= 0:
				break
			var k: int = e.get_instance_id()
			if ef["hit"].has(k) or e.get("pvp_obj") or not foe(e):
				continue
			ef["hit"][k] = true
			ef["left"] -= 1
			caught.append(e)
		if not caught.is_empty():
			h.fx(id, "caw", {"p": ef["p"], "t": caught})
			var hx := hex()
			for e in caught:
				hx.fear(id, e, val("fear_s", 1.0))

func clear() -> void:
	super.clear()
	totems.clear()

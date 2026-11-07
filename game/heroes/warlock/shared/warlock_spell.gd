class_name WarlockSpell
extends Skill
## A skill of the Warlock's (docs/content/skills.md): what all of hers share. Her spells hit with her spell power
## (WarlockHex.spell), more on a frightened or bound foe; the targeted ones turn to the foe nearest the pointer as the
## cast begins and, on the cast's impact frame, `make` an "at" with where that foe stands, so her rules (here, or on the
## match server's copy of her) strike whatever foe is there (`struck`). Life and mana her rules give her (a leech, the
## feast, Dread Harvest) come back through `give` to her own game, where WarlockHex takes them.

## How near the pointer a foe counts as the one aimed at (aim help).
const PICK_R := 3.0
## How far from the point a targeted spell's rules look for its foe (the foe has moved a little on the server).
const AT_R := 2.0

## Her own game: the foe the cast turned to (its impact goes for it).
var aimed = null

## Her shared state (curses, fears, the shield): WarlockHex, first in her kit.
func hex() -> WarlockHex:
	return WarlockSkills.hex(hero)

## A targeted spell: needs a foe in reach to cast, and strikes it on the impact frame.
func targeted() -> bool:
	return false

## Its reach (its codex "range").
func reach() -> float:
	return float(Data.skill_def(id).get("range", 12.0))

static func alive(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead

## The foe nearest the pointer (within PICK_R of it and `r` of her), else the nearest to her within `r`.
func pick(aim: Vector3, r: float):
	var h := hero
	var best = null
	var bd := PICK_R
	for e in h.game.enemies_near(aim, PICK_R):
		if e.get("pvp_hidden") or e.get("pvp_obj") or not foe(e):
			continue
		var d: float = Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length()
		if d < bd and e.global_position.distance_to(h.global_position) <= r:
			bd = d
			best = e
	if best != null:
		return best
	bd = r
	for e in h.game.enemies_near(h.global_position, r):
		if e.get("pvp_hidden") or e.get("pvp_obj") or not foe(e):
			continue
		var d: float = e.global_position.distance_to(h.global_position)
		if d < bd:
			bd = d
			best = e
	return best

## Rules: the foe standing at `at` (a targeted spell's "at"), or null.
func foe_at(at: Vector3):
	var best = null
	var bd := AT_R
	for e in hero.game.enemies_near(at, AT_R):
		if e.get("pvp_obj") or not foe(e):
			continue
		var d: float = Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length()
		if d < bd:
			bd = d
			best = e
	return best

func can_cast(aim: Vector3) -> bool:
	if targeted() and pick(aim, reach()) == null:
		hero.game.ui.message("No enemy in reach", Color(0.8, 0.8, 0.8))
		return false
	return true

func cast(aim: Vector3) -> void:
	hero._start_attack("cast", id)
	if targeted():
		aimed = pick(aim, reach())
		if aimed != null:
			hero._face(aimed.global_position - hero.global_position)

## The impact frame: a targeted spell goes for the foe it turned to (or, gone, the one nearest the aim).
func impact() -> void:
	if not targeted():
		return
	var e = aimed
	aimed = null
	if e != null and not alive(e):
		e = pick(hero.atk_aim, reach() + 2.0)
	if e != null:
		make("at", {"at": (e as Node3D).global_position})

## A targeted spell's foe, found by its rules where its impact said.
func made(kind: String, d: Dictionary) -> void:
	if kind == "at":
		var e = foe_at(d["at"])
		if e != null:
			struck(e)

## Server: a targeted spell's foe within its reach of where it has her.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "at" and targeted() and d.get("at") is Vector3 and (d["at"] as Vector3).distance_to(hero.global_position) <= reach() + 4.0

## What a targeted spell does to its foe (its rules).
func struck(_e) -> void:
	pass

## Her own game takes what her rules gave her (WarlockHex: life, and Dread Harvest's mana and time).
func given(kind: String, data: Dictionary) -> void:
	hex().take(kind, data)

func clear() -> void:
	aimed = null

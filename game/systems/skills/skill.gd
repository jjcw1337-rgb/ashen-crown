class_name Skill
extends RefCounted
## One skill of one hero: its rules and its own state (docs/content/skills.md). A hero's skills script keeps one per
## skill id in `Hero.kit`, made the first time it's needed, and hands the ClassSkills calls on to it. It never
## draws: what is seen is an fx event (`hero.fx`), drawn by the skill's look. It runs only on the hero's own game,
## never on a partner's copy of him, so a server can run it too.

var id: String
var hero: Hero

func _init(h: Hero, skill_id: String) -> void:
	hero = h
	id = skill_id

## Its number from its codex entry's "k" (data/codex/heroes/<hero>.json: the skill's numbers, as a rite's "k" are
## its), else the fallback.
func val(key: String, fallback: float) -> float:
	var k = Data.skill_def(id).get("k", {})
	return float(k.get(key, fallback)) if k is Dictionary else fallback

## Checks before the mana and the cooldown are spent (shows its own message on false).
func can_cast(_aim: Vector3) -> bool:
	return true

## Starts it: usually hero._start_attack(style, id).
func cast(_aim: Vector3) -> void:
	pass

## The attack's impact frame (the bow's release).
func impact() -> void:
	pass

## Every frame on the hero's own game.
func update(_delta: float) -> void:
	pass

## Holds the hero in place right now.
func rooted() -> bool:
	return false

## What ends when the hero dies.
func died() -> void:
	pass

## Drops everything of its (a class change, a new character, a zone change).
func clear() -> void:
	pass

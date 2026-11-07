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
	return num(id, key, fallback)

## The same for any skill, where there is no object to ask (its look, on every game).
static func num(skill_id: String, key: String, fallback: float) -> float:
	var k = Data.skill_def(skill_id).get("k", {})
	return float(k.get(key, fallback)) if k is Dictionary else fallback

## Its rules run here: on the hero's own game, except in a match where they run on the server (ServerRules), and on
## the server's copy of a player whose skills run there.
func deals() -> bool:
	return not ServerRules.on(hero) or hero.game.net.server

## Makes what its rules act on (an arrow, a rain, a sigil): here when its rules run here (`made`), else it goes to
## the match server, whose copy of the player makes it (ServerRules.received).
func make(kind: String, data: Dictionary) -> void:
	if deals():
		made(kind, data)
	else:
		hero.game.net.send_skill_make(id, kind, data)

## What `make` makes: the skill's own rule state (its Missiles, GroundZones, DelayedAreas...).
func made(_kind: String, _data: Dictionary) -> void:
	pass

## Server: does what a player's game says it made add up (near where the server has them, within the skill's
## reach and numbers)? Nothing is made otherwise.
func server_ok(_kind: String, _data: Dictionary) -> bool:
	return true

## A foe its rules may strike: alive, and not its own player's stand-in (the server keeps one for every player).
func foe(e) -> bool:
	return not e.dead and not (int(e.get("pvp_pid")) > 0 and int(e.pvp_pid) == hero.peer_id)

## Checks before the mana and the cooldown are spent (shows its own message on false).
func can_cast(_aim: Vector3) -> bool:
	return true

## Starts it: usually hero._start_attack(style, id).
func cast(_aim: Vector3) -> void:
	pass

## The attack's impact frame (the bow's release).
func impact() -> void:
	pass

## A free copy of it from elsewhere (a rite: Phoenix Quiver's free Fire Arrow): no mana, no cooldown, no
## animation. True if it has one.
func free_cast(_aim: Vector3) -> bool:
	return false

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

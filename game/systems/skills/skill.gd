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

## What its rules give its own hero (life back, mana, a cooldown cut): at once where the hero is played; from the
## match server's copy of a player, it goes to that player's game (ServerRules.give, through Net.tell_self), whose own
## copy of the skill takes it (`given`). The rules never touch the life or mana of the server's copy: the player's
## game owns them. (A plain heal from a hero's blows is Hero.gain_life; this is for a skill's own ways with it.)
func give(kind: String, data: Dictionary) -> void:
	if hero.puppet and hero.game != null and hero.game.net != null and hero.game.net.server:
		ServerRules.give(hero, id, kind, data)
	else:
		given(kind, data)

## What `give` gives, on the hero's own game.
func given(_kind: String, _data: Dictionary) -> void:
	pass

## A foe its rules may strike: alive, and not a stand-in for its own player or their side (the server keeps one for
## every player: ServerRules.friend).
func foe(e) -> bool:
	return not e.dead and not ServerRules.friend(hero, e)

# ---------------------------------------------------------------- foes the player's game picked
## A foe as every game in a match names it (SkillFx.encode's ids: a monster's net id, minus a player's id for their
## stand-in); 0 outside a match or co-op.
func net_id(e) -> int:
	var net = hero.game.net
	if e == null or net == null or not net.active:
		return 0
	return -int(e.pvp_pid) if int(e.get("pvp_pid")) > 0 else int(e.net_id)

## Makes what its rules act on, aimed at foes its game picked (`d["t"]`, nodes here): in a match they go to the server
## as the ids every game shares, and `named_foes` finds the server's own monsters and stand-ins for them.
func make_aimed(kind: String, d: Dictionary) -> void:
	if deals():
		made(kind, d)
		return
	var w := d.duplicate()
	w["t"] = SkillFx.encode(hero.game.net, {"t": d.get("t", [])})["t"]
	hero.game.net.send_skill_make(id, kind, w)

## The foes a `make_aimed` named that are still there and still foes: nodes here, or the shared ids on the server.
func named_foes(d: Dictionary) -> Array:
	var out := []
	var ids = d.get("t", [])
	if not (ids is Array or ids is PackedInt64Array):
		return out
	for x in ids:
		var e = ServerRules.foe_of(hero.game, int(x)) if (x is int) else x
		if e != null and is_instance_valid(e) and e is Enemy and foe(e):
			out.append(e)
	return out

## The first of them, or null.
func named_foe(d: Dictionary):
	var f := named_foes(d)
	return f[0] if not f.is_empty() else null

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

## Runs after the hero's other skills each frame (what ticks on what they laid: the Plague Doctor's poison).
func late() -> bool:
	return false

## Every frame, a hero's skill objects (Hero.kit), the late ones last. Run once per hero where its rules run: its own
## game (ClassSkills.update) or the match server's copy of it (ServerRules.update).
static func update_kit(h, delta: float) -> void:
	for sk in h.kit.values():
		if not sk.late():
			sk.update(delta)
	for sk in h.kit.values():
		if sk.late():
			sk.update(delta)

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

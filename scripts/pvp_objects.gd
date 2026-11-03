class_name PvpObjects
extends RefCounted
## Battlegrounds PvP: things a player makes that the other players can break, the counterplay the Plague Doctor's
## kit was designed with: his Corpse Bloom, his vat while he cranks it (broken = the experiment fails) and the creature
## out of it (killed = the quarantine ends). Each counts blows, not damage: `HITS` blows break it, every player's
## blows counting at most once per `GAP` seconds, so a poison tick or burning ground counts like a slow swing and the
## numbers never need balancing against anyone's damage.
##
## The owner's game owns the count. On every other client the owner's ghost (`Plague.ghost`) shows the thing and puts
## an invisible stand-in `Enemy` on it (`proxy`: `pvp_obj` = its id in the owner's game, `pvp_owner` = his peer id), so
## any swing, arrow or spell that hits monsters hits it, and the pointer picks it with its name and blows left in the
## target bar. A blow on a stand-in (`struck`, from `Enemy.take_damage`) goes `Net.sv_pvp_obj_hit` ->
## `Battlegrounds.pvp_obj_hit` (the attacker alive, within `REACH` of the thing where the server's own ghost of the
## owner has it, `where`, and his blows on it at most one per GAP, `allow`) -> `Net.cl_pvp_obj_hit` -> the owner's
## `Plague.obj_hit`, which counts it and sends the blows left to everyone (`"obj|id|left"`): every game flinches it,
## the stand-ins take the new count and the last one breaks it on every game at once. Co-op partners never get stand-ins (`Game.bg_mode` only), and the server never
## makes any. Stand-ins of a player who left or died are dropped by `Battlegrounds.sync_proxies` (`prune`).

const HITS := {"bloom": 3, "vat": 3, "creature": 4}
const NAMES := {"bloom": "Corpse Bloom", "vat": "Plague Vat", "creature": "The Experiment"}
## the click and hit size of each (radius, and height as `Enemy.height`: its top is 1.8x that)
const SIZE := {"bloom": [0.75, 1.0], "vat": [0.6, 0.75], "creature": [0.55, 0.85]}
const GAP := 0.6
const REACH := 25.0
## a stand-in goes by itself this long after it was made if its end never arrived
const MAX_LIFE := 14.0

## A stand-in for another player's thing on this client, or null where there should be none (not the Battlegrounds,
## the server, no id).
static func proxy(g: Node, owner: Hero, oid: int, kind: String, left: int, at: Vector3) -> Enemy:
	if g == null or not bool(g.get("bg_mode")) or g.net == null or g.net.server or g.world == null or oid <= 0 or owner == null:
		return null
	var e := Enemy.new()
	e.pvp_obj = oid
	e.pvp_owner = owner.peer_id
	g.world.enemies_root.add_child(e)
	e.global_position = at
	e.setup(g, "zombie", 1)
	var sz: Array = SIZE.get(kind, [0.6, 0.8])
	e.radius = float(sz[0])
	e.height = float(sz[1])
	e.max_life = float(HITS.get(kind, 3))
	e.life = clampf(float(left), 0.0, e.max_life)
	var who := ""
	if g.net.players.has(owner.peer_id):
		who = str(g.net.players[owner.peer_id].get("name", ""))
	e.display_name = "%s (%s)" % [NAMES.get(kind, kind), who] if who != "" else str(NAMES.get(kind, kind))
	e.set_meta("pvp_kind", kind)
	e.set_meta("pvp_until", Time.get_ticks_msec() / 1000.0 + MAX_LIFE)
	e.rig.visible = false
	return e

## The stand-in's count of blows left (from the owner's "obj" event), or it goes when broken.
static func set_left(e, left: int) -> void:
	if e == null or not is_instance_valid(e):
		return
	(e as Enemy).life = maxf(float(left), 0.0)
	if left <= 0:
		drop(e)

## Keeps a stand-in on its thing (every frame on the ghost: a skill that pulls or throws monsters moves it too).
static func keep_on(e, at: Vector3) -> void:
	if e != null and is_instance_valid(e):
		(e as Node3D).global_position = at

static func drop(e) -> void:
	if e != null and is_instance_valid(e):
		(e as Enemy).dead = true
		(e as Node).queue_free()

## A blow on a stand-in (`Enemy.take_damage`): sent at most once per GAP from this game; a spark of it here at once.
static func struck(e: Enemy, from: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if e.has_meta("pvp_last") and now - float(e.get_meta("pvp_last")) < GAP:
		return
	e.set_meta("pvp_last", now)
	if e.game != null and e.game.net != null:
		e.game.net.send_pvp_obj_hit(e.pvp_owner, e.pvp_obj, from)
	if e.game != null and e.game.world != null:
		var top := e.top()
		Fx.burst(e.game.world.fx_root, e.global_position + Vector3(0, top * 0.55, 0), Color(0.75, 0.85, 0.45, 0.9), 10, 2.2, 0.05, 0.4, true, -6.0, 70.0)

## Server: whether a player's blow on a thing counts, at most one per GAP from each player (by the server's clock, a
## little under GAP so a blow delayed on the way still counts). `last` is the server's memory of the last ones.
static func allow(last: Dictionary, attacker: int, owner_pid: int, oid: int, now: float) -> bool:
	var key := "%d:%d:%d" % [attacker, owner_pid, oid]
	if last.has(key) and now - float(last[key]) < GAP * 0.75:
		return false
	if last.size() > 256:
		for k in last.keys():
			if now - float(last[k]) > 30.0:
				last.erase(k)
	last[key] = now
	return true

## Server: where `owner`'s thing `oid` is in the server's own ghost of him, or null if he has none such.
static func where(owner: Hero, oid: int) -> Variant:
	if owner == null or owner.pd == null:
		return null
	return owner.pd.obj_pos(oid)

## Client (every frame in the Battlegrounds): drops stand-ins whose owner is gone or dead, or that outlived MAX_LIFE.
static func prune(g: Node, alive: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for e in g.world.enemies_root.get_children():
		if e is Enemy and e.pvp_obj > 0 and not e.is_queued_for_deletion():
			if not alive.has(e.pvp_owner) or (e.has_meta("pvp_until") and now > float(e.get_meta("pvp_until"))):
				drop(e)

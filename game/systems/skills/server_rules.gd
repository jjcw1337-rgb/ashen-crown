class_name ServerRules
extends RefCounted
## Skills whose rules run on the match server (docs/systems/combat.md). In a Battlegrounds, Arena or Sandbox match on
## our server, a hero of these classes deals no hits on its own game: when one of its skills makes something its
## rules act on (an arrow loosed, a rain called down, a sigil set: `Skill.make`), the player's game sends that to
## the server, and the server's copy of that player makes it there. The server then flies it, decides who it hits
## with its own positions, and deals the damage from its copy of the player's build (sent by `send_build`). What a
## player sees still comes from their own game at once (the cast, the arrow); what only the rules know (a sigil
## blowing, a mark landing) comes from the server to everyone. Single player and Enter World co-op are unchanged.

## The classes whose skills run on the server (the rest still deal their own hits until they move over).
const CLASSES := ["archer", "warlock"]

## Tests: what the server made from players' skills, and what it refused; what a player's game took from its skills'
## rules on the server (Skill.give: life back, mana).
static var made_count := 0
static var refused_count := 0
static var given_count := 0

## This hero's skills run on the server: the server's copy deals them; the player's own game only shows them.
static func on(h) -> bool:
	if h == null or not is_instance_valid(h) or h.game == null or not CLASSES.has(str(h.cls)):
		return false
	var net = h.game.net
	if net == null or not net.active:
		return false
	if net.server:
		return true
	return not net.is_host and (h.game.bg_mode or h.game.arena_mode)

## Server: a player's game sent what one of its skills made; its copy of that player makes it here, if the skill is
## its class's and it adds up (Skill.server_ok).
static func received(game, pid: int, id: String, kind: String, data: Dictionary) -> void:
	var p = game.net.players.get(pid)
	if p == null:
		return
	var h = p["hero"]
	if not is_instance_valid(h) or h.dead or not on(h):
		return
	if id == "run":
		# what the run gives every hero (a flask thrown, thorns on a blow taken): RunTalents checks and makes it
		Hero.striker = h
		if RunTalents.server_made(h, kind, data):
			made_count += 1
		else:
			refused_count += 1
			print("[RULES] refused %s's run %s" % [h.peer_id, kind])
		return
	if id != "attack" and str(Data.skill_def(id).get("cls", "")) != str(h.cls):
		return
	var m = ClassSkills.of(h.cls)
	if m == null or not m.has_method("skill"):
		return
	var s = m.skill(h, id)
	if s == null or not s.server_ok(kind, data):
		refused_count += 1
		print("[RULES] refused %s's %s %s at %s" % [h.peer_id, id, kind, str(h.global_position)])
		return
	Hero.striker = h
	made_count += 1
	s.made(kind, data)

## Server: what a player's skill's rules gave its own hero here (Skill.give) goes to that player's game
## (Net.tell_self: "give").
static func give(h, id: String, kind: String, data: Dictionary) -> void:
	h.game.net.tell_self(h, {"give": [id, kind, data]})

## A player's game: the server's rules gave its hero something (life back, mana); the skill takes it (Skill.given).
static func got(game, id: String, kind: String, data: Dictionary) -> void:
	var h = game.hero
	if h == null or not is_instance_valid(h) or h.dead or str(Data.skill_def(id).get("cls", "")) != str(h.cls):
		return
	var m = ClassSkills.of(h.cls)
	if m == null or not m.has_method("skill"):
		return
	var s = m.skill(h, id)
	if s == null:
		return
	given_count += 1
	s.given(kind, data)

## Server, every frame: the copies' skills fly, beat and blow, and what else of theirs acts here (the class's
## `server_update`: the Archer's wolf).
static func update(h, delta: float) -> void:
	if not on(h):
		return
	var m = ClassSkills.of(h.cls)
	if m != null and m.has_method("server_update"):
		m.server_update(h, delta)
	h.buff_t = maxf(0.0, h.buff_t - delta)      # (the battle buff its game sent wears off here too)
	if h.dead:
		return
	Hero.striker = h
	for sk in h.kit.values():
		sk.update(delta)

## A stand-in for this player or someone on their side (a duo's pair, an arena teammate): their skills pass it by.
## (A player's own game makes stand-ins only for foes: Battlegrounds.sync_proxies.)
static func friend(h, e) -> bool:
	var pid := int(e.get("pvp_pid")) if e is Enemy else 0
	if pid <= 0:
		return false
	var me := int(h.peer_id)
	if pid == me:
		return true
	var bg = h.game.bg if h.game.net.server else null
	if bg == null:
		return false
	if bg.has_method("team"):
		return int(bg.team(pid)) == int(bg.team(me))
	return int(bg.team_of(pid)) == int(bg.team_of(me))

## Server: the foe a player's game named (SkillFx.encode's ids: a monster's net id, or minus a player's id for the
## server's stand-in of them), or null.
static func foe_of(game, id: int):
	if id < 0:
		for e in game.world.enemies_root.get_children():
			if e is Enemy and int(e.pvp_pid) == -id and not e.dead:
				return e
		return null
	var e = game.net.enemies.get(id)
	return e if e != null and is_instance_valid(e) and not e.dead else null

# ---------------------------------------------------------------- the build
## What the server needs to work out a player's damage: level, attributes and the run's skills, rites and gems.
## (Gear already goes with Net.pl_gear.) The server keeps it on its copy; the player's game still makes the picks.
static func build_of(h) -> Dictionary:
	var d := {"cls": str(h.cls), "level": int(h.level), "str": int(h.str_), "dex": int(h.dex), "vit": int(h.vit),
		"ene": int(h.ene)}
	if h.run != null:
		d["run"] = h.run.to_dict()
	return d

## Server: a player's build arrives on its copy.
static func apply_build(h, d: Dictionary) -> void:
	if not is_instance_valid(h) or str(d.get("cls", "")) != str(h.cls):
		return
	h.level = clampi(int(d.get("level", h.level)), 0, 99)
	h.str_ = int(d.get("str", h.str_))
	h.dex = int(d.get("dex", h.dex))
	h.vit = int(d.get("vit", h.vit))
	h.ene = int(d.get("ene", h.ene))
	if d.has("run") and d["run"] is Dictionary:
		h.run = RunBuild.from_dict(d["run"])
	h._talents_changed()      # (recalcs too)

static var _sent := {}
static var _t := 0.0

## A player's game, every frame: sends its build to the server when it has changed (checked once a second).
static func client_tick(game, delta: float) -> void:
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var h = game.hero
	if h == null or not on(h):
		return
	var d := build_of(h)
	if d != _sent:
		_sent = d
		game.net.send_build(d)

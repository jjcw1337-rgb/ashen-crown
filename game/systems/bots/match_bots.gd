class_name MatchBots
extends Node
## Bot players in a real match (jj, 2026-11-07: test games "missing 1 player: I join it and the game starts"). The
## lobby service's standing lobbies list their bot seats as members with "bot": true; once the humans have arrived,
## the match server (MatchInstance) makes a hero for each here, at the humans' level, run by BotBrain.
##
## To the match a bot is a player: it sits in Net.players (with "bot": true) under a peer id of its own (BOT_PID and
## up, clear of ENet's), in MatchInstance.members with its team, so teams, the stand-ins, PvP, monsters' targets,
## rounds and the roster work as they do for people. Net sends its state (cl_bot_state) and its skills' fx
## (cl_server_fx) to every game; whatever Net would send *to* a player arrives here instead (Net.hit_player,
## Battlegrounds' statuses, the Arena's round reset). Server only: no pixels.

const BOT_PID := 2_100_000_000
## The classes bots play (their kits run on the match server as a local hero's would).
const CLASSES := ["knight", "archer", "warlock", "wraith", "demon"]
const NAMES := ["Kael", "Brannoc", "Ysolde", "Mirelle", "Corvin", "Thessaly", "Orrin", "Vesna", "Hadrik", "Liora", "Garrow", "Ilsa", "Torvald", "Selka", "Rook"]
const SEARCH := 30.0          # metres: a foe further off is ignored
const PREFER_HERO := 18.0     # metres: a hostile player this close is fought before a monster

var game: Node
var bots := {}                # pid -> {"hero", "brain", "team", "cls"}

## Every member flagged bot in the match's manifest, at `lvl`, each with its manifest team. Called once.
static func spawn_all(g: Node, mi: Node, lvl: int) -> MatchBots:
	var mb := MatchBots.new()
	mb.name = "MatchBots"
	mb.game = g
	g.add_child(mb)
	var n := 0
	for uid in (mi.config.get("members", {}) as Dictionary):
		var m: Dictionary = mi.config.members[uid]
		if not bool(m.get("bot", false)):
			continue
		var pid := BOT_PID + n
		while g.net.players.has(pid):
			pid += 1
		var cls := str(m.get("character", "")).trim_prefix("run_")
		if not cls in CLASSES:
			cls = CLASSES[n % CLASSES.size()]
		# (its membership first: where it stands comes from its team, MatchInstance.spawn)
		mi.members[pid] = {"user": str(uid), "team": int(m.get("team", n)), "character": "run_" + cls, "name": str(m.get("name", "Bot")), "bot": true}
		mb.add_bot(pid, str(m.get("name", "Bot")), cls, int(m.get("team", n)), lvl, str(mi.config.mode) == "arena")
		n += 1
	return mb

## One bot: a local (not puppet) hero on the server, outfitted like the Sandbox's, standing where its team spawns.
func add_bot(pid: int, nm: String, cls: String, team: int, lvl: int, geared: bool) -> Hero:
	var h := Hero.new()
	h.bot = true
	h.peer_id = pid
	h.name = "Bot%d" % (pid - BOT_PID)
	game.add_child(h)
	h.setup(game)
	h.pvp_force = true          # (the raid's PvP gear rules and scale: the server itself is in neither mode)
	Sandbox.outfit(game, h, cls, maxi(1, lvl), "geared" if geared else "")
	h.net_has = true            # (it has a state from the start: the arrival gate and the stand-ins count it)
	bots[pid] = {"hero": h, "brain": BotBrain.new(), "team": team, "cls": cls}
	game.net.players[pid] = {"name": nm, "hero": h, "bot": true}
	var at: Vector3 = game.match_instance.spawn(pid) if game.match_instance != null else h.global_position
	h.global_position = at
	h.net_pos = at
	for op in game.net.players:
		if not game.net.is_bot(op):
			game.net.rpc_id(op, "cl_player_join", pid, nm, h.net_gear())
	print("[BOTS] %s, a level %d %s, joins team %d" % [nm, h.level, cls, team])
	return h

## The names for a lobby's bot seats (the lobby service picks from the same list).
static func bot_name(i: int) -> String:
	return NAMES[i % NAMES.size()]

var _log_t := 0.0

func _process(delta: float) -> void:
	if game == null or game.world == null or game._busy:
		return
	var mi = game.match_instance
	if mi == null or not mi.begun or mi.ending:
		return
	_log_t -= delta
	for pid in bots:
		var h: Hero = bots[pid]["hero"]
		if not is_instance_valid(h) or h.dead:
			continue
		bots[pid]["brain"].think(h, pick_for, delta)
		if _log_t <= 0.0:
			var t: Enemy = pick_for(h)
			print("[BOTS] %s at %s, life %d, target %s, phase %s" % [game.net.players[pid]["name"], str(h.global_position.snapped(Vector3.ONE * 0.1)),
				int(h.life), (t.display_name if t != null else "none"), str(game.bg.get("round_phase")) if game.bg != null else "-"])
	if _log_t <= 0.0:
		_log_t = 30.0      # (a line per bot every 30 s in the match log: where it is and what it fights)

## What a bot fights: the nearest hostile player's stand-in within SEARCH (one within PREFER_HERO before any
## monster), else the nearest monster (none in the Arena).
func pick_for(h: Hero) -> Enemy:
	var best: Enemy = null
	var bd := SEARCH * SEARCH
	var hero_best: Enemy = null
	var hd := PREFER_HERO * PREFER_HERO
	var arena := game.match_instance != null and str(game.match_instance.config.get("mode", "")) == "arena"
	for e in game.world.enemies_root.get_children():
		if not (e is Enemy) or e.dead:
			continue
		var d: float = e.global_position.distance_squared_to(h.global_position)
		if e.pvp_pid > 0:
			if not hostile(h, int(e.pvp_pid)):
				continue
			if d < hd:
				hd = d
				hero_best = e
		elif arena or e.sandbox_hero != null:
			continue
		# (a hostile player further off than PREFER_HERO is still a target, like the nearest monster)
		if d < bd:
			bd = d
			best = e
	return hero_best if hero_best != null else best

## Is the player `pid` one this bot may fight now (the mode's own rule: Battlegrounds.pvp_pair, ArenaMatch's)?
func hostile(h: Hero, pid: int) -> bool:
	if pid == int(h.peer_id) or not game.net.players.has(pid) or game.bg == null:
		return false
	var other = game.net.players[pid]["hero"]
	if not is_instance_valid(other) or other.dead or other.invis_t > 0.0:
		return false
	return not (game.bg.pvp_pair(int(h.peer_id), pid) as Array).is_empty()

## What Net would have sent the bot's game: a blow it took (Net.hit_player).
static func take_hit(h: Hero, dmg: float, from: Vector3, kind: String, element: String) -> void:
	if is_instance_valid(h) and not h.dead:
		h.take_hit(dmg, from, kind, element)

## The Arena's round reset (Net.cl_arena_reset, for a bot).
static func reset(h: Hero, at: Vector3) -> void:
	ClassSkills.clear(h)
	SkillFx.clear(h)
	h.respawn(at)
	h.cds.clear()
	for sk in h.skill_list() + Data.shared_skills():
		h.cds[sk.id] = 0.0
	h.buff_t = 0
	h.burn_t = 0
	h.life = h.max_life
	h.mana = h.max_mana
	h.net_pos = at

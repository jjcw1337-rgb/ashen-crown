class_name CoopServer
extends Node
## Online co-op on a dedicated server (staging: `-- --server --coop --port 24570`, systemd ashen-crown-coop): the
## story game hosted by the server instead of a player's PC, so friends can play together over the internet without
## touching their routers. It is the normal co-op host (Net, host-authoritative monsters, loot and bosses) with
## Net.server + Net.coop_server: the server's own hero is hidden, parked off the map and phased, every player brings
## their own saved character (the title's "Online Co-op" -> Game.start_join to BuildEnv's coop_server), and travel,
## waypoints, portals and the party's ready check work as in player-hosted co-op (the server always says yes).
## Battlegrounds (battlegrounds.gd) is the other kind of server; one process runs one or the other.
## Test: tools/coop_server_test.gd (a server and two players).

const MAX_PLAYERS := 4

var game: Node

static func start(g: Node, port: int) -> void:
	var cs := CoopServer.new()
	cs.name = "CoopServer"
	cs.game = g
	g.add_child(cs)
	g.coop_server = cs
	g.net.server = true
	g.net.coop_server = true
	Engine.max_fps = 60             # headless, the loop would otherwise spin a whole core
	g.ui.hide_title()
	g.playing = true
	g.difficulty = 0
	g.test_immortal = true
	cs.park_hero()
	var err: int = g.net.host(port, MAX_PLAYERS)
	await g.load_zone(0, "town", "start")
	cs.park_hero()
	print("[COOP] server ", "up on UDP port %d" % port if err == OK else "FAILED to open port %d (error %d)" % [port, err])
	ServerUpdate.watch(g, "[COOP]", func() -> bool: return g.net.players.is_empty())

## The server's own hero: hidden, off the map and phased, so monsters never see it (kept so every frame).
func park_hero() -> void:
	var b: Rect2 = game.world.bounds if game.world != null else Rect2(-40, -40, 80, 80)
	game.hero.global_position = Vector3(b.position.x - 60.0, 0, b.position.y - 60.0)
	game.hero.visible = false
	game.hero.phased = true

## A player joining: beside a partner already playing, else the zone's start.
func spawn_point() -> Vector3:
	for h in game.net.puppets():
		if not h.dead and h.net_has:
			return game.world.free_spot_near(h.global_position, 2.0)
	return game.world.free_spot_near(game.world.spawns.get("start", Vector3.ZERO), 2.0)

func _process(_delta: float) -> void:
	if game.world != null and not game._busy:
		park_hero()

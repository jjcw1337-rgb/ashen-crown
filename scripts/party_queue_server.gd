extends Node
## Small, independent ENet lobby alongside the co-op host. No extra world or server process.
## Its slots are reserved during ready checks and handoff, including against direct joins.
const VERSION := 1
const READY_SECS := 30.0
const LEASE_SECS := 45.0
const HEARTBEAT_SECS := 15.0
var game
var peer: ENetMultiplayerPeer
var waiting: Array = []
var clients := {}
var group := {}
var reservations := {}
var clock := 0.0
var tick := 0.0
var game_port := 24570
var ready_secs := READY_SECS

func start(g, port: int, destination_port: int) -> int:
	game = g
	game_port = destination_port
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 64)
	if err != OK:
		peer = null
		return err
	peer.peer_disconnected.connect(_left)
	peer.peer_connected.connect(func(id): clients[id] = {"seen": clock, "joined": false})
	return OK

func _exit_tree() -> void:
	if peer: peer.close()

func send(id: int, msg: Dictionary) -> void:
	if peer == null or not clients.has(id): return
	msg["v"] = VERSION
	peer.set_target_peer(id)
	peer.put_packet(JSON.stringify(msg).to_utf8_buffer())

func _process(delta: float) -> void:
	if peer == null: return
	clock += delta
	peer.poll()
	# Bound work even when a remote peer floods the queue socket.
	for i in mini(peer.get_available_packet_count(), 128):
		var id := peer.get_packet_peer()
		var bytes := peer.get_packet()
		if bytes.size() > 1024 or not clients.has(id): continue
		var data = JSON.parse_string(bytes.get_string_from_utf8())
		if data is Dictionary: receive(id, data)
	tick += delta
	if tick < 0.5: return
	tick = 0
	for id in clients.keys():
		if clock - float(clients[id]["seen"]) > HEARTBEAT_SECS:
			_left(id)
			peer.disconnect_peer(id)
	for token in reservations.keys():
		if float(reservations[token]["until"]) <= clock: reservations.erase(token)
	if not group.is_empty():
		if game.difficulty != int(group["act"]) or group["members"].size() + game.net.players.size() < 2:
			_reset_group(false)
		elif clock >= float(group["until"]):
			_reset_group(true)
		elif group["yes"].size() == group["members"].size() and not game._busy:
			_commit()
	if group.is_empty() and not game._busy: _match()
	for id in waiting:
		send(id, {"state": "queued", "count": waiting.size()})
	if not group.is_empty():
		for id in group["members"]:
			send(id, {"state": "ready", "match": group["id"], "seconds": maxf(0, float(group["until"]) - clock),
				"count": group["members"].size() + game.net.players.size(), "accepted": group["yes"].has(id)})

func receive(id: int, data: Dictionary) -> void:
	if int(data.get("v", 0)) != VERSION:
		send(id, {"state": "error", "message": "Update the game to use the party finder."})
		return
	clients[id]["seen"] = clock
	match str(data.get("op", "")):
		"join":
			if bool(clients[id]["joined"]): return
			clients[id]["joined"] = true
			clients[id]["max_act"] = clampi(int(data.get("max_act", 0)), 0, 2)
			waiting.append(id)
		"ping": pass
		"cancel":
			for token in reservations.keys():
				if int(reservations[token]["peer"]) == id: reservations.erase(token)
			_left(id)
		"ready":
			if not group.is_empty() and str(data.get("match", "")) == str(group["id"]) and group["members"].has(id) and clock < float(group["until"]):
				group["yes"][id] = true

func _left(id: int) -> void:
	waiting.erase(id)
	clients.erase(id)
	if not group.is_empty() and group["members"].has(id): _reset_group(false)
	# Committed tickets survive the lobby disconnect while the game socket connects.

func _reset_group(expired: bool) -> void:
	var retry: Array = []
	for id in group["members"]:
		if not clients.has(id): continue
		if expired and not group["yes"].has(id):
			send(id, {"state": "expired", "message": "Ready check expired. Join the queue when ready."})
			clients[id]["joined"] = false
		else:
			retry.append(id)
	waiting = retry + waiting
	group = {}

func free_slots() -> int:
	return maxi(0, 4 - game.net.players.size() - reservations.size() - (0 if group.is_empty() else group["members"].size()))

func _match() -> void:
	var members: Array = []
	var slots := free_slots()
	for id in waiting:
		if members.size() >= slots: break
		if int(clients[id]["max_act"]) >= game.difficulty: members.append(id)
	if members.is_empty() or members.size() + game.net.players.size() < 2: return
	for id in members: waiting.erase(id)
	group = {"id": Crypto.new().generate_random_bytes(16).hex_encode(), "members": members,
		"yes": {}, "until": clock + ready_secs, "act": game.difficulty}

func _commit() -> void:
	for id in group["members"]:
		var token := Crypto.new().generate_random_bytes(24).hex_encode()
		reservations[token] = {"until": clock + LEASE_SECS, "max_act": clients[id]["max_act"], "peer": id}
		send(id, {"state": "join", "ticket": token, "port": game_port})
	group = {}

func admit(token: String) -> bool:
	if game.net.players.size() >= 4: return false
	if token == "": return free_slots() > 0
	if not reservations.has(token): return false
	var r: Dictionary = reservations[token]
	reservations.erase(token) # one use, including a stale/invalid attempt
	return float(r["until"]) > clock and int(r["max_act"]) >= game.difficulty

extends Node
## Background party search. Own socket: solo gameplay, travel and menus continue uninterrupted.
var game
var peer: ENetMultiplayerPeer
var state := "idle"
var match_id := ""
var accepted := false
var remaining := 0.0
var count := 0
var elapsed := 0.0
var heard := 0.0
var ping := 0.0
var joined := false
var character := ""
var host := ""
var destination := ""
var ticket := ""
var panel: PanelContainer
var label: Label
var detail: Label
var accept: Button
var cancel: Button

func setup(g) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "PartyFinder"
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -230
	panel.offset_right = 230
	panel.offset_top = 28
	game.ui._ornate(panel, 0.13, 8)
	game.ui.top.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	label = game.ui._label("", 20, game.ui.GOLD, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(label)
	detail = game.ui._label("", 14, game.ui.DIM)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 360
	vb.add_child(detail)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	accept = game.ui._iron_button("Ready", 150, 38, 16)
	accept.pressed.connect(accept_match)
	row.add_child(accept)
	cancel = game.ui._iron_button("Leave Queue", 150, 38, 16)
	cancel.pressed.connect(func(): stop())
	row.add_child(cancel)
	panel.hide()

func begin() -> void:
	if state != "idle": return
	if not game.playing or game.net.active or game.bg_mode or game._busy or game.hero.dead:
		game.ui.message("Find a party while playing solo.")
		return
	var address: String = BuildEnv.value("party_queue")
	if address == "" or OS.has_feature("web"):
		game.ui.message("Party finder is unavailable in this build.")
		return
	var parts: Array = Battlegrounds.parse_address(address)
	host = str(parts[0])
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(host, int(parts[1])) != OK:
		fail("Could not start party search. Try again.")
		return
	state = "connecting"
	character = game.char_id
	joined = false
	elapsed = 0
	heard = 0
	ping = 0
	panel.show()
	_refresh()

func send(data: Dictionary) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return
	data["v"] = 1
	peer.set_target_peer(1)
	peer.put_packet(JSON.stringify(data).to_utf8_buffer())

func accept_match() -> void:
	if state != "ready" or accepted or remaining <= 0: return
	if game._busy or game.hero.dead or game.paused:
		game.ui.message("Finish loading, revive, or resume before accepting.")
		return
	send({"op": "ready", "match": match_id})
	accepted = true
	_refresh()

func stop() -> void:
	send({"op": "cancel"})
	if peer: peer.close()
	peer = null
	state = "idle"
	accepted = false
	ticket = ""
	if panel: panel.hide()

func fail(message: String) -> void:
	stop()
	game.ui.message(message, Color(1, 0.7, 0.45), 6.0)

func _exit_tree() -> void:
	if peer: peer.close()

func _process(delta: float) -> void:
	if state == "idle": return
	if not game.playing or character != game.char_id or game.bg_mode:
		stop()
		return
	elapsed += delta
	heard += delta
	remaining = maxf(0, remaining - delta)
	if peer:
		peer.poll()
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			fail("Party search disconnected. Your adventure is unchanged; queue again when ready.")
			return
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not joined:
			joined = true
			send({"op": "join", "max_act": game.max_run})
		ping += delta
		if ping >= 3:
			ping = 0
			send({"op": "ping"})
		for i in mini(peer.get_available_packet_count(), 32):
			var bytes := peer.get_packet()
			if bytes.size() > 2048: continue
			var data = JSON.parse_string(bytes.get_string_from_utf8())
			if data is Dictionary: receive(data)
			if peer == null: break
	if state == "idle": return
	if game.net.active:
		stop()
		return
	if heard > 12 and state != "joining":
		fail("Party finder is not responding. Keep playing and try again shortly.")
		return
	if state == "joining":
		if remaining <= 0:
			fail("The party reservation expired. Queue again when ready.")
			return
		if not game._busy and not game.hero.dead and not game.paused:
			var address := destination
			var key := ticket
			# The host holds the reservation when this queue socket closes.
			if peer: peer.close()
			peer = null
			state = "idle"
			panel.hide()
			game.save_game()
			game.party_join_ticket = key
			game.party_join_pending = true
			game.ui.close_all()
			game.start_join(address, character)
	_refresh()

func receive(data: Dictionary) -> void:
	if int(data.get("v", 0)) != 1: return
	heard = 0
	match str(data.get("state", "")):
		"queued":
			state = "queued"
			accepted = false
			match_id = ""
			count = int(data.get("count", 1))
		"ready":
			var next := str(data.get("match", ""))
			if next != match_id:
				accepted = false
				Sfx.play("portal")
			match_id = next
			state = "ready"
			remaining = float(data.get("seconds", 0))
			count = int(data.get("count", 2))
			accepted = accepted or bool(data.get("accepted", false))
		"join":
			if state != "ready" or not accepted: return
			var port := int(data.get("port", 0))
			if port < 1024 or port > 65535: return
			ticket = str(data.get("ticket", ""))
			if ticket.length() != 48: return
			destination = "%s:%d" % [host, port]
			state = "joining"
			remaining = 35
		"expired", "error": fail(str(data.get("message", "Party search ended.")))

func _refresh() -> void:
	if state == "idle": return
	accept.visible = state == "ready" and not accepted
	cancel.text = "Decline" if state == "ready" else "Leave Queue"
	match state:
		"connecting":
			label.text = "FINDING A PARTY"
			detail.text = "Connecting… Keep adventuring while we search."
		"queued":
			label.text = "FINDING A PARTY  ·  %d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
			detail.text = "Co-op PvE · %d searching. Keep adventuring." % count
		"ready":
			label.text = "PARTY FOUND  ·  %ds" % int(ceil(remaining))
			detail.text = "Ready. Waiting for the others…" if accepted else "%d adventurers · Ready to join co-op?" % count
		"joining":
			label.text = "YOUR PARTY IS READY"
			detail.text = "Joining when loading finishes and you are alive and unpaused."

extends SceneTree
## Triage 2026-11-04: "Unable to send packet on channel 1, max channels: 0" (fd6796612eee4c16) on the raid server
## whenever it turned a player away: a graceful `disconnect_peer` empties the ENet peer's channels at once but keeps
## it listed until the client answers, and a client building the crypt can't for seconds, so every RPC sent to it
## meanwhile failed. `Net.drop_peer` disconnects now. This checks both in one process: a server and a client peer, the
## client not polled for 2.5 s (busy), the server sending to it per peer as Godot's RPCs do for a new peer.
## Usage: godot --headless --path . -s tools/nightly_drop_peer_test.gd
var fails := 0

func _check(name: String, ok: bool) -> void:
	print("[D] %s ok=%s%s" % [name, ok, "" if ok else "  FAIL"])
	if not ok:
		fails += 1

func _initialize():
	_run()

func _log_size() -> int:
	var f := FileAccess.open("user://logs/godot.log", FileAccess.READ)
	return f.get_length() if f != null else 0

func _log_since(at: int) -> String:
	var f := FileAccess.open("user://logs/godot.log", FileAccess.READ)
	if f == null:
		return ""
	f.seek(mini(at, f.get_length()))
	return f.get_buffer(f.get_length() - f.get_position()).get_string_from_utf8()

## One turn-away: returns [send errors logged, seconds until the server's peer_disconnected].
func _case(port: int, now: bool) -> Array:
	var sv := ENetMultiplayerPeer.new()
	var cl := ENetMultiplayerPeer.new()
	sv.create_server(port, 4)
	cl.create_client("127.0.0.1", port)
	var st := {"id": 0, "gone": -1.0}
	sv.peer_connected.connect(func(id): st["id"] = id)
	var t0 := Time.get_ticks_msec()
	while (int(st["id"]) == 0 or cl.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED) and Time.get_ticks_msec() - t0 < 5000:
		sv.poll()
		cl.poll()
		await process_frame
	var id: int = int(st["id"])
	sv.peer_disconnected.connect(func(_id): st["gone"] = (Time.get_ticks_msec() - t0) / 1000.0)
	var at := _log_size()
	t0 = Time.get_ticks_msec()
	if now:
		sv.get_peer(id).peer_disconnect_now(0)       # (what Net.drop_peer does)
	else:
		sv.disconnect_peer(id)
	# the client is busy for 2.5 s (not polled); the server keeps sending to it, one peer at a time, reliably
	while Time.get_ticks_msec() - t0 < 2500:
		sv.poll()
		if float(st["gone"]) < 0.0:
			sv.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
			sv.set_target_peer(id)
			sv.put_packet(PackedByteArray([1, 2, 3]))
		await process_frame
	var errs := _log_since(at).count("Unable to send packet")
	sv.close()
	cl.close()
	return [errs, float(st["gone"])]

func _run() -> void:
	var old: Array = await _case(24795, false)
	var new: Array = await _case(24796, true)
	print("[D] graceful disconnect_peer: %d send errors, left after %.2f s" % [old[0], old[1]])
	print("[D] disconnect now (Net.drop_peer): %d send errors, left after %.2f s" % [new[0], new[1]])
	_check("disconnecting now: no send errors to the busy client", int(new[0]) == 0)
	_check("and the server still sees it leave at once (peer_disconnected)", float(new[1]) >= 0.0 and float(new[1]) < 0.5)
	print("[D] done fails=%d" % fails)
	quit(1 if fails > 0 else 0)

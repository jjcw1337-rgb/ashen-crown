extends SceneTree
## Steam co-op host side, on this machine (needs Steam running and a display): the game starts as Spacewar, a
## character enters its world, Invite Friends opens it (SteamMultiplayerPeer host + a friends-only lobby with
## rich presence). Prints [STEAMHOST] lines. The join side needs a second Steam account on another machine.
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://steam_probe_chars/"
	get_root().add_child(g)
	_run()
func _run():
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	print("[STEAMHOST] steam ok: ", g.steam.ok)
	if not g.steam.ok:
		quit(1)
		return
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.toggle_pause()
	print("[STEAMHOST] invite button visible: ", g.ui.invite_btn.visible)
	g.ui.invite_btn.pressed.emit()
	var t0 := Time.get_ticks_msec()
	while g.steam.lobby == 0 and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	print("[STEAMHOST] hosting: %s, net host: %s, lobby: %s" % [g.steam.hosting, g.net.is_host, g.steam.lobby])
	print("[STEAMHOST] lobby data game=%s host=%s" % [g.steam.steam.getLobbyData(g.steam.lobby, "game"), g.steam.steam.getLobbyData(g.steam.lobby, "host")])
	print("[STEAMHOST] friends' worlds visible to me: ", g.steam.friends_worlds().size())
	await create_timer(0.5).timeout
	if g.steam.lobby == 0:
		g.steam._open_picker()      # (Steam made no lobby this time: show the window anyway, for the screenshot)
		await create_timer(0.5).timeout
	var pk = g.steam._picker
	print("[STEAMHOST] overlay: %s, invite window open: %s, online friends: %d" % [g.steam.steam.isOverlayEnabled(), pk != null and pk.visible, g.steam.online_friends().size()])
	if pk != null:
		get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[-1] if OS.get_cmdline_user_args()[-1].ends_with(".png") else "/tmp/steam_invite.png")
	await g.exit_to_title()
	print("[STEAMHOST] after exit: lobby %s hosting %s" % [g.steam.lobby, g.steam.hosting])
	quit()

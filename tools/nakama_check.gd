extends SceneTree
## Checks a Nakama server end to end with the game's own client (NakamaClient): sign in a throwaway device,
## write a storage object, read it back, delete it.
##   godot --headless --path . -s tools/nakama_check.gd -- [http(s)://host:7350] [server_key]
## Without arguments it uses this build's BuildEnv (local, or staging in a staging build). Exits 1 on any failure.

var fails := 0

func _initialize():
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[N] " + ("ok   " if ok else "FAIL ") + what)

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var url: String = a[0] if a.size() > 0 else ""
	var key: String = a[1] if a.size() > 1 else ""
	var nk := NakamaClient.new(url, key)
	get_root().add_child(nk)
	await process_frame
	print("[N] env %s, server %s" % [BuildEnv.env(), nk.url])
	var dev := "ashen-check-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var ok: bool = await nk.authenticate_device(dev)
	check(ok and nk.user_id != "", "device sign-in (user %s) %s" % [nk.user_id, nk.last_error])
	if ok:
		var obj := {"collection": "healthcheck", "key": "probe", "value": {"at": Time.get_unix_time_from_system(), "env": BuildEnv.env()}}
		check(await nk.write_objects([obj]), "write a storage object %s" % nk.last_error)
		var back: Dictionary = await nk.read_object("healthcheck", "probe")
		check(back.get("env", "") == BuildEnv.env(), "read it back %s" % nk.last_error)
		check(await nk.delete_objects([obj]), "delete it %s" % nk.last_error)
	print("[N] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)

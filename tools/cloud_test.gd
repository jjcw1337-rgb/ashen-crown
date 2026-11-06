extends SceneTree
## Cloud saves (cloud_saves.gd) and the Battlegrounds stash rules against a running Nakama with the game's module:
##   godot --headless --path . -s tools/cloud_test.gd -- http://127.0.0.1:7350 <server_key> [<http_key>]
## Uses a scratch character folder and throwaway devices, never the player's saves. Exits 1 on any failure.

var g
var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[CL] " + ("ok   " if ok else "FAIL ") + what)

func _initialize():
	BuildEnv.forced = {"cloud": "0"}     # the game itself stays local; the test drives its own CloudSaves
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _write(id: String, d: Dictionary) -> void:
	var f := FileAccess.open(g.char_dir + id + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()

func _read(id: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(g.char_dir + id + ".json")) if FileAccess.file_exists(g.char_dir + id + ".json") else null
	return d if d is Dictionary else {}

func _clear() -> void:
	var dir := DirAccess.open(g.char_dir)
	if dir:
		for fn in dir.get_files():
			DirAccess.remove_absolute(g.char_dir + fn)

func _run() -> void:
	for i in 30:
		await process_frame
	var a := OS.get_cmdline_user_args()
	var url: String = a[0] if a.size() > 0 else "http://127.0.0.1:7350"
	var key: String = a[1] if a.size() > 1 else "defaultkey"
	var http_key: String = a[2] if a.size() > 2 else ""
	g.char_dir = "user://cloud_test_chars/"
	DirAccess.make_dir_recursive_absolute(g.char_dir)
	_clear()
	var cs := CloudSaves.new(g, url, key)
	cs.device_id = "cloud-test-" + Crypto.new().generate_random_bytes(8).hex_encode()
	get_root().add_child(cs)
	await process_frame
	# migration: two characters only on this PC go up
	_write("c_one", {"name": "One", "played": 100, "hero": {"cls": "knight", "level": 3}})
	_write("c_two", {"name": "Two", "played": 200, "hero": {"cls": "wraith", "level": 5}})
	check(await cs.sync(), "signed in and synced")
	check(cs.last_sync["up"] == 2 and cs.last_sync["down"] == 0, "both local characters uploaded (%s)" % cs.last_sync)
	var remote: Array = await cs.nk.list_objects(CloudSaves.COLLECTION)
	check(remote.size() == 2, "the account holds them (%d)" % remote.size())
	# played again here: only the newer one goes up
	_write("c_one", {"name": "One", "played": 300, "hero": {"cls": "knight", "level": 4}})
	await cs.sync()
	check(cs.last_sync["up"] == 1, "a newer local save is uploaded (%s)" % cs.last_sync)
	# a new PC (no local files): everything comes down, the newest copy
	_clear()
	await cs.sync()
	check(cs.last_sync["down"] == 2 and int(_read("c_one").get("played", 0)) == 300, "a fresh PC gets every character, the newest copy")
	# played on another device: the newer account copy wins
	await cs.nk.write_objects([{"collection": CloudSaves.COLLECTION, "key": "c_two", "value": {"name": "Two", "played": 999, "hero": {"cls": "wraith", "level": 9}}}])
	await cs.sync()
	check(int(_read("c_two").get("played", 0)) == 999, "a newer save from another device comes down")
	# Game.save_game's push
	await cs.push("c_three", {"name": "Three", "played": 1000})
	remote = await cs.nk.list_objects(CloudSaves.COLLECTION)
	check(remote.size() == 3, "a save is pushed (%d in the account)" % remote.size())
	await cs.remove("c_three")
	remote = await cs.nk.list_objects(CloudSaves.COLLECTION)
	check(remote.size() == 2, "a deleted character leaves the account (%d)" % remote.size())
	# another player's device can't see these
	var other := NakamaClient.new(url, key)
	get_root().add_child(other)
	await other.authenticate_device("cloud-test-other-" + Crypto.new().generate_random_bytes(8).hex_encode())
	var theirs: Array = await other.list_objects(CloudSaves.COLLECTION)
	check(theirs.is_empty(), "another account sees none of them")
	# the server's own collections: a player can't write or delete them
	var direct: bool = await other.write_objects([{"collection": "battlegrounds", "key": "stash", "value": {"items": []}}])
	check(not direct, "a player can't write the server's collections")
	if http_key != "":
		# join tickets: one-time, and only for a signed-in player
		var tk: Dictionary = await other.user_rpc("bg_ticket", {})
		var ticket: String = str(tk.get("ticket", ""))
		check(ticket.length() >= 32, "a signed-in player gets a join ticket")
		var r1: Dictionary = await other.server_rpc("bg_ticket_redeem", {"ticket": ticket}, http_key)
		check(str(r1.get("user_id", "")) == other.user_id, "the server redeems it for that player")
		var r2: Dictionary = await other.server_rpc("bg_ticket_redeem", {"ticket": ticket}, http_key)
		check(str(r2.get("user_id", "")) == "", "but only once")
		var forged: Dictionary = await other.server_rpc("bg_ticket_redeem", {"ticket": "0".repeat(64)}, http_key)
		check(str(forged.get("user_id", "")) == "", "a made-up ticket is refused")
		var tw: bool = await other.write_objects([{"collection": "bg_tickets", "key": "x".repeat(64), "value": {"user_id": "someone", "expires": 9e15}}])
		check(not tw, "and nobody can plant one")
	# a brand-new account can't create its own stash before the server ever writes one
	var fresh := NakamaClient.new(url, key)
	get_root().add_child(fresh)
	await fresh.authenticate_device("cloud-test-fresh-" + Crypto.new().generate_random_bytes(8).hex_encode())
	var forge: bool = await fresh.write_objects([{"collection": "battlegrounds", "key": "stash", "value": {"items": [{"base": "gold", "count": 99999}]}}])
	check(not forge, "a fresh account can't create a stash of its own (%s)" % fresh.last_error.substr(0, 30))
	var empty: Dictionary = await fresh.read_object("battlegrounds", "stash")
	check(empty.is_empty(), "and none exists for it")
	# tidy up the test account's characters
	await cs.remove("c_one")
	await cs.remove("c_two")
	_clear()
	print("[CL] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)

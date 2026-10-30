extends SceneTree
## Signs an admin key for the game (AdminKey). Needs the owner's PRIVATE key, which is never in the repo.
##   godot --headless -s tools/admin_key.gd -- <private.pem> "<name>" <out admin.key>
## Put the resulting admin.key in %APPDATA%\Godot\app_userdata\Ashen Crown\ on the admin's PC.
func _initialize():
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		print("usage: -- <private.pem> \"<name>\" <out admin.key>")
		quit(1)
		return
	var key := CryptoKey.new()
	if key.load(a[0]) != OK:
		print("could not read the private key")
		quit(1)
		return
	var sig := Crypto.new().sign(HashingContext.HASH_SHA256, AdminKey.digest(a[1]), key)
	var f := FileAccess.open(a[2], FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": a[1], "sig": Marshalls.raw_to_base64(sig)}))
	f.close()
	print("signed admin key for ", a[1], " -> ", a[2], "  valid: ", AdminKey.verify(a[1], sig))
	quit()

extends SceneTree
## AdminKey: a key signed for one name verifies; the same signature with another name, a broken
## signature, or no file at all does not. godot --headless -s tools/admin_key_test.gd -- <admin.key>
func _initialize():
	var a := OS.get_cmdline_user_args()
	var d = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var sig := Marshalls.base64_to_raw(str(d["sig"]))
	var fails := 0
	for c in [[AdminKey.verify(str(d["name"]), sig), true, "the real key verifies"],
			[AdminKey.verify("Someone Else", sig), false, "the same signature with another name fails"],
			[AdminKey.verify(str(d["name"]), sig.slice(0, sig.size() - 1) + PackedByteArray([sig[-1] ^ 1])), false, "a tampered signature fails"],
			[AdminKey.verify(str(d["name"]), PackedByteArray()), false, "no signature fails"]]:
		var good: bool = c[0] == c[1]
		print("[K] ", "ok   " if good else "FAIL ", c[2])
		if not good:
			fails += 1
	print("[K] done, %d failed" % fails)
	quit(1 if fails else 0)

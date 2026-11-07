extends SceneTree
## The sea's sounds (tools/audio/make_sea.py, wired in Game._sea_sounds, BoatRide._sounds, Birds): the surf bed on
## the coast and fading inland and out at sea, the open-sea loop under sail, the hull creaking and slapping, gulls
## crying, a fish's splash, Osric's mallet on the hull. Prints [W] lines.
var g
var sfx
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func wait(s: float) -> void:
	await create_timer(s).timeout
func n(nm: String) -> int:
	return int(sfx.counts.get(nm, 0))
func ok(cond: bool, what: String) -> void:
	print("[W] %s %s" % ["ok  " if cond else "FAIL", what])
func _run() -> void:
	sfx = get_root().get_node("Sfx")
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	for nm in ["surf", "sea", "splash", "gull", "hull_creak", "hull_slap", "mallet"]:
		ok(sfx.bank.has(nm), "%s is in the bank (%d takes)" % [nm, (sfx.bank.get(nm, []) as Array).size()])
	await g.start_game(false, "knight")
	g.ui.close_all()
	g.hero.boats = ["gull"]
	g.hero.sailed = true
	await g.load_zone(0, "coast", "dock")
	await wait(0.5)
	ok(sfx.ambience.stream == sfx.bank["surf"][0] or sfx.bank["surf"].has(sfx.ambience.stream), "the coast's ambience is the surf")
	var on_beach: float = sfx.ambience.volume_db
	# Osric at the hull: the mallet rings when his hammer lands
	var m0 := n("mallet")
	g.hero.global_position = g.world.spawns["shipwright"] + Vector3(6.0, 0, 6.0)
	for i in 180:
		await wait(0.25)
		if n("mallet") > m0:
			break
	ok(n("mallet") > m0, "Osric's hammer knocks with the mallet (%d)" % (n("mallet") - m0))
	# under sail: the sea loop, creaks and slaps
	var b: BoatRide = g.boat
	g.hero.global_position = Vector3(1.5, 1.05, -0.8)
	g._interact(b.inter)
	var c0 := n("hull_creak")
	var s0 := n("hull_slap")
	# the real key: W builds speed (Game._sail_input writes her drive every frame)
	var kw := InputEventKey.new()
	kw.keycode = KEY_W
	kw.physical_keycode = KEY_W
	kw.pressed = true
	Input.parse_input_event(kw)
	await wait(12.0)
	ok(b._sea_loop != null and b._sea_loop.playing, "the open sea plays round her under sail (%.1f dB)" % (b._sea_loop.volume_db if b._sea_loop else -99.0))
	ok(n("hull_creak") > c0, "her planks creak (%d)" % (n("hull_creak") - c0))
	ok(n("hull_slap") > s0, "the bow slaps the waves at speed (%d, speed %.1f)" % [n("hull_slap") - s0, b.speed])
	ok(sfx.ambience.volume_db < on_beach - 3.0, "out at sea the surf fades (%.1f -> %.1f dB)" % [on_beach, sfx.ambience.volume_db])
	# gulls and a fish
	var birds: Birds = g.world.get_node("birds")
	var g0 := n("gull")
	var f0 := n("splash")
	for f in birds.flocks:
		f["pos"] = b.global_position + Vector3(randf_range(-10, 10), 6.0, randf_range(-10, 10))
	for i in 40:
		birds._call_t = minf(birds._call_t, 0.0)
		birds._fish_t = minf(birds._fish_t, 0.0)
		await wait(0.2)
		if n("gull") > g0 and n("splash") > f0:
			break
	ok(n("gull") > g0, "a gull cries (%d)" % (n("gull") - g0))
	ok(n("splash") > f0, "a fish splashes (%d)" % (n("splash") - f0))
	# ashore again: the sea loop stops
	var loop := b._sea_loop
	b.leave(g.hero)
	await wait(2.5)
	ok(loop == null or not is_instance_valid(loop), "stepping off, the sea loop fades out and is freed")
	quit()

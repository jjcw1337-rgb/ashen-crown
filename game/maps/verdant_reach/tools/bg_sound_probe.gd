extends SceneTree
## What the Battlegrounds sound like while nothing happens: loads the Verdant Reach as a run character, stands
## still, and logs the music and ambience streams, every sound played each second (Sfx.counts) and every other
## audio player left playing in the scene. `-- --sounds [secs]` (headless runs are silent without --sounds).
var g
var secs := 30

func _initialize():
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			secs = int(a)
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _name(st) -> String:
	return st.resource_path.get_file() if st != null and st.resource_path != "" else (str(st) if st != null else "none")

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.hide_title()
	g.hero.set_class("archer")
	g.hero.start_run()
	g.bg_mode = true
	g.test_immortal = true
	await g.load_zone(0, "bg", "start")
	var sfx = get_root().get_node("Sfx")
	print("[SND] zone %s  music %s (playing %s)  ambience %s (playing %s)" % [g.cur_zone, _name(sfx.music.stream), sfx.music.playing, _name(sfx.ambience.stream), sfx.ambience.playing])
	print("[SND] raid state: ", g.get("bg_raid"))
	var before: Dictionary = sfx.counts.duplicate()
	var alive0 := {}
	for e in g.world.enemies_root.get_children():
		if e is Enemy and not e.dead:
			alive0[e] = "%s pack %d at %.0f m" % [e.kind, e.pack_id, e.global_position.distance_to(g.hero.global_position)]
	await create_timer(2.0).timeout
	for e in alive0:
		if not is_instance_valid(e) or e.dead:
			print("[SND] died in the first 2 s: ", alive0[e])
	var pairs := {}
	for e in g.world.enemies_root.get_children():
		if is_instance_valid(e) and e.get("rival") != null and is_instance_valid(e.rival):
			var key := "%s(%s) vs %s(%s)" % [e.kind, e.def.get("faction", "-"), e.rival.kind, e.rival.def.get("faction", "-")]
			pairs[key] = "%.0f m from the hero, pack %s" % [e.global_position.distance_to(g.hero.global_position), str(e.get("pack_id"))]
	for k in pairs:
		print("[SND] fighting: %s  %s" % [k, pairs[k]])
	for s in secs:
		await create_timer(1.0).timeout
		var now: Dictionary = sfx.counts.duplicate()
		var fresh := []
		for k in now:
			var d := int(now[k]) - int(before.get(k, 0))
			if d > 0:
				fresh.append("%s x%d" % [k, d])
		before = now
		if not fresh.is_empty():
			print("[SND] t=%ds  %s" % [s + 1, ", ".join(fresh)])
	# every audio player still playing anywhere (loops left on, props with their own sound)
	for n in get_root().find_children("*", "AudioStreamPlayer", true, false) + get_root().find_children("*", "AudioStreamPlayer3D", true, false):
		if n.playing:
			print("[SND] playing: %s  %s  %s" % [n.get_path(), _name(n.stream), "%.1f dB" % n.volume_db])
	quit()

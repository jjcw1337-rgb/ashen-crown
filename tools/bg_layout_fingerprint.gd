extends SceneTree
## Prints a fingerprint of the Hollow Crypt's layout as this build makes it: every floor rect, obstacle, interactable
## (kind and place, in order: chest and portal indices cross the wire), monster spawn, arrival spot and the rock and
## blocked grids. The dedicated server and every client must build the same layout, so a change to
## Battlegrounds.build or World's crypt helpers that is meant to be visual only must leave this line unchanged
## (run it before and after, or against the staging branch's build).
##   godot --headless --path . -s tools/bg_layout_fingerprint.gd
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	g.ui.hide_title()
	g.playing = true
	await g.load_zone(0, Battlegrounds.ZONE, "start")
	while g._busy:
		await process_frame
	var w = g.world
	var parts := PackedStringArray()
	for r in w.floor_rects:
		parts.append("floor %s" % str(r))
	for o in w.obstacles:
		parts.append("obstacle %s" % str(o))
	for it in w.interactables:
		if is_instance_valid(it):
			parts.append("inter %s %s %s" % [it.kind, str(it.global_position), str(it.data)])
	for es in w.enemy_spawns:
		parts.append("spawn %s" % str(es))
	parts.append("spawns %s" % str(w.spawns))
	parts.append("bg_spawns %s" % str(w.get_meta("bg_spawns")))
	parts.append("bounds %s" % str(w.bounds))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(("\n".join(parts)).to_utf8_buffer())
	ctx.update(w.rock)
	ctx.update(w.blocked)
	print("[FP] obstacles %d interactables %d spawns %d floor rects %d rock cells %d" % [w.obstacles.size(), w.interactables.size(), w.enemy_spawns.size(), w.floor_rects.size(), w.rock.size()])
	print("[FP] layout %s" % ctx.finish().hex_encode())
	if OS.get_cmdline_user_args().has("verbose"):
		for p in parts:
			print("[FP] ", p)
	quit()

extends SceneTree
## Frames of Halvar at his anvil from close beside the forge (is the hammer coming down on the anvil? what's in his
## other hand?), by day. Needs a display; run with --fixed-fps 30.
##   godot --path . --fixed-fps 30 -s tools/_late.gd -- res://game/maps/camp/tools/forge_clip.gd <outdir> [frames 90] [side|front]

var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[1] if args.size() > 1 else "/tmp/forge"
	var frames: int = int(args[2]) if args.size() > 2 else 90
	var view: String = args[3] if args.size() > 3 else "side"
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	g.ui.close_all()
	g.ui.visible = false
	if g.day_night != null:
		g.day_night.fixed = 12.0
	var smith: Inter = null
	for it in g.world.find_children("*", "Inter", true, false):
		if (it as Inter).data.get("role", "") == "smith":
			smith = it
	if smith == null:
		print("[F] no smith")
		quit()
		return
	g.hero.global_position = smith.global_position + Vector3(0, 0, 12)     # out of his way (he'd turn to talk)
	# he hammers from the start
	smith.anim.play("Idle")
	smith._clip_t = 999.0
	smith.set_meta("forging", 999.0)
	var cam := Camera3D.new()
	cam.fov = 34
	get_root().add_child(cam)
	cam.current = true
	var yaw: float = smith.home_yaw
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var at: Vector3 = smith.global_position + Vector3(0, 1.0, 0)
	var eye: Vector3 = at + (side * 3.2 + fwd * 1.2 if view == "side" else fwd * 3.6 + side * 0.6) + Vector3(0, 0.9, 0)
	if view == "game":
		eye = at + fwd * 4.2 + side * 1.4 + Vector3(0, 3.6, 0)
	if view == "near":
		eye = at + fwd * 2.6 - side * 1.3 + Vector3(0, 1.5, 0)
	print("[F] tongs ", smith.has_meta("tongs"), " exists ", ResourceLoader.exists(SmithForge.TONGS))
	cam.global_transform = Transform3D(Basis(), eye).looking_at(at + fwd * 0.3, Vector3.UP)
	# where the hammer hand bottoms out against where the forge's anvil stands (forge.glb: its anvil at (-0.16, 1.07) in the
	# model's own x/z, the face about 0.82 m up, the stall scaled ForestCamp.STALL_SCALE)
	var s0: Dictionary = ForestCamp.SHOPS[1]
	var sp: Vector2 = s0["at"]
	var syaw := ForestCamp.face(sp, ForestCamp.CENTER)
	var anvil: Vector3 = Vector3(sp.x, g.world.height_at(sp.x, sp.y), sp.y) + Basis(Vector3.UP, syaw) * (Vector3(-0.16, 0.82, 1.07) * ForestCamp.STALL_SCALE)
	var sk: Skeleton3D = smith.model.find_child("Skeleton3D", true, false)
	var hb := sk.find_bone("RightHand")
	var off := Vector3.ZERO
	var low := Vector3(0, 99, 0)
	for f in frames:
		await process_frame
		var hm: Node3D = SmithForge._hammer(smith, sk)
		var hp: Vector3 = hm.global_transform * Vector3(SmithForge.HEAD_FACE, SmithForge.HEAD_AT, 0) if hm != null else Vector3.ZERO
		if hp.y < low.y:
			low = hp
		if f % 6 == 0 and view == "measure":
			print("[F] f%d head %s hand %s off %s forging %s anim %s" % [f, str(hp), str(sk.global_transform * sk.get_bone_global_pose(hb).origin), str(off), str(smith.get_meta("forging")), smith.anim.current_animation])
		if f == frames - 1:
			var rel: Vector3 = Basis(Vector3.UP, syaw).inverse() * (low - anvil)
			print("[F] hammer head lowest %s anvil %s  (in the stall's frame: %.2f across, %.2f out, %.2f up)" % [str(low), str(anvil), rel.x, rel.z, rel.y])
	if view == "measure":
		quit()
		return
	for f in frames:
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("%s/forge_%s_%03d.png" % [out, view, f])
	print("[F] done")
	quit()

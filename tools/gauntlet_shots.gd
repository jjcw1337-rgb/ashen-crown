extends SceneTree
## Screenshots of the Gauntlet of Kings (gauntlet.gd) from the game's camera: the camp's Gauntlet Gate, the throne
## hall before a run, the first king's entrance and fight (and `frames` frames of it for a GIF, every third frame),
## the offerings between kings, and a shot of each later king:
##   godot --path . -s tools/gauntlet_shots.gd -- outdir [frames] [class]
var g
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func shot(path: String) -> void:
	get_root().get_texture().get_image().save_png(path)
	print("saved ", path)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _inter(kind: String):
	for t in g.world.interactables:
		if is_instance_valid(t) and t.kind == kind:
			return t
	return null

## Fight the king for `n` frames (the hero by it, striking; the class's first skill now and then), saving GIF frames
## from `from` on when `gif`.
func fight(gt, n: int, out: String, gif: bool, from: int, nf: int) -> void:
	var fi := 0
	for k in n:
		var b = gt.boss
		if b != null and is_instance_valid(b) and not b.dead:
			if k > 90 and g.hero.global_position.distance_to(b.global_position) > 6.0 and k % 30 == 0:
				g.hero.global_position = g.world.free_spot_near(b.global_position + (gt.START - b.global_position).normalized() * 3.5, 1.0)
			if k % 140 == 70:
				g.hero.mana = g.hero.max_mana
				var own: Array = Data.skills_for(g.hero.cls)
				if not own.is_empty():
					g.hero.use_skill(str(own[(k / 140) % mini(3, own.size())]["id"]), b.global_position)
			elif g.hero.target != b:
				g.hero.target = b
		if gif and k >= from and k % 3 == 0 and fi < nf:
			shot("%s/mode_frame_%03d.png" % [out, fi])
			fi += 1
		g.hero.life = maxf(g.hero.life, g.hero.max_life * 0.6)
		if gt.boss != null and is_instance_valid(gt.boss) and gt.boss.global_position.z < gt.CENTER.z - 6.0 and k % 60 == 0:
			gt.boss.global_position = gt.boss.global_position.lerp(gt.CENTER, 0.25)     # (keep the fight in the open for the camera)
		await process_frame

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/tmp/gauntlet"
	var nf: int = int(a[1]) if a.size() > 1 else 50
	var cls: String = a[2] if a.size() > 2 else "knight"
	DirAccess.make_dir_recursive_absolute(out)
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, cls)
	g.ui.close_all()
	g.test_immortal = true
	g.hero.set_level(20)
	if g.cur_zone != "town":
		await g.load_zone(0, "town", "start")
	var gate = _inter("gauntlet_gate")
	g.hero.global_position = g.world.free_spot_near(gate.global_position + Vector3(2.5, 0, -2.5), 1.0)
	await frames(200)
	shot(out + "/gauntlet_camp_gate.png")
	g._interact(gate)
	while g.cur_zone != "gauntlet" or g._busy:
		await process_frame
	var gt = g.world.get_meta("gauntlet")
	await frames(5)
	gt.record = 0.0                   # (the hall's record on this PC isn't the shots' business)
	gt.record_by = ""
	g.hero.global_position = g.world.free_spot_near(gt.GONG + Vector3(2.0, 0, 3.0), 1.0)
	await frames(80)
	shot(out + "/gauntlet_hall.png")
	gt.begin()
	g.hero.global_position = g.world.free_spot_near(gt.CENTER + Vector3(1.5, 0, 3.0), 1.0)
	while gt.state != "fight":
		await process_frame
	await fight(gt, 140, out, false, 0, 0)
	shot(out + "/gauntlet_gorehide.png")
	await fight(gt, 40 + nf * 3, out, true, 40, nf)
	gt.boss.take_damage(1e9, 0.0, g.hero.global_position, 0.0, false)
	await frames(90)
	g.hero.global_position = g.world.free_spot_near(gt.CENTER + Vector3(0, 0, 13.0), 1.0)
	await frames(40)
	shot(out + "/gauntlet_offerings.png")
	gt.choose(1, "Blaine")
	g.hero.global_position = g.world.free_spot_near(gt.CENTER + Vector3(0, 0, 3.0), 1.0)
	while gt.state != "fight":
		await process_frame
	await fight(gt, 300, out, false, 0, 0)
	shot(out + "/gauntlet_cinderhide.png")
	gt.boss.take_damage(1e9, 0.0, g.hero.global_position, 0.0, false)
	await frames(30)
	gt.choose(2, "JJ")
	g.hero.global_position = g.world.free_spot_near(gt.CENTER + Vector3(0, 0, 3.0), 1.0)
	while gt.state != "fight":
		await process_frame
	await fight(gt, 420, out, false, 0, 0)
	shot(out + "/gauntlet_mossbeard.png")
	gt.boss.take_damage(1e9, 0.0, g.hero.global_position, 0.0, false)
	await frames(30)
	gt.choose(0, "Blaine")
	g.hero.global_position = g.world.free_spot_near(gt.CENTER + Vector3(0, 0, 3.0), 1.0)
	while gt.state != "fight":
		await process_frame
	await fight(gt, 360, out, false, 0, 0)
	shot(out + "/gauntlet_hrimgar.png")
	gt.boss.take_damage(1e9, 0.0, g.hero.global_position, 0.0, false)
	await frames(100)
	shot(out + "/gauntlet_won.png")
	quit()

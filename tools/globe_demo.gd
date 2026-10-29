extends SceneTree
## Renders the life and mana globes (scripts/globe.gd) acting out their behaviours, for previews:
## a hit, a heal, low and critical life, max life rising; a cast, regeneration, a big restore, low mana.
## Needs a display (xvfb). Usage: godot --fixed-fps 30 -s tools/globe_demo.gd -- outdir
func _initialize():
	_run()

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var life := Globe.new()
	life.kind = "life"
	life.ref_max = 120.0
	life.size = Vector2(300, 300)
	life.position = Vector2(30, 40)
	root.add_child(life)
	var mana := Globe.new()
	mana.kind = "mana"
	mana.ref_max = 40.0
	mana.size = Vector2(300, 300)
	mana.position = Vector2(370, 40)
	root.add_child(mana)
	var cap := Label.new()
	cap.position = Vector2(20, 350)
	cap.add_theme_font_size_override("font_size", 22)
	root.add_child(cap)
	var hp := 124.0
	var mhp := 124.0
	var mp := 36.0
	var mmp := 36.0
	# [seconds, caption, action]
	var script := [
		[1.0, "full", ""],
		[1.4, "Life: a heavy hit (surges down after a moment)", "hit40"],
		[1.4, "Life: healed (a bright ripple)", "heal35"],
		[1.6, "Life: low (pulses and shakes)", "low"],
		[1.8, "Life: critical (harder pulse, darker)", "crit"],
		[1.4, "Life: healed back up", "full"],
		[1.8, "Life: maximum life raised (a bigger globe)", "maxup"],
		[1.4, "Mana: a cast (drops fast, then swirls)", "cast"],
		[1.4, "Mana: another cast", "cast"],
		[2.2, "Mana: regenerating (rises slowly)", "regen"],
		[1.6, "Mana: low (a faint blue pulse)", "lowmana"],
		[1.6, "Mana: a big restore (a wave rising)", "restore"],
	]
	var dt := 1.0 / 30.0
	var f := 0
	for step in script:
		cap.text = step[1]
		match String(step[2]):
			"hit40": hp -= 50.0
			"heal35": hp = minf(mhp, hp + 40.0)
			"low": hp = mhp * 0.27
			"crit": hp = mhp * 0.08
			"full": hp = mhp
			"maxup":
				mhp = 420.0
				hp = mhp
			"cast": mp -= 9.0
			"lowmana": mp = mmp * 0.1
			"restore": mp = mmp
		var n := int(float(step[0]) / dt)
		for i in n:
			if step[2] == "regen":
				mp = minf(mmp, mp + dt * 8.0)
			life.set_value(hp, mhp)
			mana.set_value(mp, mmp)
			await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/g%04d.png" % [out, f])
			f += 1
	quit()

extends SceneTree
## Actual arrows on real stationary enemies: long frames still pierce the whole line,
## chill each target and stop ordinary arrows on the nearest foe, irrespective of insertion order.
var g
var fails := 0
func _initialize():
	BuildEnv.forced = {"env":"local","cloud":"0"}
	g = load("res://main.tscn").instantiate()
	g.char_dir = "user://gate/archer_sweep/"
	g.old_save = g.char_dir + "absent.json"
	root.add_child(g)
	current_scene = g
	_run()
func check(ok: bool, text: String):
	print("[SWEEP] ", "ok " if ok else "FAIL ", text)
	if not ok: fails += 1
func _run():
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false,"archer")
	await g.load_zone(0,"wild","start")
	var h = g.hero
	h.set_process(false)
	for e in g.world.enemies_root.get_children(): e.queue_free()
	await process_frame
	var at := Vector3.ZERO
	var found := false
	for x in range(-18,19,3):
		for z in range(-18,19,3):
			var p := Vector3(float(x),g.world.height_at(x,z),float(z))
			var end: Vector3 = g.world.move(p,Vector3(14,0,0),0.05)
			if Vector2(end.x-p.x-14,end.z-p.z).length()<0.01:
				at=p;found=true;break
		if found: break
	check(found,"found an unobstructed 14 m flight lane")
	if not found: await finish();return
	h.global_position=at
	for frame_step in [0.15, 0.35]:
		for pierces in [true,false]:
			for e in g.world.enemies_root.get_children(): e.queue_free()
			for a in h.arrows:
				if is_instance_valid(a.node): a.node.queue_free()
			h.arrows.clear()
			await process_frame
			var targets: Array=[]
			# Reverse insertion order checks that an ordinary shot hits the nearest first.
			for distance in [10.0,7.0,4.0]:
				var p: Vector3=at+Vector3(distance,0,0)
				p.y=g.world.height_at(p.x,p.z)
				var e=g.spawn_enemy("zombie",p,5,false,"",0)
				e.max_life=5000.0;e.life=5000.0;e.scripted=60.0
				targets.append(e)
			h.fx("a_glacial" if pierces else "attack","loose",{"p":at+Vector3(0.6,1.35,0),"d":Vector3.RIGHT,"k":"frost" if pierces else "war","x":pierces,"m":1.1})
			for step in range(int(ceil(0.35 / frame_step))): Archer.update(h,frame_step)
			var hits: Array=targets.map(func(e): return e.life<e.max_life)
			var chilled: Array=targets.map(func(e): return e.chill_t>0.0)
			print("[SWEEP RESULT] delta=",frame_step," piercing=",pierces," hits=",hits," chill=",chilled)
			check(hits==([true,true,true] if pierces else [false,false,true]),"hits every pierced target / nearest ordinary target")
			if pierces: check(chilled==[true,true,true],"all pierced foes chilled")
	await finish()
func finish():
	g.queue_free()
	for i in 20: await process_frame
	print("[SWEEP] done, ",fails," failures")
	quit(1 if fails else 0)

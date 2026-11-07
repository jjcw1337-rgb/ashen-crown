extends SceneTree
## Halvar at his anvil (Inter._strikes): each hammer blow in his work clip rings the anvil. Prints [N] lines.
var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.ui.close_all()
	var sfx = get_root().get_node("Sfx")
	var smith: Inter = null
	for t in g.world.interactables:
		if t.kind == "vendor" and str(t.data.get("role", "")) == "smith":
			smith = t
	print("[N] the smith: ", smith != null)
	if smith == null:
		quit()
		return
	g.hero.global_position = smith.global_position + Vector3(0, 0, 9.0)
	var n0: int = int(sfx.counts.get("anvil", 0))
	var swings := 0
	var was := ""
	for i in 240:
		await create_timer(0.05).timeout
		var cur: String = smith.anim.current_animation if smith.anim else ""
		if cur == "Heavy_Hammer_Swing" and was != cur:
			swings += 1
		was = cur
	var rings: int = int(sfx.counts.get("anvil", 0)) - n0
	print("[N] %s in 12 s: %d hammer clips, %d anvil rings" % ["ok  " if rings >= 2 else "FAIL", swings, rings])
	quit()

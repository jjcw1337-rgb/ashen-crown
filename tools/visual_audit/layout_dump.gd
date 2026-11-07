extends SceneTree
## Dumps one zone's layout as World alone builds it (interactables, enemy spawns, obstacle footprints), one
## line each, so two builds can be diffed: a visual change must not move anything (World.rng).
## Run each zone in a fresh process. Crate yaw and the Ferals' perches use Godot's global random numbers,
## so those lines already differ between two launches of the same build.
##   godot --headless --path . -s tools/visual_audit/layout_dump.gd -- out.txt 0 wild
## args: out_file run zone (town / wild / lair)
func _initialize():
	var args := OS.get_cmdline_user_args()
	var run := int(args[1])
	var zone := String(args[2])
	World.detail = 2
	var w := World.new()
	w.run = run
	w.oak_forest = run == 0
	w.fort = run == 0
	if "living_grass" in w:
		w.set("living_grass", true)
	get_root().add_child(w)
	w.build(0, zone, 4200 + ["town", "wild", "lair"].find(zone) * 7)
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	for it in w.interactables:
		f.store_line("I %s %.2f %.2f" % [it.kind, it.global_position.x, it.global_position.z])
	for es in w.enemy_spawns:
		f.store_line("S %s %.2f %.2f %d" % [es["kind"], es["pos"].x, es["pos"].z, es["count"]])
	for o in w.obstacles:
		f.store_line("O " + str(o))
	f.close()
	quit()

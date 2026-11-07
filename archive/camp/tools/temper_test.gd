extends SceneTree
## Weapon tempering at Halvar's furnace (furnace.gd, furnace_ui.gd, Items.temper_cost): the furnace stands by the
## forge in the Act I camp; only weapons, at most +5; the charge (logs, Heartwood from +4) and the fee are needed
## to light it; the heat model: time to heat, the fuel's ceiling (pine, oak, Heartwood), three logs at a time so
## flooding it does nothing, the bellows, cooling once the wood is gone; the soak only runs in the band; quenched
## early it fails (wood spent, weapon unchanged), after the soak it takes the level (+6% damage); the window opens,
## right-clicks load it, closing it mid-temper is a safe failure. Prints [T] lines.
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	print("[T] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1

## Runs the fire for `secs` in 0.1 s steps; returns the peak temperature.
func burn(f, secs: float, bellows := false) -> float:
	f.bellows = bellows
	var peak := 0.0
	for i in int(secs * 10.0):
		f.step(0.1)
		peak = maxf(peak, f.temp)
	f.bellows = false
	return peak

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	await g.load_zone(0, "town", "start")
	await create_timer(0.3).timeout
	var f = null
	for t in g.world.interactables:
		if t.kind == "furnace":
			f = t
	check(f != null, "the camp has a furnace")
	if f == null:
		quit(1)
		return
	var smith = null
	for t in g.world.interactables:
		if t.kind == "vendor" and str(t.data.get("role", "")) == "smith":
			smith = t
	check(smith != null and f.global_position.distance_to(smith.global_position) < 8.0, "beside the smith (%.1f m)" % f.global_position.distance_to(smith.global_position))
	check(not g.world.solid_at(f.global_position.x + 2.6 * sin(f.rotation.y), f.global_position.z + 2.6 * cos(f.rotation.y), 0.3), "its front is clear to stand at")
	var hero: Hero = g.hero
	hero.gold = 100000
	hero.inventory.fill(null)

	# what can be tempered
	var sword: Dictionary = hero.equipment["weapon"]
	var armor = hero.equipment.get("armor")
	check(f.choose(armor) != "", "armour is refused")
	var maxed := sword.duplicate(true)
	maxed["temper"] = Items.TEMPER_MAX
	check(f.choose(maxed) != "", "a +5 weapon is refused")
	check(f.choose(sword) == "", "the sword goes before the fire")
	var c: Dictionary = f.cost
	print("[T] +1 costs %s" % c)
	check(f.missing(hero).begins_with("Load"), "it needs its charge first")
	check(f.ignite(hero) != "" and not f.lit, "can't light it uncharged")

	# the heat: pine alone stops at its ceiling, however much goes in
	hero.add_to_inventory(Items.resource("pine_log", 50))
	f.load_fuel(hero, "pine_log", 50)
	check(f.hopper.size() == 50 and hero.count_of("pine_log") == 0, "50 pine loaded from the bag")
	var gold0 := hero.gold
	check(f.ignite(hero) == "" and f.lit and hero.gold == gold0 - int(c["gold"]), "lit; the fee paid (%d gold)" % int(c["gold"]))
	var t10: float = burn(f, 10.0)
	check(t10 < 900.0, "it takes time to heat (%.0f °C after 10 s)" % t10)
	var peak: float = burn(f, 60.0, true)
	check(peak <= float(Data.BASES["pine_log"]["fuel"]["max_temp"]) + 0.5, "pine never passes %d °C (peak %.0f)" % [int(Data.BASES["pine_log"]["fuel"]["max_temp"]), peak])
	check(f.burning.size() <= Furnace.SLOTS, "no more than %d logs burn at once" % Furnace.SLOTS)
	check(f.soak >= float(c["soak"]) - 0.01, "+1's soak completes at cherry heat (%.1f / %.1f s)" % [f.soak, float(c["soak"])])
	var d0: Array = Items.damage_of(sword)
	check(f.quench(hero) and int(sword.get("temper", 0)) == 1, "quenched after the soak: +1")
	var d1: Array = Items.damage_of(sword)
	print("[T] damage %s -> %s" % [d0, d1])
	check(d1[1] > d0[1], "it hits harder")
	check(f.hopper.is_empty() and not f.spent.is_empty(), "the rest of the charge burns on, but is spent")

	# +2 needs orange; quenching early fails and changes nothing
	check(f.choose(sword) == "", "back in for +2")
	c = f.cost
	hero.add_to_inventory(Items.resource("oak_log", 50))
	f.load_fuel(hero, "oak_log", int(c["logs"]))
	f.ignite(hero)
	burn(f, 4.0)
	check(f.soak < float(c["soak"]), "a few seconds in, the soak isn't done")
	check(not f.quench(hero) and int(sword["temper"]) == 1 and f.last_result == "fail", "quenched too soon: no temper, the sword is as it was")

	# oak can't reach white (+4): its ceiling is below 1250
	var it4 := sword.duplicate(true)
	it4["temper"] = 3
	check(f.choose(it4) == "", "a +3 weapon for +4")
	c = f.cost
	check(int(c["heart"]) == 2 and float(c["temp"]) == 1250.0, "+4 needs white heat and Ashen Heartwood (%s)" % c)
	f.spent.clear()
	f.burning.clear()
	f.temp = Furnace.AMBIENT
	hero.add_to_inventory(Items.resource("oak_log", 50))
	f.load_fuel(hero, "oak_log", int(c["logs"]))
	check(f.missing(hero).find("Heartwood") >= 0, "an all-oak charge is refused for +4")
	hero.add_to_inventory(Items.resource("heartwood", 4))
	f.unload(hero)
	# wood burns in the order it's loaded: oak to bring the fire up, then the Heartwood to take it past oak's ceiling
	f.load_fuel(hero, "oak_log", 6)
	f.load_fuel(hero, "heartwood", 2)
	f.load_fuel(hero, "oak_log", int(c["logs"]) - 8)
	check(f.ignite(hero) == "", "with Heartwood it lights")
	var p4: float = burn(f, 150.0, true)
	print("[T] +4 fire: peak %.0f °C, soak %.1f / %.1f" % [p4, f.soak, float(c["soak"])])
	check(p4 >= 1250.0 and p4 <= Furnace.MAX_T, "Heartwood takes it to white heat, never past %d °C" % int(Furnace.MAX_T))
	check(f.quench(hero) and int(it4["temper"]) == 4, "+4 taken with the minimum charge, loaded oak first")

	# without fuel it cools
	var hot: float = f.temp
	f.spent.clear()
	f.hopper.clear()
	f.burning.clear()
	f.lit = false
	burn(f, 60.0)
	check(f.temp < hot * 0.4, "with nothing left to burn it cools (%.0f -> %.0f °C)" % [hot, f.temp])

	# the window: opens at the furnace, right-click loads, closing mid-temper is a safe failure
	f.temp = Furnace.AMBIENT
	hero.global_position = f.global_position + Vector3(0, 0, 2.0)
	g._interact(f)
	check(g.ui.furnace_ui.visible and g.ui.inv_panel.visible and g.ui.shop_mode == "furnace", "the furnace window opens beside the bag")
	check(f.item == hero.equipment["weapon"], "the weapon in hand comes to the fire")
	hero.inventory.fill(null)
	hero.inventory[0] = Items.resource("oak_log", 20)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.shift_pressed = true
	g.ui._inv_click(0, ev)
	check(f.hopper.size() == 5 and hero.count_of("oak_log") == 15, "shift-right-click loads five")
	await process_frame
	g.ui.furnace_ui._refresh()
	print("[T] status: ", g.ui.furnace_ui.status_lbl.text, " | ", g.ui.furnace_ui.charge_lbl.text)
	var t_before := int(hero.equipment["weapon"].get("temper", 0))
	f.load_fuel(hero, "oak_log", 15)
	if f.ignite(hero) == "":
		burn(f, 5.0)
	g.ui.close_all()
	check(not g.ui.furnace_ui.visible and f.session == "idle" and int(hero.equipment["weapon"].get("temper", 0)) == t_before, "closing it mid-temper: the weapon safe, the temper lost")
	# the tooltip says so
	var tip: Array = Items.tooltip(sword)
	check(tip.any(func(l) -> bool: return str(l[0]).begins_with("Tempered +1")), "the tooltip shows the temper")
	print("[T] done, %d failures" % fails)
	quit(1 if fails > 0 else 0)

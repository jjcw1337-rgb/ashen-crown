class_name DwarfGame
extends RefCounted
## The drunken dwarves of the Verdant Isle (Blaine, 2026-11-01): three dwarves round a keg in the mouth of a jungle
## tunnel, off the path. Talk to them and they'll bet you on rock-paper-scissors, best of three (UI dialogs, their
## throw at random, one round at a time). Win: their prize (a rare piece of gear for your class and a purse) and a
## toast; you may still call them out and fight them. Lose: they don't take it kindly and come at you, hard (three
## champion dwarves, well above the island's level). Once per character (Hero.dwarves, saved): after it they're
## asleep, or dead, or gone. Offline and for the host; a co-op partner sees the fight like any monsters.
##   DwarfGame.camp(w, isle, o, at)     the dwarves, the keg and the Inter (Isle Verdant's builder)
##   DwarfGame.talk(game, inter)        Game._interact "dwarves"

const THROWS := ["Rock", "Paper", "Scissors"]
const LINES := ["“Oi! You. Yes, you. Fancy a wager? Best of three. Win and you get the good stuff. Lose and... well.”",
	"“Another round! My brother cheats, you know. Watch his hands.”", "“Last one. Make it count.”"]

static func camp(w: World, isle: Dictionary, o: Vector2, at: Vector2) -> void:
	var c := Isles.at(w, isle, o, at + Vector2(0, 4.0))
	for k in 3:
		var a := TAU * k / 3.0 + 0.3
		var p := c + Vector3(cos(a) * 1.6, 0, sin(a) * 1.6)
		var m: Node3D = MeshyMonster.build("dwarf", Data.ENEMIES["dwarf"]["look"]) if MeshyMonster.ok("dwarf") else Models.humanoid(Data.ENEMIES["dwarf"]["look"])
		var holder := Node3D.new()
		holder.add_child(m)
		w._place(holder, p)
		holder.rotation.y = atan2(-(c - p).x, -(c - p).z)
		holder.add_to_group("tunnel_dwarves")
		w.add_circle(p, 0.5)
	var keg := Props.barrel(w.props_root, c)
	w.solid(keg)
	Props.fire(w.props_root, c + Vector3(2.4, 0, 0.6), 0.8, Color(1.0, 0.6, 0.25), true)
	var it: Inter = w._inter("dwarves", "Drunken Dwarves", c + Vector3(0, 0, 1.6), 3.2, null, {})
	it.set_meta("dwarf_spots", [c + Vector3(-1.5, 0, 0), c + Vector3(1.5, 0, 0), c + Vector3(0, 0, -1.5)])

static func talk(game: Node, t: Inter) -> void:
	var h: Hero = game.hero
	match h.dwarves:
		"won":
			game.ui.open_dialog("Drunken Dwarves", "“You again! Lucky. Very lucky. Go on, have a drink, you've earned it.”",
				[["Call them out", func(): _fight(game, t, "fought")], ["Leave them to it", func(): pass]])
			return
		"lost", "fought":
			game.ui.message("Nothing stirs by the keg now.", Color(0.8, 0.8, 0.8))
			return
	_round(game, t, 0, 0, 0)

static func _round(game: Node, t: Inter, n: int, mine: int, theirs: int) -> void:
	var txt: String = LINES[mini(n, LINES.size() - 1)] + "\n\nYou %d  ·  Dwarves %d" % [mine, theirs]
	var opts := []
	for k in 3:
		var pick := k
		opts.append([THROWS[k], func(): _throw(game, t, n, mine, theirs, pick)])
	game.ui.open_dialog("Rock, Paper, Scissors", txt, opts)

static func _throw(game: Node, t: Inter, n: int, mine: int, theirs: int, you: int) -> void:
	var them := randi() % 3
	var res := "A draw! Again."
	if you != them:
		if (you - them + 3) % 3 == 1:
			mine += 1
			res = "%s beats %s. Point to you." % [THROWS[you], THROWS[them]]
		else:
			theirs += 1
			res = "%s beats %s. Point to the dwarves." % [THROWS[them], THROWS[you]]
	Sfx.play("click")
	game.ui.message(res, Color(1.0, 0.85, 0.5))
	if mine >= 2:
		_win(game, t)
	elif theirs >= 2:
		# they come at once: closing the window mustn't buy another game
		_fight(game, t, "lost")
		game.ui.open_dialog("Drunken Dwarves", "“HA! Pay up. Oh, you've no coin? Then we'll take it out of your hide!”",
			[["Fight!", func(): pass]])
	else:
		_round(game, t, n + (0 if you == them else 1), mine, theirs)

static func _win(game: Node, t: Inter) -> void:
	var h: Hero = game.hero
	h.dwarves = "won"
	var r := RandomNumberGenerator.new()
	r.randomize()
	var slot: String = ["weapon", "armor", "helm", "gloves", "boots", "belt", "amulet"][r.randi() % 7]
	var base: String = game._boost_base(slot) if game.has_method("_boost_base") else ""
	var prize: Dictionary = Items.generate(base, maxi(h.level + 2, 12), 2, r) if base != "" else Items.random_drop(h.level + 2, 300.0, r, true)
	game.drop_item(prize, t.global_position + Vector3(0, 0, 1.0))
	h.gold += 300 + h.level * 20
	Sfx.play("relic_ting")
	game.ui.big_message("You beat the dwarves!")
	game.ui.open_dialog("Drunken Dwarves", "“Bah! Fine, fine. Take it, and the coin. To your health! Hic.”",
		[["Cheers", func(): pass], ["Call them out anyway", func(): _fight(game, t, "fought")]])
	if game.char_id != "":
		game.save_game()

static func _fight(game: Node, t: Inter, how: String) -> void:
	var h: Hero = game.hero
	h.dwarves = how
	for n in game.world.get_tree().get_nodes_in_group("tunnel_dwarves"):
		n.queue_free()
	var spots: Array = t.get_meta("dwarf_spots", [t.global_position])
	var lvl := int(game.world.level) + 4
	for p in spots:
		var e = game.spawn_enemy("dwarf", p, lvl, true, "Drunken Dwarf", 1300)
		if e != null:
			e.aggro = true
	game.ui.big_message("The dwarves attack!")
	Sfx.play("battle_cry", -3.0, 0.75)
	t.used = true
	if game.char_id != "":
		game.save_game()

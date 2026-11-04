class_name Sandbox
extends Node
## The Proving Crypt (zone "sandbox"): the admins' Battlegrounds sandbox (Blaine, 2026-11-02: "a little quick
## battleground sim ... so we can easily test characters + item balancing ... put some npcs in there and pvp").
## Opened from the Escape menu's Admin column (Game.open_sandbox). Local and offline: the admin plays any class at
## level 1, 5, 10 or 20, fresh or geared, against bots (Hero.bot, played by a BotBrain) of any class, level and
## gear, and against monster packs, in a walled crypt hall. Nothing is saved while inside (Game.char_id is set
## aside and the character comes back as it was on leaving).
##
## PvP is the raid's: every hero here has an invisible stand-in (an Enemy with `sandbox_hero`) that every skill,
## swing, arrow and burn can hit; the blow is dealt to that hero at Battlegrounds.PVP_MULT through Hero.take_hit
## (armour, resist, block, dodge, wards all count), stuns and slows reach them, and no hero is hit by its own
## blows (Hero.striker). Monsters go for the nearest hero, bots included (Game.target_for). Bots fight the admin, and
## each other with "free for all" on. The panel on the left counts what everyone deals and takes (note_hit): damage
## a second over the last 5 s, totals, and how long each kill took.

const ZONE := "sandbox"
const TITLE := "The Proving Crypt"
const HALL := Rect2(-20.0, -20.0, 40.0, 40.0)
const LEVELS := [1, 5, 10, 20]
const GEARS := ["fresh", "geared"]
## Stat points per level by class (as tools/pvp_sim.gd spends them).
const POINTS := {"knight": {"str": 2, "dex": 1, "vit": 2}, "wraith": {"str": 1, "dex": 2, "vit": 2}, "demon": {"str": 2, "vit": 2, "ene": 1},
	"warlock": {"str": 1, "vit": 2, "ene": 2}, "archer": {"dex": 2, "vit": 2, "str": 1}, "plague": {"dex": 1, "vit": 2, "ene": 2},
	"doug": {"str": 2, "dex": 1, "vit": 2}}
## Monster packs the panel can call in: label -> [kind, count]
const PACKS := [["Zombies x5", "zombie", 5], ["Fallen x3", "fallen_reaver", 3], ["Skeleton archers x3", "skel_archer", 3],
	["A champion", "fallen_reaver", 1]]
const WINDOW := 5.0          # seconds the damage-a-second meters look back
const RESPAWN := 4.0         # a fallen bot stands up again after this
const COLORS := [Color(1.0, 0.45, 0.35), Color(0.5, 0.75, 1.0), Color(0.6, 1.0, 0.5), Color(1.0, 0.85, 0.35),
	Color(0.85, 0.55, 1.0), Color(1.0, 0.6, 0.85)]

var game
var bots: Array = []          # {hero, proxy, brain, label, dead_t}
var me_proxy: Enemy = null
var ffa := false
var hits: Array = []          # [time, from Hero, to Hero, damage]
var totals := {}              # Hero -> {"dealt": x, "taken": y}
var fight_start := {}         # Hero -> when it first took a blow since it last stood up
var log_lines: Array = []     # the kills, newest last
var t := 0.0
var panel: PanelContainer = null
var meter: Label = null
var _meter_t := 0.0
# the panel's picks
var pick_me := {"cls": "knight", "lvl": 20, "gear": "geared"}
var pick_bot := {"cls": "knight", "lvl": 20, "gear": "geared"}

static func build(w: World) -> void:
	w.flat_floor = true
	w.theme = {"name": "bg"}
	w.floor_rects.append(HALL)
	w.bounds = HALL.grow(3.0)
	w.dirt_blobs = [[w.bounds.get_center(), 9999.0, 1.0]]
	w.dirt_lines = []
	# a ring of pillars to fight round and break line of sight, torches, braziers, light enough to read the fight
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		w._pillar(Vector3(cos(a) * 11.0, 0, sin(a) * 11.0), 5.0)
	for k in 4:
		w._wall_torch(Vector3(lerpf(HALL.position.x + 4.0, HALL.end.x - 4.0, k / 3.0), 0, HALL.position.y + 0.15), k == 1 or k == 2)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Vigil._brazier(w, Vector3(sx * 15.0, 0, sz * 15.0))
	for k in 4:
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.75, 0.5)
		fill.light_energy = 0.9
		fill.omni_range = 16.0
		fill.shadow_enabled = false
		fill.position = Vector3(cos(TAU * k / 4.0) * 9.0, 4.0, sin(TAU * k / 4.0) * 9.0)
		w.props_root.add_child(fill)
	w._candles(Vector3(0, 0, 0), true)
	for k in 8:
		w._bones(Vector3(w.rng.randf_range(-17, 17), 0, w.rng.randf_range(-17, 17)))
	w.crypt_shell()
	w.spawns["start"] = Vector3(0, 0, 12)

## A hero dressed for a test: class, level (its stat points spent the class's way, the auto talents), and either
## its starting kit ("fresh") or rare gear of its level in every slot ("geared", Game._boost_base), full potions.
static func outfit(g: Node, h: Hero, cls: String, lvl: int, gear: String) -> void:
	if h.dead:
		h.respawn(h.global_position)
	h.set_class(cls)
	h.new_character()
	h.level = lvl
	var pts := (lvl - 1) * 5
	var w: Dictionary = POINTS.get(cls, {"str": 1, "dex": 1, "vit": 1})
	var wsum := 0
	for k in w:
		wsum += int(w[k])
	for k in w:
		var n := int(pts * int(w[k]) / float(wsum))
		match k:
			"str": h.str_ += n
			"dex": h.dex += n
			"vit": h.vit += n
			"ene": h.ene += n
	h.stat_points = 0
	if gear == "geared":
		var rng := RandomNumberGenerator.new()
		for slot in Items.EQUIP_SLOTS:
			if slot == "shield" and cls != "knight":
				continue
			var base: String = g._boost_base(slot, h, lvl) if slot != "shield" else ("kite_shield" if lvl >= 6 else "buckler")
			if base == "" or not Data.BASES.has(base):
				continue
			rng.seed = hash(slot) + lvl
			seed(hash(slot) + lvl)
			h.equipment[slot] = Items.generate(base, lvl, 2, rng)
	h.talents = Talents.auto_build(cls, lvl - 1)
	h._talents_changed()
	h.belt = [Items.potion("hp_potion"), Items.potion("hp_potion"), Items.potion("mp_potion"), Items.potion("shadow_phial") if int(h.stats.get("phial", 0)) > 0 else Items.potion("rejuv")]
	for b in h.belt:
		b["count"] = 3          # (a raid's kit: ten each outhealed every level-1 duel)
	h.refresh_gear()
	h.recalc()
	h.life = h.max_life
	h.mana = h.max_mana
	h.stamina = h.max_stamina
	for k in h.cds.keys():
		h.cds[k] = 0.0

static func describe(cls: String, lvl: int, gear: String) -> String:
	return "%s L%d %s" % [str(Data.CLASSES.get(cls, {}).get("name", cls)), lvl, gear]

func _init(g: Node) -> void:
	game = g
	name = "Sandbox"

func _ready() -> void:
	_build_panel()

func spawn_point() -> Vector3:
	return game.world.free_spot_near(Vector3(randf_range(-6, 6), 0, randf_range(8, 14)), 1.0)

func bot_heroes() -> Array:
	var out := []
	for b in bots:
		if is_instance_valid(b["hero"]):
			out.append(b["hero"])
	return out

## The nearest standing hero to `p`, the player or a bot (monsters' target, Game.target_for).
func nearest_hero(p: Vector3) -> Hero:
	var best: Hero = game.hero
	var bd: float = INF if game.hero.dead else game.hero.global_position.distance_squared_to(p)
	for h in bot_heroes():
		if h.dead:
			continue
		var d: float = h.global_position.distance_squared_to(p)
		if d < bd:
			bd = d
			best = h
	return best

func spawn_bot(cls: String, lvl: int, gear: String) -> Hero:
	var h := Hero.new()
	h.bot = true
	h.name = "Bot%d" % (bots.size() + 1)
	game.add_child(h)
	h.setup(game)
	outfit(game, h, cls, lvl, gear)
	var a := randf() * TAU
	h.global_position = game.world.free_spot_near(Vector3(cos(a) * 8.0, 0, -6.0 + sin(a) * 4.0), 1.0)
	h.light.light_energy = 0.4
	var col: Color = COLORS[bots.size() % COLORS.size()]
	var tag := Label3D.new()
	tag.text = describe(cls, lvl, gear)
	tag.font_size = 36
	tag.outline_size = 10
	tag.pixel_size = 0.006
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.modulate = col
	tag.position = Vector3(0, 2.6, 0)
	h.add_child(tag)
	h.ally_color = col
	var b := {"hero": h, "proxy": _proxy(h, tag.text), "brain": BotBrain.new(), "label": tag.text, "dead_t": 0.0}
	bots.append(b)
	_ensure_me_proxy()
	return h

func _proxy(h: Hero, nm: String) -> Enemy:
	var e := Enemy.new()
	e.sandbox_hero = h
	game.world.enemies_root.add_child(e)
	e.global_position = h.global_position
	e.setup(game, "zombie", maxi(1, h.level))
	e.def = (e.def as Dictionary).duplicate()
	e.def.erase("faction")           # (no monster takes it for a rival)
	e.display_name = nm
	e.rig.visible = false
	e.max_life = h.max_life
	e.life = h.life
	return e

func _ensure_me_proxy() -> void:
	if me_proxy == null or not is_instance_valid(me_proxy):
		me_proxy = _proxy(game.hero, game.char_name if game.char_name != "" else "You")

## Is `who` (a bot) hostile to the hero `other` stands for?
func _hostile(who: Hero, other: Hero) -> bool:
	if other == who:
		return false
	return other == game.hero or ffa

## What a bot fights: the nearest hostile hero's stand-in within 30 m (a hero over a monster when one is within
## 18 m), else the nearest monster.
func pick_for(h: Hero) -> Enemy:
	var best: Enemy = null
	var bd := 30.0 * 30.0
	var hero_best: Enemy = null
	var hd := 18.0 * 18.0
	for e in game.world.enemies_root.get_children():
		if not (e is Enemy) or e.dead or e.pvp_pid > 0:
			continue
		var d: float = e.global_position.distance_squared_to(h.global_position)
		if e.sandbox_hero != null:
			if not _hostile(h, e.sandbox_hero) or e.sandbox_hero.dead or e.sandbox_hero.invis_t > 0.0:
				continue
			if d < hd:
				hd = d
				hero_best = e
		if d < bd:
			bd = d
			best = e
	return hero_best if hero_best != null else best

## A blow landed (Enemy.take_damage on a stand-in): `from` dealt `dmg` to `to`.
func note_hit(from: Hero, to: Hero, dmg: float) -> void:
	if dmg <= 0.0:
		return
	hits.append([t, from, to, dmg])
	if from != null:
		_tot(from)["dealt"] += dmg
	_tot(to)["taken"] += dmg
	if not fight_start.has(to):
		fight_start[to] = t

func _tot(h: Hero) -> Dictionary:
	if not totals.has(h):
		totals[h] = {"dealt": 0.0, "taken": 0.0}
	return totals[h]

## Damage a second dealt (or taken) over the last WINDOW seconds, over the time since the first of those hits (at
## least a second): dividing a fight's first seconds by the whole window read as a delay (Blaine, 2026-11-03: "doesnt
## show damage on meter but its doing damage"), the rate crawling up for five seconds after the blows began.
func rate(h: Hero, dealt := true) -> float:
	var s := 0.0
	var first := t
	for x in hits:
		if t - float(x[0]) <= WINDOW and (x[1] if dealt else x[2]) == h:
			s += float(x[3])
			first = minf(first, float(x[0]))
	return s / clampf(t - first, 1.0, WINDOW) if s > 0.0 else 0.0

func hero_died(h: Hero) -> void:
	var secs: float = t - float(fight_start.get(h, t))
	fight_start.erase(h)
	var killer := ""
	for i in range(hits.size() - 1, -1, -1):
		if hits[i][2] == h and hits[i][1] != null:
			killer = _name_of(hits[i][1])
			break
	log_lines.append("%s fell%s after %.1f s" % [_name_of(h), (" to " + killer) if killer != "" else "", secs])
	while log_lines.size() > 6:
		log_lines.pop_front()

func _name_of(h: Hero) -> String:
	if h == game.hero:
		return "You"
	for b in bots:
		if b["hero"] == h:
			return str(b["label"])
	return "?"

func _process(delta: float) -> void:
	if game.world == null or game._busy or game.cur_zone != ZONE:
		return
	t += delta
	while not hits.is_empty() and t - float(hits[0][0]) > 30.0:
		hits.pop_front()
	_ensure_me_proxy()
	_sync(me_proxy, game.hero)
	var pick := Callable(self, "pick_for")
	for b in bots:
		var h: Hero = b["hero"]
		if not is_instance_valid(h):
			continue
		_sync(b["proxy"], h)
		if h.dead:
			if float(b["dead_t"]) <= 0.0:
				hero_died(h)
			b["dead_t"] = float(b["dead_t"]) + delta
			if float(b["dead_t"]) >= RESPAWN:
				b["dead_t"] = 0.0
				h.respawn(game.world.free_spot_near(Vector3(randf_range(-10, 10), 0, randf_range(-14, -4)), 1.0))
				h.life = h.max_life
				h.mana = h.max_mana
			continue
		(b["brain"] as BotBrain).think(h, pick, delta)
	_meter_t -= delta
	if _meter_t <= 0.0:
		_meter_t = 0.25
		_update_meter()

func _sync(e: Enemy, h: Hero) -> void:
	if e == null or not is_instance_valid(e) or not is_instance_valid(h):
		return
	e.global_position = h.global_position
	e.max_life = h.max_life
	e.life = maxf(1.0, h.life)
	e.dead = h.dead

func clear_bots() -> void:
	for b in bots:
		if is_instance_valid(b["proxy"]):
			b["proxy"].queue_free()
		if is_instance_valid(b["hero"]):
			SkillFx.clear(b["hero"])
			b["hero"].queue_free()
	bots.clear()

func clear_monsters() -> void:
	for e in game.world.enemies_root.get_children():
		if e is Enemy and e.sandbox_hero == null:
			e.queue_free()

func spawn_pack(kind: String, n: int, champ := false) -> void:
	var lvl: int = game.hero.level
	var a := randf() * TAU
	var at := Vector3(cos(a) * 9.0, 0, sin(a) * 9.0)
	for i in n:
		var p: Vector3 = game.world.free_spot_near(at + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 0.8)
		var e: Enemy = game.spawn_enemy(kind, p, lvl, champ)
		if e != null:
			e.aggro = true

func reset_meters() -> void:
	hits.clear()
	totals.clear()
	fight_start.clear()
	log_lines.clear()

func shutdown() -> void:
	clear_bots()
	if me_proxy != null and is_instance_valid(me_proxy):
		me_proxy.queue_free()
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	queue_free()

# ---------------------------------------------------------------- the panel
func _build_panel() -> void:
	var ui = game.ui
	panel = PanelContainer.new()
	panel.name = "sandbox_panel"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.offset_left = 14
	panel.offset_top = 70
	panel.offset_right = 380
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.hud.add_child(panel)
	ui._ornate(panel, 0.16, 8)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	panel.add_child(vb)
	var t0: Label = ui._label(TITLE.to_upper(), 20, Color(0.55, 0.85, 1.0), true)
	t0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t0)
	vb.add_child(_picker("You", pick_me))
	var apply: Button = ui._iron_button("Become this hero", 330, 34, 15)
	apply.pressed.connect(func():
		apply.release_focus()
		outfit(game, game.hero, pick_me["cls"], int(pick_me["lvl"]), pick_me["gear"])
		game.ui.refresh()
		reset_meters())
	vb.add_child(apply)
	vb.add_child(ui._divider(10))
	vb.add_child(_picker("Bot", pick_bot))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var sp: Button = ui._iron_button("Spawn bot", 160, 34, 15)
	sp.pressed.connect(func():
		sp.release_focus()
		spawn_bot(pick_bot["cls"], int(pick_bot["lvl"]), pick_bot["gear"]))
	row.add_child(sp)
	var cb: Button = ui._iron_button("Clear bots", 160, 34, 15)
	cb.pressed.connect(func():
		cb.release_focus()
		clear_bots())
	row.add_child(cb)
	vb.add_child(row)
	var ff: Button = ui._iron_button("", 330, 32, 14)
	var ff_text := func(): ff.text = "Bots fight each other: " + ("ON" if ffa else "off")
	ff_text.call()
	ff.pressed.connect(func():
		ff.release_focus()
		ffa = not ffa
		ff_text.call())
	vb.add_child(ff)
	vb.add_child(ui._divider(10))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 5)
	for pk in PACKS:
		var pb: Button = ui._iron_button(str(pk[0]), 160, 32, 13)
		var kind: String = pk[1]
		var n: int = pk[2]
		var champ: bool = str(pk[0]).begins_with("A champion")
		pb.pressed.connect(func():
			pb.release_focus()
			spawn_pack(kind, n, champ))
		grid.add_child(pb)
	vb.add_child(grid)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	var cm: Button = ui._iron_button("Clear monsters", 160, 32, 13)
	cm.pressed.connect(func():
		cm.release_focus()
		clear_monsters())
	row2.add_child(cm)
	var rm: Button = ui._iron_button("Reset meters", 160, 32, 13)
	rm.pressed.connect(func():
		rm.release_focus()
		reset_meters())
	row2.add_child(rm)
	vb.add_child(row2)
	vb.add_child(ui._divider(10))
	meter = ui._label("", 13, Color(0.9, 0.87, 0.8))
	meter.custom_minimum_size = Vector2(330, 0)
	meter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(meter)
	var leave: Button = ui._iron_button("Leave the sandbox", 330, 36, 15)
	leave.add_theme_color_override("font_color", Color(1.0, 0.62, 0.48))
	leave.pressed.connect(func():
		leave.release_focus()
		game.close_sandbox())
	vb.add_child(leave)

## Class / level / gear pickers for `pick` (a row of buttons that cycle).
func _picker(title: String, pick: Dictionary) -> Control:
	var ui = game.ui
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var l: Label = ui._label(title, 14, Color(0.75, 0.7, 0.6))
	l.custom_minimum_size = Vector2(34, 0)
	row.add_child(l)
	var classes: Array = Data.CLASSES.keys().filter(func(c): return POINTS.has(c))
	var cbtn: Button = ui._iron_button("", 130, 32, 13)
	var lbtn: Button = ui._iron_button("", 64, 32, 13)
	var gbtn: Button = ui._iron_button("", 96, 32, 13)
	var refresh := func():
		cbtn.text = str(Data.CLASSES[pick["cls"]]["name"])
		lbtn.text = "L%d" % int(pick["lvl"])
		gbtn.text = str(pick["gear"]).capitalize()
	refresh.call()
	cbtn.pressed.connect(func():
		cbtn.release_focus()
		pick["cls"] = classes[(classes.find(pick["cls"]) + 1) % classes.size()]
		refresh.call())
	lbtn.pressed.connect(func():
		lbtn.release_focus()
		pick["lvl"] = LEVELS[(LEVELS.find(int(pick["lvl"])) + 1) % LEVELS.size()]
		refresh.call())
	gbtn.pressed.connect(func():
		gbtn.release_focus()
		pick["gear"] = GEARS[(GEARS.find(pick["gear"]) + 1) % GEARS.size()]
		refresh.call())
	row.add_child(cbtn)
	row.add_child(lbtn)
	row.add_child(gbtn)
	return row

func _update_meter() -> void:
	if meter == null:
		return
	var h: Hero = game.hero
	var lines := []
	lines.append("You (%s): %d life, %d armour, %d-%d dmg" % [describe(h.cls, h.level, "").strip_edges(), int(h.max_life), h.armor, h.dmg_min, h.dmg_max])
	lines.append("  deal %.0f/s, take %.0f/s   (total %d / %d)" % [rate(h), rate(h, false), int(_tot(h)["dealt"]), int(_tot(h)["taken"])])
	for b in bots:
		var bh: Hero = b["hero"]
		if not is_instance_valid(bh):
			continue
		lines.append("%s: %s" % [b["label"], ("down" if bh.dead else "%d/%d life" % [int(bh.life), int(bh.max_life)])])
		lines.append("  deal %.0f/s, take %.0f/s   (total %d / %d)" % [rate(bh), rate(bh, false), int(_tot(bh)["dealt"]), int(_tot(bh)["taken"])])
	if not log_lines.is_empty():
		lines.append("")
		lines.append_array(log_lines)
	meter.text = "\n".join(lines)

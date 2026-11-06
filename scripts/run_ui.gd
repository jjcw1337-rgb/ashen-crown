class_name RunUI
extends Control
## The run character's windows (Blaine's overhaul, 2026-11-06), in the multiplayer look (MpStyle):
##   the build window (I, K or a bar slot): the primary attack, the five skill slots, the spellbook, passives, gear and
##     the four consumables; pick a slot then a skill (or a skill then a slot) to assign, right-click a slot to clear
##   the swap window: a found piece of gear against the one worn, Equip (the old one is left on the ground) or Leave
##   the upgrade window: a camp chest's three choices (RunBuild.offer_for), one to take
## Only for a hero with `run` (multiplayer); single player keeps its old windows.

var ui: UI
var game
var hero: Hero:
	get: return game.hero if game != null else null
var mode := ""
## The build window's selection: a slot waiting for a skill, or a skill waiting for a slot.
var pick_slot := ""
var pick_skill := ""
var _win: Control
## The offer the upgrade window shows, and the swap window's item and ground node.
var offer_key := ""
var swap_item := {}
var swap_node: Node = null

func setup(u: UI) -> void:
	ui = u
	game = u.game
	name = "RunUI"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	get_viewport().size_changed.connect(func(): if visible: size = get_viewport_rect().size)

func close() -> bool:
	if not visible:
		return false
	visible = false
	mode = ""
	pick_slot = ""
	pick_skill = ""
	swap_node = null
	for c in get_children():
		c.queue_free()
	return true

func _unhandled_key_input(ev: InputEvent) -> void:
	if visible and ev.is_pressed() and (ev as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

## A fresh modal: the scrim and a centred window of `width`.
func _open(m: String, width: float) -> VBoxContainer:
	for c in get_children():
		c.queue_free()
	mode = m
	visible = true
	position = Vector2.ZERO
	size = get_viewport_rect().size     # (the windows layer's own size isn't laid out for a late child)
	add_child(MpStyle.scrim(close))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var p := MpStyle.panel(MpStyle.INK, Color(1, 1, 1, 0.1), 10, 26)
	p.custom_minimum_size.x = minf(width, get_viewport_rect().size.x - 32.0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(p)
	_win = p
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	p.add_child(vb)
	return vb

func _header(vb: VBoxContainer, eyebrow: String, title: String, sub := "") -> void:
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(col)
	col.add_child(MpStyle.eyebrow(eyebrow))
	col.add_child(MpStyle.label(title, 28, MpStyle.IVORY, 700, true))
	if sub != "":
		col.add_child(MpStyle.para(sub, 14, MpStyle.DIM))
	var x := MpStyle.button("✕")
	x.custom_minimum_size = Vector2(36, 36)
	x.pressed.connect(close)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(x)

## A skill's icon in a square socket.
func _icon(id: String, px: float, tex_path := "") -> Control:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", MpStyle.box(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.08), 6, 4))
	holder.custom_minimum_size = Vector2(px, px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var t := TextureRect.new()
		t.texture = load(tex_path)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(t)
	elif id != "":
		var g := UI.SkillGlyph.new()
		g.id = id
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(g)
	return holder

# ---------------------------------------------------------------- the build window

func open_build(slot := "") -> void:
	if hero == null or hero.run == null:
		return
	pick_slot = slot if slot in RunBuild.SLOTS else ""
	pick_skill = ""
	_build_window()

func _build_window() -> void:
	var h := hero
	var r: RunBuild = h.run
	var vb := _open("build", 1080)
	var need := h.xp_to_next()
	_header(vb, "Run character", "%s  ·  Level %d" % [Data.CLASSES[h.cls]["name"], h.level],
		"%d / %d experience to the next level  ·  %d camps cleared" % [h.xp, need, r.camps])
	vb.add_child(MpStyle.rule())
	# the attack and the five slots
	vb.add_child(MpStyle.eyebrow("Active skills  ·  %d of %d slots" % [RunBuild.SLOTS.filter(func(s): return h.bound(s) != "").size(), RunBuild.SLOTS.size()]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	row.add_child(_slot_card("lmb", "attack", true))
	var gap := Control.new()
	gap.custom_minimum_size.x = 10
	row.add_child(gap)
	for slot in RunBuild.SLOTS:
		row.add_child(_slot_card(slot, h.bound(slot), false))
	var hint := "Choose a skill below for slot %s." % _slot_name(pick_slot) if pick_slot != "" else (
		"Choose a slot for %s." % Data.skill_def(pick_skill)["name"] if pick_skill != "" else
		"Click a slot, then a skill, to assign it. Right-click a slot to empty it. Skills change between fights.")
	vb.add_child(MpStyle.para(hint, 13, MpStyle.ARCANE if (pick_slot != "" or pick_skill != "") else MpStyle.FAINT))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	vb.add_child(cols)
	# the spellbook
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	left.add_child(MpStyle.eyebrow("Spellbook  ·  %d learned" % r.skills.size()))
	if r.skills.is_empty():
		left.add_child(MpStyle.para("No skills yet. Clear a camp and open its chest: early offers always include a skill.", 14, MpStyle.DIM, 420))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	for id in r.skills:
		grid.add_child(_book_card(id))
	# passives, gear, consumables
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	right.add_child(MpStyle.eyebrow("Passives"))
	if r.passives.is_empty():
		right.add_child(MpStyle.para("None yet: camp chests offer them too.", 14, MpStyle.DIM))
	for id in r.passives:
		var p := RunBuild.passive_def(h.cls, id)
		if p.is_empty():
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		right.add_child(line)
		line.add_child(MpStyle.label("%s  ×%d" % [p["name"], int(r.passives[id])], 14, RunBuild.RARITY_COLORS[int(p["rarity"])], 600))
		var t := MpStyle.para(RunBuild.passive_text(p, int(r.passives[id])), 13, MpStyle.DIM)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(t)
	right.add_child(MpStyle.rule())
	right.add_child(MpStyle.eyebrow("Gear"))
	for s in RunBuild.GEAR:
		if s == "shield" and h.cls != "knight":
			continue
		var it = h.equipment.get(s)
		var line := HBoxContainer.new()
		right.add_child(line)
		var k := MpStyle.label(s.capitalize(), 13, MpStyle.FAINT, 600)
		k.custom_minimum_size.x = 70
		line.add_child(k)
		if it == null:
			line.add_child(MpStyle.label("—", 14, MpStyle.FAINT))
		else:
			var n := MpStyle.label(str(it["name"]), 14, Data.RARITY_COLOR[int(it.get("rarity", 0))], 600)
			n.mouse_filter = Control.MOUSE_FILTER_STOP
			n.mouse_entered.connect(func(): ui.show_tooltip(Items.tooltip(it, 99, "run")))
			n.mouse_exited.connect(func(): ui.tooltip.visible = false)
			line.add_child(n)
	right.add_child(MpStyle.rule())
	right.add_child(MpStyle.eyebrow("Consumables  ·  %d slots" % RunBuild.BELT))
	var belt := HBoxContainer.new()
	belt.add_theme_constant_override("separation", 8)
	right.add_child(belt)
	for i in RunBuild.BELT:
		belt.add_child(_belt_card(i))

func _slot_name(slot: String) -> String:
	return {"lmb": "Left mouse", "rmb": "Right mouse"}.get(slot, slot)

func _slot_card(slot: String, id: String, fixed: bool) -> Control:
	var sel := slot == pick_slot
	var card := PanelContainer.new()
	var border := MpStyle.ARCANE if sel else (MpStyle.GOLD if fixed else Color(1, 1, 1, 0.12))
	card.add_theme_stylebox_override("panel", MpStyle.box(MpStyle.FOREST if fixed else MpStyle.PANEL, border, 6, 10, 2 if sel else 1))
	card.custom_minimum_size = Vector2(150, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	top.add_child(MpStyle.label(("PRIMARY  ·  L" if fixed else _slot_name(slot).to_upper()), 11, MpStyle.GOLD if fixed else MpStyle.FAINT, 700))
	var icon := _icon(id, 52)
	vb.add_child(icon)
	var sk := Data.skill_def(id)
	vb.add_child(MpStyle.label(sk.get("name", "Empty") if id != "" else "Empty", 14, MpStyle.IVORY if id != "" else MpStyle.FAINT, 600))
	var cd := float(hero.cds.get(id, 0.0)) if id != "" else 0.0
	if cd > 0.0:
		vb.add_child(MpStyle.label("%.1fs" % cd, 12, MpStyle.ARCANE))
	if not fixed:
		card.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed:
				card.accept_event()
				if ev.button_index == MOUSE_BUTTON_RIGHT:
					_assign(slot, "")
				elif ev.button_index == MOUSE_BUTTON_LEFT:
					_slot_clicked(slot))
	if id != "":
		card.mouse_entered.connect(func(): ui.show_tooltip(_skill_lines(id)))
		card.mouse_exited.connect(func(): ui.tooltip.visible = false)
	return card

func _book_card(id: String) -> Control:
	var sk := Data.skill_def(id)
	var on := ""
	for s in RunBuild.SLOTS:
		if hero.bound(s) == id:
			on = s
	var sel := id == pick_skill
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MpStyle.box(MpStyle.RAISED if on != "" else MpStyle.PANEL, MpStyle.ARCANE if sel else Color(1, 1, 1, 0.08), 6, 10, 2 if sel else 1))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)
	hb.add_child(_icon(id, 44))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(col)
	col.add_child(MpStyle.label(sk.get("name", id), 15, MpStyle.IVORY, 600))
	var r := RunBuild.skill_rarity(sk)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 6)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(meta)
	meta.add_child(MpStyle.tag(("Slot " + _slot_name(on)) if on != "" else "Reserve", MpStyle.ARCANE if on != "" else MpStyle.DIM))
	meta.add_child(MpStyle.tag(RunBuild.RARITY[r], RunBuild.RARITY_COLORS[r]))
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			card.accept_event()
			_skill_clicked(id))
	card.mouse_entered.connect(func(): ui.show_tooltip(_skill_lines(id)))
	card.mouse_exited.connect(func(): ui.tooltip.visible = false)
	return card

func _belt_card(i: int) -> Control:
	var it = hero.belt[i] if i < hero.belt.size() else null
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MpStyle.box(MpStyle.PANEL, Color(1, 1, 1, 0.08), 6, 8))
	card.custom_minimum_size = Vector2(96, 64)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)
	vb.add_child(MpStyle.label("%d" % (i + 1), 11, MpStyle.FAINT, 700))
	if it == null:
		vb.add_child(MpStyle.label("Empty", 13, MpStyle.FAINT))
		return card
	vb.add_child(MpStyle.label("%s ×%d" % [str(it["name"]), int(it.get("count", 1))], 13, MpStyle.IVORY, 600))
	card.mouse_entered.connect(func(): ui.show_tooltip(Items.tooltip(it, 99, "run") + [["Right-click to drop one", MpStyle.FAINT]]))
	card.mouse_exited.connect(func(): ui.tooltip.visible = false)
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			card.accept_event()
			if ev.button_index == MOUSE_BUTTON_RIGHT:
				game.run_drop_belt(i)
				_build_window()
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				hero.drink(i)
				_build_window())
	return card

func _skill_lines(id: String) -> Array:
	var sk := Data.skill_def(id)
	var lines := [[sk.get("name", id), MpStyle.GOLD], [str(sk.get("desc", "")), Color(0.85, 0.83, 0.77)]]
	if int(sk.get("mana", 0)) > 0 or float(sk.get("cd", 0.0)) > 0.0:
		lines.append(["Mana %d   ·   Cooldown %ss" % [int(round(hero.skill_cost(id))), str(snappedf(hero.skill_cd(id), 0.1))], MpStyle.ARCANE])
	return lines

func _slot_clicked(slot: String) -> void:
	if pick_skill != "":
		_assign(slot, pick_skill)
		return
	pick_slot = "" if pick_slot == slot else slot
	_build_window()

func _skill_clicked(id: String) -> void:
	if pick_slot != "":
		_assign(pick_slot, id)
		return
	# a reserve skill goes straight into an empty slot when there is one; otherwise pick where
	var empty := RunBuild.SLOTS.filter(func(s): return hero.bound(s) == "")
	var on := RunBuild.SLOTS.filter(func(s): return hero.bound(s) == id)
	if on.is_empty() and not empty.is_empty():
		_assign(empty[0], id)
		return
	pick_skill = "" if pick_skill == id else id
	_build_window()

## Assign a skill to a slot (or empty it): between fights only (Hero.combat_t), so a build isn't re-slotted mid-fight.
func _assign(slot: String, id: String) -> void:
	pick_slot = ""
	pick_skill = ""
	if hero.combat_t < Hero.COMBAT_SECS:
		ui.message("Skills change between fights", MpStyle.DANGER)
		Sfx.play("deny")
		_build_window()
		return
	hero.bind(slot, id)
	Sfx.play("click")
	_build_window()

# ---------------------------------------------------------------- the swap window

## A piece of gear found on the ground (`node`, a GroundItem): it against what is worn, Equip or Leave.
func open_swap(it: Dictionary, node: Node) -> void:
	swap_item = it
	swap_node = node
	var slot := RunBuild.gear_slot(it)
	var old = hero.equipment.get(slot)
	var vb := _open("swap", 760)
	_header(vb, "Found gear  ·  " + slot.capitalize(), str(it["name"]),
		"Equip it and the piece you wear is left on the ground. There is no backpack in a run.")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	vb.add_child(cols)
	cols.add_child(_item_col("Worn now", old))
	cols.add_child(_item_col("Found", it, old))
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	vb.add_child(bar)
	var leave := MpStyle.button("Leave it")
	leave.pressed.connect(close)
	bar.add_child(leave)
	var eq := MpStyle.button("Equip", true)
	eq.custom_minimum_size.x = 160
	eq.pressed.connect(func():
		var n := swap_node
		var item := swap_item
		close()
		game.run_swap(item, n))
	bar.add_child(eq)
	eq.grab_focus()

## One item's column; with `against`, each number it shares with that item shows the difference.
func _item_col(title: String, it, against = null) -> Control:
	var p := MpStyle.panel(MpStyle.PANEL, Color(1, 1, 1, 0.08), 8, 16)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	vb.add_child(MpStyle.eyebrow(title, MpStyle.FAINT))
	if it == null:
		vb.add_child(MpStyle.label("Nothing", 16, MpStyle.FAINT, 600))
		return p
	for i in Items.tooltip(it, 99, "run").size():
		var line: Array = Items.tooltip(it, 99, "run")[i]
		vb.add_child(MpStyle.label(str(line[0]), 17 if i == 0 else 14, line[1] if line.size() > 1 else MpStyle.IVORY, 700 if i == 0 else 400))
	if against != null:
		var diffs := _diffs(against, it)
		if not diffs.is_empty():
			vb.add_child(MpStyle.rule())
			for d in diffs:
				vb.add_child(MpStyle.label(d[0], 14, MpStyle.OK if d[1] else MpStyle.DANGER, 600))
	return p

## What changes going from `a` to `b`: damage, defence and each affix ([text, better]).
func _diffs(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	var da := Items.damage_of(a) if a.has("dmg") else []
	var db := Items.damage_of(b) if b.has("dmg") else []
	if not da.is_empty() and not db.is_empty():
		var avg := (float(db[0] + db[1]) - float(da[0] + da[1])) / 2.0
		if absf(avg) >= 0.5:
			out.append(["%+d average damage" % int(round(avg)), avg > 0.0])
	var dfa := Items.defense_of(a)
	var dfb := Items.defense_of(b)
	if dfa != dfb:
		out.append(["%+d defense" % (dfb - dfa), dfb > dfa])
	var sa := Items.stat_sum(a)
	var sb := Items.stat_sum(b)
	var keys := {}
	for k in sa:
		keys[k] = true
	for k in sb:
		keys[k] = true
	for k in keys:
		var dv := int(sb.get(k, 0)) - int(sa.get(k, 0))
		if dv != 0:
			var text: String = str(Data.STAT_LABEL.get(k, str(k) + " +%d")) % absi(dv)
			if dv < 0:
				text = "−" + text.trim_prefix("+")
			out.append([text, dv > 0])
	return out

# ---------------------------------------------------------------- the upgrade window

## A camp chest's upgrade (RunBuild.offer_for: rolled once, the same three every time it opens).
func open_offer(key: String, tier: int, camp_name := "") -> void:
	if hero == null or hero.run == null:
		return
	var o := hero.run.offer_for(hero.cls, key, tier, hero.binds)
	offer_key = key
	var vb := _open("offer", 1020)
	var tiername := "Boss" if tier >= 4 else "Tier %d" % tier
	_header(vb, "Camp reward  ·  " + tiername, "Choose an upgrade", ((camp_name + "  ·  ") if camp_name != "" else "") + "One of three. Skills fill an empty slot; passives never take one.")
	if str(o["claimed"]) != "":
		vb.add_child(MpStyle.para("You already took this camp's upgrade.", 15, MpStyle.DIM))
		return
	if o["choices"].is_empty():
		vb.add_child(MpStyle.para("Nothing left to offer: every skill and passive is already yours.", 15, MpStyle.DIM))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	for i in o["choices"].size():
		row.add_child(_offer_card(o["choices"][i], i))
	vb.add_child(MpStyle.para("Closing this keeps the offer: open the chest again to choose.", 12, MpStyle.FAINT))

func _offer_card(c: Dictionary, i: int) -> Control:
	var r := int(c["rarity"])
	var col: Color = RunBuild.RARITY_COLORS[r]
	var card := PanelContainer.new()
	var sb := MpStyle.box(MpStyle.PANEL, Color(col.r, col.g, col.b, 0.55), 8, 18)
	sb.border_width_top = 3
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(280, 300)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)
	top.add_child(MpStyle.tag(RunBuild.RARITY[r], col))
	top.add_child(MpStyle.tag("Active skill" if c["kind"] == "skill" else "Passive", MpStyle.ARCANE if c["kind"] == "skill" else MpStyle.GOLD))
	var title := ""
	var text := ""
	var extra := ""
	if c["kind"] == "skill":
		var sk := Data.skill_def(c["id"])
		title = sk.get("name", c["id"])
		text = str(sk.get("desc", ""))
		var empty := RunBuild.SLOTS.filter(func(s): return hero.bound(s) == "")
		extra = ("Goes on slot %s" % _slot_name(empty[0])) if not empty.is_empty() else "Slots full: goes to the spellbook"
		if int(sk.get("mana", 0)) > 0:
			extra += "   ·   Mana %d" % int(sk.get("mana", 0))
		if float(sk.get("cd", 0.0)) > 0.0:
			extra += "   ·   %ss cooldown" % str(snappedf(float(sk.get("cd", 0.0)), 0.1))
		vb.add_child(_icon(c["id"], 64))
	else:
		var p := RunBuild.passive_def(hero.cls, c["id"])
		var have := int(hero.run.passives.get(c["id"], 0))
		title = p["name"] + (("  ·  %d → %d" % [have, have + 1]) if have > 0 else "")
		text = RunBuild.passive_text(p, have + 1, have)
		extra = "Stacks up to %d" % int(p["max"]) if int(p["max"]) > 1 else "Once only"
		if p.has("tree"):
			extra += "   ·   " + str(p["tree"])
		vb.add_child(_icon(str(p.get("icon", "")), 64, UI.TALENT_ICON % c["id"]))
	vb.add_child(MpStyle.label(title, 20, MpStyle.IVORY, 700))
	vb.add_child(MpStyle.para(text, 14, Color(0.84, 0.83, 0.78)))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(fill)
	vb.add_child(MpStyle.para(extra, 12, MpStyle.FAINT))
	var take := MpStyle.button("Choose", true)
	take.pressed.connect(func(): _take(i))
	vb.add_child(take)
	return card

func _take(i: int) -> void:
	var c: Dictionary = game.run_claim(offer_key, i)
	close()
	if c.is_empty():
		return
	Sfx.play("levelup")
	var nm: String = Data.skill_def(c["id"]).get("name", c["id"]) if c["kind"] == "skill" else RunBuild.passive_def(hero.cls, c["id"]).get("name", c["id"])
	ui.big_message("✦ " + nm + " ✦")

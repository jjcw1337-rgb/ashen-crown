class_name CodexBook
extends RefCounted
## The players' Codex (Blaine, 2026-11-06): every hero's three directions with their skills and rites, the shared
## ones, the gems and the consumables, read from the same Hero Codex data the game plays (data/codex/, live entries
## only; text and numbers from the game's own data). What a player hasn't come across in a run shows locked, like a
## card compendium: an entry is discovered when a camp chest offers it, a gem when it is found, a consumable when a
## chest gives it (RunUI.open_offer calls `see`). Discoveries are this PC's (user://codex_seen.json).
## The window is a RunUI mode ("codex"): opened from the multiplayer screen's Codex button and the run's build window.

const PATH := "user://codex_seen.json"
static var path := PATH            # (tools point it at a test file)
static var _seen := {}
static var _loaded := false
static var reveal := false         # dev tools: show everything

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_seen = {}
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and d.get("seen") is Dictionary:
			_seen = d["seen"]

## For tests: forget what was loaded (and use another file).
static func use_file(p := PATH) -> void:
	path = p
	_loaded = false
	_load()

static func seen(kind: String, id: String) -> bool:
	_load()
	return reveal or _seen.has(kind + ":" + id)

## Mark entries as discovered (kind: skill, rite, gem, item); saved at once when anything is new.
static func see(kind: String, ids: Array) -> void:
	_load()
	var fresh := false
	for i in ids:
		var key := kind + ":" + str(i)
		if str(i) != "" and not _seen.has(key):
			_seen[key] = true
			fresh = true
	if fresh:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"seen": _seen}))
			f.close()

## A camp chest's offer as it is shown: its choices, its gem and its consumables become known.
static func see_offer(o: Dictionary) -> void:
	for c in o.get("choices", []):
		see("skill" if str(c.get("kind", "")) == "skill" else "rite", [c["id"]])
	if str(o.get("gem", "")) != "":
		see("gem", [o["gem"]])
	see("item", o.get("loot", []))

# ---------------------------------------------------------------- what the book lists

## The heroes with a codex file, by name.
static func heroes() -> Array:
	var out := []
	for cls in Data.CLASSES:
		if not Codex.hero(cls).is_empty():
			out.append(cls)
	out.sort_custom(func(a, b): return str(Data.CLASSES[a]["name"]) < str(Data.CLASSES[b]["name"]))
	return out

## A hero's pages: [{name, desc, entries: [{kind, id, name, rarity, text, icon}]}], one per direction, then "Core"
## (entries filed under no direction). Only live entries the game knows.
static func hero_sections(cls: String) -> Array:
	var h := Codex.hero(cls)
	var order := []
	var by := {}
	for d in h.get("directions", []):
		var did := str(d.get("id", ""))
		order.append(did)
		by[did] = {"name": str(d.get("name", did)), "desc": str(d.get("desc", "")), "entries": []}
	by[""] = {"name": "Core", "desc": "For any build.", "entries": []}
	order.append("")
	for e in h.get("skills", []):
		var x := _skill(e)
		if not x.is_empty():
			by.get(str(e.get("direction", "")), by[""])["entries"].append(x)
	for e in h.get("rites", []):
		var x := _rite(cls, e)
		if not x.is_empty():
			by.get(str(e.get("direction", "")), by[""])["entries"].append(x)
	var out := []
	for did in order:
		if not by[did]["entries"].is_empty():
			by[did]["entries"].sort_custom(_by_rarity)
			out.append(by[did])
	return out

## The pages every hero shares: the shared skills and the generic rites.
static func shared_sections(cls := "knight") -> Array:
	var sk := []
	var ri := []
	for e in Codex.shared().get("skills", []):
		var x := _skill(e)
		if not x.is_empty():
			sk.append(x)
	for e in Codex.shared().get("rites", []):
		var x := _rite(cls, e)
		if not x.is_empty():
			ri.append(x)
	sk.sort_custom(_by_rarity)
	ri.sort_custom(_by_rarity)
	return [{"name": "Shared skills", "desc": "Any hero can be offered these.", "entries": sk},
		{"name": "Rites for everyone", "desc": "In every hero's camp chests.", "entries": ri}]

static func gem_sections() -> Array:
	var out := []
	for e in Codex.file("gems.json").get("entries", []):
		if not Codex.live(e):
			continue
		var g := RunTalents.gem_def(str(e["id"]))
		if g.is_empty():
			continue
		out.append({"kind": "gem", "id": str(e["id"]), "name": str(g["name"]), "rarity": int(g.get("rarity", 0)),
			"text": RunTalents.text_of(g, 1), "color": g.get("color", Color.WHITE)})
	out.sort_custom(_by_rarity)
	return [{"name": "Gems", "desc": "Relics found in camp chests. They stay with the run, and with a survivor.", "entries": out}]

static func item_sections() -> Array:
	var out := []
	for e in Codex.file("consumables.json").get("entries", []):
		var id := str(e.get("id", ""))
		if not Codex.live(e) or not Data.BASES.has(id):
			continue
		var b: Dictionary = Data.BASES[id]
		out.append({"kind": "item", "id": id, "name": str(b.get("name", id)), "rarity": int(e.get("rarity", 0)),
			"text": str(e.get("text", b.get("desc", ""))), "icon": str(b.get("icon", ""))})
	return [{"name": "Consumables", "desc": "Belt items from camp chests: drunk or thrown, they stack.", "entries": out}]

static func _skill(e: Dictionary) -> Dictionary:
	if not Codex.live(e):
		return {}
	var s := Data.skill_def(str(e["id"]))
	if s.is_empty():
		return {}
	return {"kind": "skill", "id": str(e["id"]), "name": str(s.get("name", e["id"])), "rarity": RunBuild.skill_rarity(s),
		"text": str(s.get("desc", "")), "icon": "res://assets/textures/skills/%s.png" % e["id"]}

static func _rite(cls: String, e: Dictionary) -> Dictionary:
	if not Codex.live(e):
		return {}
	var p := RunBuild.passive_def(cls, str(e["id"]))
	if p.is_empty():
		return {}
	var top := int(p.get("max", 1))
	return {"kind": "rite", "id": str(e["id"]), "name": str(p.get("name", e["id"])), "rarity": int(p.get("rarity", 0)),
		"text": RunBuild.passive_text(p, 1) + (("  (up to %d stacks)" % top) if top > 1 else ""),
		"icon": UI.TALENT_ICON % e["id"], "glyph": str(p.get("icon", ""))}

static func _by_rarity(a: Dictionary, b: Dictionary) -> bool:
	if int(a["rarity"]) != int(b["rarity"]):
		return int(a["rarity"]) < int(b["rarity"])
	if a["kind"] != b["kind"]:
		return a["kind"] == "skill"
	return str(a["name"]) < str(b["name"])

## Discovered / total over some sections.
static func count(sections: Array) -> Vector2i:
	var n := 0
	var have := 0
	for s in sections:
		for x in s["entries"]:
			n += 1
			if seen(x["kind"], x["id"]):
				have += 1
	return Vector2i(have, n)

# ---------------------------------------------------------------- the window (a RunUI mode)

static var page := ""              # the open tab: a class, "shared", "gems" or "items"

static func open(ru: RunUI, tab := "") -> void:
	if tab != "":
		page = tab
	if page == "":
		page = ru.hero.cls if ru.hero != null and not Codex.hero(ru.hero.cls).is_empty() else "warlock"
	var vb := ru._open("codex", 1180)
	var all := []
	for cls in heroes():
		all.append_array(hero_sections(cls))
	all.append_array(shared_sections())
	all.append_array(gem_sections())
	all.append_array(item_sections())
	var tot := count(all)
	ru._header(vb, "The Codex", "Everything a run can offer", "%d of %d discovered. Camp chests reveal what they offer." % [tot.x, tot.y])
	# the tabs
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	vb.add_child(tabs)
	var pages := heroes().map(func(c): return [c, str(Data.CLASSES[c]["name"])])
	pages.append_array([["shared", "Every hero"], ["gems", "Gems"], ["items", "Consumables"]])
	for pg in pages:
		var b := MpStyle.button(pg[1], pg[0] == page, 14)
		b.name = "tab_" + str(pg[0])
		b.pressed.connect(func():
			Sfx.play("click")
			open(ru, pg[0]))
		tabs.add_child(b)
	if ru.game != null and ru.game.dev_tools:
		var rv := CheckBox.new()
		rv.text = "Reveal all (dev)"
		rv.button_pressed = reveal
		rv.toggled.connect(func(on):
			reveal = on
			open(ru, page))
		tabs.add_child(rv)
	vb.add_child(MpStyle.rule())
	var secs: Array = shared_sections() if page == "shared" else gem_sections() if page == "gems" else item_sections() if page == "items" else hero_sections(page)
	if Data.CLASSES.has(page):
		var fan := str(Codex.hero(page).get("fantasy", ""))
		if fan != "":
			vb.add_child(MpStyle.para(fan, 14, MpStyle.DIM, 1100))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = minf(560.0, ru.get_viewport_rect().size.y - 300.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	for s in secs:
		var c := count([s])
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		body.add_child(head)
		head.add_child(MpStyle.label(str(s["name"]), 20, MpStyle.GOLD_LIT, 700, true))
		head.add_child(MpStyle.label("%d / %d" % [c.x, c.y], 13, MpStyle.FAINT))
		if str(s["desc"]) != "":
			body.add_child(MpStyle.para(str(s["desc"]), 13, MpStyle.DIM, 1100))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		body.add_child(grid)
		for x in s["entries"]:
			grid.add_child(_card(ru, x))

static func _card(ru: RunUI, x: Dictionary) -> Control:
	var known := seen(x["kind"], x["id"])
	var r := clampi(int(x["rarity"]), 0, RunBuild.RARITY_COLORS.size() - 1)
	var col: Color = RunBuild.RARITY_COLORS[r]
	var card := PanelContainer.new()
	card.name = "card_%s_%s" % [x["kind"], x["id"]]
	card.set_meta("known", known)
	var sb := MpStyle.box(MpStyle.PANEL if known else Color(0.07, 0.075, 0.08, 0.95), Color(col.r, col.g, col.b, 0.5 if known else 0.18), 8, 12, 1)
	sb.border_width_top = 3
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(360, 96)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	card.add_child(hb)
	if not known:
		var q := MpStyle.label("?", 30, Color(col.r, col.g, col.b, 0.45), 700, true)
		q.custom_minimum_size = Vector2(56, 56)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(q)
	elif x["kind"] == "gem":
		hb.add_child(ru._gem_swatch(x.get("color", Color.WHITE), 56, x["id"]))
	elif x["kind"] == "rite":
		hb.add_child(ru._icon(str(x.get("glyph", "")), 56, str(x.get("icon", ""))))
	else:
		hb.add_child(ru._icon(x["id"] if x["kind"] == "skill" else "", 56, str(x.get("icon", ""))))
	var col2 := VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col2.add_theme_constant_override("separation", 3)
	hb.add_child(col2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	col2.add_child(top)
	var kind_name: String = {"skill": "Skill", "rite": "Rite", "gem": "Gem", "item": "Consumable"}[x["kind"]]
	top.add_child(MpStyle.label(RunBuild.RARITY[r] + " " + kind_name, 11, Color(col.r, col.g, col.b, 1.0 if known else 0.6), 600))
	col2.add_child(MpStyle.label(str(x["name"]) if known else "Undiscovered", 16, MpStyle.IVORY if known else MpStyle.FAINT, 700))
	var t := MpStyle.para(str(x["text"]) if known else "A camp chest will show it to you.", 12, Color(0.8, 0.79, 0.74) if known else MpStyle.FAINT, 270)
	col2.add_child(t)
	return card

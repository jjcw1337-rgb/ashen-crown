class_name AuctionUI
extends RefCounted
## The Gilded Hall's auction window (jj, 2026-11-04: "an auction house where players can buy and sell elixirs that
## buff you ... hard to achieve"). A first look: the auctioneer's window in the game's own iron and gold frame
## (UI._panel), the hall's listings of elixirs (each a Meshy-painted icon, assets/textures/items/elixir_<id>.png, its
## tier, its buff, the seller, the bid, the buyout, the time left) under Browse / Sell / My Bids. The bidding itself
## (server escrow, listing, expiry) is not built yet: the buttons say so.

const ELIXIRS := {
	"fury": {"name": "Elixir of Fury", "buff": "+25% damage", "col": Color(1.0, 0.42, 0.25)},
	"arcane": {"name": "Elixir of the Arcane", "buff": "+40% mana regeneration, -15% skill costs", "col": Color(0.45, 0.7, 1.0)},
	"fortune": {"name": "Elixir of Fortune", "buff": "+30% gold and magic find", "col": Color(1.0, 0.82, 0.35)},
	"wilds": {"name": "Elixir of the Wilds", "buff": "+20% movement speed, life regeneration", "col": Color(0.45, 0.95, 0.45)},
	"shadow": {"name": "Elixir of Shadow", "buff": "+15% dodge, first hit from stealth crits", "col": Color(0.75, 0.5, 1.0)},
	"colossus": {"name": "Elixir of the Colossus", "buff": "+30% life, +20% armour", "col": Color(0.82, 0.86, 0.92)},
}
## tiers: what each takes to brew (the "hard to achieve" part), how long it lasts
const TIERS := {
	"Lesser": {"col": Color(0.75, 0.72, 0.66), "brew": "rare moor herbs and a Sunstar Bloom", "mins": 20},
	"Greater": {"col": Color(0.4, 0.7, 1.0), "brew": "a Hollow Sloth's material and a champion's trophy", "mins": 30},
	"Ancient": {"col": Color(1.0, 0.62, 0.2), "brew": "a raid boss's heart and a night's brewing", "mins": 45},
}
## sample listings (the look; real ones will come from the server)
const LISTINGS := [
	["fury", "Ancient", "Ironhide", 4200, 6500, "11h"],
	["fortune", "Greater", "Maeve's apprentice", 1350, 2000, "3h"],
	["colossus", "Greater", "Kell of the Watch", 1100, 1800, "22h"],
	["arcane", "Lesser", "Wanderer", 260, 420, "40m"],
	["shadow", "Ancient", "Nightfang", 5100, 8000, "1d"],
	["wilds", "Lesser", "Brannoc", 180, 300, "5h"],
	["fury", "Greater", "Old Tom", 1250, 1900, "8h"],
	["fortune", "Ancient", "Goldtooth", 7300, 11000, "2d"],
]

static func icon(id: String) -> Texture2D:
	var p := "res://assets/textures/items/elixir_%s.png" % id
	return load(p) if ResourceLoader.exists(p) else null

## Builds the window (once, from UI._ready's builders): returns the panel.
static func build(ui) -> PanelContainer:
	var p: PanelContainer = ui._panel("The Gilded Hall", true, 820, 640)
	var vb: VBoxContainer = p.get_node("vb")
	var sub: Label = ui._label("Auctioneer Corvin  ·  elixirs of power, bought and sold", 15, Color(0.86, 0.8, 0.66))
	vb.add_child(sub)
	# the tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	var pages := {}
	for t in ["Browse", "Sell", "My Bids"]:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.button_pressed = t == "Browse"
		b.custom_minimum_size = Vector2(120, 34)
		b.add_theme_font_override("font", ui.font_title)
		b.add_theme_font_size_override("font_size", 16)
		tabs.add_child(b)
		pages[t] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	var gold: Label = ui._label("", 17, Color(1.0, 0.85, 0.4), true)
	gold.name = "gold"
	tabs.add_child(gold)
	# the listings
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 430)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.name = "list"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	var sell: Label = ui._label("You carry no elixirs to sell.\n\nElixirs are brewed by Maeve the alchemist, and they are not easy to come by:\n"
		+ "  Lesser  -  rare moor herbs and a Sunstar Bloom\n  Greater  -  a Hollow Sloth's material and a champion's trophy\n"
		+ "  Ancient  -  a raid boss's heart and a night's brewing\n\nBring one here to list it: the hall holds it until it sells, and takes 5%.", 15, Color(0.82, 0.78, 0.7))
	sell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sell.visible = false
	vb.add_child(sell)
	var bids: Label = ui._label("You have no bids standing.", 15, Color(0.82, 0.78, 0.7))
	bids.visible = false
	vb.add_child(bids)
	for t in pages:
		var b: Button = pages[t]
		b.pressed.connect(func():
			for k in pages:
				(pages[k] as Button).button_pressed = k == t
			sc.visible = t == "Browse"
			sell.visible = t == "Sell"
			bids.visible = t == "My Bids"
			Sfx.play("click"))
	for l in LISTINGS:
		list.add_child(_row(ui, l))
	vb.add_child(ui._divider(16))
	var foot: Label = ui._label("Bids are held by the hall until the hammer falls  ·  5% of each sale goes to the hall", 13, Color(0.6, 0.55, 0.46))
	vb.add_child(foot)
	return p

static func _row(ui, l: Array) -> Control:
	var e: Dictionary = ELIXIRS[l[0]]
	var tier: Dictionary = TIERS[l[1]]
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", ui._box(Color(0.06, 0.045, 0.03, 0.92), Color(0.42, 0.32, 0.18), 1, 4, 6))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)
	var ic := TextureRect.new()
	ic.texture = icon(str(l[0]))
	ic.custom_minimum_size = Vector2(58, 58)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hb.add_child(ic)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	hb.add_child(info)
	var nm: Label = ui._label("%s %s" % [l[1], e["name"]], 17, tier["col"], true)
	info.add_child(nm)
	info.add_child(ui._label("%s for %d minutes" % [e["buff"], int(tier["mins"])], 13, e["col"]))
	info.add_child(ui._label("Sold by %s  ·  %s left" % [l[2], l[5]], 12, Color(0.6, 0.56, 0.5)))
	var price := VBoxContainer.new()
	price.custom_minimum_size = Vector2(150, 0)
	hb.add_child(price)
	price.add_child(ui._label("Bid  %s" % _gold(int(l[3])), 15, Color(1.0, 0.85, 0.4), true))
	price.add_child(ui._label("Buyout  %s" % _gold(int(l[4])), 13, Color(0.85, 0.72, 0.4)))
	for t in ["Bid", "Buy"]:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size = Vector2(64, 40)
		b.add_theme_font_override("font", ui.font_title)
		b.pressed.connect(func():
			Sfx.play("coins")
			ui.message("The Gilded Hall opens its auctions soon", Color(1.0, 0.85, 0.4)))
		hb.add_child(b)
	return row

static func _gold(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out + " g"

## Opens it, the purse brought up to date.
static func open(ui, p: PanelContainer) -> void:
	var g = ui.game
	var gl := p.find_child("gold", true, false) as Label
	if gl != null and g != null and g.hero != null:
		gl.text = "Your purse  " + _gold(int(g.hero.gold))
	p.visible = true

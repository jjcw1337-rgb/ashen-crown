class_name Gems
extends RefCounted
## The gems: a run's relics. Found in camp chests (more often in deeper camps; a boss always gives one, often
## legendary; RunBuild.roll_gem), kept for the run and by its survivor. Common and rare gems are stats; legendary ones
## change the run. A gem is shaped like a rite (Rites): its fx add up in RunBuild.fx, and a proc is a rite's (RiteProcs).

## Laid over by the Hero Codex (data/codex/gems.json) when this script loads.
static func _static_init() -> void:
	Codex.apply_rites(GEMS, Codex.file("gems.json").get("entries", []), "gems")

static var GEMS: Array = [
	{"id": "ruby", "name": "Ember Ruby", "rarity": 0, "color": Color(0.95, 0.22, 0.2), "fx": {"dmg": 6, "burn_pct": 15}, "text": "+{dmg}% damage, burns +{burn_pct}%."},
	{"id": "sapphire", "name": "Frost Sapphire", "rarity": 0, "color": Color(0.25, 0.45, 1.0), "fx": {"cdr": 6, "chill_pct": 15}, "text": "Skills recharge {cdr}% faster, chills +{chill_pct}%."},
	{"id": "emerald", "name": "Venom Emerald", "rarity": 0, "color": Color(0.2, 0.85, 0.35), "fx": {"regen": 1.5, "poison_dmg": 15}, "text": "+{regen} life a second, poison +{poison_dmg}%."},
	{"id": "topaz", "name": "Storm Topaz", "rarity": 0, "color": Color(1.0, 0.8, 0.25), "fx": {"ias": 5, "crit": 3}, "text": "+{ias}% attack speed, +{crit}% critical chance."},
	{"id": "amethyst", "name": "Dusk Amethyst", "rarity": 0, "color": Color(0.7, 0.35, 0.95), "fx": {"mana_pct": 15, "res": 6}, "text": "+{mana_pct}% mana, +{res}% resistances."},
	{"id": "onyx", "name": "Onyx", "rarity": 0, "color": Color(0.25, 0.25, 0.3), "fx": {"crit_dmg": 25}, "text": "Critical hits deal +{crit_dmg}%."},
	{"id": "bloodstone", "name": "Bloodstone", "rarity": 0, "color": Color(0.6, 0.05, 0.1), "fx": {"ls": 2}, "text": "{ls}% life steal."},
	{"id": "jade", "name": "Jade", "rarity": 0, "color": Color(0.35, 0.75, 0.55), "fx": {"life_pct": 10}, "text": "+{life_pct}% life."},
	{"id": "moonstone", "name": "Moonstone", "rarity": 0, "color": Color(0.82, 0.88, 1.0), "fx": {"frw": 6}, "text": "+{frw}% run speed."},
	{"id": "heartstone", "name": "Heartstone", "rarity": 2, "color": Color(1.0, 0.35, 0.45), "fx": {"life_pct": 20, "regen": 2.5}, "text": "+{life_pct}% life, +{regen} life a second."},
	{"id": "prism", "name": "Prism", "rarity": 2, "color": Color(0.9, 0.95, 1.0), "fx": {"dmg": 8, "life_pct": 8, "ias": 6}, "text": "+{dmg}% damage, +{life_pct}% life, +{ias}% attack speed."},
	{"id": "warstone", "name": "Warstone", "rarity": 2, "color": Color(0.95, 0.5, 0.2), "fx": {"dmg": 14}, "text": "+{dmg}% damage."},
	{"id": "phoenix", "name": "Phoenix Ember", "rarity": 3, "color": Color(1.0, 0.55, 0.15), "proc": "undying", "k": {"life": 60, "secs": 99999, "burst": 1},
		"text": "Once this run, a killing blow is refused: you rise at {life}% life in a burst of fire."},
	{"id": "tempest", "name": "Eye of the Tempest", "rarity": 3, "color": Color(0.55, 0.6, 1.0), "proc": "nth_hit_bolt", "k": {"n": 8, "pct": 150, "r": 3.0},
		"text": "Every {n}th hit calls lightning down on its foe ({pct}% weapon damage)."},
	{"id": "hunger", "name": "Hunger Stone", "rarity": 3, "color": Color(0.45, 0.1, 0.2), "proc": "hunger", "k": {"per": 1, "most": 35},
		"text": "Every kill adds +{per}% damage for the rest of the run (up to {most}%)."},
	{"id": "seer", "name": "Seer's Eye", "rarity": 3, "color": Color(0.45, 0.95, 0.95), "fx": {"offer_plus": 1},
		"text": "Camp chests offer one more choice."},
	{"id": "crownshard", "name": "Shard of the Crown", "rarity": 3, "color": Color(1.0, 0.85, 0.35), "fx": {"rarity_up": 1},
		"text": "Camp chests' offers are one step rarer."},
]
## The chance a camp's chest holds a gem for each player, by tier (4 = a boss: always, legendary on LEGEND_ODDS).
const GEM_CHANCE := {1: 0.2, 2: 0.4, 3: 0.65, 4: 1.0}
const RARE_GEM_CHANCE := {1: 0.0, 2: 0.08, 3: 0.25, 4: 0.5}
const LEGEND_ODDS := 0.5

static func gem_def(id: String) -> Dictionary:
	for g in GEMS:
		if g["id"] == id:
			return g
	return {}

## A gem's painted icon (Meshy, tools/skill_icons.py grids "gems", "gems2", "potions"), or null.
static func gem_icon(id: String) -> Texture2D:
	var p := "res://assets/textures/gems/%s.png" % id
	return ResCache.get_res(p) as Texture2D if ResourceLoader.exists(p) else null

class_name RunTalents
extends RefCounted
## The run's roguelike layer (Blaine, 2026-11-06: "like Slay the Spire, themes of card types for their decks, then
## relics and consumables"): three build directions per class (THEMES: the archer Flame, Frost or Storm and Hunt; the
## plague doctor Toxin, Vermin and Rot or Alchemy), rites that change how a run plays (common to rare: a burning foe
## that dies sets the others alight, poison passes to a new host when its carrier dies, plain arrows ricochet), gems
## (the run's relics: found in camp chests, kept for the run, the survivor keeps them) and consumables.
##
## This is the one entry point the rest of the game calls. It holds what they all share (the rarities and the build
## directions) and hands everything else to its kind:
##   rites/        Rites (the table), RiteProcs (when a proc fires: the hooks below, timed buffs), ProcHits (what a
##                 proc does to foes) and RiteFx (how it looks)
##   gems/         Gems (the table and the chest's odds); a gem's proc is a rite's
##   consumables/  Consumables (what a chest holds, the thrown flask) and FlaskFx (its look)
##
## Hooks: Hero._hit_enemy (hit_mult before the roll, on_hit after), Enemy.die_visual (on_death, for the hero who
## struck it last), Enemy.ignite / chill (the striker's burn_pct, burn_dur, chill_pct), PlagueAffliction
## (poison_mult, on_dot) and PlagueSkill.damage (mark), Hero.take_hit (struck, save_from_death), Hero.use_skill (echo),
## Hero._process (tick), ArcherShot.impact (on_shot). Procs fire only where the hero's hits are decided (Hero.decides).

## Skills and rites come Common, Uncommon or Rare (Blaine's character structure, 2026-11-06: the rares are the
## run-changers). A fourth colour is the gems' legendary tier (Gems rarity 3), never a rite's.
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Legendary"]
const RARITY_COLORS := [Color(0.86, 0.84, 0.78), Color(0.42, 0.86, 0.52), Color(0.48, 0.68, 1.0), Color(1.0, 0.62, 0.18)]

## Each class's build themes, in the order shown. A theme is what a skill or talent is "for": the offers lean toward
## the themes a build already has (roll weight), like a Spire deck growing into its archetype.
const THEMES := {
	"archer": [
		{"id": "flame", "name": "Flame", "color": Color(1.0, 0.5, 0.18), "desc": "Fire Arrow and burning wounds that spread."},
		{"id": "frost", "name": "Frost", "color": Color(0.55, 0.82, 1.0), "desc": "Chill, freeze and shatter."},
		{"id": "storm", "name": "Storm and Hunt", "color": Color(0.7, 0.72, 1.0), "desc": "Thunderstep, lightning that leaps, and the wolf on the quarry."},
	],
	"plague": [
		{"id": "toxin", "name": "Toxin", "color": Color(0.45, 0.95, 0.3), "desc": "Poison that grows crueller and leaps from the dying to the living."},
		{"id": "vermin", "name": "Vermin and Rot", "color": Color(0.55, 0.62, 0.3), "desc": "The swarm and the bloom."},
		{"id": "alchemy", "name": "Alchemy", "color": Color(0.7, 0.45, 0.95), "desc": "Vials, fog and the apparatus."},
	],
	# the warlock (the jungle void spirit, WarlockHex; her skills' and rites' directions come from the Hero Codex)
	"warlock": [
		{"id": "corruption", "name": "Corruption", "color": Color(0.45, 1.0, 0.3), "desc": "Curses that stack, grow and multiply."},
		{"id": "fear", "name": "Fear", "color": Color(0.72, 0.45, 1.0), "desc": "Terrify, bind and scatter; the frightened take more."},
		{"id": "drain", "name": "Drain", "color": Color(0.75, 1.0, 0.6), "desc": "Life drained, healing past full hardening into a shield."},
	],
	"knight": [
		{"id": "crusader", "name": "Crusader", "color": Color(1.0, 0.9, 0.55), "desc": "Holy fire and the sword."},
		{"id": "bulwark", "name": "Bulwark", "color": Color(0.7, 0.78, 0.9), "desc": "Plate and shield: hard to kill."},
		{"id": "vanguard", "name": "Vanguard", "color": Color(0.95, 0.5, 0.35), "desc": "Charge, cry and the combo."},
	],
	"wraith": [
		{"id": "render", "name": "Render", "color": Color(0.6, 0.9, 1.0), "desc": "Claws, quick strikes and cruel crits."},
		{"id": "shadow", "name": "Shadow", "color": Color(0.5, 0.45, 0.9), "desc": "The tether and the mist."},
		{"id": "night", "name": "Night", "color": Color(0.35, 0.4, 0.75), "desc": "What comes out of the dark."},
	],
	"demon": [
		{"id": "magma", "name": "Magma", "color": Color(1.0, 0.45, 0.1), "desc": "Fists, charge and fury."},
		{"id": "cataclysm", "name": "Cataclysm", "color": Color(0.9, 0.3, 0.15), "desc": "The ground torn open."},
		{"id": "pit", "name": "The Pit", "color": Color(0.75, 0.2, 0.2), "desc": "What the pit gives."},
	],
	"doug": [
		{"id": "slapstick", "name": "Slapstick", "color": Color(1.0, 0.92, 0.5), "desc": "Pies and the drumstick."},
		{"id": "showman", "name": "Showmanship", "color": Color(0.95, 0.5, 0.75), "desc": "Misdirection and juggling."},
		{"id": "bigtop", "name": "Big Top", "color": Color(1.0, 0.35, 0.3), "desc": "The bounce and the clown car."},
	],
	"serpent": [
		{"id": "frost", "name": "Frost", "color": Color(0.55, 0.82, 1.0), "desc": "Breath, chill and shatter."},
		{"id": "beast", "name": "Beast", "color": Color(0.7, 0.8, 0.85), "desc": "Claws, coils and the tail."},
		{"id": "glacier", "name": "Glacier", "color": Color(0.75, 0.92, 1.0), "desc": "Tombs of ice and a hide of it: lock them down, then break them."},
	],
	"wyvern": [
		{"id": "storm", "name": "Storm", "color": Color(0.7, 0.72, 1.0), "desc": "Lightning from its jaws."},
		{"id": "beast", "name": "Beast", "color": Color(0.7, 0.8, 0.85), "desc": "Claws, wings and the tail."},
		{"id": "sky", "name": "Sky", "color": Color(0.6, 0.85, 1.0), "desc": "Dives, gales and the storm overhead: never where they strike."},
	],
}
## Each class's three talent trees -> the theme their talents (now passives) belong to.
const TREE_THEME := {
	"archer": ["flame", "frost", "storm"], "plague": ["toxin", "vermin", "alchemy"],
"knight": ["crusader", "bulwark", "vanguard"],
	"wraith": ["render", "shadow", "night"], "demon": ["magma", "cataclysm", "pit"],
	"doug": ["slapstick", "showman", "bigtop"],
	"warlock": ["drain", "corruption", "fear"],      # (her talent trees Affliction, Plague, Binding)
}
## Which theme each skill is for (the shared skills by element, so they join a build that fits).
const SKILL_THEMES := {
	"pierce": "flame", "volley": "frost", "snare": "storm", "beast": "storm", "a_multishot": "",
	"a_explosive": "flame", "a_glacial": "frost", "a_stormshot": "storm", "a_mark": "storm", "a_barrage": "",
	"toxic": "toxin", "swarm": "vermin", "bloom": "vermin", "fog": "alchemy", "transfusion": "alchemy", "experiment": "alchemy",
	"p_miasma": "toxin", "p_spread": "toxin", "p_leech": "alchemy", "p_rats": "vermin",
	"cleave": "crusader", "nova": "crusader", "charge": "vanguard", "cry": "vanguard",
	"k_judgment": "crusader", "k_aegis": "bulwark", "k_whirl": "crusader", "k_rites": "vanguard",
	"r_deathmark": "render", "r_wail": "shadow", "r_reap": "night",
	"rend": "render", "siphon": "shadow", "step": "shadow", "grasp": "night", "phantom": "render", "night": "night",
	"d_volcano": "cataclysm", "d_detonate": "magma", "d_pact": "pit",
	"fists": "magma", "icharge": "magma", "cslam": "cataclysm", "hurl": "cataclysm", "grip": "pit", "wrath": "pit",
	"u_barrage": "slapstick", "u_bonanza": "showman", "u_cannon": "bigtop",
	"pie": "slapstick", "peels": "slapstick", "slide": "showman", "doppel": "showman", "juggle": "showman", "bounce": "bigtop", "car": "bigtop",
	"frost_breath": "frost", "storm_arc": "storm",
	"s_tomb": "glacier", "s_coil": "beast", "s_lance": "frost", "v_dive": "sky", "v_cloud": "storm", "v_gale": "sky",
	"frost_nova": "frost", "arc": "storm", "earthshatter": "", "war_cry": "",
}

## The tables, kept by their own kinds (the same arrays and values: the Hero Codex lays over them where they live).
static var TALENTS: Array:
	get: return Rites.TALENTS
static var GEMS: Array:
	get: return Gems.GEMS
const GEM_CHANCE := Gems.GEM_CHANCE
const RARE_GEM_CHANCE := Gems.RARE_GEM_CHANCE
const LEGEND_ODDS := Gems.LEGEND_ODDS
const CONSUMABLES := Consumables.CONSUMABLES
const CONSUMABLE_COUNT := Consumables.CONSUMABLE_COUNT

# ---------------------------------------------------------------- data

static func theme_def(cls: String, id: String) -> Dictionary:
	for t in THEMES.get(cls, []):
		if t["id"] == id:
			return t
	return {}

static func talents_for(cls: String) -> Array:
	return Rites.talents_for(cls)

static func gem_def(id: String) -> Dictionary:
	return Gems.gem_def(id)

static func gem_icon(id: String) -> Texture2D:
	return Gems.gem_icon(id)

static func k_at(t: Dictionary, stacks: int) -> Dictionary:
	return Rites.k_at(t, stacks)

static func text_of(t: Dictionary, stacks: int, from := 0) -> String:
	return Rites.text_of(t, stacks, from)

static func roll_consumables(tier: int, rng: RandomNumberGenerator) -> Array:
	return Consumables.roll(tier, rng)

# ---------------------------------------------------------------- the hooks (RiteProcs)

static func procs(h: Hero) -> Array:
	return RiteProcs.procs(h)

static func mark(h: Hero, e) -> void:
	RiteProcs.mark(h, e)

static func hit_mult(h: Hero, e, src: String) -> float:
	return RiteProcs.hit_mult(h, e, src)

static func on_hit(h: Hero, e, dealt: float, crit: bool, src: String) -> void:
	RiteProcs.on_hit(h, e, dealt, crit, src)

static func on_death(e) -> void:
	RiteProcs.on_death(e)

static func poison_mult(h: Hero, age: float) -> float:
	return RiteProcs.poison_mult(h, age)

static func on_dot(h: Hero, e, amount: float) -> void:
	RiteProcs.on_dot(h, e, amount)

static func struck(h: Hero, dmg: float, from: Vector3) -> void:
	RiteProcs.struck(h, dmg, from)

static func save_from_death(h: Hero) -> bool:
	return RiteProcs.save_from_death(h)

static func on_cooldown(h: Hero, id: String) -> void:
	RiteProcs.on_cooldown(h, id)

static func on_shot(h: Hero) -> void:
	RiteProcs.on_shot(h)

static func tick(h: Hero, delta: float) -> void:
	RiteProcs.tick(h, delta)

## A timed buff of stats (a proc's, a consumable's, a skill's: Aegis, Blood Pact, No Quarter).
static func buff(h: Hero, key: String, fx: Dictionary, secs: float, kind := "") -> void:
	RiteProcs.buff(h, key, fx, secs, kind)

static func poisoned(h: Hero, e) -> bool:
	return ProcHits.poisoned(h, e)

static func burning(e) -> bool:
	return ProcHits.burning(e)

static func chilled(e) -> bool:
	return ProcHits.chilled(e)

# ---------------------------------------------------------------- the thrown flask (Consumables)

static func throw_flask(h: Hero, base: String, at: Vector3) -> void:
	Consumables.throw_flask(h, base, at)

## Match server: a server-run hero's game sent what its run did (ServerRules.received, id "run"): a flask thrown
## (Consumables.server_flask) or a blow taken with thorns on (RiteProcs.server_struck). False when it doesn't add up.
static func server_made(h: Hero, kind: String, d: Dictionary) -> bool:
	if h.run == null:
		return false
	match kind:
		"flask":
			return Consumables.server_flask(h, d)
		"struck":
			return RiteProcs.server_struck(h, d)
	return false

# ---------------------------------------------------------------- what is seen (every peer: "run" fx events)

static func play_fx(h: Hero, ev: Dictionary) -> void:
	if str(ev.get("e", "")) == "toss":
		FlaskFx.play(h, ev)
	else:
		RiteFx.play(h, ev)

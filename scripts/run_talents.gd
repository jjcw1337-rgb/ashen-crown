class_name RunTalents
extends RefCounted
## The run's roguelike layer (Blaine, 2026-11-06: "like Slay the Spire, themes of card types for their decks, then
## relics and consumables"): three build directions per class (THEMES: the archer Flame, Frost or Storm and Hunt; the
## plague doctor Toxin, Vermin and Rot or Alchemy), TALENTS that change how a run plays (common to rare: a burning foe that
## dies sets the others alight, poison passes to a new host when its carrier dies, plain arrows ricochet), and GEMS
## (the run's relics: found in camp chests, kept for the run, the survivor keeps them).
##
## A talent is data: {id, cls ("any" or a class), theme, rarity 0-3, max (stacks), name, text, fx (stats summed into
## Hero.tfx like a talent's), proc (a handler below) and k (its numbers, multiplied by the stacks where `per` says)}.
## Procs run on the hero's own game (not a partner's puppet): they deal their damage through the usual channels
## (Enemy.take_damage, ignite, chill), so on a client the host or the raid server applies it, and what is seen goes
## out as "run" fx events (Hero.fx), so partners see the bursts too.
##
## Hooks: Hero._hit_enemy (hit_mult before the roll, on_hit after), Enemy.die_visual (on_death, for the hero who
## struck it last), Enemy.ignite / chill (the striker's burn_pct, burn_dur, chill_pct), Plague._update_poison
## (poison_mult) and Plague._damage (on_dot), Hero.take_hit (struck, save_from_death), Hero.use_skill (echo),
## Hero._process (tick), ArcherShot.impact (on_shot).

## Skills and talents come Common, Uncommon or Rare (Blaine's character structure, 2026-11-06: the rares are the
## run-changers). A fourth colour is the gems' legendary tier (GEMS rarity 3), never a talent's.
static func _static_init() -> void:
	var entries: Array = Codex.shared().get("rites", []).duplicate()
	for cls in THEMES:
		entries.append_array(Codex.hero(cls).get("rites", []))
	for cls in ["serpent", "wyvern"]:
		entries.append_array(Codex.hero(cls).get("rites", []))
	Codex.apply_rites(TALENTS, entries)
	Codex.apply_rites(GEMS, Codex.file("gems.json").get("entries", []), "gems")

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

## The talents: every class's own (beside its talent trees, which RunBuild.passive_pool adds) and the generic ones.
## `per` names the k values that grow with each stack. Texts read {key} from k (times stacks) and fx.
## Laid over by the Hero Codex (data/codex/: a class's in its hero file, "any" in shared.json) when this script loads.
static var TALENTS: Array = [
	# ---- every class
	{"id": "x_execute", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Executioner", "icon": "t_skull",
		"proc": "more_vs_low", "k": {"below": 25, "more": 60}, "text": "Your hits on foes under {below}% life deal +{more}% damage."},
	{"id": "x_momentum", "cls": "any", "theme": "", "rarity": 1, "max": 2, "name": "Momentum", "icon": "t_fist",
		"proc": "momentum", "k": {"dmg": 4, "stacks": 5, "secs": 8}, "per": ["dmg"], "text": "Each kill: +{dmg}% damage for {secs} seconds, up to {stacks} times."},
	{"id": "x_vampire", "cls": "any", "theme": "", "rarity": 1, "max": 2, "name": "Vampiric", "icon": "t_heart",
		"proc": "heal_on_kill", "k": {"pct": 3}, "per": ["pct"], "text": "Each kill heals you for {pct}% of your life."},
	{"id": "x_chain", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Chain Reaction", "icon": "t_star",
		"proc": "explode_on_kill", "k": {"pct": 25, "r": 3.5}, "text": "Monsters you kill explode: {pct}% of their life to everything within {r} m. Kills it causes explode too."},
	{"id": "x_glass", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Glass Cannon", "icon": "t_sword",
		"fx": {"dmg": 35, "life_pct": -20}, "text": "+{dmg}% damage, {life_pct}% maximum life."},
	{"id": "x_undying", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Undying", "icon": "t_ward",
		"proc": "undying", "k": {"life": 35, "secs": 120}, "text": "A blow that would kill you leaves you at {life}% life instead (once every {secs} seconds)."},
	{"id": "x_thorns", "cls": "any", "theme": "", "rarity": 1, "max": 2, "name": "Retribution", "icon": "t_armor",
		"proc": "thorns", "k": {"pct": 60}, "per": ["pct"], "text": "Monsters that strike you take {pct}% of the blow back."},
	{"id": "x_berserk", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Berserker", "icon": "t_fist",
		"proc": "berserk", "k": {"most": 45}, "text": "Up to +{most}% damage as your life runs low."},
	{"id": "x_echo", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Echo", "icon": "t_hourglass",
		"proc": "echo", "k": {"chance": 25}, "text": "A skill with a cooldown has a {chance}% chance to be ready again at once."},
	{"id": "x_giant", "cls": "any", "theme": "", "rarity": 1, "max": 2, "name": "Giant Slayer", "icon": "t_sword",
		"proc": "more_vs_big", "k": {"more": 20}, "per": ["more"], "text": "+{more}% damage to champions and bosses."},
	{"id": "x_frenzy", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Frenzy", "icon": "t_haste",
		"proc": "frenzy", "k": {"ias": 20, "secs": 3}, "text": "Critical hits give +{ias}% attack speed for {secs} seconds."},
	{"id": "x_medic", "cls": "any", "theme": "", "rarity": 0, "max": 2, "name": "Field Medic", "icon": "t_regen",
		"fx": {"pot": 40}, "text": "Potions restore {pot}% more."},
	{"id": "x_lucky", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Lucky Charm", "icon": "t_star",
		"fx": {"offer_plus": 1}, "text": "Camp chests offer one more choice."},
	{"id": "x_treasure", "cls": "any", "theme": "", "rarity": 1, "max": 2, "name": "Treasure Hunter", "icon": "t_eye",
		"fx": {"loot_plus": 1}, "text": "Camp chests hold {loot_plus} more consumable for you."},
	{"id": "x_gemcutter", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Gemcutter", "icon": "t_star",
		"fx": {"gem_luck": 1}, "text": "Camp chests hold a gem twice as often, and rare gems more often."},
	{"id": "x_ward", "cls": "any", "theme": "", "rarity": 1, "max": 2, "name": "Second Skin", "icon": "t_ward",
		"fx": {"ward_bonus": 12}, "text": "A ward soaks blows worth {ward_bonus}% of your life; it refills out of combat."},
	{"id": "x_conduit", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Elemental Conduit", "icon": "t_hourglass",
		"fx": {"burn_dur": 50, "chill_pct": 50, "burn_pct": 15}, "text": "Your burns last {burn_dur}% longer and hurt {burn_pct}% more; your chills last {chill_pct}% longer."},
	{"id": "x_bloodlust", "cls": "any", "theme": "", "rarity": 2, "max": 1, "name": "Bloodlust", "icon": "t_heart",
		"proc": "bloodlust", "k": {"pct": 10, "below": 50}, "text": "Under {below}% life, {pct}% of the damage your hits deal heals you."},
	{"id": "x_adrenaline", "cls": "any", "theme": "", "rarity": 0, "max": 2, "name": "Adrenaline", "icon": "t_boot",
		"proc": "speed_on_kill", "k": {"frw": 12, "secs": 3}, "per": ["frw"], "text": "Each kill: +{frw}% run speed for {secs} seconds."},
	{"id": "x_scholar", "cls": "any", "theme": "", "rarity": 0, "max": 2, "name": "Quick Study", "icon": "t_eye",
		"fx": {"xp_pct": 15}, "text": "+{xp_pct}% experience."},

	# ---- the archer
	{"id": "a_kindling", "cls": "archer", "theme": "flame", "rarity": 0, "max": 3, "name": "Kindling", "icon": "pierce",
		"fx": {"burn_pct": 15, "burn_dur": 25}, "text": "Your burns deal +{burn_pct}% damage and last {burn_dur}% longer."},
	{"id": "a_firetip", "cls": "archer", "theme": "flame", "rarity": 1, "max": 1, "name": "Fire-Tipped", "icon": "pierce",
		"proc": "ignite_on_hit", "k": {"src": "attack", "pct": 30, "secs": 2.5}, "text": "Plain shots set what they strike burning ({pct}% of the hit a second)."},
	{"id": "a_wildfire", "cls": "archer", "theme": "flame", "rarity": 2, "max": 1, "name": "Wildfire", "icon": "pierce",
		"proc": "spread_burn_on_death", "k": {"r": 4.5}, "text": "A burning foe that dies sets everything within {r} m alight."},
	{"id": "a_conflag", "cls": "archer", "theme": "flame", "rarity": 2, "max": 1, "name": "Conflagration", "icon": "pierce",
		"proc": "more_vs_burning", "k": {"more": 30}, "text": "Burning foes take +{more}% damage from your hits."},
	{"id": "a_phoenix", "cls": "archer", "theme": "flame", "rarity": 2, "max": 1, "name": "Phoenix Quiver", "icon": "pierce", "needs": "pierce",
		"proc": "nth_shot", "k": {"n": 5, "skill": "pierce"}, "text": "Every {n}th plain shot looses a free Fire Arrow."},
	{"id": "a_biting", "cls": "archer", "theme": "frost", "rarity": 0, "max": 3, "name": "Biting Cold", "icon": "volley",
		"fx": {"chill_pct": 25}, "text": "Your chills last {chill_pct}% longer and slow more."},
	{"id": "a_frostbite", "cls": "archer", "theme": "frost", "rarity": 1, "max": 2, "name": "Frostbite", "icon": "volley",
		"proc": "more_vs_chilled", "k": {"more": 15}, "per": ["more"], "text": "Chilled foes take +{more}% damage from your hits."},
	{"id": "a_glacial", "cls": "archer", "theme": "frost", "rarity": 1, "max": 1, "name": "Rimed Arrows", "icon": "volley",
		"proc": "chill_on_hit", "k": {"src": "attack", "slow": 0.3, "secs": 2.0}, "text": "Plain shots chill what they strike."},
	{"id": "a_shards", "cls": "archer", "theme": "frost", "rarity": 2, "max": 1, "name": "Ice Shards", "icon": "volley",
		"proc": "shards_on_death", "k": {"pct": 90, "r": 3.5}, "text": "A chilled foe that dies shatters: {pct}% weapon damage to everything within {r} m, chilling them."},
	{"id": "a_zero", "cls": "archer", "theme": "frost", "rarity": 2, "max": 1, "name": "Absolute Zero", "icon": "volley",
		"proc": "freeze_after", "k": {"n": 4, "secs": 1.6}, "text": "Every {n}th hit on a chilled foe freezes it solid for {secs} seconds."},
	{"id": "a_static", "cls": "archer", "theme": "storm", "rarity": 0, "max": 3, "name": "Static Charge", "icon": "snare",
		"fx": {"dmg:snare": 15, "dmg:arc": 15, "dmg:a_stormshot": 15}, "text": "Thunderstep, Arc and Storm Shot deal +{dmg:snare}% damage."},
	{"id": "a_forked", "cls": "archer", "theme": "storm", "rarity": 2, "max": 1, "name": "Forked Shots", "icon": "snare",
		"proc": "chain_on_hit", "k": {"src": "attack", "jumps": 2, "pct": 50, "r": 6.0}, "text": "Plain shots leap on as lightning to {jumps} more foes ({pct}% damage)."},
	{"id": "a_overcharge", "cls": "archer", "theme": "storm", "rarity": 2, "max": 1, "name": "Overcharge", "icon": "snare",
		"proc": "bolt_on_crit", "k": {"pct": 140, "r": 2.5}, "text": "Critical hits call lightning down on the target: {pct}% weapon damage within {r} m."},
	{"id": "a_scent", "cls": "archer", "theme": "storm", "rarity": 1, "max": 2, "name": "Blood Scent", "icon": "beast",
		"proc": "more_vs_low", "k": {"below": 50, "more": 15}, "per": ["more"], "text": "+{more}% damage to foes under {below}% life."},
	{"id": "a_quarry", "cls": "archer", "theme": "storm", "rarity": 2, "max": 1, "name": "Quarry", "icon": "beast",
		"proc": "more_vs_marked", "k": {"more": 30}, "text": "The foe you shot last takes +{more}% damage from you and your wolf."},
	{"id": "a_packleader", "cls": "archer", "theme": "storm", "rarity": 2, "max": 1, "name": "Pack Leader", "icon": "beast",
		"fx": {"wolf_dmg": 100, "wolf_heal": 2}, "text": "Your wolf deals {wolf_dmg}% more damage and each bite heals you {wolf_heal}% of your life."},
	{"id": "a_steady", "cls": "archer", "theme": "", "rarity": 0, "max": 3, "name": "Steady Aim", "icon": "attack",
		"fx": {"dmg:attack": 12}, "text": "Plain shots deal +{dmg:attack}% damage."},
	{"id": "a_eagle", "cls": "archer", "theme": "", "rarity": 1, "max": 2, "name": "Eagle Eye", "icon": "attack",
		"fx": {"crit": 5, "crit_dmg": 20}, "text": "+{crit}% critical chance, +{crit_dmg}% critical damage."},
	{"id": "a_ricochet", "cls": "archer", "theme": "", "rarity": 2, "max": 1, "name": "Ricochet", "icon": "attack",
		"proc": "ricochet", "k": {"pct": 70, "r": 8.0, "bounces": 2}, "text": "Plain shots that strike a foe glance on to {bounces} more ({pct}% damage)."},

	# the archer's skill upgrades (like an upgraded card: offered only once the skill is learned)
	{"id": "a_up_fan", "cls": "archer", "theme": "", "rarity": 1, "max": 1, "name": "Wide Fan", "icon": "a_multishot", "needs": "a_multishot",
		"fx": {"multishot_more": 2, "dmg:a_multishot": 10}, "text": "Scatter Shot looses {multishot_more} more arrows and hits {dmg:a_multishot}% harder."},
	{"id": "a_up_cluster", "cls": "archer", "theme": "flame", "rarity": 2, "max": 1, "name": "Cluster Charge", "icon": "a_explosive", "needs": "a_explosive",
		"fx": {"blast_r": 40, "dmg:a_explosive": 25}, "text": "Blast Arrow's burst is {blast_r}% wider and {dmg:a_explosive}% stronger."},
	{"id": "a_up_shatter", "cls": "archer", "theme": "frost", "rarity": 1, "max": 1, "name": "Shatterpoint", "icon": "a_glacial", "needs": "a_glacial",
		"fx": {"glacial_freeze": 1, "dmg:a_glacial": 15}, "text": "Glacial Shard freezes foes already chilled for a moment, and hits {dmg:a_glacial}% harder."},
	{"id": "a_up_overload", "cls": "archer", "theme": "storm", "rarity": 1, "max": 2, "name": "Overload", "icon": "a_stormshot", "needs": "a_stormshot",
		"fx": {"storm_jumps": 2, "dmg:a_stormshot": 10}, "text": "Storm Shot's lightning leaps to {storm_jumps} more foes and hits {dmg:a_stormshot}% harder."},
	{"id": "a_up_endless", "cls": "archer", "theme": "", "rarity": 2, "max": 1, "name": "Endless Storm", "icon": "a_barrage", "needs": "a_barrage",
		"fx": {"barrage_ticks": 3}, "text": "Arrow Storm rains {barrage_ticks} more times."},
	{"id": "a_up_death", "cls": "archer", "theme": "storm", "rarity": 2, "max": 1, "name": "Marked for Death", "icon": "a_mark", "needs": "a_mark",
		"proc": "mark_reset", "k": {"dmg": 25, "secs": 5}, "text": "A marked foe that dies makes Hunter's Mark ready again and gives you +{dmg}% damage for {secs} seconds."},

	# ---- the plague doctor
	{"id": "p_virulent", "cls": "plague", "theme": "toxin", "rarity": 0, "max": 3, "name": "Virulence", "icon": "toxic",
		"fx": {"poison_dmg": 20}, "text": "Your poison deals +{poison_dmg}% damage."},
	{"id": "p_septic", "cls": "plague", "theme": "toxin", "rarity": 1, "max": 2, "name": "Septic Wounds", "icon": "toxic",
		"proc": "more_vs_poisoned", "k": {"more": 15}, "per": ["more"], "text": "Poisoned foes take +{more}% damage from your blows."},
	{"id": "p_toxblood", "cls": "plague", "theme": "toxin", "rarity": 2, "max": 1, "name": "Toxic Blood", "icon": "toxic",
		"proc": "heal_on_dot", "k": {"pct": 8}, "text": "{pct}% of the poison damage you deal heals you."},
	{"id": "p_necrosis", "cls": "plague", "theme": "toxin", "rarity": 2, "max": 1, "name": "Necrosis", "icon": "toxic",
		"proc": "necrosis", "k": {"grow": 20, "most": 160}, "text": "Poison grows {grow}% crueller every second a foe stays poisoned (up to +{most}%)."},
	{"id": "p_outbreak", "cls": "plague", "theme": "toxin", "rarity": 0, "max": 3, "name": "Outbreak", "icon": "swarm",
		"fx": {"poison_dur": 0.6}, "text": "Your poison lingers {poison_dur} seconds longer."},
	{"id": "p_carrier", "cls": "plague", "theme": "toxin", "rarity": 1, "max": 1, "name": "Plague Carrier", "icon": "attack",
		"proc": "spread_on_hit", "k": {"src": "attack", "r": 4.5, "n": 1}, "text": "Your cane's blows pass a poisoned foe's poison to another within {r} m."},
	{"id": "p_contagion", "cls": "plague", "theme": "toxin", "rarity": 2, "max": 1, "name": "Contagion", "icon": "swarm",
		"proc": "spread_on_death", "k": {"r": 6.0, "n": 3}, "text": "A poisoned foe that dies passes its poison to the {n} nearest within {r} m."},
	{"id": "p_pandemic", "cls": "plague", "theme": "toxin", "rarity": 2, "max": 1, "name": "Pandemic", "icon": "swarm",
		"proc": "cloud_on_death", "k": {"r": 3.5, "pct": 60}, "text": "A poisoned foe that dies bursts in a plague cloud: {pct}% weapon damage and poison to all within {r} m. Its dead burst too."},
	{"id": "p_hunger", "cls": "plague", "theme": "vermin", "rarity": 1, "max": 2, "name": "Ravenous Swarm", "icon": "swarm", "needs": "swarm",
		"fx": {"dmg:swarm": 25, "swarm_heal": 1.5}, "text": "The swarm bites for +{dmg:swarm}% and each bite heals you {swarm_heal}% of your life."},
	{"id": "p_overgrowth", "cls": "plague", "theme": "vermin", "rarity": 2, "max": 1, "name": "Overgrowth", "icon": "bloom", "needs": "bloom",
		"fx": {"bloom_rate": 45, "bloom_size": 20}, "text": "Corpse Bloom pulses {bloom_rate}% more often and reaches {bloom_size}% further."},
	{"id": "p_rotfeast", "cls": "plague", "theme": "vermin", "rarity": 2, "max": 1, "name": "Feast of Rot", "icon": "bloom",
		"proc": "heal_on_kill", "k": {"pct": 5, "poisoned": 1}, "text": "Each poisoned foe that dies heals you {pct}% of your life and makes you +15% faster for 3 s."},
	{"id": "p_volatile", "cls": "plague", "theme": "alchemy", "rarity": 1, "max": 2, "name": "Volatile Reagents", "icon": "toxic", "needs": "toxic",
		"fx": {"vial_burst": 80}, "text": "Pestilence Vial bursts on impact for {vial_burst}% weapon damage."},
	{"id": "p_double", "cls": "plague", "theme": "alchemy", "rarity": 2, "max": 1, "name": "Double Dose", "icon": "toxic", "needs": "toxic",
		"fx": {"vial_twin": 1}, "text": "Pestilence Vial throws a second vial beside the first."},
	{"id": "p_up_miasma", "cls": "plague", "theme": "toxin", "rarity": 1, "max": 1, "name": "Choking Miasma", "icon": "p_miasma", "needs": "p_miasma",
		"fx": {"miasma_r": 30, "miasma_slow": 1}, "text": "Miasma spreads {miasma_r}% wider and slows everything in it."},
	{"id": "p_up_epidemic", "cls": "plague", "theme": "toxin", "rarity": 2, "max": 1, "name": "Epidemic", "icon": "p_spread", "needs": "p_spread",
		"fx": {"curse_jump": 1}, "text": "When a cursed foe dies, Contagion's curse leaps to the nearest foe with its time renewed."},
	{"id": "p_up_leech", "cls": "plague", "theme": "alchemy", "rarity": 1, "max": 2, "name": "Bloated Leeches", "icon": "p_leech", "needs": "p_leech",
		"fx": {"leech_heal": 50, "leech_t": 1.5}, "text": "Leech Jar heals {leech_heal}% more and lasts {leech_t} seconds longer."},
	{"id": "p_tinctures", "cls": "plague", "theme": "alchemy", "rarity": 0, "max": 2, "name": "Strong Tinctures", "icon": "transfusion",
		"fx": {"pot": 35, "cdr": 5}, "text": "Potions restore {pot}% more; skills recharge {cdr}% faster."},

	# ---- the knight
	{"id": "k_up_judgment", "cls": "knight", "theme": "crusader", "rarity": 1, "max": 1, "name": "Wrath of Heaven", "icon": "k_judgment", "needs": "k_judgment",
		"fx": {"judgment_more": 2, "dmg:k_judgment": 10}, "text": "Judgment calls {judgment_more} more pillars round the first, each {dmg:k_judgment}% stronger."},
	{"id": "k_up_aegis", "cls": "knight", "theme": "bulwark", "rarity": 2, "max": 1, "name": "Bastion", "icon": "k_aegis", "needs": "k_aegis",
		"fx": {"aegis_pct": 20, "cd:k_aegis": 20}, "text": "Aegis's ward is {aegis_pct}% of your life stronger and comes back {cd:k_aegis}% sooner; its burst is twice as hard."},
	{"id": "k_up_whirl", "cls": "knight", "theme": "vanguard", "rarity": 1, "max": 2, "name": "Unending Spin", "icon": "k_whirl", "needs": "k_whirl",
		"fx": {"whirl_more": 1, "dmg:k_whirl": 10}, "text": "Blade Storm spins {whirl_more} more time and hits {dmg:k_whirl}% harder."},
	{"id": "k_up_rites", "cls": "knight", "theme": "vanguard", "rarity": 2, "max": 1, "name": "No Quarter", "icon": "k_rites", "needs": "k_rites",
		"fx": {"rites_buff": 1}, "text": "A Last Rites kill also gives you +30% damage and +20% run speed for 4 seconds."},
	{"id": "k_brands", "cls": "knight", "theme": "crusader", "rarity": 2, "max": 1, "name": "Searing Brands", "icon": "t_star",
		"fx": {"brand_max": 3, "brand_burn": 1}, "text": "Holy Brands stack {brand_max} higher and each one burns its foe a little."},
	{"id": "k_zealot", "cls": "knight", "theme": "crusader", "rarity": 1, "max": 2, "name": "Zealot", "icon": "t_sword",
		"proc": "ignite_on_hit", "k": {"src": "attack", "pct": 18, "secs": 3.0}, "per": ["pct"], "text": "Your sword sets foes alight with holy fire ({pct}% of the blow a second)."},
	{"id": "k_iron", "cls": "knight", "theme": "bulwark", "rarity": 0, "max": 3, "name": "Iron Hide", "icon": "t_armor",
		"fx": {"armor_pct": 15, "ward_bonus": 4}, "text": "+{armor_pct}% defense and a ward of {ward_bonus}% of your life that refills out of combat."},
	{"id": "k_cleave", "cls": "knight", "theme": "vanguard", "rarity": 1, "max": 1, "name": "Cleaving Blows", "icon": "attack",
		"proc": "ricochet", "k": {"pct": 50, "r": 3.0, "bounces": 2}, "text": "Your sword's blows cleave into {bounces} more foes beside the one struck ({pct}%)."},
	{"id": "k_sacred", "cls": "knight", "theme": "crusader", "rarity": 2, "max": 1, "name": "Sacred Flame", "icon": "nova",
		"proc": "ignite_on_crit", "k": {"pct": 60, "secs": 3.0}, "text": "Critical hits set foes alight with holy fire ({pct}% of the hit a second)."},
	{"id": "k_martyr", "cls": "knight", "theme": "bulwark", "rarity": 2, "max": 1, "name": "Martyr's Resolve", "icon": "t_ward",
		"proc": "thorns", "k": {"pct": 120}, "text": "Monsters that strike you take {pct}% of the blow back in holy fire."},
	{"id": "k_onslaught", "cls": "knight", "theme": "vanguard", "rarity": 2, "max": 1, "name": "Onslaught", "icon": "charge",
		"proc": "momentum", "k": {"dmg": 8, "stacks": 6, "secs": 6}, "text": "Each kill: +{dmg}% damage for {secs} seconds, up to {stacks} times."},
	# ---- the wraith
	{"id": "r_up_mark", "cls": "wraith", "theme": "render", "rarity": 2, "max": 1, "name": "Marked Soul", "icon": "r_deathmark", "needs": "r_deathmark",
		"fx": {"mark_pct": 30, "cd:r_deathmark": 25}, "text": "Death Mark tears out {mark_pct}% more and comes back {cd:r_deathmark}% sooner."},
	{"id": "r_up_wail", "cls": "wraith", "theme": "shadow", "rarity": 1, "max": 1, "name": "Keening", "icon": "r_wail", "needs": "r_wail",
		"fx": {"wail_r": 30, "wail_t": 0.6}, "text": "Banshee Wail reaches {wail_r}% further and terrifies {wail_t} seconds longer."},
	{"id": "r_up_reap", "cls": "wraith", "theme": "night", "rarity": 1, "max": 2, "name": "Harvest of Souls", "icon": "r_reap", "needs": "r_reap",
		"fx": {"dmg:r_reap": 15, "reap_heal": 1}, "text": "Reaping Crescent hits {dmg:r_reap}% harder and heals {reap_heal}% more for each it reaps."},
	{"id": "r_reaper", "cls": "wraith", "theme": "render", "rarity": 2, "max": 1, "name": "Reaper", "icon": "rend",
		"proc": "more_vs_low", "k": {"below": 35, "more": 80}, "text": "Your hits on foes under {below}% life deal +{more}% damage."},
	{"id": "r_soulfeast", "cls": "wraith", "theme": "shadow", "rarity": 2, "max": 1, "name": "Soul Feast", "icon": "siphon",
		"proc": "heal_on_kill", "k": {"pct": 5}, "text": "Each kill heals you {pct}% of your life."},
	{"id": "r_dread", "cls": "wraith", "theme": "night", "rarity": 2, "max": 1, "name": "Dread", "icon": "night",
		"proc": "chill_on_hit", "k": {"src": "", "slow": 0.35, "secs": 2.0}, "text": "Every hit chills its foe with dread."},
	# ---- the demon
	{"id": "d_up_volcano", "cls": "demon", "theme": "cataclysm", "rarity": 2, "max": 1, "name": "Ring of Fire", "icon": "d_volcano", "needs": "d_volcano",
		"fx": {"volcano_more": 3, "dmg:d_volcano": 10}, "text": "Volcano hurls {volcano_more} more meteors, each {dmg:d_volcano}% harder."},
	{"id": "d_up_detonate", "cls": "demon", "theme": "magma", "rarity": 1, "max": 1, "name": "Chain Brand", "icon": "d_detonate", "needs": "d_detonate",
		"fx": {"detonate_brand": 1}, "text": "Hellbrand Detonation Brands everything its eruptions strike."},
	{"id": "d_up_pact", "cls": "demon", "theme": "pit", "rarity": 1, "max": 2, "name": "Blood Price", "icon": "d_pact", "needs": "d_pact",
		"fx": {"pact_pow": 10}, "text": "Blood Pact gives {pact_pow}% more damage."},
	{"id": "d_hellfire", "cls": "demon", "theme": "magma", "rarity": 2, "max": 1, "name": "Hellfire", "icon": "fists",
		"proc": "ignite_on_hit", "k": {"src": "", "pct": 20, "secs": 3.0}, "text": "Every blow sets its foe alight ({pct}% of the hit a second)."},
	{"id": "d_eruption", "cls": "demon", "theme": "cataclysm", "rarity": 2, "max": 1, "name": "Eruption", "icon": "cslam",
		"proc": "explode_on_kill", "k": {"pct": 30, "r": 4.0}, "text": "Foes you kill erupt: {pct}% of their life to all within {r} m."},
	{"id": "d_pitborn", "cls": "demon", "theme": "pit", "rarity": 2, "max": 1, "name": "Pitborn Hide", "icon": "wrath",
		"proc": "thorns", "k": {"pct": 100}, "text": "Monsters that strike you take {pct}% of the blow back."},
	# ---- Doug
	{"id": "u_up_barrage", "cls": "doug", "theme": "slapstick", "rarity": 1, "max": 2, "name": "Bakery Order", "icon": "u_barrage", "needs": "u_barrage",
		"fx": {"barrage_more": 3}, "text": "Pie Barrage flings {barrage_more} more pies."},
	{"id": "u_up_cannon", "cls": "doug", "theme": "bigtop", "rarity": 2, "max": 1, "name": "Extra Gunpowder", "icon": "u_cannon", "needs": "u_cannon",
		"fx": {"cannon_r": 30, "dmg:u_cannon": 20}, "text": "Human Cannonball lands {cannon_r}% wider and {dmg:u_cannon}% harder."},
	{"id": "u_encore", "cls": "doug", "theme": "showman", "rarity": 2, "max": 1, "name": "Standing Ovation", "icon": "juggle",
		"proc": "echo", "k": {"chance": 35}, "text": "A skill with a cooldown has a {chance}% chance to be ready again at once."},
	{"id": "u_slapstick", "cls": "doug", "theme": "slapstick", "rarity": 2, "max": 1, "name": "Comic Timing", "icon": "pie",
		"proc": "frenzy", "k": {"ias": 30, "secs": 3}, "text": "Critical hits give +{ias}% attack speed for {secs} seconds."},
	# ---- the dragons
	{"id": "s_permafrost", "cls": "serpent", "theme": "frost", "rarity": 2, "max": 1, "name": "Permafrost", "icon": "frost_breath",
		"proc": "freeze_after", "k": {"n": 5, "secs": 1.4}, "text": "Every {n}th hit on a chilled foe freezes it solid for {secs} seconds."},
	{"id": "s_shatter", "cls": "serpent", "theme": "frost", "rarity": 2, "max": 1, "name": "Brittle", "icon": "frost_breath",
		"proc": "more_vs_chilled", "k": {"more": 25}, "text": "Chilled foes take +{more}% damage from your hits."},
	{"id": "v_tempest", "cls": "wyvern", "theme": "storm", "rarity": 2, "max": 1, "name": "Tempest", "icon": "storm_arc",
		"proc": "bolt_on_crit", "k": {"pct": 160, "r": 3.0}, "text": "Critical hits call lightning down: {pct}% weapon damage within {r} m."},
	{"id": "y_hide", "cls": "serpent,wyvern", "theme": "beast", "rarity": 0, "max": 3, "name": "Dragonhide", "icon": "t_armor",
		"fx": {"armor_pct": 15, "life_pct": 6}, "text": "+{armor_pct}% defense and +{life_pct}% life."},
	{"id": "y_claws", "cls": "serpent,wyvern", "theme": "beast", "rarity": 1, "max": 2, "name": "Rending Claws", "icon": "attack",
		"fx": {"dmg:attack": 15, "crit": 3}, "text": "Claws and bites deal +{dmg:attack}%; +{crit}% critical chance."},
	{"id": "y_apex", "cls": "serpent,wyvern", "theme": "beast", "rarity": 2, "max": 1, "name": "Apex Predator", "icon": "t_skull",
		"proc": "more_vs_low", "k": {"below": 40, "more": 40}, "text": "+{more}% damage to foes under {below}% life."},
	{"id": "y_fury", "cls": "serpent,wyvern", "theme": "beast", "rarity": 2, "max": 1, "name": "Primal Fury", "icon": "t_fist",
		"proc": "momentum", "k": {"dmg": 6, "stacks": 6, "secs": 8}, "text": "Each kill: +{dmg}% damage for {secs} seconds, up to {stacks} times."},
	{"id": "s_rime", "cls": "serpent", "theme": "frost", "rarity": 0, "max": 3, "name": "Frozen Blood", "icon": "frost_breath",
		"fx": {"chill_pct": 25, "dmg:frost_breath": 10}, "text": "Chills last {chill_pct}% longer; Frost Breath +{dmg:frost_breath}%."},
	{"id": "v_lord", "cls": "wyvern", "theme": "storm", "rarity": 0, "max": 3, "name": "Storm Lord", "icon": "storm_arc",
		"fx": {"dmg:storm_arc": 15, "dmg:arc": 15}, "text": "Storm Arc and Arc deal +{dmg:storm_arc}%."},
	# the dragons' run skills' upgrades and their third directions (Glacier, Sky)
	{"id": "s_up_tomb", "cls": "serpent", "theme": "glacier", "rarity": 1, "max": 2, "name": "Deep Freeze", "icon": "s_tomb", "needs": "s_tomb",
		"fx": {"tomb_r": 30, "tomb_t": 0.4, "dmg:s_tomb": 15}, "text": "Glacial Tomb seals {tomb_r}% wider, holds {tomb_t} s longer and shatters {dmg:s_tomb}% harder."},
	{"id": "s_up_coil", "cls": "serpent", "theme": "beast", "rarity": 1, "max": 2, "name": "Iron Coils", "icon": "s_coil", "needs": "s_coil",
		"fx": {"coil_r": 15, "dmg:s_coil": 15, "coil_shield": 1}, "text": "Crushing Coil reaches {coil_r}% further, hits {dmg:s_coil}% harder and heals {coil_shield}% of your life for each foe it crushes."},
	{"id": "s_up_lance", "cls": "serpent", "theme": "frost", "rarity": 2, "max": 1, "name": "Spear of Winter", "icon": "s_lance", "needs": "s_lance",
		"fx": {"lance_len": 40, "lance_freeze": 0.8, "dmg:s_lance": 20}, "text": "Rime Lance runs {lance_len}% further, freezes {lance_freeze} s longer and hits {dmg:s_lance}% harder."},
	{"id": "s_glacier_hide", "cls": "serpent", "theme": "glacier", "rarity": 0, "max": 3, "name": "Rime Scales", "icon": "t_armor",
		"fx": {"armor_pct": 12, "res": 6}, "text": "+{armor_pct}% defense and +{res}% to every resistance."},
	{"id": "s_glacier_cold", "cls": "serpent", "theme": "glacier", "rarity": 0, "max": 3, "name": "Biting Cold", "icon": "s_tomb",
		"fx": {"chill_pct": 20, "dmg:s_tomb": 10}, "text": "Chills last {chill_pct}% longer; Glacial Tomb +{dmg:s_tomb}%."},
	{"id": "s_glacier_thorns", "cls": "serpent", "theme": "glacier", "rarity": 1, "max": 2, "name": "Frozen Barbs", "icon": "t_armor",
		"proc": "thorns", "k": {"pct": 30}, "per": ["pct"], "text": "Foes that strike you take {pct}% of the blow back as cold."},
	{"id": "s_glacier_shards", "cls": "serpent", "theme": "glacier", "rarity": 2, "max": 1, "name": "Shatterpoint", "icon": "frost_breath",
		"proc": "shards_on_death", "k": {"pct": 60, "r": 3.0}, "text": "Chilled foes that die burst into ice shards: {pct}% weapon damage within {r} m, chilling."},
	{"id": "s_glacier_undying", "cls": "serpent", "theme": "glacier", "rarity": 2, "max": 1, "name": "Heart of the Glacier", "icon": "t_armor",
		"proc": "undying", "k": {"life": 40, "secs": 90}, "text": "A blow that would kill you leaves you at {life}% life inside a shell of ice instead (once every {secs} seconds)."},
	{"id": "v_up_dive", "cls": "wyvern", "theme": "sky", "rarity": 1, "max": 2, "name": "Plummet", "icon": "v_dive", "needs": "v_dive",
		"fx": {"dive_r": 20, "dmg:v_dive": 20, "cd:v_dive": 15}, "text": "Thunder Dive lands {dive_r}% wider, {dmg:v_dive}% harder and comes back {cd:v_dive}% sooner."},
	{"id": "v_up_cloud", "cls": "wyvern", "theme": "storm", "rarity": 2, "max": 1, "name": "Supercell", "icon": "v_cloud", "needs": "v_cloud",
		"fx": {"cloud_rate": 30, "cloud_t": 1.5, "cloud_stun": 25}, "text": "Thunderhead strikes {cloud_rate}% faster, lasts {cloud_t} s longer, and each bolt has a {cloud_stun}% chance to stun."},
	{"id": "v_up_gale", "cls": "wyvern", "theme": "sky", "rarity": 1, "max": 2, "name": "Hurricane", "icon": "v_gale", "needs": "v_gale",
		"fx": {"gale_r": 25, "dmg:v_gale": 20}, "text": "Gale Wings reaches {gale_r}% further and hits {dmg:v_gale}% harder."},
	{"id": "v_sky_speed", "cls": "wyvern", "theme": "sky", "rarity": 0, "max": 3, "name": "Tailwind", "icon": "v_gale",
		"fx": {"frw": 4, "cd:v_dive": 8}, "text": "+{frw}% run speed; Thunder Dive {cd:v_dive}% sooner."},
	{"id": "v_sky_dodge", "cls": "wyvern", "theme": "sky", "rarity": 0, "max": 3, "name": "Wind-Rider", "icon": "v_dive",
		"fx": {"dex": 4, "dmg:v_dive": 10, "dmg:v_gale": 10}, "text": "+{dex} Dexterity; Thunder Dive and Gale Wings +{dmg:v_dive}%."},
	{"id": "v_sky_kill", "cls": "wyvern", "theme": "sky", "rarity": 1, "max": 2, "name": "Hunter's Updraft", "icon": "v_dive",
		"proc": "speed_on_kill", "k": {"frw": 15, "secs": 3}, "per": ["frw"], "text": "Each kill: +{frw}% run speed for {secs} seconds."},
	{"id": "v_sky_reset", "cls": "wyvern", "theme": "sky", "rarity": 2, "max": 1, "name": "Eye of the Storm", "icon": "v_dive",
		"fx": {"dive_reset": 1}, "text": "A kill with Thunder Dive makes it ready again."},
	{"id": "v_static", "cls": "wyvern", "theme": "storm", "rarity": 2, "max": 1, "name": "Static Claws", "icon": "storm_arc",
		"proc": "chain_on_hit", "k": {"src": "attack", "jumps": 2, "pct": 40, "r": 6.0}, "text": "Claws leap on as lightning to {jumps} more foes ({pct}%)."},
]

## The gems: a run's relics. Found in camp chests (more often in deeper camps; a boss always gives one, often
## legendary), kept for the run and by its survivor. Common and rare gems are stats; legendary ones change the run.
## Laid over by the Hero Codex (data/codex/gems.json) when this script loads.
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

# ---------------------------------------------------------------- data

static func theme_def(cls: String, id: String) -> Dictionary:
	for t in THEMES.get(cls, []):
		if t["id"] == id:
			return t
	return {}

static func talents_for(cls: String) -> Array:
	return TALENTS.filter(func(t): return t["cls"] == "any" or t["cls"] == cls or (str(t["cls"]).contains(",") and str(t["cls"]).split(",").has(cls)))

## This hero struck `e` now: its death is theirs for the next 4 s (on_death). Every way a hero hurts a monster marks
## it: a blow (hit_mult), poison (Plague._damage), a burn set (Enemy.ignite), a proc (_deal).
static func mark(h: Hero, e) -> void:
	if h != null and h.run != null and not h.puppet and e != null and is_instance_valid(e):
		e.set_meta("run_hit", [h, Time.get_ticks_msec()])

## A gem's painted icon (Meshy, tools/skill_icons.py grids "gems", "gems2", "potions"), or null.
static func gem_icon(id: String) -> Texture2D:
	var p := "res://assets/textures/gems/%s.png" % id
	return ResCache.get_res(p) as Texture2D if ResourceLoader.exists(p) else null

static func gem_def(id: String) -> Dictionary:
	for g in GEMS:
		if g["id"] == id:
			return g
	return {}

## A talent's (or gem's) k at `stacks`: the numbers in `per` grow with each stack.
static func k_at(t: Dictionary, stacks: int) -> Dictionary:
	var k: Dictionary = t.get("k", {}).duplicate()
	for key in t.get("per", []):
		k[key] = float(k[key]) * stacks
	return k

## The text with {key} filled from fx (times stacks) and k (its `per` numbers times stacks); `from` > 0 shows the
## change from that many stacks: "+15% -> +30%".
static func text_of(t: Dictionary, stacks: int, from := 0) -> String:
	var s := str(t.get("text", ""))
	for key in t.get("fx", {}):
		var v := float(t["fx"][key])
		s = s.replace("{" + key + "}", (RunBuild._num(v * from) + " → " + RunBuild._num(v * stacks)) if from > 0 else RunBuild._num(v * stacks))
	var per: Array = t.get("per", [])
	for key in t.get("k", {}):
		var raw = t["k"][key]
		if typeof(raw) == TYPE_STRING:
			continue
		var v := float(raw)
		if per.has(key) and from > 0:
			s = s.replace("{" + key + "}", RunBuild._num(v * from) + " → " + RunBuild._num(v * stacks))
		else:
			s = s.replace("{" + key + "}", RunBuild._num(v * (stacks if per.has(key) else 1)))
	return s

# ---------------------------------------------------------------- the hero's active procs

## [def, stacks] for every talent and gem with a proc this hero has (cached on the run; RunBuild.changed() clears it).
static func procs(h: Hero) -> Array:
	var r: RunBuild = h.run
	if r == null:
		return []
	if r.proc_cache != null:
		return r.proc_cache
	var out := []
	for id in r.passives:
		var t := RunBuild.passive_def(h.cls, id)
		if t.has("proc"):
			out.append([t, int(r.passives[id])])
	for g in r.gems:
		var gd := gem_def(str(g))
		if gd.has("proc"):
			out.append([gd, 1])
	r.proc_cache = out
	return out

static func _active(h: Hero, proc: String) -> Array:
	return procs(h).filter(func(p): return p[0]["proc"] == proc)

## A monster this hero's procs may work on (a player's stand-in or breakable thing takes only the plain blow).
static func _monster(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead and e.pvp_pid == 0 and e.pvp_obj == 0 and e.sandbox_hero == null

static func _src_ok(k: Dictionary, src: String) -> bool:
	var want := str(k.get("src", ""))
	return want == "" or want == src

## Is a foe poisoned by this hero (the Plague Doctor's own poison)?
static func poisoned(h: Hero, e) -> bool:
	return h.pd != null and h.pd.poison.has(e.get_instance_id())

## Burning or rotting (an ignite from anyone: the Fire Arrow, the Demon, a blight).
static func burning(e) -> bool:
	return e.burn_t > 0.0

static func chilled(e) -> bool:
	return e.chill_t > 0.0 or e.has_meta("frozen_t")

## The proc damage being dealt now: a proc's own hit never sets off other procs (no endless chains, except the
## kills it causes, which chain_depth allows a few deep).
static var _in_proc := false
static var _depth := 0

## The multiplier on one of this hero's hits on `e` (before the roll): the conditional talents.
static func hit_mult(h: Hero, e, src: String) -> float:
	if h.run == null or e == null or not is_instance_valid(e):
		return 1.0
	mark(h, e)
	var m := 1.0
	var r: RunBuild = h.run
	for p in procs(h):
		var t: Dictionary = p[0]
		var k := k_at(t, int(p[1]))
		match str(t["proc"]):
			"more_vs_low":
				if e.max_life > 0.0 and e.life / e.max_life * 100.0 < float(k["below"]):
					m *= 1.0 + float(k["more"]) / 100.0
			"more_vs_burning":
				if burning(e):
					m *= 1.0 + float(k["more"]) / 100.0
			"more_vs_chilled":
				if chilled(e):
					m *= 1.0 + float(k["more"]) / 100.0
			"more_vs_poisoned":
				if poisoned(h, e):
					m *= 1.0 + float(k["more"]) / 100.0
			"more_vs_marked":
				if h.mark == e and h.mark_t > 0.0:
					m *= 1.0 + float(k["more"]) / 100.0
			"more_vs_big":
				if e.boss or e.champion:
					m *= 1.0 + float(k["more"]) / 100.0
			"berserk":
				var missing := 1.0 - h.life / maxf(1.0, h.max_life)
				m *= 1.0 + float(k["most"]) / 100.0 * clampf(missing / 0.8, 0.0, 1.0)
	if r.hunger > 0.0:
		m *= 1.0 + r.hunger / 100.0
	if e.has_meta("slipped_until"):
		# Banana Bonanza (Doug's run skill): the next blow on a foe that slipped on one of its peels
		if Time.get_ticks_msec() < int(e.get_meta("slipped_until")):
			m *= 2.0
		e.remove_meta("slipped_until")
	return m

## After one of this hero's hits landed on `e`.
static func on_hit(h: Hero, e, dealt: float, crit: bool, src: String) -> void:
	if h.run == null or h.puppet or _in_proc or e == null or not is_instance_valid(e):
		return
	e.set_meta("run_hit", [h, Time.get_ticks_msec()])
	var list := procs(h)
	if list.is_empty():
		return
	var foe_ok: bool = _monster(e) or e.pvp_pid > 0
	for p in list:
		var t: Dictionary = p[0]
		var k := k_at(t, int(p[1]))
		match str(t["proc"]):
			"ignite_on_hit":
				if _src_ok(k, src) and not e.dead and foe_ok:
					e.ignite(dealt * float(k["pct"]) / 100.0, float(k["secs"]), "" if h.cls != "archer" else "fire")
					if h.cls == "archer":
						ArrowFx.burn(h.game, e, "fire", float(k["secs"]))
			"ignite_on_crit":
				if crit and not e.dead and foe_ok:
					e.ignite(dealt * float(k["pct"]) / 100.0, float(k["secs"]))
			"chill_on_hit":
				if _src_ok(k, src) and not e.dead and foe_ok:
					e.chill(float(k["slow"]), float(k["secs"]))
			"freeze_after":
				if chilled(e) and not e.dead and _monster(e):
					var n := int(e.get_meta("frost_hits", 0)) + 1
					if n >= int(k["n"]):
						n = 0
						_freeze(h, e, float(k["secs"]))
					e.set_meta("frost_hits", n)
			"chain_on_hit":
				if _src_ok(k, src) and _monster(e):
					_chain(h, e, int(k["jumps"]), dealt * float(k["pct"]) / 100.0, float(k["r"]))
			"ricochet":
				if (src == "attack" or src == "") and _monster(e):
					_ricochet(h, e, int(k["bounces"]), dealt * float(k["pct"]) / 100.0, float(k["r"]))
			"bolt_on_crit":
				if crit and _monster(e):
					_bolt(h, e.global_position, _weapon(h) * float(k["pct"]) / 100.0, float(k["r"]))
			"nth_hit_bolt":
				if _monster(e):
					var c := int(h.run.counters.get("bolt", 0)) + 1
					if c >= int(k["n"]):
						c = 0
						_bolt(h, e.global_position, _weapon(h) * float(k["pct"]) / 100.0, float(k["r"]))
					h.run.counters["bolt"] = c
			"frenzy":
				if crit:
					buff(h, "frenzy", {"ias": float(k["ias"])}, float(k["secs"]))
			"bloodlust":
				if h.life < h.max_life * float(k["below"]) / 100.0:
					h.life = minf(h.max_life, h.life + dealt * float(k["pct"]) / 100.0)
			"spread_on_hit":
				if _src_ok(k, src) and poisoned(h, e):
					_spread_poison(h, e, int(k["n"]), float(k["r"]))

## A monster died: the procs of the hero who struck it last (within 4 s), on that hero's game.
static func on_death(e) -> void:
	if not e.has_meta("run_hit"):
		return
	var rec: Array = e.get_meta("run_hit")
	var h = rec[0]
	if not is_instance_valid(h) or h.run == null or h.puppet or h.dead:
		return
	if Time.get_ticks_msec() - int(rec[1]) > 4000 or not (e.pvp_pid == 0 and e.pvp_obj == 0 and e.sandbox_hero == null):
		return
	var was_burning := burning(e)
	var was_chilled := chilled(e)
	var was_poisoned := poisoned(h, e)
	for p in procs(h):
		var t: Dictionary = p[0]
		var k := k_at(t, int(p[1]))
		match str(t["proc"]):
			"momentum":
				var n := mini(int(h.run.counters.get("momentum", 0)) + 1, int(k["stacks"]))
				h.run.counters["momentum"] = n
				buff(h, "momentum", {"dmg": float(k["dmg"]) * n}, float(k["secs"]), "momentum")
			"heal_on_kill":
				if int(k.get("poisoned", 0)) == 0 or was_poisoned:
					h.life = minf(h.max_life, h.life + h.max_life * float(k["pct"]) / 100.0)
					if int(k.get("poisoned", 0)) == 1:
						buff(h, "rotfeast", {"frw": 15.0}, 3.0)
			"explode_on_kill":
				if _depth < 3:
					var amt := minf(e.max_life * float(k["pct"]) / 100.0, _weapon(h) * 4.0)
					_area(h, e.global_position, float(k["r"]), amt, "fire" if h.cls != "warlock" else "fel", e)
			"spread_burn_on_death":
				if was_burning:
					var dps := maxf(e.burn_dps, _weapon(h) * 0.25)
					var hit := 0
					for o in h.game.enemies_near(e.global_position, float(k["r"])):
						if o != e and _monster(o):
							o.ignite(dps, maxf(2.5, e.burn_t), e.burn_look)
							if e.burn_look != "":
								ArrowFx.burn(h.game, o, e.burn_look, 2.5)
							hit += 1
					h.fx("run", "flare", {"p": e.global_position, "r": float(k["r"]), "n": 0})
			"shards_on_death":
				if was_chilled and _depth < 3:
					_area(h, e.global_position, float(k["r"]), _weapon(h) * float(k["pct"]) / 100.0, "frost", e)
			"spread_on_death":
				if was_poisoned:
					_spread_poison(h, e, int(k["n"]), float(k["r"]))
			"cloud_on_death":
				if was_poisoned and _depth < 3:
					_area(h, e.global_position, float(k["r"]), _weapon(h) * float(k["pct"]) / 100.0, "plague", e)
			"hunger":
				h.run.hunger = minf(float(k["most"]), h.run.hunger + float(k["per"]))
			"speed_on_kill":
				buff(h, "adrenaline", {"frw": float(k["frw"])}, float(k["secs"]))
			"mark_reset":
				if e.has_meta("hunted_until") and Time.get_ticks_msec() < int(e.get_meta("hunted_until")):
					h.cds["a_mark"] = 0.0
					buff(h, "marked_death", {"dmg": float(k["dmg"])}, float(k["secs"]))

## Poison ticking on `e`: Necrosis's growth (Plague._update_poison multiplies the tick by this).
static func poison_mult(h: Hero, age: float) -> float:
	if h.run == null:
		return 1.0
	var m := 1.0
	for p in _active(h, "necrosis"):
		var k := k_at(p[0], int(p[1]))
		m *= 1.0 + minf(float(k["most"]), float(k["grow"]) * age) / 100.0
	return m

## Poison (or another damage over time of his) dealt `amount` to `e`.
static func on_dot(h: Hero, _e, amount: float) -> void:
	if h.run == null or h.puppet or amount <= 0.0:
		return
	for p in _active(h, "heal_on_dot"):
		var k := k_at(p[0], int(p[1]))
		h.life = minf(h.max_life, h.life + amount * float(k["pct"]) / 100.0)

## This hero was struck for `dmg` from `from` (after armour): Retribution's blow back.
static func struck(h: Hero, dmg: float, from: Vector3) -> void:
	if h.run == null or h.puppet or dmg <= 0.0:
		return
	var list := _active(h, "thorns")
	if list.is_empty():
		return
	var best = null
	var bd := 4.0
	for e in h.game.enemies_near(from, 4.0):
		if _monster(e):
			var d: float = e.global_position.distance_to(from)
			if d < bd:
				bd = d
				best = e
	if best == null:
		return
	var pct := 0.0
	for p in list:
		pct += float(k_at(p[0], int(p[1]))["pct"])
	_deal(h, best, dmg * pct / 100.0, "holy" if h.cls == "knight" else "phys")

## A killing blow on this hero: true when a talent or gem refuses it (life is set; the caller doesn't die).
static func save_from_death(h: Hero) -> bool:
	if h.run == null or h.puppet:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	for p in _active(h, "undying"):
		var t: Dictionary = p[0]
		var k := k_at(t, int(p[1]))
		var key := "undying_" + str(t["id"])
		var last := float(h.run.counters.get(key, -100000.0))
		if now - last < float(k["secs"]):
			continue
		if int(k.get("burst", 0)) == 1 and h.run.counters.has(key):
			continue          # (the Phoenix Ember: once a run)
		h.run.counters[key] = now
		h.life = h.max_life * float(k["life"]) / 100.0
		h.fx("run", "undying", {"p": h.global_position, "n": int(k.get("burst", 0))})
		if int(k.get("burst", 0)) == 1:
			for e in h.game.enemies_near(h.global_position, 5.0):
				if _monster(e):
					e.ignite(_weapon(h) * 0.6, 4.0)
		if h._mine():
			h.game.ui.message(str(t["name"]) + ": not yet", RARITY_COLORS[3])
		return true
	return false

## A skill went on cooldown: Echo may bring it back at once.
static func on_cooldown(h: Hero, id: String) -> void:
	if h.run == null or h.puppet or h.cds.get(id, 0.0) <= 0.0:
		return
	for p in _active(h, "echo"):
		var k := k_at(p[0], int(p[1]))
		if randf() * 100.0 < float(k["chance"]):
			h.cds[id] = 0.0
			h.fx("run", "echo", {"p": h.global_position})
			return

## A plain shot was loosed (ArcherShot.impact): Phoenix Quiver's every-nth free skill.
static func on_shot(h: Hero) -> void:
	if h.run == null or h.puppet:
		return
	for p in _active(h, "nth_shot"):
		var k := k_at(p[0], int(p[1]))
		var c := int(h.run.counters.get("shot", 0)) + 1
		if c >= int(k["n"]):
			c = 0
			ClassSkills.free_cast(h, str(k["skill"]), h.atk_aim)
		h.run.counters["shot"] = c

## Every frame on the hero's own game: the timed buffs running out.
static func tick(h: Hero, delta: float) -> void:
	var r: RunBuild = h.run
	if r == null or r.buffs.is_empty():
		return
	var gone := false
	for key in r.buffs.keys():
		r.buffs[key]["t"] = float(r.buffs[key]["t"]) - delta
		if float(r.buffs[key]["t"]) <= 0.0:
			r.buffs.erase(key)
			if key == "momentum":
				r.counters["momentum"] = 0
			gone = true
	if gone:
		h.refresh_run()

## A timed buff of stats (momentum, frenzy, a consumable's): added to the run's fx until it runs out.
static func buff(h: Hero, key: String, fx: Dictionary, secs: float, _kind := "") -> void:
	if h.run == null:
		return
	var had: bool = h.run.buffs.has(key)
	var same: bool = had and h.run.buffs[key]["fx"] == fx
	h.run.buffs[key] = {"t": secs, "fx": fx}
	if not same:
		h.refresh_run()

# ---------------------------------------------------------------- what procs do

## The hero's weapon hit, the base most proc damage is a share of.
static func _weapon(h: Hero) -> float:
	return (h.dmg_min + h.dmg_max) * 0.5 * h.buff_mult() * (1.0 + h.talent("dmg") / 100.0)

## Proc damage on one foe, through the usual channel (on a client the host applies it).
static func _deal(h: Hero, e, amount: float, kind: String) -> void:
	if e == null or not is_instance_valid(e) or e.dead or amount <= 0.0:
		return
	var was := _in_proc
	_in_proc = true
	Hero.striker = h
	e.set_meta("run_hit", [h, Time.get_ticks_msec()])
	match kind:
		"fire", "holy": e.dmg_tint = Color(1.0, 0.62, 0.25)
		"frost": e.dmg_tint = Color(0.6, 0.88, 1.0)
		"storm": e.dmg_tint = Color(0.75, 0.78, 1.0)
		"plague", "fel": e.dmg_tint = Color(0.5, 1.0, 0.35)
	e.soft_hit = true
	var dealt: float = e.take_damage(0.0, amount, h.global_position, 0.0, false)
	e.dmg_tint = Color(0, 0, 0, 0)
	e.soft_hit = false
	if h.ls > 0.0:
		h.life = minf(h.max_life, h.life + dealt * h.ls / 200.0)
	_in_proc = was

## Damage in a circle (the explosions, shards and plague clouds), the dead excluded; its own kills may set off
## death procs again, a few deep.
static func _area(h: Hero, at: Vector3, r: float, amount: float, kind: String, skip = null) -> void:
	_depth += 1
	var n := 0
	match kind:
		"fire": h.fx("run", "flare", {"p": at, "r": r, "n": 0})
		"fel": h.fx("run", "flare", {"p": at, "r": r, "n": 1})
		"frost": h.fx("run", "shards", {"p": at, "r": r})
		"plague": h.fx("run", "cloud", {"p": at, "r": r})
	for e in h.game.enemies_near(at, r):
		if e == skip or not _monster(e):
			continue
		_deal(h, e, amount, kind)
		match kind:
			"frost":
				if not e.dead:
					e.chill(0.35, 2.5)
			"plague":
				if not e.dead and h.pd != null:
					h.pd._poison(e, "toxic", 3.0)
		n += 1
	_depth -= 1

## Frozen solid: stunned (bosses a third as long, Enemy.stun) under a crust of rime.
static func _freeze(h: Hero, e, secs: float) -> void:
	e.stun(secs)
	e.chill(0.6, secs + 1.0)
	h.fx("run", "freeze", {"p": e.global_position, "r": e.radius + 0.4, "x": secs})

## Lightning from `e` through the nearest others.
static func _chain(h: Hero, e, jumps: int, amount: float, r: float) -> void:
	var at: Vector3 = e.global_position
	var done := {e: true}
	var pts := PackedVector3Array([at + Vector3(0, 1.2, 0)])
	for i in jumps:
		var best = null
		var bd := r
		for o in h.game.enemies_near(at, r):
			if done.has(o) or not _monster(o):
				continue
			var d: float = o.global_position.distance_to(at)
			if d < bd:
				bd = d
				best = o
		if best == null:
			break
		done[best] = true
		_deal(h, best, amount, "storm")
		at = best.global_position
		pts.append(at + Vector3(0, 1.2, 0))
	if pts.size() > 1:
		h.fx("run", "chain", {"ps": pts})

## A plain arrow glancing on from `e` to the next foes.
static func _ricochet(h: Hero, e, bounces: int, amount: float, r: float) -> void:
	var at: Vector3 = e.global_position
	var done := {e: true}
	var pts := PackedVector3Array([at + Vector3(0, 1.3, 0)])
	for i in bounces:
		var best = null
		var bd := r
		for o in h.game.enemies_near(at, r):
			if done.has(o) or not _monster(o):
				continue
			var d: float = o.global_position.distance_to(at)
			if d < bd:
				bd = d
				best = o
		if best == null:
			break
		done[best] = true
		_deal(h, best, amount, "phys")
		at = best.global_position
		pts.append(at + Vector3(0, 1.3, 0))
	if pts.size() > 1:
		h.fx("run", "ricochet", {"ps": pts})

## A bolt from the sky onto `at`.
static func _bolt(h: Hero, at: Vector3, amount: float, r: float) -> void:
	h.fx("run", "bolt", {"p": at, "r": r})
	_area(h, at, r, amount, "storm")

## Pass the strongest of this hero's poison on `e` to the `n` nearest others.
static func _spread_poison(h: Hero, e, n: int, r: float) -> void:
	if h.pd == null:
		return
	var near := []
	for o in h.game.enemies_near(e.global_position, r):
		if o != e and _monster(o):
			near.append(o)
	near.sort_custom(func(a, b): return a.global_position.distance_to(e.global_position) < b.global_position.distance_to(e.global_position))
	var pts := PackedVector3Array([e.global_position + Vector3(0, 1.0, 0)])
	for i in mini(n, near.size()):
		h.pd._poison(near[i], "toxic", 3.5)
		pts.append(near[i].global_position + Vector3(0, 1.0, 0))
	if pts.size() > 1:
		h.fx("run", "spread", {"ps": pts})

# ---------------------------------------------------------------- consumables

## What a camp chest gives each player besides the upgrade: the consumables (Data.BASES), weight by tier [1, 2, 3, boss].
const CONSUMABLES := {
	"hp_potion": [40, 30, 22, 14], "mp_potion": [14, 12, 10, 8], "elixir_fury": [8, 10, 12, 14], "draught_iron": [8, 10, 12, 12],
	"tonic_swift": [8, 8, 8, 8], "salve_troll": [6, 8, 10, 12], "elixir_wrath": [2, 5, 8, 12], "flask_fire": [8, 10, 12, 12],
	"flask_frost": [6, 8, 10, 12], "flask_storm": [4, 6, 8, 12], "scroll_ward": [4, 6, 8, 10], "tome_insight": [2, 4, 6, 10],
}
## How many a chest holds for each player, by tier.
const CONSUMABLE_COUNT := {1: [1, 1], 2: [1, 2], 3: [2, 2], 4: [2, 3]}

static func roll_consumables(tier: int, rng: RandomNumberGenerator) -> Array:
	tier = clampi(tier, 1, 4)
	var span: Array = CONSUMABLE_COUNT[tier]
	var n := rng.randi_range(int(span[0]), int(span[1]))
	var out := []
	for i in n:
		var total := 0.0
		for k in CONSUMABLES:
			total += float(CONSUMABLES[k][tier - 1])
		var x := rng.randf() * total
		for k in CONSUMABLES:
			x -= float(CONSUMABLES[k][tier - 1])
			if x <= 0.0:
				out.append(k)
				break
	return out

## A flask thrown at the pointer (Hero.drink): every peer sees it fly and burst ("toss"); its blow is this game's.
static func throw_flask(h: Hero, base: String, at: Vector3) -> void:
	var b: Dictionary = Data.BASES[base]
	var to := at - h.global_position
	to.y = 0
	to = to.limit_length(13.0)
	var land := h.global_position + to
	land.y = h.game.world.height_at(land.x, land.z)
	var r := float(b["bomb_r"])
	var kind := int(b["bomb"])
	h.fx("run", "toss", {"p": h.global_position + Vector3(0, 1.6, 0), "q": land, "n": kind, "r": r})
	if h.puppet:
		return
	var amount := _weapon(h) * float(b["bomb_pct"]) / 100.0
	h.get_tree().create_timer(TOSS_T).timeout.connect(func():
		if not is_instance_valid(h) or h.game == null or h.game.world == null:
			return
		for e in h.game.enemies_near(land, r):
			if e.dead:
				continue
			_deal(h, e, amount * (1.0 if _monster(e) else 0.5), ["fire", "frost", "storm"][kind])
			if e.dead:
				continue
			match kind:
				0: e.ignite(amount * 0.2, 3.0)
				1:
					if _monster(e):
						_freeze(h, e, 2.0)
					else:
						e.chill(0.4, 2.0)
	)

const TOSS_T := 0.55

# ---------------------------------------------------------------- what is seen (every peer: "run" fx events)

const FLARE := [Color(1.0, 0.5, 0.15), Color(0.6, 1.0, 0.3)]

static func play_fx(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var p: Vector3 = ev.get("p", h.global_position)
	var r: float = float(ev.get("r", 3.0))
	match str(ev.get("e", "")):
		"flare":
			var col: Color = FLARE[clampi(int(ev.get("n", 0)), 0, 1)]
			Fx.burst(root, p + Vector3(0, 0.8, 0), col, 28, r * 1.6, 0.18, 0.55, true, 1.5)
			Fx.ring(root, p, r, col, 0.45)
			Fx.flash(root, p + Vector3(0, 1.0, 0), col, 3.0, 0.3, r * 2.0)
			Sfx.play_at("thunder_blast", p, -9.0, 1.5)
		"shards":
			Fx.burst(root, p + Vector3(0, 1.0, 0), Color(0.75, 0.92, 1.0), 26, r * 1.8, 0.12, 0.6, true, -8.0)
			Fx.ring(root, p, r, Color(0.6, 0.88, 1.0), 0.4)
			Sfx.play_at("ice_burst", p, -6.0, randf_range(0.9, 1.15))
		"cloud":
			PlagueSmoke.puffs(root, p + Vector3(0, 0.4, 0), PlagueSmoke.FOG, Color(0.45, 0.9, 0.3, 0.8), 10, r * 0.9, 1.6, 1.2, r * 0.4, 0.4, 80.0, Vector3.UP, true)
			Fx.ring(root, p, r, Color(0.5, 1.0, 0.3), 0.6)
			Sfx.play_at("ice_shatter", p, -10.0, 0.6)
		"freeze":
			Fx.burst(root, p + Vector3(0, 1.0, 0), Color(0.82, 0.95, 1.0), 30, 1.5, 0.15, 1.0, true, -1.0)
			Fx.ring(root, p, r, Color(0.7, 0.92, 1.0), float(ev.get("x", 1.5)))
			Sfx.play_at("ice_shatter", p, -4.0, 0.8)
		"chain", "ricochet", "spread":
			var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
			var col := Color(0.75, 0.8, 1.0)
			if ev["e"] == "ricochet":
				col = Color(1.0, 0.92, 0.7)
			elif ev["e"] == "spread":
				col = Color(0.5, 1.0, 0.3)
			if ev["e"] == "chain":
				# the Arc skill's own lightning (the Blender bolts, the strike on each foe), leaping in turn
				ArcFx.chain(h, root, ps, Vector3.ZERO, ArcFx.STORM, 1.25)
				Sfx.play_at("arc_zap", ps[0], -5.0)
			else:
				for i in ps.size() - 1:
					Fx.bolt(root, ps[i], ps[i + 1], col, 0.18)
					Fx.burst(root, ps[i + 1], col, 8, 2.0, 0.08, 0.3, true, -3.0)
		"bolt":
			ArcFx.bolt(root, p + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), p + Vector3(0, 0.2, 0), 0.3, 1.4, ArcFx.STORM, h.game)
			Fx.ring(root, p, r, Color(0.7, 0.75, 1.0), 0.35)
			Fx.flash(root, p + Vector3(0, 2.0, 0), Color(0.7, 0.75, 1.0), 4.0, 0.2, 8.0)
			Sfx.play_at("arc_hit", p, -4.0)
		"undying":
			var col2 := Color(1.0, 0.55, 0.15) if int(ev.get("n", 0)) == 1 else Color(1.0, 0.9, 0.55)
			Fx.burst(root, p + Vector3(0, 1.0, 0), col2, 40, 4.0, 0.2, 0.8, true, 2.0)
			Fx.ring(root, p, 5.0, col2, 0.7)
			Fx.pillar(root, p, col2, 1.0)
			Sfx.play("relic_ting", -2.0)
		"echo":
			Fx.ring(root, p, 1.4, Color(0.55, 0.85, 1.0), 0.35, 0.1)
		"gem":
			Fx.pillar(root, p, Color(0.9, 0.95, 1.0), 1.2)
		"toss":
			_toss_fx(h, root, p, ev.get("q", p), r, int(ev.get("n", 0)))

## The flask's flight: a glowing bottle on an arc, trailing its colour, bursting where it lands.
static func _toss_fx(h: Hero, root: Node3D, from: Vector3, to: Vector3, r: float, kind: int) -> void:
	var col: Color = [Color(1.0, 0.45, 0.1), Color(0.55, 0.85, 1.0), Color(0.6, 0.65, 1.0)][clampi(kind, 0, 2)]
	var n := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.13
	m.height = 0.3
	n.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col.lightened(0.3)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	n.material_override = mat
	root.add_child(n)
	n.global_position = from
	Fx.aura(n, col, 18, 0.3, 0.06, 0.4, 0.0, 0.05)
	Sfx.play_at("swing_light", from, -6.0, 0.8)
	var tw := n.create_tween()
	tw.tween_method(func(k: float):
		if is_instance_valid(n):
			n.global_position = from.lerp(to, k) + Vector3(0, sin(k * PI) * 3.0, 0), 0.0, 1.0, TOSS_T)
	tw.tween_callback(func():
		if is_instance_valid(h) and h.game != null and h.game.world != null:
			_bomb_fx(h, root, to, r, kind)
		n.queue_free())

static func _bomb_fx(h: Hero, root: Node3D, p: Vector3, r: float, kind: int) -> void:
	Sfx.play_at("flask_shatter", p, -2.0)
	match kind:
		0:
			ArrowFx.finish(h, "fire", p + Vector3(0, 0.5, 0), Vector3.FORWARD, false)
			Fx.ring(root, p, r, Color(1.0, 0.5, 0.15), 0.5)
		1:
			Fx.burst(root, p + Vector3(0, 0.6, 0), Color(0.8, 0.95, 1.0), 40, r * 1.5, 0.14, 0.7, true, -6.0)
			Fx.ring(root, p, r, Color(0.65, 0.9, 1.0), 0.7)
			Sfx.play_at("ice_shatter", p, -2.0, 0.8)
		2:
			for i in 3:
				ArcFx.bolt(root, p + Vector3(randf_range(-2, 2), 12.0, randf_range(-2, 2)), p + Vector3(randf_range(-r, r) * 0.5, 0.2, randf_range(-r, r) * 0.5), 0.3, 1.2, ArcFx.STORM, h.game)
			Fx.ring(root, p, r, Color(0.7, 0.75, 1.0), 0.4)
			Sfx.play_at("arc_hit", p, -3.0)

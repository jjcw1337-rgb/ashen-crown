class_name Rites
extends RefCounted
## The rites a run offers beside a class's talent trees (RunBuild.passive_pool adds those): every class's own and the
## generic ones, Common, Uncommon or Rare (Blaine's character structure, 2026-11-06: the rares are the run-changers;
## the fourth colour is the gems' legendary tier, never a rite's).
##
## A rite is data: {id, cls ("any", a class, or "serpent,wyvern"), theme (RunTalents.THEMES), rarity 0-2, max
## (stacks), name, text, fx (stats summed into Hero.tfx like a talent's), proc (a handler in RiteProcs) and k (its
## numbers, multiplied by the stacks where `per` says)}. A gem (Gems) has the same shape.

## Laid over by the Hero Codex (data/codex/: a class's in its hero file, "any" in shared.json) when this script loads.
static func _static_init() -> void:
	var entries: Array = Codex.shared().get("rites", []).duplicate()
	for cls in RunTalents.THEMES:
		entries.append_array(Codex.hero(cls).get("rites", []))
	for cls in ["serpent", "wyvern"]:
		entries.append_array(Codex.hero(cls).get("rites", []))
	Codex.apply_rites(TALENTS, entries)

## `per` names the k values that grow with each stack. Texts read {key} from k (times stacks) and fx.
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

static func talents_for(cls: String) -> Array:
	return TALENTS.filter(func(t): return t["cls"] == "any" or t["cls"] == cls or (str(t["cls"]).contains(",") and str(t["cls"]).split(",").has(cls)))

## A rite's (or gem's) k at `stacks`: the numbers in `per` grow with each stack.
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

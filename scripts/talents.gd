class_name Talents
extends RefCounted
## Talent trees: three per class, four rows each. A character gets a talent point every level from
## level 2 (level - 1 in all; `Hero.free_talent_points`) and spends them in the talents window (N).
## A row opens once that many points are spent in the rows above it in the same tree (`ROW_REQ`);
## the last row is one capstone. Points come back free with Reset.
##
## Each talent's "fx" is what one rank gives; ranks add up (`sum`) into `Hero.tfx`, read with
## `Hero.talent(key)`. The keys:
##   flat, added to the character's stats in `Hero.recalc`: str dex vit ene res ls regen ias frw block mf
##   percent: dmg (all damage), dmg:<skill> (one skill, "attack" = the weapon attack, "summon" = the
##     demons' claws), cd:<skill> (shorter cooldown), cost:<skill> (less mana), life_pct, mana_pct,
##     armor_pct, crit (chance), crit_dmg, buff_pow (the 12 s buffs' +40% damage), block_dr
##   seconds: buff_dur (the 12 s buffs), phase_dur, wail_stun, shackle_dur, blight_dur
##   class specials, used where the skill is: nova_heal, cry_heal, charge_cdr, reap_heal, reap_full,
##     wail_echo, spirits, claw_wide, minion_speed, minion_max, pact_cost, phase_heal, drain_heal,
##     drain_fork, drain_glut, blight_size, blight_twin, shackle_range, arrow_split, snare_dur, snare_max,
##     snare_wide, volley_size, beast_two, burn_dmg, wolf_burn, chill_pct, wolf_howl, frost_shatter, arc_count
## "text" shows the total for the ranks taken: {key} is replaced by the fx value times the rank.
## Saves made before talents get a build picked for them (`auto_build`, the class's `AUTO` order).

const ROW_REQ := [0, 3, 6, 10]

const TREES := {
	"knight": [
		{"name": "Crusader", "desc": "Holy fire and the sword: Holy Slam and Holy Nova.", "talents": [
			{"id": "k_zeal", "name": "Zeal", "row": 0, "max": 3, "icon": "t_sword", "fx": {"dmg": 4}, "text": "+{dmg}% damage."},
			{"id": "k_heavy", "name": "Heavy Hand", "row": 0, "max": 3, "icon": "cleave", "fx": {"dmg:cleave": 10}, "text": "Holy Slam deals {dmg:cleave}% more damage."},
			{"id": "k_radiance", "name": "Radiance", "row": 1, "max": 3, "icon": "nova", "fx": {"dmg:nova": 12}, "text": "Holy Nova burns {dmg:nova}% hotter."},
			{"id": "k_fervor", "name": "Fervor", "row": 1, "max": 3, "icon": "t_haste", "fx": {"ias": 5}, "text": "+{ias}% attack speed."},
			{"id": "k_steel", "name": "Sanctified Steel", "row": 2, "max": 3, "icon": "t_star", "fx": {"crit": 3}, "text": "+{crit}% chance to land a critical hit."},
			{"id": "k_purify", "name": "Purifying Fire", "row": 2, "max": 2, "icon": "t_hourglass", "fx": {"cost:nova": 15, "cd:nova": 10}, "text": "Holy Nova costs {cost:nova}% less mana and recharges {cd:nova}% faster."},
			{"id": "k_consecrate", "name": "Consecration", "row": 3, "max": 1, "icon": "t_heart", "fx": {"nova_heal": 3}, "text": "Holy Nova heals you {nova_heal}% of your life for every enemy it burns (up to 5)."},
		]},
		{"name": "Bulwark", "desc": "Plate and shield: harder to hurt, harder to kill.", "talents": [
			{"id": "k_tough", "name": "Toughness", "row": 0, "max": 3, "icon": "t_armor", "fx": {"armor_pct": 6}, "text": "+{armor_pct}% defense."},
			{"id": "k_vigor", "name": "Vigor", "row": 0, "max": 3, "icon": "t_heart", "fx": {"life_pct": 4}, "text": "+{life_pct}% maximum life."},
			{"id": "k_wall", "name": "Shield Wall", "row": 1, "max": 3, "icon": "block", "fx": {"block": 4}, "text": "+{block}% chance to block with a shield."},
			{"id": "k_resolve", "name": "Resolve", "row": 1, "max": 3, "icon": "t_ward", "fx": {"res": 5}, "text": "+{res}% to all resistances."},
			{"id": "k_guard", "name": "Iron Guard", "row": 2, "max": 3, "icon": "block", "fx": {"block_dr": 3}, "text": "Block stops {block_dr}% more damage from the front."},
			{"id": "k_wind", "name": "Second Wind", "row": 2, "max": 2, "icon": "t_regen", "fx": {"regen": 1.5}, "text": "+{regen} life regenerated per second."},
			{"id": "k_unbroken", "name": "Unbreakable", "row": 3, "max": 1, "icon": "cry", "fx": {"cry_heal": 25, "buff_dur": 4}, "text": "Battle Cry heals {cry_heal}% of your life and lasts {buff_dur} seconds longer."},
		]},
		{"name": "Vanguard", "desc": "First into the fight: Charge, Battle Cry and the sword combo.", "talents": [
			{"id": "k_momentum", "name": "Momentum", "row": 0, "max": 3, "icon": "t_boot", "fx": {"frw": 5}, "text": "+{frw}% run speed."},
			{"id": "k_might", "name": "Might", "row": 0, "max": 3, "icon": "t_fist", "fx": {"str": 3}, "text": "+{str} strength."},
			{"id": "k_ram", "name": "Battering Ram", "row": 1, "max": 3, "icon": "charge", "fx": {"dmg:charge": 15, "cd:charge": 10}, "text": "Charge hits {dmg:charge}% harder and recharges {cd:charge}% faster."},
			{"id": "k_sword", "name": "Swordplay", "row": 1, "max": 3, "icon": "attack", "fx": {"dmg:attack": 8}, "text": "Your weapon attack deals {dmg:attack}% more damage."},
			{"id": "k_command", "name": "Commander", "row": 2, "max": 3, "icon": "cry", "fx": {"buff_pow": 10}, "text": "Battle Cry's damage bonus is {buff_pow}% higher."},
			{"id": "k_rally", "name": "Rally", "row": 2, "max": 2, "icon": "t_hourglass", "fx": {"cd:cry": 15}, "text": "Battle Cry recharges {cd:cry}% faster."},
			{"id": "k_relentless", "name": "Relentless", "row": 3, "max": 1, "icon": "charge", "fx": {"charge_cdr": 1}, "text": "Every enemy Charge smashes through takes {charge_cdr} second off your other cooldowns."},
		]},
	],
	"wraith": [
		{"name": "Reaper", "desc": "The scythe: Soul Reap, quick strikes and cruel crits.", "talents": [
			{"id": "w_scythe", "name": "Keen Scythe", "row": 0, "max": 3, "icon": "reap", "fx": {"dmg:reap": 10}, "text": "Soul Reap deals {dmg:reap}% more damage."},
			{"id": "w_focus", "name": "Grim Focus", "row": 0, "max": 3, "icon": "t_eye", "fx": {"dex": 3}, "text": "+{dex} dexterity."},
			{"id": "w_harvest", "name": "Soul Harvest", "row": 1, "max": 3, "icon": "t_heart", "fx": {"reap_heal": 1}, "text": "Each soul Soul Reap cuts heals {reap_heal}% more of your life."},
			{"id": "w_haste", "name": "Deathly Haste", "row": 1, "max": 3, "icon": "t_haste", "fx": {"ias": 5}, "text": "+{ias}% attack speed."},
			{"id": "w_cruel", "name": "Cruelty", "row": 2, "max": 3, "icon": "t_star", "fx": {"crit": 3}, "text": "+{crit}% chance to land a critical hit."},
			{"id": "w_exec", "name": "Executioner", "row": 2, "max": 2, "icon": "t_skull", "fx": {"crit_dmg": 20}, "text": "Critical hits deal {crit_dmg}% more damage."},
			{"id": "w_moon", "name": "Harvest Moon", "row": 3, "max": 1, "icon": "reap", "fx": {"reap_full": 1}, "text": "Soul Reap sweeps all the way round you."},
		]},
		{"name": "Banshee", "desc": "The scream and the shadow: Banshee Wail and Shadow Step.", "talents": [
			{"id": "w_scream", "name": "Piercing Scream", "row": 0, "max": 3, "icon": "wail", "fx": {"dmg:wail": 12}, "text": "Banshee Wail deals {dmg:wail}% more damage."},
			{"id": "w_mind", "name": "Ethereal Mind", "row": 0, "max": 3, "icon": "t_drop", "fx": {"mana_pct": 5}, "text": "+{mana_pct}% maximum mana."},
			{"id": "w_dread", "name": "Dread", "row": 1, "max": 3, "icon": "wail", "fx": {"wail_stun": 0.3}, "text": "Banshee Wail's terror lasts {wail_stun} seconds longer."},
			{"id": "w_slip", "name": "Slipstream", "row": 1, "max": 3, "icon": "shade", "fx": {"cd:shade": 10, "dmg:shade": 10}, "text": "Shadow Step recharges {cd:shade}% faster and strikes {dmg:shade}% harder."},
			{"id": "w_hollow", "name": "Hollow Voice", "row": 2, "max": 3, "icon": "t_drop", "fx": {"cost:wail": 15, "cd:wail": 8}, "text": "Banshee Wail costs {cost:wail}% less mana and recharges {cd:wail}% faster."},
			{"id": "w_form", "name": "Spirit Form", "row": 2, "max": 2, "icon": "t_ward", "fx": {"res": 6}, "text": "+{res}% to all resistances."},
			{"id": "w_echo", "name": "Echo", "row": 3, "max": 1, "icon": "wail", "fx": {"wail_echo": 50}, "text": "Banshee Wail screams again a moment later for {wail_echo}% of the damage."},
		]},
		{"name": "Revenant", "desc": "What will not stay dead: Spectral Host and a body hard to harm.", "talents": [
			{"id": "w_unlife", "name": "Unlife", "row": 0, "max": 3, "icon": "t_heart", "fx": {"life_pct": 4}, "text": "+{life_pct}% maximum life."},
			{"id": "w_chill", "name": "Grave Chill", "row": 0, "max": 3, "icon": "t_armor", "fx": {"armor_pct": 6}, "text": "+{armor_pct}% defense."},
			{"id": "w_legion", "name": "Legion", "row": 1, "max": 3, "icon": "host", "fx": {"dmg:host": 15}, "text": "Spectral Host's spirits strike {dmg:host}% harder."},
			{"id": "w_ward", "name": "Spectral Ward", "row": 1, "max": 3, "icon": "t_ward", "fx": {"res": 5}, "text": "+{res}% to all resistances."},
			{"id": "w_eternal", "name": "Eternal Host", "row": 2, "max": 2, "icon": "t_hourglass", "fx": {"buff_dur": 2}, "text": "Spectral Host lasts {buff_dur} seconds longer."},
			{"id": "w_siphon", "name": "Soul Siphon", "row": 2, "max": 3, "icon": "t_fang", "fx": {"ls": 1}, "text": "+{ls}% of the damage you deal comes back as life."},
			{"id": "w_rider", "name": "Fourth Rider", "row": 3, "max": 1, "icon": "host", "fx": {"spirits": 1}, "text": "Spectral Host calls {spirits} more spirit."},
		]},
	],
	"demon": [
		{"name": "Hellfire", "desc": "Burning claws: Hellfire Claw and raw fury.", "talents": [
			{"id": "d_sear", "name": "Searing Claws", "row": 0, "max": 3, "icon": "hellclaw", "fx": {"dmg:hellclaw": 10}, "text": "Hellfire Claw deals {dmg:hellclaw}% more damage."},
			{"id": "d_brim", "name": "Brimstone", "row": 0, "max": 3, "icon": "t_fist", "fx": {"str": 3}, "text": "+{str} strength."},
			{"id": "d_kindle", "name": "Kindling", "row": 1, "max": 3, "icon": "t_sword", "fx": {"dmg": 4}, "text": "+{dmg}% damage."},
			{"id": "d_frenzy", "name": "Frenzy", "row": 1, "max": 3, "icon": "t_haste", "fx": {"ias": 5}, "text": "+{ias}% attack speed."},
			{"id": "d_edge", "name": "Infernal Edge", "row": 2, "max": 3, "icon": "t_star", "fx": {"crit": 3}, "text": "+{crit}% chance to land a critical hit."},
			{"id": "d_cinder", "name": "Cinder Heart", "row": 2, "max": 2, "icon": "t_skull", "fx": {"crit_dmg": 20}, "text": "Critical hits deal {crit_dmg}% more damage."},
			{"id": "d_inferno", "name": "Inferno", "row": 3, "max": 1, "icon": "hellclaw", "fx": {"claw_wide": 1}, "text": "Hellfire Claw rakes a metre further and much wider."},
		]},
		{"name": "Summoner", "desc": "Your demons: more of them, fiercer, and the Blood Pact.", "talents": [
			{"id": "d_bargain", "name": "Dark Bargain", "row": 0, "max": 3, "icon": "summon", "fx": {"cost:summon": 15}, "text": "Summon Demon costs {cost:summon}% less mana."},
			{"id": "d_ferocity", "name": "Ferocity", "row": 0, "max": 3, "icon": "summon", "fx": {"dmg:summon": 15}, "text": "Your demons deal {dmg:summon}% more damage."},
			{"id": "d_hellsworn", "name": "Hellsworn", "row": 1, "max": 3, "icon": "t_heart", "fx": {"life_pct": 4}, "text": "+{life_pct}% maximum life."},
			{"id": "d_pack", "name": "Pack Master", "row": 1, "max": 3, "icon": "t_boot", "fx": {"minion_speed": 8}, "text": "Your demons move and claw {minion_speed}% faster."},
			{"id": "d_tithe", "name": "Blood Tithe", "row": 2, "max": 2, "icon": "pact", "fx": {"pact_cost": 4}, "text": "Blood Pact costs {pact_cost}% less of your life."},
			{"id": "d_oath", "name": "Pact Master", "row": 2, "max": 3, "icon": "pact", "fx": {"buff_pow": 10}, "text": "Blood Pact's damage bonus is {buff_pow}% higher."},
			{"id": "d_legion", "name": "Legion of Hell", "row": 3, "max": 1, "icon": "summon", "fx": {"minion_max": 1}, "text": "{minion_max} more demon can fight beside you (4 at once)."},
		]},
		{"name": "Underworld", "desc": "The other side: Underworld Phase and obsidian hide.", "talents": [
			{"id": "d_plate", "name": "Obsidian Plate", "row": 0, "max": 3, "icon": "t_armor", "fx": {"armor_pct": 6}, "text": "+{armor_pct}% defense."},
			{"id": "d_hide", "name": "Demon Hide", "row": 0, "max": 3, "icon": "t_heart", "fx": {"life_pct": 4}, "text": "+{life_pct}% maximum life."},
			{"id": "d_rift", "name": "Rift Walker", "row": 1, "max": 3, "icon": "phase", "fx": {"phase_dur": 1}, "text": "Underworld Phase lasts {phase_dur} seconds longer."},
			{"id": "d_abyss", "name": "Abyssal Ward", "row": 1, "max": 3, "icon": "t_ward", "fx": {"res": 5}, "text": "+{res}% to all resistances."},
			{"id": "d_erupt", "name": "Eruption", "row": 2, "max": 2, "icon": "phase", "fx": {"dmg:phase": 25, "cd:phase": 10}, "text": "The rift erupts {dmg:phase}% harder; Underworld Phase recharges {cd:phase}% faster."},
			{"id": "d_hunger", "name": "Hungering Dark", "row": 2, "max": 3, "icon": "t_fang", "fx": {"ls": 1}, "text": "+{ls}% of the damage you deal comes back as life."},
			{"id": "d_furnace", "name": "Soul Furnace", "row": 3, "max": 1, "icon": "t_heart", "fx": {"phase_heal": 30}, "text": "Coming back from the Underworld heals you {phase_heal}% of your life."},
		]},
	],
	"warlock": [
		{"name": "Affliction", "desc": "The beam: Drain Life, longer, wider and hungrier.", "talents": [
			{"id": "l_deep", "name": "Deep Drain", "row": 0, "max": 3, "icon": "drain", "fx": {"dmg:drain": 10}, "text": "Drain Life deals {dmg:drain}% more damage."},
			{"id": "l_thirst", "name": "Dark Thirst", "row": 0, "max": 3, "icon": "t_heart", "fx": {"drain_heal": 12}, "text": "Drain Life heals {drain_heal}% more."},
			{"id": "l_intel", "name": "Fel Intellect", "row": 1, "max": 3, "icon": "t_orb", "fx": {"ene": 3}, "text": "+{ene} energy."},
			{"id": "l_thrift", "name": "Siphon Efficiency", "row": 1, "max": 3, "icon": "t_drop", "fx": {"cost:drain": 15}, "text": "Drain Life costs {cost:drain}% less mana."},
			{"id": "l_fork", "name": "Forking Beam", "row": 2, "max": 2, "icon": "drain", "fx": {"drain_fork": 1}, "text": "Drain Life forks to {drain_fork} more enemy."},
			{"id": "l_wither", "name": "Withering", "row": 2, "max": 3, "icon": "t_sword", "fx": {"dmg": 4}, "text": "+{dmg}% damage."},
			{"id": "l_glut", "name": "Soul Glut", "row": 3, "max": 1, "icon": "t_drop", "fx": {"drain_glut": 50}, "text": "Life Drain Life pulls in past your full life fills {drain_glut}% as much mana."},
		]},
		{"name": "Plague", "desc": "Rot: Blight Bolt and its plague pools.", "talents": [
			{"id": "l_virulence", "name": "Virulence", "row": 0, "max": 3, "icon": "blight", "fx": {"dmg:blight": 10}, "text": "Blight Bolt and its pools deal {dmg:blight}% more damage."},
			{"id": "l_contagion", "name": "Contagion", "row": 0, "max": 3, "icon": "t_hourglass", "fx": {"blight_dur": 1}, "text": "Plague pools last {blight_dur} seconds longer."},
			{"id": "l_quick", "name": "Quickened Rot", "row": 1, "max": 3, "icon": "blight", "fx": {"cd:blight": 10}, "text": "Blight Bolt recharges {cd:blight}% faster."},
			{"id": "l_vigor", "name": "Fel Vigor", "row": 1, "max": 3, "icon": "t_heart", "fx": {"life_pct": 4}, "text": "+{life_pct}% maximum life."},
			{"id": "l_spread", "name": "Spreading Rot", "row": 2, "max": 2, "icon": "blight", "fx": {"blight_size": 15}, "text": "Blight bursts and pools are {blight_size}% wider."},
			{"id": "l_malice", "name": "Malice", "row": 2, "max": 3, "icon": "t_star", "fx": {"crit": 3}, "text": "+{crit}% chance to land a critical hit with your weapon and Soul Shackles."},
			{"id": "l_twin", "name": "Twin Skulls", "row": 3, "max": 1, "icon": "blight", "fx": {"blight_twin": 1}, "text": "Blight Bolt hurls two skulls."},
		]},
		{"name": "Binding", "desc": "The pact's chains: Soul Shackles, Fel Covenant and fel wards.", "talents": [
			{"id": "l_felarmor", "name": "Fel Armor", "row": 0, "max": 3, "icon": "t_armor", "fx": {"armor_pct": 6}, "text": "+{armor_pct}% defense."},
			{"id": "l_reserves", "name": "Arcane Reserves", "row": 0, "max": 3, "icon": "t_drop", "fx": {"mana_pct": 5}, "text": "+{mana_pct}% maximum mana."},
			{"id": "l_chains", "name": "Iron Chains", "row": 1, "max": 3, "icon": "shackles", "fx": {"dmg:shackles": 15, "shackle_dur": 0.3}, "text": "Soul Shackles deal {dmg:shackles}% more damage and bind {shackle_dur} seconds longer."},
			{"id": "l_sigils", "name": "Warding Sigils", "row": 1, "max": 3, "icon": "t_ward", "fx": {"res": 5}, "text": "+{res}% to all resistances."},
			{"id": "l_reach", "name": "Binding Reach", "row": 2, "max": 2, "icon": "shackles", "fx": {"shackle_range": 1.5}, "text": "Soul Shackles reach {shackle_range} metres further."},
			{"id": "l_dark", "name": "Dark Pact", "row": 2, "max": 3, "icon": "covenant", "fx": {"cd:covenant": 10, "buff_pow": 5}, "text": "Fel Covenant recharges {cd:covenant}% faster and its damage bonus is {buff_pow}% higher."},
			{"id": "l_eternal", "name": "Eternal Covenant", "row": 3, "max": 1, "icon": "covenant", "fx": {"buff_dur": 6}, "text": "Fel Covenant lasts {buff_dur} seconds longer."},
		]},
	],
	"archer": [
		{"name": "Flame", "desc": "Fire Arrow, burning wounds and the bow's weight; his wolf's fangs catch fire.", "talents": [
			{"id": "a_kindle", "name": "Kindling", "row": 0, "max": 3, "icon": "pierce", "fx": {"dmg:pierce": 12}, "text": "Fire Arrow deals {dmg:pierce}% more damage."},
			{"id": "a_draw", "name": "Heavy Draw", "row": 0, "max": 3, "icon": "attack", "fx": {"dmg:attack": 8}, "text": "Your bow shots deal {dmg:attack}% more damage."},
			{"id": "a_pyre", "name": "Pyre", "row": 1, "max": 3, "icon": "t_fist", "fx": {"burn_dmg": 20}, "text": "Burning from Fire Arrow lasts and hurts {burn_dmg}% more."},
			{"id": "a_nock", "name": "Quick Nock", "row": 1, "max": 3, "icon": "t_haste", "fx": {"ias": 5}, "text": "+{ias}% attack speed."},
			{"id": "a_embers", "name": "Ember Fangs", "row": 2, "max": 3, "icon": "beast", "fx": {"wolf_burn": 15}, "text": "Your wolf's bites set foes alight: {wolf_burn}% of each bite burns them every second for 3 seconds."},
			{"id": "a_dead", "name": "Deadeye", "row": 2, "max": 3, "icon": "t_star", "fx": {"crit": 3}, "text": "+{crit}% chance to land a critical hit."},
			{"id": "a_split", "name": "Split Arrow", "row": 3, "max": 1, "icon": "attack", "fx": {"arrow_split": 1}, "text": "Every bow shot flies as three arrows (the outer two at half damage)."},
		]},
		{"name": "Frost", "desc": "Frost Volley, the chill that slows them and the hide that keeps him alive; his wolf howls the cold.", "talents": [
			{"id": "a_eye", "name": "Keen Eye", "row": 0, "max": 3, "icon": "t_eye", "fx": {"dex": 3}, "text": "+{dex} dexterity."},
			{"id": "a_cover", "name": "Hailstorm", "row": 0, "max": 3, "icon": "volley", "fx": {"volley_size": 10}, "text": "Frost Volley covers {volley_size}% more ground."},
			{"id": "a_rime", "name": "Rime", "row": 1, "max": 3, "icon": "volley", "fx": {"chill_pct": 15}, "text": "Frost Volley's chill slows {chill_pct}% more."},
			{"id": "a_hide", "name": "Hide Armour", "row": 1, "max": 3, "icon": "t_armor", "fx": {"armor_pct": 6}, "text": "+{armor_pct}% defense."},
			{"id": "a_howl", "name": "Winter Howl", "row": 2, "max": 2, "icon": "beast", "fx": {"wolf_howl": 1}, "text": "Your wolf's pounce chills everything within 3.5 metres of where it lands."},
			{"id": "a_rain", "name": "Endless Rain", "row": 2, "max": 2, "icon": "t_hourglass", "fx": {"cd:volley": 12, "cost:volley": 10}, "text": "Frost Volley recharges {cd:volley}% faster and costs {cost:volley}% less mana."},
			{"id": "a_shatter", "name": "Shatter", "row": 3, "max": 1, "icon": "t_skull", "fx": {"frost_shatter": 1}, "text": "Chilled enemies take 20% more damage from your arrows."},
		]},
		{"name": "Storm", "desc": "Storm Snare, forked lightning and the bond with his wolf.", "talents": [
			{"id": "a_vigor", "name": "Hunter's Vigor", "row": 0, "max": 3, "icon": "t_heart", "fx": {"life_pct": 4}, "text": "+{life_pct}% maximum life."},
			{"id": "a_jaws", "name": "Thunder Jaws", "row": 0, "max": 3, "icon": "snare", "fx": {"dmg:snare": 15, "snare_dur": 0.5}, "text": "Storm Snare deals {dmg:snare}% more damage and holds {snare_dur} seconds longer."},
			{"id": "a_arc", "name": "Forked Lightning", "row": 1, "max": 3, "icon": "snare", "fx": {"arc_count": 1}, "text": "Storm Snare's lightning leaps to {arc_count} more enemies."},
			{"id": "a_bond", "name": "Spirit Bond", "row": 1, "max": 3, "icon": "beast", "fx": {"dmg:beast": 15}, "text": "Your wolf hits {dmg:beast}% harder."},
			{"id": "a_trapper", "name": "Trapper", "row": 2, "max": 2, "icon": "snare", "fx": {"snare_max": 1}, "text": "Set {snare_max} more Storm Snare at once."},
			{"id": "a_pack", "name": "Pack Hunter", "row": 2, "max": 3, "icon": "beast", "fx": {"buff_pow": 10}, "text": "The hunt your commands rouse is {buff_pow}% stronger."},
			{"id": "a_alpha", "name": "Alpha", "row": 3, "max": 1, "icon": "beast", "fx": {"beast_two": 1}, "text": "A second wolf runs with you."},
		]},
	],
}

## The build an old save gets (and the window's Auto button follows): talents in order, each taken to
## its maximum while points last and its row is open.
const AUTO := {
	"knight": ["k_zeal", "k_heavy", "k_radiance", "k_fervor", "k_steel", "k_purify", "k_consecrate", "k_vigor", "k_tough", "k_resolve", "k_wall", "k_guard", "k_wind", "k_unbroken",
		"k_might", "k_momentum", "k_ram", "k_sword", "k_command", "k_rally", "k_relentless"],
	"wraith": ["w_scythe", "w_focus", "w_harvest", "w_haste", "w_cruel", "w_exec", "w_moon", "w_unlife", "w_chill", "w_legion", "w_ward", "w_eternal", "w_siphon", "w_rider",
		"w_scream", "w_mind", "w_dread", "w_slip", "w_hollow", "w_form", "w_echo"],
	"demon": ["d_ferocity", "d_bargain", "d_pack", "d_hellsworn", "d_oath", "d_tithe", "d_legion", "d_sear", "d_brim", "d_kindle", "d_frenzy", "d_edge", "d_cinder", "d_inferno",
		"d_hide", "d_plate", "d_rift", "d_abyss", "d_erupt", "d_hunger", "d_furnace"],
	"warlock": ["l_deep", "l_thirst", "l_thrift", "l_intel", "l_fork", "l_wither", "l_glut", "l_virulence", "l_contagion", "l_quick", "l_vigor", "l_spread", "l_malice", "l_twin",
		"l_felarmor", "l_reserves", "l_chains", "l_sigils", "l_reach", "l_dark", "l_eternal"],
	"archer": ["a_kindle", "a_draw", "a_pyre", "a_nock", "a_embers", "a_dead", "a_split", "a_eye", "a_cover", "a_rime", "a_hide", "a_howl", "a_rain",
		"a_shatter", "a_vigor", "a_jaws", "a_arc", "a_bond", "a_trapper", "a_pack", "a_alpha"],
}

static func trees(cls: String) -> Array:
	return TREES.get(cls, [])

## The talent's definition and which tree it is in: {"t": talent, "tree": index}, or {} if unknown.
static func find(cls: String, id: String) -> Dictionary:
	var ts := trees(cls)
	for i in ts.size():
		for t in ts[i]["talents"]:
			if t["id"] == id:
				return {"t": t, "tree": i}
	return {}

static func spent(taken: Dictionary) -> int:
	var n := 0
	for k in taken:
		n += int(taken[k])
	return n

static func tree_spent(cls: String, tree: int, taken: Dictionary, below_row := 99) -> int:
	var n := 0
	for t in trees(cls)[tree]["talents"]:
		if int(t["row"]) < below_row:
			n += int(taken.get(t["id"], 0))
	return n

## Is this row of the tree open with these talents taken?
static func row_open(cls: String, tree: int, row: int, taken: Dictionary) -> bool:
	return tree_spent(cls, tree, taken, row) >= int(ROW_REQ[row])

## Can one more rank of the talent be taken, given free points?
static func can_learn(cls: String, id: String, taken: Dictionary, free: int) -> bool:
	var f := find(cls, id)
	if f.is_empty() or free <= 0:
		return false
	var t: Dictionary = f["t"]
	return int(taken.get(id, 0)) < int(t["max"]) and row_open(cls, f["tree"], int(t["row"]), taken)

## Can a rank be given back without leaving a talent further down without the points its row needs?
static func can_unlearn(cls: String, id: String, taken: Dictionary) -> bool:
	if int(taken.get(id, 0)) <= 0:
		return false
	var f := find(cls, id)
	if f.is_empty():
		return false
	var after := taken.duplicate()
	after[id] = int(after[id]) - 1
	return valid_tree(cls, f["tree"], after)

static func valid_tree(cls: String, tree: int, taken: Dictionary) -> bool:
	for t in trees(cls)[tree]["talents"]:
		if int(taken.get(t["id"], 0)) > 0 and not row_open(cls, tree, int(t["row"]), taken):
			return false
	return true

## Talents taken that this class has, ranks capped, rows checked (a bad or foreign save loses them).
static func clean(cls: String, taken: Dictionary) -> Dictionary:
	var out := {}
	for k in taken:
		var f := find(cls, str(k))
		if not f.is_empty() and int(taken[k]) > 0:
			out[str(k)] = mini(int(taken[k]), int(f["t"]["max"]))
	for i in trees(cls).size():
		if not valid_tree(cls, i, out):
			return {}
	return out

## Spend points along the class's AUTO order on top of what is taken.
static func auto_build(cls: String, points: int, taken := {}) -> Dictionary:
	var out := taken.duplicate()
	var order: Array = AUTO.get(cls, [])
	var progress := true
	while points > 0 and progress:
		progress = false
		for id in order:
			while points > 0 and can_learn(cls, id, out, points):
				out[id] = int(out.get(id, 0)) + 1
				points -= 1
				progress = true
	return out

## Everything the talents taken add up to: {fx key: total}.
static func sum(cls: String, taken: Dictionary) -> Dictionary:
	var out := {}
	for id in taken:
		var f := find(cls, id)
		if f.is_empty():
			continue
		var fx: Dictionary = f["t"]["fx"]
		for k in fx:
			out[k] = float(out.get(k, 0.0)) + float(fx[k]) * int(taken[id])
	return out

## The talent's text for a number of ranks (at least one, so an untaken talent shows its first rank).
static func describe(t: Dictionary, ranks: int) -> String:
	var s: String = t["text"]
	var fx: Dictionary = t["fx"]
	for k in fx:
		var v: float = float(fx[k]) * maxi(ranks, 1)
		s = s.replace("{" + k + "}", str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v)
	return s

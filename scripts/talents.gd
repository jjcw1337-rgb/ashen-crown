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
##   percent: dmg (all damage), dmg:<skill> (one skill, "attack" = the weapon attack), cd:<skill> (shorter
##     cooldown), cost:<skill> (less mana), life_pct, mana_pct,
##     armor_pct, crit (chance), crit_dmg, buff_pow (the 12 s buffs' +40% damage), block_dr
##   seconds: buff_dur (the 12 s buffs), siphon_dur, step_stun, veil, grasp_hold, shackle_dur, blight_dur,
##     trail_dur (the Demon's lava on the ground), wrath_dur
##   class specials, used where the skill is: nova_heal, cry_heal, charge_cdr, rend_heal, rend_full,
##     phantoms, fists_wide, hurl_twin, wrath_double, drain_heal,
##     drain_fork, drain_glut, blight_size, blight_twin, shackle_range, arrow_split, snare_dur, snare_max,
##     snare_wide, volley_size, beast_two, burn_dmg, wolf_burn, chill_pct, wolf_howl, frost_shatter, arc_count,
##     plague: cloud_size cloud_dur poison_dmg poison_dur blast_size ignite_dmg trap_max trap_stun inf_jumps inf_dur dome_size dome_dur
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
		{"name": "Render", "desc": "The claws: Spectral Rend, quick strikes and cruel crits.", "talents": [
			{"id": "w_scythe", "name": "Keen Claws", "row": 0, "max": 3, "icon": "rend", "fx": {"dmg:rend": 10}, "text": "Spectral Rend deals {dmg:rend}% more damage."},
			{"id": "w_focus", "name": "Grim Focus", "row": 0, "max": 3, "icon": "t_eye", "fx": {"dex": 3}, "text": "+{dex} dexterity."},
			{"id": "w_harvest", "name": "Soul Harvest", "row": 1, "max": 3, "icon": "t_heart", "fx": {"rend_heal": 1}, "text": "Each soul Spectral Rend tears out heals {rend_heal}% more of your life."},
			{"id": "w_haste", "name": "Deathly Haste", "row": 1, "max": 3, "icon": "t_haste", "fx": {"ias": 5}, "text": "+{ias}% attack speed."},
			{"id": "w_cruel", "name": "Cruelty", "row": 2, "max": 3, "icon": "t_star", "fx": {"crit": 3}, "text": "+{crit}% chance to land a critical hit."},
			{"id": "w_exec", "name": "Executioner", "row": 2, "max": 2, "icon": "t_skull", "fx": {"crit_dmg": 20}, "text": "Critical hits deal {crit_dmg}% more damage."},
			{"id": "w_moon", "name": "Harvest Moon", "row": 3, "max": 1, "icon": "rend", "fx": {"rend_full": 1}, "text": "Spectral Rend's claws tear all the way round you."},
		]},
		{"name": "Shadow", "desc": "The tether and the mist: Soul Siphon and Shadowstep.", "talents": [
			{"id": "w_scream", "name": "Hungry Tether", "row": 0, "max": 3, "icon": "siphon", "fx": {"dmg:siphon": 12}, "text": "Soul Siphon drains {dmg:siphon}% more."},
			{"id": "w_mind", "name": "Ethereal Mind", "row": 0, "max": 3, "icon": "t_drop", "fx": {"mana_pct": 5}, "text": "+{mana_pct}% maximum mana."},
			{"id": "w_dread", "name": "Long Grip", "row": 1, "max": 3, "icon": "siphon", "fx": {"siphon_dur": 0.3}, "text": "Soul Siphon holds {siphon_dur} seconds longer."},
			{"id": "w_slip", "name": "Slipstream", "row": 1, "max": 3, "icon": "step", "fx": {"cd:step": 10, "dmg:step": 10}, "text": "Shadowstep recharges {cd:step}% faster and strikes {dmg:step}% harder."},
			{"id": "w_hollow", "name": "Hollow Hunger", "row": 2, "max": 3, "icon": "t_drop", "fx": {"cost:siphon": 15, "cd:siphon": 8}, "text": "Soul Siphon costs {cost:siphon}% less mana and recharges {cd:siphon}% faster."},
			{"id": "w_form", "name": "Spirit Form", "row": 2, "max": 2, "icon": "t_ward", "fx": {"res": 6}, "text": "+{res}% to all resistances."},
			{"id": "w_echo", "name": "Lingering Mist", "row": 3, "max": 1, "icon": "step", "fx": {"veil": 0.6, "step_stun": 0.5}, "text": "After Shadowstep you stay mist {veil} seconds longer, and its strike stuns {step_stun} seconds longer."},
		]},
		{"name": "Night", "desc": "What comes out of the dark: Haunting Grasp, Phantom Assault and Eternal Night.", "talents": [
			{"id": "w_unlife", "name": "Unlife", "row": 0, "max": 3, "icon": "t_heart", "fx": {"life_pct": 4}, "text": "+{life_pct}% maximum life."},
			{"id": "w_chill", "name": "Grave Chill", "row": 0, "max": 3, "icon": "t_armor", "fx": {"armor_pct": 6}, "text": "+{armor_pct}% defense."},
			{"id": "w_legion", "name": "Legion", "row": 1, "max": 3, "icon": "phantom", "fx": {"dmg:phantom": 12, "dmg:grasp": 12}, "text": "Phantom Assault and Haunting Grasp strike {dmg:phantom}% harder."},
			{"id": "w_ward", "name": "Spectral Ward", "row": 1, "max": 3, "icon": "t_ward", "fx": {"res": 5}, "text": "+{res}% to all resistances."},
			{"id": "w_eternal", "name": "Eternal", "row": 2, "max": 2, "icon": "t_hourglass", "fx": {"buff_dur": 2, "grasp_hold": 0.3}, "text": "Eternal Night's power lasts {buff_dur} seconds longer and Haunting Grasp holds {grasp_hold} seconds longer."},
			{"id": "w_siphon", "name": "Soul Siphon", "row": 2, "max": 3, "icon": "t_fang", "fx": {"ls": 1}, "text": "+{ls}% of the damage you deal comes back as life."},
			{"id": "w_rider", "name": "Fourth Rider", "row": 3, "max": 1, "icon": "night", "fx": {"phantoms": 1, "dmg:night": 15}, "text": "Phantom Assault sends a fourth phantom, and Eternal Night deals {dmg:night}% more damage."},
		]},
	],
	"demon": [
		{"name": "Magma", "desc": "The fists and the charge: Molten Fists, Infernal Charge and raw fury.", "talents": [
			{"id": "d_sear", "name": "Searing Fists", "row": 0, "max": 3, "icon": "fists", "fx": {"dmg:fists": 10}, "text": "Molten Fists deal {dmg:fists}% more damage."},
			{"id": "d_brim", "name": "Brimstone", "row": 0, "max": 3, "icon": "t_fist", "fx": {"str": 3}, "text": "+{str} strength."},
			{"id": "d_kindle", "name": "Kindling", "row": 1, "max": 3, "icon": "t_sword", "fx": {"dmg": 4}, "text": "+{dmg}% damage."},
			{"id": "d_frenzy", "name": "Frenzy", "row": 1, "max": 3, "icon": "t_haste", "fx": {"ias": 5}, "text": "+{ias}% attack speed."},
			{"id": "d_edge", "name": "Infernal Edge", "row": 2, "max": 3, "icon": "t_star", "fx": {"crit": 3}, "text": "+{crit}% chance to land a critical hit."},
			{"id": "d_cinder", "name": "Cinder Heart", "row": 2, "max": 2, "icon": "t_skull", "fx": {"crit_dmg": 20}, "text": "Critical hits deal {crit_dmg}% more damage."},
			{"id": "d_inferno", "name": "Inferno", "row": 3, "max": 1, "icon": "fists", "fx": {"fists_wide": 1}, "text": "Molten Fists crack the ground a metre further and wider, and what they light burns twice as long."},
		]},
		{"name": "Cataclysm", "desc": "The ground torn open: Infernal Charge, Fault of the Pit and Brimstone Hurl.", "talents": [
			{"id": "d_bargain", "name": "Cheap Fury", "row": 0, "max": 3, "icon": "icharge", "fx": {"cost:icharge": 15, "cost:hurl": 10}, "text": "Infernal Charge costs {cost:icharge}% and Brimstone Hurl {cost:hurl}% less mana."},
			{"id": "d_ferocity", "name": "Ferocity", "row": 0, "max": 3, "icon": "cslam", "fx": {"dmg:cslam": 12, "dmg:hurl": 12}, "text": "Fault of the Pit and Brimstone Hurl deal {dmg:cslam}% more damage."},
			{"id": "d_hellsworn", "name": "Hellsworn", "row": 1, "max": 3, "icon": "t_heart", "fx": {"life_pct": 4}, "text": "+{life_pct}% maximum life."},
			{"id": "d_pack", "name": "Slow Cooling", "row": 1, "max": 3, "icon": "cslam", "fx": {"trail_dur": 1}, "text": "Fault of the Pit stays molten {trail_dur} seconds longer."},
			{"id": "d_tithe", "name": "Stampede", "row": 2, "max": 2, "icon": "icharge", "fx": {"cd:icharge": 15, "dmg:icharge": 10}, "text": "Infernal Charge recharges {cd:icharge}% faster and hits {dmg:icharge}% harder."},
			{"id": "d_oath", "name": "Pit Lord", "row": 2, "max": 3, "icon": "wrath", "fx": {"buff_pow": 10}, "text": "Pit-born's damage bonus (after Wrath of the Pit) is {buff_pow}% higher."},
			{"id": "d_legion", "name": "Brimstone Hoard", "row": 3, "max": 1, "icon": "hurl", "fx": {"hurl_twin": 1}, "text": "Brimstone Hurl holds a third charge."},
		]},
		{"name": "The Pit", "desc": "What the pit gives: Hellgrip, Wrath of the Pit and charcoal hide.", "talents": [
			{"id": "d_plate", "name": "Charcoal Hide", "row": 0, "max": 3, "icon": "t_armor", "fx": {"armor_pct": 6}, "text": "+{armor_pct}% defense."},
			{"id": "d_hide", "name": "Demon Hide", "row": 0, "max": 3, "icon": "t_heart", "fx": {"life_pct": 4}, "text": "+{life_pct}% maximum life."},
			{"id": "d_rift", "name": "Crushing Grip", "row": 1, "max": 3, "icon": "grip", "fx": {"dmg:grip": 12}, "text": "Hellgrip smashes {dmg:grip}% harder."},
			{"id": "d_abyss", "name": "Abyssal Ward", "row": 1, "max": 3, "icon": "t_ward", "fx": {"res": 5}, "text": "+{res}% to all resistances."},
			{"id": "d_erupt", "name": "Long Wrath", "row": 2, "max": 2, "icon": "wrath", "fx": {"wrath_dur": 1, "cd:wrath": 8}, "text": "Wrath of the Pit's meteors rain {wrath_dur} seconds longer and it recharges {cd:wrath}% faster."},
			{"id": "d_hunger", "name": "Hungering Fire", "row": 2, "max": 3, "icon": "t_fang", "fx": {"ls": 1}, "text": "+{ls}% of the damage you deal comes back as life."},
			{"id": "d_furnace", "name": "Meteor Storm", "row": 3, "max": 1, "icon": "wrath", "fx": {"wrath_double": 1}, "text": "Wrath of the Pit calls two meteors at a time."},
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
	"plague": [
		{"name": "Toxicology", "desc": "Poison: Toxic Flask, longer and crueller clouds.", "talents": [
			{"id": "p_dose", "name": "Stronger Dose", "row": 0, "max": 3, "icon": "toxic", "fx": {"dmg:toxic": 10}, "text": "Toxic Flask deals {dmg:toxic}% more damage."},
			{"id": "p_study", "name": "Studied Hand", "row": 0, "max": 3, "icon": "t_eye", "fx": {"ene": 3}, "text": "+{ene} energy."},
			{"id": "p_venom", "name": "Virulent Venom", "row": 1, "max": 3, "icon": "t_star", "fx": {"poison_dmg": 8}, "text": "All your poison hurts {poison_dmg}% more."},
			{"id": "p_cloud", "name": "Heavy Vapour", "row": 1, "max": 3, "icon": "toxic", "fx": {"cloud_size": 10}, "text": "Your poison clouds spread {cloud_size}% wider."},
			{"id": "p_linger", "name": "Lingering Rot", "row": 2, "max": 3, "icon": "t_hourglass", "fx": {"poison_dur": 1.0}, "text": "Poison keeps working {poison_dur} seconds longer after a foe leaves a cloud."},
			{"id": "p_thrift", "name": "Measured Doses", "row": 2, "max": 2, "icon": "t_hourglass", "fx": {"cost:toxic": 15}, "text": "Toxic Flask costs {cost:toxic}% less mana."},
			{"id": "p_miasma", "name": "Standing Miasma", "row": 3, "max": 1, "icon": "toxic", "fx": {"cloud_dur": 2.0}, "text": "Every poison cloud hangs {cloud_dur} seconds longer."},
		]},
		{"name": "Volatile Arts", "desc": "Fire and fuses: Volatile Mixture and the ignition of his clouds.", "talents": [
			{"id": "p_charge", "name": "Bigger Charge", "row": 0, "max": 3, "icon": "volatile", "fx": {"dmg:volatile": 12}, "text": "Volatile Mixture deals {dmg:volatile}% more damage."},
			{"id": "p_steady", "name": "Steady Hands", "row": 0, "max": 3, "icon": "t_fist", "fx": {"dex": 3}, "text": "+{dex} dexterity."},
			{"id": "p_blast", "name": "Wide Blast", "row": 1, "max": 3, "icon": "volatile", "fx": {"blast_size": 8}, "text": "Volatile Mixture's blast reaches {blast_size}% further."},
			{"id": "p_quick", "name": "Short Fuse", "row": 1, "max": 3, "icon": "t_hourglass", "fx": {"cd:volatile": 8}, "text": "Volatile Mixture recharges {cd:volatile}% faster."},
			{"id": "p_ignite", "name": "Flashpoint", "row": 2, "max": 3, "icon": "volatile", "fx": {"ignite_dmg": 20}, "text": "Ignited clouds burn {ignite_dmg}% hotter."},
			{"id": "p_cane", "name": "Iron-Shod Cane", "row": 2, "max": 2, "icon": "attack", "fx": {"dmg:attack": 10}, "text": "Your cane strikes {dmg:attack}% harder."},
			{"id": "p_inferno", "name": "Alchemical Fire", "row": 3, "max": 1, "icon": "volatile", "fx": {"dmg:volatile": 25, "blast_size": 15}, "text": "Volatile Mixture deals {dmg:volatile}% more damage and its blast reaches {blast_size}% further."},
		]},
		{"name": "Contagion", "desc": "Traps and the epidemic: preparation, infection and the dome.", "talents": [
			{"id": "p_spring", "name": "Hair Trigger", "row": 0, "max": 3, "icon": "trap", "fx": {"dmg:trap": 12}, "text": "Pestilent Trap deals {dmg:trap}% more damage."},
			{"id": "p_hardy", "name": "Hardened Physician", "row": 0, "max": 3, "icon": "t_heart", "fx": {"life_pct": 4}, "text": "+{life_pct}% maximum life."},
			{"id": "p_snare", "name": "Choking Gas", "row": 1, "max": 3, "icon": "trap", "fx": {"trap_stun": 0.3}, "text": "Pestilent Trap stuns {trap_stun} seconds longer."},
			{"id": "p_spread", "name": "Carriers", "row": 1, "max": 3, "icon": "epidemic", "fx": {"inf_jumps": 1}, "text": "Infection can jump {inf_jumps} more times."},
			{"id": "p_cache", "name": "Second Cache", "row": 2, "max": 1, "icon": "trap", "fx": {"trap_max": 1}, "text": "Keep {trap_max} more Pestilent Trap set."},
			{"id": "p_fever", "name": "Long Fever", "row": 2, "max": 3, "icon": "t_hourglass", "fx": {"inf_dur": 1.0, "dome_dur": 0.5}, "text": "Infection lasts {inf_dur} seconds longer and the dome {dome_dur} seconds longer."},
			{"id": "p_last", "name": "Pandemic", "row": 3, "max": 1, "icon": "epidemic", "fx": {"dome_size": 20, "cd:epidemic": 20}, "text": "The Last Epidemic's dome is {dome_size}% wider and it recharges {cd:epidemic}% faster."},
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
	"plague": ["p_dose", "p_study", "p_venom", "p_cloud", "p_linger", "p_thrift", "p_miasma", "p_charge", "p_steady", "p_blast", "p_quick", "p_ignite",
		"p_cane", "p_inferno", "p_spring", "p_hardy", "p_snare", "p_spread", "p_cache", "p_fever", "p_last"],
	"knight": ["k_zeal", "k_heavy", "k_radiance", "k_fervor", "k_steel", "k_purify", "k_consecrate", "k_vigor", "k_tough", "k_resolve", "k_wall", "k_guard", "k_wind", "k_unbroken",
		"k_might", "k_momentum", "k_ram", "k_sword", "k_command", "k_rally", "k_relentless"],
	"wraith": ["w_scythe", "w_focus", "w_harvest", "w_haste", "w_cruel", "w_exec", "w_moon", "w_unlife", "w_chill", "w_legion", "w_ward", "w_eternal", "w_siphon", "w_rider",
		"w_scream", "w_mind", "w_dread", "w_slip", "w_hollow", "w_form", "w_echo"],
	"demon": ["d_sear", "d_brim", "d_kindle", "d_frenzy", "d_edge", "d_cinder", "d_inferno", "d_ferocity", "d_bargain", "d_pack", "d_hellsworn", "d_tithe", "d_oath", "d_legion",
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

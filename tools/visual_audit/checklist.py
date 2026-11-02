#!/usr/bin/env python3
"""Builds the visual production checklist (docs/visual/checklist.csv) from the audit's measurements and the
per-asset assessment below. Re-run after changing an assessment or re-measuring:

    python3 tools/visual_audit/glb_audit.py build/visual_audit && python3 tools/visual_audit/uv_report.py build/visual_audit/uv.csv
    python3 tools/visual_audit/checklist.py build/visual_audit docs/visual/checklist.csv

Scores are 1-5 against the Diablo IV / Path of Exile 2 bar at the game camera (and in close-ups where the asset is
shown up close): 5 ship-ready AAA, 4 good, 3 acceptable in play with visible weaknesses, 2 visibly below the rest
of the game, 1 placeholder. Columns: geometry, silhouette/design, texture, material (PBR response), animation,
LOD/scalability, consistency with the game, performance. Status is one of the overhaul's eight stages.
Actions: R rebuild (new model), M regenerate with Meshy, B Blender refinement, T new or improved textures,
S material/shader work, A animation, O optimise.
"""
import csv
import json
import os
import sys

STATUSES = ["Not inspected", "Inspected", "Needs improvement", "Being rebuilt", "Blender refinement",
	"Imported into Godot", "In-game testing", "Approved"]

# path (under assets/models) -> (geo, sil, tex, mat, anim, lod, cons, perf), priority, actions, status, note
# anim 0 = not animated (props); lod 2 = no LODs (Meshy's UV atlas blocks the importer's LOD generation)
A = {
	# --- heroes (playable bodies)
	"knight_meshy.glb": ((4, 3, 3, 3, 4, 2, 3, 4), "P3", "B T", "Inspected", "The plain knight (no armour): the only light-coloured hero, reads well. Generic shirt and shorts; 33k tris."),
	"knight_armored.glb": ((4, 4, 3, 4, 3, 2, 4, 3), "P3", "T", "In-game testing", "Great helm, spiked plate, tattered cloak. Its plate was painted near-black (metal 0.26 sRGB = 5% reflectance), so it read as a dark blob: metal_lift.py raised the metal's reflectance to 0.50 and its roughness 0.51 -> 0.41 (stage 2), and the rim light outlines him. Normal map still weak (4.7 deg)."),
	"knight_mocap.glb": ((4, 4, 3, 4, 4, 2, 4, 3), "P3", "T O", "In-game testing", "The armoured knight in play (mocap skeleton): the same metal lift as knight_armored (stage 2), so the plate reads as steel and catches the hero light and the rim. 70k tris, no LOD."),
	"knight_statue.glb": ((4, 4, 3, 2, 0, 3, 4, 2), "P3", "O T", "In-game testing", "Arena statues: 70k tris for a static statue (5 in Aurelia), flat normal map (1.9 deg). Detail normals generated (stage 2); decimate to ~15k."),
	"archer_ranger.glb": ((4, 4, 4, 3, 4, 2, 4, 3), "P3", "S", "Inspected", "Hooded ranger with fur collar and quiver: good sculpt, very dark leathers; 60k tris, 16 clips."),
	"wraith_mocap.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P3", "S", "Inspected", "Horned, chained wraith on mocap with the spectral shader: strong silhouette; 45k tris."),
	"demon_mocap.glb": ((4, 5, 3, 3, 4, 2, 4, 3), "P3", "S", "Inspected", "Magma brute (wings, horns, tail, lava cracks): the strongest silhouette in the game; 50k tris."),
	"gnome_warlock.glb": ((4, 5, 3, 2, 3, 2, 4, 3), "P2", "T A", "In-game testing", "Huge hat and beard: distinct. Flat normal map (1.5 deg) -> detail normals generated (stage 2). No baked clips (code-posed A-pose rig)."),
	"plague_doctor.glb": ((4, 5, 3, 3, 4, 2, 4, 3), "P3", "S", "Inspected", "Beak mask, hat, coat and satchels: strong design, 27 clips; dark (colour map 0.21)."),
	"dragons/wyrm.glb": ((4, 4, 3, 3, 3, 2, 3, 3), "P3", "S T", "Inspected", "Obsidian Wyrm: near-black body (0.16) with red emissive; code-posed; no skills yet."),
	"dragons/serpent.glb": ((4, 4, 3, 3, 3, 2, 3, 3), "P3", "S T", "Inspected", "Frost Serpent: antlered eastern dragon, near-black with cyan emissive; code-posed."),
	"dragons/wyvern.glb": ((4, 4, 3, 3, 3, 2, 3, 3), "P3", "S T", "Inspected", "Storm Wyvern: near-black with teal accents; code-posed."),
	# --- bosses
	"grubb_mutant.glb": ((4, 5, 3, 2, 3, 2, 4, 3), "P2", "T", "In-game testing", "King Grubb: crown, belly, cape, key; distinct. Flat normal map (1.5 deg) -> detail normals generated. 80k tris."),
	# --- monsters
	"monsters/zombie.glb": ((3, 3, 3, 2, 3, 2, 3, 3), "P2", "T A", "In-game testing", "Ragged zombie: flat normal map (1.0 deg) -> detail normals generated. Code-posed A-pose rig; 24k tris, no LOD."),
	"monsters/fallen.glb": ((3, 3, 3, 2, 3, 2, 3, 3), "P3", "T", "In-game testing", "Plain red imp (base Fallen): flat normals -> generated. Low detail next to its three variants."),
	"monsters/fallen_skirmisher.glb": ((3, 3, 3, 3, 3, 2, 4, 3), "P3", "", "Inspected", "Horned red imp: fine at game distance."),
	"monsters/champion.glb": ((4, 5, 4, 4, 3, 2, 4, 3), "P3", "", "In-game testing", "A2 boss Aurelius, Champion of the Arena (stage 3, Meshy): lion-faced bronze cuirass, lion pauldron, crimson crest and pteruges, rigged on the game's 13 joints (rig_monster.py, crotch hint for the skirt). Was the code-built humanoid in red cloth. 30k tris, 2K."),
	"monsters/gladiator.glb": ((4, 4, 4, 4, 3, 2, 4, 4), "P3", "", "In-game testing", "A2 arena Gladiator (stage 3, Meshy): bronze helm, manica, loincloth, greaves. Was the code-built humanoid. 20k tris, 1K."),
	"monsters/ashen_king.glb": ((4, 5, 4, 4, 3, 2, 4, 3), "P3", "", "In-game testing", "A3 boss The Ashen King (stage 3, Meshy): charred plate cracked with embers (emission map from the painted cracks, emission_from_albedo.py), skull face, spiked iron crown, ermine mantle. Was the code-built humanoid. 30k tris, 2K."),
	# added on staging the same night (Blaine's Verdant Isle and Battlegrounds work), inspected after the merge
	"monsters/dino/raptor.glb": ((4, 4, 3, 3, 3, 2, 4, 3), "P4", "", "Inspected", "Feathered raptor (Verdant Isle packs): detailed, dark (colour map 0.20); posed in code (theropod.gd). 30k tris, 2K."),
	"monsters/dino/trex.glb": ((4, 4, 3, 3, 3, 2, 4, 2), "P3", "O", "Inspected", "Gorehide the Tyrant: bony, spiked-tail T-rex; strong silhouette. 45k tris is heavy for a roaming boss (no LOD)."),
	"monsters/dino/triceratops.glb": ((4, 4, 3, 3, 3, 2, 4, 3), "P4", "T", "Inspected", "Mother triceratops: good; weak normal map (4.6 deg)."),
	"monsters/dino/baby_trike.glb": ((4, 4, 3, 3, 3, 2, 4, 4), "P4", "", "Inspected", "Baby triceratops: charming, clean (198 UV islands). 15k tris."),
	"monsters/dwarf.glb": ((4, 4, 3, 3, 3, 2, 4, 3), "P4", "", "Inspected", "The Drunken Dwarf: hammer, fur cape, braided beard; reads well. 22k tris."),
	"monsters/hermit.glb": ((4, 5, 3, 3, 3, 2, 4, 3), "P4", "", "Inspected", "Old Mossbeard, the thorn hermit (Battlegrounds boss): mushroom cap and moss beard, a memorable silhouette. 28k tris."),
	"monsters/ice_troll.glb": ((4, 5, 4, 3, 3, 2, 4, 3), "P4", "", "Inspected", "Hrimgar the Frostbound (Battlegrounds boss): ice crystals down the back, strong. 40k tris, 2K."),
	"monsters/troll_shaman.glb": ((4, 4, 3, 3, 3, 2, 4, 3), "P4", "", "Inspected", "Troll Beast-Tamer: feathered headdress, tribal straps; dark at game distance. 22k tris."),
	"isles/verdant/egg_nest.glb": ((2, 3, 3, 2, 0, 2, 3, 3), "P3", "B", "Needs improvement", "Raptor nest: the decimation left a crumpled shard soup (2,526 islands); reads as twigs from afar, poorly up close."),
	"isles/verdant/raptor_pen.glb": ((3, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Stake pen: good."),
	"isles/verdant/troll_hut.glb": ((3, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Thatched troll hut: shard-like thatch but reads as a hut. 12k tris."),
	"isles/verdant/troll_totem.glb": ((3, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Feathered totem: good."),
	"isles/verdant/tunnel.glb": ((3, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Vine-hung rock tunnel: faceted rock up close, fine in play."),
	"monsters/fallen_reaver.glb": ((4, 4, 3, 4, 3, 2, 4, 3), "P4", "", "In-game testing", "Armoured demon brute: good; its dark iron lifted to 0.42 (metal_lift.py, stage 2)."),
	"monsters/fallen_stalker.glb": ((4, 4, 3, 3, 3, 2, 4, 3), "P3", "", "Inspected", "Long-limbed stalker: good silhouette."),
	"monsters/archer.glb": ((3, 3, 3, 2, 3, 2, 3, 3), "P3", "T", "In-game testing", "Bone Archer: flat normals (1.6 deg) -> generated."),
	"monsters/goblin_guard.glb": ((3, 3, 3, 2, 3, 2, 3, 3), "P3", "T", "In-game testing", "Goblin guard: flat normals (1.0 deg) -> generated; dark."),
	"monsters/bandit.glb": ((3, 3, 3, 3, 3, 2, 3, 3), "P3", "", "Inspected", "Hooded bandit: generic but fine; also the Bandit Bowman."),
	"monsters/bear.glb": ((4, 5, 3, 3, 3, 2, 4, 3), "P3", "", "Inspected", "Forsaken Bear (antlers, thorns, chains): excellent silhouette."),
	"monsters/wolf.glb": ((4, 4, 3, 3, 3, 2, 4, 3), "P3", "", "Inspected", "Spirit Wolf (pet/summon)."),
	"monsters/lion.glb": ((4, 4, 3, 3, 3, 2, 4, 3), "P3", "", "Inspected", "Arena lion: good, dark (0.14)."),
	"monsters/feral1.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Feral crawler (baked clips): good; five colour/costume variants."),
	"monsters/feral2.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Feral variant (red)."),
	"monsters/feral3.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Feral variant."),
	"monsters/feral4.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Feral variant (blue-grey)."),
	"monsters/feral5.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Feral variant."),
	"monsters/hollow_sloth_fire.glb": ((4, 5, 3, 2, 3, 2, 4, 3), "P3", "T", "In-game testing", "Cinderhide: great elemental variant; flat normals (1.5 deg) -> generated."),
	"monsters/hollow_sloth_ice.glb": ((4, 5, 3, 3, 3, 2, 4, 3), "P3", "T", "In-game testing", "Rimeclaw: weak normals (2.7 deg) -> generated."),
	"monsters/hollow_sloth_storm.glb": ((4, 5, 3, 2, 3, 2, 4, 3), "P3", "T", "In-game testing", "Thundermaw: flat normals (1.3 deg) -> generated."),
	# --- NPCs
	"npc/grisold.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Blacksmith: good; baked idle/talk clips."),
	"npc/hedda.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Armourer: good."),
	"npc/maeve.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Hooded alchemist: good, very dark."),
	"npc/osric.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Shipwright: good."),
	"npc/roth.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Cloaked veteran: good."),
	"npc/tarrow.glb": ((4, 4, 3, 3, 4, 2, 4, 3), "P4", "", "Inspected", "Gambler in red: good, the most colourful NPC."),
	# --- camp
	"camp/alchemy.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Alchemist's stall (herbs, potion shelves, cauldron): good."),
	"camp/armory.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Armory stall: good."),
	"camp/forge.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Forge: good."),
	"camp/gate.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Twin-tower gate: good."),
	"camp/bonfire.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Stone ring with spit and pot: good."),
	"camp/cookfire.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Re-baked set piece: good."),
	"camp/hide_rack.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Re-baked set piece: good."),
	"camp/lantern.glb": ((4, 4, 4, 4, 0, 4, 4, 4), "P4", "", "In-game testing", "Hanging lantern (used all over the camp), re-made (stage 3): a Meshy concept (chain edited out so it hangs from its ring), image-to-3D, re-baked onto clean UVs by camp/rebake_prop.py (191 islands, was 507; 512 px, was 256; 2k tris). Was shattered glass shards and spikes."),
	"camp/lantern_post.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Re-baked set piece: good."),
	"camp/log_bench.glb": ((4, 3, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Re-baked set piece: fine."),
	"camp/palisade.glb": ((4, 4, 4, 3, 0, 4, 4, 4), "P4", "", "In-game testing", "Camp palisade section (34 round the ring), re-made (stage 3): ten tight, mossy, unevenly sharpened logs in two rope bands (Meshy), re-baked onto clean UVs (415 islands, was 1,323; 1K, was 512; 5k tris) so the importer can make LODs. 4.2 m tall (was 3.6). Chunked for culling (stage 1)."),
	"camp/runestone.glb": ((3, 3, 2, 3, 0, 2, 4, 4), "P3", "B", "In-game testing", "Rune stone: faceted shards, 512 px; reads fine with its glow. Chunked (stage 1)."),
	"camp/stash_chest.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Re-baked set piece."),
	"camp/supply_pile.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Re-baked set piece."),
	"camp/tent.glb": ((4, 3, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Tent: fine."),
	"camp/wagon.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Wagon: good."),
	"camp/weapon_rack.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Re-baked set piece."),
	"camp/woodpile.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Re-baked set piece."),
	# --- fort
	"fort/gate.glb": ((4, 4, 3, 2, 0, 2, 4, 3), "P3", "T", "In-game testing", "Grubb's gatehouse: good; flat normals -> generated. 40k tris, 2K."),
	"fort/hall.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Longhouse: good."),
	"fort/hut.glb": ((4, 4, 3, 2, 0, 2, 4, 3), "P3", "T", "In-game testing", "Hut: flat normals -> generated."),
	"fort/palisade.glb": ((4, 4, 3, 2, 0, 2, 4, 3), "P3", "T", "In-game testing", "Stake wall: flat normals -> generated."),
	"fort/tower.glb": ((4, 4, 3, 2, 0, 2, 4, 3), "P3", "T", "In-game testing", "Watchtower: flat normals -> generated."),
	# --- coast and isles
	"isles/beacon.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Lighthouse tower: good."),
	"isles/mono.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Rune monolith: good."),
	"isles/store.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Timber store house: good."),
	"isles/temple.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Overgrown temple: good."),
	"isles/wreck.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Shipwreck: good."),
	"boats/sloop.glb": ((4, 4, 4, 3, 0, 2, 4, 3), "P4", "", "Inspected", "The boat: 2K PNG textures (12 MB), good."),
	# --- sloth lairs
	"lairs/fire_rock.glb": ((3, 3, 3, 2, 0, 2, 4, 4), "P3", "T B", "In-game testing", "Lava rock: faceted shards, flat normals -> generated."),
	"lairs/fire_tree.glb": ((3, 4, 3, 2, 0, 2, 4, 4), "P3", "T", "In-game testing", "Burning dead tree: flat normals -> generated."),
	"lairs/ice_crystals.glb": ((3, 4, 3, 2, 0, 2, 4, 4), "P3", "T", "In-game testing", "Ice crystals: weak normals -> generated."),
	"lairs/ice_rock.glb": ((3, 3, 3, 2, 0, 2, 4, 4), "P3", "T B", "In-game testing", "Frozen rock: faceted, weak normals -> generated."),
	"lairs/storm_stone.glb": ((3, 4, 3, 2, 0, 2, 4, 4), "P3", "T", "In-game testing", "Storm rune stone: flat normals -> generated."),
	"lairs/storm_tree.glb": ((3, 4, 3, 2, 0, 2, 4, 4), "P3", "T", "In-game testing", "Storm tree: flat normals -> generated."),
	# --- trees and vegetation
	"trees/oak1.glb": ((2, 4, 3, 3, 0, 2, 4, 3), "P2", "M", "Needs improvement", "The moor's oak (hundreds on screen across Act I). Its own canopy is crumpled shards in a model sheet, but in play the game's leaf clusters cover it and it reads as a full, rooted oak. A procedural Blender replacement (tools/blender/trees/oak_gen.py: bark baked from a procedural material, one UV island per branch) was built and compared in the game (oak_compare.gd) and rejected: sparse, oversized, bare limbs. Better fix: Meshy with a modelled canopy."),
	"trees/oak2.glb": ((2, 4, 3, 3, 0, 2, 4, 3), "P2", "M", "Needs improvement", "Autumn oak: same; full in play."),
	"trees/oak3.glb": ((2, 4, 3, 3, 0, 2, 4, 3), "P2", "M", "Needs improvement", "Bent oak: same."),
	"trees/pine_old.glb": ((2, 3, 2, 2, 0, 2, 3, 3), "P2", "M R", "Needs improvement", "Old pine: shard canopy, 18k tris."),
	"trees/deadtree.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P3", "", "In-game testing", "Gnarled dead tree: good; 20k tris is heavy for a forest tree (chunked in the camp, stage 1)."),
	"grass/dry.glb": ((4, 4, 4, 4, 4, 4, 4, 3), "P4", "", "Inspected", "Living 3D grass species (Blender clumps on Meshy atlas, two LODs, wind and touch): good."),
	"grass/meadow.glb": ((4, 4, 4, 4, 4, 4, 4, 3), "P4", "", "Inspected", "Grass species."),
	"grass/moss.glb": ((4, 4, 4, 4, 4, 4, 4, 3), "P4", "", "Inspected", "Grass species."),
	"grass/sparse.glb": ((4, 4, 4, 4, 4, 4, 4, 3), "P4", "", "Inspected", "Grass species."),
	"grass/tall.glb": ((4, 4, 4, 4, 4, 4, 4, 3), "P4", "", "Inspected", "Grass species."),
	"grass/tussock.glb": ((4, 4, 4, 4, 4, 4, 4, 3), "P4", "", "Inspected", "Grass species."),
	"grass/weed.glb": ((4, 4, 4, 4, 4, 4, 4, 3), "P4", "", "Inspected", "Grass species."),
	# --- title screen
	"title/arcade.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Ruined gothic arcade: good."),
	"title/colossus.glb": ((4, 5, 4, 3, 0, 2, 4, 3), "P4", "", "Inspected", "Crowned king bust: excellent."),
	"title/crown.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "The crown: fine."),
	"title/gate.glb": ((4, 4, 3, 3, 0, 2, 4, 3), "P4", "", "Inspected", "The Gate of the Ashen Crown: good, 40k tris."),
	# --- items and class props
	"items/cinderheart.glb": ((2, 4, 3, 2, 0, 2, 3, 4), "P3", "B T", "In-game testing", "Material item: crumpled decimation shards; flat normals -> generated."),
	"items/everfrost.glb": ((3, 4, 3, 2, 0, 2, 3, 4), "P3", "B T", "In-game testing", "Material item: faceted; flat normals -> generated."),
	"items/stormglass.glb": ((2, 4, 3, 2, 0, 2, 3, 4), "P3", "B T", "In-game testing", "Material item: shards; flat normals -> generated."),
	"plague/cane.glb": ((4, 4, 3, 2, 0, 2, 4, 4), "P4", "T", "In-game testing", "Plague Doctor's cane: flat normals -> generated."),
	"plague/flask.glb": ((3, 4, 3, 2, 0, 2, 4, 4), "P3", "B T", "In-game testing", "Toxic Flask: faceted round glass; flat normals -> generated."),
	"plague/trap.glb": ((3, 4, 3, 3, 0, 2, 4, 4), "P4", "T", "In-game testing", "Pestilent Trap: flat normals -> generated; its iron lifted to 0.42 (metal_lift.py)."),
	"plague/volatile.glb": ((3, 4, 3, 2, 0, 2, 4, 4), "P3", "B T", "In-game testing", "Volatile Mixture: faceted; flat normals -> generated."),
	"ranger_bow.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "The ranger's bow: fine."),
	"arrows/fire.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Arrow model (Fire Arrow pipeline)."),
	"arrows/frost.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Arrow model."),
	"arrows/war.glb": ((4, 4, 3, 3, 0, 2, 4, 4), "P4", "", "Inspected", "Arrow model."),
	"fx/rock_chunks.glb": ((3, 3, 3, 3, 0, 4, 4, 4), "P4", "", "Inspected", "Untextured debris chunks for slams (coloured in code)."),
}

# Built in code or not a .glb: the systems the audit covered as a whole (see docs/visual/AUDIT.md)
P = [
	# id, category, (scores), priority, actions, status, note
	("enemy:grabber", "monsters", (3, 4, 3, 3, 3, 2, 3, 3), "P3", "M", "Inspected", "King Grubb's Gold Grabbers: code-sculpted goblins (Sculpt SDF bodies)."),
	("legacy acts 2-4 monsters", "monsters", (2, 2, 2, 2, 2, 2, 2, 3), "P4", "", "Inspected", "raider, mummy, scarab, sekhmun, fetish, spider, lizardman, vael, imp, hell_knight, doom_caster, malgoroth: code-built; their acts (Data.ACTS 1-3) are not reachable."),
	("terrain (Mats.TERRAIN_SHADER)", "environment", (3, 3, 2, 2, 0, 3, 3, 4), "P2", "T S", "Needs improvement", "Every zone's ground: fbm noise and Voronoi cobbles in one procedural shader, no material textures or decals (graphics plan phase 2, not started)."),
	("roads (World.road_style)", "environment", (3, 3, 3, 3, 0, 3, 3, 4), "P3", "T", "Inspected", "The paved Old Kingsroad and trails: procedural."),
	("procedural trees (Flora.pine/dead_tree/bush/fern)", "environment", (2, 2, 2, 2, 0, 2, 3, 3), "P2", "M R", "Needs improvement", "Code-built pines (3.7-4.5k tris each, ~1,500 on the coast), dead trees, bushes and ferns: tube-and-card trees next to Meshy assets."),
	("A2/A3 grass (Flora grass clumps)", "environment", (2, 2, 2, 2, 3, 3, 3, 3), "P2", "R", "Needs improvement", "A2 and A3 still use the old blade clumps (15 M triangles on the Imperial Road), not Act I's living 3D grass."),
	("rocks (Props.rock_mesh)", "environment", (3, 3, 2, 2, 0, 3, 3, 4), "P3", "M T", "Needs improvement", "Code-built rocks and boulders."),
	("Roman architecture (Roman.*)", "environment", (3, 3, 2, 2, 0, 3, 3, 4), "P2", "M T", "Needs improvement", "A2's Aurelia, aqueducts, colonnades, arena: code-built boxes and cylinders with procedural marble/tuff/brick."),
	("small props (Props.crate/barrel/log_pile/pot/...)", "environment", (2, 2, 2, 2, 0, 3, 3, 4), "P3", "M", "Needs improvement", "Code-built clutter where no Meshy set piece replaced it."),
	("waypoint (Props.waypoint)", "environment", (3, 3, 3, 3, 0, 3, 3, 4), "P3", "M", "Inspected", "Procedural stone ring; retuned in the camp plan."),
	("ocean (Ocean)", "environment", (4, 4, 4, 4, 4, 3, 4, 3), "P4", "", "Inspected", "Wave simulation and shading for the coast and isles."),
	("weather (Weather)", "environment", (3, 3, 3, 3, 3, 4, 4, 4), "P4", "", "Inspected", "Snow and ash particles."),
	("fire (FireFx)", "vfx", (4, 4, 4, 4, 4, 3, 4, 3), "P4", "", "Inspected", "Every fire: Mantaflow flipbooks on layered particles. The benchmark."),
	("archer skills (ArrowFx)", "vfx", (4, 4, 4, 4, 4, 3, 4, 3), "P4", "", "Inspected", "Fire/Frost/War arrows: custom shaders and flipbooks. The Fire Arrow benchmark."),
	("demon skills (DemonFx, DemonFistsFx, InfernalFx)", "vfx", (4, 4, 4, 4, 4, 3, 4, 3), "P4", "", "Inspected", "Lava, fissures, meteors, Hellbrand fists: custom shaders and flipbooks."),
	("knight skills (KnightFx)", "vfx", (4, 4, 3, 3, 3, 4, 4, 4), "P2", "S", "In-game testing", "Stage 2: Holy Nova, Battle Cry and Charge rebuilt from the knight's own visual language (HolyFx: a sacred seal drawn on the ground, gold-and-white holy fire rings, a streaked light column, a screen-space shockwave, sunbursts, motes, a glinting charge trail), so the default class no longer looks like everyone's recoloured bursts. Needs a real-GPU look at speed."),
	("wraith skills (WraithFx)", "vfx", (4, 4, 3, 3, 3, 4, 4, 4), "P3", "S", "In-game testing", "Had one custom shader (the night floor) and 20 generic bursts and 8 rings. Stage 3: his spirit light streaks out as curling wisps (quads stretched along their flight, cyan to violet), shadow rolls as soft smoke, and every ring is a ripple of soul-mist racing over the ground (WraithFx._spirit_burst, _soul_ring), so none of his skills uses the shared shapes."),
	("warlock skills (WarlockFx)", "vfx", (4, 4, 3, 3, 3, 4, 4, 4), "P3", "S", "In-game testing", "Drain Life's beam was already custom. Stage 3: Blight Bolt's burst (a ring of fel fire, a pale flare, sickly smoke, splashing blight, souls rising), Soul Shackles' cast (his sigil turning under him, shadow and fel sparks pulled in from the edge of its reach, the air shuddering) and Fel Covenant (a big sigil, a crown of fel fire roaring up round him, souls spiralling up) replace the generic ring, burst and pillar; fel fire is InfernalFx's flame in the Warlock's palette."),
	("plague skills (Plague)", "vfx", (3, 3, 3, 3, 3, 4, 3, 4), "P2", "S T", "Inspected", "Flask, mixture, trap, epidemic effects in plague.gd."),
	("shared skills (SharedFx)", "vfx", (4, 4, 3, 3, 3, 4, 4, 4), "P3", "S", "In-game testing", "Every class can use them. Were the generic burst and ring in four colours; now ElementalFx (stage 3): Earthshatter cracks the ground through its wedge (a crack decal running out, rock spikes heaving up and sinking, chunks, pebbles, rolling dust); Frost Nova spreads frost with a bright edge and bursts a ring of ice crystals that shatter, cold mist, glints; Arc is jagged branching lightning re-struck every few frames, leaping target to target; War Cry burns a war sigil, ripples the air, rolls a wave of dust and ash out to its 8 m, embers rise."),
	("generic effects (Fx)", "vfx", (3, 3, 2, 3, 3, 4, 3, 4), "P2", "S T", "Needs improvement", "burst/ring/pillar/flash/telegraph: soft-dot particles a few monsters and items still share (the heroes' skills no longer use them). Stage 3: sparks and blood (every hit) are streaks stretched along their flight (Fx.streaks); the bosses' slams and the bear's maul crack the ground with rock spikes and dust (ElementalFx.ground_slam), novas are a ring of hellfire (or sick green fire) racing out with a heat ripple (fire_nova), summonings burn a circle and raise smoke (summon_circle)."),
	("weapon trail and hit flash (Hero, Enemy)", "vfx", (0, 3, 3, 4, 3, 4, 4, 4), "P2", "S", "In-game testing", "Every class's swing and every struck foe. The trail was additive at 55-90% across its whole width (a flat white band in Forward+); staging fixed it the same night (Hero._trail_shader, 00e1d19: hot edge, soft body, Catmull-Rom). The hit flash was flat unshaded white (paper cut-outs); now rim-weighted and fading, so the body keeps its shape (Enemy.FLASH_SHADER, stage 2)."),
	("lighting and grade (Game._zone_env, Grade)", "rendering", (0, 0, 0, 3, 0, 3, 3, 3), "P1", "S", "In-game testing", "Low contrast and lifted blacks (fog); the hero is hard to read on dark ground. Rim light now in every zone (stage 2); grading per zone needs a real-GPU pass."),
	("shadows (sun cascades, omni budget)", "rendering", (0, 0, 0, 4, 0, 4, 4, 4), "P1", "O", "In-game testing", "Cascades fitted to the camera, fire shadows under the budget (stage 1)."),
	("culling and LOD (multimesh chunks, LODs)", "rendering", (0, 0, 0, 0, 0, 2, 3, 2), "P1", "O B", "In-game testing", "Camp chunked and the hidden portrait stopped (stage 1). No Meshy model has LODs (UV atlas)."),
	("texture import (lossy WebP, uncompressed in VRAM)", "rendering", (0, 0, 3, 0, 0, 0, 3, 2), "P2", "O", "Needs improvement", "Model textures decode to RGBA8 in video memory (1.0-1.9 GB); VRAM compression would cut it ~4x but grows the download: a decision."),
	("HUD and windows (UI, Meshy frames)", "ui", (0, 4, 4, 0, 3, 0, 4, 4), "P4", "", "Inspected", "D4-style HUD, globes, Meshy-painted frames, skill and talent icons."),
	("title screen (TitleStage)", "screens", (4, 4, 4, 3, 3, 3, 4, 3), "P4", "", "Inspected", "The Gate of the Ashen Crown at dusk."),
	("new character screen (ClassStage)", "screens", (4, 4, 3, 3, 4, 3, 4, 3), "P3", "S", "Inspected", "Focused carousel of the heroes: close-ups expose the dark textures and flat normals (gnome)."),
]


def main():
	src, out = sys.argv[1], sys.argv[2]
	audit = {m["path"]: m for m in json.load(open(os.path.join(src, "audit.json")))["models"]}
	uv = {}
	uvp = os.path.join(src, "uv.csv")
	if os.path.exists(uvp):
		for r in csv.DictReader(open(uvp)):
			uv[r["path"]] = r
	cols = ["asset", "category", "kind", "tris", "texture", "uv_islands", "uv_coverage", "normal_tilt", "albedo",
		"geometry", "silhouette", "texture_q", "material", "animation", "lod", "consistency", "performance", "overall",
		"priority", "actions", "status", "notes"]
	rows = []
	for rel, (sc, pri, act, status, note) in A.items():
		path = "assets/models/" + rel
		m = audit.get(path, {})
		u = uv.get(path, {})
		vals = [s for s in sc if s > 0]
		rows.append([rel, m.get("category", ""), "glb", m.get("tris", ""), m.get("max_tex", ""), u.get("islands", ""),
			u.get("coverage", ""), u.get("normal_tilt", ""), u.get("albedo_lum", "")] +
			[s if s > 0 else "" for s in sc] + [round(sum(vals) / len(vals), 1), pri, act, status, note])
	missing = sorted(set(p[len("assets/models/"):] for p in audit) - set(A))
	for rel in missing:
		rows.append([rel, audit["assets/models/" + rel].get("category", ""), "glb", audit["assets/models/" + rel].get("tris", ""),
			"", "", "", "", ""] + [""] * 8 + ["", "", "", "Not inspected", "added after the audit"])
	for pid, cat, sc, pri, act, status, note in P:
		vals = [s for s in sc if s > 0]
		rows.append([pid, cat, "code"] + [""] * 6 + [s if s > 0 else "" for s in sc] + [round(sum(vals) / len(vals), 1), pri, act, status, note])
	rows.sort(key=lambda r: (r[18], r[17] if r[17] != "" else 9, r[0]))
	os.makedirs(os.path.dirname(out), exist_ok=True)
	with open(out, "w", newline="") as f:
		w = csv.writer(f, lineterminator="\n")
		w.writerow(cols)
		w.writerows(rows)
	by = {}
	for r in rows:
		by[r[20]] = by.get(r[20], 0) + 1
	print("%d assets: %s" % (len(rows), ", ".join("%s %d" % (k, by[k]) for k in STATUSES if k in by)))
	if missing:
		print("not assessed:", missing)


if __name__ == "__main__":
	main()

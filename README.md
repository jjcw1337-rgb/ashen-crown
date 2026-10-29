# Ashen Crown — Act I: The Ashen Moors

An isometric action RPG in the spirit of Diablo II, built in Godot 4.3 (Forward+ renderer).
Every model, texture, sound and piece of music is generated in code. There are no art files.

## Play

**In a browser (quick test build):** https://jjcw1337-rgb.github.io/ashen-crown/ is a lighter version: graphics up to Medium, no intro and no co-op. Downloads for the full game are at that same address: `AshenCrown-Windows.zip`, `AshenCrown-Linux.zip`, `AshenCrown-Mac.zip`.

The game opens with the trailer; press any key to skip it.


**Linux:** download `AshenCrown-Linux.zip` from the same address, unzip it and run `./AshenCrown.x86_64` (run `chmod +x AshenCrown.x86_64` first if it won't start).

**Mac:** download `AshenCrown-Mac.zip` from the game's GitHub Pages address, unzip it and move **Ashen Crown** to Applications. It isn't notarized by Apple, so the first time macOS will refuse to open it: go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. (Or in Terminal: `xattr -dr com.apple.quarantine "/Applications/Ashen Crown.app"`.)

**Windows:** unzip `AshenCrown-Windows.zip` and run `AshenCrown.exe`.

Windows SmartScreen may warn that the app is unrecognised (it isn't code-signed). Choose **More info → Run anyway**.

**Black screen, or the picture looks wrong?** Run **`Ashen Crown (Safe Mode).bat`** instead. It starts the game with the OpenGL renderer, which works on almost every laptop. The game also checks for a black screen when you enter an outdoor area and lowers the graphics setting by itself if it finds one.

**From source:** install [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/), open `project.godot`, press F5.

## Classes

**New Game** lets you choose:

- **Knight**: sword and shield. *Holy Slam* (Q), *Holy Nova* (E), *Charge* (R), *Battle Cry* (F).
- **Wraith**: a hooded spirit that floats above the ground, trailing mist.
  - *Soul Reap* (Q): a spectral scythe arc. Every soul it cuts flies back and heals you.
  - *Banshee Wail* (E): a scream that hurls enemies back and freezes them in terror.
  - *Shadow Step* (R): melt into shadow and re-form at the cursor. The shade left behind implodes.
  - *Spectral Host* (F): three spirits circle you for 12 seconds, darting out to strike enemies.

- **Demon**: a horned, winged fiend in obsidian plate with ember-edged horns, spikes, claws and wings.
  - *Hellfire Claw* (Q): three burning rakes that set enemies alight.
  - *Summon Demon* (E): a demon climbs out of a burning sigil to fight beside you, up to 3 at once (a fourth replaces the oldest). They follow you between areas.
  - *Underworld Phase* (R): for 6 seconds you walk in the Underworld. The act turns bone-and-violet with soul-light veins and crimson rune rings, monsters glow and can't see or hurt you, and you move faster. When you return, the rift erupts around you.
  - *Blood Pact* (F): pay 20% of your life for +40% damage for you and your demons for 12 seconds.

- **Warlock**: a gnome warlock in deep purple robes under a towering horned hat, with fel-green eyes, a braided beard hung with silver rings and tiny skulls, runed robes and a chained spellbook, fel fire in one hand and a grimoire floating at his shoulder. (His model was generated with [Meshy](https://www.meshy.ai) from a Meshy concept image, then rigged in Blender.)
  - *Drain Life* (Q): a green beam latches onto an enemy and pulls its life out, forking to up to 3 enemies around it. Everything it drains heals you. Hold Q to keep draining (costs mana each second); if the victim dies the beam jumps to the next one. Moving breaks it.
  - *Blight Bolt* (E): a skull of blight that bursts on impact and leaves a plague pool, rotting enemies in it for 4 seconds.
  - *Soul Shackles* (R): chains of fel fire bind every enemy within 7 metres for 2.5 seconds.
  - *Fel Covenant* (F): +40% damage for 12 seconds; Drain Life forks to two more enemies and heals twice as much.

Every class has four skills on Q E R F, unlocking at levels 1, 3, 6 and 10. Your class is saved with your character, and co-op partners see it.

**Talents** (press **N**): every class has three talent trees, each with seven talents in four rows, ending in a capstone. You get a talent point every level from level 2; left-click a talent to learn a rank, right-click to take it back. A row opens once you've spent enough points above it in that tree (3, 6, then 10 for the capstone). **Reset** gives every point back for free, and **Auto-assign** spends your points on a suggested build. Characters from before talents arrived got a build picked for their class and level; reset it if you want your own.

- Knight: *Crusader* (Holy Slam and Holy Nova), *Bulwark* (defense, shield and Battle Cry healing), *Vanguard* (Charge, the sword combo, Battle Cry).
- Wraith: *Reaper* (Soul Reap, crits), *Banshee* (Banshee Wail, Shadow Step), *Revenant* (Spectral Host, toughness).
- Demon: *Hellfire* (Hellfire Claw, fury), *Summoner* (your demons, Blood Pact, a fourth demon), *Underworld* (Underworld Phase, obsidian hide).
- Warlock: *Affliction* (Drain Life), *Plague* (Blight Bolt and its pools), *Binding* (Soul Shackles, Fel Covenant, fel wards).

## Co-op (two to four players on the same home network)

1. On the first computer, pick **Host Co-op Game** on the title screen.
2. On the second computer, pick **Join Co-op Game**. The host's game appears in the list within a second or two; click it. If it doesn't appear, type the address shown at the top left of the host's screen (for example `192.168.1.23`) and press **Join**.
3. The first time, **Windows Firewall** asks whether to allow Ashen Crown on each computer. Tick **Private networks** and click **Allow**, or co-op can't connect.

How it works:

- Each player brings their own saved knight (or a new one if there's no save) and keeps their own gold, gear and inventory.
- Monster drops are shared: whoever picks an item up first gets it. Gold, chests and shrines work the same way.
- Everyone gets experience for every kill.
- The party stays together. When anyone walks through an exit, takes a waypoint or uses a portal, everyone travels.
- If you die, **Respawn** brings you back next to your partner. If everyone is down, the party returns to town.
- Esc doesn't pause the game in co-op.

## Controls

| Input | Action |
|---|---|
| Left-click | Move / attack / pick up / talk (hold to keep moving or attacking). Attacking is a three-swing sword combo: a diagonal cut, a rising cut, then a spinning finisher that hits everything around you; keep clicking or hold to chain it |
| WASD | Move directly (you can keep moving while attacking) |
| Shift (hold) | Sprint. Drains the yellow stamina bar, also works mid-attack |
| Space (hold) | The same combo the way you face, without needing a target |
| Right-click (hold) | Raise shield. Blocks most melee damage and stops arrows and fireballs from the front |
| Q | Holy Slam: leap at the cursor and slam the sword down in a burst of white light; knocks enemies back and stuns them for 1 second (level 1) |
| E | Holy Nova: ring of holy fire (level 3) |
| R | Charge: dash through enemies (level 6) |
| F | Battle Cry: +40% damage and defense, stuns nearby enemies (level 10) |
| 1–4 | Drink potion from belt |

Space and the skill keys fire the way your hero is facing (for every class), bending slightly onto an enemy just ahead. Shadow Step is the one skill that goes to the cursor.
| I | Inventory |
| C | Character sheet (spend stat points) |
| K | Skills: put any skill on a mouse button or Q E R F G V (or drag it onto the bar) |
| N | Talents |
| T | Town portal |
| Alt (hold) | Show all item names on the ground |
| M | Toggle minimap |
| Tab | Toggle the large map |
| Mouse wheel | Zoom |
| F3 | FPS counter |
| Esc | Close panels / pause menu (graphics quality, save and quit) |

Skill bar: drag a skill from the skills window (K) onto a slot, drag one slot onto another to swap them, or drag a skill off the bar to clear it. Clicking a slot opens a list to choose from.

Inventory: click an item to equip it (or an equipped item to take it off). **Drag** an item to another bag slot to move it, onto your equipment to wear it, or out of the window onto the game world to drop it on the ground. Right-click to drink, sell (at a merchant) or store (at the stash). Ctrl-click also drops.

The action bar shows your **experience** (violet, with your level and progress) and **stamina** (green; it turns orange and reads "Winded" when you run out, and glows while you sprint).

## What's in Act I

- **Greywatch Camp (town):**
  - Old Maeve's alchemy camp: potions, rings and amulets.
  - Grisold's forge: weapons and shields.
  - Hedda's armory: helms, body armor, gloves, boots and belts.
  - Tarrow's gambling tent.
  - Stash, waypoint, and Captain Roth.
- **Cairnfell Moor (wilderness):**
  - A winding road past a standing-stone circle and a graveyard.
  - Shrines, chests, a waypoint and roaming packs, including blue-glowing champion packs.
- **Grubb's Fort (dungeon):** the goblin king Grubb's stronghold of sharpened logs at the end of the moor. You arrive to find his guards holding the gate against the moor's dead; both sides will fight you too. Inside, the goblins live among huts, tents, cookfires, cages and stolen loot, round an open courtyard of heaped gold, open chests, a throne of chests and goblin tunnels in the ground. There sits **King Grubb the Gilded**, a fat, greedy goblin under a stack of stolen crowns, with three sacks of gold on his back and a vault key the size of a club. His **Gold Grabbers** stand guard.
  - The one rule: **his gold is his life.** Every pile you take from him hurts him; every pile that reaches him heals him.
  - He swings and slams with his key and lobs **Gilded Bombs** at you. A red circle marks where each one lands; get out before it blows.
  - At 75%, 50% and 25% of his life (the gold notches on his health bar) one of his sacks rips open. Gold sprays across the vault in glowing piles and more Gold Grabbers climb out of the tunnels. Everyone scrambles for it: grabbers scoop a pile and haul it back to him over their heads, and he waddles from pile to pile scooping it up himself.
  - **Step on a pile:** the gold is yours, and he shrieks and loses a chunk of life. Kill a grabber hauling gold and it drops it for you. His bombs hurt his own goblins too.
  - King Grubb's model was generated with [Meshy](https://www.meshy.ai) from a Meshy concept image, then rigged in Blender.
  - When the gold is gone the fight goes on. After the last sack he's broke and furious: faster, and three bombs at a time. When he dies his hoard bursts open.

**A2:** after you defeat King Grubb, the victory screen offers **Begin A2**. Everyone starts over at Greywatch Camp with their knight, gear, gold and level. Waypoints and the boss reset. In A2:

- Monsters have 6 times the life and armor (King Grubb 4 times) and 5 times the damage, and give 5 times the experience.
- Every item they drop has 5 times the flat stats (damage, defense, life, attributes and other flat bonuses), marked "A2 item" in its tooltip. Percentage bonuses (enhanced damage and defense, attack speed, life steal, resist, block, magic and gold find, run speed) stay as rolled.

**Winter in A2:** A2 is snowed in. The camp and the moor are buried in snow (with packed slush on the roads), trees and rooftops carry snow, the grass pokes through frosted, snow falls around you, your knight leaves footprints and his breath steams in the cold. On Ultra the snowfall is at its heaviest. The crypt stays as it is.

**A3:** beating A2 offers **Begin A3**. Everyone starts over again with their knight, and it stacks on top of A2:

- Monsters have 24 times the life of Act I (the Ashen King 10 times) and 15 times the damage, and give 25 times the experience.
- Drops have 25 times the flat stats of Act I, marked "A3 item".
- King Grubb is gone. His vault is now the **Throne of the Ashen King**, a giant crowned skeleton with a burning sword. He swings, slams, throws fireballs, casts a fire nova and raises bone archers.
- He always drops his own unique sword, **Cinderbrand, the King's Edge**, at A3 strength. It never drops anywhere else.
- Beating A3 offers "Play A3 again".

**A3 is burning:** the camp and the moor are scorched and on fire. Tents, banners and planks have holes burned through them with glowing edges, the ground is charred black and grey with glowing cracks, the forest is burned to black skeletons (some still smouldering), ash falls, embers rise, and smoke columns climb beyond the trees under a blood-orange sky.

**Armor enchanting:** talk to Hedda the armorer and pick **Enchant armor**. Pay gold to enchant your worn helm, body armor, gloves, boots, belt or shield, up to +10. Each level adds 15% defense and extra life (more on A2/A3 gear). Costs rise with each level and with the item's value. Gear at +5 or higher gains a blue arcane glow. Enchant levels show in the item's name and tooltip.

**Switching acts:** once you've unlocked A2 or A3, the waypoint in Greywatch Camp has a **Switch act** row with Act I, A2 and A3. Each act keeps its own waypoints and boss progress; your knight, gear and gold come with you. In co-op the host's game decides, and either player can switch.

Because A2 and A3 multiply every bonus, a few percentages are capped: attack speed at +120%, life steal at 25% and run speed at +100%. Resistances (75%) and block (60%) were already capped.

In co-op, the host's choice applies to everyone. Area names show "· A2" or "· A3".

Loot comes in Normal, Magic, Rare and Unique quality, with 18 kinds of affixes and 10 named uniques. Every item type has its own 3D model. Equipped weapons, shields, helms, armor, gloves, boots, belts and amulets all appear on your character.

## Graphics settings

Esc → Graphics cycles Low / Medium / High / Ultra. The setting is remembered on each computer, and the pause menu shows which graphics card and renderer the game is using. Grass density changes when you next enter an area.

- **Low:** 2x MSAA, light grass, no ambient occlusion or fog effects.
- **Medium (default on laptops with built-in graphics):** adds ambient occlusion.
- **High (default with a dedicated graphics card):** full grass, volumetric fog, screen-space indirect light, 4x MSAA and higher-resolution shadows.
- **Ultra (default on RTX 30/40/50 and recent Radeon cards):** 1.7x denser grass drawn farther out, grass shadows, real-time bounce lighting (SDFGI), 8x MSAA, 8K soft shadows, finest ambient occlusion and fog, and screen-space reflections.

Vegetation is all generated: pines with branch whorls and needle sprays, gnarled dead trees, leafy moor oaks, bushes, ferns, and grass with wildflowers, all swaying in the wind. Co-op players can use different settings; only grass density differs between them.

V-sync is on, so the game runs at your monitor's refresh rate (60+ fps on a mid-range GPU at High).

## Project layout

- `scripts/game.gd`: main loop, camera, input, zones, saving
- `scripts/world.gd`: terrain, town layout, wilderness and dungeon generation, pathfinding
- `scripts/models.gd`, `props.gd`: procedural 3D models (characters, items, buildings, props)
- `scripts/anim.gd`: procedural attack, block, walk and death animation
- `scripts/hero.gd`, `enemy.gd`: player and monster logic
- `scripts/items.gd`, `data.gd`: loot generation and game data (acts 2–4 data is already defined)
- `scripts/mats.gd`: shaders (terrain, grass, water, lava, cloth, orbs)
- `scripts/ui.gd`: HUD and menus · `scripts/sfx.gd`: synthesised audio

## Building on it

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: open `project.godot` in Godot 4.3, change things, push to `main`, and the online version and the Windows download rebuild themselves in a few minutes.

## Settings and testing keys

- **F2** or **Esc → Sound**: turn all sound on or off (remembered between sessions).
- **F3**: FPS counter.
- **F8** or **Esc → Testing panel** (only while `UNLOCK_ALL_ACTS` is on): switches for **Immortal**, **One-hit kill**, **Infinite stamina** and **Unlock all skills** (use every skill at any level), plus a **Level** box: type a level (1–99) and press **Set**. The switches aren't saved; a level change is (raising it gives the usual 5 stat points per level).

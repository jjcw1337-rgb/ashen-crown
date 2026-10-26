# Ashen Crown — Act I: The Ashen Moors

An isometric action RPG in the spirit of Diablo II, built in Godot 4.3 (Forward+ renderer).
Every model, texture, sound and piece of music is generated in code. There are no art files.

## Play

**In a browser (quick test build):** https://jjcw1337-rgb.github.io/ashen-crown/ is a lighter version: lower graphics, no grass blades, no intro and no co-op. Downloads for the full game are at that same address: `AshenCrown-Windows.zip`, `AshenCrown-Linux.zip`, `AshenCrown-Mac.zip`.

The game opens with the trailer; press any key to skip it.


**Linux:** download `AshenCrown-Linux.zip` from the same address, unzip it and run `./AshenCrown.x86_64` (run `chmod +x AshenCrown.x86_64` first if it won't start).

**Mac:** download `AshenCrown-Mac.zip` from the game's GitHub Pages address, unzip it and move **Ashen Crown** to Applications. It isn't notarized by Apple, so the first time macOS will refuse to open it: go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. (Or in Terminal: `xattr -dr com.apple.quarantine "/Applications/Ashen Crown.app"`.)

**Windows:** unzip `AshenCrown-Windows.zip` and run `AshenCrown.exe`.

Windows SmartScreen may warn that the app is unrecognised (it isn't code-signed). Choose **More info → Run anyway**.

**Black screen, or the picture looks wrong?** Run **`Ashen Crown (Safe Mode).bat`** instead. It starts the game with the OpenGL renderer, which works on almost every laptop. The game also checks for a black screen when you enter an outdoor area and lowers the graphics setting by itself if it finds one.

**From source:** install [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/), open `project.godot`, press F5.

## Classes

**New Game** lets you choose:

- **Knight**: sword and shield. *Cleave* (Q), *Holy Nova* (E), *Charge* (R), *Battle Cry* (F).
- **Wraith**: a hooded spirit that floats above the ground, trailing mist.
  - *Soul Reap* (Q): a spectral scythe arc. Every soul it cuts flies back and heals you.
  - *Banshee Wail* (E): a scream that hurls enemies back and freezes them in terror.
  - *Shadow Step* (R): melt into shadow and re-form at the cursor. The shade left behind implodes.
  - *Spectral Host* (F): three spirits circle you for 12 seconds, darting out to strike enemies.

Your class is saved with your character, and co-op partners see it.

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
| Left-click | Move / attack / pick up / talk (hold to keep moving or attacking) |
| WASD | Move directly (you can keep moving while attacking) |
| Shift (hold) | Sprint. Drains the yellow stamina bar, also works mid-attack |
| Space (hold) | Swing toward the cursor without needing a target |
| Right-click (hold) | Raise shield. Blocks most melee damage and stops arrows and fireballs from the front |
| Q | Cleave: wide arcing blow (level 1) |
| E | Holy Nova: ring of holy fire (level 3) |
| R | Charge: dash through enemies (level 6) |
| F | Battle Cry: +40% damage and defense, stuns nearby enemies (level 10) |
| 1–4 | Drink potion from belt |
| I | Inventory |
| C | Character sheet (spend stat points) |
| T | Town portal |
| Alt (hold) | Show all item names on the ground |
| M | Toggle minimap |
| Tab | Toggle the large map |
| Mouse wheel | Zoom |
| F3 | FPS counter |
| Esc | Close panels / pause menu (graphics quality, save and quit) |

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
- **Crypt of the Matron (dungeon):** a chain of torch-lit tomb rooms ending in the boss chamber of **The Hollow Matron**. She has scythe slams with ground warnings, summons zombies and becomes enraged at low health.

**A2:** after you defeat the Hollow Matron, the victory screen offers **Begin A2**. Everyone starts over at Greywatch Camp with their knight, gear, gold and level. Waypoints and the boss reset. In A2:

- Monsters have 20 times the life, damage and armor, and give 5 times the experience.
- Every item they drop has 5 times the stats (damage, defense and all bonuses), marked "A2 item" in its tooltip.

**Winter in A2:** A2 is snowed in. The camp and the moor are buried in snow (with packed slush on the roads), trees and rooftops carry snow, the grass pokes through frosted, snow falls around you, your knight leaves footprints and his breath steams in the cold. On Ultra the snowfall is at its heaviest. The crypt stays as it is.

**A3:** beating A2 offers **Begin A3**. Everyone starts over again with their knight, and it stacks on top of A2:

- Monsters are 400 times stronger than Act I (20× A2) and give 25 times the experience.
- Drops are 25 times stronger than Act I (5× A2), marked "A3 item".
- The Hollow Matron is gone. Her crypt is now the **Throne of the Ashen King**, a giant crowned skeleton with a burning sword. He swings, slams, throws fireballs, casts a fire nova and raises bone archers.
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
- **F8** or **Esc → Testing panel** (only while `UNLOCK_ALL_ACTS` is on): switches for **Immortal** and **One-hit kill**. Nothing else changes and they aren't saved.

# Ashen Crown — Act I: The Ashen Moors

An isometric action RPG in the spirit of Diablo II, built in Godot 4.3 (Forward+ renderer).
Every model, texture, sound and piece of music is generated in code. There are no art files.

## The game

Ashen Crown is a dark-fantasy action roguelite. You build a hero over one run, then bring it into the
fights that matter.

1. **The Battlegrounds run (PvE roguelite).** Everyone drops into the same open map (the Verdant Reach)
   at level 0 with only a basic attack. You grow by clearing **camps**: packs of monsters guarding a
   sealed chest. When a camp falls, each player picks **1 of 3** prizes from the chest:
   - **Skills**: active abilities. You have five slots (right mouse and Q E R F).
   - **Rites**: passives and power-ups that stack (+damage, longer curses, cheaper spells...).

   The camp sets the odds. Common camps mostly offer common picks; harder camps and bosses roll more
   uncommon and rare ones. Chests also give **consumables**, which come in three kinds:
   - **Items**: reusable on a cooldown, like a smoke bomb or a grappling hook.
   - **One-shot consumables**: potions and flasks that stack on the belt.
   - **Gems**: one-of-a-kind power-ups that bend a build, like relics.

   Other players are in the same map, so the run is PvPvE. Reach an extraction portal to keep your hero.
2. **Then take the hero further.** A hero who extracts is saved as a survivor and can be taken into the
   **waves** (co-op against an endless horde) and into **PvP** (the Arena: 1v1, 2v2, 3v3).

### Heroes: three directions each

Every hero is designed around **three major directions** a run can take. They become the hero's three
groups of skills and rites (in code, the three `Talents.TREES` per class). A run that keeps picking one
direction becomes that kind of hero. The Warlock's three directions:

- **Corruption**: stacking damage-over-time curses.
- **Fear**: crowd control.
- **Drain**: life drain that overflows into shields.

A new hero needs its three directions before its skills.

### The Hero Codex

Every hero's skills, rites and gems, the shared skills and rites, and the items and consumables are
listed in one place: `data/codex/` (JSON). **The game loads them from there** (`scripts/codex.gd`), so
the Codex is the game's data, not a copy of it. The Codex editor (`tools/codex/server.py`, see
`tools/codex/README.md`) lists and edits it in the browser, and saving commits the change.

Entries marked *in game* already work, and editing one changes the game. *Design* entries are ideas
waiting for their code. A new rite made only of stats the game already reads goes live straight away.

## Play

**In a browser (quick test build):** https://jjcw1337-rgb.github.io/ashen-crown/ is a lighter version: graphics up to Medium, no intro and no co-op. Downloads for the full game are at that same address: `AshenCrown-Windows.zip`, `AshenCrown-Linux.zip`, `AshenCrown-Mac.zip`.

The game opens with the trailer; press any key to skip it.


**Linux:** download `AshenCrown-Linux.zip` from the same address, unzip it and run `./AshenCrown.x86_64` (run `chmod +x AshenCrown.x86_64` first if it won't start).

**Mac:** download `AshenCrown-Mac.zip` from the game's GitHub Pages address, unzip it and move **Ashen Crown** to Applications. It isn't notarized by Apple, so the first time macOS will refuse to open it: go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. (Or in Terminal: `xattr -dr com.apple.quarantine "/Applications/Ashen Crown.app"`.)

**Windows:** unzip `AshenCrown-Windows.zip` and run `AshenCrown.exe`.

Windows SmartScreen may warn that the app is unrecognised (it isn't code-signed). Choose **More info → Run anyway**.

**Black screen, or the picture looks wrong?** Run **`Ashen Crown (Safe Mode).bat`** instead. It starts the game with the OpenGL renderer, which works on almost every laptop. The game also checks for a black screen when you enter an outdoor area and lowers the graphics setting by itself if it finds one.

**From source:** install [Godot 4.4.1](https://godotengine.org/download/archive/4.4.1-stable/), open `project.godot`, press F5.

## Classes

**New Game** lets you choose:

- **Knight**: sword and shield. *Holy Slam* (Q), *Holy Nova* (E), *Charge* (R), *Battle Cry* (F).
- **Wraith**: a horned spirit in chains that floats above the ground, trailing mist.
  - *Spectral Rend* (Q): lunge at the foe ahead and tear through it with spectral claws, twice. Every soul torn out flies back and heals you.
  - *Soul Siphon* (E): hook a tether into an enemy: it stands rigid while its soul is drained into you, and is slowed after.
  - *Shadow Step* (R): come apart into mist and re-form at the cursor with a spinning claw strike. For a moment after, blows pass through you; the shade left behind collapses.
  - *Haunting Grasp* (F): spectral hands burst out of the earth around the cursor, drag enemies in and hold them.
  - *Phantom Assault* (G, level 14): three phantoms streak through the enemies ahead, then your own claws land.
  - *Eternal Night* (V, level 18): rise and bring down the night: a scream of terror, the dark feeding on everything in it while you hang untouchable above, and its collapse into your slam. +40% damage after.

- **Demon**: a horned, winged magma brute. One job per skill, built for PvP:
  - *Molten Fists* (Q): a slow, heavy two-fisted blow (your fists catch fire as you draw back; dodge to cancel it) that cracks the ground open in a wedge and sets it alight. Branded enemies take more.
  - *Infernal Charge* (E): paws the ground (the path burns where everyone can see it), then charges; it stops on the first champion or player, staggering and Branding them.
  - *Fault of the Pit* (R): splits the ground in a line across your aim; after a glowing warning it erupts, throws enemies up and Brands them, and stays molten for 4 seconds.
  - *Brimstone Hurl* (F): lob a molten boulder that lands under a mark, Brands a direct hit and shatters into burning shards. No cooldown: throw as fast as the throw allows.
  - *Hellgrip* (G): hurl a chain with an iron claw; the first enemy it hooks is dragged in and smashed. Bosses drag you to them.
  - *Wrath of the Pit* (V): kneel inside a cage of obsidian crystals that glows hotter with every blow you take (half damage, unstoppable), then burst it apart, terrifying everyone near you, and burn white-hot for 6 seconds while meteors fall.

Every class has four skills on Q E R F, unlocking at levels 1, 3, 6 and 10. Your class is saved with your character, and co-op partners see it.

**Talents** (press **N**): every class has three talent trees, each with seven talents in four rows, ending in a capstone. You get a talent point every level from level 2; left-click a talent to learn a rank, right-click to take it back. A row opens once you've spent enough points above it in that tree (3, 6, then 10 for the capstone). **Reset** gives every point back for free, and **Auto-assign** spends your points on a suggested build. Characters from before talents arrived got a build picked for their class and level; reset it if you want your own.

- Knight: *Crusader* (Holy Slam and Holy Nova), *Bulwark* (defense, shield and Battle Cry healing), *Vanguard* (Charge, the sword combo, Battle Cry).
- Wraith: *Render* (Spectral Rend, crits), *Shadow* (Soul Siphon, Shadow Step), *Night* (Haunting Grasp, Phantom Assault, Eternal Night, toughness).
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
| WASD | Move directly. You keep moving while you attack or cast, in any direction: the mouse aims, the keys move |
| Shift (hold) | Sprint. Drains the yellow stamina bar, also works mid-attack |
| Space (hold) | The same combo toward the cursor, without needing a target |
| Right-click (hold) | Raise shield. Blocks most melee damage and stops arrows and fireballs from the front |
| Q | Holy Slam: leap at the cursor and slam the sword down in a burst of white light; knocks enemies back and stuns them for 1 second (level 1) |
| E | Holy Nova: ring of holy fire (level 3) |
| R | Charge: dash through enemies (level 6) |
| F | Battle Cry: +40% damage and defense, stuns nearby enemies (level 10) |
| 1–4 | Drink potion from belt |

The mouse aims everything, for every class: arrows, bolts, beams, charges and swings go from your hero toward the cursor, and skills that land on the ground (Frost Volley, Haunting Grasp, Brimstone Hurl, the flasks...) land on it, up to their range. Which way your hero is facing or walking doesn't matter, so you can run one way with WASD and shoot the other. Close-range blows bend slightly onto an enemy right next to the cursor's line.
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

Traders: talk to anyone with a nameplate, then **Trade**. The trade window shows who you're dealing with, their goods by kind (tabs) and each item's price (red when you can't afford it). Walk away and it closes.

Inventory: click an item to equip it (or an equipped item to take it off). **Drag** an item to another bag slot to move it, onto your equipment to wear it, or out of the window onto the game world to drop it on the ground. Right-click to drink, sell (at a merchant) or store (at the stash). Ctrl-click also drops.

The action bar shows your **experience** (violet, with your level and progress) and **stamina** (green; it turns orange and reads "Winded" when you run out, and glows while you sprint).

## What's in Act I

- **The Forsaken Wilds (the camp, deep in the forest):**
  - Agnes Grimwood's alchemy camp: potions, rings and amulets.
  - Halvar Emberhammer's forge: weapons and shields (he works at his anvil inside it).
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

**A2, the Imperial Road:** after you defeat King Grubb, the victory screen offers **Begin A2**. Everyone starts over at the camp in the Forsaken Wilds with their knight, gear, gold and level, and the road north leads somewhere new:

- **The Imperial Road**: a longer, wider road under a warm late-afternoon sun. It starts on the moor (the restless dead and the moor's creatures), runs through a rocky pass where **bandits lie in wait** around an overturned wagon and spring out from behind the rocks when you stop to look, then becomes the old Roman road: paving and milestones, tombs along both verges, cypresses, toppled columns and an aqueduct you walk beneath. Near the city, bandits hold the road between ruined colonnades and statues, and a triumphal arch leads into Aurelia.
- **Aurelia**: a city run by bandits. In through the gate, up the colonnaded main street past shops, apartment blocks, a temple and a market to the old arena, where **Varro the lanista** offers you a place in the games.
- **The games**: the Gate of Life shuts behind you and the crowd roars. Fight through the stages: **the lions**, **the gladiators**, **the beasts of the pit** (with the pit's spike traps: step out of the glowing circles), and finally **Aurelius, Champion of the Arena**, who charges across the sand behind his shield and calls lions and his gladiator brothers as he weakens. Beat him to finish A2. If you fall, Varro will take another wager.
- Monsters have 6 times the life and armor (bosses 4 times) and 5 times the damage, and give 5 times the experience.
- Every item they drop has 5 times the flat stats (damage, defense, life, attributes and other flat bonuses), marked "A2 item" in its tooltip. Percentage bonuses (enhanced damage and defense, attack speed, life steal, resist, block, magic and gold find, run speed) stay as rolled.

**A3:** beating A2 offers **Begin A3**. Everyone starts over again with their knight, and it stacks on top of A2:

- Monsters have 24 times the life of Act I (the Ashen King 10 times) and 15 times the damage, and give 25 times the experience.
- Drops have 25 times the flat stats of Act I, marked "A3 item".
- King Grubb is gone. His vault is now the **Throne of the Ashen King**, a giant crowned skeleton with a burning sword. He swings, slams, throws fireballs, casts a fire nova and raises bone archers.
- He always drops his own unique sword, **Cinderbrand, the King's Edge**, at A3 strength. It never drops anywhere else.
- Beating A3 offers "Play A3 again".

**A3 is burning:** the camp and the moor are scorched and on fire. Tents, banners and planks have holes burned through them with glowing edges, the ground is charred black and grey with glowing cracks, the forest is burned to black skeletons (some still smouldering), ash falls, embers rise, and smoke columns climb beyond the trees under a blood-orange sky.

**Armor enchanting:** talk to Hedda the armorer and pick **Enchant armor**. Pay gold to enchant your worn helm, body armor, gloves, boots, belt or shield, up to +10. Each level adds 15% defense and extra life (more on A2/A3 gear). Costs rise with each level and with the item's value. Gear at +5 or higher gains a blue arcane glow. Enchant levels show in the item's name and tooltip.

**Switching acts:** once you've unlocked A2 or A3, the camp's waypoint has a **Switch act** row with Act I, A2 and A3. Each act keeps its own waypoints and boss progress; your knight, gear and gold come with you. In co-op the host's game decides, and either player can switch.

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

### On-demand multiplayer preview

The post-intro Multiplayer browser groups Battlegrounds, endless waves (The Last Flame), and
1v1/2v2/3v3 Arena behind a shared create/join/ready/start lobby flow. Waiting rooms are lightweight;
only started matches allocate a Godot process. See [multiplayer lobbies](docs/multiplayer_lobbies.md)
for selected-item arena stakes, local tests, capacity limits and the coordinated server rollout.
The old sandbox remains available for admin testing. This requires matching clients and the new
lobby service; it does not install or enable that service automatically.

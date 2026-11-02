Build a massive overhaul of the Battlegrounds map, its encounters, and its match flow. This should feel like a substantial new dungeon experience: sprawling, dangerous, atmospheric, and filled with distinctive places and enemies worth discovering.

Inspect the current implementation and available assets first, then carry the work through implementation, integration, and testing. Make thoughtful decisions wherever details are unspecified, including any necessary database changes.

**A much larger, deeper Battlegrounds**

Make the map significantly larger, with enough exploration and branching paths that players can get a little lost.

- Build three connected dungeon floors, with descents into levels two and three.
- Give each floor a distinct identity through its architecture, lighting, environmental storytelling, enemies, and landmarks.
- Include branching routes, side chambers, shortcuts, dangerous chokepoints, and larger spaces suitable for PvP and boss encounters.
- Make exploration rewarding while keeping navigation learnable. Use recognizable landmarks and environmental cues so the dungeon feels mysterious without becoming an indistinguishable maze.
- Design routes and points of interest that bring players into contact despite the increased size. Consider travel time, encounter placement, and opportunities for ambushes, escapes, and contested rewards.

Aim for the oppressive dungeon atmosphere and memorable zones associated with **Dark and Darker**. The environment should feel deliberately constructed, with strong visual identities and convincing connections between areas.

**Twenty-minute matches and clearer wave flow**

Set Battlegrounds matches to **20 minutes**, with a clear timer and understandable start and end states.

Overhaul how players join and how waves begin:

- Add a clear queue/lobby flow so a player can initiate a Battlegrounds run and other players can join.
- Make player-triggered wave starts explicit, with a clear interaction, preparation state, and countdown.
- Clearly communicate the current wave, when the next wave is starting, and whether players can still join.
- Inspect how waves currently work and choose a coherent relationship between the match queue, individual waves, and the 20-minute match timer.
- Make sensible decisions about readiness, late joining, disconnects, rejoining, and what happens when time expires.
- Keep match, queue, timer, and encounter state consistent across players. Implement the necessary server and database changes.

The entire flow should be understandable from the game interface.

**An actual, epic ice troll**

Add a distinctive ice troll with a proper model, animations, and a dedicated encounter space.

It should feel physically imposing and belong to a recognizable icy part of the dungeon. Give it a coherent combat identity, with heavy attacks, ice-themed abilities, readable windups, impactful effects, and opportunities for skilled counterplay.

Build a complete encounter around it: environment, movement space, sound, effects, combat behavior, and rewards.

**The thorn-covered hermit and golden chest**

Create a unique mushroom druid boss: a strange, gnome-like hermit living in an overgrown pocket of the dungeon.

The area should feel as though something alive has broken into and spread through the stone:

- Thorny grass sprawls out of the entrance and into surrounding corridors.
- Thick vines connect the chamber to the dungeon, crawling across walls, floors, and architectural details.
- Oversized mushrooms, fungal growths, and eerie lighting give the space a distinctive silhouette and atmosphere.
- A massive golden chest sits behind the hermit, visible enough to tempt players deeper into the encounter.

Give the hermit memorable spells and a complete boss fight. One signature mechanic must summon mushrooms that produce poison, changing which parts of the arena are safe. Make the poison and mushroom behavior readable, with meaningful ways for players to respond.

The golden chest starts locked and unlocks after the boss is defeated. Connect that behavior to authoritative encounter state so it works reliably in multiplayer.

**Assets and construction quality**

Use **Meshy and Blender** to create and finish the new assets this overhaul needs.

Reuse suitable existing assets, but create distinctive models and environmental pieces where they will materially improve the result—especially the bosses and their signature spaces.

Integrate assets properly: materials, textures, scale, orientation, animations, collision, and in-game lighting. Check how they look from the actual gameplay camera. Maintain a cohesive visual style and reasonable performance across the expanded dungeon.

Prioritize finished, memorable areas and characters. The ambition should be visible in the playable result.

**Integration and verification**

Integrate the new enemies, bosses, and rewards with the game’s existing progression and combat balance.

Play through the complete experience and verify:

- All three floors are reachable and navigable.
- Collision, enemy navigation, camera behavior, and floor transitions work.
- Queuing, wave starts, the 20-minute timer, and match endings work across players.
- Both bosses function, their abilities are readable, and the hermit’s chest unlocks correctly.
- The larger map supports actual PvP encounters and runs acceptably with its new assets and effects.

Deliver the implemented overhaul, then briefly explain the new map structure, match flow, encounters, database changes, and any remaining limitations.
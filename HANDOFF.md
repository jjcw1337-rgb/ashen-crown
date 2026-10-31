# Handoff to Blaine's Claude: the Fallen rework and the Forsaken Bear

From JJ (written by JJ's Claude, 2026-10-30). Repo: `jjcw1337-rgb/ashen-crown`, Godot 4.3.
Read `CLAUDE.md` first; the sections that matter most are "Act I monsters", "Blender assets", "The Feral", the A2 lion
and "Sound". Work on test branches only; nothing goes to `main` until JJ has played it and said "push it".
Ask JJ before spending any Meshy or ElevenLabs credits.

---

## Part 1: The Fallen, a complete rework

**What JJ wants:** rework the Fallen faction from the ground up as three genuinely different enemies: different
silhouettes, runs, signature attacks and AI. Not one model recoloured three times, and not the same AI with
different animations. All three must be real, reusable entries in the enemy roster (`Data.ENEMIES`) that spawn
through the normal system and can be used in any act. They must read clearly in actual gameplay: the player
should recognise each attack and be able to react.

### Already done: Meshy is finished, Blender is not started
Everything is on branch `jj-models`, folder `exports/fallen/`. JJ picked concept "A" for each.
| Enemy id | Name | Role | Signature attack | Raw Meshy model (A-pose, about 40k polys, textured) |
|---|---|---|---|---|
| `fallen_skirmisher` | Fallen Skirmisher | fast, aggressive melee | Savage Lunge | `skirm_meshy_raw.glb` |
| `fallen_reaver` | Fallen Reaver | heavy, brutal melee | Brutal Cleave | `reaver_meshy_raw.glb` |
| `fallen_stalker` | Fallen Stalker | erratic hunter | Hooking Slash | `stalk_meshy_raw.glb` |

Each model comes with its concepts (`*_concept_a/b.png`) and Meshy previews (`*_meshy_*.png`, `meshy_3d_sheet.png`).
The Meshy generation is paid for and complete: 126 credits, approved by JJ. **No more Meshy is needed** unless JJ
asks for matching Meshy weapons; if so, quote the cost first.

Problems in the raw models to fix in Blender:
- Meshy's A-pose mode **dropped the held weapons**: the Skirmisher has no sickle and the Reaver has no cleaver-axe.
  Give them weapons through `MeshyMonster`'s grips and the look's `"weapon"` (as the current Fallen holds its club),
  or as separate Meshy props if JJ approves. The Stalker fights with its long hooked claws, so it needs no weapon.
- The Skirmisher stands on a **round stone base**: cut everything below the hooves.
- Decimate each model to about 20k triangles.

### Steps
1. Start a branch `test-monsters` from the latest `origin/main`.
2. **Blender, one per model:** cut the base, decimate, then
   `blender -b --python tools/blender/act1/rig_monster.py -- <decimated.glb> assets/models/monsters/<kind>.glb layout.json [tex px] [hints]`
   and `python3 tools/blender/act1/layout_to_gd.py <kind> layout.json`.
   - Keep the `.blend` outside the repo, in `~/Documents/Blender/Game Factory/sources/`.
   - Use hints `{"sh_z", "sh_x"}` if the Stalker's hood and horn fool the neck finder.
   - Render a lineup and show JJ before wiring them in: `tools/monster_lineup.gd -- lineup.png <kinds>`.
3. **Roster:** add full entries for all three in `Data.ENEMIES`, modelled on `"zombie"` (mesh, name, rig `"humanoid"`,
   life, dmg, speed, range, xp, ai, atk, atk_time, armor, radius, blood, look).
   - Replace `"fallen"` in the acts' foe lists with the three (JJ's choice). Keep the old `"fallen"` entry, unused.
   - Starting stats are below. Tune them with `tools/balance.sh`; variety should come from behaviour, not inflated
     health or damage.
4. **Movement:** three different gaits in `scripts/anim.gd`, each picked by a `"gait"` meta on the rig, the way the
   knight's run is. Don't play one run at different speeds.
5. **Signature attacks:** a new style each in `Anim.pose` (`match style`), with its impact frame in `Anim.impact_at`.
   Add each new style to `Net.STYLES` so co-op partners see it.
6. **AI:** one function each in `scripts/enemy.gd`, called from `_think_combat` like `_feral_combat`: `ai` values
   `"skirmisher"`, `"reaver"`, `"stalker"`. Damage lands once, only in the attack window, and never on a dead or
   invalid target. Use the existing `go_to` and A* for navigation, and `stun`, hit flinch and death as they are.
7. **Tests:**
   - `tools/fallen_test.gd` (`[F]` lines) spawns each alone, then all three together, against a hero. It checks that
     each one acquires the hero, uses its own attack, hits only in the window (once), recovers, takes hits, dies,
     and doesn't get stuck.
   - `tools/monster_shot.gd` for screenshots.
   - A contact sheet `tools/fallen_sheet.gd` (run and attack rows, like `tools/lion_sheet.gd`).
   - Then `playtest`, plus any test that spawns Act I monsters.
8. **Don't touch `scripts/games.gd`:** the arena crowd adds finished models by itself.
9. Add a short entry to `CLAUDE.md`, commit, `git push origin HEAD:test-monsters`, and send JJ the Actions run link
   and the renders.

### The three, in detail (movement and skills)
Timings are fractions of the attack's duration (`atk` 0..1 in the pose). Distances are in metres. Treat these as
starting points and tune by eye.

**Fallen Skirmisher** (lean, wiry, sickle): fast, aggressive, unpredictable
- Stats: life about 14, dmg 3-6, speed 5.0, range 1.5, atk_time 0.9, armor 2.
- **Run (`gait` "skirm"):**
  - low and leaning forward hard (torso pitch about 0.35 rad), short rapid strides (about 1.4x cadence);
  - knees driving high, arms flailing out of sync, head jerking and scanning;
  - the sickle arm held back, ready.
  - Turns are snappy: face the move direction fast.
- **Savage Lunge (style `"skirm_lunge"`, about 0.9 s):**
  - 0-0.3: crouch and coil (hips drop about 0.15, weapon drawn back), a readable wind-up;
  - 0.3-0.5: launch, moving about 3.5 m along the ground toward the target (move it in `_update_attack` like
    `feral_lunge`; no teleporting);
  - 0.5: the slash; hit if the target is within 1.4 m and in front;
  - 0.5-1.0: stumble, a 0.6 s recovery opening where it's slow and turns slowly.
- **AI (`"skirmisher"`):** rush straight in; lunge from 2.5-5 m with a cooldown of about 3 s; short sidesteps between
  attempts; never stands still for long.

**Fallen Reaver** (stocky, spiked pauldron, cleaver-axe): heavy, punishes standing too close
- Stats: life about 45, dmg 8-14, speed 3.2, range 2.2, atk_time 1.6, armor 6.
- **Run (`gait` "reaver"):**
  - upright and broad, long forceful strides (about 0.8x cadence, bigger stride);
  - heavy footfalls (a vertical bob and a small dip on each), shoulders rolling with the weapon's weight;
  - the axe carried on the shoulder;
  - slow to accelerate and to turn.
- **Brutal Cleave (style `"reaver_cleave"`, about 1.6 s):**
  - 0-0.15: plant the feet and turn to the target;
  - 0.15-0.45: raise the axe high and twist back (a deliberate wind-up). Show the danger zone on the ground at
    0.15: a 120-degree arc out to 2.6 m, using `Fx.telegraph` or a new arc decal, sent through `_fx` so partners see it;
  - 0.45-0.6: the torso and shoulders whip round in a horizontal swing; hit at 0.52 for everyone in the arc;
  - 0.6-0.75: the follow-through carries the body round;
  - 0.75-1.0: a long recovery with the axe low, an opening.
- **AI (`"reaver"`):** walk in steadily (no circling); cleave when the target is within 2.4 m; after a cleave, stand
  for about 1 s.

**Fallen Stalker** (gaunt, hooded, long hooked claws): erratic, comes from unexpected angles
- Stats: life about 20, dmg 4-8, speed 4.4, range 1.6, atk_time 1.1, armor 3.
- **Run (`gait` "stalk"):**
  - low and hunched, long loping strides, lateral weaving (a sideways offset that sways about 0.8 m), occasional sharp
    direction changes;
  - the claws trailing low, the head tilted and twitching.
  - The weave must look intentional: a smooth sine with random direction flips every 1-2 s, not jitter. Keep the
    feet in step with the ground speed.
- **Hooking Slash (style `"stalk_hook"`, about 1.1 s):**
  - 0-0.25: shift sideways about 1.5 m, then drop low;
  - 0.25-0.45: dart in at an angle (about 40 degrees off the direct line);
  - 0.45: a diagonal hook from high on one side to low on the other; hit within 1.5 m in front;
  - 0.45-1.0: pull back about 1.5 m and recover.
- **AI (`"stalker"`):** circle at 4-6 m and pick a side; approach in arcs, never in a straight line; hook, then
  retreat and re-circle (`slot_a` and `f_state`, like the Feral).

Acceptance: all three have distinct models, runs, signature attacks and AI, and verified working roster entries.
Report what was tested, what passed, what couldn't be tested, and any credits spent.

---

## Part 2: The Forsaken Bear (Act I), mostly done; finish it

Branch `test-bear` (from `origin/test-crowd`, with `origin/main` merged in). Full details are in `HANDOFF_BEAR.md` on
that branch.

### Already done
- **Meshy:** concept 2, "corrupted ancient". The raw model is on `jj-models`, `exports/forsaken_bear/bear2_meshy_raw.glb`.
- **Blender:** `tools/blender/act1/rig_bear.py` rebuilds `assets/models/monsters/bear.glb` from the raw model:
  - cuts the slab and ground roots, decimates to 25k, sets 1.6 m at the shoulder;
  - 21 bones with the lion's names, plus `jaw` and the antlers;
  - surface-distance skinning.
- **Animation** (`scripts/bear.gd`, class `Bear`): the walk, rear up and roar, and the maul, all checked in renders.
- **Code** (compiles; not yet run in a game):
  - the enemy entry `"bear"`, the build and pose hooks;
  - the AI: wanders, roars now and then, roars once on noticing a hero, charges and mauls, gives up 30 m from home;
  - the maul's danger ring and 3 m arc hit, which knocks the hero back (`Hero.knock_v`);
  - co-op fx and styles.

### To finish
1. **Spawns:** 2 bears per Act I moor, 20-40 m off the road, kept out of the camp and the fort (copy `World._feral_packs`).
2. **`tools/bear_test.gd`:** check it spawns, wanders, rears and roars, notices, charges, mauls, damages and knocks
   back, and goes home when outrun.
3. **Sounds:** `bear_roar` and `bear_maul` through `tools/audio` (needs the ElevenLabs key). Give JJ 3 options of each.
   Until then it borrows the lion's roar pitched down and the boss slam.
4. **Polish:** a little hide stretches at the back of the neck at full rear-up. Lower `neck_x`/`head_x` in the roar,
   or soften the skin weights.
5. **Regression tests:** `playtest`, `feral_test`, `a2_arena_test`, `sound_test`, `tools/crowd_shot.gd`.
6. Push to `test-bear` and send JJ the link and renders.

---

## Tools on your machine
- **Blender 4.5:** `bash tools/blender/setup_blender.sh`.
- **Godot 4.3:** if `godot --headless --editor --quit` doesn't pick up new class names, run `godot --headless --import`.
- **JJ's Meshy key:** only for new generations, after asking JJ.
- **The ElevenLabs key:** for the bear's sounds.

## Heads-up
`main` now has the mocap knight, the attack pace (`Data.ATTACK_PACE`), the stacking damage numbers, the weapon draw,
the admin key and the waypoint TOWN tag. Rebase or merge `origin/main` into your branches before asking JJ to push.
`hero.gd`, `anim.gd`, `data.gd`, `enemy.gd` and `net.gd` are shared, so keep merges small and frequent.

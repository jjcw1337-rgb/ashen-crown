# The Fallen overhaul: handoff

From JJ's Claude to Blaine's Claude. JJ's full brief is the "COMPLETE THE FALLEN OVERHAUL" prompt; ask JJ for it.
Read CLAUDE.md first ("Act I monsters", "Blender assets"). Work on `test-monsters` (from the latest `origin/main`);
nothing goes to `main` without JJ's OK.

## JJ's picks (concept "A" of each; the "B" options are here for reference)
| Enemy id | Name | Role | Signature attack | Raw model (Meshy, A-pose) |
|---|---|---|---|---|
| `fallen_skirmisher` | Fallen Skirmisher | fast, aggressive melee | Savage Lunge | `skirm_meshy_raw.glb` (task 01a18bfc-5765-769c-83de-e1dbda9a2fcc) |
| `fallen_reaver` | Fallen Reaver | heavy, brutal melee | Brutal Cleave | `reaver_meshy_raw.glb` (task 01a18bfc-5786-718b-bcdd-bcd275f62cf6) |
| `fallen_stalker` | Fallen Stalker | erratic hunter | Hooking Slash | `stalk_meshy_raw.glb` (task 01a18bfc-5766-734c-8004-7dfdd964f28f) |

Each has 4 Meshy previews (`*_meshy_front/back/left/right.png`); `meshy_3d_sheet.png` shows all three side by side.
Meshy spent: 36 credits on the concepts and 90 on the 3D models. JJ approved this. Ask him before spending more.

## Known issues in the raw models
- Meshy's A-pose mode **dropped the held weapons**: the Skirmisher has no sickle and the Reaver has no axe. The
  Stalker's weapons are its claws, so it's fine. Give the two of them weapons through `MeshyMonster`'s grips and the
  look's `"weapon"`, the way the current Fallen holds its club. If JJ wants matching Meshy weapons, generate them as
  separate props, but ask first because that costs credits.
- The Skirmisher stands on a **round stone base**. Cut it off before rigging (everything below the hooves).
- Each model is about 40k polys; decimate to ~20k triangles.

## Steps
1. For each model: decimate to ~20k triangles, then
   `blender -b --python tools/blender/act1/rig_monster.py -- <decimated.glb> assets/models/monsters/<kind>.glb layout.json`
   and `python3 tools/blender/act1/layout_to_gd.py <kind> layout.json`.
   Keep the `.blend` in `~/Documents/Blender/Game Factory/sources/`. Use `[hints]` if the neck finder is fooled
   (the Stalker's hood and horn).
2. In `Data.ENEMIES`, add full entries `fallen_skirmisher`, `fallen_reaver` and `fallen_stalker`, modelled on `"zombie"`
   with `"mesh": "<kind>"`.
   - Act I foes: replace `"fallen"` with the three new ones (JJ's choice). Keep the old `"fallen"` entry in the list, unused.
3. Movement and attacks, each different (this is the main work; JJ wants it to read in real gameplay):
   - **Skirmisher**: a low, forward-leaning, frantic sprint. Savage Lunge: crouch, accelerate in, a committed strike,
     then a clear recovery window. No teleporting.
   - **Reaver**: a heavy charge with long strides and mass in the torso. Not the Skirmisher's run slowed down.
     Brutal Cleave: plant, raise the weapon, a horizontal swing with a danger zone on the ground, follow-through,
     long recovery.
   - **Stalker**: a low, erratic run with lateral weaving and sharp direction changes. Hooking Slash: shift sideways,
     drop low, dart in at an angle, a diagonal hook, pull back.
   - Each needs its own AI in `enemy.gd` (like `_feral_combat`) and its own `Anim` gait and attack styles. New styles
     go in `Net.STYLES` and `Anim.impact_at`. Damage lands once, in the attack window.
4. Tests: `tools/monster_lineup.gd -- lineup.png fallen_skirmisher fallen_reaver fallen_stalker`, `tools/monster_shot.gd`,
   a test that spawns all three together and checks each one's attack lands and recovers, then `playtest`.
5. Don't touch `scripts/games.gd`: the arena crowd picks up finished models by itself.
6. Commit, `git push origin HEAD:test-monsters`, and send JJ the run link and renders.

## Also open, in case it clashes
`test-bear` (the Forsaken Bear) also changes `enemy.gd`, `data.gd`, `anim.gd`, `net.gd` and `hero.gd`.
See `HANDOFF_BEAR.md` on that branch.

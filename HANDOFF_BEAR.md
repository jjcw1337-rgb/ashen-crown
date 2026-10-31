# Handoff: the Forsaken Bear (branch test-bear)

From JJ's Claude to Blaine's Claude. Read CLAUDE.md first. Push only to `test-bear`, never `main` without JJ's OK.

## Branch state
`test-bear` = `origin/test-crowd` + a merge of `origin/main` (as of 2026-10-30: mocap knight, attack pace,
damage numbers, weapon draw, admin key, waypoints). The three merge conflicts (`CLAUDE.md`, `hero.gd`, `ui.gd`)
were resolved by keeping both sides.

## Done
- **Model and rig:** `tools/blender/act1/rig_bear.py` builds `assets/models/monsters/bear.glb` from the raw Meshy glb.
  - Source: `git show origin/jj-models:exports/forsaken_bear/bear2_meshy_raw.glb > bear_raw.glb`.
  - Run: `blender -b --python tools/blender/act1/rig_bear.py -- bear_raw.glb assets/models/monsters/bear.glb [--blend out.blend] [--debug prefix]`.
    `--debug` renders the bones in colour; it needs `xvfb-run -a`.
  - Clean-up: merges split vertices, cuts the rock slab and any ground roots more than 0.17 m from the paws,
    closes the soles, decimates to 25k tris, and scales to 1.6 m at the shoulder.
  - Skeleton: 21 bones with the lion's names, plus `jaw` and `antler_l`/`antler_r`.
  - Skinning: by surface distance (Dijkstra over the edges), at most 4 bones per vertex, power 3.
- **`scripts/bear.gd`** (class `Bear`): `ok`, `build` and `pose`, driving:
  - the walk (diagonal pairs, head low and swinging, shoulders rolling);
  - `bear_roar`: rears onto the hind legs, pivoting at the hips (`PIVOT`), forepaws up, jaw wide, chest heaving, spine shake;
  - `bear_maul`: rears, then slams both forepaws down (impact at `MAUL_HIT`).
  - `tools/bear_sheet.gd -- out.png [side|34]` renders the contact sheet. It looked right at handoff.
  - `Bear.sound()` falls back to `lion_roar` pitched down and `slam` until `bear_roar` and `bear_maul` exist.
- **Wiring** (written, and it compiles; **not yet run in a real game**):
  - `Data.ENEMIES["bear"]`: mesh `bear`, rig `crawler`, ai `bear`, life 130, damage 9-16, speed 3.0, range 2.4.
  - `Enemy.build_rig` and `Enemy.pose_rig` have Bear branches; the bear also uses the lion/feral death roll.
  - `Enemy._bear_idle`: wanders within 9 m of home and rears and roars every 14-26 s.
  - `Enemy._bear_combat`: roars once on noticing a hero, charges at 1.5x speed and mauls. It gives up beyond 30 m
    from home (`b_roared`, `f_calm`).
  - The maul shows a green danger ring (fx `bear_tele`) and hits everyone in a 3 m arc in front, with kind `"maul"`.
    `Hero.take_hit` turns `"maul"` into a knockback (`Hero.knock_v`, applied in `_process`).
  - Fx events `bear_roar`, `bear_maul` and `bear_tele` are sent to co-op partners through `_fx`. `Net.STYLES` gained
    `bear_roar` and `bear_maul`, so every peer needs this build. `Anim.impact_at` knows both styles.
  - `Games.finished_model` includes `"bear"` (the arena crowd).

## To finish
1. **Spawns:** 2 bears per Act I moor, 20-40 m off the road, with their own seed, kept out of the camp and the fort.
   Follow `World._feral_packs`, adding `enemy_spawns.append({"kind": "bear", ...})` from the moor builder.
2. **`tools/bear_test.gd`** (`[B]` lines). Check that it:
   - spawns off the road and wanders inside its area;
   - rears and roars;
   - notices, charges, mauls, does damage and knocks the hero back;
   - goes home when led more than 30 m away.
3. **Sounds:** `bear_roar` and `bear_maul` through `tools/audio` (`spec.py`, `eleven.py`, `score.py`, picks, `build_sfx.py`),
   with 3 options each for JJ. The ElevenLabs key wasn't in JJ's Claude's workspace.
4. **Regression tests:** `playtest`, `feral_test`, `a2_arena_test`, `sound_test`, `tools/crowd_shot.gd`.
5. **Polish if needed:** a little hide still stretches on the nape at full rear. Lower `neck_x`/`head_x` in the roar,
   or soften the skin weights further.
6. Add a short Bear entry to CLAUDE.md, push to `test-bear`, and send JJ the Actions run link and renders.
   Tip: if `godot --headless --editor --quit` doesn't pick up new class names, run `godot --headless --import`.

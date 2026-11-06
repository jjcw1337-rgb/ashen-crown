# Adding a hero

How a new hero goes from an idea to playable. It was first run with Doug. Each step names its tool, what it costs,
and the check that must pass before the next step. Everything the hero owns lives in `game/heroes/<id>/`. Copy the
Archer's layout (`game/heroes/archer/`).

## 0. Brief → codex (no credits)

- Inputs: the admin's description and reference images.
- Write the hero's codex file, `data/codex/heroes/<id>.json`. It holds the fantasy, three directions, the skills and
  the rites.
  - The kit: LMB attack, RMB and Q E R (the base kit), F G V (stronger skills, V the ultimate).
  - For every skill: what it does, why it's fun in PvP, **the answer to it** (counterplay), and whether it's a
    damage skill (no cooldown) or a utility one (cooldown and a tag).
- Post the kit summary to Discord.
- Gate: every skill has a counterplay line, and no button carries more than one hard crowd control.

## 1. Concept art (Meshy 2D, ~6 credits each)

- `tools/meshy/meshy.py edit <reference.png> "<prompt>" --ref <other ref> --aspect 3:4` (2 takes) and
  `meshy.py draw "<prompt>" --aspect 3:4` (2 takes).
- The prompt says: full body, symmetrical A-pose, arms a little away from the body, front view, plain grey
  background, even lighting, game asset for rigging.
- Gate: the whole body is visible, and the hands are empty or the held prop is clear of the body.

## 2. Model (Meshy image-to-3D, ~30 credits)

- `meshy.py image <concept.png> -o <dir> --pose a-pose --polys 60000`.
- Gate: it looks like the concept, has a clean silhouette and no fused limbs. Held props usually drop out, so make
  them separate props (step 5).

## 3. Rig and clips (auto-rig 5 credits, clips ~3 credits each)

- `meshy.py rig <image task id> --height <m>`.
- Pick clips with `meshy.py library <search>` (free): locomotion (idle, walk, run), every skill's whole-body move, a
  three-blow combo, hit, death.
- `meshy.py animate <rig task id> <ids>` (6–8 per batch).

## 4. Body in Blender (local)

- Copy another hero's `build/prep_*_mocap.py` into `game/heroes/<id>/build/`. Map the clip names it prints
  ("dropped clip ...") to the game's names.
- Export the body to `game/heroes/<id>/body/<id>.glb`. Keep the editable `.blend` outside the project.
- Gate: every clip is listed and none is "MISSING".

## 5. Props and effects art (Meshy text-to-3D ~10 credits each)

- One per thing a skill throws, places or rides: `meshy.py text "<prop>, game prop" --polys 5000-9000`.
- Prepare it with `tools/blender/prep_prop.py` into the skill's own folder (`game/heroes/<id>/skills/<skill>/`).
- Check it beside a man-sized post: `tools/blender/prop_sheet.py`.
- Gate: the right object, right way up, the right size, textured, ≤10k triangles, 1k textures.
- Text-to-3D is a coin toss for anything that isn't a simple object. For those, start with a concept and then
  image-to-3D (~36 credits).

## 6. Code

Follow the Archer's files:
- `<id>.gd`: the body (`Knight.build_mocap`).
- `skills/<skill>/`: what each skill does, plus `*_fx.gd` for what it looks like. Every visible thing is an fx event
  ([effects](patterns/effects.md)).
- The class's numbers are in its codex file and its `Data.CLASSES` entry.

Register the hero where the game lists classes:
- `ClassSkills.of`/`all`, `SkillFx.play`/`update`/`clear`;
- `Hero.is_<id>` and `_build_rig`;
- `Net.STYLES` (append new styles);
- the weapon in `Models.item_model`;
- the class picker (`ClassStage`: CLASSES, ACCENTS, EMBLEMS, SIGNATURE, SKILL_SHOW, PICK_SOUND).

## 7. Gates

- The hero's own test in `game/heroes/<id>/tests/` (each skill's gameplay).
- `tools/coop_fx_test.gd`: every skill reaches a puppet, and replaying it hurts nothing.
- `tools/skill_spec_test.gd`, `tools/playtest.gd`, and `tools/bg_pvp_test.gd` (PvP crowd control).
- Test in game time (`--fixed-fps 60`), not the wall clock.
- Screenshots of every skill from the game camera, posted.

## 8. Sound (ElevenLabs, ~10 credits a second)

Add the hero's sounds to `tools/audio/spec.py`, then run `eleven.py <names>` and `score.py --rank`. A human picks,
then run `build_sfx.py picks.json`. Until then the hero uses the closest existing sounds.

**Cost for Doug:** about 190 Meshy credits (concepts 24, model 30, rig 5, clips 60, props 70).

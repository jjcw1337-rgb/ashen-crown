# The character workflow (piloted with Doug, 2026-11-02)

Blaine: *"this is a trial run that is going to become our character generating workflow."* This is the pipeline
Doug went through, written so the next character is a matter of running it. Each step names its tool, what it
costs, and the check that must pass before the next step. A character is not done until every gate is green.

## 0. Brief → design doc (no credits)

- Inputs: the admin's description and reference images (Discord attachments).
- Write the hero's codex file `data/codex/heroes/<id>.json` (its fantasy, three directions, skills and rites; the Codex editor edits it): who they are, their **PvP identity in one line**, body and motion, and the kit:
  LMB attack, RMB + Q E R (the base kit), F G V (stronger skills, V the ultimate). For **every** skill: what it
  does, why it's fun in PvP, **the answer to it** (counterplay), its unlock level, and whether it's a damage skill
  (no cooldown, PoE standard) or a utility one (cooldown + tag).
- Post the kit summary to Discord. Gate: each skill has a counterplay line; at most one hard CC per button.

## 1. Concept art (Meshy 2D, ~6 credits each)

- `meshy.py edit <reference.png> "<A-pose full-body sheet prompt>" --ref <other ref> --aspect 3:4` (2 takes) and
  `meshy.py draw "<full prompt>" --aspect 3:4` (2 takes). Prompt must say: full body, symmetrical A-pose, arms a
  little away from the body, front view, plain grey background, even lighting, game asset for rigging.
- Run Meshy from headless Blender when the add-on holds the key (`scratchpad/meshy_run/run.py`, see memory
  meshy-headless-via-blender). Save into `~/Documents/Blender/Game Factory/exports/<id>/`.
- Pick the take closest to the reference (Blaine's call stands if he makes one; otherwise pick and say why).
  Gate: the whole body is visible, hands empty or the held prop clear of the body.

## 2. Model (Meshy image-to-3D, ~30 credits)

- `meshy.py image <concept.png> -o .../<id>_3d --pose a-pose --polys 60000`.
- Look at the four turnaround renders. Gate: likeness, clean silhouette, no fused limbs. Held props usually drop
  out: make them separate props (step 5).

## 3. Rig and clips (Meshy auto-rig 5 credits, clips ~3 credits each)

- `meshy.py rig <image task id> -o .../<id>_rigged --height <m>`.
- Pick clips with `meshy.py library <search>` (free): locomotion (idle, walk, run, run fast), every skill's
  whole-body move, a three-blow combo, flair (taunt, bow, cheer), hit, death. Write them into the design doc.
- `meshy.py animate <rig task id> <ids> -o .../clips_a` (6–8 per batch).

## 4. Body in Blender (local)

- Copy `tools/blender/doug/prep_doug_mocap.py` to `tools/blender/<id>/prep_<id>_mocap.py`; map the clip names
  it prints ("dropped clip ...") to the game's names; run
  `blender -b --python ... -- rigged.glb assets/models/<id>.glb 60000 clips_a.glb clips_b.glb clips_c.glb`.
- Save the editable `.blend` in `~/Documents/Blender/Game Factory/sources/<id>.blend` (never in the project).
- Gate: "clips N" lists every clip, no "MISSING". Meshy names a clip by its library title with its own numbering
  (Doug's "Idle_02" came back as "Idle_03", "Right-Hand Sword Slash" as "Right_Hand_Sword_Slash"): map every name
  the run prints as dropped.

## 5. Props and effects art (Meshy text-to-3D ~10 credits each)

- One per thing a skill throws, places or rides: `meshy.py text "<prop>, game prop, realistic stylized" --polys 5000-9000`,
  then `blender -b --python tools/blender/prep_prop.py -- in.glb assets/models/<id>/<prop>.glb <size> --axis ... --tris N --tex 1024`.
- Look at each prepared prop beside a man-sized post: `blender -b --python tools/blender/prop_sheet.py -- outdir
  assets/models/<id>/*.glb` (prints sizes too). Gate: the right object, right way up, the right size for the body,
  textured, ≤10k triangles, 1k textures. Doug's first pass, for the record: the "bicycle horn" was a goblin playing a
  horn and the "kelp" a ragged figure (both dropped; the code's fallbacks stand in), the bramble patch came out as a
  dead tree (regenerated, and the second take is a flat thicket: the code crosses two), and the clown car had a
  jester sitting on its roof: `tools/blender/cut_above.py` cut it at the window line into an open tourer he drives
  (prepare the size by the car's length, not its height). Text-to-3D is cheap but a coin toss for anything that isn't
  a simple object: for those, concept → image-to-3D (~36 credits) from the start.

## 6. Code (the project's patterns; copy `game/heroes/archer/`'s layout)

- `Data.CLASSES[<id>]`, seven `Data.SKILLS` entries with SkillSpec fields (`style`, `use`, `hit`, `dmg`, `area`,
  `tags`...), the class's weapon base.
- `scripts/<id>.gd` (body: `Knight.build_mocap(GLB, {"relaxed", "combat", "acts": ACTS})`), `scripts/<id>_skills.gd`
  (from `tools/templates/new_class_skills.gd`: can_cast, cast, impact, update, rooted, clear, died, sound),
  `scripts/<id>_fx.gd` (play/update/clear: draws only; every visible thing is an fx event).
- Register: `ClassSkills.of/all/trail_color`, `SkillFx.play/update/clear`, `Hero.is_<id>` + `_build_rig`,
  `Net.STYLES` (new styles appended), `Models.item_model` (the weapon), `ClassStage` (CLASSES, ACCENTS, EMBLEMS,
  SIGNATURE, SKILL_SHOW, PICK_SOUND, `_fidget`, `_signature`), `UI.SkillGlyph` (a glyph per skill),
  `Talents.TREES` + `AUTO`. PvP crowd control: `Net.send_pvp_effect` kinds, handled in `Hero.take_hit`.

## 7. Gates (all must pass)

- `godot --headless --editor --quit` then `--check-only` on each new script.
- `tools/coop_fx_test.gd` (every skill reaches a puppet, replays hurt nothing), `tools/skill_spec_test.gd` (the PoE
  rules), `tools/<id>_test.gd` (each skill's gameplay), `tools/talent_test.gd`, `tools/class_carousel_test.gd`,
  `tools/playtest.gd`, `tools/bg_pvp_test.gd` (PvP crowd control), `tools/skill_perf.sh <id>` (no new stutters).
- Test scripts wait in game time (frames at `--fixed-fps 60`), not the wall clock: headless runs faster than real
  time, so a 2 s slow is over before a wall-clock `secs(1.6)` looks. Freeze the test monsters (`speed = 0`) where a
  skill shot has to land on one. Load the class's skills script at run time in a `-s` tool (`load(...)`).
- Screenshots from the game camera of every skill (`tools/mocap_knight_clip.gd` / a skills clip tool), posted.

## 8. Sound (ElevenLabs, ~10 credits a second)

- Add the class's sounds to `tools/audio/spec.py`, `eleven.py <names>`, `score.py --rank`, a human picks on the
  Sound Picks page, `build_sfx.py picks.json`. Until then the class uses the closest existing sounds.

## Costs (Doug)

Concepts 24, model 30, rig 5, clips 60, props 70: ~190 Meshy credits; Blender and the code are local.

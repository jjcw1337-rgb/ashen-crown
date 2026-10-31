# The Plague Doctor: progress note

Goal: a new playable class, a dark-fantasy plague physician who fights through preparation, poison, fire and traps,
with his own Meshy model, motion-captured moves for every skill, and full integration (class picker, talents, saving,
co-op). Scope for this first version: the same four skills every class has (the brief's other four, Corrosive Compound,
Fever Dart, Plague Swarm and Contagion as its own skill, wait; the model's belt of vials was made for them).

## Done (2026-10-31, branch from test-all fde6720)

**Model.** Four Meshy concept images from the reference (image-to-image, nano-banana-pro); concept 1 picked
(bandolier, most vials, coat split at the front). Image-to-3D (Meshy 7.1, textured, PBR, A-pose, 100k), task
01a191d9-dfec-77ab-90e2-4853b2c02bc4. Meshy auto-rig (24 bones, 1.8 m), task 01a191dc-4fd3-7584-82b8-dd7321ff498c.
26 library clips in three requests (ids at the top of `tools/blender/plague/prep_plague_mocap.py`), merged and
decimated to 60k by that script into `assets/models/plague_doctor.glb`. Props (Meshy text-to-3D): crow-skull cane,
toxic flask, volatile bottle, trap canister in `assets/models/plague/`.

**Animation checklist** (L = library clip as is, M = library clip re-timed per skill):

| Move | Clip | Src |
|---|---|---|
| Idle, combat idle, walk, combat walk, run | Idle, Idle 2, Casual Walk, Walk Fight Forward, Run 2 (speed-blended, as the knight) | L |
| Inspecting a vial (class-stage fidget) | Stand and Drink, stopped short of the beak | M |
| Hit, death | Hit Reaction, Dying Backwards | L |
| Turning, roll, stagger, sprint | in the glb for later (Walk/Run Turn Left, Roll Dodge, Mummy Stagger, Lean Forward Sprint) | L |
| Cane combo, his own | Charged Upward Slash = Crow's Peck, Charged Slash = Vial Flick, Heavy Hammer Swing = Censer Slam (swipe1/2/3; eight library clips tried, these three kept; the first version's sword slashes dropped) | M |
| Toxic Flask | Over Shoulder Throw: hand to belt, arm back, throw, recover | M |
| Volatile Mixture | Crouch Charge and Throw: down in a crouch, the long release | M |
| Pestilent Trap | Crouch Pick Up Place Side: kneel, set, rise | M |
| The Last Epidemic | Charged Ground Slam (the censer smashed), then Charged Spell Cast (arms raised) | M |

Every skill's core action is its own clip; none reuses another's. The release of each is keyed to the game's impact
frame for its style (`Plague.ACTS`), so the flask leaves the hand when the projectile spawns at any attack speed.

**Game.** `scripts/plague.gd` (class, skills, statuses, effects, co-op replay); whole-body clips per attack style added
to the mocap rig (`Knight.build_mocap` opts `"acts"`, `knight_mocap_rig.gd`), usable by any mocap body; hero hooks;
`Data` class, skills and two canes; styles in `Net.STYLES` and `Anim.impact_at`; class stage entry (accent, signature
Toxic Flask, pick sound, the vial fidget); skill glyphs; three talent trees with Meshy-painted icons; weapon draw
profile; README and CLAUDE.md.

**Co-op.** Damage is the usual route (each hit through `Enemy.take_damage`, which partners forward to the host).
New: partners see his effects (`Net.hero_fx` → `Plague.remote` on the puppet, which shows but never deals damage).
No other class does this yet; the same channel would work for them.

**Tests.** `tools/plague_test.gd` (30 checks: body, clips per skill, poison not stacking, ignition, trap limit and
spring, both ultimate stages, infection limit, cleanup), `tools/plague_mp_test.gd` (host + join, both directions).
`talent_test` passes for every class including his. `balance_sim` knows him (and the archer's stat weights, missing before).

**Balance** (`tools/balance.sh classes=plague`, after tuning): A1 moor 4.8 s a pack, A1 boss 20.8 s, A2 arrive 7.1 s
(1.48x), A2 moor 5.8 s (1.21x), A2 boss 17.5 s (0.84x), A3 moor 4.5 s (0.94x), A3 boss 34.5 s (1.66x); no deaths, few
potions. Two mild flags, both "later acts a little quick against his own Act I" (the warlock had four in the same run).
The bot now throws his flasks and traps point-blank too (`balance_sim.gd`), as a player would; before that it only
swung the cane in melee and he looked far weaker than he is.

**His cane combo** (same three blows as every class, each his own): Crow's Peck poisons what it strikes for 2 s, Vial
Flick fans poison drops across its arc (3 s on everyone struck), Censer Slam cracks a vial on the ground ahead into a
2 m cloud for 2.5 s. Balance rerun after it: A1 moor 4.4 s, A1 boss 20.1 s, A2 arrive 7.1 s (1.61x), A2 moor 7.1 s
(1.61x), A2 boss 17.1 s (0.85x), A3 moor 4.5 s (1.02x), A3 boss 34.5 s (1.72x): three flags, each at the edge of its band.

**Colour:** an oxblood coat and cape with a black hat, gloves and boots (picked from six options rendered at eye level
and from the game's camera: it reads from above, isn't the warlock's green or the forest's, and sets off his green
poison). `tools/plague_colors.py` + `Plague.dye`, by region; the other schemes ship as options. The straps, silver
mask, brass and vials keep their colours.

**Also fixed on the way:** poison ticks are quiet hits (`Enemy.soft_hit`: a green number, no white flash, no flinch;
a partner's travel to the host as knock -1); the cane is put away while a skill needs both hands and a bottle shows in
his hand during the wind-ups; after ~10 s standing about with the cane away he takes out a vial and peers at it (pose
only, partners see it). Known and not his: `tools/playtest.gd` fails to compile headless on test-all (`Sfx` in
ground_item.gd) and `mp_test`'s "[H4] partner pos ok" is false there too, both on the untouched branch.

**Meshy credits spent:** 395 of the month's 1,011 in all (balance 616 after; the eight cane clips tried cost 24 by the task record, and the balance dropped 48 over that step): concepts 36, model 30, rig 5, clips 78,
props 4 x ~30, talent grids 24 (one repainted because it had text in it), and ~30 for the first test model made straight
from the reference image before the plan.

## Next
- The other four skills from the brief (Corrosive Compound, Fever Dart, Plague Swarm, Contagion), if wanted: a bar slot
  question first (six hotkeys + two mouse buttons).
- His own sounds (ElevenLabs needs Blaine's OK): locust swarm, glass, the dome; existing takes stand in now.
- Coat panels (hA..hC) like the crusader's cloak if the coat looks stiff at a run on a real GPU.
- Turning, stagger and the dodge roll are in the glb but not wired: no class has a dodge yet.

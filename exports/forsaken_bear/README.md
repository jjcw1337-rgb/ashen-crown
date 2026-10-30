# Forsaken bear (Act I): handoff

JJ's pick: **concept 2, the corrupted ancient**, as an Act I bear. Handed over so Blaine's Claude can take it from here.

## What's here
- `concept_1_hunted_grizzly.png`, `concept_2_corrupted_ancient.png`, `concept_3_starving_revenant.png`, `concepts_sheet.png`:
  the three Meshy concepts (text-to-image, 6 credits each).
- `bear2_meshy_raw.glb`: Meshy image-to-3D of concept 2, untouched: no pose mode (standing on all fours), 60k-poly target,
  PBR textures, ~19 MB. Task `01a18b83-ea8a-74e5-99d3-348b4224a43d` (30 credits). Not decimated or rigged yet.
- `bear2_meshy_front/back/left/right.png`: Meshy's preview renders of that model.

## What JJ asked for
- Clean it up and rig it in **Blender** for maximum detail (the lion and the Feral are the closest examples: a quadruped skeleton,
  skinned by distance along the surface, posed in code like `Lion.pose`).
- Behaviour: **wanders, rears up, roars**, and **one attack**.
- Add it to the enemy file (`Data.ENEMIES` in `scripts/data.gd`) as a general entry so later acts can reuse it; place it in Act I.
- Show JJ renders before it goes into the game, push to a `test-*` branch, nothing to `main` without his OK.

## Heads-up
- JJ's other open branches touch `scripts/hero.gd`: `test-knight-rig` (mocap knight) and `test-combatpace`
  (attacks 20% slower, stacking damage numbers). Neither touches `enemy.gd` or `data.gd`'s enemy table.
- The 3D was made from JJ's Meshy key; tell him the credit cost before generating more.

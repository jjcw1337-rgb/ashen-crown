# Knight overhaul: progress note

Goal: replace the knight's 13-bone rig and maths-driven run with a full humanoid skeleton and
motion-captured animation, keeping every existing combat move working.

## Done
- Stage 1 (2026-10-30): Meshy auto-rig of the crusader (image-to-3D task 01a189fd-5d64-71b5-b1be-4f33ca0c450a,
  rig task 01a18b53-937c-7758-981d-5d228d56decc): 24 bones (Hips, Spine02/01/Spine, neck, Head,
  Left/RightShoulder, Arm, ForeArm, Hand, UpLeg, Leg, Foot, ToeBase). 13 Meshy library clips merged:
  idle, combat_idle, walk, walk_fight, run, run_fast, sprint, walk_back, run_fwd_left, run_fwd_right,
  hit, death, roll. Built by tools/blender/knight/prep_knight_mocap.py into assets/models/knight_mocap.glb
  (70k faces, one AnimationPlayer). Meshy credits spent: 44.

## Next
- Stage 2: in Godot, a mocap body for the armoured knight: AnimationTree blending idle/walk/run/sprint by
  speed (+ strafes, backpedal), the existing combat (combo, Holy Slam, block, weapon draw) layered on the
  upper body, weapon on RightHand, the scabbard hilt split, the cloak.
- Stage 3: in-game review clips from every angle, regression tests, preview build.

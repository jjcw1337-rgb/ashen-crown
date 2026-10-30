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

## Stage 2: in the game (done, test-knight-rig)
- `Knight.build_mocap()` + `scripts/knight_mocap_rig.gd`: the armoured knight is now the mocap body whenever armour is on
  (`Hero._knight_body()` returns "mocap"; falls back to "armored" without the glb).
- Locomotion: AnimationTree (relaxed and combat blend spaces by ground speed in m/s, mixed by the weapon draw, death clip).
  Playback rate follows the measured speed (clip speeds measured from the planted foot: walk 0.55, run 4.25, fast run 6.6).
- Combat: Anim's proxies are laid onto the real bones per bone (upper body for swings/casts/block; legs too for footwork attacks),
  fading in and out (w_up / w_low).
- Gear rides followers of the real bones (`J["at_hand_r"]` etc.); a relaxed hand tips the sword down (`RELAXED_TIP`).
- Cloak: 9 bones hA..hC swung by `_sway_hair` (rig-axis swing turned into each bone's frame, `hair_conj`; `hair_run` 0.45).
- Preview: `tools/mocap_knight_clip.gd -- outdir run|attack|runattack|block|turn [side|front|34|back] [frames]`.
- Tests: meshy_knight_test (accepts mocap), holy_slam_test pass.

## Stage 3: checks (test-knight-rig)
- Weapon draw/holster merged (test-weapondraw): the draw counts as "acting" only while the blade moves; sheathed he runs
  the relaxed clips, drawn the battle-ready ones. The mocap body's scabbard hilt hides while the sword is out.
- Locomotion uses one run clip scaled by speed (run_fast dropped from the blend: two runs with different cycles mushed the
  feet). Planted-foot slide: ~0.26 m/s at 4.8 m/s, ~0.33 at 6.2 (was 0.74 / 1.39).
- Game-camera tour (`mocap_knight_clip.gd -- out tour game 330`): turns, swing, block, hit, death all read.
- Tests: weapon_draw_test (16/16), meshy_knight_test, holy_slam_test.

## Finish (test-knight-finish)
- The cross-body draw reaches the real hilt: `KnightMocapRig._reach_hilt` steers the right arm onto the scabbard hilt
  (found from the "Hilt" surface, kept in the hips' frame) with a two-bone IK blended in around the grab (draw 0.12-0.6).
  Hand-to-hilt at the grab: 0 cm (was about 90).
- Cloak at speed: `hair_run` 0.3 (was 0.45), so at a sprint it streams back instead of lifting.
- Co-op checked with `mp_test` host + join (the host plays the mocap knight): the partner sees him, travel, kills, loot
  and leaving all work.

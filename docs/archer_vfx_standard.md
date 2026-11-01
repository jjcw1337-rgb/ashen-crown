# Archer skill visuals: the quality standard

Fire Arrow (`pierce`, the Phoenix) is the benchmark for every Archer skill. A new bow skill is not done until
it has everything below, at this quality, and the proof renders have been looked at.

## What every Archer skill must have

1. **A layered projectile** (`scripts/arrow_fx.gd`, `ArrowFx.PRESETS[kind]`): the Meshy arrow model plus a hot
   core and tip spark, two or more shader flame/energy sheaths with a multi-stop colour gradient (core → mid →
   edge → tip; never one flat colour), a signature shape (the Phoenix's feather wings; a new skill needs its own:
   frost crystals, lightning arcs, ...), and GPU particles drawn with **painted textures** (feathers, flame
   tongues, smoke: `assets/textures/fx/phoenix_*.png`, cut from Meshy sheets by `tools/fx_atlas.py`).
   No untextured dots, no solid-coloured boxes or cones, no uniform particle clouds.
2. **A trail**: the ribbon (`ArrowFx._trail`, an ImmediateMesh strip rebuilt from the head's last positions,
   `TRAIL_SHADER`: flame at the head thinning into smoke, edges eaten by noise) or an equivalent of the skill's
   own (ice shards, arcs). It is left to fade where the flight ends, never cut off.
3. **Dynamic light**: an OmniLight that moves with the projectile and flickers (`"light"`), capped at
   `ArrowFx.LIGHT_CAP` arrows lit at once; a pop of light on every impact; the burst's light decays.
4. **The draw**: the skill is visible before the release (`ArrowFx.draw_charge`: the charge gathering on the
   nocked arrow in his hand, tied to the attack's progress so it plays standing, walking and on the puppet).
5. **The release**: the bow flares as the arrow leaves (`ArrowFx.release`: embers, a ring, light, a small shake).
6. **Each impact**: an entry flash, a reaction out of the far side of the foe along the arrow's line, sparks,
   light, a tiny hitstop (`ArrowFx.pierce`), and the skill's status drawn on the foe for its duration
   (`ArrowFx.burn`: one particle system per foe, removed at the end).
7. **The end of the flight**: a burst where it ends (`ArrowFx.finish`: flash, the energy swelling open, textured
   embers, a ground ring, debris, bouncing sparks, a short ground effect, smoke, a scorch/decal, light decay).
8. **Whole-body animation**: the body takes part in the shot (`KnightMocapRig` shot layer + the procedural
   layers in `_shot_body`: held full draw, torso twist, weight on the back foot, the bow arm's recoil, the
   string hand flung back, follow-through). It works standing and walking and on the co-op puppet, and never
   breaks `Archer.pose_bow` (the string meets the fingers, the release snap).
9. **Sound synced to the animation**: layers in the preset's `"sounds"` (`cast`, `release`, `pierce`, `end`),
   the release payoff on the impact frame (`Sfx.play_synced` through `Hero._attack_sound`), impacts
   positional (`Sfx.play_at`), the caster's own flat (`SkillFx.snd`). Existing takes only; no new buses.
10. **Co-op through one event**: one `"loose"` event per shot (`Hero.fx`) carrying `p, d, k, x, m`; every
    visual replays identically on the partner's puppet from `Archer.update` / `ArcherFx.update`; nothing is
    sent per frame; the puppet deals no damage (`tools/coop_fx_test.gd` must pass).
11. **Budgets**: ≤ ~120 live particles per arrow, impact bursts ≤ ~150 one-shot, ≤ 1 moving light per arrow
    (3 at once), everything freed when done, no per-frame allocation beyond the trail rebuild.
12. **Web / Low fallback** (`ArrowFx.cheap`): half the particles, no smoke, no heat haze (`shimmer_ok`:
    Forward+ only), no rock chunks. It must still read as the same skill.
13. **It reads at gameplay distance**: judged from the game camera (`Game.CAM_OFFSET`), not only close up.

## Proof

Record it from the running game with the clip tool (the frames are what the game drew):

    xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
      --fixed-fps 30 -s tools/fire_arrow_clip.gd -- <outdir> <skill id> both 30

It stages the ranger on the moor with three monsters in a line, fires the skill standing and then walking,
and saves frames from the game camera and from a close camera following the arrow. Encode with ffmpeg
(`-c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p`) and look at the frames before calling it done.
Software rendering (llvmpipe) is dimmer than a GPU: the HDR glow and bloom are stronger in the real game.

## Adding a skill

Add a preset to `ArrowFx.PRESETS` (copy `"fire"`, change the colours, textures, shapes and sounds), paint its
sheets (`meshy.py draw ... --cutout`, ~6 credits each) and pack them with `tools/fx_atlas.py`, give its
`"loose"` event the new kind in `Archer._loose`, add its draw/release/pierce/end behaviour where the preset
needs something the module doesn't have, and record it with the clip tool. Then run `tools/archer_test.gd`
(`--fixed-fps 60`), `tools/coop_fx_test.gd`, `tools/sound_test.gd` and `tools/ui_click_test.gd`.

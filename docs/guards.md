# The camp guards (Act I)

jj's request (2026-11-04): real guards for the Act I town, built to the playable characters' standard, three distinct
hand-to-hand fighters in full armour patrolling the camp, alive and moving in every direction, casting shadows like
the waypoint and the traders, with three open attack slots for our skills. The skills, their effects and animation are
for later; this file is the notes for that work.

Code: `scripts/camp_guard.gd` (`CampGuard`), placed by `ForestCamp.build` (`CampGuard.place_all`). Models:
`assets/models/guards/<id>.glb` + `<id>.json` (clip measurements). Test: `tools/guard_test.gd` (run through
`tools/_late.gd`). Screenshots: `tools/guard_shots.gd -- outdir`. `--guard-fight` lets four zombies loose in the camp.

## The three

| | Warden Bram (`warden`) | Sentry Kell (`sentry`) | Ironfist Varg (`ironfist`) |
|---|---|---|---|
| Look | blackened plate over mail, closed bascinet, green surcoat with the ember flame, spiked gauntlets | kettle helm and mail coif, studded leather brigandine, wolf-fur mantle, studded fighting gloves | horned face-visor helm, iron lamellar, bronze-banded cestus gauntlets, red padded skirt, lantern and chains at the hip (the lantern is lit: a light on his hips bone) |
| Height (rig) | 1.92 m | 1.8 m | 1.95 m (all x `SCALE` 1.08) |
| Round | north gate (inside), the lantern path, the forge, the bonfire | the whole ring: west gate, wagon, alchemist, north path, forge, armoury, Vigil Gate, the south tents, the west wall | the grand waypoint, the south-west wall, the Vigil Gate, the armoury side |
| Walk | Casual Walk | Quick Walk | Casual Walk |
| Idle / flourish | Idle / Angry Ground Stomp | Idle 1 / Stand Dodge | Idle 2 / Punch Pose |
| Slot 1 | both fists driven forward (214) | left jab (191) | punch combo (198) |
| Slot 2 | elbow strike (212) | right upper hook (195) | right uppercut (194) |
| Slot 3 | Spartan kick (206) | roundhouse kick (207) | stepping knee strike (211) |
| Rim / fill | ember orange | moon blue | lantern amber |

Every guard also has: Alert (2), Short and Long Breathe and Look Around (338, 336), Idle Turn Left/Right (576, 586),
Combat Idle Turn Left (575), Alert Quick Turn Right (589), Walk Backward (544), Walk Turn Left/Right (572, 583), Walk
Slowly and Look Around (341), Run 2 (14), Combat Stance (89), Walk Fight Forward/Back (21, 20), ForwardLeft/Right
Run Fight (9, 10: the strafes), Boxing Warm-up (385), Hit Reaction (178), Dying Backwards (189). 26 clips each.

## Sources (Meshy, jj's key)

- Concepts (text-to-image, nano-banana-2, prompts in `~/Documents/Blender/Game Factory/exports/act1/guards/prompts.txt`):
  warden 01a1a4d7-ebee-7138-aee7-110c0bfd5549, sentry 01a1a4d7-ebf7-71d5-97e7-fe0bdc2107b2, ironfist
  01a1a4d7-ebf3-724d-aaa4-09e1f29263e0.
- Image-to-3D (a-pose, 60k): warden 01a1a4d8-ca04-74a3-8c0e-0c58cd19a67c, sentry 01a1a4d8-ca02-753e-9954-ed68adc49d09,
  ironfist 01a1a4d8-ca0b-7678-9deb-57536dec1ae4.
- Rigs: warden 01a1a4dc-12f7-767b-bdf2-8b3db9c006ce, sentry 01a1a4de-49c9-7233-b2b7-bc4682fecb79, ironfist
  01a1a4de-49c7-76bf-a238-a2ce660f24c4.
- Clips: three animation tasks per guard (ids in `exports/act1/guards/<id>_clips.txt`, results in `anim/`).
- Credits: about 340 (18 concepts, 90 models, 15 rigs, 234 clips).
- Rebuild a body: `blender -b --python tools/blender/guards/prep_guard.py -- rig/guard_1_warden.glb
  assets/models/guards/warden.glb 45000 warden_names.json anim/warden_1.glb anim/warden_2.glb anim/warden_3.glb`,
  then `godot --headless --path . --import`. The editable sources stay in `exports/act1/guards/` (never a .blend in
  the project).

## How they move

- Patrol: `GUARDS[i]["posts"]` (spot, what they watch, how long). At a post: idle, look about, turn in place to watch
  another way (the turn clip plays and the body turns by the angle the clip had: prep_guard.py bakes the hips' yaw
  out of the turn clips and `CampGuard._turning` turns the body), stand alert, warm up, their flourish. Between posts:
  World.find_path, the walk (now and then the slow look-around walk), the walking turn at a sharp corner.
- Heroes: within 7.5 m they stop (once per 14 s), turn to face (the alert turn clips), stand alert and follow the hero
  with their head (`CampGuard.HeadLook`, a SkeletonModifier3D: neck 40%, head 60%, up to 66 degrees aside).
- Fighting: a monster within 13 m and inside the ring: run in, the fighting walk near, then circle (the two strafes),
  step back out when crowded, square up (combat stance), strike from the next slot when the cooldown is up and they
  face it. The blows land on the clip's own moments (`<id>.json` `hits`, where a hand or foot is farthest out in
  front); the strike is cut 0.5 s after its last blow (`RECOVER`). Damage: host only, `Enemy.take_hit` (a rival's blow:
  no xp or loot). They never leave the ring.
- Every clip plays in place (its drift taken out, the sway kept) and the body moves by the clip's measured ground
  motion through World.move: Meshy's walks and runs are in place, so their speed is measured off the planted foot.

## Still to do (later, jj)

### The three slots' skills
A slot is `{"skill": "", "clip": "strike_N", "reach", "dmg", "cd"}`. Filling `"skill"` with a skill id is the hook:
`CampGuard._strike` should then play that skill's clip and effect instead of the plain blow. Ideas to choose from:
- Warden: **Ember Brand** (the flame on his surcoat flares, a burning two-fisted blow: fire, `Enemy.ignite`), **Gate
  Hold** (his stomp, a ring that taunts and slows everything near: `Enemy.taunt`, `Enemy.slow`), **Shoulder Charge**
  (Standard Forward Charge 510, knockback).
- Sentry: **Wolf Rush** (a dash and a jab flurry: Punch Combo 200-205), **Hamstring Sweep** (Leg Sweep 213: slows), **The
  Alarm** (a shout that brings the other two running to him).
- Ironfist: **Lantern Flare** (the lantern flashes and blinds: a stun cone, its light flares), **Cestus Slam** (both
  fists into the ground: Charged Ground Slam, a shockwave), **Unbroken** (stands firm: less damage, a parry).

### Rendering and animation
- Effects per skill through `Hero.fx`-style events if guards ever need to show on partners' screens identically
  (today they run on every game locally; a fight looks the same because the monsters are synced).
- Sounds: footsteps with armour clank (plate for the warden, mail for the sentry, lamellar and chains for the
  ironfist), fist impacts on flesh and bone, a grunt per strike. To generate with ElevenLabs; jj picks from 3 options.
- Hit and death are in the clips (`hit`, `death`) but unused: guards can't be hurt yet.
- Night rounds with the day/night cycle (a torch for the sentry at night, lanterns brighter).

### An invasion of Act I
- Monsters that attack the camp would need to target guards (today `Enemy` only fights heroes and rival factions):
  give guards an Enemy-like target interface (`take_hit`, `dead`, `global_position`, `radius`), life, and the hit and
  death clips.
- Co-op: guard positions are local to each game; for real fights the host should own them (a small sync like the
  enemies': position, yaw, clip).

### Playable
They're on the 24-bone Meshy humanoid rig the ranger and the plague doctor use, so one can be made a class through
`Knight.build_mocap(glb, opts)` with a `KnightMocapRig` (the clips are named like the mocap bodies' where they overlap:
idle, walk, run, combat_idle, hit, death).

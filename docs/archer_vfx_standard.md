# Archer skill visuals: the realistic standard

Fire Arrow (`pierce`) is the benchmark for every Archer skill. The target is photoreal, Diablo IV and beyond: no
cartoon shapes, no painted flames, no glowing tubes or flat textures, no plain particle dots. A new bow skill is
not done until it has everything below and its proof recordings (Forward+) have been looked at frame by frame.

## Simulate, don't paint

Fire and smoke come from fluid simulations, the way studios use EmberGen or Houdini:

- `tools/blender/fx/fire_sims.py` bakes Mantaflow gas domains (fire + smoke, vorticity, wavelet noise x2) in
  Blender 4.5 and renders them with Cycles, orthographic from the front, 256 px per frame:
  `blender -b --python tools/blender/fx/fire_sims.py -- <framesdir> flame|burst|smoke|all [res=96] [samples=24] [px=256]`
  - **flame**: a burning stick (licking flames, little smoke), 80 frames after it has settled;
  - **burst**: a fireball (fuel thrown out of a noise-displaced sphere whose emitting shell swells over 5 frames,
    its fuel in clots from a noise texture, burning open and rolling up into smoke), 64 frames, resolution 112;
  - **smoke**: a gout of smoke rising and rolling open, 64 frames.
  Fire frames hold the volume's emission as data: R = flame, G = flame x temperature (G/R is the mean temperature
  along the ray); smoke in front absorbs the fire. Smoke frames are a white scattering volume lit by three
  coloured suns (red from the right, green from above, blue from the left): an RGB lightmap, alpha = opacity.
- `python3 tools/fx_flipbook.py <framesdir> assets/textures/fx` crops each sim to the window it fills, crossfades
  the flame's last 16 frames into its first 16 (a seamless loop) and packs 8x8 atlases: `real_flame.png`,
  `real_burst_fire.png`, `real_burst_smoke.png`, `real_smoke.png` (mipmaps on, lossless: they are data); it also
  makes the burn mark procedurally (`real_scorch.png` soot + coverage, `real_scorch_n.png` a blistered char
  normal map, `real_scorch_e.png` ember cracks in a blackbody colour). It prints each sheet's pivot (where the
  source sits), which goes into `ArrowFx.PIVOT`, and smooths Cycles' grain out of the thin smoke (premultiplied) and
  drops stray specks of flame.

The run times on the 2-core cloud machine (domain res 80, 16 samples): about 3-4 min per bake, 6-25 s per frame.

## How the game draws it (`scripts/arrow_fx.gd`)

- **Fire** (`FIRE_SHADER`): flipbook particles (or cards) blending one frame into the next; the light is the sim's
  flame, the colour a blackbody at the sim's own temperature (`t_lo`..`t_hi` Kelvin, `ArrowFx.blackbody`), the
  brightness rising with the temperature so thick hot cores go white-yellow through ACES and thin edges deep red.
  Never hand-picked colour ramps. Additive, soft where it meets the ground or a body (the depth buffer, Forward+).
  A card stands up the world or lies along the arrow (its flames blown back), turning to the screen when seen
  down its axis.
- **Smoke** (`SMOKE_SHADER`): alpha-blended, relit in `light()` from its RGB lightmap by every real light: the sun
  with its shadows, the sky, the fire's own OmniLights. Smoke near the fire is lit orange from below because the
  fire's light is really there. Its colour is what burns (the preset's `smoke_col`).
- **Embers and sparks** (`STREAK_SHADER`): a hot core in a soft glow, stretched along the velocity
  (`particle_flag_align_y`), cooling along a blackbody curve over life; embers ride turbulence, sparks fall and
  collide with the ground (`_ground_collider`, bounce and friction by surface).
- **Heat haze** (`HAZE_SHADER`, Forward+ only): the solid scene behind the card bent by drifting normal noise,
  drawn before the other see-through things (`render_priority -20`).
- **The arrow itself** (`HEAT_SHADER`, an overlay on the Meshy arrow): the head glowing with heat, the shaft behind
  it charred and blistered with embers in the cracks.
- **Light**: the flight's light flickers on noise in a blackbody colour and casts shadows (not on Low / web); the
  end's light flashes and dies down to the glow of what is left burning; burning foes carry a small light
  (`BURN_LIGHT_CAP`).
- **Burn marks**: a `Decal` (soot albedo, char normal, emission cooling); Compatibility gets a lit quad.
- **The ground answers** (`ArrowFx.surface`, the preset's `"surfaces"`): grass smoulders (a ring of small flames,
  embers that settle and glow, pale smoke, the grass flattened and charred by the decal), stone throws sparks that
  skitter and bounce with chips and a soot mark and no lingering fire, dirt kicks up dust with the smoke, wood
  catches and keeps a small fire burning (`_keep_burning`) with a glowing char, dark ground is carried by the
  fire's light. A zone can name its surfaces with a `surface_fn` meta (the proof range does).

## What every Archer skill must have

1. A projectile built from simulated or physically-shaded layers wrapped round the real arrow model (preset
   `"flame"`, `"heat"`), never a tube or a flat card.
2. A trail that is one continuous thing, never a row of identical sprites: the flame's tail as a strip along the
   head's path (`_ribbon`: the sim flame laid along it, two offset frames, torn by noise toward the tail) and the
   lit smoke strip behind it, plus what is shed in the air (smoke puffs, embers, sparks) from emitters that follow
   the head (`fly`), left to burn out after the flight, never cut off. Timers run on `ArrowFx.now()` (game time).
3. Real light: a moving light with shadows (≤ `LIGHT_CAP` arrows lit), a flash on every impact, light that decays.
4. The draw: the effect visible on the nocked arrow before the release (`draw_charge`, tied to the attack's
   progress so it plays standing, walking and on the puppet).
5. The release (`release`), each foe struck (`pierce`, no blood: the wound is seared) and the status on him
   (`burn`: fire rising from his skeleton's joints and bones, not one patch), the end of the flight (`finish`:
   several turned and staggered instances of the burst sim, a white-hot core, a smoke column) with the ground's own
   reaction (wood catches along its grain, `_plank_burn`).
6. Whole-body animation: the shot layer in `KnightMocapRig._shot_body` (wind-up, breath, back set, held draw with
   a tremor, recoil, the string hand flung back, the weight rolling forward in the follow-through), standing,
   walking and on the co-op puppet, never breaking `Archer.pose_bow`.
7. Sound synced to the animation (preset `"sounds"`; existing takes only).
8. Co-op through one event: one `"loose"` event per shot carrying `p, d, k, x, m`; everything replays on the
   puppet from it; nothing per frame; the puppet deals no damage (`tools/coop_fx_test.gd`).
9. Budgets: ≤ ~150 live particles per arrow, impact bursts ≤ ~200 one-shot, ≤ 1 moving light per arrow
   (3 at once), everything freed when done.
10. Low / web (`ArrowFx.cheap`): half the particles, no haze, no light shadows, no chips; still the same fire.
    Compatibility: no soft intersections, no haze, the scorch as a quad; nothing may break.
11. It reads at gameplay distance (the game camera) as well as close up.

## Proof: the range, in Forward+

The moor is too heavy for the cloud machine's software Vulkan, so skills are recorded on the proof range
(`tools/fire_range.gd`, its ground `tools/fire_range_zone.gd`, built in through `World.custom_zones`): five lanes
(grass with the living 3D grass, stone flagstones, dirt, wooden planks with logs, dark charred soil in a wall's
shadow) at dusk, the real ranger and three real zombies, the skill fired through `Hero.use_skill`.

    apt-get install -y mesa-vulkan-drivers        # lavapipe, if /usr/share/vulkan/icd.d/lvp_icd.json is missing
    xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan --rendering-method forward_plus \
      --path . --resolution 1280x720 --fixed-fps 30 -s tools/fire_range.gd -- <outdir> <mode> [lane] [skill]

Modes: `game` (the game camera, standing then walking), `follow` (a camera riding beside the arrow), `impact`
(close on the far end), `surfaces` (the impact on every lane), `anim` (the archer close, side and three-quarter),
`still` (the range from above). Each take prints its frame cost before and during the shot. Encode with
`ffmpeg -framerate 30 -i ... -c:v libx264 -crf 18 -pix_fmt yuv420p`. Software rendering takes seconds per frame
and is dimmer than a GPU; judge shapes, motion and colour, then check brightness on a real GPU.

## Adding a skill

Frost Volley (`scripts/frost_volley_fx.gd`) is the second skill built to this standard, and the model for a skill that
is not one arrow: its cold mists are Mantaflow sims (`smoke_flipbook.py` kinds `frost`, `rime`: colder than the air, so
they sink and roll) drawn as `DemonKitFx.smoke` books, its crystals are Meshy models broken in Blender
(`fracture_rock.py`), its ground is a Meshy-painted texture, and its stages run from one event per cast plus
`Archer._rain`'s strikes on both games. Record it with `RANGE_SECS=6 ... fire_range.gd -- out game grass volley`.

Add a preset to `ArrowFx.PRESETS` (copy `"fire"`), simulate or model what it needs (a frost sim is a smoke sim
with cold, dense, falling vapour; lightning wants branching emissive geometry, not a sim), pack it with
`tools/fx_flipbook.py`, give its `"loose"` event the new kind in `Archer._loose`, and record it on the range.
Then run `tools/archer_test.gd` (`--fixed-fps 60`), `tools/coop_fx_test.gd`, `tools/sound_test.gd` and
`tools/ui_click_test.gd`.

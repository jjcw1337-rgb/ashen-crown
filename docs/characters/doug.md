# Doug — design (the pilot of the character workflow)

Blaine, 2026-11-01: *"a short stubby clown … our tier 1 character, our leading character. His unique abilities should
stand out and he should feel incredibly dynamic, especially at a PvP level."* Reference: Blaine's two screenshots
(rainbow afro, red bulb nose, mustard polka-dot suit, a battered leather breastplate, flip-flops, a roast drumstick).
Concept picked: `Game Factory/exports/doug/doug_edit_1.png` (Meshy edit of the reference into an A-pose sheet).

## Who he is

A washed-up circus brawler who wandered into the Forsaken Wilds and found that monsters, like crowds, can be
worked. Comic on the surface, nasty underneath: every gag is a weapon. He is **the trickster skirmisher**: not the
strongest in a straight fight, the hardest to pin down and the best at making the other player misread the fight.

**PvP identity in one line:** *he wins by making you look the wrong way.* Every one of his tools is readable (bright
props, loud sounds, honest wind-ups) and every one has an answer, so beating him and being beaten by him both feel
earned. That is what Blaine's balance doc asks for: a better player should be able to win.

**Body and feel:** 1.2 m, wide, heavy belly, short legs: a quick waddle that breaks into a surprisingly fast
belly-forward run; he bounces on his landings, his afro and belly jiggle (spring bones, like the knight's hair),
the flip-flops slap. Every skill ends in a little pose or flourish (a bow, a honk, a shrug), so he reads at a glance
even in a 10-player brawl.

## The kit (PoE standard: SkillSpec timing; cooldowns only on utility)

| Key | Skill | Lvl | What it does | Why it's fun in PvP | The answer to it |
|---|---|---|---|---|---|
| LMB | **Drumstick Smack** | 1 | 3-blow combo with the roast drumstick: smack, backhand, belly-bump (the 3rd knocks back 2 m). Melee 2.2 m, 100/110/140% weapon. | Fast, chunky, the belly-bump creates space for the next trick. | Short reach; the 3rd blow's wind-up is visible. |
| RMB | **Cream Pie** | 1 | Lobs a pie at the cursor (12 m, visible arc, 0.9 s use). Splat 120% + **Pied**: monsters blinded (50% miss) 2 s; a player gets cream over their screen edges and their aim-assist removed for 1.5 s. Same target can't be Pied again for 6 s. | A real skill shot with a funny, meaningful payoff: it wins the next exchange, not the fight. | Dodge-roll through it; it arcs, so moving sideways makes it miss; immunity after. |
| Q | **Banana Peels** | 1 | Tosses 3 peels in a fan ahead (they land 3–6 m out, last 8 s, max 6 down). Stepping on one: a player slips (0.7 s knockdown, slides on in the way they walked); a monster is stunned 1 s. Cooldown 7 s (trap). | Zone control and mind games: where will they walk? Combos with every other skill. | Bright yellow and visible; walk round them; a dodge-roll over a peel doesn't slip. |
| E | **Pratfall Slide** | 3 | Belly-slides 7 m the way he faces, honking: foes in the way take 90% and are shoved aside; he pops up with a "ta-da". Cooldown 5 s (movement). | His escape and his engage: slide in, slide out. | No i-frames: a well-timed hit at the end lands; it's a straight line. |
| R | **Doppel-Doug** | 6 | Doug ducks behind a puff of confetti: **he turns invisible for 1.8 s** and a balloon double of him runs off the way he aimed, waving; the double pops when struck (a confetti burst that slows for 1.5 s). Cooldown 14 s (utility). | The signature trick: which one is real? Great players bait with it, read players see through it. | The double is a touch too shiny (a balloon sheen) and runs straight; Doug's footprints still puff dust; AoE hits him. |
| F | **Pin Juggle** | 10 | Throws 5 juggling pins in quick succession at the cursor (1.4 s use); each ricochets to 2 more foes. 60% each. | His sustained damage; chaining between players rewards catching them grouped. | A visible juggling wind-up; spread out. |
| G | **Big Top Bounce** | 14 | Slams down a trampoline and bounces up to 10 m to the cursor; lands in a belly-flop: 180% in 3 m, launches foes (0.8 s airborne). Cooldown 10 s (movement, cc). | The big play-maker: over walls of peels, onto a fleeing player. | A shadow and a whistle mark where he lands, 0.6 s before; roll out of the shadow. |
| V | **Clown Car** (ultimate) | 20 | A tiny clown car screeches in; Doug jumps in and drives it for 5 s (fast, steerable, rams foes for 140% + knockback, honks, unstoppable). Then it bursts: confetti, 6 mini-clowns tumble out and sprint at the nearest foes, each popping in a pie splat (Pied). Cooldown 60 s. | A screen-wide "oh no" moment that turns a fight, and is hilarious. | It's loud and obvious; dodge the car's line; kill or outrun the mini-clowns (one hit each). |

Number targets follow the PvP overhaul (docs/queue_progression_overhaul.md): base kit at level 1 (attack, Pie, Peels),
Slide at 3, Doppel at 6, Juggle at 10, Bounce at 14, the ultimate at 20. All PoE: Pie and Juggle have no cooldown
(their use time is the limit); Peels, Slide, Doppel, Bounce and Clown Car carry utility tags and cooldowns.

## What makes him "tier 1"

- **One readable trick per button**, each with a prop you can see from across the screen and a sound you can hear.
- **Combos that reward skill**: Peels → Pie the slipper; Doppel → Slide the other way; Bounce over Peels onto a
  slipped foe; Clown Car through a Peel field.
- **Honest counterplay** for every tool (the right column), so PvP stays about players, not stats.
- **Personality in motion**: the waddle, the belly bounce, the afro jiggle, the flourishes and the honks.

## Assets (Meshy + Blender the whole way)

- **Body**: image-to-3D from the picked concept (A-pose), Meshy auto-rig + library clips (idle, walk, run, throw,
  slide/dive, jump, punches, taunt, hit, death), merged by a `prep_doug_mocap.py` like the ranger's, on the knight's
  mocap system; spring bones for the afro and belly; the drumstick as a grip prop.
- **Props** (Meshy text-to-3D, `prep_prop.py`): cream pie, banana peel, juggling pin, trampoline, clown car, the
  horn, confetti sprites; the mini-clown (image-to-3D, a small rig) for the ultimate.
- **Effects**: pie splat decal + screen-edge cream for the Pied player, confetti (GPU particles, capped), a balloon
  sheen shader for the double, a slide dust trail, a landing ring.
- **Sound**: ElevenLabs takes for the honk, splat, slip, boing, car horn, engine, crowd laugh, his grunts and a
  catchphrase or two (picked through the Sound Picks page).

## Engineering (the project's patterns)

`Data.CLASSES["doug"]`, seven `Data.SKILLS` entries with SkillSpec fields, `scripts/doug.gd` (body, Doug.build_mocap),
`scripts/doug_skills.gd` (ClassSkills interface), `scripts/doug_fx.gd` (DougFx.play/update, every visible thing an fx
event so partners and PvP opponents see it), `ClassStage` entries (carousel, signature move), talent trees and icons,
tests: `tools/doug_test.gd` + `coop_fx_test` (automatic) + `skill_perf.sh` for every skill.

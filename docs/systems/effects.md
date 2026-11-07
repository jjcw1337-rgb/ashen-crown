# Effects

How a skill's look reaches every screen, and when it is good enough.

## How it works

1. **Rules call `Hero.fx(skill, event, data)`** wherever something is to be seen. That plays the event locally
   (`SkillFx.play` → the hero's effects script) and sends it once; every other player's game plays it on the caster's
   copy. The Plague Doctor still sends most of its effects through its own events (`Plague._send`).
2. **An effects script only draws.** It never touches life, mana, cooldowns or statuses. Whatever it needs travels in
   the event (`"p"`, `"d"`, `"t"`…).
3. **Nothing is sent every frame.** Lingering effects keep their state in `Hero.fxs` and are moved by
   `SkillFx.update`.
4. Models load through `ResCache` ([loading](loading.md)). `tools/coop_fx_test.gd` fails a skill that shows partners
   nothing, or whose replay changes a monster.

## When it's good enough

Fire Arrow (`scripts/arrow_fx.gd`) is the reference.
- **Real things:** simulated fire and smoke, Meshy models, real fractured pieces, not glowing tubes or flat sprites.
- **Every phase shows:** the wind-up, the release, each foe struck, the end, and the ground's reaction.
- **Real light** on impact that decays, a continuous trail, and sound synced to the animation.
- **The body sells it,** and it reads from the game camera, not only close up.
- **It's cheap:** everything is freed when done, and low settings still look like the same effect.

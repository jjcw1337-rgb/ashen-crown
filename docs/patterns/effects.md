# Skill effects

**Goal:** what a skill draws is the same for the caster and every partner, costs nothing new on the network, and
never changes the game's state.

## The rules

1. **Skill code never draws.** Wherever something is to be seen, it calls `Hero.fx(skill_id, event, data)`. That plays
   the event locally (`SkillFx.play`) and, in co-op, sends it once to partners, whose game plays it on the caster's
   puppet.
2. **A handler only draws.** `<Class>Fx.play(h, ev)` must not touch life, mana, cooldowns, stuns or talents (a puppet
   has none). Send what the effect needs in the event (`"p"`, `"d"`, `"t"`, ...).
3. **Nothing is sent per frame.** Lingering effects are state in `Hero.fxs`, started and ended by events and moved by
   `SkillFx.update`. A partner's copy ends itself if the end is lost.
4. **Load and compile like [loading.md](loading.md)**: models through `ResCache`, one cached `Shader` per effect kind,
   and re-record `SkillWarmData` (`tools/skill_warm_capture.gd`) after changing what a skill draws.
5. **Tested by `tools/coop_fx_test.gd`**: it fails a skill that shows partners nothing, a lingering effect that doesn't
   reach the puppet, or a replay that changes a monster.

## The quality bar

A skill's look is done when it has all of these. Fire Arrow (`scripts/arrow_fx.gd`) is the reference.
1. **Real things, not painted ones.** Fire and smoke come from simulations rendered into flipbooks (Blender
   Mantaflow), models come from Meshy, and broken things are real fractured pieces. There are no flat glowing tubes,
   painted flames or plain particle dots.
2. **One continuous trail**, not a row of identical sprites. What it sheds (smoke, embers, sparks) is left to burn
   out, not cut off.
3. **Real light:** a flash on impact and light that decays. At most 2 shadowed effect lights at once
   (`Fx.effect_shadow`).
4. **Every phase is shown:** the wind-up on the caster, the release, each foe struck, any status on them, and the
   end (with the ground's reaction).
5. **The body sells it:** whole-body animation for the cast, standing, walking and on the puppet.
6. **Sound synced to the animation**, using existing takes until new ones are picked.
7. **Budgets:** about 150 live particles per projectile, about 200 in a one-shot burst, everything freed when done.
   Low / web settings get half the particles and no haze, and must still look like the same effect.
8. **It reads from the game camera**, not only close up.

Details: `scripts/skill_fx.gd`'s header.

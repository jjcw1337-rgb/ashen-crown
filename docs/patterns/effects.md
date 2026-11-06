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

Details: `scripts/skill_fx.gd`'s header.

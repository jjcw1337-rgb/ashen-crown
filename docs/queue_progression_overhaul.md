Completely overhaul the game’s leveling, skill progression, combat numbers, and itemization around PvP battlegrounds.

Character level and skills should provide most of a player’s power. Gear should provide smaller but meaningful advantages, with exciting PvP utility.

The balance targets are:

- **Equal player skill: the fully geared character should always win against the fresh, ungeared character.** This includes matchups between two highly skilled players. Progression and gear must provide a dependable advantage.
- **A substantial player skill difference: the ungeared character should still be capable of winning through significantly better play.** Avoid stat gaps that make this effectively impossible.

**Leveling and skill unlocks**

Replace the current approach of making every skill immediately available with a deliberate progression system.

- Show locked skills grayed out, with hover text explaining the level at which they unlock.
- Review both the existing generic skills that players can swap into their spell bar and each character’s own skills. Integrate both into a coherent unlock progression.
- Give players a useful starting kit and distribute unlocks thoughtfully as they level, considering complexity, combinations, and meaningful progression.
- Every existing ultimate ability unlocks at **level 20**. This includes the Wraith’s ultimate “untouchable” ability. Inspect the implementation to identify the correct ability and name.
- Characters without an ultimate do not need a new one invented for this overhaul.
- Enforce unlock requirements when equipping and using skills, including through the existing spell-bar swapping system. Handle previously equipped skills that become locked.

**Combat numbers and health**

Perform a comprehensive first balancing pass across every character’s health, attacks, and abilities.

- Use **levels 1, 5, 10, and 20** as explicit balance checkpoints, with sensible scaling between them.
- Review health, basic attack damage, ability damage, healing, shields, and other numerical combat effects wherever they exist.
- Balance characters against one another at each checkpoint, accounting for their roles, available skills, survivability, and damage potential. Balanced characters do not need identical stats.
- Preserve each character’s fundamental identity and the behavior of existing attacks and abilities. This pass changes combat numbers and skill unlock timing; it should not redesign their core mechanics.
- Make health bars and displayed combat values accurately reflect the revised numbers.
- Make the best practical first attempt using the current implementation and reasonable assumptions. Identify areas that will need playtesting afterward.

**Items and PvP rewards**

Dramatically reduce the current power contribution of items.

- Keep raw stat bonuses small. Gear should support playstyles and reward progression without creating overwhelming numerical advantages.
- Make high-end items exciting through useful PvP effects. **+5% movement speed** should feel like a standout reward.
- Reserve stronger utility or mechanical effects for exceptional level 20 items. Possible examples include:
  - An extra dodge/roll charge.
  - A shield effect.
  - Starting each battleground with a potion that grants invisibility for 20 seconds.
- Treat these as examples of the desired direction. Evaluate their strength, availability, and interactions before choosing and implementing a balanced selection.
- Prevent stacking bonuses and item combinations from recreating the excessive power gap we are trying to remove.
- Add more class-specific drops that are meaningfully rarer than general gear and support distinct class playstyles.
- Reduce the emphasis on ultra-rare random drops. Make desirable rewards come more from difficult content, accomplishments, or deliberate effort than extremely low drop chances.

**Admin testing shortcut**

Add an admin-only button labeled **“Go to level 20”**.

When used, it should:

- Set the current character to level 20 and update progression and derived stats consistently.
- Unlock all skills available to that character at level 20, including its ultimate if it has one.
- Equip a solid, class-appropriate baseline set of level 20 gear, suitable for representative PvP testing.

Use the existing admin system if available. Otherwise, add a persistent admin flag or role, with database support if necessary, and a way to designate our accounts as admins. Enforce authorization on the server as well as hiding the button from non-admins. Make repeated use safe without duplicating rewards or unintentionally destroying inventory.

Inspect the existing implementation first, then implement the overhaul using the project’s established patterns. Handle existing characters, equipment, and skill loadouts consistently.

Validate character balance at levels 1, 5, 10, and 20, skill unlocks, gear power differences, and the admin shortcut. Evaluate both equally skilled matchups and matchups with a substantial skill difference. Finish with a concise explanation of the changes, the unlock progression, representative combat numbers at each checkpoint, and remaining playtesting needs.
---

## Plan (Claude, 2026-11-02, working notes; kept here so the work survives a context reset)

Unlocks vs jj's unlock-all (2026-11-01): Blaine's spec wins for live play; `Data.SKILLS_UNLOCKED` stays as the one-line
switch back, and the F8 panel's "All skills" (`Game.test_allskills`) still opens everything for testing. jj asked.

1. **Unlocks** (data + the existing lock UI): class skills Q 1, E 3, R 5, F 9, G 14, V (the ultimate) 20; ultimates =
   Eternal Night (the Wraith's "untouchable": he hangs untouchable above the dark), Wrath of the Pit, The Last
   Epidemic, Clown Car. Doug: pie 1, peels 2, slide 4, doppel 7, juggle 10, bounce 14, car 20. Shared skills: War Cry 6,
   Frost Nova 8, Arc 11, Earthshatter 16. Locked bound skills stay on the bar greyed with their level (they light up
   when reached); unbindable while locked; refused on use (server-trusted client for now). `unlock_test`.
2. **Numbers** at levels 1/5/10/20: a PvP duel sim (`tools/pvp_sim.gd`: two bot heroes in an arena, skill = how
   often they dodge telegraphed hits and land skill shots) for every class pair, fresh vs geared; targets: equal skill
   -> geared wins >= 80%; big skill gap (0.9 vs 0.4) -> ungeared wins >= 40%. Tune class life/damage/skill numbers in
   `Data`, item stat ranges in `Items`.
3. **Items**: flat stats cut (gear <= ~25% of a level-20 character's power), PvP affixes (move speed +5% rare top
   roll, extra dodge charge / shield on hit / BG-start invisibility potion on level-20 uniques only, one each,
   never stacking), class-specific drops (rarer), fewer ultra-rare randoms; rewards from bosses/chests/achievements.
4. **Admin**: Go to level 20 exists (dev tools / admin key); server-side: the BG server refuses a hero whose
   level/gear can't come from its record (later; note).

## Status (2026-11-02, morning)

Done: (1) unlocks as planned; (2) the raid's gear rules; (3) class uniques with the free roll / ward, from the raid's
bosses and the golden chest; Go to level 20 (F8, dev tools / admin key only, safe twice). Tests: skill_unlock_test,
pvp_items_test, the nightly gate, bg_test, bg_pvp_test (with Doug).

`tools/pvp_sim.gd`, geared vs fresh of the same class (the gear's damage x speed and ehp; duels at 0.75 vs 0.75 skill,
and at fresh 0.9 vs geared 0.45):

| level | power (geared / fresh) | geared wins, equal skill | much better fresh player wins |
|---|---|---|---|
| 1 | x1.35 - 1.8 | 93 - 100% | 61 - 100% |
| 5 | x1.55 - 1.9 | 92 - 100% | 57 - 98% |
| 10 | x1.57 - 2.1 | 88 - 100% | 51 - 93% |
| 20 | x1.37 - 1.9 | 72 - 99% | 51 - 92% |

(Before: x2 - 7, a much better fresh player won 0 - 10% in most matchups.) Representative level-20 numbers in a raid,
fresh -> geared: knight life 326 -> 374, armour 9 -> 33, damage 18-34 -> 23-43; Doug 320 -> 357, 18-34 -> 19-37.

Still to do / needs playtesting:
- Plague Doctor (done, the one class change): his damage had a per-level part growing to twice anyone's (a Toxic
  Flask cloud ~60 a second at 19, every source stacking) and one Last Epidemic did ~600, more than a geared level-20
  player's ehp. Per-level parts x0.55, Volatile Mixture (16, 2.2, 0.5), the Epidemic's slam / collapse / dome /
  infection cut, its cooldown 24 -> 45 s like the other ultimates. Moving-target sim (`pvp_sim.gd -- moving`):
  level 10 39 -> 24 dps, level 20 121 -> 64 (45 of it without the Epidemic).
- Class against class otherwise: the sim's bot measures melee classes too low (it doesn't play the knight's combo or the
  demon's charges well) and the Warlock and Plague Doctor far too high against a target that never leaves their beams
  and clouds (190-270 dps at 20 against 25-50). A moving-target sim before retuning class numbers; until then no class
  numbers were changed. Warlock and Plague at 20 are the first thing to watch in playtests.
- The 20 s invisibility potion: left out (needs networked invisibility and an answer to it; 20 s outclasses the free
  roll and the ward). Candidates for a later pass: a 6 s version that breaks on attacking.
- Server-side checks of a raid hero's level and gear against the server's own record (the client is trusted today).
- PvE: items keep their full power outside the raid (Acts II-III are tuned on empowered gear); the balance sim says
  whether to bring the raid's rules out there.

## Status (2026-11-02, afternoon): the items rework, the sandbox, the admin role, the class pass

- **Items**: reworked for the whole game (`docs/queue_items_rework.md`), not only for raids. Since then:
  - the morning's raid-only shares are 1;
  - level-20 gear is worth about x1.6 power over none;
  - utility affixes and a signature effect on every unique;
  - boss loot tables with bad-luck protection, and the bonfire's Reforge;
  - burns and chills reach other players (Net.sv_pvp_dot / "chill").
- **The invisibility potion**: the Veilmother's Locket (level 20, Hrimgar and Mossbeard) gives a Shadow Phial at the
  start of each raid (`Game.give_raid_phials`). Drinking it makes you unseen for **6 s** (`Hero.invis_t`):
  - monsters lose you (`hidden_t`);
  - other players see a faint shimmer within 4 m (the state's bit 2, `Hero._show_invis`);
  - any blow, given or taken, and any cast end it.

  20 s was evaluated and cut: duels at level 20 last 5-20 s.
- **Admin**: the role is in Nakama, written by the server only (`tools/admin_role.sh`). The admin tools appear for an
  admin account in any build. The raid server turns away non-admins wearing "Go to level 20" gear
  (`tools/bg_admin_test.gd`). Saves are still client-written, so this stops honest clients, not a modified game.
- **The sandbox** (Escape -> Admin) and `tools/duel_sim.gd`: real bot duels.
  - **Level 20, geared** (8 duels a pairing; share of pairings won): knight 58, Wraith 58, Doug 57, Plague 50,
    demon 45, warlock 41, archer 38. The first reading had the Wraith at 100 and Doug at 13.
  - The knobs: `Data.PVP_CLASS` (PvP damage dealt and taken per class) and the Wraith's spirit damage (more from the
    weapon).
  - Geared beats fresh of its class 7-8 of 8, the Wraith 4 of 8 before his change.
  - Levels 1, 5, 10: running.
- **Needs playtesting**:
  - the bots play well but not like people: no line-of-sight tricks, no baiting;
  - 6 s invisibility against real players;
  - the act multipliers in Acts II-III by hand (the sim's bands pass);
  - the Plague Doctor and the warlock in real raids.

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
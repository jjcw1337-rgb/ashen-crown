# Multiplayer overhaul: plan and progress

Blaine's spec (2026-11-06, Discord attachment): Battlegrounds-centred multiplayer, Arena the other mode; fresh run
characters from level 0 in Battlegrounds, survivors saved at a successful exit and used in Arena; five active skill
slots (right-click included) plus a spellbook; passive power-ups instead of talents; camp chests offering three
upgrades; four consumable slots, no gold/rings/amulets, no backpack; a large lush map (12-16 camps, an ice boss and a
mushroom boss); a modern fantasy (Valorant-inspired) UI; single player and Enter World untouched; Waves and Create
Character retired. This file is the working plan: each step is pushed to staging when it plays.

## Steps

1. [x] **Mode switch + retirements** (`MpMode`, docs/cleanup.md): Waves and Create Character off. `ce9f830`.
   Authority audit: docs/multiplayer_authority.md. `2f34d20`.
2. [x] **Run character** (`RunBuild`, on the hero only in Battlegrounds/Arena): level 0, basic attack, five slots
   (RMB Q E R F) + spellbook, passives feeding `Hero.tfx` instead of talents, four consumable slots (the belt), no
   gold/rings/amulets/backpack (found gear is equipped or left on the ground, with a comparison).
3. [x] **Camps + rewards**: camps as encounters (tier 1-3, boss), completion opens the camp's chest, one upgrade
   offer of three (common/uncommon/rare, generated once, claimed once), XP from kills and camps, levels 0-20+.
4. [ ] **Survivors**: successful extraction -> results -> Save Character (no duplicates) -> survivor roster
   (`user://survivors/`, separate from single-player characters) -> Arena lobby picks a survivor.
5. [x] **The map** (`BgForest`, the Verdant Reach; first pass): a lush connected forest (mushroom woodland, dark elf camps, ridges, streams, ruins), 12-16 camps,
   the ice boss and the mushroom boss.
6. [ ] **UI redesign**: multiplayer entry, lobby browser, lobby prep with class tiles, survivor roster, reward panel,
   results; modern fantasy (charcoal, deep green, ivory text, gold/arcane accents).
7. [ ] **Verification** with the archer and the plague doctor: level 0 -> camps -> upgrades -> skills/loot -> levels
   -> bosses -> survive -> save -> reload roster -> Arena; then the write-up (implemented / verified / retained
   legacy / hosting limits).

## Notes

- Authority today is client-trusted (docs/multiplayer_authority.md): survivors and Arena results are not
  tamper-proof; say so, don't claim otherwise.
- Blaine (2026-11-06): the Battlegrounds map is a whole rebuild, no corridors; the old crypt map goes completely
  once the forest map is in (its rooms host the camps meanwhile).
- Peak Ruins (jj's snowy map) is parked on `test-peak-ruins`; it can come back as a second map.

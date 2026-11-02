# Items rework (Blaine, 2026-11-02: "not 'cut' but full rework")

Follows the progression overhaul (`docs/queue_progression_overhaul.md`, "Items and PvP rewards"). The first pass only
changed gear inside the Battlegrounds (`Data.PVP_*`, `Hero.pvp_scaled`); everywhere else items kept their full power.
This replaces that with one item system for the whole game.

## Goals (from the spec)

- Character level and skills give most of a player's power; gear gives smaller but meaningful advantages.
- PvP utility makes high-end items exciting; +5% run speed is a standout reward.
- Strong mechanical effects only on exceptional level-20 items.
- Stacking can't rebuild the old gap.
- More class-specific drops, rarer than general gear.
- Desirable rewards come from hard content, accomplishments and effort, not tiny drop chances.

## 1. Power budget

Best-in-slot gear at a level is worth about **+25-35% power** (damage x effective life) over a fresh character of the
same level, in PvE and in PvP. Measured by `tools/pvp_sim.gd` (geared / fresh power, the duel targets) and
`tools/balance_sim.gd` (the act bands).

## 2. Bases

- **Weapons**: damage follows the character's level (what the raid does today, `Data.pvp_damage`), everywhere. The
  base sets the kind, the speed and a quality of 0.9-1.05 (a base made for a higher level hits a little harder). A
  weapon is chosen for how it plays, not for a 6x damage gap.
- **Armour**: base defence counts for about a third of today's.
- **Shields**: block stays (the knight's identity); their defence is cut like armour.

## 3. Affixes

| Group | Stats | Size (level 20, rare) |
|---|---|---|
| Core | Strength, Dexterity, Vitality, Energy, Life, Mana, Defense, Enhanced Defense | about a third of today's |
| Combat (capped) | Enhanced Damage, +Damage, Fire Damage, Attack Speed, Life Steal, Resist All, Block | small; caps across all gear |
| Utility (new) | Run speed 1-3% (up to 5% on level 18+ rares), dodge stamina cost -5-10%, cooldowns -3-6%, potion healing +10-20%, shorter stuns and slows -10-20% | at most one per item |
| Economy | Gold Find, Magic Find | unchanged (no power) |

- Magic items roll 1-2 affixes (as now), rares 2-3 (were 3-5).
- **Caps across all gear**: run speed 5%, attack speed 25%, resist 25%, life steal 4%, cooldowns 10%, crowd-control
  reduction 30%, block 15%.

## 4. Uniques

Every unique is rebuilt with smaller stats plus **one signature effect** from a small shared set:

- ward (a shield of life that refills out of combat)
- free dodge roll
- set foes burning on hit
- chill foes on hit
- heal on kill
- a burst of speed after a dodge

Effects work everywhere, not only in raids. Two items with the same effect don't stack; the stronger one counts.
The seven level-20 class uniques keep their effects. The strong ones stay level 20 and come only from bosses.

## 5. Where rewards come from

- Random uniques from ordinary monsters drop from 1.2% to about 0.3% (a rare surprise, not the main path).
- **Each boss has its own loot table** of 2-3 uniques:
  - the first kill guarantees one;
  - every kill without one raises the next chance (bad-luck protection).
- Quests, the dwarves' game and the golden chest give named rewards.
- **Crafting (effort)**: the smith rerolls one affix of a rare for a material (Cinderheart, Everfrost, Stormglass).
- Tempering (+6% damage a level, x5) and enchanting are scaled to the new budget.

## 6. Acts II-III and the Battlegrounds

- A2/A3 loot keeps its act multiplier on base damage, defence and core stats (not on combat or utility).
- The act monsters are retuned with the balance sim.
- In a raid, act multipliers are ignored and the stricter raid caps apply.
- The duel targets (geared beats fresh at equal skill, a much better fresh player can still win) are re-checked.

## 7. Old saves

Every saved item is rebuilt once (`"gen": 2`):
- affixes rescaled to the new ranges;
- rares trimmed to their best 3;
- uniques regenerated from the table by id, keeping enchant and temper.

Nothing is deleted. This covers the stash and the Battlegrounds stash as well as characters.

## 8. Tooltips

- Tooltips show the real numbers.
- A weapon shows your damage with it at your level.
- Effects are described in words.
- The equipped item is shown for comparison.

## Build order

1. Data, rules, migration, tooltips.
2. Utility affixes (hooks in Dodge, skill_cd, potions, stun/slow).
3. Unique effects.
4. Sources (boss tables, bad-luck protection, crafting).
5. Both sims, then retune the acts and classes.
6. The write-up.

## Status

- 2026-11-02, step 1 done:
  - affix scales, rare count, armour share and caps;
  - level-based weapon damage;
  - the save rebuild;
  - tooltips;
  - enchant and temper scaled;
  - act power ×1.6/×2.4 with new act monster multipliers.

  Level-20 gear: ×1.45 power over none (was ×6.7); a starting sword against a rare flamberge at level 20: ×1.1 (was
  ~×4). Balance sim: 15 flags, 0 deaths (before the rework 15 flags; with the cut alone 39 flags and deaths in every
  A2/A3 boss).
- Also built: the Battlegrounds sandbox (Blaine: "do the sim first") for testing classes and items by hand against
  bots and monsters.
- Next: steps 2 (utility affixes), 3 (unique effects), 4 (sources); then the class pass with the sandbox's bots.

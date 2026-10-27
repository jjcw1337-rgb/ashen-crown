# Balance protocol

How we keep Act I, A2 and A3 feeling right as classes, items and monsters change. It's built
to run unattended (a nightly job) and to be read by a person or by Claude.

## What it measures

`tools/balance_sim.gd` plays the game headless. For every class and every **checkpoint** it
builds a plausible character and sends an autopilot into real fights against the real
monsters:

| Checkpoint | Where | Character |
|---|---|---|
| A1 moor | Act I wilderness packs | level reached 40% through Act I, ilvl 3 gear |
| A1 boss | the Hollow Matron | level after clearing Act I, ilvl 6 gear |
| A2 arrive | A2 wilderness packs | same level, still in **Act I gear** (the wall you hit when you start A2) |
| A2 moor | A2 wilderness packs | 40% through A2, the same gear at A2 strength |
| A2 boss | the Matron in A2 | after clearing A2 |
| A3 moor / A3 boss | A3 packs / the Ashen King | likewise, A3 gear |

- **Levels** come from the content: the sim loads each zone and adds up the experience a
  player gets for clearing it, with the game's falloff for monsters below your level.
- **Gear** is the best base item you could wear at that point, magic, with fixed rolls, so
  A2 gear is exactly the Act I gear at A2 strength.
- **The bot** casts its skills when they'd do something (buffs first, then area skills,
  then its attack skills), attacks the nearest foe otherwise, and drinks a potion below
  45% life. At the Matron it goes for the Mourner with her heart, like a player who kept
  track of it.

Per checkpoint it records:
- `pack_s`: seconds to wipe a pack (the 3 packs nearest the zone start, averaged)
- `pack_hurt`: life lost per pack, as a share of max life (potions put some back, so it can
  pass 1)
- `boss_s` and `boss_hurt`: the same for the boss
- potions drunk, and whether the character died

## Targets

The bands are `BANDS` in `tools/balance_sim.gd`:
- **Act I** is checked in absolute terms; it's the anchor.
- **Kill times in later runs** are checked as a ratio to the same class's Act I numbers, so
  the bot's skill cancels out. For example, A2 packs should take 0.9–1.6× as long as Act I
  packs once you have A2 gear, and 1.2–3× when you first arrive in Act I gear.
- **Life lost** is checked as a plain share of max life.
- **A death** always flags.

Anything outside its band prints a `[BAL-FLAG]` line.

## Running it

```
tools/balance.sh                    # all classes, about 30 s on a desktop CPU; GODOT=/path/to/godot if not on PATH
tools/balance.sh classes=warlock    # one class
tools/balance.sh quick              # A1 moor, A2 arrive and A2 moor only
```

Each run writes `build/balance/<date>.json`, `.log` and `.txt`, plus `latest.json` and
`latest.txt`; `build/` is git-ignored.
- Exit code 0: nothing flagged.
- Exit code 2: something flagged.
- Exit code 1: the sim itself broke.

## The tuning knobs

| What | Where |
|---|---|
| Run multipliers (monster life, boss life, monster damage, loot, xp) | `Data.RUNS` |
| Monster base stats | `Data.ENEMIES` |
| Item bases and affixes | `Data.BASES`, `Data.AFFIXES` |
| Which bonuses A2/A3 loot multiplies | `Items.empower`; percentages in `Items.PCT_STATS` stay as rolled |
| Skill damage | `Hero._impact` (and `_update_drain`, `_blight_burst` and friends) |
| The Matron's mechanic | constants at the top of `scripts/matron.gd` |

## The protocol (each run)

1. Run `tools/balance.sh` on `main`.
2. If nothing flagged, stop.
3. For each flag, decide whether it's the **content** (a number is off), the **bot** (it plays a
   class badly, e.g. walks into a wall) or the **band** (the target was wrong). Only the first
   is a tuning change; fix the bot or the band in `balance_sim.gd` otherwise.
4. Change one knob at a time, the smallest change that moves the number back into its band.
   Prefer run-wide knobs (`Data.RUNS`) for "a whole run is too hard", and class or monster
   numbers for "one class or one fight is off".
5. Re-run and check the change didn't push something else out of its band.
6. Run the normal tests (`CLAUDE.md`) and put the change on a branch or a PR with the before
   and after `[BAL]` lines. Don't push balance changes to `main` unattended: a push publishes
   the game.

## History

- **2026-10-27, first pass.**
  - A2 was 20× monster life and damage against 5× loot. The sim had every class dying at the
    A2 boss and taking 2–6× as long per pack as in Act I.
  - `Items.empower` was also multiplying percentage bonuses, so A2/A3 items could roll 100%+
    resist or life steal. Now only flat stats scale.
  - New run multipliers: A2 is 6× life, 4× boss life, 5× damage; A3 is 24×, 10× and 15×.
    Result: A2 packs take about 1.0–1.6× as long as Act I, no deaths on A2 packs or the A2
    boss.
  - The Hollow Matron's heart mechanic (`matron.gd`) replaced her zombie summons; every
    class now beats her in 15–50 s.
  - Still flagged:
    - The Ashen King (A3 boss) is slow for everyone but the Demon.
    - Spell damage scales mostly with level, not gear, so the Warlock falls behind in A2/A3
      boss fights.

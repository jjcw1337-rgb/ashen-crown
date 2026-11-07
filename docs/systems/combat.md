# Combat

How a hit becomes damage, and who decides it.

## A hit

```mermaid
sequenceDiagram
  participant A as Attacker's game
  participant S as Host or match server
  participant E as Every game
  Note over A: the skill finds the hit
  Note over A: Hero._hit_enemy works out the damage
  A->>S: sv_enemy_hit (the finished number)
  Note over S: Enemy.take_damage: armour, marks, life
  S-->>E: the monster's life and death
  A-->>E: fx events (the arrow, the hit)
```

- A skill finds what it hit on the attacker's game and calls `Hero._hit_enemy(e, mult, knock, src)`
  (`scripts/hero.gd`). That rolls the weapon's damage, crit, rites and buffs, and the skill's own power.
- `Enemy.take_damage` (`scripts/enemy.gd`) applies armour and marks. On a player's game the monster is a copy, so the
  numbers go to the host (`Net.sv_enemy_hit`), which applies them.
- **Monsters** run only on the host. Their hits on a player are applied by that player's own game (`Hero.take_hit`).
- **PvP:** other players are invisible `Enemy` stand-ins. A hit sends the attacker's number to the server
  (`Net.sv_pvp_hit` → `Battlegrounds.pvp_hit`), which checks the pair and scales it.

## Statuses

- **Monsters** carry burn, chill, stun and slow, and tags such as Hunter's Mark, in `enemy.gd`.
- **Players** take crowd control through `PvpStatus` (`game/systems/combat/pvp_status.gd`): stagger (a stun), knockup, pull,
  fear, slow, burn and more. The server checks it, and hard crowd control has diminishing returns. New crowd control
  on players goes through `PvpStatus`.

## Rites and gems

`game/items/run_talents.gd` holds what rites and gems do. They hook into combat at fixed points: before and after a
hit (`hit_mult`, `on_hit`), on a kill, when struck, on a cooldown, every frame, and on a shot.

## Who decides

**The Archer's skills run on the match server** (`game/systems/skills/server_rules.gd`). In a Battlegrounds, Arena
or Sandbox match his game sends what a skill makes (an arrow, a rain, a sigil); the server's copy of him makes it,
decides who it hits with its own positions and its own stand-ins for players, and deals the damage from the build his
game sends it (level, attributes, the run's skills, rites and gems). His wolf bites there and his rites fire there
(`Hero.decides`); what they do to him (life back, a buff, a cooldown) goes back to his game (`Net.tell_self`).

Every other hero's game still decides its own damage, cooldowns and mana, and the server trusts it (PvP numbers are
clamped). The host or match server decides monsters, deaths and loot. Each hero moves onto the server as it moves
onto the skill layout ([skills](../content/skills.md)). There is no combat log yet.

# The loot list (game/ui/loot_list/)

Hold **Ctrl** in a world: every item on the ground within 18 m is listed top left, nearest first, in its rarity's
colour with its distance. Hovering a row lights the item's label; a click sends the hero to pick it up (if his walk
stops short at a footprint's edge, he takes it from 1.6 m, or is sent on). Releasing Ctrl hides it.

| File | What |
|---|---|
| `loot_list.gd` | `LootList` (UI.loot_list, made by `LootList.attach`) |
| `tests/loot_list_test.gd` | Ctrl shows it, nearest first, nothing past its range, a click picks the item up, release hides it |

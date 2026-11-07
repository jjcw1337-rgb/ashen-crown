# Stash chests

Every stash chest, numbered as they're added (jj). The game reads the same list from `scripts/stash_chests.gd`
(`StashChests.CHESTS`); a chest's fire colours are `Battlegrounds.STASH_THEMES`. Renders are in `previews/`.

| # | Name | Model | Dais | Fire | Used on | Notes |
|---|---|---|---|---|---|---|
| 1 | Ember Chest | `chest_01.glb` | `dais_01.glb` | red (`ember`) | saved for the next map | The first raid chest: Meshy camp concept A rebuilt from seven Meshy parts in Blender, gold wolf seals (jj's pick B). |
| 2 | Spirit Chest | `chest_01.glb` | `dais_01.glb` | blue (`spirit`) | **Battlegrounds: The Hollow Crypt** (the antechambers' stash) | Chest #1 burning blue: the camp waypoint's spirit-fire in the bowls, the spray, the coals and the seals' glow. |
| 3 | Void Chest | `chest_01.glb` | `dais_01.glb` | purple (`void`) | kept in the list for a map to come | Chest #1 burning purple: violet spirit-fire in the bowls, the spray, the coals and the seals' glow. |

Previews: `previews/01_ember_closed.jpg`, `01_ember_open.jpg`, `02_spirit_closed.jpg`, `02_spirit_open.jpg`, `03_void_closed.jpg`, `03_void_open.jpg`, and the
model alone in studio light, `chest_01_model.jpg`.

## Adding a chest

1. Its model here as `chest_NN.glb` (and `dais_NN.glb` if it has its own dais). The rebuild script is
   `tools/blender/camp/assemble_chest.py`, the dais `tools/blender/camp/build_stash_dais.py`; Blender sources and Meshy
   parts live outside the repo in `~/Documents/Blender/Game Factory/exports/stash/chest/NN_name/`.
2. An entry in `StashChests.CHESTS` (name, model, dais, theme, the maps that use it). A new fire colour is a new
   `Battlegrounds.STASH_THEMES` entry (and `StashDais.THEMES` for its dais).
3. A row in the table above, and its renders in `previews/` (the raid stash is retired; its render tool was deleted).

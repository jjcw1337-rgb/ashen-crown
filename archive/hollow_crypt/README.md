# The Hollow Crypt (archived)

The Battlegrounds' first map (2026-11): a dungeon of rooms round a great hall, two floors below (the Frozen Depths
and the Overgrown Roots), an antechamber with iron gates and bells, and three raid stash chests on fire-lit daises.
The Verdant Reach replaced it. What's here is the good art, kept for a future map:

| Folder | What |
|---|---|
| `models/` | Meshy pieces, re-baked on clean UVs: archway (the rune gate the Extraction Portals stood in), brazier, iron-bound chest, ossuary niche, sarcophagus, the golden boss chest |
| `textures/` | the crypt floor (albedo, normal), cobwebs, the floor seal (and its glow) |
| `stash_chest/` | the raid stash chest and its dais, previews of its three fires (ember, spirit, void), CHESTS.md, the dais's Blender build |

The pillar, sconce, candles, bones and the wall stone live on in the Arena (`game/maps/arena/props/`, `textures/`).
The code that built the crypt (`battlegrounds.gd`'s builder, `bg_floors.gd`, `crypt_props.gd`, `stash_chests.gd`,
`stash_dais.gd`) is in git history before this folder was made. To use a model again, move it under `game/maps/<map>/`
(this folder has a `.gdignore`: Godot neither imports nor exports it).

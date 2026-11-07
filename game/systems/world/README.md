# The world (game/systems/world/)

What every map is built on. A map (`game/maps/<map>/`) builds its zone on a `World`; these are the pieces.

| File | What |
|---|---|
| `world.gd` | `World`: a zone's ground (relief, terrain shader, paths), its collision grid and pathfinding (AStarGrid2D, `free_spot_near`, `los`), spawns, interactables, chests, and `build` (which map builds which zone) |
| `props.gd` | `Props`: shared props and materials (fire, iron, stone, footprints, multimeshes, see-through) |
| `map_kit.gd` | `MapKit`: a prepared Meshy prop placed with its footprint, facing a point, merged meshes, a clip's root pinned |
| `flora.gd`, `grass.gd`, `grass_field.gd` | trees and plants; the living grass (`GrassField`) |
| `weather.gd` | rain, wind and fog |
| `grade.gd` | `Grade`: the colour grade and shadow budget |
| `geo.gd` | `Geo`: procedural meshes (boxes, cylinders, spheres) |
| `inter.gd` | `Inter`: an interactable (a chest, an Extraction Portal, the bell) |
| `tests/` | `grass_test`, `collision_test`, `grass_bench` |
| `tools/` | `grass_lab`, `grass_closeup`, `flora_shot`, the grass atlas scripts |

Rules never draw: on the stripped server the world builds its collision and footprints, never its meshes' looks.

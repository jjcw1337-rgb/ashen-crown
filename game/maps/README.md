# Maps (game/maps/<map>/)

One folder per map: its builder, its pieces (props, textures), the modes played on it, its tests and tools. The map
registry (`maps.gd`, `Maps`) is the one place that knows which map builds which zone; Game and World ask it and
never name a map.

| Map | Zones | What |
|---|---|---|
| `verdant_reach/` | `bg` | The Battlegrounds: a PvPvE forest of monster camps and three bosses (BgForest; the raid's rules in `battlegrounds.gd`) |
| `arena/` | `arena`, `sandbox` | The stone hall of the Arena (team fights) and the Sandbox (practice) (ArenaMap) |

**Adding a map:** a folder with its map script, which declares (see `maps.gd`):
- `const ZONES`, `const INDOOR`, `const MUSIC` (`{"song", "amb", "db"}`), `const LOADING_ART`;
- `static func build(w: World)`, `static func title(zone)`, and optionally `static func light(g, zone)`.

Then add it to `Maps.all()`. Its props go in `props/`, tests in `tests/`, tools in `tools/` (exports skip both). The
zone's preload list comes from `--preload-record` (game/systems/loading/). Camps are rows of a map's camp table
(`verdant_reach.gd` `CAMPS`), and a boss camp names its boss's kind (game/monsters/).

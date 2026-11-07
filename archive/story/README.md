# The story's assets (archive/story/)

The story mode past the starting camp is cut (Blaine, 2026-11-06: Enter World stays, as the camp alone). Its code
(the moor, Grubb's fort, the Sloths' lairs, the Imperial Road, Aurelia and its games, the Ashen King's crypt, the acts)
is deleted; git keeps it (`scripts/fort.gd`, `via.gd`, `aurelia.gd`, `games.gd`, `roman.gd`, `sloth_lair.gd`, and
`World._build_wild` / `_build_lair` in `scripts/world.gd`). Its good assets are here. Godot ignores this folder
(`archive/.gdignore`): nothing in it is imported or shipped. Move a piece back into a map's `props/` to use it.

| Here | What |
|---|---|
| `assets/models/fort/` | Grubb's fort (Meshy): the gatehouse, the great hall, a hut, the palisade. Its watchtower is live in `game/maps/verdant_reach/props/tower.glb` |
| `assets/models/lairs/` | the Hollow Sloths' lairs: lava rock and burning tree (fire), ice crystals (cold), rune stone and split tree (storm). The ice rock is live in `game/maps/verdant_reach/props/` |
| `assets/models/roman/` | the Imperial Road and Aurelia (Meshy): the aqueduct and its ruin, the arena's arcade and podium, a brazier, a cypress, a fountain, a milestone, the emperor's statue, two tombs, the city wall and its gate tower. The arch, broken column, column and drum are live in `game/maps/verdant_reach/props/` |
| `assets/models/monsters/ashen_king.glb` | the Ashen King (Act III's boss, Meshy) |
| `assets/models/rocks/kerb.glb` | the kerbstone along the moor's kingsroad and the Imperial Road (Meshy; modelled lying along x) |
| `assets/textures/ui/wp_act2.png`, `wp_act3.png` | the waypoint window's Act II and Act III banners |
| `assets/textures/grass/flower_sun.png` | the moor's rare Sunstar Bloom, painted for a camera-facing card (Flora's grass cards) |
| `assets/audio/sfx/crowd_*.wav` | the arena games' crowd: its roar and its cheers (credits in `assets/audio/CREDITS.md`) |

The Ashen King's rig for `MeshyMonster.MODELS` (`scripts/meshy_monster.gd`), with the model's path here:

```
"ashen_king": {"glb": "res://archive/story/assets/models/monsters/ashen_king.glb", "height": 1.9, "layout": {"hips": ["", Vector3(0.0, 0.874, -0.0752)], "torso": ["hips", Vector3(0.0, 0.988, -0.0752)], "head": ["torso", Vector3(0.0, 1.526, -0.0701)], "sh_r": ["torso", Vector3(0.19, 1.355, -0.0341)], "el_r": ["sh_r", Vector3(0.3338, 1.1424, -0.0467)], "hand_r": ["el_r", Vector3(0.4665, 0.9462, -0.0583)], "sh_l": ["torso", Vector3(-0.19, 1.355, 0.0487)], "el_l": ["sh_l", Vector3(-0.3307, 1.1455, 0.0019)], "hand_l": ["el_l", Vector3(-0.4606, 0.9521, -0.0414)], "leg_r": ["hips", Vector3(0.095, 0.874, 0.0065)], "knee_r": ["leg_r", Vector3(0.1975, 0.4658, 0.0241)], "leg_l": ["hips", Vector3(-0.095, 0.874, -0.0197)], "knee_l": ["leg_l", Vector3(-0.1581, 0.463, 0.0181)]}},
```

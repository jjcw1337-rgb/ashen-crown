# The Necromancer (game/heroes/necromancer/)

A lich-priest in grave-rune robes behind a skull mask, a lantern of trapped souls at his belt (jj, 2026-11-07: "a
necromancer... a graveyard summon skill, use the waypoint resources... meshy and blender"). Built like every hero
([heroes](../../../docs/content/heroes.md)): his skills script `necromancer.gd`, his look `necromancer_fx.gd`, his
numbers and text `data/codex/heroes/necromancer.json`.

| | |
|---|---|
| `body/` | `necromancer.glb`: the Meshy model with 17 Meshy library clips on its rig (`build/prep_necromancer_mocap.py`), played by `Knight.build_mocap` (`necromancer_body.gd`: his moves -> clips) |
| `weapon/` | `grave_scythe.glb`: his scythe-staff (Meshy text-to-3D, `tools/blender/prep_prop.py`), the class weapon `grave_scythe` |
| `skills/bone_bolt/` | Bone Bolt (right mouse): a shard of bone that pierces one foe. Rules `bone_bolt.gd` (a Missile), look `bone_bolt_fx.gd`, `bone_shard.glb` (Meshy) |
| `skills/graveyard/` | Graveyard: a graveyard torn up at the pointer for 8 s; its 4 risen dead (the game's zombies and bone archers) strike the foes inside every second, and its chill slows them. Rules `graveyard.gd` (a GroundZone), look `graveyard_fx.gd` + `graveyard_site.gd`; `props/`: the old waypoint's dais, guardian, pillar and brazier and its rune rings (from `archive/camp/`), gravestones (Meshy) |
| `tests/` | `necromancer_test.gd`: his body, clips, staff and binds; Bone Bolt strikes and pierces; Graveyard rises, its dead strike and slow the foes inside and leave one outside alone, and it's gone after its time (with a folder: shots from the game camera) |

The skill icons are `assets/textures/skills/bone_bolt.png` and `graveyard.png` (`tools/skill_icons.py necromancer`;
the grid's seven spares are for the rest of his kit).

**Sources (Meshy, jj's key):**
- Concepts: three takes; take 2 (the lich-priest) was built. They're kept, with every task record, in
  `~/Documents/Game Factory Art/necromancer/` on the Game Factory Mac.
- Body: edits to empty hands and no mist; image-to-3D 01a1b542-ee7b-7249-8321-6930e65ade97; rig
  01a1b545-9366-70e2-b3e1-896c7d568fe1.
- Clips 0, 12, 30, 14, 16, 509, 21, 178, 189, 158 / 127, 125, 129, 130, 131, 132, 342.

**Next:** the rest of his kit (six more skills and their rites; the codex's directions Grave, Bone and Soul), his own
sounds (ElevenLabs), and a pick between the three concepts.

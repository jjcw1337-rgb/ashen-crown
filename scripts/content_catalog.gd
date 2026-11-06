extends RefCounted
## Presentation dependencies. Godot loads imported dependencies of these roots itself.
## Dynamic skill paths live in named families; adding content to an existing family needs no warm-list edit.
## Simulation dependencies remain in World/Enemy: dedicated servers must not request these bundles.
const LOBBY_ART := {"battlegrounds": "res://assets/textures/ui/mp_battlegrounds.jpg",
	"arena": "res://assets/textures/ui/mp_arena.jpg", "sandbox": "res://assets/textures/ui/mp_arena.jpg"}
const FX_DIRS := ["res://assets/models/fx", "res://assets/textures/fx"]
const CLASS_DIRS := {
	"archer": ["res://assets/models/arrows", "res://assets/textures/ranger"],
	"plague": ["res://assets/models/plague", "res://assets/textures/plague"],
	"doug": ["res://assets/models/doug"]}
const CLASS_ROOTS := {
	"knight": ["knight_mocap.glb", "knight_meshy.glb"], "demon": ["demon_mocap.glb"],
	"plague": ["plague_doctor.glb"], "archer": ["archer_ranger.glb", "ranger_bow.glb"],
	"doug": ["doug.glb"], "wraith": ["wraith_mocap.glb"], "warlock": ["gnome_warlock.glb"],
	"wyrm": ["dragons/wyrm.glb"], "serpent": ["dragons/serpent.glb"], "wyvern": ["dragons/wyvern.glb"]}
# Builders stay responsible for placement. These families declare dynamically chosen asset roots;
# recorded exact paths supplement them, rather than being the only coverage for a map.
const COMMON_ZONE := ["models/props", "models/rocks", "models/waypoint", "models/stash", "textures/waypoint"]
const OUTDOOR := ["models/grass", "textures/grass", "models/trees", "models/boats", "models/coast", "models/isles"]
const ZONE_FAMILIES := {
	"town": ["models/camp", "models/island", "models/npc", "models/guards", "models/roman", "textures/space"],
	"wild": ["models/roman"], "lair": ["models/fort", "models/roman", "models/crypt", "textures/crypt"],
	"bg": ["models/bg", "models/crypt", "textures/crypt"],
	"arena": ["models/crypt", "textures/crypt"], "vigil": ["models/crypt", "textures/crypt"], "coast": ["models/npc"]}
const EXTENSIONS := ["glb", "tscn", "tres", "png", "jpg", "jpeg", "webp"]
static var _families := {}

## Imported model scenes already own their texture dependencies. Extracted JPG/PNG
## files beside a GLB are importer artifacts, not additional presentation roots.
static func family_roots(dir: String) -> Array:
	var paths := files(dir)
	if dir.begins_with("res://assets/models/"):
		return paths.filter(func(p): return str(p).get_extension() in ["glb", "tscn", "tres"])
	return paths

static func files(dir: String, recursive := true) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for file in da.get_files():
		var name := file.trim_suffix(".remap").trim_suffix(".import")
		if name.get_extension() in EXTENSIONS:
			var path := dir.path_join(name)
			if not out.has(path):
				out.append(path)
	if recursive:
		for sub in da.get_directories():
			out.append_array(files(dir.path_join(sub)))
	out.sort()
	return out

static func combat(classes: Array = []) -> Array:
	if not _families.has("combat"):
		var paths: Array = ["res://scripts/demon_mocap.gdshader", "res://scripts/wraith_mocap.gdshader"]
		for dir in FX_DIRS:
			paths.append_array(family_roots(dir))
		_families["combat"] = paths
	var result: Array = (_families["combat"] as Array).duplicate()
	for cls in (CLASS_ROOTS.keys() if classes.is_empty() else classes):
		if cls == "archer": result.append(SpiritBeast.WOLF_GLB)
		for dir in CLASS_DIRS.get(cls, []):
			if not _families.has(dir): _families[dir] = family_roots(str(dir))
			result.append_array(_families[dir])
		for path in CLASS_ROOTS.get(cls, []):
			result.append("res://assets/models/" + str(path))
	return result

static func zone(run: int, name: String) -> Array:
	var forest := name == "bg" and MpMode.FOREST
	# The recorded BG list predates Verdant Reach and describes the retired crypt.
	var paths: Array = [] if forest else (ZonePreloadData.PATHS.get("%d:%s" % [run, name], []) as Array).duplicate()
	# World torches/fires are needed even when no combat bundle is requested.
	paths.append_array(["res://assets/textures/fx/fire_tongue.png", "res://assets/textures/fx/fire_body.png"])
	if forest:
		paths.append_array(["res://assets/models/camp/runestone.glb", "res://assets/models/camp/tent.glb",
			"res://assets/models/camp/lantern_post.glb", "res://assets/models/camp/cookfire.glb",
			"res://assets/models/camp/weapon_rack.glb",
			"res://assets/models/fort/tower.glb", "res://assets/models/lairs/ice_rock.glb"])
	if name == "town": paths.append_array(LOBBY_ART.values())
	var family := "isle" if name.begins_with("isle_") else ("arena" if name == "sandbox" else name)
	if family in ["bg", "arena"]:
		# Reward cards and newly learned run skills first appear during play.
		for dir in ["res://assets/textures/skills", "res://assets/textures/gems"]:
			if not _families.has(dir): _families[dir] = files(dir)
			paths.append_array(_families[dir])
	# The procedural PvP hall and Vigil use crypt props, not outdoor rocks, Roman
	# scenery or town waypoint/stash models. Keep those bundles out of their residency.
	var dirs: Array = [] if forest or family in ["arena", "vigil"] else COMMON_ZONE.duplicate()
	if forest:
		dirs.append_array(["models/bg", "models/props", "models/rocks", "models/trees", "models/grass", "textures/grass"])
	else:
		dirs.append_array(ZONE_FAMILIES.get(family, []))
	if family in ["town", "wild", "coast", "isle"] or (family == "lair" and run == 0):
		dirs.append_array(OUTDOOR)
	for dir in dirs:
		var key := "zone/" + str(dir)
		if not _families.has(key):
			# Imported GLB dependencies include their extracted textures; request model roots only.
			var found := files("res://assets/" + str(dir))
			_families[key] = found.filter(func(p): return not str(dir).begins_with("models/") or str(p).ends_with(".glb"))
		for path in _families[key]:
			if not paths.has(path): paths.append(path)
	return paths

class_name Maps
extends RefCounted
## The map registry: which map builds each zone, and how the zone presents itself. A map is a folder
## (game/maps/<map>/) whose map script (one listed in `all`) declares:
##
##   const ZONES := [...]                the zone ids it builds (World.kind)
##   const INDOOR := bool                under a roof (no sky, the hero's light carries the room)
##   const MUSIC := {"song": "", "amb": "none", "db": -6.0}   Sfx.play_music's song key ("music_<song>" in the bank,
##                                       "" for none), the ambience bed under it ("none": silence) and the song's level
##   const LOADING_ART := ""             a painting behind the loading screen's words ("" for black)
##   static func build(w: World)         builds the zone on `w`
##   static func title(zone) -> String   the zone's name on screen
##   static func light(g: Node, zone)    its sky, sun, fog and grade, over the indoor or outdoor base (client only)
##
## Game and World ask here (Maps.of, build, title, indoor, music, light, loading_art) and never name a map, so a new
## map is a folder and one line in `all`. Systems never name a map.

## The maps: one line per map folder.
static func all() -> Array:
	return [BgForest, ArenaMap]

## The map script that builds `zone`, or null.
static func of(zone: String) -> Script:
	for m in all():
		if zone in (m as Script).get_script_constant_map().get("ZONES", []):
			return m
	return null

static func _const(zone: String, key: String, fallback: Variant) -> Variant:
	var m := of(zone)
	return m.get_script_constant_map().get(key, fallback) if m != null else fallback

## Builds `w`'s zone (World.build). False when no map has it.
static func build(w: World) -> bool:
	var m := of(w.kind)
	if m == null:
		return false
	m.call("build", w)
	return true

static func title(zone: String) -> String:
	var m := of(zone)
	return str(m.call("title", zone)) if m != null else ""

static func indoor(zone: String) -> bool:
	return bool(_const(zone, "INDOOR", false))

## {"song", "amb", "db"}: what plays in the zone (no map: silence).
static func music(zone: String) -> Dictionary:
	var d: Dictionary = {"song": "", "amb": "none", "db": -6.0}
	d.merge(_const(zone, "MUSIC", {}), true)
	return d

static func loading_art(zone: String) -> String:
	var p := str(_const(zone, "LOADING_ART", ""))
	return p if p != "" and ResourceLoader.exists(p) else ""

## The zone's own light over the base Game._zone_env set (its sky, sun, fog, grade).
static func light(g: Node, zone: String) -> void:
	var m := of(zone)
	if m != null and m.get_script_method_list().any(func(f): return f["name"] == "light"):
		m.call("light", g, zone)

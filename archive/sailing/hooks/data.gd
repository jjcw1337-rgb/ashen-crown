## Not a script: what sailing had in scripts/data.gd, cut out whole when sailing was archived (2026-11-06), to paste back.
## REVIVE.md says where each piece was used.

# ACTS[0]: "coast": "The Mournwater Coast"
# VENDORS[0]: "shipwright": "Osric Saltmarrow"

# WAYPOINT_ACTIVITIES: the coast
	{"id": "coast", "group": "pve", "name": "The Mournwater Coast", "kind": "Exploration",
		"route": "zone", "run": 0, "zone": "coast", "spawn": "from_town",
		"description": "Explore the coast, visit the shipwright and sail to the islands."},


## Boats the shipwright on the Mournwater Coast sells (coast.gd, boat.gd, boat_ride.gd). One today; more
## boats, faster hulls or upgrades are new entries here. speed: cruising m/s (the island routes are
## planned for 8: Isles.ISLANDS "sail" / speed ~ the crossing's seconds), accel: m/s per second,
## turn: radians per second at speed, crew: how many it carries (co-op: each player sails their own).
const BOATS := {
	"gull": {"name": "The Gull", "price": 1000000, "speed": 8.0, "accel": 3.2, "turn": 0.95, "crew": 1,
		"paint": Color(0.16, 0.3, 0.42),
		"desc": "A single-masted cutter of tarred oak, seven paces long, built here on the strand. Quick on the wind, steady in a swell, and she'll put you ashore at any jetty on the Mournwater."},
	# Imported boats: "glb" is a model prepared by tools/blender/prep_boat.py (bow toward -z, waterline y = 0); its
	# printout gives length, beam, sheer and draft. "deck" is where the hero stands at the helm, "lamps" the lanterns'
	# lights. Swap the model by changing "glb" (and the sizes); without the file she's drawn as the Gull.
	"sloop": {"name": "The Ember Sloop", "price": 10000000, "speed": 45.0, "accel": 13.0, "turn": 0.8, "crew": 2,
		"glb": "res://assets/models/boats/sloop.glb", "length": 14.0, "beam": 4.6, "sheer": 1.74, "draft": 1.3,
		"deck": Vector3(0.6, 1.15, 2.6), "lamps": [[Vector3(1.21, 2.85, 6.73), 1.2], [Vector3(-1.21, 2.85, 6.73), 1.2]],
		"paint": Color(0.3, 0.06, 0.04),
		"desc": "A gaff-rigged sloop of black-tarred oak with patched rust-red canvas, fourteen paces stem to stern. Roomier and a knot faster than the Gull, with a cabin aft and lanterns at her stern."},
}

# zone_level(act, kind):
	if kind == "coast" or kind.begins_with("isle_"):
		return base + 3

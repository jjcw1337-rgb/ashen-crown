extends RefCounted
## Six rendered actors, two teams of Demon/Plague/Archer. Replays presentation events only;
## actual network damage, team and round correctness are tested separately by lobby_team_test.
var actors: Array = []
var bursts := 0
var events := 0
var next_burst := 0.0
var peak_nodes := 0
var node_samples: Array = []
var creation_us := {}
const ROSTERS := {
	"pvp3v3": ["demon", "plague", "archer", "demon", "plague", "archer"],
	"pvp_dragons": ["wyrm", "serpent", "wyvern", "wyrm", "serpent", "wyvern"],
	"pvp_forest": ["warlock", "wraith", "plague", "warlock", "wraith", "plague"],
}
var classes: Array = []
var positions: Array = []
var profile := "pvp3v3"

func setup(g, scenario := "pvp3v3") -> void:
	profile = scenario
	classes = ROSTERS[profile].duplicate()
	g.hero.visible = false
	for i in classes.size():
		var actor := Hero.new()
		actor.puppet = true
		actor.peer_id = 90 + i
		actor.name = "PvPStress_%d" % i
		g.add_child(actor)
		actor.setup(g)
		actor.set_class(classes[i])
		var at: Vector3 = g.hero.global_position + Vector3((i % 3 - 1) * 3.0, 0, -3 if i < 3 else 3)
		actor.global_position = at
		actor.net_pos = at
		actor.net_st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
		actor.net_has = true
		actors.append(actor)
		positions.append(at)

func step(g, elapsed: float) -> void:
	# Keep the original profile unchanged; extra profiles move targets through overlapping lingering effects.
	if profile != "pvp3v3":
		for i in actors.size():
			var at: Vector3 = positions[i] + Vector3(sin(elapsed + i) * 2.0, 0, cos(elapsed + i) * 2.0)
			actors[i].net_pos = g.world.free_spot_near(at, 0.7)
			actors[i].global_position = actors[i].net_pos
	peak_nodes = maxi(peak_nodes, g.world.fx_root.get_child_count())
	if elapsed < next_burst:
		return
	node_samples.append(g.world.fx_root.get_child_count())
	next_burst = elapsed + 6.0
	bursts += 1
	for actor in actors:
		for event in SkillWarmData.EVENTS.get(actor.cls, []):
			if event is Dictionary:
				var t := Time.get_ticks_usec()
				SkillFx.play(actor, SkillWarm._rebuild(event, actor.global_position))
				_record("%s/%s/%s" % [actor.cls, event.get("s", ""), event.get("e", "")], Time.get_ticks_usec() - t)
				events += 1
		if actor.cls == "plague" and actor.pd != null:
			for event in SkillWarmData.PLAGUE + SkillWarm.PLAGUE_TAIL:
				var t := Time.get_ticks_usec()
				actor.pd.remote(SkillWarm._pd_rebuild(str(event), actor.global_position))
				_record("plague/" + str(event).split("|")[0], Time.get_ticks_usec() - t)
				events += 1

func _record(key: String, us: int) -> void:
	var row: Dictionary = creation_us.get(key, {"count": 0, "total_us": 0, "max_us": 0})
	row.count += 1
	row.total_us += us
	row.max_us = maxi(row.max_us, us)
	creation_us[key] = row

func report() -> Dictionary:
	return {"actors": actors.size(), "teams": [3, 3], "classes": classes, "profile": profile, "bursts": bursts,
		"presentation_events": events, "peak_fx_root_children": peak_nodes,
		"pre_burst_fx_children": node_samples, "creation_us": creation_us, "kind": "presentation_replay_not_network_simulation"}

func cleanup() -> void:
	for actor in actors:
		if is_instance_valid(actor):
			SkillFx.clear(actor)
			actor.queue_free()
	actors.clear()

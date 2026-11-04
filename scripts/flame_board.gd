class_name FlameBoard
extends RefCounted
## The Last Flame's leaderboard (Blaine: "tracks your wave ranking with a leaderboard added to the main title
## page"). A vigil's score is the waves held before the flame went out (Vigil, "lost:<held>:<players>"). Each
## player's game keeps its own best (user://flame_best.json, the tools' test file when testing) and, in builds with
## the cloud (BuildEnv.cloud(): staging and production), sends it to Nakama (ashen.lua flame_submit: one record per
## account, the best kept, ties to the smaller party). The title's Hall of the Last Flame (UI) lists the top ten
## (flame_top). Offline, the local best still counts and the hall says it can't reach the server.
## (The score is the player's game's word, as everything in the story game is; good enough for the beta.)

const PATH := "user://flame_best.json"
const TEST_PATH := "user://flame_best_test.json"
const TOP := 10

static func _path(game) -> String:
	return TEST_PATH if game._testing() else PATH

## This game's best: {"waves", "party", "char", "cls", "when"} (empty: none yet).
static func best_record(game) -> Dictionary:
	var p := _path(game)
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}

static func best(game) -> int:
	return int(best_record(game).get("waves", 0))

## A vigil ended with `waves` held by a party of `party`: keeps it if it's this game's best and sends it to the
## leaderboard. True when it beat the old best.
static func record(game, waves: int, party: int) -> bool:
	var old := best_record(game)
	var better := waves > int(old.get("waves", 0)) or (waves == int(old.get("waves", 0)) and waves > 0 and party < int(old.get("party", 99)))
	var rec := {"waves": waves, "party": party, "char": str(game.char_name), "cls": str(game.hero.cls) if game.hero else "", "when": int(Time.get_unix_time_from_system())}
	if better:
		var f := FileAccess.open(_path(game), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(rec))
			f.close()
	if waves > 0:
		submit(game, rec)
	return better and waves > 0

## Sends a score to Nakama (the server keeps the account's best). Fire and forget.
static func submit(game, rec: Dictionary) -> void:
	if game.cloud == null or game._testing():
		return
	if not await game.cloud.ensure():
		return
	await game.cloud.nk.user_rpc("flame_submit", {"waves": int(rec["waves"]), "party": int(rec["party"]),
		"name": str(rec["char"]), "cls": str(rec["cls"])})

## The top ten: [{"rank", "name", "cls", "waves", "party", "mine"}], or null when the server can't be reached
## (no cloud in this build, offline).
static func top(game):
	if game.cloud == null:
		return null
	if not await game.cloud.ensure():
		return null
	var r: Dictionary = await game.cloud.nk.user_rpc("flame_top", {"limit": TOP})
	if not r.has("records"):
		return null
	var out := []
	for x in r["records"]:
		if x is Dictionary:
			out.append({"rank": int(x.get("rank", 0)), "name": str(x.get("name", "?")), "cls": str(x.get("cls", "")),
				"waves": int(x.get("waves", 0)), "party": int(x.get("party", 1)), "mine": str(x.get("owner", "")) == str(game.account_id)})
	return out

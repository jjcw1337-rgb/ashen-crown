class_name ServerUpdate
extends Node
## A dedicated server moving to a new deploy without kicking anyone (Blaine, 2026-11-02: "the battleground ended and
## my online co-op game kicked me back to the title"). deploy/staging/deploy.sh puts each deploy in its own release
## folder and points the `game` link at it (ASHEN_LIVE_DIR, the service's environment); a server keeps running the
## release it started from (res://, resolved when it started) and, every CHECK seconds, compares that release's
## DEPLOYED_REV with the live one. When they differ it tells the players once (Net.cl_bg_note: no new RPC, so old
## clients keep working) and quits as soon as `idle` says nobody would be hurt (a raid: no players, or between rounds;
## co-op: no players). systemd's Restart=always brings it back on the new release.
##   ServerUpdate.watch(game, "[BG]", func() -> bool: return ...)

const CHECK := 20.0

var game: Node
var tag := ""
var idle: Callable
var mine := ""
var _t := 0.0
var _told := false

static func watch(g: Node, log_tag: String, is_idle: Callable) -> ServerUpdate:
	var u := ServerUpdate.new()
	u.name = "ServerUpdate"
	u.game = g
	u.tag = log_tag
	u.idle = is_idle
	u.mine = _rev("res://DEPLOYED_REV")
	g.add_child(u)
	if u.mine != "":
		print("%s running release %s" % [log_tag, u.mine])
	return u

static func _rev(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""

## The release the `game` link points at now ("" when this isn't a deployed server).
func live() -> String:
	var dir := OS.get_environment("ASHEN_LIVE_DIR")
	return _rev(dir.path_join("DEPLOYED_REV")) if dir != "" else ""

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or mine == "":
		return
	_t = CHECK
	var now := live()
	if now == "" or now == mine:
		return
	if idle.call():
		print("%s release %s is live: restarting into it (nobody playing here)" % [tag, now])
		get_tree().quit(0)
		return
	if not _told:
		_told = true
		print("%s release %s is live: waiting for the players here to finish" % [tag, now])
		if not game.net.players.is_empty():
			game.net.rpc("cl_bg_note", "A server update is waiting: it applies when everyone here has left")

class_name Telemetry
extends Node
## Player telemetry and error reports (docs/nightly/TELEMETRY.md), into the staging backend's database through
## Nakama (the "telemetry" RPC, deploy/nakama/modules/ashen.lua), shown in Grafana and read by the nightly triage job.
## On in cloud builds that aren't production (staging), and in production only if the player turns it on
## (settings "telemetry"/"on"); never in tools, tests, screenshots or KPI runs. The dedicated servers send their errors
## too (with the runtime http_key, ASHEN_NAKAMA_HTTP_KEY).
##  - **Performance**: every `SAMPLE_SECS` of play a sample: fps, 1% low, p99 frame, hitches (frames of 100 ms+), where
##    (zone, run, position), what was going on (monsters near, a boss fight, Battlegrounds, co-op partners), the preset,
##    the PC.
##  - **Errors**: Godot writes every error to its log file (user://logs/godot.log); every `LOG_SECS` the new lines are
##    read, each [USER] ERROR / [USER] SCRIPT ERROR becomes an event with its "at:" location, fingerprinted (the message with numbers
##    taken out + the location) so one bug is one issue, counted per session.
##  - **Crashes**: a session that didn't end cleanly (user://telemetry_run.json still says running) is reported at the
##    next start as a crash, with the end of that session's log (Godot keeps it as the newest rotated godot*.log).
##  - **Breadcrumbs**: the last `CRUMBS` things the player did (`Telemetry.crumb`: zones, deaths, levels, bosses,
##    raids), sent with every error, so the triage job can see where they were and what led to it.
## Batches go up every `FLUSH_SECS` (at most MAX_BATCH of each kind); offline they wait (up to MAX_QUEUE).

const SAMPLE_SECS := 60.0
const LOG_SECS := 15.0
const FLUSH_SECS := 60.0
const CRUMBS := 30
const MAX_BATCH := 20
const MAX_QUEUE := 200
const HITCH_MS := 100.0
const RUN_FILE := "user://telemetry_run.json"
const LOG_FILE := "user://logs/godot.log"

static var me: Telemetry
var game: Node
var session := ""
var server := false
var http_key := ""
var crumbs: Array = []
var samples: Array = []
var errors: Array = []
var seen := {}            # fingerprint -> its error event still queued (counts add up), or true once sent
var frames: Array = []
var window_t := 0.0
var log_t := 0.0
var flush_t := 0.0
var log_pos := 0
var busy := false
var nk: NakamaClient

static func wanted() -> bool:
	var a := OS.get_cmdline_user_args()
	if a.has("--kpi") or a.has("--shot") or a.has("--no-telemetry") or OS.get_cmdline_args().has("-s"):
		return false
	if a.has("--server"):
		return OS.get_environment("ASHEN_NAKAMA_HTTP_KEY") != ""
	if not BuildEnv.cloud():
		return false
	var cf := ConfigFile.new()
	var opted := cf.load("user://settings.cfg") == OK and bool(cf.get_value("telemetry", "on", false))
	return BuildEnv.env() != "production" or opted

func _init(g: Node) -> void:
	game = g
	name = "Telemetry"
	me = self
	session = "%x%x" % [Time.get_unix_time_from_system() * 1000.0, randi()]
	server = OS.get_cmdline_user_args().has("--server")

func _ready() -> void:
	if server:
		http_key = OS.get_environment("ASHEN_NAKAMA_HTTP_KEY")
		nk = NakamaClient.new(OS.get_environment("ASHEN_NAKAMA_URL"), "")
		add_child(nk)
	_check_last_run()
	_write_run(true)
	if FileAccess.file_exists(LOG_FILE):
		var f := FileAccess.open(LOG_FILE, FileAccess.READ)
		log_pos = f.get_length() if f else 0
	crumb("start", {"build": BuildEnv.value("rev"), "env": BuildEnv.env()})

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_write_run(false)

## Something the player did, kept for the next error report (and the crash report).
static func crumb(kind: String, data := {}) -> void:
	if me == null:
		return
	var c := {"t": int(Time.get_unix_time_from_system()), "k": kind}
	c.merge(data)
	if me.game != null and me.game.world != null and me.game.hero != null:
		c["zone"] = me.game.cur_zone
		c["x"] = snappedf(me.game.hero.global_position.x, 0.1)
		c["z"] = snappedf(me.game.hero.global_position.z, 0.1)
	me.crumbs.append(c)
	if me.crumbs.size() > CRUMBS:
		me.crumbs.pop_front()

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	if not server and game.playing and not game.paused and game.world != null and not game._busy:
		frames.append(real * 1000.0)
		window_t += real
		if window_t >= SAMPLE_SECS:
			_sample()
	log_t += real
	if log_t >= LOG_SECS:
		log_t = 0.0
		_read_log()
	flush_t += real
	if flush_t >= FLUSH_SECS:
		flush_t = 0.0
		_flush()

# ---------------------------------------------------------------- what is sent

func _context() -> Dictionary:
	var c := {"build": BuildEnv.value("rev"), "env": BuildEnv.env(), "os": OS.get_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(), "server": server}
	if game.world != null:
		c["zone"] = game.cur_zone
		c["run"] = game.difficulty
	if not server and game.hero != null:
		c["class"] = game.hero.cls
		c["level"] = game.hero.level
		c["x"] = snappedf(game.hero.global_position.x, 0.1)
		c["z"] = snappedf(game.hero.global_position.z, 0.1)
		c["preset"] = game.quality
		c["bg"] = game.bg_mode
	return c

func _sample() -> void:
	var fr := frames.duplicate()
	var secs := window_t
	frames.clear()
	window_t = 0.0
	if fr.size() < 10:
		return
	fr.sort()
	var n := fr.size()
	var k := maxi(1, int(n * 0.01))
	var worst := 0.0
	var hitches := 0
	for i in k:
		worst += float(fr[n - 1 - i])
	worst /= k
	for f in fr:
		if float(f) >= HITCH_MS:
			hitches += 1
	var h = game.hero
	var near: Array = game.enemies_near(h.global_position, 25.0).filter(func(e): return not e.dead)
	var boss := false
	for e in near:
		if e.boss and e.aggro:
			boss = true
	var s := _context()
	s.merge({"secs": snappedf(secs, 0.1), "fps_avg": snappedf(n / secs, 0.1), "fps_low1": snappedf(1000.0 / worst, 0.1),
		"frame_p99": snappedf(float(fr[mini(n - 1, int(n * 0.99))]), 0.1), "hitches": hitches, "enemies": near.size(),
		"boss": boss, "partners": game.net.puppets().size() if game.net.active else 0, "dead": h.dead,
		"vram_mb": roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6),
		"res": _res()})
	_queue(samples, s)

## The window in real pixels, the screen's scale and the 3D view's (Game.apply_render_scale): "3232x1800@2.0 3d0.50".
## (Until 2026-11-02 it was the UI's size in points, which hid a Retina screen's four times the pixels.)
func _res() -> String:
	var w := get_window().size
	return "%dx%d@%.1f 3d%.2f" % [w.x, w.y, DisplayServer.screen_get_scale(), get_viewport().scaling_3d_scale]

## How many bytes of a log chunk can be read now: whole lines only (the engine may be halfway through writing the
## last one), and not an error whose "at:" line isn't written yet. Both wait for the next read. Reading them early
## split one engine error into two made-up issues on the servers (triage 2026-11-02: an "at:" cut in two, and an
## error with no "at:" that slipped past the headless renderer's filter).
static func whole_lines(buf: PackedByteArray) -> int:
	var end := buf.rfind(10) + 1
	if end <= 0:
		return 0
	var start := buf.rfind(10, end - 2) + 1 if end >= 2 else 0
	var last := buf.slice(start, end).get_string_from_utf8().strip_edges().trim_prefix("USER ")
	if last.begins_with("ERROR:") or last.begins_with("SCRIPT ERROR:"):
		return start
	return end

## New lines of Godot's own log: every error becomes an event (fingerprinted, counted).
func _read_log() -> void:
	var f := FileAccess.open(LOG_FILE, FileAccess.READ)
	if f == null:
		return
	var len := f.get_length()
	if len < log_pos:
		log_pos = 0       # (a new log)
	if len == log_pos:
		return
	f.seek(log_pos)
	var buf := f.get_buffer(mini(len - log_pos, 256 * 1024))
	var end := whole_lines(buf)
	if end <= 0:
		return
	log_pos += end
	var lines := buf.slice(0, end).get_string_from_utf8().split("\n")
	for i in lines.size():
		var l := lines[i].strip_edges().trim_prefix("USER ")     # ("USER ERROR:" / "USER SCRIPT ERROR:": from scripts)
		var kind := ""
		if l.begins_with("SCRIPT ERROR:"):
			kind = "script"
		elif l.begins_with("ERROR:"):
			kind = "error"
		if kind == "":
			continue
		var msg := l.substr(l.find(":") + 1).strip_edges()
		var at := ""
		if i + 1 < lines.size() and lines[i + 1].strip_edges().begins_with("at:"):
			at = lines[i + 1].strip_edges().substr(3).strip_edges()
		if at.contains("rendering/dummy/"):
			continue       # (a headless server has no renderer: meshes asked about there are noise, not bugs)
		error_event(kind, msg, at)

## Reports one error (the log reader calls it; game code may too for things worth knowing that aren't errors).
func error_event(kind: String, msg: String, at := "", tail := "") -> void:
	var fp := _fingerprint(kind, msg, at)
	var q = seen.get(fp, null)
	if q is Dictionary:
		q["count"] = int(q["count"]) + 1
		return
	if q != null:
		return       # (sent this session already: once per session is enough to count players and sessions)
	var e := {"kind": kind, "message": msg.left(500), "at": at.left(300), "fingerprint": fp, "count": 1,
		"context": _context(), "crumbs": crumbs.duplicate(), "tail": tail.right(6000)}
	seen[fp] = e
	_queue(errors, e)

static func _fingerprint(kind: String, msg: String, at: String) -> String:
	var re := RegEx.new()
	re.compile("[0-9]+|0x[0-9a-fA-F]+|'[^']*'|\"[^\"]*\"")
	return (kind + "|" + re.sub(msg, "#", true) + "|" + re.sub(at, "#", true)).md5_text().left(16)

func _queue(list: Array, item: Dictionary) -> void:
	list.append(item)
	while list.size() > MAX_QUEUE:
		list.pop_front()

func _flush() -> void:
	if busy or (samples.is_empty() and errors.is_empty()):
		return
	var s := samples.slice(0, MAX_BATCH)
	var e := errors.slice(0, MAX_BATCH)
	var payload := {"session": session, "samples": s, "errors": e}
	busy = true
	var r: Dictionary
	if server:
		r = await nk.server_rpc("telemetry_server", payload, http_key)
	else:
		if game.cloud == null or not await game.cloud.ensure():
			busy = false
			return
		r = await game.cloud.nk.user_rpc("telemetry", payload)
	busy = false
	if not r.has("ok"):
		return        # (kept for the next flush)
	samples = samples.slice(s.size())
	errors = errors.slice(e.size())
	for x in e:
		seen[x["fingerprint"]] = true

# ---------------------------------------------------------------- crashes

func _write_run(running: bool) -> void:
	var f := FileAccess.open(RUN_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"running": running, "session": session, "context": _context() if running else {},
			"crumbs": crumbs}))

## The last session never said it ended: it crashed (or was killed). Report it with the end of its log.
func _check_last_run() -> void:
	if not FileAccess.file_exists(RUN_FILE):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(RUN_FILE))
	if not (d is Dictionary) or not bool(d.get("running", false)):
		return
	var newest := ""
	var dir := DirAccess.open("user://logs")
	if dir:
		var names := Array(dir.get_files()).filter(func(n): return n.begins_with("godot") and n.ends_with(".log") and n != "godot.log")
		names.sort()
		if not names.is_empty():
			newest = "user://logs/" + str(names.back())
	var tail := ""
	var last := ""
	var crashed := false
	if newest != "":
		var lines := FileAccess.get_file_as_string(newest).split("\n")
		tail = "\n".join(lines.slice(maxi(0, lines.size() - 80)))
		for l in lines:
			if l.contains("crashed") or l.contains("handle_crash") or l.contains("Program crashed with signal"):
				crashed = true
			if l.contains("crashed") or l.trim_prefix("USER ").begins_with("SCRIPT ERROR") or l.trim_prefix("USER ").begins_with("ERROR"):
				last = l.strip_edges()
	if server and not crashed:
		return       # (a server stopped by systemd for a deploy never says goodbye either: only a real crash counts)
	crumbs = d.get("crumbs", [])
	error_event("crash", "the game closed without shutting down" + (": " + last if last != "" else ""), "", tail)
	var ev: Dictionary = errors.back()
	ev["context"] = d.get("context", ev["context"])
	ev["session"] = str(d.get("session", ""))
	crumbs = []

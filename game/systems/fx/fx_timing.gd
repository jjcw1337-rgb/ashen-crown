class_name FxTiming
extends RefCounted
## Where a frame's time goes in skills and their effects (Blaine, 2026-11-05: "lag ... when some abilities are
## firing ... audit it, measure what happens"). Off unless the game is started with `-- --fx-timing`: then every
## timed call slower than SLOW_MS prints "[fxt] <what> N ms" (SkillFx.play per event, each class's update,
## Hero.use_skill / _impact, the Plague Doctor's casts and update). Costs nothing when off.

const SLOW_MS := 6.0
static var on: bool = OS.get_cmdline_user_args().has("--fx-timing")
## every timed call of 2 ms or more since a tool last emptied it ([what, ms]), for per-frame breakdowns
static var calls: Array = []

static func t() -> int:
	return Time.get_ticks_usec() if on else 0

static func done(t0: int, what: String) -> void:
	if not on:
		return
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if ms >= 2.0:
		calls.append([what, ms])
	if ms >= SLOW_MS:
		print("[fxt] %s %.1f ms" % [what, ms])

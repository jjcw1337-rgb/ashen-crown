extends SceneTree
## The Battlegrounds' raids on the clock (Battlegrounds.phase / schedule / best_raid): three raids staggered a third
## of a period apart, so at any moment at least one takes joiners; the pick is the open one with the most time left,
## or (with fewer raids live) the next to open. Pure arithmetic, no server.
var fails := 0
func check(ok: bool, what: String) -> void:
	print("[R] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func _initialize() -> void:
	var BG = load("res://scripts/battlegrounds.gd")
	var P: float = BG.PERIOD
	check(is_equal_approx(BG.RAID_SECS, 1200.0), "a round is 20 minutes")
	var t0 := 1793600000.0
	check(absf(fposmod(BG.phase(1, t0) - BG.phase(0, t0), P) - (P - P / 3.0)) < 0.01, "raid II runs a third of a period behind raid I")
	var always := true
	var picks_best := true
	var worst_wait := 0.0
	for k in 2000:
		var now := t0 + k * 1.7
		var sch: Array = BG.schedule(now, 3)
		var open := sch.filter(func(r): return r["open"])
		if open.is_empty():
			always = false
		var b: Dictionary = BG.best_raid(now, 3)
		for r in open:
			if float(r["left"]) > float(b["left"]) + 0.001:
				picks_best = false
		var one: Dictionary = BG.best_raid(now, 1)
		if not one["open"]:
			worst_wait = maxf(worst_wait, float(one["opens_in"]))
	check(always, "with three raids one is always open")
	check(picks_best, "the pick is the open raid with the most time left")
	check(worst_wait <= BG.RAID_SECS - BG.JOIN_CLOSE + BG.RESET_SECS + 0.01, "with one raid the wait is at most its closed minutes and the reset (%d s)" % int(worst_wait))
	var b0: Dictionary = BG.best_raid(t0, 3)
	check(int(b0["port"]) in BG.RAID_PORTS, "the pick carries its server's port (%d)" % int(b0["port"]))
	print("[R] done, %d failed" % fails)
	quit()

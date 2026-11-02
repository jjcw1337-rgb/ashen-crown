extends SceneTree
## Co-op for the Plague Doctor: what one player throws, sets and raises, the other sees on their puppet of him
## (Net.hero_fx, Plague.remote), and the puppet's copy never deals damage. Both players are plague doctors here:
## the host casts first, then the partner (whose events go through the host).
## Run one copy with "-- host" and another with "-- join". Prints [PM] lines.
var g
var role := "host"
var fails := 0

func _initialize():
	role = "join" if OS.get_cmdline_user_args().has("join") else "host"
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[PM] %s %s %s" % [role, "ok  " if ok else "FAIL", what])

func wait(n: int) -> void:
	for i in n:
		await process_frame

func secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

func idle() -> void:
	while g._busy or g.net.loading:
		await wait(5)

func _run() -> void:
	Engine.max_fps = 60
	await wait(30)
	await idle()
	if role == "host":
		await g.start_host()
		await idle()
		g.hero.set_class("plague")
		g.ui.close_all()
		var t0 := Time.get_ticks_msec()
		while g.net.players.is_empty() and Time.get_ticks_msec() - t0 < 60000:
			await wait(10)
		check(g.net.players.size() == 1, "the partner joined")
	else:
		await secs(2.0)
		g.start_join("127.0.0.1")
		var t0 := Time.get_ticks_msec()
		while (g.net.players.is_empty() or g.net.loading or g._busy) and Time.get_ticks_msec() - t0 < 30000:
			await wait(5)
		g.ui.close_all()
		g.hero.set_class("plague")
	g.playing = false
	await secs(4.0)
	var me = g.hero
	me.level = 20          # (The Last Epidemic, his ultimate, opens at 20)
	me.recalc()
	var other = g.net.puppets()[0] if g.net.puppets().size() > 0 else null
	check(other != null and other.is_plague() and other.rig.has_meta("plague"), "the other player shows as a plague doctor on his own body")
	# both watch the whole time; the host casts first, the partner once the host is done
	_watch(other)
	if role == "host":
		await _cast_all(me)
	else:
		await secs(9.0)
		await _cast_all(me)
	while not watched:
		await wait(5)
	await secs(3.0)
	print("[PM] %s done, %d failed" % [role, fails])
	quit(1 if fails > 0 else 0)

## Casts Toxic Flask, Pestilent Trap and The Last Epidemic a few metres off, with waits between.
func _cast_all(h) -> void:
	var fwd: Vector3 = -h.rig.global_transform.basis.z
	var mine := {"toxic": false, "trap": false, "epidemic": false}
	for id in ["toxic", "trap", "epidemic"]:
		h.cds[id] = 0.0
		h.mana = h.max_mana
		var at: Vector3 = h.global_position + fwd * (6.0 if id == "toxic" else 3.0)
		h.use_skill(id, at)
		await secs(2.6)
		mine[id] = h.pd != null and not (h.pd.clouds if id == "toxic" else (h.pd.traps if id == "trap" else [h.pd.dome] if not h.pd.dome.is_empty() else [])).is_empty()
	check(mine.values().all(func(v) -> bool: return v), "my own cloud, trap and dome went up %s" % [mine])

## Watches the other player's puppet for the same: a cloud, a trap and the dome, shown only.
var watched := false
func _watch(other) -> void:
	var saw := {"cloud": false, "trap": false, "dome": false}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 24000 and not (saw["cloud"] and saw["trap"] and saw["dome"]):
		if other != null and other.pd != null:
			saw["cloud"] = saw["cloud"] or not other.pd.clouds.is_empty()
			saw["trap"] = saw["trap"] or not other.pd.traps.is_empty()
			saw["dome"] = saw["dome"] or not other.pd.dome.is_empty()
		await wait(5)
	check(saw["cloud"], "I see the other's Toxic Flask cloud")
	check(saw["trap"], "I see the other's Pestilent Trap")
	check(saw["dome"], "I see the other's Last Epidemic dome")
	var pd = other.pd if other != null else null
	check(pd != null and pd.ghost() and pd.poison.is_empty() and pd.infected.is_empty(), "the copy on my screen only shows: it poisons and infects nothing (pd %s, ghost %s, poisoned %d, infected %d)" % [pd != null, pd.ghost() if pd else false, pd.poison.size() if pd else -1, pd.infected.size() if pd else -1])
	watched = true

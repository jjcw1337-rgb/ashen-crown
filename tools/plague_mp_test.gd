extends SceneTree
## Co-op for the Plague Doctor: everything one player throws, releases, plants, drops, straps on and raises, the
## other sees on their puppet of him (Net.hero_fx, Plague.remote), and the puppet's copy never deals anything (no
## poison, no Blight). Both players are plague doctors here: the host casts his six skills first, then the partner
## (whose events go through the host).
## Run one copy with "-- host" and another with "-- join". Prints [PM] lines.
var g
var role := "host"
var fails := 0

## each skill, where it goes (metres ahead; transfusion is on himself) and how long to let it play out
const CASTS := [["toxic", 6.0, 1.8], ["swarm", 6.0, 1.6], ["bloom", 4.0, 1.6], ["fog", 3.0, 1.6],
	["transfusion", 0.0, 1.2], ["experiment", 4.0, 4.8]]

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
	me.level = 24          # (every skill open; The Last Experiment, his ultimate, at 20)
	me.recalc()
	var other = g.net.puppets()[0] if g.net.puppets().size() > 0 else null
	# the partner's class change follows his own zone load; give it time to arrive
	var tc := Time.get_ticks_msec()
	while other and not (other.is_plague() and other.rig.has_meta("plague")) and Time.get_ticks_msec() - tc < 10000:
		await wait(5)
	check(other != null and other.is_plague() and other.rig.has_meta("plague"), "the other player shows as a plague doctor on his own body")
	# both watch the whole time; the host casts first, the partner once the host is done
	_watch(other)
	if role == "host":
		await _cast_all(me)
	else:
		await secs(_cast_time() + 4.0)
		await _cast_all(me)
	while not watched:
		await wait(5)
	await secs(3.0)
	print("[PM] %s done, %d failed" % [role, fails])
	quit(1 if fails > 0 else 0)

func _cast_time() -> float:
	var t := 0.0
	for c in CASTS:
		t += float(c[2])
	return t

## Casts the six a few metres off, with waits between, and checks each went up on his own screen.
func _cast_all(h) -> void:
	var mine := {}
	for c in CASTS:
		var id: String = c[0]
		# the last move must be over (a cast mid-throw is refused); slow machines take longer than the plan
		var tw := Time.get_ticks_msec()
		while h.atk_t >= 0.0 and Time.get_ticks_msec() - tw < 4000:
			await wait(2)
		var fwd: Vector3 = -h.rig.global_transform.basis.z
		h.cds[id] = 0.0
		h.mana = h.max_mana
		var at: Vector3 = h.global_position + fwd * float(c[1])
		h.use_skill(id, h.skill_aim(id, at))
		var t0 := Time.get_ticks_msec()
		var up := false
		while Time.get_ticks_msec() - t0 < int(float(c[2]) * 1000.0):
			up = up or _has(h.pd, id)
			await wait(2)
		mine[id] = up
	check(mine.values().all(func(v) -> bool: return v), "my own six went up %s" % [mine])

## What one of his skills leaves in his `Plague` while it plays.
func _has(pd, id: String) -> bool:
	if pd == null:
		return false
	match id:
		"toxic":
			return not pd.vial_flights.is_empty() or not pd.clouds.is_empty()
		"swarm":
			return not pd.swarm.is_empty()
		"bloom":
			return not pd.blooms.is_empty()
		"fog":
			return not pd.fogs.is_empty()
		"transfusion":
			return not pd.trans.is_empty()
		"experiment":
			return not pd.lab.is_empty()
	return false

## Watches the other player's puppet for the same six, shown only.
var watched := false
func _watch(other) -> void:
	var saw := {}
	for c in CASTS:
		saw[c[0]] = false
	var burst := false
	var t0 := Time.get_ticks_msec()
	var limit := int((_cast_time() * 2.0 + 20.0) * 1000.0)
	while Time.get_ticks_msec() - t0 < limit and not (saw.values().all(func(v) -> bool: return v) and burst):
		if other != null and other.pd != null:
			for id in saw.keys():
				saw[id] = saw[id] or _has(other.pd, id)
			burst = burst or (not other.pd.lab.is_empty() and int(other.pd.lab.get("stage", 0)) == 2)
		await wait(3)
	check(saw["toxic"], "I see the other's Pestilence Vial")
	check(saw["swarm"], "I see the other's swarm")
	check(saw["bloom"], "I see the other's Corpse Bloom")
	check(saw["fog"], "I see the other's fog")
	check(saw["transfusion"], "I see the other's Transfusion apparatus")
	check(saw["experiment"] and burst, "I see the other's Last Experiment, vat and burst")
	var pd = other.pd if other != null else null
	check(pd != null and pd.ghost() and pd.poison.is_empty() and pd.blight.is_empty(), "the copy on my screen only shows: it poisons and blights nothing (pd %s, ghost %s, poisoned %d, blighted %d)" % [pd != null, pd.ghost() if pd else false, pd.poison.size() if pd else -1, pd.blight.size() if pd else -1])
	watched = true

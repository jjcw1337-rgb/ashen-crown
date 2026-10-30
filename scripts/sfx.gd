extends Node
## Sound effects and ambient music. Most effects are rendered offline (tools/audio/make_sfx.py) into
## assets/audio/sfx/<name>_<take>.wav, listed in sfx_bank.gd: each play picks one of a sound's takes
## (never the same twice in a row) and nudges its pitch. Anything not in the bank falls back to the
## old sounds synthesised here at start-up. play() is heard flat (the hero's own skills, UI);
## play_at() comes from a place in the world (hits, monsters), louder near the camera and panned.
## Buses: SFX, UI, Music, Ambience into Master, which has a limiter so big fights don't clip.

const RATE := 22050
const BANK := preload("res://scripts/sfx_bank.gd").BANK
const BANK_DIR := "res://assets/audio/sfx/"
## Rendered sounds that loop (a channel, the ambience beds)
const LOOPS := ["drain_loop", "wind", "forest", "drip", "music_town"]
var streams := {}
## name -> [streams] for the rendered sounds
var bank := {}
var _last_take := {}
## name -> [msec of the last play, plays in that burst]: a big pull can't stack 20 identical hits
var _recent := {}
## name -> times played (for tests: tools/sound_test.gd)
var counts := {}
## [seconds left, name, volume] for play_synced
var _pending: Array = []
var players: Array = []
var players3d: Array = []
var _next3 := 0
var music: AudioStreamPlayer
var ambience: AudioStreamPlayer
var _next := 0
var volume_db := 0.0
## Sound off: nothing new starts and the music/ambience loops stop. (Muting the audio bus
## instead crashes the browser build's audio code in Godot 4.3.)
var muted := false

func set_muted(m: bool) -> void:
	if m == muted:
		return
	muted = m
	for p in [music, ambience]:
		if p == null or p.stream == null:
			continue
		if m:
			p.stop()
		else:
			p.play()

func _ready() -> void:
	_buses()
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	for i in 28:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = 24.0          # the camera is ~24 m from the hero: full volume there
		p3.max_distance = 75.0
		p3.panning_strength = 0.7
		add_child(p3)
		players3d.append(p3)
	music = AudioStreamPlayer.new()
	music.volume_db = -14.0
	music.bus = "Music"
	add_child(music)
	ambience = AudioStreamPlayer.new()
	ambience.volume_db = -20.0
	ambience.bus = "Ambience"
	add_child(ambience)
	for nm in BANK.keys():
		var takes := []
		for k in int(BANK[nm][0]):
			var path := "%s%s_%d.wav" % [BANK_DIR, nm, k]
			if ResourceLoader.exists(path):
				takes.append(load(path))
		if not takes.is_empty():
			bank[nm] = takes
	_gen()
	for nm in LOOPS:
		for st in bank.get(nm, []):
			var w: AudioStreamWAV = st
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)

func _buses() -> void:
	# set_bus_count, never add_bus: in the browser build (Godot 4.5.1's web sample playback) add_bus
	# files the new bus in front of Master, which then sends into it instead of the speakers and the
	# whole game goes silent. set_bus_count appends them in order, each sending to Master.
	var missing: Array = ["SFX", "UI", "Music", "Ambience"].filter(func(nm: String) -> bool: return AudioServer.get_bus_index(nm) < 0)
	var first := AudioServer.bus_count
	AudioServer.set_bus_count(first + missing.size())
	for k in missing.size():
		AudioServer.set_bus_name(first + k, missing[k])
		AudioServer.set_bus_send(first + k, "Master")
	# a limiter on the master so a big pull of hits doesn't clip (where the platform has one)
	if ClassDB.class_exists("AudioEffectHardLimiter") and AudioServer.get_bus_effect_count(0) == 0:
		var lim: AudioEffect = ClassDB.instantiate("AudioEffectHardLimiter")
		lim.set("ceiling_db", -0.5)
		AudioServer.add_bus_effect(0, lim)

## One of the sound's takes (not the one played last), or the old synthesised stream.
func _pick(nm: String) -> AudioStream:
	if bank.has(nm):
		var takes: Array = bank[nm]
		var k := randi() % takes.size()
		if takes.size() > 1 and k == _last_take.get(nm, -1):
			k = (k + 1) % takes.size()
		_last_take[nm] = k
		return takes[k]
	return streams.get(nm)

## At most three of the same sound within 50 ms.
func _allow(nm: String) -> bool:
	var now := Time.get_ticks_msec()
	var r: Array = _recent.get(nm, [-1000, 0])
	if now - int(r[0]) < 50:
		if int(r[1]) >= 3:
			return false
		_recent[nm] = [r[0], int(r[1]) + 1]
	else:
		_recent[nm] = [now, 1]
	return true

func _bus(nm: String) -> String:
	return "UI" if BANK.has(nm) and BANK[nm][1] == "ui" else "SFX"

func play(nm: String, vol := 0.0, pitch := 1.0, from := 0.0) -> void:
	if muted or not _allow(nm):
		return
	var st := _pick(nm)
	if st == null:
		return
	counts[nm] = int(counts.get(nm, 0)) + 1
	var p: AudioStreamPlayer = players[_next]
	_next = (_next + 1) % players.size()
	p.stream = st
	p.bus = _bus(nm)
	p.volume_db = vol + volume_db
	p.pitch_scale = pitch * (randf_range(0.97, 1.03) if bank.has(nm) else 1.0)
	p.play(from)

## Seconds into a rendered sound where its payoff (its loudest moment) is; 0 for the rest.
func hit_of(nm: String) -> float:
	return float(BANK[nm][2]) if BANK.has(nm) and (BANK[nm] as Array).size() > 2 else 0.0

## Plays a sound so that its payoff lands `at` seconds from now (an attack's impact frame, whatever the
## attack speed): started later when there is time, or part-way in when the impact comes sooner.
## A pitch below 1 plays it slower, so its payoff comes later.
func play_synced(nm: String, at: float, vol := 0.0, pitch := 1.0) -> void:
	var lead := at - hit_of(nm) / pitch
	if lead <= 0.01:
		play(nm, vol, pitch, -minf(lead, 0.0) * pitch)
	else:
		# counted down in _process, on the same clock as the attack it belongs to
		_pending.append([lead, nm, vol, pitch])

func _process(delta: float) -> void:
	if _pending.is_empty():
		return
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i][0] -= delta
		if _pending[i][0] <= 0.0:
			var q: Array = _pending[i]
			_pending.remove_at(i)
			play(q[1], q[2], q[3])

## A sound from a place in the world: louder near the camera, panned left or right of it.
func play_at(nm: String, pos: Vector3, vol := 0.0, pitch := 1.0) -> void:
	if muted or not _allow(nm):
		return
	var st := _pick(nm)
	if st == null:
		return
	counts[nm] = int(counts.get(nm, 0)) + 1
	var p: AudioStreamPlayer3D = players3d[_next3]
	_next3 = (_next3 + 1) % players3d.size()
	p.stream = st
	p.global_position = pos
	p.volume_db = vol + volume_db
	p.pitch_scale = pitch * (randf_range(0.96, 1.04) if bank.has(nm) else 1.0)
	p.play()

## Pulls the music down for a moment under a big spell, then lets it back up.
func duck(db := -8.0, hold := 0.6) -> void:
	var i := AudioServer.get_bus_index("Music")
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, db)
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_method(func(v: float): AudioServer.set_bus_volume_db(i, v), db, 0.0, 1.2)

## A sound that keeps looping until the caller stops and frees the player (a channelled
## skill). Returns null while muted.
func start_loop(nm: String, vol := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var st := _pick(nm)
	if muted or st == null:
		return null
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = st
	p.volume_db = vol + volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	return p

## The zone's music and its ambience bed (wind outdoors, drips in the crypt; `amb` picks another, like
## Act I's forest rustle outside the camp).
func play_music(kind: String, amb_over := "") -> void:
	var key := "music_" + kind
	# a recorded song where there is one (the campsite's piano), else the old synthesized drone
	var song: AudioStream = bank[key][0] if bank.has(key) else null
	if song == null and not streams.has(key):
		streams[key] = _drone(kind)
	if song == null:
		song = streams[key]
	if music.stream != song:
		music.stream = song
		# the recorded songs are levelled already (build_sfx.py); the synthesized drones are louder
		music.volume_db = -6.0 if bank.has(key) else -14.0
		if not muted:
			music.play()
	var amb := amb_over if amb_over != "" and bank.has(amb_over) else ("wind" if kind != "lair" else "drip")
	var amb_st: AudioStream = bank[amb][0] if bank.has(amb) else streams.get(amb)
	if ambience.stream != amb_st:
		ambience.stream = amb_st
		# the recorded beds are levelled already; the old synthesized ones need pulling down
		ambience.volume_db = -4.0 if bank.has(amb) else -20.0
		if not muted:
			ambience.play()

func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w

func _buf(sec: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	return a

func _gen() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# swing: band-passed noise whoosh
	var s := _buf(0.28)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / s.size()
		var env := sin(t * PI) * sin(t * PI)
		var cut := 0.05 + 0.25 * sin(t * PI)
		lp += (rng.randf_range(-1, 1) - lp) * cut
		lp2 += (lp - lp2) * cut
		s[i] = (lp - lp2) * env * 2.2
	streams["swing"] = _wav(s)
	# hit: thump + crunch
	s = _buf(0.22)
	lp = 0.0
	for i in s.size():
		var t := float(i) / RATE
		var env := exp(-t * 22.0)
		lp += (rng.randf_range(-1, 1) - lp) * 0.3
		s[i] = (sin(TAU * (90.0 - t * 200.0) * t) * 0.9 + lp * 0.8) * env
	streams["hit"] = _wav(s)
	# block: metallic clang
	s = _buf(0.7)
	var freqs := [523.0, 1187.0, 1873.0, 2611.0, 3420.0]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			v += sin(TAU * freqs[k] * t) * exp(-t * (6.0 + k * 3.0)) / (k + 1.0)
		v += rng.randf_range(-1, 1) * exp(-t * 60.0) * 0.6
		s[i] = v * 0.7
	streams["block"] = _wav(s)
	# hurt: short low grunt
	s = _buf(0.25)
	for i in s.size():
		var t := float(i) / RATE
		var f := 140.0 - t * 160.0
		var saw := fmod(t * f, 1.0) * 2.0 - 1.0
		s[i] = saw * exp(-t * 10.0) * 0.4 * sin(t * PI / 0.25)
	streams["hurt"] = _wav(s)
	# die: descending groan
	s = _buf(0.6)
	lp = 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 180.0 - t * 200.0
		lp += ((fmod(t * f, 1.0) * 2.0 - 1.0) - lp) * 0.15
		s[i] = lp * exp(-t * 4.0) * 0.9
	streams["die"] = _wav(s)
	streams["death"] = streams["die"]
	# boss death: long roar
	s = _buf(1.8)
	lp = 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 90.0 - t * 30.0 + sin(t * 30.0) * 6.0
		lp += ((fmod(t * f, 1.0) * 2.0 - 1.0) + rng.randf_range(-0.5, 0.5) - lp) * 0.12
		s[i] = lp * sin(t * PI / 1.8) * 0.9
	streams["boss_die"] = _wav(s)
	streams["roar"] = streams["boss_die"]
	streams["growl"] = _wav(s.slice(0, int(RATE * 0.5)))
	# potion: bubbles
	s = _buf(0.45)
	for i in s.size():
		var t := float(i) / RATE
		var bub := sin(TAU * (300.0 + 400.0 * fmod(t * 9.0, 1.0)) * t)
		s[i] = bub * 0.35 * exp(-fmod(t * 9.0, 1.0) * 5.0) * (1.0 - t / 0.45)
	streams["potion"] = _wav(s)
	# gold: coin jingle
	s = _buf(0.35)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in 3:
			var tt := t - k * 0.05
			if tt > 0.0:
				v += sin(TAU * (2400.0 + k * 500.0) * tt) * exp(-tt * 25.0)
		s[i] = v * 0.3
	streams["gold"] = _wav(s)
	# drop / pickup / equip / ui
	s = _buf(0.12)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * 220.0 * t) * exp(-t * 40.0) * 0.6 + rng.randf_range(-1, 1) * exp(-t * 80.0) * 0.3
	streams["drop"] = _wav(s)
	s = _buf(0.15)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * (600.0 + t * 2000.0) * t) * exp(-t * 20.0) * 0.35
	streams["pickup"] = _wav(s)
	streams["click"] = _wav(s.slice(0, int(RATE * 0.05)))
	s = _buf(0.25)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (sin(TAU * 330.0 * t) + rng.randf_range(-0.3, 0.3)) * exp(-t * 18.0) * 0.4
	streams["equip"] = _wav(s)
	s = _buf(0.2)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (fmod(t * 110.0, 1.0) * 2.0 - 1.0) * 0.25 * (1.0 - t / 0.2)
	streams["deny"] = _wav(s)
	# level up: rising arpeggio
	s = _buf(1.2)
	var notes := [261.6, 329.6, 392.0, 523.3, 659.3]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var tt := t - k * 0.09
			if tt > 0.0:
				v += sin(TAU * notes[k] * tt) * exp(-tt * 2.5) * 0.25
		s[i] = v
	streams["levelup"] = _wav(s)
	# nova / cry / cast: whoosh sweep
	s = _buf(0.7)
	lp = 0.0
	for i in s.size():
		var t := float(i) / RATE
		var cut := 0.02 + t * 0.4
		lp += (rng.randf_range(-1, 1) - lp) * cut
		s[i] = (lp * 1.2 + sin(TAU * (200.0 + t * 600.0) * t) * 0.3) * exp(-t * 4.0)
	streams["nova"] = _wav(s)
	streams["summon"] = streams["nova"]
	streams["fireball"] = _wav(s.slice(0, int(RATE * 0.35)))
	s = _buf(0.8)
	for i in s.size():
		var t := float(i) / RATE
		var f := 160.0 + sin(t * 40.0) * 10.0
		s[i] = ((fmod(t * f, 1.0) * 2.0 - 1.0) * 0.4 + sin(TAU * f * 1.5 * t) * 0.3) * sin(t * PI / 0.8)
	streams["cry"] = _wav(s)
	streams["charge"] = streams["swing"]
	# slam: deep boom
	s = _buf(0.9)
	lp = 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.05
		s[i] = (sin(TAU * (55.0 - t * 20.0) * t) + lp * 2.0) * exp(-t * 5.0) * 0.8
	streams["slam"] = _wav(s)
	# bow twang
	s = _buf(0.2)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * (180.0 + 60.0 * exp(-t * 30.0)) * t) * exp(-t * 18.0) * 0.4
	streams["bow"] = _wav(s)
	# portal / waypoint shimmer
	s = _buf(1.0)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (sin(TAU * 880.0 * t + sin(TAU * 6.0 * t) * 3.0) * 0.2 + sin(TAU * 1320.0 * t) * 0.1) * sin(t * PI)
	streams["portal"] = _wav(s)
	# ambient wind (looping)
	s = _buf(6.0)
	lp = 0.0
	lp2 = 0.0
	for i in s.size():
		var t := float(i) / s.size()
		lp += (rng.randf_range(-1, 1) - lp) * 0.02
		lp2 += (lp - lp2) * 0.02
		s[i] = lp * (0.6 + 0.4 * sin(t * TAU * 2.0)) * 3.0
	streams["wind"] = _wav(s, true)
	s = _buf(5.0)
	for i in s.size():
		s[i] = rng.randf_range(-1, 1) * 0.01
	for k in 6:
		var at := rng.randi_range(0, s.size() - 3000)
		for j in 2500:
			var t := float(j) / RATE
			s[at + j] += sin(TAU * (1200.0 - t * 3000.0) * t) * exp(-t * 40.0) * 0.4
	streams["drip"] = _wav(s, true)
	# drain: a hollow, rising siphon (Drain Life)
	s = _buf(0.4)
	lp = 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 110.0 + t * 260.0
		lp += (rng.randf_range(-1, 1) - lp) * 0.08
		s[i] = (sin(TAU * f * t + sin(TAU * 7.0 * t) * 2.0) * 0.35 + lp * 0.5) * sin(t * PI / 0.4)
	streams["drain"] = _wav(s)
	# drain loop: a breathing, hollow hum under the beam (loops seamlessly every 2 s)
	s = _buf(2.0)
	lp = 0.0
	lp2 = 0.0
	for i in s.size():
		var t := float(i) / RATE
		var u := float(i) / s.size()
		lp += (rng.randf_range(-1, 1) - lp) * 0.06
		lp2 += (lp - lp2) * 0.06
		var swell := 0.6 + 0.4 * sin(u * TAU * 2.0)
		var hum := sin(TAU * 82.0 * t + sin(TAU * 3.0 * t) * 1.5) * 0.3 + sin(TAU * 123.0 * t) * 0.12 + sin(TAU * 246.0 * t + sin(TAU * 5.0 * t)) * 0.06
		s[i] = (hum + (lp - lp2) * 1.6) * swell
	streams["drain_loop"] = _wav(s, true)
	# coins: a sack of gold pouring out (King Grubb's burst sacks)
	s = _buf(1.6)
	for k in 70:
		var t0 := pow(rng.randf(), 1.6) * 1.3
		var f := rng.randf_range(2200.0, 5200.0)
		var amp := rng.randf_range(0.15, 0.4) * (1.0 - t0 / 1.6)
		var start := int(t0 * RATE)
		for i in range(start, mini(start + int(0.12 * RATE), s.size())):
			var u := float(i - start) / RATE
			s[i] += (sin(TAU * f * u) + sin(TAU * f * 1.53 * u) * 0.5) * exp(-u * 40.0) * amp
	for i in s.size():
		s[i] = clampf(s[i], -1.0, 1.0) * 0.6
	streams["coins"] = _wav(s)
	# cackle: a nasal goblin laugh, "heh-heh-heh-heh"
	s = _buf(0.9)
	lp = 0.0
	for i in s.size():
		var t := float(i) / RATE
		var syl := fmod(t, 0.13) / 0.13
		var k := floorf(t / 0.13)
		var env := sin(minf(syl / 0.7, 1.0) * PI) * (1.0 - t / 0.95)
		var f := 330.0 + k * 12.0 - syl * 70.0 + sin(t * 40.0) * 8.0
		var saw := fmod(t * f, 1.0) * 2.0 - 1.0
		lp += (saw + rng.randf_range(-0.35, 0.35) - lp) * 0.35
		s[i] = (lp * 0.8 + sin(TAU * f * 3.0 * t) * 0.15) * env * 0.7
	streams["cackle"] = _wav(s)
	# fuse: a hissing, crackling fuse
	s = _buf(1.2)
	lp = 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.6
		var crack := rng.randf_range(-1, 1) * (1.0 if rng.randf() < 0.004 else 0.0)
		s[i] = (lp * 0.25 + crack * 0.8) * minf(1.0, t * 10.0) * minf(1.0, (1.2 - t) * 6.0)
	streams["fuse"] = _wav(s)
	# boom: a deep blast with a rattle of falling coins
	s = _buf(1.4)
	lp = 0.0
	lp2 = 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * (0.25 * exp(-t * 3.0) + 0.02)
		lp2 += (lp - lp2) * 0.2
		var thump := sin(TAU * (70.0 - t * 40.0) * t) * exp(-t * 5.0)
		s[i] = clampf((lp2 * 2.2 + thump * 0.9) * exp(-t * 2.2), -1.0, 1.0) * 0.95
	streams["boom"] = _wav(s)

func _drone(kind: String) -> AudioStreamWAV:
	var sec := 16.0
	var s := _buf(sec)
	var root := 55.0 if kind != "lair" else 46.25
	var chord := [1.0, 1.5, 2.0, 2.4, 3.0] if kind == "town" else [1.0, 1.498, 2.0, 2.378, 2.997]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in chord.size():
			var f: float = root * chord[k]
			var lfo := 0.6 + 0.4 * sin(TAU * t / sec * (k + 1) + k)
			v += sin(TAU * f * t + sin(TAU * 0.13 * t + k) * 0.8) * lfo / (k + 1.5)
		lp += (rng.randf_range(-1, 1) - lp) * 0.01
		v += lp * 0.6
		s[i] = v * 0.32
	return _wav(s, true)

extends Node
## Procedurally synthesised sound effects and ambient music.

const RATE := 22050
var streams := {}
var players: Array = []
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
	for i in 20:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	music = AudioStreamPlayer.new()
	music.volume_db = -14.0
	add_child(music)
	ambience = AudioStreamPlayer.new()
	ambience.volume_db = -20.0
	add_child(ambience)
	_gen()

func play(nm: String, vol := 0.0, pitch := 1.0) -> void:
	if muted or not streams.has(nm):
		return
	var p: AudioStreamPlayer = players[_next]
	_next = (_next + 1) % players.size()
	p.stream = streams[nm]
	p.volume_db = vol + volume_db
	p.pitch_scale = pitch
	p.play()

## A sound that keeps looping until the caller stops and frees the player (a channelled
## skill). Returns null while muted.
func start_loop(nm: String, vol := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	if muted or not streams.has(nm):
		return null
	var p := AudioStreamPlayer.new()
	p.stream = streams[nm]
	p.volume_db = vol + volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	return p

func play_music(kind: String) -> void:
	var key := "music_" + kind
	if not streams.has(key):
		streams[key] = _drone(kind)
	if music.stream != streams[key]:
		music.stream = streams[key]
		if not muted:
			music.play()
	var amb := "wind" if kind != "lair" else "drip"
	if ambience.stream != streams.get(amb):
		ambience.stream = streams.get(amb)
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

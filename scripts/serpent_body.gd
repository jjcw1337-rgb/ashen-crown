class_name SerpentBody
extends RefCounted
## The Frost Serpent's body, alive (jj, 2026-11-04: "fix his movement so it matches actually moving with step and
## lifelike movement, add movement everywhere like the tail"). Dragon.pose hands the serpent here. It runs on the
## re-rigged skeleton (tools/blender/dragons/rechain_serpent.py: tail_0..11 from the hips back, spine_0..5 hips to
## shoulders, neck_0..6 up the S of the neck), every bone turned from its rest each frame from the hero's animation
## state, on the local hero and on a co-op puppet alike:
##  - the walk is a lizard's: the legs in diagonal pairs (front left with hind right), each foot planted and swept
##    back in a straight line for STANCE of the cycle (so it keeps to the ground: the hero's phase runs at the gait's
##    own stride, Dragon.KINDS "stride"), then lifted and swung forward; the step's reach grows with speed;
##  - the body swims: a wave runs from the shoulders down to the tail tip with the gait (the spine bending toward each
##    stance pair), the head held steady on its course by the neck undoing what the spine does;
##  - turns: the body curves into them, the head leading and the tail swinging wide and catching up behind;
##  - the tail is a chain of springs (TAIL_K): it lags the body, overshoots, drags in turns, never still: a slow S at
##    rest, the tip curling and flicking now and then, a lash when hit;
##  - at rest it breathes (the chest lifting, the jaw parting), looks about, shifts its weight from foot to foot, and
##    now and then breathes out a cold mist from its nostrils;
##  - attacks: a raking foreclaw, a lunging bite, a tail spin; "breath" (Frost Breath) lowers the neck and thrusts the
##    head out with the jaws wide, sweeping slowly; block coils the body round itself, the tail wrapped round and the
##    head tucked low (SerpentFx grows the ice shell round it); hit jerks the head back; death rolls it onto its side.

const STANCE := 0.62          # of the gait cycle a foot is on the ground
const REACH := 0.42           # rad either side of the leg's rest a foot sweeps at a walk
const SWIM := 0.11            # rad of the body wave per bone at a walk
const TURN_BEND := 0.05       # rad per bone per rad/s of turning
const TAIL_K := [60.0, 9.0]   # the tail springs' stiffness at the root and the tip (damping is critical-ish)
const PUFF_EVERY := Vector2(5.0, 10.0)

static func pose(rig: Node3D, st: Dictionary) -> void:
	var sk: Skeleton3D = rig.get_meta("drg_sk")
	var info: Dictionary = rig.get_meta("drg_info")
	var hold: Node3D = rig.get_meta("drg_hold")
	var mem: Dictionary = rig.get_meta("drg_mem")
	var t: float = float(st.get("time", 0.0))
	var dt := clampf(t - float(mem.get("t", t)), 0.0, 0.05)
	mem["t"] = t
	var sd: float = float(mem.get("seed", 0.0))
	var ph: float = float(st.get("phase", 0.0))
	var m := clampf(float(st.get("move", 0.0)), 0.0, 1.4)
	var a: float = float(st.get("atk", -1.0))
	var style: String = str(st.get("style", ""))
	var blk := clampf(float(st.get("block", 0.0)), 0.0, 1.0)
	var hit := clampf(float(st.get("hit", 0.0)), 0.0, 1.0)
	var look := clampf(float(st.get("look", 0.0)), -0.8, 0.8)
	var dead := clampf(float(st.get("dead", 0.0)), 0.0, 1.0) if st.has("dead") else 0.0
	if dead > 0.0:
		m = 0.0
		a = -1.0
		blk = 0.0
	var mw := minf(m, 1.0)
	var run := clampf((m - 1.0) / 0.3, 0.0, 1.0)
	var calm := 1.0 - mw
	var P := {}
	var spine := Dragon._chain(info, "spine_")
	var neck := Dragon._chain(info, "neck_")
	var tail := Dragon._chain(info, "tail_")
	var ns := maxf(1.0, spine.size())
	var nn := maxf(1.0, neck.size())
	var nt := maxf(1.0, tail.size())
	var cyc := ph / TAU                   # gait cycles covered
	var breath := sin(t * 1.25 + sd) * 0.5 + 0.5

	# --- turning: how fast the body's heading changes (rad/s, + = left), smoothed
	var yaw_now := rig.global_rotation.y if rig.is_inside_tree() else 0.0
	var yr := 0.0
	if mem.has("yaw") and dt > 0.0:
		yr = wrapf(yaw_now - float(mem["yaw"]), -PI, PI) / dt
	mem["yaw"] = yaw_now
	var turn: float = lerpf(float(mem.get("turn", 0.0)), clampf(yr, -6.0, 6.0), 1.0 - exp(-dt * 6.0))
	mem["turn"] = turn

	# --- the legs: diagonal pairs, each foot planted and swept back, then lifted and swung forward
	var reach := REACH * (0.35 + 0.65 * mw + 0.3 * run)
	var legs := {"leg_FL": 0.0, "leg_HR": 0.0, "leg_FR": 0.5, "leg_HL": 0.5}
	var stance_side := 0.0          # which pair is planted: + the FL/HR pair, - the other
	for lg in legs:
		var phi := fposmod(cyc + float(legs[lg]), 1.0)
		var swing := 0.0            # +1 reaching forward .. -1 swept back
		var lift := 0.0
		if phi < STANCE:
			swing = lerpf(1.0, -1.0, phi / STANCE)
			if lg == "leg_FL":
				stance_side = 1.0 - 2.0 * (phi / STANCE)
		else:
			var u := (phi - STANCE) / (1.0 - STANCE)
			swing = lerpf(-1.0, 1.0, smoothstep(0.0, 1.0, u))
			lift = sin(PI * u)
		var front: bool = str(lg).contains("F")
		var amt := mw + run * 0.3
		# the weight shifting at rest: now and then one foot lifts and settles again
		if calm > 0.5:
			var shift := sin(t * 0.7 + float(legs[lg]) * 9.0 + sd)
			lift = maxf(lift, smoothstep(0.85, 1.0, shift) * 0.35 * calm)
		Dragon._add(P, lg + "_0", -swing * reach * amt, 0.0, (0.06 if front else 0.04) * lift)
		Dragon._add(P, lg + "_1", lift * (0.85 if front else 0.75) - 0.08 * mw)
		Dragon._add(P, lg + "_2", -lift * (0.55 if front else 0.45) + swing * 0.12 * amt)

	# --- the body: a wave down it with the gait, curving into turns; breathing
	var body: Array = []
	for s in spine:
		body.append(s)
	var swim := SWIM * (mw + run * 0.4) * (6.0 / ns)
	var spine_yaw := 0.0
	for i in spine.size():
		var k := float(i) / ns
		var w := swim * sin(TAU * cyc - k * 2.2) + 0.035 * calm * sin(t * 0.55 - k * 1.5 + sd)
		w += turn * TURN_BEND * (1.0 - k * 0.4)
		spine_yaw += w
		Dragon._add(P, spine[i], -breath * 0.012 + sin(2.0 * TAU * cyc) * 0.01 * m, w)
	# the neck: the S kept, the head held on its course (it undoes the spine's swing), leading into turns, looking
	# about at rest, stretched out and lowered at a run
	var wander := (sin(t * 0.33 + sd) * 0.3 + sin(t * 0.87 + sd * 2.0) * 0.12) * calm
	for i in neck.size():
		var k := float(i + 1) / nn
		var yaw := (-spine_yaw * 0.9 + look * 0.8 + wander + turn * 0.08) / nn
		yaw += 0.03 * calm * sin(t * 0.9 - k * 2.0 + sd)
		var pit := breath * 0.012 - 0.06 * run * (1.0 - k) + 0.04 * run * k
		Dragon._add(P, neck[i], pit, yaw)
	Dragon._add(P, "head_0", sin(t * 1.05 + sd) * 0.03 * calm - 0.08 * run, look * 0.25 + wander * 0.3)
	var jaw := breath * 0.06 * calm + 0.08 * run

	# --- the tail: springs chasing the wave, the turn's drag and an S at rest; flicks, a lash when hit
	# (Arrays, not packed ones: these are kept in mem and changed in place)
	if not mem.has("tail_y") or (mem["tail_y"] as Array).size() != tail.size():
		var z: Array = []
		z.resize(tail.size())
		z.fill(0.0)
		mem["tail_y"] = z.duplicate()
		mem["tail_v"] = z.duplicate()
		mem["tail_p"] = z.duplicate()
		mem["tail_pv"] = z.duplicate()
	var ty: Array = mem["tail_y"]
	var tv: Array = mem["tail_v"]
	var tp: Array = mem["tail_p"]
	var tpv: Array = mem["tail_pv"]
	var fa: float = float(mem.get("flick_at", 4.0))
	if t > fa:
		mem["flick_t0"] = t
		mem["flick_at"] = t + randf_range(Dragon.FLICK_EVERY.x, Dragon.FLICK_EVERY.y)
	var f0: float = float(mem.get("flick_t0", -10.0))
	var flick := sin(clampf((t - f0) / 1.1, 0.0, 1.0) * PI) if t - f0 < 1.1 else 0.0
	var fsign := 1.0 if fmod(f0, 2.0) < 1.0 else -1.0
	var wag_amp := 0.3 * calm + 0.08
	for i in tail.size():
		var k := float(i + 1) / nt
		var want := swim * 1.15 * (0.6 + k) * sin(TAU * cyc - 2.2 - k * 3.2)          # the wave carried on down it
		want += wag_amp * (0.3 + k) * sin(t * (1.1 + 0.25 * sin(t * 0.21 + sd)) - k * 2.6 + sd)
		want += -turn * TURN_BEND * 1.6 * (0.4 + k)                                      # swung wide in a turn
		want += flick * 0.5 * k * k * fsign
		want += hit * 0.4 * sin(t * 20.0 - i) * k
		var wp := 0.02 * calm * sin(t * 0.8 - k * 2.0 + sd) + 0.05 * run * (1.0 - k) + flick * 0.22 * k * k
		var kk: float = lerpf(TAIL_K[0], TAIL_K[1], k)
		var dmp := 2.0 * sqrt(kk) * 0.55
		tv[i] = float(tv[i]) + (kk * (want - float(ty[i])) - dmp * float(tv[i])) * dt
		ty[i] = float(ty[i]) + float(tv[i]) * dt
		tpv[i] = float(tpv[i]) + (kk * (wp - float(tp[i])) - dmp * float(tpv[i])) * dt
		tp[i] = float(tp[i]) + float(tpv[i]) * dt
	# (each bone turns by its own share: a bone's spring holds the curve up to it, so hand on the difference)
	var prev_y := 0.0
	var prev_p := 0.0
	for i in tail.size():
		Dragon._add(P, tail[i], float(tp[i]) - prev_p * 0.5, float(ty[i]) - prev_y * 0.5)
		prev_y = float(ty[i])
		prev_p = float(tp[i])

	# --- attacks
	var spin := 0.0
	var lift_y := 0.0
	if a >= 0.0:
		var env := Dragon._sm(0.0, 0.18, a) * (1.0 - Dragon._sm(0.78, 1.0, a))
		match style:
			"swipe1":
				# the front of the body rears, the right foreclaw raised and raked down on the impact (0.4)
				var raise := Dragon._sm(0.0, 0.3, a) * (1.0 - Dragon._sm(0.42, 0.75, a))
				var rake := Dragon._sm(0.3, 0.42, a)
				lift_y = 0.1 * raise
				for i in spine.size():
					Dragon._add(P, spine[i], -0.12 * raise * float(i + 1) / ns / ns * 2.0)
				Dragon._add(P, "leg_FR_0", lerpf(-1.3 * raise, 0.35, rake) * env, -0.25 * raise)
				Dragon._add(P, "leg_FR_1", 0.9 * raise * (1.0 - rake))
				for i in neck.size():
					Dragon._add(P, neck[i], 0.12 * rake * env / nn, -0.2 * env / nn)
				jaw += 0.25 * raise
			"swipe2":
				# the bite: the neck coils back, then strikes like a snake's, snapping shut on the impact (0.42)
				var draw := Dragon._sm(0.0, 0.28, a) * (1.0 - Dragon._sm(0.3, 0.42, a))
				var strike := Dragon._sm(0.3, 0.42, a) * (1.0 - Dragon._sm(0.62, 0.95, a))
				for i in neck.size():
					var k := float(i + 1) / nn
					Dragon._add(P, neck[i], (-0.5 * draw * (1.2 - k) + 0.6 * strike) / nn)
				Dragon._add(P, "head_0", -0.25 * draw + 0.3 * strike)
				jaw += 0.75 * Dragon._sm(0.1, 0.36, a) * (1.0 - Dragon._sm(0.4, 0.45, a))
				lift_y = -0.05 * strike
			"swipe3":
				# a full spin sweeping the tail round in front, flung out wide
				spin = TAU * Dragon._sm(0.12, 0.82, a)
				for i in tail.size():
					var k := float(i + 1) / nt
					Dragon._add(P, tail[i], 0.04 * env, -0.22 * env * (0.4 + k) / nt * 6.0)
				for s in spine:
					Dragon._add(P, s, 0.0, -0.1 * env / ns * 2.0)
				jaw += 0.3 * env
			"breath":
				# Frost Breath: the neck lowered and stretched out, the head thrust forward with the jaws wide, sweeping
				# slowly across the cone; the body braced
				var on := Dragon._sm(0.0, 0.15, a) * (1.0 - Dragon._sm(0.85, 1.0, a))
				var sweep := sin(a * PI * 2.0) * 0.18 * on
				for i in neck.size():
					var k := float(i + 1) / nn
					Dragon._add(P, neck[i], (0.32 * (1.0 - k) - 0.18 * k) * on / nn * 3.0, sweep / nn)
				Dragon._add(P, "head_0", -0.22 * on, sweep * 0.4)
				jaw += 0.85 * on + 0.06 * sin(t * 31.0) * on
				lift_y -= 0.05 * on
				for lg in ["leg_FL", "leg_FR"]:
					Dragon._add(P, lg + "_0", 0.12 * on)
			_:
				# anything else: a roar, head up, jaws wide
				for i in neck.size():
					Dragon._add(P, neck[i], -0.25 * env / nn)
				Dragon._add(P, "head_0", -0.3 * env)
				jaw += 0.75 * env

	# --- block: it coils round itself, the tail wrapped round, the head tucked low (the ice shell is SerpentFx's)
	if blk > 0.0:
		var c := Dragon._sm(0.0, 1.0, blk)
		lift_y -= 0.14 * c
		for i in spine.size():
			Dragon._add(P, spine[i], 0.02 * c, 0.42 * c / ns * 3.0)
		for i in tail.size():
			var k := float(i + 1) / nt
			Dragon._add(P, tail[i], -0.02 * c, 0.45 * c * (0.5 + k) / nt * 6.0)
		for i in neck.size():
			var k := float(i + 1) / nn
			Dragon._add(P, neck[i], 0.38 * c * (1.0 - k) / nn * 3.0, 0.3 * c / nn)
		Dragon._add(P, "head_0", 0.25 * c, 0.2 * c)
		for lg in ["leg_FL", "leg_FR", "leg_HL", "leg_HR"]:
			Dragon._add(P, lg + "_1", 0.35 * c)
	if hit > 0.0:
		for i in neck.size():
			Dragon._add(P, neck[i], -0.3 * hit / nn)
		Dragon._add(P, "head_0", -0.15 * hit)

	# --- death: it slumps onto its side, neck and tail limp
	if dead > 0.0:
		var d := Dragon._sm(0.0, 1.0, dead)
		for i in neck.size():
			Dragon._add(P, neck[i], 0.7 * d / nn)
		Dragon._add(P, "head_0", 0.3 * d)
		jaw = lerpf(jaw, 0.35, d)
		for lg in legs:
			Dragon._add(P, lg + "_0", 0.25 * d)
			Dragon._add(P, lg + "_1", 0.6 * d)
	Dragon._add(P, "jaw_0", jaw)

	# --- apply
	for bone in info:
		var b: Array = info[bone]
		var q: Quaternion = b[1]
		var v: Vector3 = P.get(bone, Vector3.ZERO)
		if v.x != 0.0:
			q = q * Quaternion(b[2] as Vector3, v.x)
		if v.y != 0.0:
			q = q * Quaternion(b[3] as Vector3, v.y)
		if v.z != 0.0:
			q = q * Quaternion(b[4] as Vector3, v.z)
		sk.set_bone_pose_rotation(int(b[0]), q)
	var dd := Dragon._sm(0.0, 1.0, dead)
	# the body rides a little higher on each stance and rolls with the wave
	var bob := (0.5 - 0.5 * cos(2.0 * TAU * cyc)) * 0.035 * m
	hold.position = Vector3(0.0, bob + lift_y + breath * 0.008 - dd * 2.75 * 0.12, 0.0)
	hold.rotation = Vector3(0.0, spin, dd * 1.25 + stance_side * 0.025 * mw)

	# --- sounds and breath: a footfall as each pair plants; a cold breath from its nostrils now and then at rest
	var step := int(floor(cyc * 2.0))
	if m > 0.25 and step != int(mem.get("step", step)) and rig.is_inside_tree():
		var sfx: Node = rig.get_tree().root.get_node_or_null("Sfx")
		if sfx != null:
			sfx.call("play_at", "serpent_step", rig.global_position, -6.0 + 4.0 * run, randf_range(0.95, 1.1))
	mem["step"] = step
	if dead <= 0.0 and rig.is_inside_tree():
		var pa: float = float(mem.get("puff_at", t + 3.0))
		if t > pa:
			mem["puff_at"] = t + randf_range(PUFF_EVERY.x, PUFF_EVERY.y)
			SerpentFx.nostril_puff(rig)
		elif not mem.has("puff_at"):
			mem["puff_at"] = pa
	SerpentFx.shell_pose(rig, blk)

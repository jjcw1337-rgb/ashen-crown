class_name Anim
extends RefCounted
## Procedural animation for humanoid and crawler rigs.

## Smooth keyframe interpolation. keys: [[t, value], ...] sorted by t.
static func kf(t: float, keys: Array) -> float:
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var u: float = (t - a[0]) / max(b[0] - a[0], 0.0001)
			u = u * u * (3.0 - 2.0 * u)
			return lerpf(a[1], b[1], u)
	return keys[keys.size() - 1][1]

## Fraction of an attack animation at which the blow lands.
static func impact_at(style: String) -> float:
	match style:
		"over": return 0.5
		"back": return 0.48
		"side": return 0.48
		"thrust": return 0.52
		"swipe1": return 0.4
		"swipe2": return 0.42
		"swipe3": return 0.47
		"cleave": return 0.5
		"bow": return 0.72
		"cast": return 0.55
		"claw": return 0.45
		"slam": return 0.58
		"bite": return 0.5
		"lob": return 0.55
		"smash": return 0.58
		"scoop": return 0.55
		"burst": return 0.3
		"cackle": return 0.5
		"feral_lunge": return 0.64      # his hands land (feral.gd's baked lunge)
		"feral_swipe": return 0.32      # the right claw rakes across
	return 0.5

## 0 at walking stride, 1 at full sprint stride (move > 1 means sprinting).
static func run_factor(m: float) -> float:
	return smoothstep(1.02, 1.25, m)

## Cheap smooth pseudo-noise in roughly [-1, 1].
static func n1(x: float) -> float:
	return sin(x) * 0.55 + sin(x * 2.31 + 1.7) * 0.3 + sin(x * 4.13 + 0.3) * 0.15

## Per-rig animation memory: springs, previous facing, personality seed.
static func _mem(rig: Node3D) -> Dictionary:
	if not rig.has_meta("an"):
		var sd := float(rig.get_instance_id() % 9973) / 9973.0
		rig.set_meta("an", {"seed": sd, "rate": 0.85 + sd * 0.3})
	return rig.get_meta("an")

## Damped spring (k stiffness, z damping ratio). Gives overshoot and settle.
static func spring(D: Dictionary, key: String, target: float, k: float, z: float, dt: float) -> float:
	if not D.has(key):
		D[key] = target
		D[key + "_v"] = 0.0
		return target
	var x: float = D[key]
	var v: float = D[key + "_v"]
	var steps := maxi(1, int(ceil(dt / 0.012)))
	var h := dt / steps
	var c := 2.0 * sqrt(k) * z
	for i in steps:
		v += ((target - x) * k - v * c) * h
		x += v * h
	D[key] = x
	D[key + "_v"] = v
	return x

static func kick(D: Dictionary, key: String, impulse: float) -> void:
	D[key + "_v"] = D.get(key + "_v", 0.0) + impulse

## st: time, phase, move, atk (-1 or 0..1), style, block (0..1), hit (0..1)
static func pose(rig: Node3D, st: Dictionary) -> void:
	var J: Dictionary = rig.get_meta("j")
	if rig.has_meta("crawler"):
		_pose_crawler(rig, J, st, rig.get_meta("h"))
		return
	var h: float = rig.get_meta("h")
	var t: float = st.get("time", 0.0)
	var ph: float = st.get("phase", 0.0)
	var m: float = st.get("move", 0.0)
	var a: float = st.get("atk", -1.0)
	var style: String = st.get("style", "over")
	var b: float = st.get("block", 0.0)
	var hit: float = st.get("hit", 0.0)
	var zombie: bool = st.get("zombie", false)

	var D := _mem(rig)
	var dt := clampf(t - D.get("t", t), 0.0, 0.05)
	D["t"] = t
	var sd: float = D["seed"]
	var rate: float = D["rate"]
	var pers: String = rig.get_meta("pers", "")
	var heavy := pers == "boss"
	var shamble := zombie or pers == "zombie"
	var twitchy := pers == "fallen"
	var bony := pers == "skeleton"
	var breathe_rate := (1.2 if heavy else (2.6 if twitchy else 1.6)) * rate
	var breathe := sin(t * breathe_rate + sd * 10.0) * (0.04 if heavy else 0.025)
	var leg_l := sin(ph) * 0.62 * m
	var leg_r := -leg_l
	var knee_l := -(maxf(0.0, cos(ph)) * 1.05 * m + 0.04)
	var knee_r := -(maxf(0.0, -cos(ph)) * 1.05 * m + 0.04)
	var shl := Vector3(-leg_l * 0.75 + 0.05, 0.0, -0.1)
	var shr := Vector3(-leg_r * 0.35 + 0.15, 0.0, 0.12)
	var ell := 0.25 + m * 0.2
	var elr := 0.45
	var tx := breathe * 0.5 - 0.09 * m
	var ty := sin(ph) * 0.1 * m
	var hy := ((cos(2.0 * ph) * 0.5 + 0.5) * 0.035 - 0.02) * m * h
	var hz := 0.0
	var tz := 0.0
	var head_z := 0.0
	var hip_x := 0.0
	var hip_yaw := 0.0
	var hip_roll := 0.0
	var hip_spin := 0.0   # a whole-body turn about the hips (the swipe3 spin); not smoothed
	var hip_turn := 0.0   # the hips turning over planted feet (the legs counter-turn)
	var grip_p := 0.0     # wrist: blade cocked back (+) or thrown out in line with the arm (-)
	var grip_y := 0.0
	var swiping := false
	var head_x := 0.0
	var head_y := sin(t * 0.37) * 0.15 * (1.0 - m)

	# sprint pose: shield up across the chest, sword carried high, deep lean and knee drive
	var rf := run_factor(m) * (0.0 if (zombie or pers == "zombie") else 1.0)
	if rf > 0.0:
		var pump := sin(ph)
		shl = shl.lerp(Vector3(1.05 + pump * 0.1, 0.12, 0.45), rf)
		ell = lerpf(ell, 1.35 - pump * 0.1, rf)
		shr = shr.lerp(Vector3(0.9 - pump * 0.22, 0.0, 0.22), rf)
		elr = lerpf(elr, 1.05 + pump * 0.18, rf)
		knee_l -= (maxf(0.0, cos(ph)) * 0.45 + maxf(0.0, -sin(ph)) * 0.6) * rf
		knee_r -= (maxf(0.0, -cos(ph)) * 0.45 + maxf(0.0, sin(ph)) * 0.6) * rf
		tx -= 0.17 * rf
		hy += (cos(2.0 * ph) * 0.5 + 0.5) * 0.035 * h * rf
		head_x += 0.15 * rf
	if shamble:
		# limp: the right leg drags and stays stiff
		leg_r *= 0.55
		knee_r *= 0.4
		shl.x = lerpf(shl.x, 1.3, 0.8)
		shr.x = lerpf(shr.x, 1.2, 0.8)
		ell = 0.2
		elr = 0.2
		tx -= 0.15
		head_x = 0.25

	if a >= 0.0:
		match style:
			"over":
				shr.x = kf(a, [[0, 0.3], [0.35, 3.3], [0.52, 0.45], [1, 0.3]])
				shr.z = kf(a, [[0, 0.1], [0.35, 0.55], [0.52, -0.3], [1, 0.1]])
				elr = kf(a, [[0, 0.4], [0.35, 1.3], [0.52, 0.15], [1, 0.4]])
				ty += kf(a, [[0, 0.0], [0.35, -0.5], [0.52, 0.45], [1, 0.0]])
				tx += kf(a, [[0, 0.0], [0.35, 0.12], [0.52, -0.28], [1, 0.0]])
				hz = kf(a, [[0, 0.0], [0.35, 0.05], [0.52, -0.16], [1, 0.0]]) * h
				leg_r += kf(a, [[0, 0.0], [0.35, -0.15], [0.52, 0.5], [1, 0.0]])
				leg_l += kf(a, [[0, 0.0], [0.52, -0.3], [1, 0.0]])
				knee_r -= kf(a, [[0, 0.0], [0.52, 0.35], [1, 0.0]])
				shl.x += kf(a, [[0, 0.0], [0.35, 0.5], [0.52, -0.2], [1, 0.0]])
			"back":
				# backhand: wind up across the body, sweep out to the right
				shr.x = kf(a, [[0, 0.3], [0.3, 1.25], [0.5, 1.5], [0.7, 1.2], [1, 0.3]])
				shr.y = kf(a, [[0, 0.0], [0.3, 1.25], [0.5, -0.6], [0.7, -1.2], [1, 0.0]])
				shr.z = kf(a, [[0, 0.1], [0.3, -0.35], [0.5, 0.2], [1, 0.1]])
				elr = kf(a, [[0, 0.4], [0.3, 1.6], [0.5, 0.15], [1, 0.4]])
				ty += kf(a, [[0, 0.0], [0.3, 0.6], [0.5, -0.45], [0.7, -0.6], [1, 0.0]])
				tx += kf(a, [[0, 0.0], [0.3, 0.06], [0.5, -0.12], [1, 0.0]])
				hz = kf(a, [[0, 0.0], [0.5, -0.12], [1, 0.0]]) * h
				leg_l += kf(a, [[0, 0.0], [0.5, 0.42], [1, 0.0]])
				knee_l -= kf(a, [[0, 0.0], [0.5, 0.35], [1, 0.0]])
				shl.x += kf(a, [[0, 0.0], [0.3, -0.2], [0.5, 0.45], [1, 0.0]])
			"side":
				shr.x = kf(a, [[0, 0.3], [0.28, 1.45], [0.62, 1.35], [1, 0.3]])
				shr.y = kf(a, [[0, 0.0], [0.28, -1.35], [0.62, 1.3], [1, 0.0]])
				elr = kf(a, [[0, 0.4], [0.28, 0.9], [0.5, 0.1], [1, 0.4]])
				ty += kf(a, [[0, 0.0], [0.28, -0.7], [0.62, 0.75], [1, 0.0]])
				hz = kf(a, [[0, 0.0], [0.48, -0.12], [1, 0.0]]) * h
				leg_r += kf(a, [[0, 0.0], [0.48, 0.4], [1, 0.0]])
				knee_r -= kf(a, [[0, 0.0], [0.48, 0.3], [1, 0.0]])
			"thrust":
				shr.x = kf(a, [[0, 0.4], [0.35, 0.75], [0.52, 1.55], [1, 0.4]])
				elr = kf(a, [[0, 0.5], [0.35, 1.8], [0.52, 0.0], [1, 0.5]])
				ty += kf(a, [[0, 0.0], [0.35, -0.35], [0.52, 0.2], [1, 0.0]])
				hz = kf(a, [[0, 0.0], [0.35, 0.06], [0.52, -0.2], [1, 0.0]]) * h
				leg_r += kf(a, [[0, 0.0], [0.52, 0.5], [1, 0.0]])
				shl.x += kf(a, [[0, 0.0], [0.52, 0.6], [1, 0.0]])
			# --- the right-click combo (Hero.swipe_attack): three cuts a knight would chain. Each is driven
			# from the ground up: the feet step, the hips turn first (hip_turn, over planted feet), the
			# shoulders follow on their spring, the arm last, and the wrist (grip_p) cocks the blade back
			# in the wind-up and throws it out in line with the arm through the cut. The shield arm pulls
			# in against the turn. Each swipe starts from the pose the last one is cut off in (a = 0.68),
			# so the chain flows.
			"swipe1":
				# Oberhau: from a high guard over the right shoulder, a diagonal cut down to the left hip,
				# stepping in on the right foot and dropping the weight onto it
				swiping = true
				shr.x = kf(a, [[0, 0.5], [0.24, 2.65], [0.34, 1.9], [0.42, 0.85], [0.6, 0.55], [1, 0.3]])
				shr.y = kf(a, [[0, 0.0], [0.24, -0.7], [0.34, -0.05], [0.42, 1.05], [0.6, 1.25], [1, 0.0]])
				shr.z = kf(a, [[0, 0.1], [0.24, 0.55], [0.42, -0.15], [0.6, -0.1], [1, 0.1]])
				elr = kf(a, [[0, 0.5], [0.24, 1.75], [0.34, 0.9], [0.42, 0.12], [0.6, 0.3], [1, 0.4]])
				grip_p = kf(a, [[0, 0.0], [0.24, 0.95], [0.34, 0.2], [0.42, -0.75], [0.6, -0.45], [1, 0.0]])
				hip_turn = kf(a, [[0, 0.0], [0.24, -0.38], [0.38, 0.32], [0.6, 0.38], [1, 0.0]])
				ty += kf(a, [[0, 0.0], [0.24, -0.55], [0.42, 0.5], [0.6, 0.58], [1, 0.0]])
				tx += kf(a, [[0, 0.0], [0.24, 0.16], [0.42, -0.34], [0.6, -0.3], [1, 0.0]])
				tz += kf(a, [[0, 0.0], [0.24, -0.08], [0.42, 0.1], [1, 0.0]])
				hz = kf(a, [[0, 0.0], [0.24, 0.05], [0.42, -0.14], [0.7, -0.12], [1, 0.0]]) * h
				hy -= kf(a, [[0, 0.0], [0.24, -0.02], [0.42, 0.08], [0.6, 0.07], [1, 0.0]]) * h
				hip_x += kf(a, [[0, 0.0], [0.24, -0.03], [0.42, 0.04], [1, 0.0]]) * h
				# the right foot lifts in the wind-up and plants forward on the cut; the left pushes off
				leg_r += kf(a, [[0, 0.0], [0.24, 0.3], [0.42, 0.62], [0.7, 0.5], [1, 0.0]])
				knee_r -= kf(a, [[0, 0.0], [0.24, 0.75], [0.42, 0.38], [0.7, 0.42], [1, 0.0]])
				leg_l += kf(a, [[0, 0.0], [0.24, 0.05], [0.42, -0.42], [0.7, -0.38], [1, 0.0]])
				knee_l -= kf(a, [[0, 0.0], [0.24, 0.2], [0.42, 0.12], [0.7, 0.18], [1, 0.0]])
				shl.x += kf(a, [[0, 0.0], [0.24, 0.65], [0.42, 0.9], [0.6, 0.8], [1, 0.0]])
				shl.z += kf(a, [[0, 0.0], [0.24, -0.3], [0.42, 0.15], [1, 0.0]])
				ell += kf(a, [[0, 0.0], [0.42, 1.0], [0.6, 0.9], [1, 0.0]])
				head_x = kf(a, [[0, 0.0], [0.24, -0.12], [0.42, 0.18], [1, 0.0]])
			"swipe2":
				# Unterhau: sink low with the blade carried back past the left hip, then a passing step
				# with the left foot as the cut rips up and out to the right, coming up out of the knees
				swiping = true
				shr.x = kf(a, [[0, 0.55], [0.22, 0.35], [0.32, 0.95], [0.42, 2.25], [0.6, 2.55], [1, 0.3]])
				shr.y = kf(a, [[0, 1.25], [0.22, 1.45], [0.32, 0.6], [0.42, -1.0], [0.6, -1.2], [1, 0.0]])
				shr.z = kf(a, [[0, -0.1], [0.22, -0.25], [0.42, 0.55], [0.6, 0.6], [1, 0.1]])
				elr = kf(a, [[0, 0.3], [0.22, 1.35], [0.32, 0.7], [0.42, 0.12], [0.6, 0.35], [1, 0.4]])
				grip_p = kf(a, [[0, -0.45], [0.22, 0.75], [0.32, 0.2], [0.42, -0.85], [0.6, -0.3], [1, 0.0]])
				hip_turn = kf(a, [[0, 0.38], [0.22, 0.5], [0.4, -0.3], [0.6, -0.38], [1, 0.0]])
				ty += kf(a, [[0, 0.58], [0.22, 0.7], [0.42, -0.55], [0.6, -0.62], [1, 0.0]])
				tx += kf(a, [[0, -0.3], [0.22, -0.36], [0.42, 0.12], [0.6, 0.06], [1, 0.0]])
				tz += kf(a, [[0, 0.0], [0.22, 0.1], [0.42, -0.12], [1, 0.0]])
				hy -= kf(a, [[0, 0.07], [0.22, 0.14], [0.34, 0.1], [0.44, -0.02], [0.6, 0.0], [1, 0.0]]) * h
				hz = kf(a, [[0, -0.12], [0.22, -0.08], [0.42, -0.16], [0.7, -0.1], [1, 0.0]]) * h
				hip_x += kf(a, [[0, 0.04], [0.22, 0.05], [0.42, -0.04], [1, 0.0]]) * h
				# passing step: the left foot comes through (knee up at the midpoint) and lands in front
				leg_l += kf(a, [[0, -0.38], [0.22, -0.3], [0.32, 0.25], [0.44, 0.6], [0.7, 0.5], [1, 0.0]])
				knee_l -= kf(a, [[0, 0.18], [0.22, 0.4], [0.32, 1.0], [0.44, 0.35], [0.7, 0.4], [1, 0.0]])
				leg_r += kf(a, [[0, 0.5], [0.22, 0.45], [0.44, -0.4], [0.7, -0.35], [1, 0.0]])
				knee_r -= kf(a, [[0, 0.42], [0.22, 0.7], [0.44, 0.15], [0.7, 0.2], [1, 0.0]])
				shl.x += kf(a, [[0, 0.8], [0.22, 0.95], [0.42, -0.15], [0.6, -0.1], [1, 0.0]])
				shl.z += kf(a, [[0, 0.0], [0.22, 0.2], [0.42, -0.55], [0.6, -0.5], [1, 0.0]])
				ell += kf(a, [[0, 0.9], [0.22, 1.0], [0.42, 0.3], [1, 0.0]])
				head_x = kf(a, [[0, 0.15], [0.22, 0.25], [0.42, -0.18], [1, 0.0]])
			"swipe3":
				# finisher: drop into a crouch with the blade trailing low behind the right hip, then pivot
				# a full turn on the left foot with the arm and blade flung straight out (a flat cut all
				# round), the right leg sweeping round, and land wide and low with the sword out in front
				swiping = true
				shr.x = kf(a, [[0, 2.5], [0.2, 0.75], [0.3, 1.45], [0.62, 1.42], [0.78, 1.3], [1, 0.3]])
				shr.y = kf(a, [[0, -1.2], [0.2, -1.05], [0.3, -1.25], [0.62, -1.15], [0.78, -0.45], [1, 0.0]])
				shr.z = kf(a, [[0, 0.6], [0.2, 0.5], [0.3, 0.3], [0.62, 0.3], [1, 0.1]])
				elr = kf(a, [[0, 0.35], [0.2, 1.05], [0.3, 0.06], [0.62, 0.06], [0.78, 0.45], [1, 0.4]])
				grip_p = kf(a, [[0, -0.3], [0.2, 0.55], [0.3, -0.95], [0.62, -0.95], [0.78, -0.15], [1, 0.0]])
				grip_y = kf(a, [[0, 0.0], [0.3, 0.35], [0.62, 0.3], [0.8, 0.0]])
				hip_spin = kf(a, [[0, 0.0], [0.2, -0.95], [0.64, TAU], [1, TAU]])
				hip_turn = kf(a, [[0, -0.38], [0.2, -0.2], [0.3, 0.0], [1, 0.0]])
				ty += kf(a, [[0, -0.62], [0.2, -0.45], [0.3, 0.25], [0.62, 0.15], [0.8, 0.1], [1, 0.0]])
				tx += kf(a, [[0, 0.06], [0.2, -0.3], [0.45, -0.12], [0.7, -0.38], [0.85, -0.3], [1, 0.0]])
				tz += kf(a, [[0, 0.0], [0.3, 0.16], [0.6, 0.14], [0.75, 0.0]])
				hy += kf(a, [[0, 0.0], [0.2, -0.13], [0.42, 0.06], [0.66, -0.16], [0.85, -0.12], [1, 0.0]]) * h
				hz = kf(a, [[0, -0.1], [0.2, 0.0], [0.66, -0.1], [1, 0.0]]) * h
				knee_l -= kf(a, [[0, 0.4], [0.2, 0.9], [0.42, 0.3], [0.66, 0.95], [0.85, 0.85], [1, 0.0]])
				knee_r -= kf(a, [[0, 0.2], [0.2, 0.75], [0.36, 1.1], [0.5, 0.6], [0.66, 0.9], [0.85, 0.8], [1, 0.0]])
				leg_l += kf(a, [[0, 0.5], [0.2, 0.4], [0.42, 0.1], [0.66, 0.6], [0.85, 0.55], [1, 0.0]])
				leg_r += kf(a, [[0, -0.35], [0.2, -0.3], [0.36, 0.45], [0.5, 0.2], [0.66, -0.45], [0.85, -0.4], [1, 0.0]])
				shl.x += kf(a, [[0, -0.1], [0.2, 0.4], [0.3, 0.7], [0.62, 0.7], [0.8, 0.4], [1, 0.0]])
				shl.z += kf(a, [[0, -0.5], [0.3, -0.85], [0.62, -0.8], [0.8, -0.3], [1, 0.0]])
				ell += kf(a, [[0, 0.3], [0.3, 0.5], [0.8, 0.3], [1, 0.0]])
				head_x = kf(a, [[0, -0.15], [0.2, 0.15], [0.7, 0.22], [1, 0.0]])
			"cleave":
				# Holy Slam (the knight's Q): a leaping slam. He sinks into a crouch with the sword drawn back,
				# springs up and forward with the blade raised high over his head and his back arched, then
				# drives it down with everything as he lands, dropping into a deep lunge as the blade hits
				# the ground in front of him; he holds the blow a moment, then rises back to the guard
				swiping = true
				shr.x = kf(a, [[0, 0.3], [0.18, 0.9], [0.36, 3.25], [0.44, 2.6], [0.5, 0.75], [0.72, 0.7], [1, 0.3]])
				shr.y = kf(a, [[0, 0.0], [0.18, -0.6], [0.36, 0.1], [0.5, 0.25], [0.72, 0.2], [1, 0.0]])
				shr.z = kf(a, [[0, 0.1], [0.18, 0.4], [0.36, 0.25], [0.5, -0.1], [1, 0.1]])
				elr = kf(a, [[0, 0.4], [0.18, 1.2], [0.36, 1.55], [0.44, 0.9], [0.5, 0.05], [0.72, 0.1], [1, 0.4]])
				grip_p = kf(a, [[0, 0.0], [0.18, 0.6], [0.36, 0.95], [0.44, 0.3], [0.5, -0.75], [0.72, -0.65], [1, 0.0]])
				# the shield arm swings up with the leap and drives down beside the blow
				shl.x += kf(a, [[0, 0.0], [0.18, -0.3], [0.36, 1.8], [0.5, 0.7], [0.72, 0.6], [1, 0.0]])
				shl.z += kf(a, [[0, 0.0], [0.36, -0.35], [0.5, -0.2], [1, 0.0]])
				ell += kf(a, [[0, 0.0], [0.36, 0.6], [0.5, 0.9], [1, 0.0]])
				# crouch, spring, hang in the air, land hard and sink into the blow
				hy += kf(a, [[0, 0.0], [0.18, -0.17], [0.26, 0.12], [0.36, 0.42], [0.44, 0.3], [0.5, -0.24], [0.56, -0.28], [0.72, -0.24], [0.88, -0.06], [1, 0.0]]) * h
				tx += kf(a, [[0, 0.0], [0.18, -0.3], [0.36, 0.3], [0.44, 0.15], [0.5, -0.62], [0.72, -0.55], [1, 0.0]])
				ty += kf(a, [[0, 0.0], [0.18, -0.25], [0.36, 0.0], [0.5, 0.12], [1, 0.0]])
				hz = kf(a, [[0, 0.0], [0.18, 0.08], [0.5, -0.12], [0.72, -0.12], [1, 0.0]]) * h
				hip_turn = kf(a, [[0, 0.0], [0.18, -0.25], [0.4, 0.0], [0.5, 0.15], [1, 0.0]])
				# legs: crouch, push off straight, tuck in the air, land in a deep lunge (left foot forward,
				# right knee nearly down)
				knee_l -= kf(a, [[0, 0.0], [0.18, 1.0], [0.26, 0.15], [0.36, 1.1], [0.44, 0.7], [0.5, 1.05], [0.72, 1.0], [0.9, 0.3], [1, 0.0]])
				knee_r -= kf(a, [[0, 0.0], [0.18, 1.0], [0.26, 0.1], [0.36, 1.25], [0.44, 0.9], [0.5, 1.4], [0.72, 1.35], [0.9, 0.35], [1, 0.0]])
				leg_l += kf(a, [[0, 0.0], [0.18, 0.55], [0.26, 0.05], [0.36, 0.75], [0.5, 0.85], [0.72, 0.8], [0.9, 0.25], [1, 0.0]])
				leg_r += kf(a, [[0, 0.0], [0.18, 0.45], [0.26, -0.2], [0.36, 0.5], [0.5, -0.45], [0.72, -0.4], [0.9, -0.1], [1, 0.0]])
				head_x = kf(a, [[0, 0.0], [0.18, 0.15], [0.36, -0.25], [0.5, 0.35], [0.72, 0.3], [1, 0.0]])
			"bow":
				shl.x = kf(a, [[0, 0.2], [0.25, 1.55], [0.85, 1.55], [1, 0.2]])
				shl.z = kf(a, [[0, -0.1], [0.25, 0.2], [0.85, 0.2], [1, -0.1]])
				ell = kf(a, [[0, 0.3], [0.25, 0.0], [0.85, 0.0], [1, 0.3]])
				shr.x = kf(a, [[0, 0.2], [0.25, 1.45], [0.85, 1.45], [1, 0.2]])
				elr = kf(a, [[0, 0.3], [0.25, 0.6], [0.7, 2.3], [0.74, 0.4], [1, 0.3]])
				ty += kf(a, [[0, 0.0], [0.25, -0.55], [0.85, -0.55], [1, 0.0]])
			"cast":
				shl.x = kf(a, [[0, 0.2], [0.4, 2.7], [0.6, 1.4], [1, 0.2]])
				shr.x = shl.x
				shl.z = kf(a, [[0, -0.1], [0.4, -0.4], [0.6, 0.15], [1, -0.1]])
				shr.z = -shl.z
				ell = 0.3
				elr = 0.3
				tx += kf(a, [[0, 0.0], [0.4, 0.15], [0.6, -0.2], [1, 0.0]])
				head_x = kf(a, [[0, 0.0], [0.4, -0.25], [0.6, 0.1], [1, 0.0]])
			"claw":
				shr.x = kf(a, [[0, 0.7], [0.28, 2.5], [0.45, 0.6], [1, 0.7]])
				shl.x = kf(a, [[0, 0.7], [0.4, 2.3], [0.6, 0.6], [1, 0.7]])
				elr = 0.5
				ell = 0.5
				tx += kf(a, [[0, 0.0], [0.3, 0.15], [0.48, -0.3], [1, 0.0]])
				hz = kf(a, [[0, 0.0], [0.45, -0.12], [1, 0.0]]) * h
			"slam":
				shl.x = kf(a, [[0, 0.3], [0.4, 3.2], [0.58, 0.6], [1, 0.3]])
				shr.x = shl.x
				shl.z = kf(a, [[0, -0.1], [0.4, 0.3], [0.58, 0.2], [1, -0.1]])
				shr.z = -shl.z
				ell = kf(a, [[0, 0.3], [0.4, 0.9], [0.58, 0.1], [1, 0.3]])
				elr = ell
				tx += kf(a, [[0, 0.0], [0.4, 0.28], [0.58, -0.55], [1, 0.0]])
				hy -= kf(a, [[0, 0.0], [0.58, 0.12], [1, 0.0]]) * h
				leg_l += kf(a, [[0, 0.0], [0.58, 0.5], [1, 0.0]])
				leg_r += kf(a, [[0, 0.0], [0.58, 0.5], [1, 0.0]])
				knee_l -= kf(a, [[0, 0.0], [0.58, 0.9], [1, 0.0]])
				knee_r -= kf(a, [[0, 0.0], [0.58, 0.9], [1, 0.0]])
			"smash":
				# a heavy overhead blow: lean back and hold, then slam down through the hips
				shr.x = kf(a, [[0, 0.3], [0.4, 3.35], [0.5, 3.5], [0.58, 0.25], [0.72, 0.05], [1, 0.3]])
				shr.z = kf(a, [[0, 0.1], [0.4, 0.4], [0.58, -0.25], [1, 0.1]])
				elr = kf(a, [[0, 0.4], [0.4, 1.4], [0.5, 1.6], [0.58, 0.1], [1, 0.4]])
				shl.x = kf(a, [[0, 0.2], [0.4, 1.6], [0.58, 0.6], [1, 0.2]])
				shl.z = kf(a, [[0, -0.1], [0.4, -0.5], [0.58, -0.2], [1, -0.1]])
				tx += kf(a, [[0, 0.0], [0.4, 0.26], [0.5, 0.3], [0.58, -0.45], [0.75, -0.38], [1, 0.0]])
				ty += kf(a, [[0, 0.0], [0.4, -0.25], [0.58, 0.2], [1, 0.0]])
				hy -= kf(a, [[0, 0.0], [0.5, 0.0], [0.6, 0.1], [0.8, 0.07], [1, 0.0]]) * h
				knee_l -= kf(a, [[0, 0.0], [0.6, 0.55], [1, 0.0]])
				knee_r -= kf(a, [[0, 0.0], [0.6, 0.55], [1, 0.0]])
				leg_r += kf(a, [[0, 0.0], [0.4, -0.2], [0.58, 0.5], [1, 0.0]])
				leg_l -= kf(a, [[0, 0.0], [0.58, 0.2], [1, 0.0]])
				head_x = kf(a, [[0, 0.0], [0.4, 0.25], [0.58, -0.2], [1, 0.0]])
			"lob":
				# off-hand throw: reach back, twist, sling it high
				shl.x = kf(a, [[0, 0.2], [0.38, -0.95], [0.55, 2.5], [0.75, 1.5], [1, 0.2]])
				shl.z = kf(a, [[0, -0.1], [0.38, -0.35], [0.55, 0.1], [1, -0.1]])
				ell = kf(a, [[0, 0.3], [0.38, 1.3], [0.55, 0.1], [1, 0.3]])
				ty += kf(a, [[0, 0.0], [0.38, -0.55], [0.55, 0.5], [1, 0.0]])
				tx += kf(a, [[0, 0.0], [0.38, 0.18], [0.55, -0.25], [1, 0.0]])
				leg_l += kf(a, [[0, 0.0], [0.55, 0.45], [1, 0.0]])
				knee_l -= kf(a, [[0, 0.0], [0.55, 0.3], [1, 0.0]])
			"scoop":
				# crouch, rake in with both arms, hug it to the chest
				tx += kf(a, [[0, 0.0], [0.3, -0.6], [0.55, -0.55], [0.8, -0.1], [1, 0.0]])
				hy -= kf(a, [[0, 0.0], [0.3, 0.14], [0.6, 0.14], [1, 0.0]]) * h
				knee_l -= kf(a, [[0, 0.0], [0.3, 0.9], [0.6, 0.9], [1, 0.0]])
				knee_r -= kf(a, [[0, 0.0], [0.3, 0.9], [0.6, 0.9], [1, 0.0]])
				leg_l += kf(a, [[0, 0.0], [0.3, 0.45], [0.6, 0.45], [1, 0.0]])
				leg_r += kf(a, [[0, 0.0], [0.3, 0.45], [0.6, 0.45], [1, 0.0]])
				shl.x = kf(a, [[0, 0.2], [0.3, 1.4], [0.5, 0.8], [0.75, 1.5], [1, 0.2]])
				shr.x = shl.x
				shl.z = kf(a, [[0, -0.1], [0.3, -0.3], [0.5, 0.35], [0.75, 0.45], [1, -0.1]])
				shr.z = -shl.z
				ell = kf(a, [[0, 0.3], [0.3, 0.3], [0.5, 0.9], [0.75, 1.9], [1, 0.3]])
				elr = ell
				head_x = kf(a, [[0, 0.0], [0.3, -0.3], [0.75, 0.1], [1, 0.0]])
			"burst":
				# staggered: thrown back, arms flung up
				tx += kf(a, [[0, 0.0], [0.2, 0.42], [0.65, 0.3], [1, 0.0]])
				shl.x = kf(a, [[0, 0.2], [0.2, 2.3], [0.6, 1.9], [1, 0.2]])
				shr.x = kf(a, [[0, 0.2], [0.22, 2.0], [0.6, 1.7], [1, 0.2]])
				shl.z = kf(a, [[0, 0.0], [0.2, -0.75], [0.6, -0.5], [1, 0.0]])
				shr.z = -shl.z
				head_x = kf(a, [[0, 0.0], [0.2, 0.45], [0.7, 0.3], [1, 0.0]])
				knee_l -= kf(a, [[0, 0.0], [0.2, 0.4], [1, 0.0]])
				knee_r -= kf(a, [[0, 0.0], [0.2, 0.4], [1, 0.0]])
			"cackle":
				# leans back and shakes with laughter, arms spread
				var shake := sin(a * 70.0) * 0.06 * sin(a * PI)
				tx += kf(a, [[0, 0.0], [0.2, 0.3], [0.85, 0.3], [1, 0.0]]) + shake
				shl.x = kf(a, [[0, 0.2], [0.2, 0.75], [0.85, 0.75], [1, 0.2]]) + shake * 2.0
				shr.x = kf(a, [[0, 0.2], [0.2, 0.9], [0.85, 0.9], [1, 0.2]]) - shake * 2.0
				shl.z = kf(a, [[0, 0.0], [0.2, -0.6], [0.85, -0.6], [1, 0.0]])
				shr.z = -shl.z
				ell = 0.9
				elr = 0.9
				head_x = kf(a, [[0, 0.0], [0.2, 0.4], [0.85, 0.4], [1, 0.0]]) + shake

	if b > 0.0:
		shl = shl.lerp(Vector3(1.2, 0.15, 0.55), b)
		ell = lerpf(ell, 1.45, b)
		if a < 0.0:
			shr = shr.lerp(Vector3(0.5, 0.0, 0.25), b)
			elr = lerpf(elr, 0.9, b)
		tx -= 0.12 * b
		leg_l += 0.28 * b
		leg_r += 0.12 * b
		knee_l -= 0.5 * b
		knee_r -= 0.35 * b
		hy -= 0.06 * h * b

	if hit > 0.0:
		tx += 0.35 * hit
		head_x += 0.3 * hit
		shl.z -= 0.35 * hit
		shr.z += 0.35 * hit

	var idle := clampf(1.0 - m, 0.0, 1.0) * (1.0 if a < 0.0 else 0.3) * (1.0 - b)
	var mm := clampf(m, 0.0, 1.4)

	# --- idle life: breathing, weight shifts, glances, fidgets
	var br := sin(t * breathe_rate + sd * 10.0)
	shl.z -= br * 0.03 * idle
	shr.z += br * 0.03 * idle
	head_x -= br * 0.015 * idle
	var ws := n1(t * 0.33 * rate + sd * 20.0)
	hip_x += ws * 0.028 * h * idle
	hip_roll -= ws * 0.05 * idle
	tz += ws * 0.035 * idle
	knee_l -= maxf(0.0, ws) * 0.2 * idle
	knee_r -= maxf(0.0, -ws) * 0.2 * idle
	hy -= absf(ws) * 0.012 * h * idle
	var glance_speed := 0.7 if twitchy else 0.22
	head_y = n1(t * glance_speed * rate + sd * 7.0) * (0.55 if twitchy else 0.4) * idle
	head_x += n1(t * glance_speed * 0.8 + sd * 3.0) * 0.1 * idle
	shl.x += n1(t * 0.41 + sd * 5.0) * 0.05 * idle
	shr.x += n1(t * 0.37 + sd * 9.0) * 0.04 * idle
	ell += (n1(t * 0.5 + sd) * 0.5 + 0.5) * 0.12 * idle
	if shamble:
		head_z += n1(t * 0.6 + sd * 4.0) * 0.32
		head_x += 0.15 + n1(t * 0.45 + sd) * 0.12
		tz += n1(t * 0.4 + sd * 2.0) * 0.1
		if fmod(t * rate + sd * 17.0, 7.3) < 0.18:
			head_z += sin(t * 70.0) * 0.25
			shl.z -= sin(t * 60.0) * 0.2
	if bony:
		head_y += sin(t * 23.0 + sd * 40.0) * 0.03
		head_x += sin(t * 31.0 + sd * 13.0) * 0.02
		shl.z -= absf(sin(t * 19.0)) * 0.03
	if twitchy:
		tx -= 0.22
		hy += absf(sin(t * 5.0 * rate + sd * 8.0)) * 0.025 * h * idle
		shl.x += 0.25
		shr.x += 0.25
	if heavy:
		var deep := sin(t * 0.9 + sd * 6.0)
		tx += deep * 0.04 * idle
		shl.z -= deep * 0.06 * idle
		shr.z += deep * 0.06 * idle
		head_y = n1(t * 0.15 + sd * 7.0) * 0.5 * idle

	# --- locomotion: pelvis twist, counter-rotating shoulders, side-to-side weight
	hip_yaw -= sin(ph) * 0.15 * mm
	ty += sin(ph) * 0.14 * mm
	hip_x -= cos(ph) * 0.026 * h * mm * (1.8 if shamble else 1.0)
	hip_roll += cos(ph) * 0.07 * mm * (2.2 if shamble else 1.0)
	ell += maxf(0.0, -(shl.x - 0.05)) * 0.6 * mm
	elr += maxf(0.0, -(shr.x - 0.15)) * 0.35 * mm
	head_x += absf(sin(ph)) * 0.02 * mm

	# --- knight gait: a realistic run. The arms pump straight forward and back, opposite the legs,
	# elbows bent near a right angle and carried a little wide of the body; shoulders counter-rotate
	# against the hips, the body leans into the run and stays steady (no side-to-side rocking).
	if rig.has_meta("gait") and rig.get_meta("gait") == "knight" and mm > 0.02:
		var kg := clampf(mm * 1.6, 0.0, 1.0) * (1.0 - b) * (1.0 if a < 0.0 else 0.35)
		var sw := sin(ph)
		var amp := 0.45 + 0.25 * clampf(mm - 0.6, 0.0, 0.6) / 0.6
		# left arm swings with the right leg (counter to its own leg), and the reverse
		shl.x = lerpf(shl.x, 0.05 - sw * amp, kg)
		shr.x = lerpf(shr.x, 0.05 + sw * amp, kg)
		shl.y = lerpf(shl.y, 0.0, kg)
		shr.y = lerpf(shr.y, 0.0, kg)
		var wide: float = rig.get_meta("elbow_out") if rig.has_meta("elbow_out") else 1.0
		shl.z = lerpf(shl.z, -0.3 * wide, kg)
		shr.z = lerpf(shr.z, 0.3 * wide, kg)
		# elbows bend more as the arm comes forward, open a little as it drives back
		ell = lerpf(ell, 1.2 - sw * 0.18, kg)
		elr = lerpf(elr, 1.2 + sw * 0.18, kg)
		ty = lerpf(ty, sw * 0.16 * clampf(mm, 0.0, 1.0), kg)
		tz *= 1.0 - 0.8 * kg
		hip_roll *= 1.0 - 0.5 * kg
		tx -= 0.06 * kg

	# --- dynamics: lean into speed and acceleration, bank into turns, settle with overshoot
	var prev_m: float = D.get("pm", mm)
	var accel := (mm - prev_m) / maxf(dt, 0.001) if dt > 0.0 else 0.0
	D["pm"] = mm
	var yaw: float = rig.rotation.y
	var prev_yaw: float = D.get("py", yaw)
	var yaw_v := wrapf(yaw - prev_yaw, -PI, PI) / maxf(dt, 0.001) if dt > 0.0 else 0.0
	D["py"] = yaw
	var lean := spring(D, "lean", -0.1 * mm - clampf(accel, -6.0, 6.0) * 0.03, 60.0, 0.45, dt)
	var bank := spring(D, "bank", clampf(-yaw_v * 0.05 * mm, -0.3, 0.3), 45.0, 0.5, dt)
	tx += lean + 0.09 * m
	tz += bank
	hip_roll += bank * 0.6
	# hit reactions wobble on a spring instead of snapping
	var prev_hit: float = D.get("ph", 0.0)
	if hit > prev_hit + 0.2:
		kick(D, "wob", 6.0 * (hit - prev_hit))
		kick(D, "wobz", (randf() - 0.5) * 8.0 * (hit - prev_hit))
	D["ph"] = hit
	tx += spring(D, "wob", 0.0, 90.0, 0.25, dt)
	tz += spring(D, "wobz", 0.0, 90.0, 0.3, dt)
	# torso and head follow through with a little overshoot
	var stiff := 260.0 if a >= 0.0 else 140.0
	tx = spring(D, "tx", tx, stiff, 0.55, dt)
	# turning: the head looks into the turn first and the shoulders follow a little ("look", radians, + = left)
	var look: float = st.get("look", 0.0)
	ty = spring(D, "ty", ty + look * 0.3, stiff, 0.55, dt)
	head_x = spring(D, "hx", head_x - tx * 0.4, 80.0, 0.5, dt)
	head_y = spring(D, "hy", head_y - ty * 0.5 + look, 70.0, 0.55, dt)
	head_z = spring(D, "hz", head_z - tz * 0.6, 70.0, 0.5, dt)
	# the off-hand arm lags behind body motion
	shl.x = spring(D, "slx", shl.x, 120.0 if b < 0.3 else 400.0, 0.45, dt)
	ell = spring(D, "ell", ell, 120.0 if b < 0.3 else 400.0, 0.5, dt)

	(J["hips"] as Node3D).position = Vector3(hip_x, J["hips_y"] + hy, hz)
	if swiping:
		# the sword arm and wrist get a stiff spring: the snap of the cut stays, but there's no pop
		# where one swipe takes over from the last or starts from the guard
		shr = Vector3(spring(D, "srx", shr.x, 1100.0, 0.75, dt), spring(D, "sry", shr.y, 1100.0, 0.75, dt), spring(D, "srz", shr.z, 1100.0, 0.75, dt))
		elr = spring(D, "elr", elr, 1100.0, 0.75, dt)
		grip_p = spring(D, "gp", grip_p, 900.0, 0.7, dt)
		hip_turn = spring(D, "htn", hip_turn, 500.0, 0.7, dt)
		head_y -= ty * 0.35     # eyes stay on the foe while the shoulders turn
	else:
		# outside the combo the springs just track the pose, so the first cut starts from the guard
		for kv in [["srx", shr.x], ["sry", shr.y], ["srz", shr.z], ["elr", elr], ["gp", 0.0], ["htn", 0.0]]:
			D[kv[0]] = kv[1]
			D[kv[0] + "_v"] = 0.0
	if J.has("grip_r") and (swiping or D.get("grip_set", false)):
		(J["grip_r"] as Node3D).rotation = Vector3(deg_to_rad(-28.0) + grip_p, grip_y, 0.0)
		D["grip_set"] = swiping
	(J["hips"] as Node3D).rotation = Vector3(0, hip_yaw - ty * 0.2 + hip_spin + hip_turn, hip_roll)
	var dead: float = st.get("dead", 0.0)
	if dead > 0.0:
		var dk := clampf(dead * 2.0, 0.0, 1.0)
		knee_l -= dk * 1.1
		knee_r -= dk * 0.8
		leg_l += dk * 0.7
		leg_r += dk * 0.4
		tx -= dk * 0.4
		shl = shl.lerp(Vector3(0.6, 0.0, -0.5), dk)
		shr = shr.lerp(Vector3(0.8, 0.0, 0.6), dk)
	var torso: Node3D = J["torso"]
	torso.rotation = Vector3(tx, ty, tz - hip_roll * 0.7)
	(J["head"] as Node3D).rotation = Vector3(head_x, head_y, head_z)
	(J["sh_l"] as Node3D).rotation = Vector3(shl.x, shl.y, shl.z)
	(J["sh_r"] as Node3D).rotation = Vector3(shr.x, shr.y, shr.z)
	(J["el_l"] as Node3D).rotation = Vector3(ell, 0, 0)
	if J.has("bow_l"):
		(J["grip_l"] as Node3D).rotation = Vector3(-(shl.x + ell), 0.0, -shl.z)
	(J["el_r"] as Node3D).rotation = Vector3(elr, 0, 0)
	(J["leg_l"] as Node3D).rotation = Vector3(leg_l, -hip_turn * 0.85, -hip_roll * 0.5)
	(J["leg_r"] as Node3D).rotation = Vector3(leg_r, -hip_turn * 0.85, -hip_roll * 0.5)
	(J["knee_l"] as Node3D).rotation = Vector3(knee_l, 0, 0)
	(J["knee_r"] as Node3D).rotation = Vector3(knee_r, 0, 0)
	if J.has("wing_l"):
		var flap := sin(t * (9.0 if m > 0.1 else 3.0) * rate + sd * 5.0) * (0.45 if m > 0.1 else 0.15)
		var fold := spring(D, "wing", -0.4 - flap, 120.0, 0.4, dt)
		(J["wing_l"] as Node3D).rotation = Vector3(0, fold, sin(t * 2.0) * 0.05)
		(J["wing_r"] as Node3D).rotation = Vector3(0, -fold, -sin(t * 2.0) * 0.05)
	if J.has("tail"):
		var tw := spring(D, "tail", sin(t * 2.0 * rate + ph + sd * 6.0) * 0.3 - bank * 1.5, 30.0, 0.35, dt)
		(J["tail"] as Node3D).rotation = Vector3(-0.1 + sin(ph * 2.0) * 0.08 * mm, tw, 0)
	if rig.has_meta("goblin"):
		Goblin.after_pose(rig, J, D, st, dt)
	if rig.has_method("sync_pose"):
		rig.sync_pose(st)    # the mocap knight: motion capture with these moves laid over it
	elif rig.has_method("sync"):
		rig.sync()

static func _pose_crawler(rig: Node3D, J: Dictionary, st: Dictionary, s: float) -> void:
	var D := _mem(rig)
	var t: float = st.get("time", 0.0)
	var dt := clampf(t - D.get("t", t), 0.0, 0.05)
	D["t"] = t
	var sd: float = D["seed"]
	var ph: float = st.get("phase", 0.0)
	var m: float = st.get("move", 0.0)
	var a: float = st.get("atk", -1.0)
	var hit: float = st.get("hit", 0.0)
	var body: Node3D = J["body"]
	var lunge := 0.0
	var pitch := 0.0
	var idle := clampf(1.0 - m, 0.0, 1.0)
	var mand := 0.15 + sin(t * 6.0 + sd * 9.0) * 0.1 + maxf(0.0, sin(t * 17.0)) * 0.08 * idle
	if a >= 0.0:
		lunge = kf(a, [[0, 0.0], [0.35, 0.15], [0.5, -0.35], [1, 0.0]]) * s
		pitch = kf(a, [[0, 0.0], [0.35, 0.2], [0.5, -0.15], [1, 0.0]])
		mand = kf(a, [[0, 0.1], [0.35, 0.7], [0.5, -0.1], [1, 0.1]])
	var yaw: float = rig.rotation.y
	var yaw_v := wrapf(yaw - D.get("py", yaw), -PI, PI) / maxf(dt, 0.001) if dt > 0.0 else 0.0
	D["py"] = yaw
	var bank := spring(D, "bank", clampf(-yaw_v * 0.06, -0.25, 0.25), 50.0, 0.5, dt)
	var breath := sin(t * 1.4 + sd * 8.0) * 0.012 * s
	var bob := spring(D, "bob", sin(ph * 2.0) * 0.03 * m * s, 160.0, 0.35, dt)
	var tilt := spring(D, "tilt", -0.06 * m, 40.0, 0.4, dt)
	var prev_hit: float = D.get("ph", 0.0)
	if hit > prev_hit + 0.2:
		kick(D, "wob", 7.0 * (hit - prev_hit))
	D["ph"] = hit
	var wob := spring(D, "wob", 0.0, 90.0, 0.25, dt)
	body.position = Vector3(sin(ph) * 0.015 * m * s, J["body_y"] + bob + breath, lunge)
	body.rotation = Vector3(pitch + tilt + wob + n1(t * 0.5 + sd) * 0.03 * idle, n1(t * 0.3 + sd * 4.0) * 0.08 * idle, sin(ph) * 0.06 * m + bank)
	body.scale = Vector3(1.0, 1.0 + sin(t * 1.4 + sd * 8.0) * 0.02, 1.0)
	for side in [1, -1]:
		(J["mand_" + str(side)] as Node3D).rotation = Vector3(0, side * mand, 0)
	var li := 0
	for L in J["legs"]:
		var hip: Node3D = L["hip"]
		var p: float = ph + L["phase"]
		var fidget := n1(t * 0.9 + li * 1.7 + sd * 11.0)
		var lift := maxf(0.0, cos(p)) * 0.42 * m + maxf(0.0, fidget - 0.6) * 0.5 * idle
		hip.rotation = Vector3(0, L["base_y"] + sin(p) * 0.36 * m + fidget * 0.05 * idle, lift + sin(t * 2.0 + p) * 0.03 - bank * float(L["side"]) * 0.5)
		li += 1

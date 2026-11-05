class_name SmithForge
extends RefCounted
## Halvar at his anvil, forging for real (jj, 2026-11-04: "fix the blacksmith so when he does go hit the anvil it
## actually hits the anvil and he holds a piece of material hes working on"). Meshy's Heavy Hammer Swing brought the
## hammer down 0.8 m below the anvil's face, beside it. While he forges, his body plays a calm idle and his arms are
## placed by two-bone IK every frame after the animation: the right raises the war hammer over his shoulder and drives
## its head down onto the anvil's face (a ring, sparks, a jolt of light, the hand rebounding), the left holds the
## Meshy tongs (assets/models/camp/props/tongs.glb) with the glowing bar (emissive only: no light of its own, the camp's
## frame time is a benchmark) on the anvil, turning it now and then; every
## few strikes he plunges it into the quench bucket in a hiss of steam, then back into the heat.
## Driven from Inter._process (the keeper's AnimationPlayer is advanced by hand first, so the IK goes on top).

const CYCLE := 1.15          # seconds per blow
const STRIKE := 0.62         # of the cycle: the head meets the anvil
const QUENCH_EVERY := 7      # blows between quenches
const QUENCH_T := 2.2
## the forge model's own points (forge.glb, metres, Godot axes; the stall is scaled ForestCamp.STALL_SCALE)
const ANVIL := Vector3(-0.16, 0.84, 1.07)
const BUCKET := Vector3(-1.09, 0.42, 0.99)
const TONGS := "res://assets/models/camp/props/tongs.glb"

static func setup(it: Inter, stall_at: Vector2, yaw: float, scale: float, w: World) -> void:
	var b := Basis(Vector3.UP, yaw)
	var base := Vector3(stall_at.x, w.height_at(stall_at.x, stall_at.y), stall_at.y)
	it.set_meta("forge", {"anvil": base + b * (ANVIL * scale), "bucket": base + b * (BUCKET * scale), "yaw": yaw,
		"t": 0.0, "blows": 0, "q": -1.0, "turn": 0.0})
	if it.anim != null:
		it.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ForestCamp.fist(it.model, "LeftHand", 1.0)       # round the tongs
	# the tongs with the bar, glowing hot
	if ResourceLoader.exists(TONGS):
		var tg: Node3D = (load(TONGS) as PackedScene).instantiate()
		DemonKitFx.heat_model(tg, 2.6, Color(1.0, 0.45, 0.12))
		w.props_root.add_child(tg)
		tg.top_level = true
		it.set_meta("tongs", tg)

static func forging(it: Inter) -> bool:
	return it.has_meta("forging") and float(it.get_meta("forging")) > 0.0

## Every frame (Inter._process): the animation advanced, then the arms on the anvil while he forges.
static func update(it: Inter, delta: float) -> void:
	if it.anim != null:
		it.anim.advance(delta)
	var tg = it.get_meta("tongs") if it.has_meta("tongs") else null
	var sk: Skeleton3D = it.model.find_child("Skeleton3D", true, false) if it.model != null else null
	if sk == null:
		return
	var f: Dictionary = it.get_meta("forge")
	var on := forging(it)
	if on:
		it.set_meta("forging", float(it.get_meta("forging")) - delta)
	if not on:
		var hm := _hammer(it, sk)
		if hm != null and hm.top_level:
			hm.top_level = false
			hm.transform = it.get_meta("hammer_rest")
		# between heats the tongs rest on the anvil's horn
		if is_instance_valid(tg):
			var rest: Vector3 = f["anvil"] + Vector3(0, 0.03, 0)
			(tg as Node3D).global_transform = Transform3D(Basis(Vector3.UP, float(f["yaw"]) + 1.1), rest)
			_heat(it, 0.6)
		return
	var anvil: Vector3 = f["anvil"]
	var yaw: float = f["yaw"]
	var fwd := Vector3(sin(yaw), 0, cos(yaw))       # the way he faces (out of the forge)
	var right := Vector3(-cos(yaw), 0, sin(yaw))    # his right hand's side
	var up := Vector3.UP
	f["t"] = float(f["t"]) + delta
	var qt: float = f["q"]
	var quench := qt >= 0.0
	if quench:
		f["q"] = qt + delta
		if float(f["q"]) > QUENCH_T:
			f["q"] = -1.0
			quench = false
	var u := fposmod(float(f["t"]) / CYCLE, 1.0)
	var prev_u: float = f.get("u", 0.0)
	f["u"] = u
	# --- the hammer: placed by hand (its handle in his fist, the face leading the swing): raised over his shoulder,
	# driven down until its face meets the anvil's, a rebound, raised again; his right arm reaches its grip
	var shoulder := _bone(sk, "RightArm")
	var h_hit := (fwd * 0.72 - right * 0.62 - up * 0.12).normalized()       # handle across toward the anvil
	var hit := Transform3D(_hammer_basis(h_hit, -up), anvil + up * HEAD_FACE - h_hit * HEAD_AT)
	var h_up := (up * 0.85 - fwd * 0.45 + right * 0.12).normalized()        # head up behind his shoulder
	var raised := Transform3D(_hammer_basis(h_up, fwd * 0.8 + up * 0.5), shoulder + up * 0.22 + right * 0.14 + fwd * 0.12)
	var rest_t := Transform3D(_hammer_basis((-up * 0.9 + fwd * 0.3).normalized(), fwd), shoulder - up * 0.52 + right * 0.1 + fwd * 0.12)
	var ht: Transform3D
	if quench:
		ht = rest_t                                                           # by his side while he quenches
	elif u < STRIKE - 0.16:
		ht = hit.interpolate_with(raised, smoothstep(0.0, 1.0, u / (STRIKE - 0.16)))
	elif u < STRIKE:
		var k := (u - (STRIKE - 0.16)) / 0.16
		ht = raised.interpolate_with(hit, k * k)                             # accelerating down
	else:
		var r := (u - STRIKE) / (1.0 - STRIKE)
		ht = hit.interpolate_with(raised, 0.12 * sin(PI * minf(r * 3.0, 1.0)) * (1.0 - r))   # the rebound
	var hh: Vector3 = ht.basis.y
	var hf: Vector3 = ht.basis.x
	# a fist round the handle (the keeper's fist_R shape key): the fingers out toward the face before they curl, the palm
	# in toward his middle, so the knuckle line runs along the handle
	var pn := hf.cross(hh)
	pn *= signf(pn.dot(-right) + 0.001)
	_reach(sk, "RightArm", "RightForeArm", "RightHand", ht.origin - hf * FIST_IN - pn * FIST_PALM, Vector3.ZERO, it.global_position + right * 0.7 - fwd * 0.2 - up * 0.1)
	_wrist(it, sk, "RightHand", hf, pn)
	var hm := _hammer(it, sk)
	if hm != null:
		hm.top_level = true
		hm.global_transform = ht
	# the strike: a ring, sparks off the anvil, a jolt of light, the bar a shade hotter
	if not quench and prev_u < STRIKE and u >= STRIKE:
		f["blows"] = int(f["blows"]) + 1
		var fx := it.game_fx()
		if fx != null:
			DemonKitFx.sparks(fx, anvil + up * 0.08, up, 6, 70.0, Vector2(1.0, 2.6), 0.28)
			Fx.sparks(fx, anvil + up * 0.08, Color(1.0, 0.7, 0.3))
			Fx.flash(fx, anvil + up * 0.2, Color(1.0, 0.6, 0.25), 2.2, 0.15, 3.0)
		var sfx: Node = it.get_tree().root.get_node_or_null("Sfx")
		if sfx != null:
			sfx.call("play_at", "anvil", anvil, -2.0, randf_range(0.96, 1.06))
		if int(f["blows"]) % QUENCH_EVERY == 0:
			f["q"] = 0.0
			f["quenched"] = false
		elif randf() < 0.25:
			f["turn"] = 1.0                       # he turns the bar over
	# --- the tongs: the bar on the anvil (turned now and then), or plunged into the bucket
	var bar := anvil + up * 0.04
	var tdir := (fwd * 0.55 + right * 0.83).normalized()      # reaching across from his left
	var turn: float = maxf(0.0, float(f["turn"]) - delta * 2.5)
	f["turn"] = turn
	var heat := 1.0
	if quench:
		var q := float(f["q"]) / QUENCH_T
		var dip := sin(PI * clampf(q * 1.2, 0.0, 1.0))
		bar = bar.lerp(f["bucket"] as Vector3, dip)
		tdir = tdir.slerp((fwd * 0.2 + right * 0.6 - up * 0.75).normalized(), dip)
		heat = 1.0 - 0.8 * smoothstep(0.35, 0.6, q) + 0.8 * smoothstep(0.75, 1.0, q)
		if q > 0.42 and not bool(f.get("quenched", false)):
			f["quenched"] = true
			_steam(it, f["bucket"])
	var grip := bar - tdir * 0.62 + up * 0.06
	var tf := (-up - tdir * tdir.dot(-up)).normalized()                  # the fingers round under the tongs' handles
	var tp := (right - tdir * tdir.dot(right) - tf * tf.dot(right)).normalized()  # the palm in toward his middle
	var hand := _reach(sk, "LeftArm", "LeftForeArm", "LeftHand", grip - tf * FIST_IN - tp * FIST_PALM, Vector3.ZERO, it.global_position - right * 0.6 - fwd * 0.3 + up * 0.7)
	_wrist(it, sk, "LeftHand", tf, tp)
	hand = grip
	if is_instance_valid(tg):
		var bb := Basis.looking_at(tdir, up).rotated(tdir, turn * PI)
		(tg as Node3D).global_transform = Transform3D(bb, hand + tdir * 0.35)
	_heat(it, heat)
	# his head down on the work
	var hd := sk.find_bone("Head")
	if hd >= 0:
		_aim_look(sk, hd, anvil)

static func _heat(it: Inter, k: float) -> void:
	var tg = it.get_meta("tongs") if it.has_meta("tongs") else null
	if is_instance_valid(tg):
		DemonKitFx.set_heat(tg, 2.6 * k * randf_range(0.9, 1.0))

## The hiss of the quench: steam boiling up out of the bucket.
static func _steam(it: Inter, at: Vector3) -> void:
	var fx := it.game_fx()
	if fx == null:
		return
	DemonKitFx.smoke(fx, at + Vector3(0, 0.15, 0), "steam", 1.1, 1.8, false, Color(1, 1, 1))
	ElementalFx._dust(fx, at + Vector3(0, 0.2, 0), Color(0.85, 0.85, 0.85), 0.6, 0.45, {"amount": 8, "life": 1.6,
		"explosive": 0.8, "shape": "sphere", "r": 0.15, "dir": Vector3.UP, "spread": 25.0, "vel": [0.6, 1.4], "gravity": 0.4,
		"damping": [0.8, 1.4], "scale": [0.6, 1.0], "grow": [0.6, 2.4]})
	var sfx: Node = it.get_tree().root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.call("play_at", "quench", at, -3.0, randf_range(0.95, 1.05))

# ---------------------------------------------------------------- the IK
static func _bone(sk: Skeleton3D, nm: String) -> Vector3:
	var i := sk.find_bone(nm)
	return sk.global_transform * sk.get_bone_global_pose(i).origin if i >= 0 else sk.global_position

## The war hammer (Models.item_model's "hammer": handle along its +y from the grip at its origin, head HEAD_AT up the
## handle, the striking face out along +x) as an orientation: handle along h, face toward f.
const HEAD_AT := 0.62
const FIST_IN := 0.1         # a fist's hollow from the wrist: out along the fingers
const FIST_PALM := 0.035     # and in from the palm
const HEAD_FACE := 0.135
static func _hammer_basis(h: Vector3, f: Vector3) -> Basis:
	var y := h.normalized()
	var x := (f - y * f.dot(y)).normalized()
	return Basis(x, y, x.cross(y))

## The hammer node he holds (ForestCamp.hold's item under the RightHand BoneAttachment3D); its place in the hand kept.
static func _hammer(it: Inter, sk: Skeleton3D) -> Node3D:
	if it.has_meta("hammer"):
		return it.get_meta("hammer")
	var hm: Node3D = null
	for ba in sk.get_children():
		if ba is BoneAttachment3D and (ba as BoneAttachment3D).bone_name == "RightHand" and ba.get_child_count() > 0:
			hm = ba.get_child(0) as Node3D
	it.set_meta("hammer", hm)
	if hm != null:
		it.set_meta("hammer_rest", hm.transform)
	return hm

## Two-bone IK: the upper and lower bones turned so the end (the hand, or what it holds at `tip` in the hand's frame)
## reaches `target`, the elbow bending toward `pole` (world points). The forearm, hand and what it holds turn as one, so
## the tip lands where it's sent. Solved in one pass from the pose as it is (the skeleton's global poses aren't brought
## up to date between set_bone_pose_rotation calls); returns where the hand ends up.
static func _reach(sk: Skeleton3D, up_n: String, lo_n: String, hand_n: String, target: Vector3, tip: Vector3, pole: Vector3) -> Vector3:
	var ui := sk.find_bone(up_n)
	var li := sk.find_bone(lo_n)
	var hi := sk.find_bone(hand_n)
	if ui < 0 or li < 0 or hi < 0:
		return target
	var inv := sk.global_transform.affine_inverse()
	var gu := sk.get_bone_global_pose(ui)
	var gl := sk.get_bone_global_pose(li)
	var gh := sk.get_bone_global_pose(hi)
	var S := gu.origin
	var E := gl.origin
	var H := gh.origin
	var T: Vector3 = gh * tip
	var t: Vector3 = inv * target
	var a := S.distance_to(E)
	var b := E.distance_to(T)
	var dd := S.distance_to(t)
	if a < 1e-4 or b < 1e-4 or dd < 1e-4:
		return sk.global_transform * H
	var d := clampf(dd, absf(a - b) * 1.01, (a + b) * 0.998)
	var dir := (t - S) / dd
	var pd: Vector3 = (inv * pole) - S
	pd = pd - dir * pd.dot(dir)
	pd = pd.normalized() if pd.length() > 1e-4 else Vector3.UP
	var ca := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var elbow := S + dir * a * ca + pd * a * sqrt(maxf(0.0, 1.0 - ca * ca))
	var q1 := Quaternion((E - S).normalized(), (elbow - S).normalized())
	var T1 := S + q1 * (T - S)
	var H1 := S + q1 * (H - S)
	var goal := S + dir * d
	var q2 := Quaternion((T1 - elbow).normalized(), (goal - elbow).normalized())
	var H2 := elbow + q2 * (H1 - elbow)
	var bu := Basis(q1) * gu.basis.orthonormalized()
	var bl := Basis(q2 * q1) * gl.basis.orthonormalized()
	var p := sk.get_bone_parent(ui)
	var pb: Basis = sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	sk.set_bone_pose_rotation(ui, (pb.inverse() * bu).get_rotation_quaternion())
	sk.set_bone_pose_rotation(li, (bu.inverse() * bl).get_rotation_quaternion())
	_lower = bl
	return sk.global_transform * H2

static var _lower := Basis()      # the forearm's new skeleton-space basis from the last _reach

## The hand turned so its fingers lie along `along` with its palm toward `palm` (world directions; the Meshy rigs have
## no finger bones, so an open hand laid along a handle reads as holding it). Call right after that arm's _reach.
static func _wrist(it: Inter, sk: Skeleton3D, hand_n: String, along: Vector3, palm: Vector3) -> void:
	var hi := sk.find_bone(hand_n)
	if hi < 0:
		return
	var rs := sk.global_transform.basis.orthonormalized()
	var key := "palm_" + hand_n
	if not it.has_meta(key):
		# which of the hand's own axes its palm is (found once from the clip's relaxed hand: palm in toward the thigh),
		# and the fingers' (down the hand, away from the forearm)
		var g := sk.get_bone_global_pose(hi)
		var b := g.basis.orthonormalized()
		var side: Vector3 = rs.inverse() * (it.model.global_transform.basis.orthonormalized() * Vector3(-1.0 if hand_n.begins_with("Left") else 1.0, 0, 0))
		var fing := Vector3.UP
		var pal := Vector3.RIGHT
		var best := -2.0
		for ax in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
			var dd: float = (b * (ax as Vector3)).dot(side)
			if dd > best:
				best = dd
				pal = ax
		it.set_meta(key, [fing, pal])
	var axes: Array = it.get_meta(key)
	var lf: Vector3 = axes[0]
	var lp: Vector3 = axes[1]
	var wf: Vector3 = rs.inverse() * along.normalized()
	var wp: Vector3 = rs.inverse() * palm
	wp = (wp - wf * wp.dot(wf)).normalized()
	var ml := Basis(lf, lp, lf.cross(lp))
	var mw := Basis(wf, wp, wf.cross(wp))
	var want := mw * ml.inverse()
	sk.set_bone_pose_rotation(hi, (_lower.inverse() * want).get_rotation_quaternion())

## Turns bone i (in place) so the point `now` it carries swings to `to` (world points).
static func _aim(sk: Skeleton3D, i: int, now: Vector3, to: Vector3) -> void:
	var inv := sk.global_transform.affine_inverse()
	var g := sk.get_bone_global_pose(i)
	var a := (inv * now) - g.origin
	var b := (inv * to) - g.origin
	if a.length() < 1e-5 or b.length() < 1e-5:
		return
	var q := Quaternion(a.normalized(), b.normalized())
	var ng := Basis(q) * g.basis.orthonormalized()
	var p := sk.get_bone_parent(i)
	var pb: Basis = sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	sk.set_bone_pose_rotation(i, (pb.inverse() * ng).get_rotation_quaternion())

## The head turned down toward a point (a little: it keeps the clip's own life).
static func _aim_look(sk: Skeleton3D, hd: int, at: Vector3) -> void:
	var g := sk.global_transform * sk.get_bone_global_pose(hd)
	var fwd_now: Vector3 = (g.basis * Vector3.BACK).normalized()
	var want := (at - g.origin).normalized()
	_aim(sk, hd, g.origin + fwd_now, g.origin + fwd_now.slerp(want, 0.55))

extends "res://game/systems/bodies/mocap_rig.gd"
## The Warlock's jungle void spirit on the shared mocap system (Warlock._build_spirit; the Wraith's float mode). Meshy's
## idle and float clips hold her almost still, so a slow procedural "weave" is laid over them whenever she isn't
## casting (Blaine, 2026-11-06: "he looks so static when he's just chilling"): the spine undulates in a wave from the
## hips to the head, the body sways, the head tilts and looks about, and the arms drift in turn as if stirring the void
## round her hands, the wrists rolling. Gliding, the arms trail out behind and the hands flutter. A cast or a hit fades
## it out at once (the clips and the procedural layer own those), death too.
## Rig frame: the body faces -z, its right is +x (so an arm swings forward by +x turns, the left arm out by -z turns).

var weave_w := 0.0
var _wst := {}
var _wt := -1.0

const WEAVE_HZ := 1.15        # the arms' slow stir (rad/s of the cycle)
const ARM_FWD := 0.16         # rad: how far each arm drifts forward and back
const ARM_OUT := 0.12         # rad: and out to the side
const ELBOW := 0.22           # rad: the forearm lifting as the hand comes round
const WRIST := 0.35           # rad: the wrist rolling
const SPINE := 0.035          # rad: the spine's wave
const SWAY := 0.05            # rad: the sideways sway
const HEAD_TILT := 0.09
const HEAD_LOOK := 0.22

func sync_pose(st: Dictionary) -> void:
	_wst = st
	super(st)

func _sway_hair(fwd_speed: float, side_speed: float, t: float, dt: float) -> void:
	super(fwd_speed, side_speed, t, dt)
	_weave()

## The weave over the clip (the bones were just set by the AnimationTree, so these turns don't pile up).
func _weave() -> void:
	var t: float = float(_wst.get("time", 0.0))
	var dt := clampf(t - _wt, 0.0, 0.1) if _wt >= 0.0 else 0.0
	if fixed_dt > 0.0:
		dt = fixed_dt
	_wt = t
	var acting := float(_wst.get("atk", -1.0)) >= 0.0 or float(_wst.get("hit", 0.0)) > 0.3 or float(_wst.get("dead", 0.0)) > 0.0
	var g := clampf(speed / 3.0, 0.0, 1.0)
	weave_w = lerpf(weave_w, 0.0 if acting else 1.0, 1.0 - exp(-dt * (16.0 if acting else 3.0)))
	if weave_w < 0.003:
		return
	var w := weave_w
	var X := Vector3.RIGHT
	var Y := Vector3.UP
	var Z := Vector3.BACK
	# the spine: a slow wave rising from the hips, the body swaying side to side
	var b := t * 1.4
	_add_turn("Spine", Quaternion(X, -SPINE * sin(b) * w) * Quaternion(Z, SWAY * sin(t * 0.8) * w))
	_add_turn("Spine01", Quaternion(X, -SPINE * sin(b - 0.7) * w))
	_add_turn("Spine02", Quaternion(X, -SPINE * sin(b - 1.4) * w) * Quaternion(Z, -SWAY * 0.6 * sin(t * 0.8 - 0.6) * w))
	# the head: tilts against the sway, looks about, nods with the wave
	_add_turn("Head", Quaternion(Y, HEAD_LOOK * (sin(t * 0.43) * 0.8 + sin(t * 1.07 + 2.0) * 0.2) * w * (1.0 - g * 0.6))
		* Quaternion(Z, HEAD_TILT * sin(t * 0.7 + 1.0) * w) * Quaternion(X, -0.05 * sin(b - 2.1) * w))
	# the arms take turns stirring: one comes forward and in, lifting its forearm, while the other eases back and out;
	# gliding, both trail out behind and the hands flutter
	var s := t * WEAVE_HZ
	for side in [1.0, -1.0]:
		var nm := "Right" if side > 0.0 else "Left"
		var ph: float = s + (0.0 if side > 0.0 else PI)
		var fwd := ARM_FWD * sin(ph) * (1.0 - g) - 0.32 * g
		var out := ARM_OUT * (0.6 + 0.4 * cos(ph)) * (1.0 - g * 0.3) + 0.2 * g
		_add_turn(nm + "Arm", Quaternion(X, fwd * w) * Quaternion(Z, side * out * w))
		_add_turn(nm + "ForeArm", Quaternion(X, ELBOW * (0.5 + 0.5 * sin(ph + 0.8)) * w * (1.0 - g)))
		var flutter := sin(t * 7.0 + side) * 0.18 * g
		_add_turn(nm + "Hand", Quaternion(Z, side * (WRIST * sin(ph * 2.0 + 0.4) + flutter) * w)
			* Quaternion(X, (0.15 * sin(ph + 1.6) + flutter) * w))

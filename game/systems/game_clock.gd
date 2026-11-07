class_name GameClock
extends RefCounted
## Game seconds: frame deltas summed, so effects and timers follow the game's time, not the wall clock (the same in
## play; very different when frames are rendered slowly, as in recordings).

static var _clk := 0.0
static var _clk_frame := -1

static func now() -> float:
	var f := Engine.get_process_frames()
	if f != _clk_frame:
		var tree := Engine.get_main_loop() as SceneTree
		var dt: float = tree.root.get_process_delta_time() if tree != null else 0.016
		_clk += dt * float(clampi(f - _clk_frame, 1, 10)) if _clk_frame >= 0 else 0.0
		_clk_frame = f
	return _clk

extends Node
## Kpi's stopwatch (scripts/kpi.gd): two of these, one processed first in the frame (process_priority very low) and
## one last, so the time between them is every node's _process in the frame (the scripts' main-thread cost, which
## Godot's TIME_PROCESS can't show: it includes drawing and waiting for the GPU). Physics the same way.
var first := true
static var t_proc := 0
static var t_phys := 0
static var proc_us := 0
static var phys_us := 0

func _process(_d: float) -> void:
	if first:
		t_proc = Time.get_ticks_usec()
	else:
		proc_us += Time.get_ticks_usec() - t_proc

func _physics_process(_d: float) -> void:
	if first:
		t_phys = Time.get_ticks_usec()
	else:
		phys_us += Time.get_ticks_usec() - t_phys

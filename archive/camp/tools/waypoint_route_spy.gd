extends "res://game/game.gd"
## Test-only transport boundary: exercise real waypoint dispatch without joining a public server.
var dispatched: Array = []
func _ready() -> void: pass
func _process(_delta: float) -> void: pass
func save_game() -> void: dispatched.append(["save"])
func start_join(ip: String, id := "") -> void: dispatched.append(["coop", ip, id])
func start_battlegrounds(addr: String, id: String, _cls := "") -> void: dispatched.append(["raid", addr, id])
func travel(act: int, zone: String, spawn: String, _at = null, _clear_tp := false) -> void:
 dispatched.append(["travel", act, zone, spawn])

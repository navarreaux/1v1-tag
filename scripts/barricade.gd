extends Node3D
## A barricade standing beside a 2 m gap. The Runner can drop it to block the gap.
## Once down, the Runner can vault it and the Hunter can break it.
## Local X runs along the gap; local Z is the direction you pass through it.

const Greybox := preload("res://scripts/greybox.gd")

enum State { UP, DOWN, BROKEN }

const GAP_WIDTH := 2.0
const COLOR := Color(0.78, 0.6, 0.3)

var state := State.UP
var _upright: Node3D
var _dropped: Node3D


func _ready() -> void:
	_upright = Greybox.box(self, Transform3D(Basis(), Vector3(0.9, 0.9, 0)), Vector3(0.12, 1.8, 1.1), COLOR)
	_dropped = Greybox.box(self, Transform3D(Basis(), Vector3(0, 0.45, 0)), Vector3(GAP_WIDTH, 0.9, 0.35), COLOR)
	set_state(State.UP)


func set_state(s: State) -> void:
	state = s
	_upright.visible = s == State.UP
	_upright.collision_layer = Greybox.WORLD_LAYER if s == State.UP else 0
	_dropped.visible = s == State.DOWN
	_dropped.collision_layer = Greybox.WORLD_LAYER if s == State.DOWN else 0


## True if `pos` is standing where the dropped barricade lands.
func in_zone(pos: Vector3) -> bool:
	var local := to_local(pos)
	return absf(local.x) < GAP_WIDTH * 0.55 and absf(local.z) < 0.75

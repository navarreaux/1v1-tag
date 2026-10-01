extends Node3D
## A trash can standing in the middle of a 3 m gap, with room to run past it on either side.
## The Runner can knock it over to block the gap: it falls and rests at 45 degrees against the
## structure on the far side, with trash spilled out. Once down, the Runner can hurdle it and the
## Hunter can kick it away for good.
## Local X runs along the gap; local Z is the direction you pass through it.

const Greybox := preload("res://scripts/greybox.gd")

enum State { UP, DOWN, BROKEN }

const GAP_WIDTH := 3.0
const CAN_COLOR := Color(0.15, 0.62, 0.5)
const RIM_COLOR := Color(0.08, 0.38, 0.3)
const BAG_COLOR := Color(0.12, 0.12, 0.14)
const PAPER_COLOR := Color(0.95, 0.93, 0.85)
const CAN_HEIGHT := 1.75
const CAN_RADIUS := 0.35

var state := State.UP
var _upright: Node3D
var _upright_body: StaticBody3D  # solid while the can stands, so you run around it
var _fallen: Node3D
var _blocker: Node3D  # invisible box that fills the gap while the can is down
var _fallen_xform: Transform3D
var _kick: Tween


func _ready() -> void:
	_upright = _can(self)
	_upright_body = StaticBody3D.new()
	_upright_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = CAN_RADIUS
	cyl.height = CAN_HEIGHT
	shape.shape = cyl
	shape.position.y = CAN_HEIGHT / 2.0
	_upright_body.add_child(shape)
	add_child(_upright_body)
	# Fallen: tipped 45 degrees toward -X, its bottom rim on the ground mid-gap and its lid
	# resting against whatever stands at the other end of the gap.
	_fallen = Node3D.new()
	add_child(_fallen)
	var tipped := _can(_fallen)
	tipped.transform = Transform3D(Basis(Vector3.BACK, PI / 4.0), Vector3(0.0, 0.25, 0))
	Greybox.round(_fallen, Transform3D(Basis(), Vector3(0.6, 0.22, 0.2)), Vector3(0.5, 0.44, 0.5), BAG_COLOR)
	Greybox.round(_fallen, Transform3D(Basis(), Vector3(1.1, 0.2, -0.2)), Vector3(0.45, 0.4, 0.45), BAG_COLOR)
	Greybox.round(_fallen, Transform3D(Basis(), Vector3(0.35, 0.08, -0.15)), Vector3(0.22, 0.16, 0.22), PAPER_COLOR)
	Greybox.round(_fallen, Transform3D(Basis(), Vector3(0.95, 0.08, 0.3)), Vector3(0.2, 0.14, 0.2), PAPER_COLOR)
	_fallen_xform = _fallen.transform
	_blocker = Greybox.box(self, Transform3D(Basis(), Vector3(0, 0.45, 0)), Vector3(GAP_WIDTH, 0.9, 0.35), CAN_COLOR)
	for c in _blocker.get_children():
		if c is MeshInstance3D:
			c.visible = false
	set_state(State.UP)


## A trash can with its base at the node's origin, standing along +Y.
func _can(parent: Node3D) -> Node3D:
	var can := Node3D.new()
	parent.add_child(can)
	var d := CAN_RADIUS * 2.0
	Greybox.round(can, Transform3D(Basis(), Vector3(0, (CAN_HEIGHT - 0.1) / 2.0, 0)), Vector3(d, CAN_HEIGHT - 0.1, d), CAN_COLOR, Greybox.Shape.ROD)
	for y in [0.35, 0.95]:
		Greybox.round(can, Transform3D(Basis(), Vector3(0, y, 0)), Vector3(d + 0.06, 0.07, d + 0.06), RIM_COLOR, Greybox.Shape.ROD)
	Greybox.round(can, Transform3D(Basis(), Vector3(0, CAN_HEIGHT - 0.05, 0)), Vector3(d + 0.1, 0.1, d + 0.1), RIM_COLOR, Greybox.Shape.ROD)
	Greybox.box(can, Transform3D(Basis(), Vector3(0, CAN_HEIGHT + 0.05, 0)), Vector3(0.3, 0.06, 0.08), RIM_COLOR, false)
	return can


func set_state(s: State) -> void:
	state = s
	if _kick:
		_kick.kill()
		_kick = null
	_fallen.transform = _fallen_xform
	_upright.visible = s == State.UP
	_upright_body.collision_layer = Greybox.WORLD_LAYER if s == State.UP else 0
	_fallen.visible = s == State.DOWN
	_blocker.collision_layer = Greybox.WORLD_LAYER if s == State.DOWN else 0


## Kicked away by a Hunter standing at `from`: the can and its trash fly off and vanish.
func kick_away(from: Vector3) -> void:
	set_state(State.BROKEN)
	_fallen.visible = true
	var away := signf(to_local(from).z)
	away = -1.0 if away >= 0.0 else 1.0
	var end := _fallen_xform.translated_local(Vector3(0, 0.6, away * 4.0)).rotated_local(Vector3.RIGHT, away * 2.5)
	_kick = create_tween()
	_kick.tween_property(_fallen, "transform", end, 0.45).set_ease(Tween.EASE_OUT)
	_kick.tween_callback(func(): _fallen.visible = false)


## True if `pos` is standing where the can lands when knocked over.
func in_zone(pos: Vector3) -> bool:
	var local := to_local(pos)
	return absf(local.x) < GAP_WIDTH * 0.55 and absf(local.z) < 0.75

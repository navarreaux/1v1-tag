extends Node3D
## A blocky, cartoony person built from boxes, with a simple procedural walk/run cycle.
## Feet are at y = 0 and the model faces -Z. Joints are pivots (Node3D) that `animate` rotates.
## A limb hangs straight down at rotation 0; a positive X rotation swings it forward.

const Greybox := preload("res://scripts/greybox.gd")

const HIP_HEIGHT := 0.92
const THIGH := 0.45
const SHIN := 0.45
const TORSO := 0.46
const SHOULDER_HEIGHT := 0.41  # above the hips
const UPPER_ARM := 0.3
const FOREARM := 0.3

## Shown when `pose()` gets these.
enum Pose { NORMAL, CROUCH, VAULT, STUNNED, DOWNED }

var hips: Node3D
var torso: Node3D
var head: Node3D
var legs: Array[Node3D] = []  # [left thigh, right thigh]
var knees: Array[Node3D] = []
var arms: Array[Node3D] = []  # [left shoulder, right shoulder]
var elbows: Array[Node3D] = []
## Something else (the Hunter's weapon arm) can be parented here in place of the right arm.
var right_shoulder: Node3D

var _parts := {}  # name -> Array of meshes, for recoloring
var _phase := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0


## Builds the person from an outfit, a Dictionary of colors and options:
##   skin, top, bottom (required); sleeve (forearms, default skin); shoes, shoe_trim; hair;
##   hat ("cap_back" or "police") with hat_color; hood, backpack, belt, badge, shades.
## `has_right_arm` is false for the Hunter, whose right arm is the weapon arm.
func build(o: Dictionary, has_right_arm := true) -> void:
	var skin: Color = o.skin
	var top: Color = o.top
	var bottom: Color = o.bottom
	var sleeve: Color = o.get("sleeve", skin)
	var shoes: Color = o.get("shoes", bottom.darkened(0.5))
	var black := Color(0.06, 0.06, 0.07)
	var gold := Color(1.0, 0.8, 0.2)

	hips = _pivot(self, Vector3(0, HIP_HEIGHT, 0))
	_part("bottom", hips, Vector3(0, 0.04, 0), Vector3(0.36, 0.16, 0.22), bottom)
	if o.has("belt"):
		_part("belt", hips, Vector3(0, 0.11, 0), Vector3(0.38, 0.06, 0.24), o.belt)
		_part("belt", hips, Vector3(0, 0.11, -0.125), Vector3(0.08, 0.05, 0.01), gold)
	torso = _pivot(hips, Vector3(0, 0.08, 0))
	_part("top", torso, Vector3(0, TORSO / 2.0, 0), Vector3(0.42, TORSO, 0.24), top)
	if o.get("hood", false):
		_part("top", torso, Vector3(0, TORSO, 0.09), Vector3(0.32, 0.1, 0.12), top)
	if o.has("backpack"):
		_part("backpack", torso, Vector3(0, TORSO * 0.5, 0.18), Vector3(0.32, 0.34, 0.13), o.backpack)
	if o.get("badge", false):
		_part("badge", torso, Vector3(-0.11, TORSO * 0.75, -0.125), Vector3(0.07, 0.08, 0.01), gold)

	# A big cartoon head.
	head = _pivot(torso, Vector3(0, TORSO + 0.02, 0))
	_part("skin", head, Vector3(0, 0.03, 0), Vector3(0.12, 0.08, 0.12), skin)  # neck
	_part("skin", head, Vector3(0, 0.2, 0), Vector3(0.3, 0.3, 0.28), skin)
	if o.get("shades", false):
		_part("eyes", head, Vector3(0, 0.22, -0.143), Vector3(0.25, 0.07, 0.01), black)
	else:
		for x in [-0.065, 0.065]:
			_part("eyes", head, Vector3(x, 0.22, -0.142), Vector3(0.07, 0.08, 0.01), Color.WHITE)
			_part("eyes", head, Vector3(x, 0.21, -0.148), Vector3(0.035, 0.05, 0.01), black)
	if o.has("hair"):
		_part("hair", head, Vector3(0, 0.34, 0.01), Vector3(0.31, 0.06, 0.29), o.hair)
		_part("hair", head, Vector3(0, 0.24, 0.135), Vector3(0.31, 0.22, 0.03), o.hair)
	match o.get("hat", ""):
		"cap_back":  # a cap worn backwards
			_part("hat", head, Vector3(0, 0.38, 0.0), Vector3(0.32, 0.08, 0.3), o.hat_color)
			_part("hat", head, Vector3(0, 0.35, 0.2), Vector3(0.26, 0.03, 0.14), o.hat_color.darkened(0.25))
		"police":
			_part("hat", head, Vector3(0, 0.41, 0), Vector3(0.34, 0.1, 0.32), o.hat_color)
			_part("hat", head, Vector3(0, 0.355, 0), Vector3(0.33, 0.04, 0.31), black)
			_part("hat", head, Vector3(0, 0.345, -0.19), Vector3(0.3, 0.03, 0.12), black)
			_part("hat", head, Vector3(0, 0.41, -0.165), Vector3(0.06, 0.06, 0.01), gold)

	for side in [-1.0, 1.0]:
		var thigh := _pivot(hips, Vector3(0.1 * side, 0, 0))
		_part("bottom", thigh, Vector3(0, -THIGH / 2.0, 0), Vector3(0.15, THIGH, 0.17), bottom)
		var knee := _pivot(thigh, Vector3(0, -THIGH, 0))
		_part("bottom", knee, Vector3(0, -SHIN / 2.0 + 0.02, 0), Vector3(0.13, SHIN - 0.04, 0.15), bottom)
		# Chunky shoes.
		_part("shoes", knee, Vector3(0, -SHIN + 0.06, -0.05), Vector3(0.16, 0.1, 0.28), shoes)
		if o.has("shoe_trim"):
			_part("shoes", knee, Vector3(0, -SHIN + 0.02, -0.05), Vector3(0.165, 0.035, 0.285), o.shoe_trim)
		legs.append(thigh)
		knees.append(knee)

		var shoulder := _pivot(torso, Vector3(0.28 * side, SHOULDER_HEIGHT, 0))
		arms.append(shoulder)
		if side > 0.0:
			right_shoulder = shoulder
			if not has_right_arm:
				elbows.append(null)
				continue
		_part("top", shoulder, Vector3(0, -UPPER_ARM / 2.0 + 0.04, 0), Vector3(0.12, UPPER_ARM, 0.13), top)
		var elbow := _pivot(shoulder, Vector3(0, -UPPER_ARM + 0.04, 0))
		_part("sleeve", elbow, Vector3(0, -(FOREARM - 0.08) / 2.0, 0), Vector3(0.11, FOREARM - 0.08, 0.12), sleeve)
		_part("skin", elbow, Vector3(0, -FOREARM + 0.03, 0), Vector3(0.1, 0.1, 0.11), skin)
		elbows.append(elbow)
	_last_pos = global_position


## Recolors the shirt and sleeves (the Runner's hoodie turns red when injured).
func set_top_color(c: Color) -> void:
	for m in _parts.get("top", []) + _parts.get("sleeve", []):
		m.material_override = Greybox.material(c)


func set_shadows(on: bool) -> void:
	for list in _parts.values():
		for m in list:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## How far through the current stride the legs are (radians). The Hunter's weapon arm swings with it.
func stride_phase() -> float:
	return _phase


## Moves every joint toward the pose for `pose`, adding a walk/run cycle from how fast we're moving.
## Works the same for your own body and the other computer's, because speed comes from position changes.
func animate(delta: float, pose: Pose) -> void:
	if delta <= 0.0:
		return
	var moved := global_position - _last_pos
	_last_pos = global_position
	moved.y = 0.0
	# Teleports (spawns, being pushed out of a barricade) shouldn't look like sprinting.
	var inst := moved.length() / delta if moved.length() < 1.0 else 0.0
	_speed = lerpf(_speed, inst, minf(1.0, delta * 10.0))

	var run := clampf((_speed - 2.4) / 1.6, 0.0, 1.0)  # 0 at walking pace, 1 at a sprint
	var moving := clampf(_speed / 1.0, 0.0, 1.0)
	var stride := lerpf(1.3, 2.7, run)  # meters per full step cycle
	_phase = fmod(_phase + _speed / stride * TAU * delta, TAU)
	var s := sin(_phase)

	# Targets: [hips y, hips pitch, torso pitch, head pitch, legs, knees, arms, elbows]
	var leg_amp := lerpf(0.45, 0.85, run) * moving
	var arm_amp := lerpf(0.35, 0.9, run) * moving
	var hip_y := HIP_HEIGHT + absf(cos(_phase)) * 0.05 * run * moving
	var torso_x := lerpf(-0.05, -0.3, run) * moving
	var head_x := -torso_x * 0.6
	var leg_x := [s * leg_amp, -s * leg_amp]
	# Knees bend most while the foot swings forward.
	var knee_x := [-maxf(0.0, cos(_phase)) * lerpf(0.5, 1.4, run) * moving - 0.05,
		-maxf(0.0, -cos(_phase)) * lerpf(0.5, 1.4, run) * moving - 0.05]
	var arm_x := [-s * arm_amp, s * arm_amp]
	var elbow_x := [lerpf(0.2, 1.3, run) + 0.1, lerpf(0.2, 1.3, run) + 0.1]
	var arm_z := [-0.08, 0.08]

	match pose:
		Pose.CROUCH:
			var a := 0.25 * moving
			hip_y = 0.55
			torso_x = -0.55
			head_x = 0.45
			leg_x = [1.3 + s * a, 1.3 - s * a]
			knee_x = [-1.9 + maxf(0.0, s) * a, -1.9 + maxf(0.0, -s) * a]
			arm_x = [0.5 - s * a, 0.5 + s * a]
			elbow_x = [1.0, 1.0]
		Pose.VAULT:
			hip_y = HIP_HEIGHT - 0.1
			torso_x = -0.6
			head_x = 0.4
			leg_x = [1.4, 0.6]
			knee_x = [-1.6, -0.6]
			arm_x = [1.4, 1.4]
			elbow_x = [0.3, 0.3]
		Pose.STUNNED:
			torso_x = 0.25
			head_x = 0.3
			leg_x = [0.2, -0.1]
			knee_x = [-0.2, -0.2]
			arm_x = [2.6, 2.6]
			elbow_x = [1.6, 1.6]
			arm_z = [-0.4, 0.4]
		Pose.DOWNED:
			# Lying on the ground face down, crawling.
			var c := sin(_phase) * 0.4 * moving
			hip_y = HIP_HEIGHT - 0.9  # centers the lying body over where we stand
			torso_x = 0.0
			head_x = -0.6
			leg_x = [0.1 + c, 0.1 - c]
			knee_x = [-0.3, -0.3]
			arm_x = [2.6 - c, 2.6 + c]
			elbow_x = [0.4, 0.4]

	var w := minf(1.0, delta * 14.0)
	var downed := pose == Pose.DOWNED
	rotation.x = lerp_angle(rotation.x, -PI / 2.0 if downed else 0.0, w)
	hips.position.y = lerpf(hips.position.y, hip_y, w)
	hips.position.z = lerpf(hips.position.z, 0.13 if downed else 0.0, w)  # lying down, local +Z is up
	torso.rotation.x = lerp_angle(torso.rotation.x, torso_x, w)
	head.rotation.x = lerp_angle(head.rotation.x, head_x, w)
	for i in 2:
		legs[i].rotation.x = lerp_angle(legs[i].rotation.x, leg_x[i], w)
		knees[i].rotation.x = lerp_angle(knees[i].rotation.x, knee_x[i], w)
		if elbows[i] == null:
			continue  # the Hunter's weapon arm animates itself
		arms[i].rotation.x = lerp_angle(arms[i].rotation.x, arm_x[i], w)
		arms[i].rotation.z = lerp_angle(arms[i].rotation.z, arm_z[i], w)
		elbows[i].rotation.x = lerp_angle(elbows[i].rotation.x, elbow_x[i], w)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


func _part(group: String, parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var m := Greybox.box(parent, Transform3D(Basis(), pos), size, color, false)
	if not _parts.has(group):
		_parts[group] = []
	_parts[group].append(m)

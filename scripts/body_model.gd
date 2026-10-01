extends Node3D
## A cartoony person built from rounded shapes, with a simple procedural walk/run cycle.
## Feet are at y = 0 and the model faces -Z. Joints are pivots (Node3D) that `animate` rotates.
## A limb hangs straight down at rotation 0; a positive X rotation swings it forward.

const Greybox := preload("res://scripts/greybox.gd")
const TUNING := preload("res://tuning.tres")

const HIP_HEIGHT := 0.92
const THIGH := 0.45
const SHIN := 0.45
const TORSO := 0.46
const SHOULDER_HEIGHT := 0.41  # above the hips
const UPPER_ARM := 0.3
const FOREARM := 0.3

## Shown when `pose()` gets these.
enum Pose { NORMAL, CROUCH, VAULT, HURDLE, STUNNED, DOWNED, KICK }

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
var _pose := Pose.NORMAL
var _pose_time := 0.0  # seconds in the current pose


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
	const BALL := Greybox.Shape.BALL
	const PILL := Greybox.Shape.PILL
	const ROD := Greybox.Shape.ROD

	hips = _pivot(self, Vector3(0, HIP_HEIGHT, 0))
	_part("bottom", hips, Vector3(0, 0.04, 0), Vector3(0.38, 0.22, 0.24), bottom, BALL)
	if o.has("belt"):
		_part("belt", hips, Vector3(0, 0.11, 0), Vector3(0.4, 0.06, 0.26), o.belt, ROD)
		_part("belt", hips, Vector3(0, 0.11, -0.13), Vector3(0.08, 0.05, 0.02), gold)
	torso = _pivot(hips, Vector3(0, 0.08, 0))
	_part("top", torso, Vector3(0, TORSO / 2.0, 0), Vector3(0.44, TORSO + 0.06, 0.27), top, PILL)
	if o.get("hood", false):
		_part("top", torso, Vector3(0, TORSO - 0.02, 0.1), Vector3(0.34, 0.14, 0.16), top, BALL)
	if o.has("backpack"):
		_part("backpack", torso, Vector3(0, TORSO * 0.5, 0.18), Vector3(0.32, 0.36, 0.16), o.backpack, PILL)
	if o.get("badge", false):
		_part("badge", torso, Vector3(-0.1, TORSO * 0.72, -0.135), Vector3(0.07, 0.08, 0.02), gold, BALL)

	# A big, round cartoon head.
	head = _pivot(torso, Vector3(0, TORSO + 0.02, 0))
	_part("skin", head, Vector3(0, 0.04, 0), Vector3(0.12, 0.1, 0.12), skin, ROD)  # neck
	_part("skin", head, Vector3(0, 0.21, 0), Vector3(0.34, 0.33, 0.32), skin, BALL)
	_part("skin", head, Vector3(0, 0.19, -0.16), Vector3(0.06, 0.06, 0.05), skin.darkened(0.08), BALL)  # nose
	if o.get("shades", false):
		_part("eyes", head, Vector3(0, 0.25, -0.15), Vector3(0.27, 0.07, 0.04), black, PILL)
	else:
		for x in [-0.07, 0.07]:
			_part("eyes", head, Vector3(x, 0.25, -0.145), Vector3(0.08, 0.1, 0.03), Color.WHITE, BALL)
			_part("eyes", head, Vector3(x, 0.24, -0.16), Vector3(0.04, 0.055, 0.02), black, BALL)
	if o.has("hair"):
		_part("hair", head, Vector3(0, 0.3, 0.03), Vector3(0.36, 0.22, 0.33), o.hair, BALL)
	match o.get("hat", ""):
		"cap_back":  # a cap worn backwards
			_part("hat", head, Vector3(0, 0.33, 0.0), Vector3(0.36, 0.2, 0.34), o.hat_color, BALL)
			_part("hat", head, Vector3(0, 0.33, 0.2), Vector3(0.24, 0.03, 0.16), o.hat_color.darkened(0.25), ROD)
		"police":
			_part("hat", head, Vector3(0, 0.36, 0), Vector3(0.36, 0.06, 0.34), black, ROD)
			_part("hat", head, Vector3(0, 0.43, 0), Vector3(0.42, 0.1, 0.4), o.hat_color, ROD)
			_part("hat", head, Vector3(0, 0.345, -0.18), Vector3(0.28, 0.03, 0.14), black, ROD)
			_part("hat", head, Vector3(0, 0.41, -0.2), Vector3(0.06, 0.06, 0.02), gold, BALL)

	for side in [-1.0, 1.0]:
		var thigh := _pivot(hips, Vector3(0.1 * side, 0, 0))
		_part("bottom", thigh, Vector3(0, -THIGH / 2.0, 0), Vector3(0.16, THIGH + 0.06, 0.17), bottom, PILL)
		var knee := _pivot(thigh, Vector3(0, -THIGH, 0))
		_part("bottom", knee, Vector3(0, -SHIN / 2.0 + 0.04, 0), Vector3(0.14, SHIN, 0.15), bottom, PILL)
		# Big, chunky sneakers.
		_part("shoes", knee, Vector3(0, -SHIN + 0.07, -0.05), Vector3(0.18, 0.14, 0.32), shoes, BALL)
		if o.has("shoe_trim"):
			_part("shoes", knee, Vector3(0, -SHIN + 0.03, -0.05), Vector3(0.19, 0.04, 0.33), o.shoe_trim, PILL)
		legs.append(thigh)
		knees.append(knee)

		var shoulder := _pivot(torso, Vector3(0.27 * side, SHOULDER_HEIGHT, 0))
		arms.append(shoulder)
		if side > 0.0:
			right_shoulder = shoulder
			if not has_right_arm:
				elbows.append(null)
				continue
		_part("top", shoulder, Vector3(0, -UPPER_ARM / 2.0 + 0.04, 0), Vector3(0.13, UPPER_ARM + 0.06, 0.13), top, PILL)
		var elbow := _pivot(shoulder, Vector3(0, -UPPER_ARM + 0.04, 0))
		_part("sleeve", elbow, Vector3(0, -(FOREARM - 0.06) / 2.0, 0), Vector3(0.12, FOREARM, 0.12), sleeve, PILL)
		_part("skin", elbow, Vector3(0, -FOREARM + 0.01, 0), Vector3(0.12, 0.12, 0.12), skin, BALL)  # hand
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

	if pose != _pose:
		_pose = pose
		_pose_time = 0.0
	_pose_time += delta
	var sway := 0.0
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
		Pose.HURDLE:
			# Hurdling a fallen trash can: lead leg out straight, back leg tucked up behind,
			# leaning forward with the arms swinging opposite.
			hip_y = HIP_HEIGHT
			torso_x = -0.45
			head_x = 0.3
			leg_x = [1.5, -0.5]
			knee_x = [-0.1, -1.7]
			arm_x = [-0.7, 1.3]
			elbow_x = [0.6, 0.4]
		Pose.STUNNED:
			# Staggering: reeling back, swaying, hands flailing at the head.
			var f := sin(_pose_time * 14.0)
			torso_x = 0.35
			head_x = 0.4 + f * 0.15
			leg_x = [0.25, -0.15]
			knee_x = [-0.3, -0.2]
			arm_x = [2.5 + f * 0.4, 2.5 - f * 0.4]
			elbow_x = [1.6, 1.6]
			arm_z = [-0.5, 0.5]
			sway = sin(_pose_time * 7.0) * 0.18
		Pose.KICK:
			# A slow wind-up (right leg drawn back, leaning in) the Runner can see coming,
			# then the kick itself at the very end.
			var kick_at: float = TUNING.hunter_break_time - 0.3
			var wind := clampf(_pose_time / kick_at, 0.0, 1.0)
			torso_x = -0.15 - 0.2 * wind
			head_x = 0.2
			arm_x = [-0.5 * wind, 0.6 * wind]
			arm_z = [-0.5 * wind, 0.5 * wind]
			elbow_x = [0.4, 0.4]
			leg_x = [0.1, -1.0 * wind]
			knee_x = [-0.2, -1.4 * wind]
			if _pose_time >= kick_at:
				torso_x = 0.25
				leg_x = [0.1, 1.6]
				knee_x = [-0.2, 0.0]
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
	var lean := 0.0
	if downed:
		lean = -PI / 2.0
	rotation.x = lerp_angle(rotation.x, lean, w)
	rotation.z = lerp_angle(rotation.z, sway, w)
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


## Adds one piece of the body: a box, or a rounded shape when `kind` is a Greybox.Shape.
func _part(group: String, parent: Node3D, pos: Vector3, size: Vector3, color: Color, kind := -1) -> void:
	var m: Node3D
	if kind < 0:
		m = Greybox.box(parent, Transform3D(Basis(), pos), size, color, false)
	else:
		m = Greybox.round(parent, Transform3D(Basis(), pos), size, color, kind)
	if not _parts.has(group):
		_parts[group] = []
	_parts[group].append(m)

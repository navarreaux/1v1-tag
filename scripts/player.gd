extends CharacterBody3D
## One player's body. The computer that owns it moves it and sends its position to the other computer.
## Hunters see in first person; Runners see in third person.

const Greybox := preload("res://scripts/greybox.gd")
const TUNING := preload("res://tuning.tres")

enum Role { RUNNER, HUNTER }

const GRAVITY := 20.0
const MOUSE_SENSITIVITY := 0.0025
const RADIUS := 0.35
const HEIGHT := 1.8
const HUNTER_COLOR := Color(0.85, 0.25, 0.2)
const RUNNER_COLOR := Color(0.25, 0.5, 0.9)

var game: Node  # set by game.gd before this is added
## Bots are run by the computer that owns them, like a human player, but get no camera.
var is_bot := false
## Which way the bot wants to go this frame (same meaning as WASD), set by bot.gd.
var bot_input := Vector2.ZERO
var role := Role.RUNNER

var frozen := true  # true during countdowns and between rounds
var downed := false
var stun := 0.0
var busy := 0.0  # seconds left in a vault or a barricade break
var vaulting := false
var cooldown := 0.0  # Hunter is slowed after a swing
var lunge := 0.0
var boost := 0.0  # Runner speed boost after being hit

var yaw := 0.0
var pitch := 0.0

var _body_mesh: MeshInstance3D
var _rig: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _on_busy_done := Callable()
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0


func _ready() -> void:
	collision_layer = Greybox.PLAYER_LAYER
	collision_mask = Greybox.WORLD_LAYER | Greybox.PLAYER_LAYER

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position.y = HEIGHT / 2.0
	add_child(shape)

	_body_mesh = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = RADIUS
	cm.height = HEIGHT
	_body_mesh.mesh = cm
	_body_mesh.position.y = HEIGHT / 2.0
	add_child(_body_mesh)
	# A little visor so you can tell which way the other player is facing.
	Greybox.box(_body_mesh, Transform3D(Basis(), Vector3(0, 0.5, -0.3)), Vector3(0.4, 0.15, 0.15), Color(0.1, 0.1, 0.1), false)

	if is_multiplayer_authority() and not is_bot:
		_rig = Node3D.new()
		_rig.top_level = true
		add_child(_rig)
		_spring = SpringArm3D.new()
		_spring.add_excluded_object(get_rid())
		_spring.collision_mask = Greybox.WORLD_LAYER
		_rig.add_child(_spring)
		_camera = Camera3D.new()
		_camera.fov = 85
		_spring.add_child(_camera)
		_camera.current = true

	set_role(role)


func set_role(r: Role) -> void:
	role = r
	downed = false
	stun = 0.0
	busy = 0.0
	cooldown = 0.0
	lunge = 0.0
	boost = 0.0
	_on_busy_done = Callable()
	_body_mesh.material_override = Greybox.material(HUNTER_COLOR if r == Role.HUNTER else RUNNER_COLOR)
	_body_mesh.rotation = Vector3.ZERO
	_body_mesh.position.y = HEIGHT / 2.0
	if _rig:
		var hunter := r == Role.HUNTER
		_spring.spring_length = 0.0 if hunter else 3.2
		_spring.position = Vector3.ZERO if hunter else Vector3(0.5, 0, 0)
		# Hunters are first person, so hide your own body.
		_body_mesh.visible = not hunter
		pitch = 0.0 if hunter else -0.25


func spawn_at(pos: Vector3, facing: float) -> void:
	global_position = pos
	rotation.y = facing
	yaw = facing
	velocity = Vector3.ZERO
	_net_pos = pos
	_net_yaw = facing


func is_local() -> bool:
	return is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if not is_local() or is_bot or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch -= event.relative.y * MOUSE_SENSITIVITY
		if role == Role.HUNTER:
			pitch = clampf(pitch, -1.4, 1.4)
		else:
			pitch = clampf(pitch, -1.1, 0.5)
	elif event.is_action_pressed("interact"):
		game.do_interact(self)
	elif event.is_action_pressed("attack"):
		try_attack()


func _process(delta: float) -> void:
	if _rig:
		var eye := 1.6 if role == Role.HUNTER else 1.5
		if downed:
			eye = 0.6
		_rig.global_position = global_position + Vector3(0, eye, 0)
		_rig.rotation = Vector3(pitch, yaw, 0)
	if not is_local():
		# Smoothly follow the position the other computer sent.
		var t := minf(1.0, delta * 15.0)
		if global_position.distance_to(_net_pos) > 4.0:
			global_position = _net_pos
		else:
			global_position = global_position.lerp(_net_pos, t)
		rotation.y = lerp_angle(rotation.y, _net_yaw, t)


func _physics_process(delta: float) -> void:
	if not is_local():
		return
	stun = maxf(0.0, stun - delta)
	cooldown = maxf(0.0, cooldown - delta)
	boost = maxf(0.0, boost - delta)
	if busy > 0.0:
		busy -= delta
		if busy <= 0.0 and _on_busy_done.is_valid():
			var done := _on_busy_done
			_on_busy_done = Callable()
			done.call()
	if lunge > 0.0:
		lunge -= delta
		if _check_hit():
			lunge = 0.0
			cooldown = TUNING.hunter_hit_cooldown
			game.request_hit.rpc_id(1)
		elif lunge <= 0.0:
			cooldown = TUNING.hunter_miss_cooldown

	if not vaulting:
		_move(delta)
	_net_state.rpc(global_position, rotation.y)


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var input := Vector2.ZERO
	if frozen or downed or stun > 0.0 or busy > 0.0:
		pass
	elif is_bot:
		input = bot_input
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	var speed := current_speed()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if role == Role.HUNTER:
		rotation.y = yaw
	elif dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * 12.0))
	move_and_slide()


func current_speed() -> float:
	var t = TUNING
	if role == Role.HUNTER:
		var s: float = t.hunter_speed
		if lunge > 0.0:
			s *= t.hunter_lunge_mult
		elif cooldown > 0.0:
			s *= t.hunter_cooldown_speed_mult
		return s
	var s: float = t.runner_speed
	if boost > 0.0:
		s *= t.runner_hit_boost_mult
	return s


func try_attack() -> void:
	if role != Role.HUNTER or frozen or stun > 0.0 or busy > 0.0 or cooldown > 0.0 or lunge > 0.0:
		return
	lunge = TUNING.hunter_lunge_time


## Hunter only: is the Runner close, in front of us, and not behind a wall?
func _check_hit() -> bool:
	var runner = game.get_runner()
	if runner == null or runner.downed:
		return false
	var to: Vector3 = runner.global_position - global_position
	to.y = 0.0
	if to.length() > TUNING.hunter_attack_range:
		return false
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	if to.length() > 0.5 and forward.dot(to.normalized()) < cos(deg_to_rad(40)):
		return false
	var eye := global_position + Vector3(0, 1.5, 0)
	var query := PhysicsRayQueryParameters3D.create(eye, runner.global_position + Vector3(0, 1.0, 0), Greybox.WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Jumps through a window (or over a dropped barricade) described by `xf`.
func vault(xf: Transform3D, duration: float) -> void:
	var n := xf.basis.z
	n.y = 0.0
	n = n.normalized()
	var side := signf((global_position - xf.origin).dot(n))
	if side == 0.0:
		side = 1.0
	var start := global_position
	var end := xf.origin - n * side * 1.0
	end.y = start.y
	vaulting = true
	busy = duration
	velocity = Vector3.ZERO
	var layer := collision_layer
	var mask := collision_mask
	collision_layer = 0
	collision_mask = 0
	if role == Role.RUNNER:
		rotation.y = atan2(n.x * side, n.z * side)
	var tween := create_tween()
	tween.tween_method(func(t: float): global_position = start.lerp(end, t) + Vector3.UP * sin(t * PI) * 0.6, 0.0, 1.0, duration)
	tween.finished.connect(func():
		collision_layer = layer
		collision_mask = mask
		vaulting = false)


## Stand still for `duration` seconds, then run `done` (used for breaking barricades).
func start_busy(duration: float, done: Callable) -> void:
	busy = duration
	_on_busy_done = done


func apply_stun(duration: float) -> void:
	stun = duration
	lunge = 0.0
	if not vaulting:
		busy = 0.0
		_on_busy_done = Callable()


## Called when a barricade drops on top of us: step out to whichever side we were on.
func push_out_of(barricade: Node3D) -> void:
	var local := barricade.to_local(global_position)
	local.z = 0.95 if local.z >= 0.0 else -0.95
	global_position = barricade.to_global(local)


func on_health_changed(health: int, hurt: bool) -> void:
	downed = health <= 0
	if downed:
		# Lie down.
		_body_mesh.rotation.x = PI / 2.0
		_body_mesh.position.y = RADIUS
	elif hurt and is_local():
		boost = TUNING.runner_hit_boost_time


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector3, facing: float) -> void:
	_net_pos = pos
	_net_yaw = facing

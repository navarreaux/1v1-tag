extends CharacterBody3D
## One player's body. The computer that owns it moves it and sends its state to the other computer.
## Hunters see in first person; Runners see over the shoulder in third person.

const Greybox := preload("res://scripts/greybox.gd")
const BodyModel := preload("res://scripts/body_model.gd")
const TUNING := preload("res://tuning.tres")

enum Role { RUNNER, HUNTER }
enum VaultKind { WINDOW, BARRICADE }

## Bits in the state flags sent to the other computer.
const FLAG_LUNGE := 1
const FLAG_WIPE := 2
const FLAG_RECOVER := 4
const FLAG_CROUCH := 8
const FLAG_SPRINT := 16
const FLAG_VAULT := 32
const FLAG_STUN := 64

const GRAVITY := 20.0
const RUNNER_CAMERA_DISTANCE := 3.0
const RUNNER_CAMERA_OFFSET := Vector3(0.7, 0.25, 0)  # right and up from the eye point
const MOUSE_SENSITIVITY := 0.0025
const RADIUS := 0.35
const HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const HUNTER_SCALE := 1.12
## Bright, cartoony outfits: the Runner is a teen in street clothes, the Hunter a police officer.
const RUNNER_OUTFIT := {
	"skin": Color(0.96, 0.76, 0.6), "top": Color(1.0, 0.55, 0.1), "bottom": Color(0.2, 0.4, 0.78),
	"sleeve": Color(1.0, 0.55, 0.1), "hood": true, "shoes": Color(0.95, 0.95, 0.95),
	"shoe_trim": Color(0.9, 0.15, 0.15), "hair": Color(0.5, 0.3, 0.15), "hat": "cap_back",
	"hat_color": Color(0.1, 0.75, 0.8), "backpack": Color(0.6, 0.25, 0.8),
}
const HUNTER_OUTFIT := {
	"skin": Color(0.9, 0.68, 0.52), "top": Color(0.15, 0.25, 0.55), "bottom": Color(0.08, 0.12, 0.3),
	"shoes": Color(0.06, 0.06, 0.07), "belt": Color(0.06, 0.06, 0.07), "badge": true, "shades": true,
	"hat": "police", "hat_color": Color(0.1, 0.16, 0.38),
}
const RUNNER_COLOR := Color(1.0, 0.55, 0.1)
const INJURED_COLOR := Color(0.85, 0.2, 0.25)  # the hoodie turns red when hurt
const SLEEVE_COLOR := Color(0.15, 0.25, 0.55)
const SKIN_COLOR := Color(0.9, 0.68, 0.52)
const BATON_COLOR := Color(0.08, 0.08, 0.09)

var game: Node  # set by game.gd before this is added
## Bots are run by the computer that owns them, like a human player, but get no camera.
var is_bot := false
## What the bot wants this frame, set by bot.gd (same meaning as the keys).
var bot_input := Vector2.ZERO
var bot_sprint := false
var bot_attack_held := false
var role := Role.RUNNER

var frozen := true  # true during countdowns and between rounds
var downed := false
var injured := false
var stun := 0.0
var busy := 0.0  # seconds left in a vault or a barricade break
var vaulting := false
var boost := 0.0  # Runner speed boost after being hit

## Runner movement state.
var sprinting := false
var crouching := false
var run_up := 0.0  # meters sprinted at full speed (for fast vaults)
var revault_run_up := 0.0  # the same, but only reset by vaulting (for re-vaulting the same thing)
var last_vault := ""  # which window or barricade we vaulted last, like "w3" or "b5"
var dropped_barricade := -1  # the barricade we just dropped, and how long until we may vault it
var drop_lock := 0.0

## Hunter attack state.
var lunge_time := -1.0  # seconds into the current lunge, or -1 when not lunging
var cooldown := 0.0  # Hunter is slowed after a swing
var wiping := false  # the cooldown came from a hit (the longer one) rather than a miss

## Hunter chase state (only tracked on the Hunter's own computer).
var in_chase := false
var chase_time := 0.0
var bloodlust := 0
var _unseen_time := 0.0

var yaw := 0.0
var pitch := 0.0

var _shape: CollisionShape3D
var _model: BodyModel
var _rig: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _arm: Node3D  # the Hunter's swinging arm (on the camera for yourself, on the body for others)
var _red_stain: SpotLight3D
var _on_busy_done := Callable()
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_flags := 0
var _remote_lunge := 0.0


func _ready() -> void:
	collision_layer = Greybox.PLAYER_LAYER
	collision_mask = Greybox.WORLD_LAYER | Greybox.PLAYER_LAYER

	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	_shape.shape = capsule
	_shape.position.y = HEIGHT / 2.0
	add_child(_shape)

	if is_human_local():
		_rig = Node3D.new()
		_rig.top_level = true
		add_child(_rig)
		_spring = SpringArm3D.new()
		_spring.add_excluded_object(get_rid())
		_spring.collision_mask = Greybox.WORLD_LAYER
		_spring.margin = 0.2
		_rig.add_child(_spring)
		_camera = Camera3D.new()
		# Dead by Daylight's 87 is a horizontal field of view; Godot measures vertically by default.
		_camera.keep_aspect = Camera3D.KEEP_WIDTH
		_camera.fov = 87
		_spring.add_child(_camera)
		_camera.current = true

	set_role(role)


## True for the player sitting at this computer (not a bot, not the other computer's player).
func is_human_local() -> bool:
	return is_multiplayer_authority() and not is_bot


func is_local() -> bool:
	return is_multiplayer_authority()


func set_role(r: Role) -> void:
	role = r
	downed = false
	injured = false
	stun = 0.0
	busy = 0.0
	boost = 0.0
	lunge_time = -1.0
	cooldown = 0.0
	wiping = false
	sprinting = false
	crouching = false
	run_up = 0.0
	revault_run_up = 0.0
	last_vault = ""
	dropped_barricade = -1
	drop_lock = 0.0
	_end_chase()
	_on_busy_done = Callable()
	_build_model()
	_build_arm()
	_build_red_stain()
	if _rig:
		var hunter := r == Role.HUNTER
		# Runner camera: behind and over the right shoulder, a bit above head height, like Dead by Daylight.
		_spring.spring_length = 0.0 if hunter else RUNNER_CAMERA_DISTANCE
		_spring.position = Vector3.ZERO if hunter else RUNNER_CAMERA_OFFSET
		pitch = 0.0 if hunter else -0.25


func spawn_at(pos: Vector3, facing: float) -> void:
	global_position = pos
	rotation.y = facing
	yaw = facing
	velocity = Vector3.ZERO
	_net_pos = pos
	_net_yaw = facing


## A cartoony person. Hunters are bigger, and their right arm is the weapon arm (see _build_arm).
func _build_model() -> void:
	if _model:
		_model.queue_free()
	_model = BodyModel.new()
	add_child(_model)
	if role == Role.HUNTER:
		_model.build(HUNTER_OUTFIT, false)
		_model.scale = Vector3.ONE * HUNTER_SCALE
	else:
		_model.build(RUNNER_OUTFIT)
	# Hunters are first person, so you don't see your own body (its shadow still shows).
	if role == Role.HUNTER and is_human_local():
		for m in _model.find_children("*", "MeshInstance3D", true, false):
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_update_color()


func _update_color() -> void:
	if role == Role.RUNNER:
		_model.set_top_color(INJURED_COLOR if injured else RUNNER_COLOR)


## The Hunter's arm swinging a police baton. It's a pivot at the shoulder; poses rotate it.
func _build_arm() -> void:
	if _arm:
		_arm.queue_free()
		_arm = null
	if role != Role.HUNTER:
		return
	_arm = Node3D.new()
	# Pieces lie along -Z (rounded shapes are built along Y, so tip them forward).
	var along := Basis(Vector3.RIGHT, PI / 2.0)
	Greybox.round(_arm, Transform3D(along, Vector3(0, 0, -0.1)), Vector3(0.15, 0.24, 0.15), SLEEVE_COLOR, Greybox.Shape.PILL)
	Greybox.round(_arm, Transform3D(along, Vector3(0, 0, -0.34)), Vector3(0.12, 0.32, 0.12), SKIN_COLOR, Greybox.Shape.PILL)
	Greybox.round(_arm, Transform3D(along, Vector3(0, 0, -0.53)), Vector3(0.14, 0.13, 0.14), SKIN_COLOR, Greybox.Shape.BALL)
	Greybox.round(_arm, Transform3D(along, Vector3(0, 0, -0.85)), Vector3(0.07, 0.7, 0.07), BATON_COLOR, Greybox.Shape.ROD)
	Greybox.round(_arm, Transform3D(along, Vector3(0, 0, -1.2)), Vector3(0.09, 0.05, 0.09), BATON_COLOR, Greybox.Shape.ROD)
	if _camera:
		_camera.add_child(_arm)
		_arm.position = Vector3(0.24, -0.19, -0.15)
	else:
		_model.right_shoulder.add_child(_arm)
	for m in _arm.get_children():
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _camera else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if _camera:
			# Right in front of the camera an ink outline would look huge, so skip it.
			m.material_override = m.material_override.duplicate()
			m.material_override.next_pass = null


## The red light the Hunter casts in front of them, so the Runner can tell where they're looking.
## The Hunter never sees their own.
func _build_red_stain() -> void:
	if _red_stain:
		_red_stain.queue_free()
		_red_stain = null
	if role != Role.HUNTER or is_human_local():
		return
	_red_stain = SpotLight3D.new()
	_red_stain.light_color = Color(1, 0.05, 0.05)
	_red_stain.light_energy = 6.0
	_red_stain.spot_range = 9.0
	_red_stain.spot_angle = 14.0
	_red_stain.position = Vector3(0, 1.7, -0.3)
	_red_stain.rotation.x = deg_to_rad(-38)
	add_child(_red_stain)


func _unhandled_input(event: InputEvent) -> void:
	if not is_human_local() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch -= event.relative.y * MOUSE_SENSITIVITY
		if role == Role.HUNTER:
			pitch = clampf(pitch, -1.4, 1.4)
		else:
			pitch = clampf(pitch, -1.1, 0.6)
	elif event.is_action_pressed("interact"):
		game.do_interact(self)
	elif event.is_action_pressed("attack"):
		try_attack()


func _process(delta: float) -> void:
	if _rig:
		var eye := 1.85 if role == Role.HUNTER else 1.45
		if downed:
			eye = 0.6
		elif crouching:
			eye = 0.95
		_rig.global_position = global_position + Vector3(0, eye, 0)
		_rig.rotation = Vector3(pitch, yaw, 0)
	if not is_local():
		# Smoothly follow what the other computer sent.
		var t := minf(1.0, delta * 15.0)
		if global_position.distance_to(_net_pos) > 4.0:
			global_position = _net_pos
		else:
			global_position = global_position.lerp(_net_pos, t)
		rotation.y = lerp_angle(rotation.y, _net_yaw, t)
		crouching = _net_flags & FLAG_CROUCH != 0
		sprinting = _net_flags & FLAG_SPRINT != 0
		_remote_lunge = _remote_lunge + delta if _net_flags & FLAG_LUNGE else 0.0
	_model.animate(delta, _pose())
	_animate_arm(delta)


func _pose() -> BodyModel.Pose:
	var local := is_local()
	if downed:
		return BodyModel.Pose.DOWNED
	if (vaulting if local else _net_flags & FLAG_VAULT != 0):
		return BodyModel.Pose.VAULT
	if (stun > 0.0 if local else _net_flags & FLAG_STUN != 0):
		return BodyModel.Pose.STUNNED
	if crouching:
		return BodyModel.Pose.CROUCH
	return BodyModel.Pose.NORMAL


func _physics_process(delta: float) -> void:
	if not is_local():
		return
	stun = maxf(0.0, stun - delta)
	cooldown = maxf(0.0, cooldown - delta)
	boost = maxf(0.0, boost - delta)
	drop_lock = maxf(0.0, drop_lock - delta)
	if busy > 0.0:
		busy -= delta
		if busy <= 0.0 and _on_busy_done.is_valid():
			var done := _on_busy_done
			_on_busy_done = Callable()
			done.call()
	if role == Role.HUNTER:
		_update_lunge(delta)
		_update_chase(delta)

	if not vaulting:
		_move(delta)
	_net_state.rpc(global_position, rotation.y, _flags())


func _flags() -> int:
	var f := 0
	if lunge_time >= 0.0:
		f |= FLAG_LUNGE
	if cooldown > 0.0:
		f |= FLAG_WIPE if wiping else FLAG_RECOVER
	if crouching:
		f |= FLAG_CROUCH
	if sprinting:
		f |= FLAG_SPRINT
	if vaulting:
		f |= FLAG_VAULT
	if stun > 0.0:
		f |= FLAG_STUN
	return f


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var input := Vector2.ZERO
	var want_sprint := false
	var want_crouch := false
	if frozen or downed or stun > 0.0 or busy > 0.0 or (role == Role.HUNTER and game.hunter_held()):
		pass
	elif is_bot:
		input = bot_input
		want_sprint = bot_sprint
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		want_sprint = Input.is_action_pressed("sprint")
		want_crouch = Input.is_action_pressed("crouch")
	if role == Role.RUNNER:
		_set_crouch(want_crouch and not downed)
		sprinting = want_sprint and not crouching and input.length() > 0.1
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	var speed := current_speed()
	dir = _wall_slide(dir, speed * delta)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if role == Role.HUNTER:
		rotation.y = yaw
	elif dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * 12.0))
	move_and_slide()
	var flat_speed := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if sprinting and flat_speed >= TUNING.runner_sprint_speed * 0.9:
		run_up += flat_speed * delta
		revault_run_up += flat_speed * delta
	else:
		run_up = 0.0
		revault_run_up = 0.0


## Like Dead by Daylight: running at a wall at a shallow angle slides you along it at full speed
## (plain physics would slow you down by how much you push into it). Head-on, you still stop.
func _wall_slide(dir: Vector3, step: float) -> Vector3:
	if dir.length() < 0.1 or not is_on_floor():
		return dir
	dir = dir.normalized() * minf(dir.length(), 1.0)
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, dir.normalized() * (step + 0.05), hit):
		return dir
	if not hit.get_collider() is StaticBody3D:
		return dir  # only walls, not the other player
	var n := hit.get_normal()
	n.y = 0.0
	if n.length() < 0.5:
		return dir
	n = n.normalized()
	var into := -dir.normalized().dot(n)  # 1 = straight into the wall
	if into <= 0.0 or into > sin(deg_to_rad(TUNING.wall_slide_max_angle)):
		return dir
	return (dir - n * dir.dot(n)).normalized() * dir.length()


func _set_crouch(on: bool) -> void:
	if on == crouching:
		return
	crouching = on
	var h := CROUCH_HEIGHT if on else HEIGHT
	_shape.shape.height = h
	_shape.position.y = h / 2.0


func current_speed() -> float:
	var t = TUNING
	if role == Role.HUNTER:
		var s: float = t.hunter_speed
		if bloodlust > 0:
			s += t.bloodlust_tier_speed[bloodlust - 1]
		if lunge_time >= 0.0:
			s *= t.hunter_lunge_mult
		elif cooldown > 0.0:
			s *= t.hunter_cooldown_speed_mult
		return s
	var s: float = t.runner_walk_speed
	if crouching:
		s = t.runner_crouch_speed
	elif sprinting:
		s = t.runner_sprint_speed
	if boost > 0.0:
		s *= t.runner_hit_boost_mult
	return s


# --- Hunter: attacking ---------------------------------------------------

func try_attack() -> void:
	if role != Role.HUNTER or frozen or game.hunter_held() or stun > 0.0 or busy > 0.0 or cooldown > 0.0 or lunge_time >= 0.0:
		return
	lunge_time = 0.0


func _attack_held() -> bool:
	if is_bot:
		return bot_attack_held
	return Input.is_action_pressed("attack") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _update_lunge(delta: float) -> void:
	if lunge_time < 0.0:
		return
	lunge_time += delta
	if _check_hit():
		lunge_time = -1.0
		cooldown = TUNING.hunter_hit_cooldown
		wiping = true
		game.request_hit.rpc_id(1)
		return
	var keep_going: bool = lunge_time < TUNING.hunter_lunge_min or (_attack_held() and lunge_time < TUNING.hunter_lunge_max)
	if not keep_going:
		lunge_time = -1.0
		cooldown = TUNING.hunter_miss_cooldown
		wiping = false


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
	return _line_of_sight(runner, 1.0)


func _line_of_sight(target: Node3D, target_height: float) -> bool:
	var eye := global_position + Vector3(0, 1.6, 0)
	var query := PhysicsRayQueryParameters3D.create(eye, target.global_position + Vector3(0, target_height, 0), Greybox.WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Moves the arm toward the pose for what the Hunter is doing.
func _animate_arm(delta: float) -> void:
	if _arm == null:
		return
	var lunging: bool
	var lunge_t: float
	var wipe: bool
	var recover: bool
	if is_local():
		lunging = lunge_time >= 0.0
		lunge_t = lunge_time
		wipe = cooldown > 0.0 and wiping
		recover = cooldown > 0.0 and not wiping
	else:
		lunging = _net_flags & FLAG_LUNGE != 0
		lunge_t = _remote_lunge
		wipe = _net_flags & FLAG_WIPE != 0
		recover = _net_flags & FLAG_RECOVER != 0
	# Rotation (pitch, yaw) in radians. Positive pitch raises the arm.
	# In first person the arm sits in front of the camera; on the body it hangs from the shoulder.
	var fp := _camera != null
	var target := Vector2(-0.35, 0.15) if fp else Vector2(-1.2 - sin(_model.stride_phase()) * 0.35, 0.1)
	var speed := 10.0
	if downed:
		pass
	elif lunging:
		# Raise, then slash down and across as the lunge goes on.
		var k := clampf(lunge_t / TUNING.hunter_lunge_min, 0.0, 1.0)
		if fp:
			target = Vector2(lerpf(0.9, -0.5, k), lerpf(0.5, -0.6, k))
		else:
			target = Vector2(lerpf(1.8, -0.6, k), lerpf(0.3, -0.5, k))
		speed = 30.0
	elif wipe:
		target = Vector2(-0.9, -0.7) if fp else Vector2(-0.4, -1.0)  # tapping the baton after a hit
		speed = 6.0
	elif recover:
		target = Vector2(-1.0, 0.0) if fp else Vector2(-1.5, -0.2)  # swung through and drooping
		speed = 8.0
	var w := minf(1.0, delta * speed)
	_arm.rotation.x = lerpf(_arm.rotation.x, target.x, w)
	_arm.rotation.y = lerpf(_arm.rotation.y, target.y, w)
	if fp:
		_arm.position.z = lerpf(_arm.position.z, -0.25 if lunging else -0.15, w)


# --- Hunter: chase and bloodlust -----------------------------------------

func _update_chase(delta: float) -> void:
	var runner = game.get_runner()
	if runner == null or not game.is_chasing() or runner.downed:
		_end_chase()
		return
	var to: Vector3 = runner.global_position - global_position
	to.y = 0.0
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var sees: bool = to.length() < TUNING.chase_sight_range \
		and (to.length() < 3.0 or forward.dot(to.normalized()) > cos(deg_to_rad(55))) \
		and _line_of_sight(runner, 1.2)
	if sees:
		in_chase = true
		_unseen_time = 0.0
	elif in_chase:
		_unseen_time += delta
		if _unseen_time > TUNING.chase_lose_time:
			_end_chase()
	if not in_chase:
		return
	chase_time += delta
	bloodlust = 0
	var tiers = TUNING.bloodlust_tier_times
	for i in tiers.size():
		if chase_time >= tiers[i]:
			bloodlust = i + 1


func _end_chase() -> void:
	in_chase = false
	reset_bloodlust()


## Bloodlust is lost when the Hunter hits, breaks a barricade, gets stunned, or loses the chase.
func reset_bloodlust() -> void:
	chase_time = 0.0
	bloodlust = 0
	_unseen_time = 0.0


# --- Vaulting, breaking, stuns -------------------------------------------

## Jumps through a window or over a dropped barricade at `xf`.
## Runners vault fast, medium or slow depending on how they come in; Hunters only vault windows, slowly.
## `key` names what is being vaulted ("w3" = window 3, "b5" = barricade 5).
func vault(xf: Transform3D, kind: VaultKind, key := "") -> void:
	var n := xf.basis.z
	n.y = 0.0
	n = n.normalized()
	var side := signf((global_position - xf.origin).dot(n))
	if side == 0.0:
		side = 1.0
	var through := -n * side  # direction we're vaulting

	var speed_name := "slow"
	var duration: float = TUNING.hunter_window_vault_time
	if role == Role.RUNNER:
		# Fast vaults need you to be running straight at the opening.
		var moving := get_real_velocity()
		moving.y = 0.0
		var straight := moving.length() > 0.5 and moving.normalized().dot(through) >= cos(deg_to_rad(TUNING.fast_vault_max_angle))
		# Going back over the thing you just vaulted needs a longer fresh run-up to be fast.
		var again := key != "" and key == last_vault
		var enough_run: bool = revault_run_up >= TUNING.fast_vault_runup_meters * TUNING.revault_runup_mult if again \
			else run_up >= TUNING.fast_vault_runup_meters
		if kind == VaultKind.WINDOW:
			if sprinting and enough_run and straight:
				speed_name = "fast"
			elif sprinting:
				speed_name = "medium"
			duration = {"fast": TUNING.window_vault_fast, "medium": TUNING.window_vault_medium, "slow": TUNING.window_vault_slow}[speed_name]
		else:
			var fast := sprinting and (enough_run or not again)
			speed_name = "fast" if fast else "slow"
			duration = TUNING.barricade_vault_fast if fast else TUNING.barricade_vault_slow
		last_vault = key
		revault_run_up = 0.0
		rotation.y = atan2(-through.x, -through.z)
		if speed_name != "slow":
			# Rushed vaults are loud: the Hunter gets a noise alert. Slow vaults are silent.
			game.make_noise.rpc(xf.origin)
		# A fast vault keeps your momentum; anything slower makes you build a run-up again.
		if speed_name != "fast":
			run_up = 0.0

	var start := global_position
	var end := xf.origin + through * 1.0
	end.y = start.y
	vaulting = true
	busy = duration
	velocity = Vector3.ZERO
	var layer := collision_layer
	var mask := collision_mask
	collision_layer = 0
	collision_mask = 0
	var hop := 0.6 if speed_name != "fast" else 0.4
	var tween := create_tween()
	tween.tween_method(func(t: float): global_position = start.lerp(end, t) + Vector3.UP * sin(t * PI) * hop, 0.0, 1.0, duration)
	tween.finished.connect(func():
		collision_layer = layer
		collision_mask = mask
		vaulting = false)
	if is_human_local():
		game.hud.flash("%s vault" % speed_name.capitalize())


## Stand still for `duration` seconds, then run `done` (used for breaking barricades).
func start_busy(duration: float, done: Callable) -> void:
	busy = duration
	_on_busy_done = done


func apply_stun(duration: float) -> void:
	stun = duration
	lunge_time = -1.0
	reset_bloodlust()
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
	injured = health == 1
	_update_color()
	if downed:
		_set_crouch(false)  # the body model lies down by itself
	elif hurt and is_local():
		boost = TUNING.runner_hit_boost_time


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector3, facing: float, flags: int) -> void:
	_net_pos = pos
	_net_yaw = facing
	_net_flags = flags

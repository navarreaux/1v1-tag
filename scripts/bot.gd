extends Node
## A computer-controlled opponent for playing alone. Add it as a child of a player body.
## As Hunter it chases and swings, and at a dropped barricade it works out whether breaking it
## or running around is quicker.
## As Runner it runs to the far side of nearby windows and barricades, drops barricades
## on the Hunter, and vaults when its path goes through a window.

const Role := preload("res://scripts/player.gd").Role
const TUNING := preload("res://tuning.tres")
const Barricade := preload("res://scripts/barricade.gd")

const REPATH_TIME := 0.25
const STUCK_TIME := 1.0
## After vaulting, the bot Hunter walks around for a while instead of vaulting back and forth.
const HUNTER_VAULT_REST := 6.0
## How long the Hunter sticks with a choice to break or go around, so it doesn't dither.
const DECIDE_TIME := 1.0

var game: Node
var body: CharacterBody3D

var _agent: NavigationAgent3D
var _repath := 0.0
var _goal := Vector3.ZERO
var _goal_time := 0.0
var _stuck_timer := 0.0
var _stuck_from := Vector3.ZERO
var _think_delay := 0.0
var _vault_rest := 0.0
var _go_around := false
var _decide := 0.0
## True while the Hunter stands still to swing over something (a dropped barricade, a window sill).
var _aiming := false


func _ready() -> void:
	body = get_parent()
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.6
	_agent.radius = 0.4
	_agent.navigation_layers = 1 | 2  # 1 = ground, 2 = window shortcuts
	body.add_child.call_deferred(_agent)


func _physics_process(delta: float) -> void:
	body.bot_input = Vector2.ZERO
	body.bot_attack_held = false
	_aiming = false
	# Bot Runners always sprint (Shift held) when moving.
	body.bot_sprint = body.role == Role.RUNNER
	if not game.is_chasing() or body.frozen or body.downed or not _agent.is_inside_tree():
		_goal_time = 0.0
		return
	var foe = null
	for p in game.players.values():
		if p != body:
			foe = p
	if foe == null:
		return
	_think_delay -= delta
	_repath -= delta
	if body.vaulting and body.role == Role.HUNTER:
		_vault_rest = HUNTER_VAULT_REST
	_vault_rest -= delta
	var layers := 1 if _vault_rest > 0.0 else 1 | 2
	if _agent.navigation_layers != layers:
		_agent.navigation_layers = layers
		_repath = 0.0
	if body.role == Role.HUNTER:
		_hunt(delta, foe)
	else:
		_go_around = false
		_flee(delta, foe)
	var map: RID = game.arena.nav_blocked_map if _go_around else body.get_world_3d().navigation_map
	if _agent.get_navigation_map() != map:
		_agent.set_navigation_map(map)
		_agent.target_position = _goal
	_follow_path(delta)


func _hunt(delta: float, runner) -> void:
	if runner.downed:
		return
	_decide -= delta
	if _decide <= 0.0:
		_decide = DECIDE_TIME
		_go_around = _quicker_around(runner.global_position)
	_set_goal(runner.global_position)
	# Right at a dropped barricade with the Runner across it, and breaking is quicker: break it.
	if not _go_around and body.busy <= 0.0 and game.is_chasing():
		for i in game.arena.barricades.size():
			var b = game.arena.barricades[i]
			if b.state != Barricade.State.DOWN or body.global_position.distance_to(b.global_position) > 1.8:
				continue
			var my_side: float = b.to_local(body.global_position).z
			var their_side: float = b.to_local(runner.global_position).z
			if my_side * their_side < 0.0 and runner.global_position.distance_to(b.global_position) < 10.0:
				game.start_break(body, i)
				return
	var to: Vector3 = runner.global_position - body.global_position
	to.y = 0.0
	if to.length() < 4.0 and _can_see(runner):
		var clear := _clear_run(runner)
		# Close with nothing in the way: turn to face the Runner and lunge, holding the swing to reach
		# further. Something low in the way (a window sill, a dropped barricade): only swing when the
		# Runner is within reach, otherwise keep following the path around instead of running into it.
		if clear or (to.length() < TUNING.hunter_attack_range and body.cooldown <= 0.0):
			body.yaw = atan2(-to.x, -to.z)
			body.bot_attack_held = true
			if clear:
				body.bot_input = Vector2(0, -1)
			else:
				_aiming = true
			if to.length() < 3.2 and _think_delay <= 0.0:
				_think_delay = 0.25  # a human-ish reaction time
				body.try_attack()


## True if a dropped barricade lies on the way to `target` and walking around it is quicker
## than walking up to it and breaking it.
func _quicker_around(target: Vector3) -> bool:
	var me := body.global_position
	var layers := _agent.navigation_layers
	var through := NavigationServer3D.map_get_path(body.get_world_3d().navigation_map, me, target, true, layers)
	if not _crosses_dropped(through):
		return false
	var around := NavigationServer3D.map_get_path(game.arena.nav_blocked_map, me, target, true, layers)
	if around.is_empty() or around[around.size() - 1].distance_to(target) > 1.5:
		return false  # no way around
	var speed: float = TUNING.hunter_speed
	var break_time := _length(through) / speed + TUNING.hunter_break_time
	return _length(around) / speed < break_time


func _crosses_dropped(path: PackedVector3Array) -> bool:
	for b in game.arena.barricades:
		if b.state != Barricade.State.DOWN:
			continue
		for i in range(1, path.size()):
			var a: Vector3 = b.to_local(path[i - 1])
			var c: Vector3 = b.to_local(path[i])
			if a.z * c.z >= 0.0:
				continue
			var x := lerpf(a.x, c.x, a.z / (a.z - c.z))
			if absf(x) < Barricade.GAP_WIDTH:
				return true
	return false


func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## True if the Hunter could run straight at `target` without bumping into anything.
func _clear_run(target: Node3D) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), body.global_position + Vector3(0, 0.5, 0))
	q.motion = target.global_position - body.global_position
	q.motion.y = 0.0
	var hit := body.get_world_3d().direct_space_state.cast_motion(q)
	return hit.is_empty() or hit[0] >= 1.0


func _flee(delta: float, hunter) -> void:
	var me: Vector3 = body.global_position
	var threat: Vector3 = hunter.global_position
	var dist := me.distance_to(threat)

	# Drop a barricade on the Hunter when they are right behind us.
	var it: Dictionary = game.find_interaction(body)
	if it.get("kind") == "drop" and dist < 5.0 and _think_delay <= 0.0:
		_think_delay = 0.3
		game.do_interact(body)
		_goal_time = 0.0
		return

	# When the Hunter is close, loop an obstacle: keep it between us by heading for its far side.
	if dist < 12.0:
		var loop := _pick_loop(me, threat)
		if loop != Vector3.INF:
			_goal_time = 0.0
			_set_goal(loop)
			return

	_goal_time -= delta
	if _goal_time <= 0.0 or me.distance_to(_goal) < 1.0:
		_goal_time = 1.5
		_set_goal(_pick_flee_spot(me, threat))


## The far side (from the Hunter) of the nearest window or barricade we can reach first,
## or Vector3.INF if there isn't one.
func _pick_loop(me: Vector3, threat: Vector3) -> Vector3:
	var openings: Array[Transform3D] = []
	for i in game.arena.windows.size():
		if not game.arena.is_window_blocked(i):
			openings.append(game.arena.windows[i])
	for b in game.arena.barricades:
		if b.state != Barricade.State.BROKEN:
			openings.append(b.global_transform)
	var best := Vector3.INF
	var best_d := 10.0
	for xf in openings:
		var d := me.distance_to(xf.origin)
		if d < best_d and d < threat.distance_to(xf.origin) - 0.5:
			var n := xf.basis.z
			var away_side := signf((xf.origin - threat).dot(n))
			if away_side == 0.0:
				away_side = 1.0
			best = xf.origin + n * away_side * 3.0
			best_d = d
	return best


## Picks somewhere to run: far from the Hunter, not past them, preferably behind a wall.
func _pick_flee_spot(me: Vector3, threat: Vector3) -> Vector3:
	var best := me
	var best_score := -INF
	var away := me - threat
	away.y = 0.0
	away = away.normalized()
	var threat_dist := me.distance_to(threat)
	var space := body.get_world_3d().direct_space_state
	# Running through a standing barricade lets us drop it behind us, so those spots get a bonus.
	var bonus := {}
	for b in game.arena.barricades:
		if b.state == Barricade.State.UP and me.distance_to(b.global_position) < 8.0:
			var far_side := 2.0 if b.to_local(threat).z < 0.0 else -2.0
			bonus[b.to_global(Vector3(0, 0, far_side))] = 6.0
	for spot: Vector3 in game.arena.loop_spots:
		var dir := spot - me
		dir.y = 0.0
		var score := spot.distance_to(threat) - 0.5 * dir.length()
		if dir.length() > 0.5 and dir.normalized().dot(away) < -0.2:
			score -= 15.0  # would run toward the Hunter
		if spot.distance_to(threat) < dir.length():
			score -= 10.0  # the Hunter would get there first
		if threat_dist < 10.0 and dir.length() < 3.0:
			score -= 20.0  # the Hunter is coming; don't stand still
		var q := PhysicsRayQueryParameters3D.create(threat + Vector3(0, 1.5, 0), spot + Vector3(0, 1.0, 0), 1)
		if not space.intersect_ray(q).is_empty():
			score += 6.0  # a wall between us and the Hunter
		score += bonus.get(spot, 0.0) + randf() * 2.0
		if score > best_score:
			best_score = score
			best = spot
	return best


func _set_goal(p: Vector3) -> void:
	# Re-plan a few times a second, or right away if the goal jumped somewhere new.
	if _repath <= 0.0 or p.distance_to(_goal) > 2.0:
		_repath = REPATH_TIME
		_agent.target_position = p
	_goal = p


func _follow_path(delta: float) -> void:
	if body.busy > 0.0 or body.stun > 0.0:
		return
	var me := body.global_position
	var next := _agent.get_next_path_position()
	var dir := next - me
	dir.y = 0.0
	if body.bot_input == Vector2.ZERO and not _aiming and dir.length() > 0.05:
		body.yaw = atan2(-dir.x, -dir.z)
		body.bot_input = Vector2(0, -1)

	# Vault or break when the path goes through a window or a dropped barricade.
	var it: Dictionary = game.find_interaction(body)
	match it.get("kind", ""):
		"vault_window":
			if _vault_rest <= 0.0 and _crosses(game.arena.windows[it.index], me, next, _goal):
				game.do_interact(body)
		"vault_barricade", "break":
			var b = game.arena.barricades[it.index]
			if not (it.kind == "break" and _go_around) and _crosses(b.global_transform, me, next, _goal):
				game.do_interact(body)

	# If we haven't really moved in a while, try whatever is in reach, then pick a new spot.
	_stuck_timer += delta
	if _stuck_timer >= STUCK_TIME:
		if me.distance_to(_stuck_from) < 0.4 and body.bot_input != Vector2.ZERO:
			if not it.is_empty() and it.kind != "drop":
				game.do_interact(body)
			_goal_time = 0.0
		_stuck_timer = 0.0
		_stuck_from = me


## True if going from `a` toward `b` or `goal` means passing through the opening at `xf`.
func _crosses(xf: Transform3D, a: Vector3, b: Vector3, goal: Vector3) -> bool:
	var n := xf.basis.z
	var side_a := (a - xf.origin).dot(n)
	return side_a * (b - xf.origin).dot(n) < 0.0 or side_a * (goal - xf.origin).dot(n) < 0.0


func _can_see(target: Node3D) -> bool:
	var from := body.global_position + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, target.global_position + Vector3(0, 1.0, 0), 1)
	return body.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

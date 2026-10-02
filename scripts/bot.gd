extends Node
## A computer-controlled opponent for playing alone. Add it as a child of a player body.
## As Hunter it closes the distance and swings: it runs straight at the Runner (aiming a little
## ahead of them) when nothing is in the way, follows the path otherwise, and at a dropped trash
## can works out whether kicking it or running around is quicker.
## As Runner it tries to stay as far from the Hunter as it can: a few times a second it scores
## places it could run to by how far behind the Hunter would be when it got there, avoids paths
## the Hunter could cut off, knocks trash cans over on the Hunter and doesn't vault the same
## window back and forth.
## Both steer around corners they would snag on and sidestep when they stop making progress.

const Role := preload("res://scripts/player.gd").Role
const TUNING := preload("res://tuning.tres")
const Barricade := preload("res://scripts/barricade.gd")

const REPATH_TIME := 0.25
## How often the Runner rethinks where to run.
const THINK_TIME := 0.25
## After vaulting, the bot Hunter walks around for a while instead of vaulting back and forth.
const HUNTER_VAULT_REST := 6.0
## How long the Hunter sticks with a choice to break or go around, so it doesn't dither.
const DECIDE_TIME := 1.0
## The Runner won't vault a window again this soon after vaulting it (no ping-pong).
const REVAULT_REST := 6.0
## Moving less than this far in UNSTICK_CHECK seconds while trying to move means we're stuck.
const UNSTICK_CHECK := 0.5
const UNSTICK_MIN_MOVE := 0.35
const UNSTICK_TIME := 0.45
## The Runner picks a new spot only if it is clearly better, so it doesn't flip-flop.
const SWITCH_MARGIN := 1.5
## Further than this (metres, by the Hunter's path) and the Runner just waits by a good spot.
const FAR := 30.0
## How much the Runner likes being next to a window or a standing trash can.
const LOOP_BONUS := 3.0
## How far ahead (seconds) the Runner looks when comparing ways to run.
const LOOKAHEAD := 2.5

var game: Node
var body: CharacterBody3D

var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _goal := Vector3.INF
var _goal_bonus := 0.0
var _think := 0.0
var _think_delay := 0.0
var _vault_rest := 0.0
var _go_around := false
var _decide := 0.0
## True while the Hunter stands still to swing over something (a dropped barricade, a window sill).
var _aiming := false
## True while the Hunter runs straight at the Runner instead of following a path.
var _direct := false
## Windows the Runner vaulted recently: window index -> seconds since.
var _vaulted := {}
var _was_vaulting := false
var _check_timer := 0.0
var _check_from := Vector3.ZERO
var _unstick := 0.0
var _unstick_dir := Vector3.ZERO
var _unstick_turn := 1.0


func _physics_process(delta: float) -> void:
	if body == null:
		body = get_parent()
	body.bot_input = Vector2.ZERO
	body.bot_attack_held = false
	_aiming = false
	_direct = false
	# Bot Runners always sprint (Shift held) when moving.
	body.bot_sprint = body.role == Role.RUNNER
	if game.bot_frozen or not game.is_chasing() or body.frozen or body.downed:
		_path = PackedVector3Array()
		_goal = Vector3.INF
		return
	var foe = null
	for p in game.players.values():
		if p != body:
			foe = p
	if foe == null:
		return
	_think_delay -= delta
	_repath -= delta
	_note_vaults(delta)
	if body.role == Role.HUNTER:
		_hunt(delta, foe)
	else:
		_go_around = false
		_flee(delta, foe)
	_follow(delta)


func _note_vaults(delta: float) -> void:
	for k in _vaulted.keys():
		_vaulted[k] += delta
		if _vaulted[k] > REVAULT_REST:
			_vaulted.erase(k)
	if body.vaulting and not _was_vaulting:
		if body.role == Role.HUNTER:
			_vault_rest = HUNTER_VAULT_REST
		elif body.last_vault.begins_with("w"):
			_vaulted[int(body.last_vault.substr(1))] = 0.0
		_path = PackedVector3Array()
		_repath = 0.0
	_was_vaulting = body.vaulting
	_vault_rest -= delta


# --- Hunter --------------------------------------------------------------

func _hunt(delta: float, runner) -> void:
	if runner.downed:
		return
	var me := body.global_position
	var rpos: Vector3 = runner.global_position
	var to := rpos - me
	to.y = 0.0
	var dist := to.length()
	var sees := _can_see(runner)
	_decide -= delta
	if _decide <= 0.0:
		_decide = DECIDE_TIME
		_go_around = _quicker_around(rpos)

	# Right at a dropped trash can with the Runner across it, and breaking is quicker: break it.
	if not _go_around and body.busy <= 0.0:
		for i in game.arena.barricades.size():
			var b = game.arena.barricades[i]
			if b.state != Barricade.State.DOWN or me.distance_to(b.global_position) > 1.8:
				continue
			var my_side: float = b.to_local(me).z
			var their_side: float = b.to_local(rpos).z
			if my_side * their_side < 0.0 and rpos.distance_to(b.global_position) < 10.0:
				game.start_break(body, i)
				return

	# Aim a little ahead of a Runner we can see, so we cut corners instead of trailing them.
	var aim := rpos
	if sees and dist > 2.5:
		var v: Vector3 = runner.get_real_velocity()
		v.y = 0.0
		aim += v * clampf(dist / TUNING.hunter_speed, 0.0, 0.6)

	if dist < 4.0 and sees:
		var clear := _clear_run(rpos)
		# Close with nothing in the way: face the Runner and lunge, holding the swing to reach further.
		# Something low in the way (a window sill, a dropped trash can): only swing when the Runner is
		# within reach, otherwise keep following the path around instead of running into it.
		if clear or (dist < TUNING.hunter_attack_range and body.cooldown <= 0.0):
			body.yaw = atan2(-to.x, -to.z)
			body.bot_attack_held = true
			if clear:
				body.bot_input = Vector2(0, -1)
				_direct = true
			else:
				_aiming = true
			if dist < 3.2 and _think_delay <= 0.0:
				_think_delay = 0.25  # a human-ish reaction time
				body.try_attack()
			return

	# Nothing in the way: run straight at where the Runner is going.
	if sees and dist < 15.0 and _clear_run(aim) and _clear_run(rpos):
		_steer_toward(aim)
		_direct = true
		return
	_set_goal(rpos)


## True if a dropped barricade lies on the way to `target` and walking around it is quicker
## than walking up to it and breaking it.
func _quicker_around(target: Vector3) -> bool:
	var me := body.global_position
	var layers := _hunter_layers()
	var through := NavigationServer3D.map_get_path(_main_map(), me, target, true, layers)
	if _crossed_cans(through) == 0:
		return false
	var around := NavigationServer3D.map_get_path(game.arena.nav_blocked_map, me, target, true, layers)
	if around.is_empty() or around[around.size() - 1].distance_to(target) > 1.5:
		return false  # no way around
	return _length(around) < _length(through) + TUNING.hunter_break_time * TUNING.hunter_speed


func _hunter_layers() -> int:
	return 1 if _vault_rest > 0.0 else 1 | 2


# --- Runner --------------------------------------------------------------

func _flee(delta: float, hunter) -> void:
	var me: Vector3 = body.global_position
	var threat: Vector3 = hunter.global_position
	var dist := me.distance_to(threat)

	# Knock a trash can over on the Hunter once we're through it and they're right behind us.
	var it: Dictionary = game.find_interaction(body)
	if it.get("kind") == "drop" and dist < 5.0 and _think_delay <= 0.0:
		var b = game.arena.barricades[it.index]
		var mine: float = b.to_local(me).z
		var theirs: float = b.to_local(threat).z
		var heading: float = b.to_local(_goal).z if _goal != Vector3.INF else -theirs
		if mine * theirs < 0.0 or (absf(mine) < 1.0 and heading * theirs < 0.0):
			_think_delay = 0.3
			game.do_interact(body)
			_think = 0.0
			return

	_think -= delta
	if _think <= 0.0 or _goal == Vector3.INF:
		_think = THINK_TIME
		_pick_spot(me, hunter)


## Scores places to run to and heads for the best. A place is good when the Hunter would still be
## far behind (by their own path, counting vaults and trash cans) by the time we got there.
## Places beside windows and trash cans get a bonus: that's where the Runner can gain ground.
func _pick_spot(me: Vector3, hunter) -> void:
	var threat: Vector3 = hunter.global_position
	var map := _main_map()
	var far := _hunter_cost(threat, me) > FAR
	var spots: Array[Vector3] = []
	var bonus: Array[float] = []
	for i in game.arena.windows.size():
		if game.arena.is_window_blocked(i):
			continue
		var w: Transform3D = game.arena.windows[i]
		for side in [2.0, -2.0]:
			spots.append(w.origin + w.basis.z * side)
			bonus.append(LOOP_BONUS)
	for b in game.arena.barricades:
		if b.state == Barricade.State.BROKEN:
			continue
		for side in [2.0, -2.0]:
			spots.append(b.to_global(Vector3(0, 0, side)))
			bonus.append(LOOP_BONUS if b.state == Barricade.State.UP else LOOP_BONUS * 0.5)
	if not far:
		for k in 16:
			var a := TAU * k / 16.0
			for r in [4.0, 9.0]:
				spots.append(NavigationServer3D.map_get_closest_point(map, me + Vector3(sin(a), 0, cos(a)) * r))
				bonus.append(0.0)
	var keep := _goal
	if keep != Vector3.INF:
		spots.append(keep)
		bonus.append(_goal_bonus)

	var best := -1
	var best_path := PackedVector3Array()
	var best_score := -INF
	var keep_score := -INF
	var keep_path := PackedVector3Array()
	for i in spots.size():
		var s := spots[i]
		if me.distance_to(s) > 30.0:
			continue
		var path := _runner_path(me, s)
		if path.is_empty() or path[path.size() - 1].distance_to(s) > 1.5:
			continue
		var score: float
		if far:
			# The Hunter is a long way off: get to a good spot near us, not toward them.
			score = bonus[i] - _length(path) + 0.3 * _hunter_cost(threat, s)
		else:
			score = _score_spot(path, threat) + bonus[i]
		if i == spots.size() - 1 and s == keep:
			keep_score = score
			keep_path = path
		score += randf() * 0.3
		if score > best_score:
			best_score = score
			best = i
			best_path = path
	if best < 0:
		return
	# Stick with the current spot unless the new one is clearly better or we got there.
	if keep_score > -INF and me.distance_to(keep) > 1.5 and best_score < keep_score + SWITCH_MARGIN:
		best = spots.size() - 1
		best_path = keep_path
	if spots[best] != _goal or _repath <= 0.0:
		_goal = spots[best]
		_goal_bonus = bonus[best]
		_use_path(best_path)
		_repath = REPATH_TIME


## How good running along `path` is: how far the Hunter would still be from us LOOKAHEAD seconds from now.
func _score_spot(path: PackedVector3Array, threat: Vector3) -> float:
	var vr: float = TUNING.runner_sprint_speed
	var vh: float = TUNING.hunter_speed
	# Where we'd be after LOOKAHEAD seconds of running this way (or the spot itself, if nearer)...
	var at := _point_along(path, vr * LOOKAHEAD)
	# ...and how far the Hunter would still be from there by then, by their own way (counting the
	# time they lose vaulting or kicking a trash can). Bigger is better.
	var score := _hunter_cost(threat, at) - vh * LOOKAHEAD
	# Don't run past the Hunter or anywhere they can reach first on the way.
	var along := 0.0
	var space := body.get_world_3d().direct_space_state
	for i in range(1, path.size()):
		along += path[i - 1].distance_to(path[i])
		if along > 10.0:
			break
		var p := path[i]
		if threat.distance_to(p) < along * vh / vr + 1.5:
			var q := PhysicsRayQueryParameters3D.create(threat + Vector3(0, 0.5, 0), p + Vector3(0, 0.5, 0), 1)
			if space.intersect_ray(q).is_empty():
				score -= 20.0
				break
	# Standing trash cans on the way are good: we can knock them over behind us.
	if _crossed_cans(path, Barricade.State.UP) > 0:
		score += 3.0
	return score


## The point `dist` metres along `path` (or its end).
func _point_along(path: PackedVector3Array, dist: float) -> Vector3:
	for i in range(1, path.size()):
		var step := path[i - 1].distance_to(path[i])
		if step >= dist:
			return path[i - 1].lerp(path[i], dist / step)
		dist -= step
	return path[path.size() - 1]


## Path length for the Hunter from `from` to `to`, plus their vault and can kicking time as distance.
func _hunter_cost(from: Vector3, to: Vector3) -> float:
	var vh: float = TUNING.hunter_speed
	var path := NavigationServer3D.map_get_path(_main_map(), from, to, true, 1 | 2)
	var cost := _length(path) + _crossed_windows(path).size() * (TUNING.hunter_window_vault_time * vh - 2.0)
	if _crossed_cans(path) > 0:
		var around := NavigationServer3D.map_get_path(game.arena.nav_blocked_map, from, to, true, 1 | 2)
		var around_cost := INF
		if not around.is_empty() and around[around.size() - 1].distance_to(to) < 1.5:
			around_cost = _length(around) + _crossed_windows(around).size() * (TUNING.hunter_window_vault_time * vh - 2.0)
		cost = minf(cost + _crossed_cans(path) * TUNING.hunter_break_time * vh, around_cost)
	return cost


## Our own way to `to`: through windows if allowed, else around. No windows that are blocked for us
## or that we just vaulted (that's how the old bot ping-ponged).
func _runner_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := _main_map()
	var path := NavigationServer3D.map_get_path(map, from, to, true, 1 | 2)
	for w in _crossed_windows(path):
		if game.arena.is_window_blocked(w) or _vaulted.has(w):
			return NavigationServer3D.map_get_path(map, from, to, true, 1)
	return path


# --- Paths and steering --------------------------------------------------

func _main_map() -> RID:
	return body.get_world_3d().navigation_map


func _set_goal(p: Vector3) -> void:
	# Re-plan a few times a second, or right away if the goal jumped somewhere new.
	if _repath > 0.0 and p.distance_to(_goal) <= 2.0 and not _path.is_empty():
		return
	_repath = REPATH_TIME
	_goal = p
	var map: RID = game.arena.nav_blocked_map if _go_around else _main_map()
	_use_path(NavigationServer3D.map_get_path(map, body.global_position, p, true, _hunter_layers()))


func _use_path(path: PackedVector3Array) -> void:
	_path = path
	_path_i = 1 if path.size() > 1 else 0


func _follow(delta: float) -> void:
	if body.busy > 0.0 or body.stun > 0.0 or body.vaulting:
		_check_from = body.global_position
		_check_timer = 0.0
		return
	var me := body.global_position
	var next := me
	if not _direct and not _aiming and body.bot_input == Vector2.ZERO:
		while _path_i < _path.size() and _flat(_path[_path_i] - me).length() < 0.5:
			_path_i += 1
		if _path_i < _path.size():
			next = _path[_path_i]
			_steer_toward(next)

	# Vault or break when the path goes through a window or a dropped trash can.
	var it: Dictionary = game.find_interaction(body)
	var after := _path[mini(_path_i + 1, _path.size() - 1)] if not _path.is_empty() else next
	match it.get("kind", ""):
		"vault_window":
			var ok: bool = _vault_rest <= 0.0 if body.role == Role.HUNTER else not _vaulted.has(it.index)
			if ok and not _direct and _crosses(game.arena.windows[it.index], me, next, after):
				game.do_interact(body)
		"vault_barricade", "break":
			var b = game.arena.barricades[it.index]
			if not (it.kind == "break" and _go_around) and _crosses(b.global_transform, me, next, after):
				game.do_interact(body)

	# Not getting anywhere while trying to move: sidestep for a moment, then plan again.
	_check_timer += delta
	if _unstick > 0.0:
		_unstick -= delta
		body.yaw = atan2(-_unstick_dir.x, -_unstick_dir.z)
		body.bot_input = Vector2(0, -1)
	elif _check_timer >= UNSTICK_CHECK:
		if _flat(me - _check_from).length() < UNSTICK_MIN_MOVE and body.bot_input != Vector2.ZERO and not _aiming:
			if not it.is_empty() and it.kind != "drop":
				game.do_interact(body)
			var want := Vector3(-sin(body.yaw), 0, -cos(body.yaw))
			_unstick_turn = -_unstick_turn
			_unstick_dir = want.rotated(Vector3.UP, deg_to_rad(100.0) * _unstick_turn)
			_unstick = UNSTICK_TIME
			_repath = 0.0
			_think = 0.0
			_path = PackedVector3Array()
		_check_timer = 0.0
		_check_from = me


## Faces and walks toward `p`, turning off a little if something would snag us on the way.
func _steer_toward(p: Vector3) -> void:
	var dir := _flat(p - body.global_position)
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	if not _crossing_opening(dir):
		for turn in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0]:
			var d := dir.rotated(Vector3.UP, deg_to_rad(turn))
			if not _blocked(d):
				dir = d
				break
	body.yaw = atan2(-dir.x, -dir.z)
	body.bot_input = Vector2(0, -1)


## True if walking a short way in `dir` would bump into a wall (not the floor or the other player).
func _blocked(dir: Vector3) -> bool:
	var hit := KinematicCollision3D.new()
	if not body.test_move(body.global_transform, dir * 0.45, hit):
		return false
	if not hit.get_collider() is StaticBody3D:
		return false
	var n := hit.get_normal()
	return absf(n.y) < 0.7 and -dir.dot(_flat(n).normalized()) > 0.35


## True if we're about to go through a window or trash can gap: don't steer off that line.
func _crossing_opening(dir: Vector3) -> bool:
	var me := body.global_position
	var ahead := me + dir * 1.5
	for i in game.arena.windows.size():
		var w: Transform3D = game.arena.windows[i]
		if me.distance_to(w.origin) < 2.2 and _crosses(w, me, ahead, ahead):
			return true
	for b in game.arena.barricades:
		if b.state != Barricade.State.BROKEN and me.distance_to(b.global_position) < 2.2 \
				and _crosses(b.global_transform, me, ahead, ahead):
			return true
	return false


# --- Helpers -------------------------------------------------------------

## Windows a path goes through (by index).
func _crossed_windows(path: PackedVector3Array) -> Array[int]:
	var out: Array[int] = []
	for i in game.arena.windows.size():
		if _path_crosses(game.arena.windows[i], path, 1.2):
			out.append(i)
	return out


## How many trash cans in `state` (dropped by default) a path goes through.
func _crossed_cans(path: PackedVector3Array, state := Barricade.State.DOWN) -> int:
	var n := 0
	for b in game.arena.barricades:
		if b.state == state and _path_crosses(b.global_transform, path, Barricade.GAP_WIDTH * 0.5):
			n += 1
	return n


func _path_crosses(xf: Transform3D, path: PackedVector3Array, half_width: float) -> bool:
	var inv := xf.affine_inverse()
	for i in range(1, path.size()):
		var a: Vector3 = inv * path[i - 1]
		var c: Vector3 = inv * path[i]
		if a.z * c.z >= 0.0:
			continue
		var x := lerpf(a.x, c.x, a.z / (a.z - c.z))
		if absf(x) < half_width:
			return true
	return false


func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## True if the Hunter could run straight at `target` without bumping into anything.
func _clear_run(target: Vector3) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), body.global_position + Vector3(0, 0.5, 0))
	q.motion = _flat(target - body.global_position)
	var hit := body.get_world_3d().direct_space_state.cast_motion(q)
	return hit.is_empty() or hit[0] >= 1.0


## True if going from `a` toward `b` or `c` means passing through the opening at `xf`.
func _crosses(xf: Transform3D, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var n := xf.basis.z
	var side_a := (a - xf.origin).dot(n)
	return side_a * (b - xf.origin).dot(n) < 0.0 or side_a * (c - xf.origin).dot(n) < 0.0


func _can_see(target: Node3D) -> bool:
	var from := body.global_position + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, target.global_position + Vector3(0, 1.0, 0), 1)
	return body.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

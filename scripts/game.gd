extends Node3D
## Runs one match: builds the arena, spawns the players and (on the host) runs the rounds.
## Round 1: host is the Hunter. Round 2: roles swap. Whoever survived longer as Runner wins.
##
## The host makes every decision that matters (hits, barricades, round end) and tells the
## other computer with RPCs. Each player moves their own body.

signal exit_to_menu(message: String)

const PlayerScript := preload("res://scripts/player.gd")
const Arena := preload("res://scripts/arena.gd")
const Barricade := preload("res://scripts/barricade.gd")
const Hud := preload("res://scripts/hud.gd")
const Bot := preload("res://scripts/bot.gd")
const Effects := preload("res://scripts/effects.gd")
const TUNING := preload("res://tuning.tres")

const Role := PlayerScript.Role

enum Phase { LOBBY, COUNTDOWN, CHASE, ROUND_OVER, MATCH_OVER }

const ROUND_OVER_TIME := 5.0
const HIT_GRACE_MS := 1000
## The bot's made-up peer id. Real peers never get id 2 (ENet ids are large random numbers).
const BOT_ID := 2

## Playing alone against a bot. You keep the role you picked every round.
var vs_bot := false
var map_id := 0  # which map to build (set before adding the game); see arena.gd
var bot_frozen := false  # dev key F6: the bot stands still and does nothing
var human_role := Role.RUNNER
var closing := false
var phase := Phase.LOBBY
var round_num := 0
var hunter_id := 0
var runner_id := 0
var runner_health := 2  # 2 healthy, 1 injured, 0 downed
## Counts down during COUNTDOWN and ROUND_OVER; counts up during CHASE (the survival time).
var clock := 0.0
## One entry per finished round: {"runner": peer id, "time": seconds}.
var results: Array = []
var players := {}  # peer id -> player node
var last_reason := ""
var arena: Node3D
var hud: CanvasLayer
var effects: Node3D

var _players_root: Node3D
var _last_hit_ms := -HIT_GRACE_MS
var _clock_send := 0.0


func _ready() -> void:
	arena = Arena.new()
	arena.name = "Arena"
	arena.map_id = map_id
	add_child(arena)
	_players_root = Node3D.new()
	_players_root.name = "Players"
	add_child(_players_root)
	effects = Effects.new()
	effects.game = self
	add_child(effects)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Starting ------------------------------------------------------------

func start_host() -> void:
	# Walk around on your own while you wait for someone to join.
	_spawn_players([1])
	players[1].frozen = false


func start_client() -> void:
	pass  # The host tells us when to spawn.


func start_vs_bot(role: Role) -> void:
	vs_bot = true
	human_role = role
	_spawn_players([1, BOT_ID])
	var bot := Bot.new()
	bot.game = self
	players[BOT_ID].add_child(bot)
	_begin_round(1)


# --- Connection events ---------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if closing or vs_bot or not multiplayer.is_server():
		return
	_spawn_players.rpc([1, id])
	_begin_round(1)


func _on_peer_disconnected(_id: int) -> void:
	if not closing:
		exit_to_menu.emit("Your opponent left the match.")


func _on_server_disconnected() -> void:
	if not closing:
		exit_to_menu.emit("Lost connection to the host.")


func _on_connection_failed() -> void:
	if not closing:
		exit_to_menu.emit("Could not connect. Check the IP address and that the host is waiting.")


# --- Every frame ---------------------------------------------------------

func _process(delta: float) -> void:
	var host := multiplayer.is_server()
	match phase:
		Phase.COUNTDOWN:
			clock -= delta
			if host and clock <= 0.0:
				_set_phase.rpc(Phase.CHASE)
		Phase.CHASE:
			clock += delta
			if host and clock >= TUNING.round_time_cap:
				_finish_round("time")
		Phase.ROUND_OVER:
			clock -= delta
			if host and clock <= 0.0:
				if round_num == 1 and not vs_bot:
					_begin_round(2)
				else:
					_end_match.rpc()
				return
	if host and not vs_bot and phase != Phase.LOBBY:
		_clock_send -= delta
		if _clock_send <= 0.0:
			_clock_send = 0.2
			_sync_clock.rpc(clock)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rematch") and phase == Phase.MATCH_OVER and multiplayer.is_server():
		_begin_round(1 if not vs_bot else round_num + 1)
	# Dev keys for practicing against the bot: F5 resets every window and trash can,
	# F6 freezes or unfreezes the bot in place.
	if vs_bot and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5:
				_dev_reset_map()
			KEY_F6:
				bot_frozen = not bot_frozen
				hud.flash("Bot frozen" if bot_frozen else "Bot unfrozen")


func _dev_reset_map() -> void:
	arena.reset()
	for p in players.values():
		p.dropped_barricade = -1
		p.last_vault = ""
	hud.flash("Windows and trash cans reset")


# --- Helpers used by players and the HUD ---------------------------------

func local_player() -> Node:
	return players.get(multiplayer.get_unique_id())


func get_runner() -> Node:
	return players.get(runner_id)


func is_chasing() -> bool:
	return phase == Phase.CHASE


## True during the Runner's head start at the beginning of the chase, when the Hunter can't act yet.
func hunter_held() -> bool:
	return phase == Phase.CHASE and clock < TUNING.runner_head_start


## What the player could do right now by pressing the interact key, or {} if nothing.
func find_interaction(p: Node) -> Dictionary:
	if phase != Phase.CHASE or p.busy > 0.0 or p.stun > 0.0 or p.downed or p.vaulting:
		return {}
	var best := {}
	var best_dist := INF
	for i in arena.barricades.size():
		var b = arena.barricades[i]
		var d := _flat_distance(p.global_position, b.global_position)
		var option := {}
		if p.role == Role.RUNNER and b.state == Barricade.State.UP and d < 1.7:
			option = {"kind": "drop", "index": i, "text": "Knock over trash can"}
		elif p.role == Role.RUNNER and b.state == Barricade.State.DOWN and d < 1.5 \
				and not (i == p.dropped_barricade and p.drop_lock > 0.0):
			option = {"kind": "vault_barricade", "index": i, "text": "Slide over trash can"}
		elif p.role == Role.HUNTER and b.state == Barricade.State.DOWN and d < 1.8:
			option = {"kind": "break", "index": i, "text": "Kick trash can away"}
		if not option.is_empty() and d < best_dist:
			best = option
			best_dist = d
	for i in arena.windows.size():
		if p.role == Role.RUNNER and arena.is_window_blocked(i):
			continue
		var d := _flat_distance(p.global_position, arena.windows[i].origin)
		if d < 1.4 and d < best_dist:
			best = {"kind": "vault_window", "index": i, "text": "Vault window"}
			best_dist = d
	return best


func do_interact(p: Node) -> void:
	if p.role == Role.HUNTER and hunter_held():
		return
	var it := find_interaction(p)
	if it.is_empty():
		return
	var i: int = it.index
	match it.kind:
		"drop":
			request_drop.rpc_id(1, i)
			# Dropping takes a moment: stand still briefly, and no instant vault over it.
			p.start_busy(TUNING.drop_pause, Callable())
			p.dropped_barricade = i
			p.drop_lock = TUNING.drop_vault_lockout
		"vault_barricade":
			p.vault(arena.barricades[i].global_transform, PlayerScript.VaultKind.BARRICADE, "b%d" % i)
		"vault_window":
			p.vault(arena.windows[i], PlayerScript.VaultKind.WINDOW, "w%d" % i)
			if p.role == Role.RUNNER:
				window_vaulted.rpc(i)
		"break":
			start_break(p, i)


func start_break(p: Node, i: int) -> void:
	# The Hunter winds up a kick (so the Runner can see it coming), then boots the can away.
	p.kicking = true
	p.start_busy(TUNING.hunter_break_time, func():
		p.kicking = false
		p.reset_bloodlust()
		request_break.rpc_id(1, i))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


## True if the request came from the computer that controls `player_id` (the host runs the bot).
func _sent_by(player_id: int) -> bool:
	return _sender() == (1 if player_id == BOT_ID else player_id)


# --- Host-only round flow ------------------------------------------------

func _begin_round(n: int) -> void:
	if vs_bot:
		var human_hunts := human_role == Role.HUNTER
		_start_round.rpc(n, 1 if human_hunts else BOT_ID, BOT_ID if human_hunts else 1)
		return
	var other := 0
	for id in players:
		if id != 1:
			other = id
	if other == 0:
		return
	var hunter := 1 if n == 1 else other
	var runner := other if n == 1 else 1
	_start_round.rpc(n, hunter, runner)


func _finish_round(reason: String) -> void:
	_round_over.rpc(runner_id, minf(clock, TUNING.round_time_cap), reason)


# --- Requests sent to the host -------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_hit() -> void:
	if not multiplayer.is_server() or phase != Phase.CHASE or not _sent_by(hunter_id):
		return
	var hunter = players.get(hunter_id)
	var runner = get_runner()
	if hunter == null or runner == null or runner_health <= 0:
		return
	# Allow a little extra range for network delay.
	if hunter.global_position.distance_to(runner.global_position) > TUNING.hunter_attack_range + 1.5:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < HIT_GRACE_MS:
		return
	_last_hit_ms = now
	_set_runner_health.rpc(runner_health - 1)
	if runner_health <= 0:
		_finish_round("downed")


@rpc("any_peer", "call_local", "reliable")
func request_drop(index: int) -> void:
	if not multiplayer.is_server() or phase != Phase.CHASE or not _sent_by(runner_id):
		return
	var b = arena.barricades[index]
	if b.state != Barricade.State.UP:
		return
	_set_barricade.rpc(index, Barricade.State.DOWN)
	var hunter = players.get(hunter_id)
	if hunter and b.in_zone(hunter.global_position):
		_stun_hunter.rpc()


@rpc("any_peer", "call_local", "reliable")
func request_break(index: int) -> void:
	if not multiplayer.is_server() or phase != Phase.CHASE or not _sent_by(hunter_id):
		return
	if arena.barricades[index].state == Barricade.State.DOWN:
		_set_barricade.rpc(index, Barricade.State.BROKEN)


# --- Messages from the host to everyone ----------------------------------

@rpc("authority", "call_local", "reliable")
func _spawn_players(ids: Array) -> void:
	for p in players.values():
		p.queue_free()
		p.name = "old"
	players.clear()
	for id in ids:
		var p := PlayerScript.new()
		p.name = str(id)
		p.game = self
		p.is_bot = id == BOT_ID
		p.set_multiplayer_authority(1 if p.is_bot else id)
		_players_root.add_child(p)
		players[id] = p
		p.spawn_at(arena.runner_spawn, arena.runner_spawn_yaw)


@rpc("authority", "call_local", "reliable")
func _start_round(n: int, hunter: int, runner: int) -> void:
	if n == 1:
		results.clear()
	round_num = n
	hunter_id = hunter
	runner_id = runner
	runner_health = 2
	arena.reset()
	for id in players:
		var p = players[id]
		p.set_role(Role.HUNTER if id == hunter else Role.RUNNER)
		if id == hunter:
			p.spawn_at(arena.hunter_spawn, arena.hunter_spawn_yaw)
		else:
			p.spawn_at(arena.runner_spawn, arena.runner_spawn_yaw)
		p.frozen = true
	_last_hit_ms = -HIT_GRACE_MS
	phase = Phase.COUNTDOWN
	clock = TUNING.countdown_time


@rpc("authority", "call_local", "reliable")
func _set_phase(p: Phase) -> void:
	phase = p
	if p == Phase.CHASE:
		clock = 0.0
		for player in players.values():
			player.frozen = false
		var me = local_player()
		hud.flash("RUN!" if me and me.role == Role.RUNNER else "HUNT!")


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_clock(value: float) -> void:
	clock = value


@rpc("authority", "call_local", "reliable")
func _set_runner_health(health: int) -> void:
	var hurt := health < runner_health
	runner_health = health
	var runner = get_runner()
	if runner:
		runner.on_health_changed(health, hurt)
	var hunter = players.get(hunter_id)
	if hurt and hunter and hunter.is_local():
		hunter.reset_bloodlust()
	if hurt and health > 0:
		hud.flash("Runner hit!")


@rpc("authority", "call_local", "reliable")
func _set_barricade(index: int, state: Barricade.State) -> void:
	var b = arena.barricades[index]
	var hunter = players.get(hunter_id)
	if state == Barricade.State.BROKEN and hunter:
		b.kick_away(hunter.global_position)
	else:
		b.set_state(state)
	if state == Barricade.State.DOWN:
		for p in players.values():
			if p.is_local() and b.in_zone(p.global_position):
				p.push_out_of(b)


@rpc("any_peer", "call_local", "reliable")
func window_vaulted(index: int) -> void:
	arena.note_window_vault(index)
	if arena.is_window_blocked(index):
		hud.flash("Window blocked!")


## A loud noise (a fast vault). Only the Hunter is shown where it came from.
@rpc("any_peer", "call_local", "reliable")
func make_noise(pos: Vector3) -> void:
	effects.noise_alert(pos)


@rpc("authority", "call_local", "reliable")
func _stun_hunter() -> void:
	var hunter = players.get(hunter_id)
	if hunter and hunter.is_local():
		hunter.apply_stun(TUNING.hunter_stun_time)
	hud.flash("Hunter stunned!")


@rpc("authority", "call_local", "reliable")
func _round_over(runner: int, time: float, reason: String) -> void:
	results.append({"runner": runner, "time": time})
	last_reason = reason
	phase = Phase.ROUND_OVER
	clock = ROUND_OVER_TIME
	for p in players.values():
		p.frozen = true


@rpc("authority", "call_local", "reliable")
func _end_match() -> void:
	phase = Phase.MATCH_OVER


## Text for the end-of-match screen, from this computer's point of view.
func match_summary() -> String:
	if vs_bot:
		return _bot_summary()
	var me := multiplayer.get_unique_id()
	var mine := 0.0
	var theirs := 0.0
	for r in results:
		if r.runner == me:
			mine = r.time
		else:
			theirs = r.time
	var lines := "You survived %s as Runner.\nYour opponent survived %s.\n\n" % [Hud.format_time(mine), Hud.format_time(theirs)]
	if absf(mine - theirs) <= TUNING.tie_window:
		lines += "DRAW! (Sudden death comes in a later version.)"
	elif mine > theirs:
		lines += "YOU WIN!"
	else:
		lines += "YOU LOSE."
	return lines


func _bot_summary() -> String:
	var last: Dictionary = results.back()
	var times: Array = results.map(func(r): return r.time)
	if last_reason == "time":
		return "Time cap reached! The bot survived %s." % Hud.format_time(last.time)
	if human_role == Role.RUNNER:
		return "You survived %s.\nYour best this session: %s" % [Hud.format_time(last.time), Hud.format_time(times.max())]
	return "You caught the bot in %s.\nYour fastest catch this session: %s" % [Hud.format_time(last.time), Hud.format_time(times.min())]

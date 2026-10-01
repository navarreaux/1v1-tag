extends CanvasLayer
## On-screen text: the timer, your role and health, what the Space key will do, and the pause menu.

const Role := preload("res://scripts/player.gd").Role
const TUNING := preload("res://tuning.tres")

var game: Node

var _top: Label
var _big: Label
var _info: Label
var _prompt: Label
var _crosshair: Label
var _pause: PanelContainer
var _flash_text := ""
var _flash_time := 0.0


static func format_time(seconds: float) -> String:
	var m := int(seconds) / 60
	return "%d:%04.1f" % [m, seconds - m * 60]


func _ready() -> void:
	_top = _label(28, Control.PRESET_CENTER_TOP, Vector2(0, 16))
	_big = _label(40, Control.PRESET_CENTER, Vector2.ZERO)
	_info = _label(22, Control.PRESET_BOTTOM_LEFT, Vector2(20, -20))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_prompt = _label(26, Control.PRESET_CENTER_BOTTOM, Vector2(0, -80))
	_crosshair = _label(26, Control.PRESET_CENTER, Vector2.ZERO)
	_crosshair.text = "+"
	_build_pause_menu()


func _label(font_size: int, preset: Control.LayoutPreset, offset: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	if preset != Control.PRESET_BOTTOM_LEFT:
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.position += offset
	return l


func _build_pause_menu() -> void:
	_pause = PanelContainer.new()
	add_child(_pause)
	_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_pause.add_child(box)
	var title := Label.new()
	title.text = "Paused (the match keeps going)"
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(_resume)
	box.add_child(resume)
	var leave := Button.new()
	leave.text = "Leave match"
	leave.pressed.connect(func(): game.exit_to_menu.emit("You left the match."))
	box.add_child(leave)
	_pause.hide()


func _resume() -> void:
	_pause.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _pause.visible:
			_resume()
		else:
			_pause.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()


func flash(text: String) -> void:
	_flash_text = text
	_flash_time = 1.5


func _process(delta: float) -> void:
	_flash_time -= delta
	var me = game.local_player()
	var P = game.Phase
	_top.text = ""
	_big.text = ""
	_prompt.text = ""
	_info.text = ""
	_crosshair.visible = me != null and me.role == Role.HUNTER and game.phase == P.CHASE

	match game.phase:
		P.LOBBY:
			if multiplayer.is_server():
				var ips := Net.local_addresses()
				_big.text = "Waiting for an opponent to join...\nYour IP: %s  (port %d)" % [", ".join(ips) if ips.size() > 0 else "127.0.0.1", Net.DEFAULT_PORT]
				_info.text = "Walk around while you wait. Esc for the menu."
			else:
				_big.text = "Connecting to the host..."
		P.COUNTDOWN:
			var goal := "Catch the Runner fast!" if me.role == Role.HUNTER else "Survive as long as you can!"
			var round_text := "Round %d vs the bot" % game.round_num if game.vs_bot else "Round %d of 2" % game.round_num
			_big.text = "%s\nYou are the %s\n%s\n\n%d" % [round_text, _role_name(me), goal, ceili(game.clock)]
		P.CHASE:
			_top.text = "Round %d   %s" % [game.round_num, format_time(game.clock)]
		P.ROUND_OVER:
			var r: Dictionary = game.results.back()
			var who := "You" if r.runner == multiplayer.get_unique_id() else ("The bot" if game.vs_bot else "Your opponent")
			var why := "The Runner was caught!" if game.last_reason == "downed" else "Time cap reached!"
			_big.text = "%s\n%s survived %s." % [why, who, format_time(r.time)]
			if game.round_num == 1 and not game.vs_bot:
				_big.text += "\n\nSwapping roles..."
		P.MATCH_OVER:
			_big.text = game.match_summary()
			if game.vs_bot:
				_big.text += "\n\nPress Enter to play again. Esc for the menu."
			elif multiplayer.is_server():
				_big.text += "\n\nHost: press Enter for a rematch."
			else:
				_big.text += "\n\nWaiting for the host to start a rematch."

	if me and game.phase == P.CHASE:
		_info.text = "You are the %s" % _role_name(me)
		if me.role == Role.RUNNER:
			_info.text += "   Health: %s" % ["Downed", "Injured", "Healthy"][clampi(game.runner_health, 0, 2)]
			if me.crouching:
				_info.text += "   Crouching"
			elif not me.sprinting:
				_info.text += "   Walking (hold Shift to sprint)"
		else:
			if me.in_chase:
				_info.text += "   In chase"
			if me.bloodlust > 0:
				_info.text += "   Bloodlust %s" % ["I", "II", "III"][me.bloodlust - 1]
		if me.stun > 0.0:
			_prompt.text = "Stunned!"
		elif me.busy > 0.0 and not me.vaulting and me.role == Role.HUNTER:
			_prompt.text = "Kicking..."
		elif me.role == Role.HUNTER and me.cooldown > 0.0:
			_prompt.text = "Recovering from your swing..."
		else:
			var it: Dictionary = game.find_interaction(me)
			if not it.is_empty():
				_prompt.text = "[Space] " + it.text

	if me and game.hunter_held():
		var left := ceili(TUNING.runner_head_start - game.clock)
		_prompt.text = ("Runner's head start: you can move in %d" if me.role == Role.HUNTER else "Head start! The Hunter is released in %d") % left

	if _flash_time > 0.0 and _big.text == "":
		_big.text = _flash_text


func _role_name(p) -> String:
	return "HUNTER" if p.role == Role.HUNTER else "RUNNER"

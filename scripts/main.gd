extends Node
## The main menu. Hosts a game, joins one, or starts a solo game against a bot.
##
## Shortcut for testing: run the game with "--host" or "--join" after "--" on the
## command line (or in Debug > Customize Run Instances) to skip the menu.

const GameScript := preload("res://scripts/game.gd")
const Role := preload("res://scripts/player.gd").Role

var game
var _menu: CanvasLayer
var _ip: LineEdit
var _status: Label


func _ready() -> void:
	_setup_input()
	_build_menu()
	var args := OS.get_cmdline_user_args()
	if "--host" in args:
		_host()
	elif "--join" in args:
		_join()


func _host() -> void:
	var err := Net.host()
	if err != OK:
		_status.text = "Could not host a game (error %d). Is another copy already hosting?" % err
		return
	_start_game().start_host()


func _join() -> void:
	var address := _ip.text.strip_edges()
	if address == "":
		address = "127.0.0.1"
	var err := Net.join(address)
	if err != OK:
		_status.text = "Could not start connecting (error %d)." % err
		return
	_start_game().start_client()


func _vs_bot(role: Role) -> void:
	Net.leave()
	_start_game().start_vs_bot(role)


func _start_game():
	_menu.hide()
	game = GameScript.new()
	game.name = "Game"  # must be the same on both computers so messages find it
	game.exit_to_menu.connect(_back_to_menu)
	add_child(game)
	return game


func _back_to_menu(message: String) -> void:
	if game:
		game.closing = true
		game.name = "ClosedGame"
		game.queue_free()
		game = null
	Net.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = message
	_menu.show()


func _setup_input() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("interact", [KEY_SPACE])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("crouch", [KEY_CTRL, KEY_C])
	_add_keys("rematch", [KEY_ENTER, KEY_KP_ENTER])
	_add_keys("pause", [KEY_ESCAPE])
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", click)


func _add_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _build_menu() -> void:
	_menu = CanvasLayer.new()
	add_child(_menu)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.11, 0.14)
	_menu.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "1v1 TAG"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Prototype. One Hunter chases one Runner."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var bot_label := Label.new()
	bot_label.text = "Play alone against a bot:"
	box.add_child(bot_label)
	var bot_row := HBoxContainer.new()
	box.add_child(bot_row)
	var br := _button("I'm the Runner", _vs_bot.bind(Role.RUNNER))
	br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_row.add_child(br)
	var bh := _button("I'm the Hunter", _vs_bot.bind(Role.HUNTER))
	bh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_row.add_child(bh)

	var online_label := Label.new()
	online_label.text = "Play against a person:"
	box.add_child(online_label)
	box.add_child(_button("Host a game", _host))
	var ip_row := HBoxContainer.new()
	box.add_child(ip_row)
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.placeholder_text = "Host's IP address"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_row.add_child(_ip)
	ip_row.add_child(_button("Join", _join))

	var help := Label.new()
	help.text = "WASD move   Shift sprint   Ctrl crouch   Mouse look\nSpace drop, vault, break   Left click swing (hold to lunge)   Esc pause"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.7)
	box.add_child(help)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.modulate = Color(1, 0.8, 0.4)
	box.add_child(_status)

	box.add_child(_button("Quit", get_tree().quit))


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(action)
	return b

extends PanelContainer
## Tile Test's tile builder: press T to open it (it frees the mouse). Pick any preset tile to
## spawn it in the middle of the arena, then select its pieces to move, turn and resize them,
## add or remove pieces, and spread the whole tile out or squeeze it together. Changes show at
## once. Save keeps a tile (it shows up in the menu next time); Copy numbers puts the tile's
## pieces on the clipboard as text, ready to bake into a map later.

const Arena := preload("res://scripts/arena.gd")

## Saved tiles go here (on Windows: %APPDATA%/Godot/app_userdata/<project>/tiles).
const SAVE_DIR := "user://tiles"
## Which numbers each kind of piece has.
const FIELDS := {
	"wall": ["x", "z", "rot", "length", "height"],
	"window": ["x", "z", "rot"],
	"can": ["x", "z", "rot"],
	"container": ["x", "z", "rot", "length"],
	"block": ["x", "z", "rot", "y", "sx", "sy", "sz"],
	"train": ["x", "z", "rot"],
	"lamp": ["x", "z"],
}
const FIELD_NAMES := {"x": "Left / right (m)", "z": "Back / front (m)", "rot": "Turn (degrees)",
	"length": "Length (m)", "height": "Height (m)", "y": "Lift off ground (m)", "sx": "Width (m)",
	"sy": "Height (m)", "sz": "Depth (m)"}
## [min, max, step] for each number.
const RANGES := {"x": [-30, 30, 0.25], "z": [-30, 30, 0.25], "rot": [-180, 180, 5],
	"length": [0.5, 40, 0.25], "height": [0.3, 6, 0.1], "y": [0, 8, 0.1], "sx": [0.1, 40, 0.25],
	"sy": [0.05, 8, 0.1], "sz": [0.1, 40, 0.25]}
## What "Add piece" offers, and the piece each one starts as (placed in the middle).
const NEW_PIECES := [
	["Wall", {"type": "wall", "length": 4.0, "height": 3.0, "color": "7f8fa8"}],
	["Low wall (see over it)", {"type": "wall", "length": 4.0, "height": 1.0, "color": "7f8fa8"}],
	["Window", {"type": "window"}],
	["Trash can (3 m gap)", {"type": "can"}],
	["Container", {"type": "container", "length": 5.5}],
	["Block", {"type": "block", "y": 0.0, "sx": 2.0, "sy": 2.0, "sz": 2.0, "color": "bf523a", "solid": true}],
	["Train car", {"type": "train"}],
	["Lamp", {"type": "lamp"}],
]
const TYPE_NAMES := {"wall": "Wall", "window": "Window", "can": "Trash can", "container": "Container",
	"block": "Block", "train": "Train car", "lamp": "Lamp"}
## Seconds to wait after the last change before redoing the bot's paths (that part is slow).
const BAKE_DELAY := 0.4

var game: Node

var _tiles: OptionButton
var _spread: HSlider
var _spread_label: Label
var _list: ItemList
var _fields: GridContainer
var _name: LineEdit
var _selected := -1
var _bake_in := 0.0
var _saved := {}  # tile name -> pieces


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -400
	offset_right = -10
	offset_top = 10
	offset_bottom = -10
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	box.add_child(_heading("Tile builder   (T to close)"))
	box.add_child(_text("Spawn a tile in the middle of the arena:"))
	_tiles = OptionButton.new()
	_tiles.item_selected.connect(_on_tile_picked)
	box.add_child(_tiles)
	_load_saved()
	_fill_tile_menu()

	var row := HBoxContainer.new()
	_spread_label = _text("Spread: 1.00x")
	_spread_label.custom_minimum_size.x = 120
	row.add_child(_spread_label)
	_spread = HSlider.new()
	_spread.min_value = 0.5
	_spread.max_value = 2.0
	_spread.step = 0.05
	_spread.value = 1.0
	_spread.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spread.value_changed.connect(_on_spread)
	row.add_child(_spread)
	box.add_child(row)

	box.add_child(_heading("Pieces"))
	_list = ItemList.new()
	_list.custom_minimum_size.y = 200
	_list.item_selected.connect(_select)
	box.add_child(_list)
	row = HBoxContainer.new()
	var add := MenuButton.new()
	add.text = "Add piece"
	add.flat = false
	for i in NEW_PIECES.size():
		add.get_popup().add_item(NEW_PIECES[i][0], i)
	add.get_popup().id_pressed.connect(_add_piece)
	row.add_child(add)
	row.add_child(_button("Duplicate", _duplicate_piece))
	row.add_child(_button("Delete", _delete_piece))
	box.add_child(row)
	_fields = GridContainer.new()
	_fields.columns = 2
	box.add_child(_fields)

	box.add_child(_heading("Save"))
	row = HBoxContainer.new()
	_name = LineEdit.new()
	_name.placeholder_text = "Tile name"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	row.add_child(_button("Save", _save))
	box.add_child(row)
	box.add_child(_button("Copy numbers to clipboard", _copy))
	var where := _text("Saved tiles are kept in:\n" + ProjectSettings.globalize_path(SAVE_DIR))
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(where)

	box.add_child(_heading("Test it"))
	box.add_child(_button("Spawn / remove bot   (B)", func(): game.toggle_test_bot()))
	box.add_child(_button("Reset windows & trash cans   (F5)", func(): game.dev_reset_map()))
	box.add_child(_button("Close   (T)", _close))
	_refresh_list()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	return l


func _text(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		if visible:
			_close()
		else:
			visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if _selected >= 0:
				game.arena.show_marker(game.arena.tile_pieces[_selected])
		get_viewport().set_input_as_handled()


func _close() -> void:
	visible = false
	release_focus()
	game.arena.show_marker(null)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _bake_in > 0.0:
		_bake_in -= delta
		if _bake_in <= 0.0:
			game.arena.rebuild_tile(true)
			game.on_tile_rebuilt()


# --- Tiles -----------------------------------------------------------------

func _fill_tile_menu() -> void:
	_tiles.clear()
	_tiles.add_item("Pick a tile...")
	_tiles.set_item_disabled(0, true)
	_tiles.add_item("(empty)")
	for name in Arena.TEST_TILES:
		_tiles.add_item(name)
	var names := _saved.keys()
	names.sort()
	for name in names:
		_tiles.add_item("Saved: " + name)
	_tiles.select(0)


func _on_tile_picked(index: int) -> void:
	var text := _tiles.get_item_text(index)
	var pieces: Array
	if text == "(empty)":
		pieces = []
	elif text.begins_with("Saved: "):
		pieces = _saved[text.trim_prefix("Saved: ")].duplicate(true)
		_name.text = text.trim_prefix("Saved: ")
	else:
		pieces = game.arena.tile_preset(text)
		_name.text = text
	game.arena.tile_pieces = pieces
	game.arena.tile_spread = 1.0
	_spread.set_value_no_signal(1.0)
	_spread_label.text = "Spread: 1.00x"
	_selected = -1
	_rebuild_now()
	_refresh_list()
	_tiles.select(0)
	game.hud.flash("Spawned %s" % text.trim_prefix("Saved: "))


func _on_spread(value: float) -> void:
	game.arena.tile_spread = value
	_spread_label.text = "Spread: %.2fx" % value
	_changed()


# --- Pieces ----------------------------------------------------------------

func _describe(piece: Dictionary) -> String:
	var text: String = TYPE_NAMES.get(piece.type, piece.type)
	match piece.type:
		"wall":
			text = ("Low wall" if piece.get("height", 3.0) < 2.0 else "Wall") + " %.1f m" % piece.length
		"container":
			text += " %.1f m" % piece.length
		"block":
			text += " %.1f x %.1f x %.1f" % [piece.sx, piece.sy, piece.sz]
	return text + "   at (%.2f, %.2f)" % [piece.x, piece.z]


func _refresh_list() -> void:
	_list.clear()
	var pieces: Array = game.arena.tile_pieces
	for i in pieces.size():
		_list.add_item("%d. %s" % [i + 1, _describe(pieces[i])])
	if _selected >= 0 and _selected < pieces.size():
		_list.select(_selected)
		_show_fields()
	else:
		_selected = -1
		_show_fields()


func _select(index: int) -> void:
	_selected = index
	_show_fields()


func _show_fields() -> void:
	for c in _fields.get_children():
		c.queue_free()
	if _selected < 0:
		game.arena.show_marker(null)
		return
	var piece: Dictionary = game.arena.tile_pieces[_selected]
	game.arena.show_marker(piece)
	for f in FIELDS.get(piece.type, []):
		_fields.add_child(_text(FIELD_NAMES[f]))
		var spin := SpinBox.new()
		spin.min_value = RANGES[f][0]
		spin.max_value = RANGES[f][1]
		spin.step = RANGES[f][2]
		spin.value = piece.get(f, 0.0)
		spin.custom_minimum_size.x = 120
		spin.value_changed.connect(_on_field.bind(f))
		_fields.add_child(spin)


func _on_field(value: float, field: String) -> void:
	if _selected < 0:
		return
	var piece: Dictionary = game.arena.tile_pieces[_selected]
	piece[field] = value
	_list.set_item_text(_selected, "%d. %s" % [_selected + 1, _describe(piece)])
	game.arena.show_marker(piece)
	_changed()


func _add_piece(id: int) -> void:
	var piece: Dictionary = NEW_PIECES[id][1].duplicate(true)
	piece.x = 0.0
	piece.z = 0.0
	piece.rot = 0.0
	game.arena.tile_pieces.append(piece)
	_selected = game.arena.tile_pieces.size() - 1
	_changed()
	_refresh_list()


func _duplicate_piece() -> void:
	if _selected < 0:
		return
	var piece: Dictionary = game.arena.tile_pieces[_selected].duplicate(true)
	piece.x += 2.0
	game.arena.tile_pieces.append(piece)
	_selected = game.arena.tile_pieces.size() - 1
	_changed()
	_refresh_list()


func _delete_piece() -> void:
	if _selected < 0:
		return
	game.arena.tile_pieces.remove_at(_selected)
	_selected = -1
	_changed()
	_refresh_list()


## Rebuild what you see straight away; redo the bot's paths once you stop changing things.
func _changed() -> void:
	game.arena.rebuild_tile(false)
	game.on_tile_rebuilt()
	_bake_in = BAKE_DELAY


func _rebuild_now() -> void:
	game.arena.rebuild_tile(true)
	game.on_tile_rebuilt()
	_bake_in = 0.0


# --- Saving ----------------------------------------------------------------

func _load_saved() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_DIR + "/" + file))
		if data is Dictionary and data.get("pieces") is Array:
			_saved[data.get("name", file.get_basename())] = data.pieces


## The tile as text: its name and every piece's numbers (positions with the spread worked in).
func _tile_json() -> String:
	var name := _name.text.strip_edges()
	return JSON.stringify({"name": name, "pieces": game.arena.tile_pieces_spread()}, "\t")


func _save() -> void:
	var name := _name.text.strip_edges()
	if name == "":
		game.hud.flash("Type a name for the tile first")
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := "%s/%s.json" % [SAVE_DIR, name.validate_filename()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		game.hud.flash("Couldn't save the tile")
		return
	file.store_string(_tile_json())
	file.close()
	_saved[name] = game.arena.tile_pieces_spread()
	_fill_tile_menu()
	game.hud.flash("Saved %s" % name)


func _copy() -> void:
	DisplayServer.clipboard_set(_tile_json())
	game.hud.flash("Tile numbers copied")

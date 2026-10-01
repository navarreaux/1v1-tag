extends Node3D
## The maps, built in code. Set `map_id` before adding the arena to the tree.
##
## Rotten Fields (map 0): a sunny subway yard laid out like Dead by Daylight's Rotten Fields. A grid of
## 16 m cells inside a stepped outer wall (96 x 128 m at its widest). Cells around the edge, at
## clock positions, hold tiles: wall pairs, T walls, a bent wall, the one long wall, and big train
## loops at 1, 7 and 10 o'clock. A shack sits in the very middle with a tile above and below it;
## the rest is sparse filler (shipping containers, lamp posts, container barricades).
## A very strong Runner building (the depot) sits in the top-left corner; both players start there.
## Every barricade stands in a gap between two solid things, so it can always be looped.
##
## The Last Stop (map 1): a compact 80 x 80 m abandoned roadside service station. A 5 x 5 grid of
## 16 m cells (plus one sticking out on the right) around a fixed 32 x 32 m service station: long
## walls at B and V, short walls at D, N and T, a shack at F, a trash can loop at R, and filler,
## scrap piles, drainage curbs and open lanes in the rest. The Runner starts inside the station.
##
## Every player builds the same map from this code, so nothing about it is sent over the network.

enum Map { ROTTEN_FIELDS, LAST_STOP, TILE_TEST }
const MAP_NAMES := ["Rotten Fields", "The Last Stop", "Tile Test"]

const Greybox := preload("res://scripts/greybox.gd")
const Barricade := preload("res://scripts/barricade.gd")
## Half the width of a trash can gap.
const GAP := Barricade.GAP_WIDTH / 2.0
const TUNING := preload("res://tuning.tres")

const CELL := 24.0
const RF_SCALE := 2.0 / 3.0
## The outer wall, going clockwise. Walls stand just outside these lines.
const OUTLINE := [Vector2(-48, -96), Vector2(24, -96), Vector2(24, -72), Vector2(48, -72), Vector2(48, -48),
	Vector2(72, -48), Vector2(72, 72), Vector2(48, 72), Vector2(48, 96), Vector2(-24, 96), Vector2(-24, 72),
	Vector2(-48, 72), Vector2(-48, 48), Vector2(-72, 48), Vector2(-72, -72), Vector2(-48, -72)]
const WALL_H := 2.6
const WALL_T := 0.4
const WINDOW_W := 1.4
const SILL_H := 0.9
const LINTEL_Y := 2.0

const FLOOR_COLOR := Color(0.4, 0.36, 0.32)  # gravel
const WALL_COLOR := Color(0.5, 0.56, 0.66)  # blue-grey concrete
const MAIN_COLOR := Color(0.75, 0.32, 0.22)  # red brick depot
const WINDOW_COLOR := Color(0.2, 0.5, 0.95)
const POLE_COLOR := Color(0.45, 0.47, 0.5)
const LAMP_COLOR := Color(1.0, 0.9, 0.4)
const RAIL_COLOR := Color(0.55, 0.55, 0.6)
const SLEEPER_COLOR := Color(0.38, 0.27, 0.18)
## Bright spray-paint colors for graffiti and containers.
const PAINT := [Color(1.0, 0.25, 0.6), Color(0.1, 0.85, 0.95), Color(0.5, 0.95, 0.2), Color(1.0, 0.85, 0.1),
	Color(0.6, 0.3, 1.0), Color(1.0, 0.5, 0.1), Color(0.2, 0.45, 1.0)]

## Rotten Fields: both players start at the depot in the top-left corner: the Runner inside, the
## Hunter about 22 m away facing it. (The Hunter also waits out the Runner's head start.)
const DEPOT := Vector3(-24, 0, -72)

enum Tile { T_WALL, L_WINDOW, L_BARRICADE, JUNGLE_GYM, SHACK, LONG_WALL, BARRICADE_LOOP, BENT_WALL,
	L_PAIR, TRAIN_LOOP }
## One tile per pictured cell: [tile, x, z, degrees]. Drawn on 24 m cells, then built at RF_SCALE (2/3) size.
## The long wall (two walls with a window between) is very strong, so there is only one.
const TILES := [
	[Tile.L_PAIR, 6, -72, 0],  # 12 o'clock
	[Tile.TRAIN_LOOP, 24, -48, -45],  # 1
	[Tile.L_PAIR, 48, 0, 90],  # 3
	[Tile.BENT_WALL, 48, 48, 200],  # 4
	[Tile.LONG_WALL, 0, 72, 0],  # 6
	[Tile.TRAIN_LOOP, -24, 48, 45],  # 7
	[Tile.T_WALL, -48, 0, 90],  # 9
	[Tile.TRAIN_LOOP, -48, -48, 45],  # 10
	[Tile.SHACK, 0, 0, 0],  # the middle
	[Tile.T_WALL, 0, -24, 90],  # top mid
	[Tile.BARRICADE_LOOP, 0, 24, 30],  # bottom mid
]
## Filler in the other cells: [x, z, degrees].
const ROCK_PALLETS := [[-24, -26, 45], [48, -22, 0], [-46, 24, 90], [24, 22, -45], [-62, 0, 90],
	[62, 40, 90], [24, 84, 0]]
const ROCKS := [[-21, -45], [27, -21], [-26, 3], [22, 5], [-20, 27], [26, 45], [-60, -20], [3, 50], [54, 62],
	[-64, -32], [64, 16], [64, -36], [-64, 32], [36, 86], [-40, -86], [-36, 62], [14, -86]]
const LAMPS := [[0, -46], [50, 26], [24, 72], [-44, -28], [18, 10], [-28, -50], [-12, -12], [12, 12],
	[-12, 12], [12, -12], [-46, 46], [30, -64], [-64, 0], [64, 0], [10, 88], [-10, -88]]

## The Last Stop.
const LS_OUTLINE := [Vector2(-40, -40), Vector2(40, -40), Vector2(40, -8), Vector2(56, -8), Vector2(56, 8),
	Vector2(40, 8), Vector2(40, 40), Vector2(-40, 40)]
## The service station's middle: it fills cells C, D, H (2 x 2 cells).
const LS_STATION := Vector3(8, 0, -8)

## Which map to build, and where each player starts on it.
var map_id := Map.ROTTEN_FIELDS
var runner_spawn := Vector3.ZERO
var runner_spawn_yaw := 0.0
var hunter_spawn := Vector3.ZERO
var hunter_spawn_yaw := 0.0

## Barricade nodes, in a fixed order so peers can refer to them by index.
var barricades: Array = []
## One transform per window: origin = middle of the window at floor level, basis.z = direction you vault.
var windows: Array[Transform3D] = []
## Per window: Runner vaults so far, and seconds left blocked (0 = open).
var window_vaults: Array[int] = []
var window_blocked: Array[float] = []
## Per window: seconds since its last Runner vault (the count starts over after a long gap).
var window_since: Array[float] = []
var _window_blockers: Array[Node3D] = []
## Points worth running to (both sides of every window and barricade); used by the bot.
var loop_spots: Array[Vector3] = []

## Walkable-area map used by the bot to find paths. All solid geometry lives under it.
var _nav: NavigationRegion3D
## A second walkable-area map where every barricade is down. The bot Hunter uses it to work out
## how far it is around a dropped barricade, to choose between breaking it and running around.
var nav_blocked_map: RID
var _wall_color := WALL_COLOR
## Where building helpers put solid things (part of the walkable-area bake) and looks-only things.
## Normally the nav region and the arena; Tile Test points both at its tile node.
var _solid: Node3D
var _decor: Node3D
## Tile Test: an Array while recording a preset's pieces (see tile_preset), otherwise null.
var _record = null
## Nav links made by the last bake, freed when baking again.
var _nav_links: Array = []
var _blocked_region: NavigationRegion3D
## Same seed on every computer, so graffiti and container colors match (they're only looks anyway).
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build_environment()
	_rng.seed = 1234
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	_solid = _nav
	_decor = self
	if map_id == Map.LAST_STOP:
		_build_last_stop()
	elif map_id == Map.TILE_TEST:
		_build_tile_test()
	else:
		_build_rotten_fields()
	_bake_navigation()


func _build_rotten_fields() -> void:
	# The layout below is drawn on 24 m cells; it's built at 2/3 size (16 m cells, 96 x 128 m) so
	# it's about as packed as The Last Stop. Tiles keep their own size; only positions shrink.
	var k := RF_SCALE
	var outline := []
	for p: Vector2 in OUTLINE:
		outline.append(p * k)
	_outline(outline, Vector3.ZERO, Vector2(100, 132))
	_depot(_at(DEPOT.x * k, DEPOT.z * k, 0))
	runner_spawn = DEPOT * k + Vector3(7.25, 0, 0)
	runner_spawn_yaw = PI  # facing along the corridor
	hunter_spawn = Vector3(4, 0, -30)  # about 20 m away
	hunter_spawn_yaw = 0.838  # facing the depot
	for t in TILES:
		_tile(t[0], _at(t[1] * k, t[2] * k, t[3]))
	for f in ROCK_PALLETS:
		_rock_pallet(_at(f[0] * k, f[1] * k, f[2]))
	for r in ROCKS:
		_rock(Vector3(r[0] * k, 0, r[1] * k))
	for l in LAMPS:
		_lamp(Vector3(l[0] * k, 0, l[1] * k))


## The floor (a `floor_size` rectangle centered on `center`) and a solid wall around `outline`.
func _outline(outline: Array, center: Vector3, floor_size: Vector2) -> void:
	Greybox.box(_nav, Transform3D(Basis(), center + Vector3(0, -0.5, 0)), Vector3(floor_size.x, 1, floor_size.y), FLOOR_COLOR)
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var along := (b - a).normalized()
		var out := Vector2(along.y, -along.x)  # outward, since the outline runs clockwise
		var mid := (a + b) / 2.0 + out * 0.5
		var xf := Transform3D(Basis(Vector3.UP, -along.angle()), Vector3(mid.x, 1.5, mid.y))
		Greybox.box(_nav, xf, Vector3(a.distance_to(b) + 1.0, 3, 1), WALL_COLOR)


# --- Tile Test -------------------------------------------------------------

## Tile Test is one small walled arena with a single tile in the middle. Every tile is a list of
## simple pieces (walls, windows, trash cans, containers, blocks, a train car, lamps), so the tile
## builder panel can spawn any preset, then move, resize, add and remove its pieces live.
const TEST_SIZE := 64.0
## Presets in the tile menu, matched by name in tile_preset().
const TEST_TILES := ["T Wall", "L Window", "L Trash Can", "Jungle Gym", "Shack", "Long Wall",
	"Trash Can Loop", "Bent Wall", "L Pair", "Train Loop", "Short Wall", "Filler Trash Can",
	"Container", "Scrap Yard", "Drainage", "Lamp", "Depot", "Service Station"]
## The tile in the middle of the arena, as pieces: dictionaries with "type", "x", "z", "rot"
## (degrees) and per-type sizes. See _build_piece().
var tile_pieces: Array = []
## Multiplies every piece's position (not its size): spreads a tile out or squeezes it together.
var tile_spread := 1.0
var _tile_node: Node3D  # everything the tile builds, so it can be cleared
var _marker: MeshInstance3D  # highlights the piece being edited


func _build_tile_test() -> void:
	var h := TEST_SIZE / 2.0
	_outline([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)], Vector3.ZERO,
		Vector2(TEST_SIZE + 2, TEST_SIZE + 2))
	runner_spawn = Vector3(0, 0, h - 6)
	runner_spawn_yaw = 0.0  # facing the middle
	hunter_spawn = Vector3(0, 0, -h + 6)
	hunter_spawn_yaw = PI
	_tile_node = Node3D.new()
	_nav.add_child(_tile_node)
	_marker = MeshInstance3D.new()
	_marker.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.1, 0.35)
	mat.no_depth_test = true
	_marker.material_override = mat
	_marker.visible = false
	add_child(_marker)
	tile_pieces = tile_preset("T Wall")
	rebuild_tile(false)  # _ready bakes the navigation right after


## The pieces of a preset tile, centred on the arena.
func tile_preset(name: String) -> Array:
	_record = []
	var o := Transform3D.IDENTITY
	match name:
		"T Wall": _t_wall(o)
		"L Window": _l_window(o)
		"L Trash Can": _l_barricade(o)
		"Jungle Gym": _jungle_gym(o)
		"Shack": _shack(o)
		"Long Wall": _long_wall(o)
		"Trash Can Loop": _barricade_loop(o)
		"Bent Wall": _bent_wall(o)
		"L Pair": _l_pair(o)
		"Train Loop": _train_loop(_at(-1.75, 0, 0))  # the car is off-centre in its tile
		"Short Wall": _short_wall(o)
		"Filler Trash Can": _rock_pallet(o)
		"Container": _container(o, 5.5)
		"Scrap Yard": _scrap_yard(o)
		"Drainage": _drainage(o)
		"Lamp": _lamp(Vector3.ZERO)
		"Depot": _depot(o)
		"Service Station": _service_station(o)
	var pieces: Array = _record
	_record = null
	return pieces


## Clears the tile and builds tile_pieces again. Bake = also redo the bot's walkable-area maps
## (slower; the builder waits until you stop dragging).
func rebuild_tile(bake := true) -> void:
	for b in barricades:
		b.free()
	barricades.clear()
	windows.clear()
	window_vaults.clear()
	window_blocked.clear()
	window_since.clear()
	_window_blockers.clear()
	for c in _tile_node.get_children():
		c.free()
	_rng.seed = 99  # same container colors every rebuild
	_solid = _tile_node
	_decor = _tile_node
	for piece in tile_pieces:
		_build_piece(piece)
	_solid = _nav
	_decor = self
	if bake:
		_bake_navigation()


## The pieces as they'd be saved: with the spread worked into their positions.
func tile_pieces_spread() -> Array:
	var out := []
	for piece in tile_pieces:
		var q: Dictionary = piece.duplicate()
		q.x = snappedf(q.x * tile_spread, 0.01)
		q.z = snappedf(q.z * tile_spread, 0.01)
		out.append(q)
	return out


## Highlights one piece (or nothing, for null) with a see-through yellow box.
func show_marker(piece) -> void:
	if piece == null:
		_marker.visible = false
		return
	var size := Vector3(1, 1, 1)
	var lift := 0.0
	match piece.type:
		"wall": size = Vector3(piece.length, piece.get("height", WALL_H), WALL_T)
		"window": size = Vector3(WINDOW_W, WALL_H, WALL_T)
		"can": size = Vector3(Barricade.GAP_WIDTH, 1.8, 0.8)
		"container": size = Vector3(piece.length, 2.4, 1.4)
		"train": size = Vector3(14, 3.5, 3)
		"lamp": size = Vector3(0.4, 4.5, 0.4)
		"block":
			size = Vector3(piece.sx, piece.sy, piece.sz)
			lift = piece.get("y", 0.0)
	(_marker.mesh as BoxMesh).size = size + Vector3(0.2, 0.2, 0.2)
	_marker.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(piece.get("rot", 0.0))),
		Vector3(piece.x * tile_spread, lift + size.y / 2.0, piece.z * tile_spread))
	_marker.visible = true


## Builds one piece (see tile_pieces).
func _build_piece(piece: Dictionary) -> void:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(piece.get("rot", 0.0))),
		Vector3(piece.x * tile_spread, 0, piece.z * tile_spread))
	match piece.type:
		"wall":
			_wall_color = Color.html(piece.get("color", WALL_COLOR.to_html(false)))
			_wall(xf, piece.length, piece.get("height", WALL_H))
			_wall_color = WALL_COLOR
		"window": _window(xf, 0, 0)
		"can": _barricade(xf, 0, 0)
		"container": _container(xf, piece.length)
		"lamp": _lamp(xf.origin)
		"train": _train(xf)
		"block":
			_block(xf.translated(Vector3(0, piece.get("y", 0.0), 0)), Vector3(piece.sx, piece.sy, piece.sz),
				Color.html(piece.get("color", "8090a8")), piece.get("solid", true))


## While a preset is being recorded, the building helpers below add a piece here instead of building.
func _rec(type: String, xf: Transform3D, extra := {}) -> void:
	var piece := {"type": type, "x": snappedf(xf.origin.x, 0.01), "z": snappedf(xf.origin.z, 0.01),
		"rot": snappedf(rad_to_deg(xf.basis.get_euler().y), 0.1)}
	piece.merge(extra)
	_record.append(piece)


# --- The Last Stop ---------------------------------------------------------

## The middle of a cell: columns A..E are 0..4 left to right (5 is the extra cell M sticks out
## into), rows are 0..4 top to bottom.
func _cell(col: int, row: int, degrees := 0.0) -> Transform3D:
	return _at(-32.0 + col * 16.0, -32.0 + row * 16.0, degrees)


func _build_last_stop() -> void:
	_outline(LS_OUTLINE, Vector3(8, 0, 0), Vector2(98, 82))
	runner_spawn = LS_STATION + Vector3(-10, 0, 6)
	runner_spawn_yaw = PI / 2.0
	hunter_spawn = Vector3(-32, 0, 0)  # J, an open lane
	hunter_spawn_yaw = -PI / 2.0  # facing the station
	_service_station(_at(LS_STATION.x, LS_STATION.z, 0))
	# Strong loops on opposite edges, medium ones spread out, one shack, one loop tile.
	_long_wall(_cell(1, 0, 0))  # B
	_long_wall(_cell(3, 4, 180))  # V
	_short_wall(_cell(3, 0, 0))  # D
	_short_wall(_cell(0, 3, 90))  # N
	_short_wall(_cell(1, 4, 180))  # T
	_shack(_cell(0, 1, 90))  # F
	_rock_pallet(_cell(4, 3, 30))  # R: a loop with an unsafe trash can
	# Filler: a weak trash can between two short containers, plus a container for cover.
	for f in [[1, 1, 60], [4, 1, -30], [1, 3, -60], [3, 3, 20]]:  # G, I, O, Q
		var cell := _cell(f[0], f[1], f[2])
		_rock_pallet(cell * Transform3D(Basis(), Vector3(0, 0, -2.5)))
		_container(cell * Transform3D(Basis(Vector3.UP, 0.3), Vector3(1.5, 0, 3.5)), 4.0)
	# Scrap yards: piles of containers that break sight lines (no trash cans).
	for c in [[2, 0, 15], [1, 2, -20], [4, 2, 75], [2, 3, 40]]:  # C, K, L, P
		_scrap_yard(_cell(c[0], c[1], c[2]))
	# Drainage in the corners: low curbs you run around (they don't block sight).
	for d in [[0, 0, 45], [4, 0, -45], [0, 4, -45], [4, 4, 45]]:  # A, E, S, W
		_drainage(_cell(d[0], d[1], d[2]))
	# Dead space (J, M, U) stays open: clear escape lanes, just a lamp each.
	for l in [[-32, 6], [48, 0], [6, 32], [-16, -16], [24, 16], [-24, 24]]:
		_lamp(Vector3(l[0], 0, l[1]))


## The service station (32 x 32 m): a fenced forecourt with entrances west and south, a pump
## island under a canopy in the middle, and a shop in the north-east corner with a trash can
## between it and the fence. One window in the east fence is the only vault.
func _service_station(tile: Transform3D) -> void:
	var h := 15.0
	var w := WINDOW_W / 2.0
	var e := WALL_T / 2.0
	# Fence: north and east solid (window in the east), west and south with 6 m entrances.
	_wall_x(tile, -h - e, h + e, -h)
	_wall_z(tile, -h + e, 4 - w, h)
	_window_z(tile, 4, h)
	_wall_z(tile, 4 + w, h - e, h)
	_wall_z(tile, -h + e, -3, -h)
	_wall_z(tile, 3, h - e, -h)
	_wall_x(tile, -h - e, -3, h)
	_wall_x(tile, 3, h + e, h)
	# The shop, with a trash can in the gap between it and the east fence.
	_wall_color = MAIN_COLOR
	var gap_x := h - WALL_T / 2.0 - GAP
	var shop_x1 := gap_x - GAP
	var shop := _block(tile * Transform3D(Basis(), Vector3(shop_x1 - 4.5, 0, -10)), Vector3(9, 3.2, 7), MAIN_COLOR)
	if shop:
		Greybox.box(shop, Transform3D(Basis(), Vector3(0, 1.9, 0)), Vector3(9.4, 0.4, 7.4), MAIN_COLOR.darkened(0.3), false)
		Greybox.box(shop, Transform3D(Basis(), Vector3(-1, 0.2, 3.52)), Vector3(4, 1.2, 0.05), WINDOW_COLOR, false)
		Greybox.box(shop, Transform3D(Basis(), Vector3(0, 2.4, 3.5)), Vector3(5, 0.7, 0.2), PAINT[3], false)
	_wall_color = WALL_COLOR
	_barricade(tile, gap_x, -10, 90)
	# Pump island: low and solid (you can see over it), with pumps on top, under a canopy.
	_block(tile * Transform3D(Basis(), Vector3(0, 0, 2)), Vector3(10, 1.0, 2.4), Color(0.75, 0.75, 0.72))
	for x in [-3.0, 3.0]:
		var pump := _block(tile * Transform3D(Basis(), Vector3(x, 1.0, 2)), Vector3(0.9, 1.6, 0.6), Color(0.9, 0.2, 0.2))
		if pump:
			Greybox.box(pump, Transform3D(Basis(), Vector3(0, 0.3, 0.31)), Vector3(0.6, 0.4, 0.02), Color(0.15, 0.2, 0.3), false)
	for p in [Vector3(-7, 0, -2), Vector3(7, 0, -2), Vector3(-7, 0, 6), Vector3(7, 0, 6)]:
		_block(tile * Transform3D(Basis(), p), Vector3(0.5, 4.8, 0.5), POLE_COLOR)
	_block(tile * Transform3D(Basis(), Vector3(0, 4.75, 2)), Vector3(17, 0.5, 11), Color(0.95, 0.95, 0.95), false)
	_block(tile * Transform3D(Basis(), Vector3(0, 4.875, 2)), Vector3(17.1, 0.25, 11.1), PAINT[0], false)


## A medium loop: a 6 m wall with a window, a trash can gap, then a short post, with a short
## return at the far end to break sight.
func _short_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -5, -2 - w, 0)
	_window(tile, -2, 0)
	_wall_x(tile, -2 + w, 2 - GAP, 0)
	_barricade(tile, 2, 0)
	_wall_x(tile, 2 + GAP, 4.5, 0)
	_wall_z(tile, WALL_T / 2.0, 2.5, -5)


## A scrap yard: a jumble of containers that blocks sight lines. No trash cans.
func _scrap_yard(tile: Transform3D) -> void:
	_container(tile * Transform3D(Basis(Vector3.UP, 0.2), Vector3(-2.5, 0, -2)), 5.0)
	_container(tile * Transform3D(Basis(Vector3.UP, 1.4), Vector3(3, 0, 1)), 4.0)
	_container(tile * Transform3D(Basis(Vector3.UP, -0.5), Vector3(-1.5, 0, 3.5)), 3.0)


## Drainage: two low concrete curbs along a dry channel. Low cover: you see over them but run around.
func _drainage(tile: Transform3D) -> void:
	for z in [-1.6, 1.6]:
		_block(tile * Transform3D(Basis(), Vector3(0, 0, z)), Vector3(9, 0.6, 0.6), WALL_COLOR.darkened(0.15))
	_block(tile, Vector3(9, 0.04, 2.6), Color(0.3, 0.33, 0.36), false)


# --- Rotten Fields tiles (also used by The Last Stop) -----------------------


func _bake_navigation() -> void:
	for link in _nav_links:
		link.free()
	_nav_links.clear()
	loop_spots.clear()
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Greybox.WORLD_LAYER
	nm.agent_radius = 0.4
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	_nav.navigation_mesh = nm
	# Trash cans aren't part of the bake, so their gaps count as open. Paths run through the middle
	# of a gap and bodies slide around a standing can.
	_nav.bake_navigation_mesh(false)
	# Window vaults are shortcuts the path finder may use; they cost extra because vaulting is slow.
	for w in windows:
		var link := NavigationLink3D.new()
		link.start_position = w.origin + w.basis.z * 1.0
		link.end_position = w.origin - w.basis.z * 1.0
		link.travel_cost = 3.0
		link.navigation_layers = 2  # so a bot can choose to ignore windows
		_nav.add_child(link)
		_nav_links.append(link)
	_bake_blocked_map(nm)
	for xf in windows:
		loop_spots.append(xf.origin + xf.basis.z * 2.0)
		loop_spots.append(xf.origin - xf.basis.z * 2.0)
	for b in barricades:
		loop_spots.append(b.to_global(Vector3(0, 0, 2.0)))
		loop_spots.append(b.to_global(Vector3(0, 0, -2.0)))


func _bake_blocked_map(main_mesh: NavigationMesh) -> void:
	if not nav_blocked_map.is_valid():
		nav_blocked_map = NavigationServer3D.map_create()
		NavigationServer3D.map_set_cell_size(nav_blocked_map, main_mesh.cell_size)
		NavigationServer3D.map_set_cell_height(nav_blocked_map, main_mesh.cell_height)
		NavigationServer3D.map_set_active(nav_blocked_map, true)
		_blocked_region = NavigationRegion3D.new()
		add_child(_blocked_region)
		_blocked_region.set_navigation_map(nav_blocked_map)
	var region := _blocked_region
	var nm: NavigationMesh = main_mesh.duplicate()
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"nav_blocked"
	region.navigation_mesh = nm
	_nav.add_to_group(&"nav_blocked")
	for b in barricades:
		b.add_to_group(&"nav_blocked")
		b.set_state(Barricade.State.DOWN)
	region.bake_navigation_mesh(false)
	for b in barricades:
		b.set_state(Barricade.State.UP)
	for w in windows:
		var link := NavigationLink3D.new()
		link.start_position = w.origin + w.basis.z * 1.0
		link.end_position = w.origin - w.basis.z * 1.0
		link.travel_cost = 3.0
		link.navigation_layers = 2
		region.add_child(link)
		link.set_navigation_map(nav_blocked_map)
		_nav_links.append(link)


func _exit_tree() -> void:
	if nav_blocked_map.is_valid():
		NavigationServer3D.free_rid(nav_blocked_map)


## Puts every barricade back up (start of each round).
func reset() -> void:
	for b in barricades:
		b.set_state(Barricade.State.UP)
	for i in windows.size():
		window_vaults[i] = 0
		window_blocked[i] = 0.0
		window_since[i] = 0.0


func is_window_blocked(i: int) -> bool:
	return window_blocked[i] > 0.0


## Counts a Runner vault. Too many on the same window and it's blocked for a while,
## so the Runner can't loop one window forever.
func note_window_vault(i: int) -> void:
	# 30 s or more between two vaults and the count starts over.
	if window_since[i] >= TUNING.window_block_reset_time:
		window_vaults[i] = 0
	window_since[i] = 0.0
	window_vaults[i] += 1
	if window_vaults[i] >= TUNING.window_block_vaults:
		window_vaults[i] = 0
		window_blocked[i] = TUNING.window_block_time


func _process(delta: float) -> void:
	for i in windows.size():
		window_blocked[i] = maxf(0.0, window_blocked[i] - delta)
		window_since[i] += delta
		_window_blockers[i].visible = window_blocked[i] > 0.0


func _at(x: float, z: float, degrees: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3(x, 0, z))


## A straight wall in tile space, running along X from x0 to x1 at depth z.
func _wall_x(tile: Transform3D, x0: float, x1: float, z: float) -> void:
	_wall(tile * Transform3D(Basis(), Vector3((x0 + x1) / 2.0, 0, z)), x1 - x0)


## A straight wall in tile space, running along Z from z0 to z1 at x.
func _wall_z(tile: Transform3D, z0: float, z1: float, x: float) -> void:
	_wall(tile * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x, 0, (z0 + z1) / 2.0)), z1 - z0)


## A wall `length` long along local X, standing on the ground at `xf`.
func _wall(xf: Transform3D, length: float, height := WALL_H) -> void:
	if _record != null:
		_rec("wall", xf, {"length": snappedf(length, 0.01), "height": height, "color": _wall_color.to_html(false)})
		return
	var mid := xf * Transform3D(Basis(), Vector3(0, height / 2.0, 0))
	Greybox.box(_solid, mid, Vector3(length, height, WALL_T), _wall_color)
	_trim(mid, length, height)
	if height >= 2.0:
		_graffiti(mid, length)


## A darker cap along the top of a wall, so walls look finished rather than like plain blocks.
func _trim(xf: Transform3D, length: float, height := WALL_H) -> void:
	Greybox.box(_decor, xf * Transform3D(Basis(), Vector3(0, height / 2.0, 0)), Vector3(length + 0.06, 0.14, WALL_T + 0.12), _wall_color.darkened(0.3), false)


## Splashes of spray paint on both faces of a wall segment `length` long (`xf` is its middle).
func _graffiti(xf: Transform3D, length: float) -> void:
	if length < 1.5:
		return
	for i in _rng.randi_range(1, 2):
		var w := minf(length * 0.8, _rng.randf_range(1.0, 2.6))
		var h := _rng.randf_range(0.4, 1.1)
		var x := _rng.randf_range(-(length - w) / 2.0, (length - w) / 2.0)
		var y := _rng.randf_range(-0.6, 0.5)
		var c: Color = PAINT[_rng.randi() % PAINT.size()]
		Greybox.box(_decor, xf * Transform3D(Basis(), Vector3(x, y, 0)), Vector3(w, h, WALL_T + 0.02), c, false)
		# A smaller tag in another color on top.
		var c2: Color = PAINT[_rng.randi() % PAINT.size()]
		Greybox.box(_decor, xf * Transform3D(Basis(), Vector3(x + w * 0.15, y + h * 0.1, 0)), Vector3(w * 0.5, h * 0.4, WALL_T + 0.04), c2, false)


## A window opening centered at x along a wall at depth z (sill below, lintel above).
func _window(tile: Transform3D, x: float, z: float) -> void:
	if _record != null:
		_rec("window", tile * Transform3D(Basis(), Vector3(x, 0, z)))
		return
	var size_sill := Vector3(WINDOW_W, SILL_H, WALL_T)
	var size_top := Vector3(WINDOW_W, WALL_H - LINTEL_Y, WALL_T)
	Greybox.box(_solid, tile * Transform3D(Basis(), Vector3(x, SILL_H / 2.0, z)), size_sill, WINDOW_COLOR)
	Greybox.box(_solid, tile * Transform3D(Basis(), Vector3(x, (LINTEL_Y + WALL_H) / 2.0, z)), size_top, WINDOW_COLOR)
	windows.append(tile * Transform3D(Basis(), Vector3(x, 0, z)))
	window_vaults.append(0)
	window_blocked.append(0.0)
	window_since.append(0.0)
	var blocker := Greybox.box(_decor, tile * Transform3D(Basis(), Vector3(x, (SILL_H + LINTEL_Y) / 2.0, z)), Vector3(WINDOW_W, LINTEL_Y - SILL_H, 0.05), Color(0.8, 0.1, 0.1), false)
	blocker.visible = false
	_window_blockers.append(blocker)


## A window in a wall that runs along Z, centered at z.
func _window_z(tile: Transform3D, z: float, x: float) -> void:
	_window(tile * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x, 0, z)), 0, 0)


## A trash can standing in a gap (Barricade.GAP_WIDTH wide) centered at (x, z). At 0 degrees the gap runs along X.
func _barricade(tile: Transform3D, x: float, z: float, degrees := 0.0) -> void:
	if _record != null:
		_rec("can", tile * Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3(x, 0, z)))
		return
	var b := Barricade.new()
	b.transform = tile * Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3(x, 0, z))
	add_child(b)
	barricades.append(b)


## A shipping container (the "rocks" of this map): long and thin, too tall to see over.
func _rock(pos: Vector3) -> void:
	_container(Transform3D(Basis(Vector3.UP, pos.x * 0.3 + pos.z * 0.1), pos), 5.5)


## A container `length` m long along X, 1.4 m wide, painted a random bright color with dark ribs.
func _container(xf: Transform3D, length: float) -> void:
	if _record != null:
		_rec("container", xf, {"length": length})
		return
	var c: Color = PAINT[_rng.randi() % PAINT.size()]
	var body := Greybox.box(_solid, xf * Transform3D(Basis(), Vector3(0, 1.2, 0)), Vector3(length, 2.4, 1.4), c)
	var x := -length / 2.0 + 0.4
	while x < length / 2.0 - 0.2:
		Greybox.box(body, Transform3D(Basis(), Vector3(x, 0, 0)), Vector3(0.12, 2.3, 1.44), c.darkened(0.3), false)
		x += 0.8
	Greybox.box(body, Transform3D(Basis(), Vector3(0, 1.17, 0)), Vector3(length + 0.04, 0.1, 1.44), c.darkened(0.45), false)


## A plain box `size` big, its bottom at `xf` (so xf's height lifts it off the ground). Solid boxes
## block movement; others are looks only. Returns the box, or null while recording a preset.
func _block(xf: Transform3D, size: Vector3, color: Color, solid := true) -> Node3D:
	if _record != null:
		_rec("block", xf, {"y": snappedf(xf.origin.y, 0.01), "sx": size.x, "sy": size.y, "sz": size.z,
			"color": color.to_html(false), "solid": solid})
		return null
	return Greybox.box(_solid if solid else _decor, xf * Transform3D(Basis(), Vector3(0, size.y / 2.0, 0)), size, color, solid)


## A street lamp: a thin pole with a glowing head.
func _lamp(pos: Vector3) -> void:
	if _record != null:
		_rec("lamp", Transform3D(Basis(), pos))
		return
	Greybox.box(_solid, Transform3D(Basis(), pos + Vector3(0, 2.25, 0)), Vector3(0.25, 4.5, 0.25), POLE_COLOR)
	Greybox.box(_decor, Transform3D(Basis(), pos + Vector3(0, 4.5, -0.3)), Vector3(0.3, 0.15, 0.8), POLE_COLOR, false)
	var head := Greybox.box(_decor, Transform3D(Basis(), pos + Vector3(0, 4.4, -0.55)), Vector3(0.35, 0.1, 0.35), LAMP_COLOR, false)
	head.material_override = head.material_override.duplicate()
	head.material_override.emission_enabled = true
	head.material_override.emission = LAMP_COLOR


## A parked train car on a short stretch of track. Too tall to vault; you run around it.
func _train(tile: Transform3D) -> void:
	if _record != null:
		_rec("train", tile)
		return
	# Track: two rails on sleepers, flat on the ground (just looks).
	for x in range(-11, 12, 1):
		Greybox.box(_decor, tile * Transform3D(Basis(), Vector3(x, 0.03, 0)), Vector3(0.25, 0.06, 2.6), SLEEPER_COLOR, false)
	for z in [-0.75, 0.75]:
		Greybox.box(_decor, tile * Transform3D(Basis(), Vector3(0, 0.09, z)), Vector3(23, 0.08, 0.1), RAIL_COLOR, false)
	var c: Color = PAINT[_rng.randi() % PAINT.size()]
	var car := Greybox.box(_solid, tile * Transform3D(Basis(), Vector3(0, 1.75, 0)), Vector3(14, 3.5, 3.0), Color(0.92, 0.92, 0.94))
	Greybox.box(car, Transform3D(Basis(), Vector3(0, -0.8, 0)), Vector3(14.02, 0.5, 3.02), c, false)
	Greybox.box(car, Transform3D(Basis(), Vector3(0, 0.55, 0)), Vector3(13.4, 0.8, 3.02), Color(0.15, 0.2, 0.3), false)
	Greybox.box(car, Transform3D(Basis(), Vector3(0, 1.8, 0)), Vector3(13.8, 0.12, 2.8), Color(0.6, 0.62, 0.66), false)
	# Graffiti on the sides.
	_graffiti(tile * Transform3D(Basis(), Vector3(0, 1.1, 0)).scaled_local(Vector3(1, 1, 3.0 / WALL_T)), 12.0)


func _tile(kind: Tile, tile: Transform3D) -> void:
	match kind:
		Tile.T_WALL: _t_wall(tile)
		Tile.L_WINDOW: _l_window(tile)
		Tile.L_BARRICADE: _l_barricade(tile)
		Tile.JUNGLE_GYM: _jungle_gym(tile)
		Tile.SHACK: _shack(tile)
		Tile.LONG_WALL: _long_wall(tile)
		Tile.BARRICADE_LOOP: _barricade_loop(tile)
		Tile.BENT_WALL: _bent_wall(tile)
		Tile.L_PAIR: _l_pair(tile)
		Tile.TRAIN_LOOP: _train_loop(tile)


## The depot: the strongest Runner building, in a corner. Inside, a corridor runs all the way
## around a long solid block, so the Runner can loop it. A barricade across the west corridor makes
## the loop very safe until the Hunter breaks it. Two doors and two windows lead outside.
func _depot(tile: Transform3D) -> void:
	_wall_color = MAIN_COLOR
	var w := WINDOW_W / 2.0
	var e := WALL_T / 2.0
	# North wall with a door; south wall with a door and a window; east wall with a window.
	_wall_x(tile, -9 - e, 5, -4.5)
	_wall_x(tile, 7, 9 + e, -4.5)
	_wall_x(tile, -9 - e, -7.5, 4.5)
	_wall_x(tile, -5.5, 4 - w, 4.5)
	_window(tile, 4, 4.5)
	_wall_x(tile, 4 + w, 9 + e, 4.5)
	_wall_z(tile, -4.5 + e, 4.5 - e, -9)
	_wall_z(tile, -4.5 + e, -w, 9)
	_window_z(tile, 0, 9)
	_wall_z(tile, w, 4.5 - e, 9)
	# The long solid middle block.
	_block(tile, Vector3(11, WALL_H, 2.5), MAIN_COLOR.darkened(0.15))
	# The barricade across the west corridor, between the outer wall and the block.
	_wall_x(tile, -9 + e, -7.25 - GAP, 0)
	_barricade(tile, -7.25, 0)
	_wall_x(tile, -7.25 + GAP, -5.5, 0)
	_wall_color = WALL_COLOR


## A T: a long wall with a window, and a stem coming off its middle with a barricade in it.
func _t_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -7.5, -3.5 - w, -3.5)
	_window(tile, -3.5, -3.5)
	_wall_x(tile, -3.5 + w, 7.5, -3.5)
	_wall_z(tile, -3.5 + WALL_T / 2.0, -GAP, 0)
	_barricade(tile, 0, 0, 90)
	_wall_z(tile, GAP, 3.5, 0)


## A long L with a window in its long side.
func _l_window(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -8, -2 - w, -3.5)
	_window(tile, -2, -3.5)
	_wall_x(tile, -2 + w, 3.5 + WALL_T / 2.0, -3.5)
	_wall_z(tile, -3.5 + WALL_T / 2.0, 1.5, 3.5)


## A long L with a barricade in its short side.
func _l_barricade(tile: Transform3D) -> void:
	_wall_x(tile, -8.5, 2.5 + WALL_T / 2.0, -3.5)
	_wall_z(tile, -3.5 + WALL_T / 2.0, 0.5 - GAP, 2.5)
	_barricade(tile, 2.5, 0.5, 90)
	_wall_z(tile, 0.5 + GAP, 3.0, 2.5)


## A jungle gym: two Ls facing each other around a long 11 x 5 m rectangle. One has a window and
## a barricade (between the L and a short wall); the other is plain.
func _jungle_gym(tile: Transform3D) -> void:
	var hx := 5.5
	var hz := 2.5
	var w := WINDOW_W / 2.0
	var e := WALL_T / 2.0
	_wall_x(tile, -hx - e, -2.5 - w, -hz)
	_window(tile, -2.5, -hz)
	_wall_x(tile, -2.5 + w, 2.5 - GAP, -hz)
	_barricade(tile, 2.5, -hz)
	_wall_x(tile, 2.5 + GAP, hx + e, -hz)
	_wall_z(tile, -hz + e, 0.5, -hx)
	_wall_x(tile, -1.5, hx + e, hz)
	_wall_z(tile, -0.5, hz - e, hx)


## A shack: a long 8 x 4 m room with a doorway and a vault window, and a barricade beside it
## between the shack wall and a short post.
func _shack(tile: Transform3D) -> void:
	var hx := 4.0
	var hz := 2.0
	var w := WINDOW_W / 2.0
	_wall_x(tile, -hx, -w, -hz)
	_window(tile, 0, -hz)
	_wall_x(tile, w, hx, -hz)
	_wall_x(tile, -hx, -1.1, hz)
	_wall_x(tile, 1.1, hx, hz)
	_wall_z(tile, -hz - WALL_T / 2.0, hz + WALL_T / 2.0, -hx)
	_wall_z(tile, -hz - WALL_T / 2.0, hz + WALL_T / 2.0, hx)
	_barricade(tile, hx + WALL_T / 2.0 + GAP, hz)
	_wall_z(tile, hz - 1, hz + 1, hx + WALL_T + 2.0 * GAP)


## A long wall with a window and a barricade, with side walls to break line of sight.
func _long_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -7, -w, 0)
	_window(tile, 0, 0)
	_wall_x(tile, w, 5.2 - GAP, 0)
	_barricade(tile, 5.2, 0)
	_wall_x(tile, 5.2 + GAP, 7, 0)
	_wall_z(tile, WALL_T / 2.0, 2.5, -7)
	_wall_z(tile, -2.5, -WALL_T / 2.0, 7)


## A wall with a barricade in the middle and side walls at both ends.
func _barricade_loop(tile: Transform3D) -> void:
	_wall_x(tile, -7, -GAP, 0)
	_barricade(tile, 0, 0)
	_wall_x(tile, GAP, 7, 0)
	_wall_z(tile, -2.5, -WALL_T / 2.0, -7)
	_wall_z(tile, WALL_T / 2.0, 2.5, 7)


## A long wall bent in the middle: a straight run, a barricade at the bend, then a run angled
## 30 degrees away with a window in it.
func _bent_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -8, -GAP, 0)
	_barricade(tile, 0, 0)
	var bend := tile * Transform3D(Basis(Vector3.UP, deg_to_rad(30)), Vector3(GAP, 0, 0))
	_wall_x(bend, 0, 4 - w, 0)
	_window(bend, 4, 0)
	_wall_x(bend, 4 + w, 8, 0)


## Two Ls at opposite corners of a 12 m square, like the wall pairs on Dead by Daylight maps.
## One has a window in its long side; the other has a barricade between its short side and a post.
func _l_pair(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	var e := WALL_T / 2.0
	_wall_x(tile, -6 - e, -1 - w, -6)
	_window(tile, -1, -6)
	_wall_x(tile, -1 + w, 5, -6)
	_wall_z(tile, -6 + e, 1, -6)
	_wall_x(tile, -5, 6 + e, 6)
	_wall_z(tile, 1.5 + GAP, 6 - e, 6)
	_barricade(tile, 6, 1.5, 90)
	_wall_z(tile, -1.5, 1.5 - GAP, 6)


## A big loop like the harvesters on Rotten Fields: a parked train car, then a barricade between
## its end and a short container.
func _train_loop(tile: Transform3D) -> void:
	_train(tile)
	_barricade(tile, 7 + GAP, 0)
	_container(tile * Transform3D(Basis(), Vector3(7 + 2.0 * GAP + 1.75, 0, 0)), 3.5)


## Filler: a barricade between the ends of two short containers. Weak, but it can buy a few
## seconds between zones.
func _rock_pallet(tile: Transform3D) -> void:
	for x in [-GAP - 1.75, GAP + 1.75]:
		_container(tile * Transform3D(Basis(), Vector3(x, 0, 0)), 3.5)
	_barricade(tile, 0, 0)


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.96, 0.88)  # warm afternoon sun
	sun.light_energy = 0.85
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.5, 0.95)
	sky_mat.sky_horizon_color = Color(0.7, 0.85, 1.0)
	sky_mat.ground_horizon_color = Color(0.6, 0.6, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2  # punchy, cartoony colors
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.85, 1.0)
	env.fog_density = 0.003
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

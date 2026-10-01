extends Node3D
## The maps, built in code. Set `map_id` before adding the arena to the tree.
##
## Rotten Fields (map 0): a sunny subway yard laid out like Dead by Daylight's Rotten Fields. A grid of
## 24 m cells inside a stepped outer wall (144 x 192 m at its widest). Cells around the edge, at
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

enum Map { ROTTEN_FIELDS, LAST_STOP }
const MAP_NAMES := ["Rotten Fields", "The Last Stop"]

const Greybox := preload("res://scripts/greybox.gd")
const Barricade := preload("res://scripts/barricade.gd")
const TUNING := preload("res://tuning.tres")

const CELL := 24.0
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
## One tile per pictured cell: [tile, x, z, degrees]. Cell centers are multiples of 24 m.
## The long wall (two walls with a window between) is very strong, so there is only one.
const TILES := [
	[Tile.L_PAIR, 0, -72, 0],  # 12 o'clock
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
const ROCKS := [[-21, -45], [27, -21], [-26, 3], [22, 5], [-20, 27], [26, 45], [-50, -20], [3, 50], [40, 56],
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
var runner_spawn := Vector3(-16.75, 0, -72)
var runner_spawn_yaw := PI  # facing along the corridor
var hunter_spawn := Vector3(-8, 0, -52)
var hunter_spawn_yaw := 0.675  # facing the depot

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
## Same seed on every computer, so graffiti and container colors match (they're only looks anyway).
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build_environment()
	_rng.seed = 1234
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	if map_id == Map.LAST_STOP:
		_build_last_stop()
	else:
		_build_rotten_fields()
	_bake_navigation()


func _build_rotten_fields() -> void:
	_outline(OUTLINE, Vector3(0, 0, 0), Vector2(148, 196))
	_depot(_at(DEPOT.x, DEPOT.z, 0))
	for t in TILES:
		_tile(t[0], _at(t[1], t[2], t[3]))
	for f in ROCK_PALLETS:
		_rock_pallet(_at(f[0], f[1], f[2]))
	for r in ROCKS:
		_rock(Vector3(r[0], 0, r[1]))
	for l in LAMPS:
		_lamp(Vector3(l[0], 0, l[1]))


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
	# The shop, with a trash can in the 2 m gap between it and the east fence.
	_wall_color = MAIN_COLOR
	var shop := Greybox.box(_nav, tile * Transform3D(Basis(), Vector3(8.5, 1.6, -10)), Vector3(9, 3.2, 7), MAIN_COLOR)
	Greybox.box(shop, Transform3D(Basis(), Vector3(0, 1.9, 0)), Vector3(9.4, 0.4, 7.4), MAIN_COLOR.darkened(0.3), false)
	Greybox.box(shop, Transform3D(Basis(), Vector3(-1, 0.2, 3.52)), Vector3(4, 1.2, 0.05), WINDOW_COLOR, false)
	Greybox.box(shop, Transform3D(Basis(), Vector3(0, 2.4, 3.5)), Vector3(5, 0.7, 0.2), PAINT[3], false)
	_wall_color = WALL_COLOR
	_barricade(tile, 14, -10, 90)
	# Pump island: low and solid (you can see over it), with pumps on top, under a canopy.
	Greybox.box(_nav, tile * Transform3D(Basis(), Vector3(0, 0.5, 2)), Vector3(10, 1.0, 2.4), Color(0.75, 0.75, 0.72))
	for x in [-3.0, 3.0]:
		var pump := Greybox.box(_nav, tile * Transform3D(Basis(), Vector3(x, 1.8, 2)), Vector3(0.9, 1.6, 0.6), Color(0.9, 0.2, 0.2))
		Greybox.box(pump, Transform3D(Basis(), Vector3(0, 0.3, 0.31)), Vector3(0.6, 0.4, 0.02), Color(0.15, 0.2, 0.3), false)
	for p in [Vector3(-7, 0, -2), Vector3(7, 0, -2), Vector3(-7, 0, 6), Vector3(7, 0, 6)]:
		Greybox.box(_nav, tile * Transform3D(Basis(), p + Vector3(0, 2.4, 0)), Vector3(0.5, 4.8, 0.5), POLE_COLOR)
	Greybox.box(self, tile * Transform3D(Basis(), Vector3(0, 5.0, 2)), Vector3(17, 0.5, 11), Color(0.95, 0.95, 0.95), false)
	Greybox.box(self, tile * Transform3D(Basis(), Vector3(0, 5.0, 2)), Vector3(17.1, 0.25, 11.1), PAINT[0], false)


## A medium loop: a 6 m wall with a window, a trash can gap, then a short post, with a short
## return at the far end to break sight.
func _short_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -5, -2 - w, 0)
	_window(tile, -2, 0)
	_wall_x(tile, -2 + w, 1, 0)
	_barricade(tile, 2, 0)
	_wall_x(tile, 3, 4.5, 0)
	_wall_z(tile, WALL_T / 2.0, 2.5, -5)


## A scrap yard: a jumble of containers that blocks sight lines. No trash cans.
func _scrap_yard(tile: Transform3D) -> void:
	_container(tile * Transform3D(Basis(Vector3.UP, 0.2), Vector3(-2.5, 0, -2)), 5.0)
	_container(tile * Transform3D(Basis(Vector3.UP, 1.4), Vector3(3, 0, 1)), 4.0)
	_container(tile * Transform3D(Basis(Vector3.UP, -0.5), Vector3(-1.5, 0, 3.5)), 3.0)


## Drainage: two low concrete curbs along a dry channel. Low cover: you see over them but run around.
func _drainage(tile: Transform3D) -> void:
	for z in [-1.6, 1.6]:
		Greybox.box(_nav, tile * Transform3D(Basis(), Vector3(0, 0.3, z)), Vector3(9, 0.6, 0.6), WALL_COLOR.darkened(0.15))
	Greybox.box(self, tile * Transform3D(Basis(), Vector3(0, 0.02, 0)), Vector3(9, 0.04, 2.6), Color(0.3, 0.33, 0.36), false)


# --- Rotten Fields tiles (also used by The Last Stop) -----------------------


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Greybox.WORLD_LAYER
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	_nav.navigation_mesh = nm
	# Barricades are up while baking, so their gaps count as open.
	_nav.bake_navigation_mesh(false)
	# Window vaults are shortcuts the path finder may use; they cost extra because vaulting is slow.
	for w in windows:
		var link := NavigationLink3D.new()
		link.start_position = w.origin + w.basis.z * 1.0
		link.end_position = w.origin - w.basis.z * 1.0
		link.travel_cost = 3.0
		link.navigation_layers = 2  # so a bot can choose to ignore windows
		_nav.add_child(link)
	_bake_blocked_map(nm)
	for xf in windows:
		loop_spots.append(xf.origin + xf.basis.z * 2.0)
		loop_spots.append(xf.origin - xf.basis.z * 2.0)
	for b in barricades:
		loop_spots.append(b.to_global(Vector3(0, 0, 2.0)))
		loop_spots.append(b.to_global(Vector3(0, 0, -2.0)))


func _bake_blocked_map(main_mesh: NavigationMesh) -> void:
	nav_blocked_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(nav_blocked_map, main_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(nav_blocked_map, main_mesh.cell_height)
	NavigationServer3D.map_set_active(nav_blocked_map, true)
	var region := NavigationRegion3D.new()
	add_child(region)
	region.set_navigation_map(nav_blocked_map)
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
	var xf := tile * Transform3D(Basis(), Vector3((x0 + x1) / 2.0, WALL_H / 2.0, z))
	Greybox.box(_nav, xf, Vector3(x1 - x0, WALL_H, WALL_T), _wall_color)
	_trim(xf, x1 - x0)
	_graffiti(xf, x1 - x0)


## A straight wall in tile space, running along Z from z0 to z1 at x.
func _wall_z(tile: Transform3D, z0: float, z1: float, x: float) -> void:
	var xf := tile * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x, WALL_H / 2.0, (z0 + z1) / 2.0))
	Greybox.box(_nav, xf, Vector3(z1 - z0, WALL_H, WALL_T), _wall_color)
	_trim(xf, z1 - z0)
	_graffiti(xf, z1 - z0)


## A darker cap along the top of a wall, so walls look finished rather than like plain blocks.
func _trim(xf: Transform3D, length: float) -> void:
	Greybox.box(self, xf * Transform3D(Basis(), Vector3(0, WALL_H / 2.0, 0)), Vector3(length + 0.06, 0.14, WALL_T + 0.12), _wall_color.darkened(0.3), false)


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
		Greybox.box(self, xf * Transform3D(Basis(), Vector3(x, y, 0)), Vector3(w, h, WALL_T + 0.02), c, false)
		# A smaller tag in another color on top.
		var c2: Color = PAINT[_rng.randi() % PAINT.size()]
		Greybox.box(self, xf * Transform3D(Basis(), Vector3(x + w * 0.15, y + h * 0.1, 0)), Vector3(w * 0.5, h * 0.4, WALL_T + 0.04), c2, false)


## A window opening centered at x along a wall at depth z (sill below, lintel above).
func _window(tile: Transform3D, x: float, z: float) -> void:
	var size_sill := Vector3(WINDOW_W, SILL_H, WALL_T)
	var size_top := Vector3(WINDOW_W, WALL_H - LINTEL_Y, WALL_T)
	Greybox.box(_nav, tile * Transform3D(Basis(), Vector3(x, SILL_H / 2.0, z)), size_sill, WINDOW_COLOR)
	Greybox.box(_nav, tile * Transform3D(Basis(), Vector3(x, (LINTEL_Y + WALL_H) / 2.0, z)), size_top, WINDOW_COLOR)
	windows.append(tile * Transform3D(Basis(), Vector3(x, 0, z)))
	window_vaults.append(0)
	window_blocked.append(0.0)
	window_since.append(0.0)
	var blocker := Greybox.box(self, tile * Transform3D(Basis(), Vector3(x, (SILL_H + LINTEL_Y) / 2.0, z)), Vector3(WINDOW_W, LINTEL_Y - SILL_H, 0.05), Color(0.8, 0.1, 0.1), false)
	blocker.visible = false
	_window_blockers.append(blocker)


## A window in a wall that runs along Z, centered at z.
func _window_z(tile: Transform3D, z: float, x: float) -> void:
	_window(tile * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x, 0, z)), 0, 0)


## A barricade standing in a 2 m gap centered at (x, z). At 0 degrees the gap runs along X.
func _barricade(tile: Transform3D, x: float, z: float, degrees := 0.0) -> void:
	var b := Barricade.new()
	b.transform = tile * Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3(x, 0, z))
	add_child(b)
	barricades.append(b)


## A shipping container (the "rocks" of this map): long and thin, too tall to see over.
func _rock(pos: Vector3) -> void:
	_container(Transform3D(Basis(Vector3.UP, pos.x * 0.3 + pos.z * 0.1), pos), 5.5)


## A container `length` m long along X, 1.4 m wide, painted a random bright color with dark ribs.
func _container(xf: Transform3D, length: float) -> void:
	var c: Color = PAINT[_rng.randi() % PAINT.size()]
	var body := Greybox.box(_nav, xf * Transform3D(Basis(), Vector3(0, 1.2, 0)), Vector3(length, 2.4, 1.4), c)
	var x := -length / 2.0 + 0.4
	while x < length / 2.0 - 0.2:
		Greybox.box(body, Transform3D(Basis(), Vector3(x, 0, 0)), Vector3(0.12, 2.3, 1.44), c.darkened(0.3), false)
		x += 0.8
	Greybox.box(body, Transform3D(Basis(), Vector3(0, 1.17, 0)), Vector3(length + 0.04, 0.1, 1.44), c.darkened(0.45), false)


## A street lamp: a thin pole with a glowing head.
func _lamp(pos: Vector3) -> void:
	Greybox.box(_nav, Transform3D(Basis(), pos + Vector3(0, 2.25, 0)), Vector3(0.25, 4.5, 0.25), POLE_COLOR)
	Greybox.box(self, Transform3D(Basis(), pos + Vector3(0, 4.5, -0.3)), Vector3(0.3, 0.15, 0.8), POLE_COLOR, false)
	var head := Greybox.box(self, Transform3D(Basis(), pos + Vector3(0, 4.4, -0.55)), Vector3(0.35, 0.1, 0.35), LAMP_COLOR, false)
	head.material_override = head.material_override.duplicate()
	head.material_override.emission_enabled = true
	head.material_override.emission = LAMP_COLOR


## A parked train car on a short stretch of track. Too tall to vault; you run around it.
func _train(tile: Transform3D) -> void:
	# Track: two rails on sleepers, flat on the ground (just looks).
	for x in range(-11, 12, 1):
		Greybox.box(self, tile * Transform3D(Basis(), Vector3(x, 0.03, 0)), Vector3(0.25, 0.06, 2.6), SLEEPER_COLOR, false)
	for z in [-0.75, 0.75]:
		Greybox.box(self, tile * Transform3D(Basis(), Vector3(0, 0.09, z)), Vector3(23, 0.08, 0.1), RAIL_COLOR, false)
	var c: Color = PAINT[_rng.randi() % PAINT.size()]
	var car := Greybox.box(_nav, tile * Transform3D(Basis(), Vector3(0, 1.75, 0)), Vector3(14, 3.5, 3.0), Color(0.92, 0.92, 0.94))
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
	Greybox.box(_nav, tile * Transform3D(Basis(), Vector3(0, WALL_H / 2.0, 0)), Vector3(11, WALL_H, 2.5), MAIN_COLOR.darkened(0.15))
	# The barricade across the west corridor, between the outer wall and the block.
	_wall_x(tile, -9 + e, -8.25, 0)
	_barricade(tile, -7.25, 0)
	_wall_x(tile, -6.25, -5.5, 0)
	_wall_color = WALL_COLOR


## A T: a long wall with a window, and a stem coming off its middle with a barricade in it.
func _t_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -7.5, -3.5 - w, -3.5)
	_window(tile, -3.5, -3.5)
	_wall_x(tile, -3.5 + w, 7.5, -3.5)
	_wall_z(tile, -3.5 + WALL_T / 2.0, -1, 0)
	_barricade(tile, 0, 0, 90)
	_wall_z(tile, 1, 3, 0)


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
	_wall_z(tile, -3.5 + WALL_T / 2.0, -0.5, 2.5)
	_barricade(tile, 2.5, 0.5, 90)
	_wall_z(tile, 1.5, 2.7, 2.5)


## A jungle gym: two Ls facing each other around a long 11 x 5 m rectangle. One has a window and
## a barricade (between the L and a short wall); the other is plain.
func _jungle_gym(tile: Transform3D) -> void:
	var hx := 5.5
	var hz := 2.5
	var w := WINDOW_W / 2.0
	var e := WALL_T / 2.0
	_wall_x(tile, -hx - e, -2.5 - w, -hz)
	_window(tile, -2.5, -hz)
	_wall_x(tile, -2.5 + w, 1.5, -hz)
	_barricade(tile, 2.5, -hz)
	_wall_x(tile, 3.5, hx + e, -hz)
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
	_barricade(tile, hx + 1.2, hz)
	_wall_z(tile, hz - 1, hz + 1, hx + 2.4)


## A long wall with a window and a barricade, with side walls to break line of sight.
func _long_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -7, -w, 0)
	_window(tile, 0, 0)
	_wall_x(tile, w, 4.2, 0)
	_barricade(tile, 5.2, 0)
	_wall_x(tile, 6.2, 7, 0)
	_wall_z(tile, WALL_T / 2.0, 2.5, -7)
	_wall_z(tile, -2.5, -WALL_T / 2.0, 7)


## A wall with a barricade in the middle and side walls at both ends.
func _barricade_loop(tile: Transform3D) -> void:
	_wall_x(tile, -7, -1, 0)
	_barricade(tile, 0, 0)
	_wall_x(tile, 1, 7, 0)
	_wall_z(tile, -2.5, -WALL_T / 2.0, -7)
	_wall_z(tile, WALL_T / 2.0, 2.5, 7)


## A long wall bent in the middle: a straight run, a barricade at the bend, then a run angled
## 30 degrees away with a window in it.
func _bent_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -8, -1, 0)
	_barricade(tile, 0, 0)
	var bend := tile * Transform3D(Basis(Vector3.UP, deg_to_rad(30)), Vector3(1, 0, 0))
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
	_wall_z(tile, 2.5, 6 - e, 6)
	_barricade(tile, 6, 1.5, 90)
	_wall_z(tile, -1.5, 0.5, 6)


## A big loop like the harvesters on Rotten Fields: a parked train car, then a barricade between
## its end and a short container.
func _train_loop(tile: Transform3D) -> void:
	_train(tile)
	_barricade(tile, 8, 0)
	_container(tile * Transform3D(Basis(), Vector3(10.75, 0, 0)), 3.5)


## Filler: a barricade between the ends of two short containers. Weak, but it can buy a few
## seconds between zones.
func _rock_pallet(tile: Transform3D) -> void:
	for x in [-2.75, 2.75]:
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

extends Node3D
## The map: a 112 x 112 m sunny subway yard laid out like a Dead by Daylight map.
## A very strong Runner building (the depot) sits in one corner; both players start there.
## The other corners hold zones of well-spaced tiles (T walls, L walls, jungle gyms, shacks),
## joined by sparse filler: shipping containers, lamp posts, container barricades and parked trains.
## Tiles are long and thin rather than square, so no single block can be looped forever.
## Every barricade stands in a gap between two solid things, so it can always be looped.
## Every player builds the same map from this code, so nothing about it is sent over the network.

const Greybox := preload("res://scripts/greybox.gd")
const Barricade := preload("res://scripts/barricade.gd")
const TUNING := preload("res://tuning.tres")

const SIZE := 112.0
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

## Both players start at the depot in the north-east corner: the Runner inside, the Hunter
## about 23 m away facing it. (The Hunter also waits out the Runner's head start.)
const DEPOT := Vector3(40.6, 0, -42)
const RUNNER_SPAWN := Vector3(47.85, 0, -42)
const RUNNER_SPAWN_YAW := PI  # facing along the corridor
const HUNTER_SPAWN := Vector3(30, 0, -27)
const HUNTER_SPAWN_YAW := -0.615  # facing the depot

enum Tile { T_WALL, L_WINDOW, L_BARRICADE, JUNGLE_GYM, SHACK, LONG_WALL, BARRICADE_LOOP }
## Tiles are long and thin, fit within about 6.5 m of their middle, and sit at least 8 m apart: [tile, x, z, degrees].
const TILES := [
	# North-west zone
	[Tile.T_WALL, -44.1, -44.1, 0], [Tile.JUNGLE_GYM, -20.3, -44.1, 0],
	[Tile.LONG_WALL, -44.1, -20.3, 90], [Tile.L_WINDOW, -20.3, -20.3, 180],
	# South-west zone
	[Tile.JUNGLE_GYM, -44.1, 20.3, 90], [Tile.L_BARRICADE, -20.3, 20.3, 0],
	[Tile.SHACK, -44.1, 44.1, 180], [Tile.T_WALL, -20.3, 44.1, 180],
	# South-east zone
	[Tile.LONG_WALL, 20.3, 20.3, 0], [Tile.L_WINDOW, 44.1, 20.3, 90],
	[Tile.T_WALL, 20.3, 44.1, 270], [Tile.BARRICADE_LOOP, 44.1, 44.1, 0],
	# Around the depot (north-east)
	[Tile.L_BARRICADE, 18.9, -44.1, 90], [Tile.SHACK, 44.1, -20.3, 0], [Tile.JUNGLE_GYM, 20.3, -20.3, 0],
	# Middle of the map
	[Tile.T_WALL, 0, 0, 0],
]
## Filler between the zones: [x, z, degrees].
const ROCK_PALLETS := [[0, -33.6, 0], [0, 33.6, 0], [-33.6, 0, 90], [33.6, 0, 90]]
const ROCKS := [[-8.4, -19.6], [8.4, -23.8], [-8.4, -46.2], [9.8, 44.8], [-7, 21], [7, 18.2], [19.6, -7], [-21, 8.4],
	[-46.2, -8.4], [43.4, 8.4]]
const LAMPS := [[-4.2, -14], [4.2, 14], [-14, 4.2], [14, -4.2], [-9.8, -37.8], [9.8, -29.4], [-9.8, 29.4], [9.8, 37.8],
	[-29.4, -8.4], [-37.8, 8.4], [29.4, 8.4], [37.8, -8.4]]
## Parked trains on tracks along the edges: [x, z, degrees]. At 0 degrees a train runs along X.
const TRAINS := [[0, -51.1, 0], [0, 51.1, 0], [-51.1, 0, 90], [51.1, 0, 90]]

## Barricade nodes, in a fixed order so peers can refer to them by index.
var barricades: Array = []
## One transform per window: origin = middle of the window at floor level, basis.z = direction you vault.
var windows: Array[Transform3D] = []
## Per window: Runner vaults so far, and seconds left blocked (0 = open).
var window_vaults: Array[int] = []
var window_blocked: Array[float] = []
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
	var half := SIZE / 2.0
	Greybox.box(_nav, Transform3D(Basis(), Vector3(0, -0.5, 0)), Vector3(SIZE + 2, 1, SIZE + 2), FLOOR_COLOR)
	for side in [-1, 1]:
		Greybox.box(_nav, Transform3D(Basis(), Vector3(0, 1.5, side * (half + 0.5))), Vector3(SIZE + 2, 3, 1), WALL_COLOR)
		Greybox.box(_nav, Transform3D(Basis(), Vector3(side * (half + 0.5), 1.5, 0)), Vector3(1, 3, SIZE + 2), WALL_COLOR)

	_depot(_at(DEPOT.x, DEPOT.z, 0))
	for t in TILES:
		_tile(t[0], _at(t[1], t[2], t[3]))
	for f in ROCK_PALLETS:
		_rock_pallet(_at(f[0], f[1], f[2]))
	for r in ROCKS:
		_rock(Vector3(r[0], 0, r[1]))
	for l in LAMPS:
		_lamp(Vector3(l[0], 0, l[1]))
	for t in TRAINS:
		_train(_at(t[0], t[1], t[2]))
	_bake_navigation()


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


func is_window_blocked(i: int) -> bool:
	return window_blocked[i] > 0.0


## Counts a Runner vault. Too many on the same window and it's blocked for a while,
## so the Runner can't loop one window forever.
func note_window_vault(i: int) -> void:
	window_vaults[i] += 1
	if window_vaults[i] >= TUNING.window_block_vaults:
		window_vaults[i] = 0
		window_blocked[i] = TUNING.window_block_time


func _process(delta: float) -> void:
	for i in windows.size():
		window_blocked[i] = maxf(0.0, window_blocked[i] - delta)
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
	_wall_x(tile, -6.5, -3 - w, -3.5)
	_window(tile, -3, -3.5)
	_wall_x(tile, -3 + w, 6.5, -3.5)
	_wall_z(tile, -3.5 + WALL_T / 2.0, -1, 0)
	_barricade(tile, 0, 0, 90)
	_wall_z(tile, 1, 3, 0)


## A long L with a window in its long side.
func _l_window(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -6.5, -1.5 - w, -3.5)
	_window(tile, -1.5, -3.5)
	_wall_x(tile, -1.5 + w, 3.5 + WALL_T / 2.0, -3.5)
	_wall_z(tile, -3.5 + WALL_T / 2.0, 1.5, 3.5)


## A long L with a barricade in its short side.
func _l_barricade(tile: Transform3D) -> void:
	_wall_x(tile, -7, 2.5 + WALL_T / 2.0, -3.5)
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
	_wall_x(tile, -6, -w, 0)
	_window(tile, 0, 0)
	_wall_x(tile, w, 3.2, 0)
	_barricade(tile, 4.2, 0)
	_wall_x(tile, 5.2, 6, 0)
	_wall_z(tile, WALL_T / 2.0, 2.5, -6)
	_wall_z(tile, -2.5, -WALL_T / 2.0, 6)


## A wall with a barricade in the middle and side walls at both ends.
func _barricade_loop(tile: Transform3D) -> void:
	_wall_x(tile, -6, -1, 0)
	_barricade(tile, 0, 0)
	_wall_x(tile, 1, 6, 0)
	_wall_z(tile, -2.5, -WALL_T / 2.0, -6)
	_wall_z(tile, WALL_T / 2.0, 2.5, 6)


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

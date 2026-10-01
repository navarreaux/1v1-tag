extends Node3D
## The map: an 80 x 80 m sunny subway yard laid out like a Dead by Daylight map.
## A very strong Runner building (the depot) sits in one corner; both players start there.
## The other corners hold zones of well-spaced tiles (T walls, L walls, jungle gyms, shacks),
## joined by sparse filler: crate stacks, lamp posts, crate barricades and parked trains.
## Every barricade stands in a gap between two solid things, so it can always be looped.
## Every player builds the same map from this code, so nothing about it is sent over the network.

const Greybox := preload("res://scripts/greybox.gd")
const Barricade := preload("res://scripts/barricade.gd")
const TUNING := preload("res://tuning.tres")

const SIZE := 80.0
const WALL_H := 2.6
const WALL_T := 0.4
const WINDOW_W := 1.4
const SILL_H := 0.9
const LINTEL_Y := 2.0

const FLOOR_COLOR := Color(0.4, 0.36, 0.32)  # gravel
const WALL_COLOR := Color(0.5, 0.56, 0.66)  # blue-grey concrete
const MAIN_COLOR := Color(0.75, 0.32, 0.22)  # red brick depot
const WINDOW_COLOR := Color(0.2, 0.5, 0.95)
const ROCK_COLOR := Color(0.75, 0.5, 0.25)  # wooden crates
const POLE_COLOR := Color(0.45, 0.47, 0.5)
const LAMP_COLOR := Color(1.0, 0.9, 0.4)
const RAIL_COLOR := Color(0.55, 0.55, 0.6)
const SLEEPER_COLOR := Color(0.38, 0.27, 0.18)
## Bright spray-paint colors for graffiti and crates.
const PAINT := [Color(1.0, 0.25, 0.6), Color(0.1, 0.85, 0.95), Color(0.5, 0.95, 0.2), Color(1.0, 0.85, 0.1),
	Color(0.6, 0.3, 1.0), Color(1.0, 0.5, 0.1), Color(0.2, 0.45, 1.0)]

## Both players start at the depot in the north-east corner: the Runner inside, the Hunter
## about 20 m away facing it. (The Hunter also waits out the Runner's head start.)
const DEPOT := Vector3(29, 0, -30)
const RUNNER_SPAWN := Vector3(34.25, 0, -30)
const RUNNER_SPAWN_YAW := PI  # facing along the corridor
const HUNTER_SPAWN := Vector3(16, 0, -22)
const HUNTER_SPAWN_YAW := -1.02  # facing the depot

enum Tile { T_WALL, L_WINDOW, L_BARRICADE, JUNGLE_GYM, SHACK, LONG_WALL, BARRICADE_LOOP }
## Tiles fit within about 5 m of their middle and sit at least 7 m apart: [tile, x, z, degrees].
const TILES := [
	# North-west zone
	[Tile.T_WALL, -31.5, -31.5, 0], [Tile.JUNGLE_GYM, -14.5, -31.5, 0],
	[Tile.LONG_WALL, -31.5, -14.5, 90], [Tile.L_WINDOW, -14.5, -14.5, 180],
	# South-west zone
	[Tile.JUNGLE_GYM, -31.5, 14.5, 90], [Tile.L_BARRICADE, -14.5, 14.5, 0],
	[Tile.SHACK, -31.5, 31.5, 180], [Tile.T_WALL, -14.5, 31.5, 180],
	# South-east zone
	[Tile.LONG_WALL, 14.5, 14.5, 0], [Tile.L_WINDOW, 31.5, 14.5, 90],
	[Tile.T_WALL, 14.5, 31.5, 270], [Tile.BARRICADE_LOOP, 31.5, 31.5, 0],
	# Around the depot (north-east)
	[Tile.L_BARRICADE, 13.5, -31.5, 90], [Tile.SHACK, 31.5, -14.5, 0], [Tile.JUNGLE_GYM, 14.5, -14.5, 0],
	# Middle of the map
	[Tile.T_WALL, 0, 0, 0],
]
## Filler between the zones: [x, z, degrees].
const ROCK_PALLETS := [[0, -24, 0], [0, 24, 0], [-24, 0, 90], [24, 0, 90]]
const ROCKS := [[-6, -14], [6, -17], [-6, -33], [7, 32], [-5, 15], [5, 13], [14, -5], [-15, 6],
	[-33, -6], [31, 6]]
const LAMPS := [[-3, -10], [3, 10], [-10, 3], [10, -3], [-7, -27], [7, -21], [-7, 21], [7, 27],
	[-21, -6], [-27, 6], [21, 6], [27, -6]]
## Parked trains on tracks along the edges: [x, z, degrees]. At 0 degrees a train runs along X.
const TRAINS := [[0, -36.5, 0], [0, 36.5, 0], [-36.5, 0, 90], [36.5, 0, 90]]

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
var _wall_color := WALL_COLOR
## Same seed on every computer, so graffiti and crate colors match (they're only looks anyway).
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
	for xf in windows:
		loop_spots.append(xf.origin + xf.basis.z * 2.0)
		loop_spots.append(xf.origin - xf.basis.z * 2.0)
	for b in barricades:
		loop_spots.append(b.to_global(Vector3(0, 0, 2.0)))
		loop_spots.append(b.to_global(Vector3(0, 0, -2.0)))


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


## A stack of crates (the "rocks" of this map): one solid block, painted as a big and a small crate.
func _rock(pos: Vector3) -> void:
	_crates(Transform3D(Basis(Vector3.UP, pos.x * 0.3 + pos.z * 0.1), pos))


func _crates(xf: Transform3D) -> void:
	var c: Color = PAINT[_rng.randi() % PAINT.size()]
	var body := Greybox.box(_nav, xf * Transform3D(Basis(), Vector3(0, 1.0, 0)), Vector3(2.2, 2.0, 1.6), ROCK_COLOR)
	# Painted panels and dark slats, so it reads as two stacked crates.
	Greybox.box(body, Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(2.22, 0.9, 1.62), c, false)
	for y in [-0.05, 0.95]:
		Greybox.box(body, Transform3D(Basis(), Vector3(0, y, 0)), Vector3(2.24, 0.1, 1.64), ROCK_COLOR.darkened(0.4), false)


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
## around a solid block, so the Runner can loop it. A barricade across the west corridor makes the
## loop very safe until the Hunter breaks it. Two doors and two windows lead outside.
func _depot(tile: Transform3D) -> void:
	_wall_color = MAIN_COLOR
	var w := WINDOW_W / 2.0
	var e := WALL_T / 2.0
	# North wall with a door; south wall with a door and a window; east wall with a window.
	_wall_x(tile, -7 - e, 4, -5)
	_wall_x(tile, 6, 7 + e, -5)
	_wall_x(tile, -7 - e, -6, 5)
	_wall_x(tile, -4, 3 - w, 5)
	_window(tile, 3, 5)
	_wall_x(tile, 3 + w, 7 + e, 5)
	_wall_z(tile, -5 + e, 5 - e, -7)
	_wall_z(tile, -5 + e, -w, 7)
	_window_z(tile, 0, 7)
	_wall_z(tile, w, 5 - e, 7)
	# The solid middle block.
	Greybox.box(_nav, tile * Transform3D(Basis(), Vector3(0, WALL_H / 2.0, 0)), Vector3(7, WALL_H, 3), MAIN_COLOR.darkened(0.15))
	# The barricade across the west corridor, between the outer wall and the block.
	_wall_x(tile, -7 + e, -6.25, 0)
	_barricade(tile, -5.25, 0)
	_wall_x(tile, -4.25, -3.5, 0)
	_wall_color = WALL_COLOR


## A T: a long wall with a window, and a stem coming off its middle with a barricade in it.
func _t_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -5, -2.5 - w, -3.5)
	_window(tile, -2.5, -3.5)
	_wall_x(tile, -2.5 + w, 5, -3.5)
	_wall_z(tile, -3.5 + WALL_T / 2.0, -1, 0)
	_barricade(tile, 0, 0, 90)
	_wall_z(tile, 1, 3.5, 0)


## A long L with a window in its long side.
func _l_window(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -5, -1 - w, -3.5)
	_window(tile, -1, -3.5)
	_wall_x(tile, -1 + w, 3.5 + WALL_T / 2.0, -3.5)
	_wall_z(tile, -3.5 + WALL_T / 2.0, 3.5, 3.5)


## An L with a barricade in its short side.
func _l_barricade(tile: Transform3D) -> void:
	_wall_x(tile, -5, 2.5 + WALL_T / 2.0, -3.5)
	_wall_z(tile, -3.5 + WALL_T / 2.0, -0.5, 2.5)
	_barricade(tile, 2.5, 0.5, 90)
	_wall_z(tile, 1.5, 3.5, 2.5)


## A jungle gym: two Ls facing each other around an 8 m square. One has a window and a
## barricade (between the L and a short wall); the other is plain.
func _jungle_gym(tile: Transform3D) -> void:
	var h := 4.0
	var w := WINDOW_W / 2.0
	var e := WALL_T / 2.0
	_wall_x(tile, -h - e, -1.5 - w, -h)
	_window(tile, -1.5, -h)
	_wall_x(tile, -1.5 + w, 1, -h)
	_barricade(tile, 2, -h)
	_wall_x(tile, 3, h + e, -h)
	_wall_z(tile, -h + e, 1, -h)
	_wall_x(tile, -1, h + e, h)
	_wall_z(tile, -1, h - e, h)


## A shack: a 5 x 5 m room with a doorway and a vault window, and a barricade beside it
## between the shack wall and a short post.
func _shack(tile: Transform3D) -> void:
	var h := 2.5
	var w := WINDOW_W / 2.0
	_wall_x(tile, -h, -w, -h)
	_window(tile, 0, -h)
	_wall_x(tile, w, h, -h)
	_wall_x(tile, -h, -1.1, h)
	_wall_x(tile, 1.1, h, h)
	_wall_z(tile, -h - WALL_T / 2.0, h + WALL_T / 2.0, -h)
	_wall_z(tile, -h - WALL_T / 2.0, h + WALL_T / 2.0, h)
	_barricade(tile, h + 1.2, h)
	_wall_z(tile, h - 1, h + 1, h + 2.4)


## A long wall with a window and a barricade, with side walls to break line of sight.
func _long_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -5, -w, 0)
	_window(tile, 0, 0)
	_wall_x(tile, w, 2.2, 0)
	_barricade(tile, 3.2, 0)
	_wall_x(tile, 4.2, 5, 0)
	_wall_z(tile, WALL_T / 2.0, 3, -5)
	_wall_z(tile, -3, -WALL_T / 2.0, 5)


## A wall with a barricade in the middle and side walls at both ends.
func _barricade_loop(tile: Transform3D) -> void:
	_wall_x(tile, -5, -1, 0)
	_barricade(tile, 0, 0)
	_wall_x(tile, 1, 5, 0)
	_wall_z(tile, -3, -WALL_T / 2.0, -5)
	_wall_z(tile, WALL_T / 2.0, 3, 5)


## Filler: a barricade between two crate stacks. Weak, but it can buy a few seconds between zones.
func _rock_pallet(tile: Transform3D) -> void:
	for x in [-2.1, 2.1]:
		_crates(tile * Transform3D(Basis(), Vector3(x, 0, 0)))
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

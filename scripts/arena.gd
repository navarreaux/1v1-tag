extends Node3D
## The greybox map: a 40 x 40 m walled field with a few "tiles" to loop around.
## Every player builds the same map from this code, so nothing about it is sent over the network.

const Greybox := preload("res://scripts/greybox.gd")
const Barricade := preload("res://scripts/barricade.gd")
const TUNING := preload("res://tuning.tres")

const SIZE := 40.0
const WALL_H := 2.6
const WALL_T := 0.4
const WINDOW_W := 1.4
const SILL_H := 0.9
const LINTEL_Y := 2.0

const FLOOR_COLOR := Color(0.25, 0.32, 0.22)
const WALL_COLOR := Color(0.5, 0.5, 0.48)
const WINDOW_COLOR := Color(0.45, 0.55, 0.7)
const ROCK_COLOR := Color(0.48, 0.45, 0.42)

const HUNTER_SPAWN := Vector3(0, 0, -16)
const HUNTER_SPAWN_YAW := PI  # facing the middle
const RUNNER_SPAWN := Vector3(0, 0, 16)
const RUNNER_SPAWN_YAW := 0.0

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


func _ready() -> void:
	_build_environment()
	_nav = NavigationRegion3D.new()
	add_child(_nav)
	var half := SIZE / 2.0
	Greybox.box(_nav, Transform3D(Basis(), Vector3(0, -0.5, 0)), Vector3(SIZE + 2, 1, SIZE + 2), FLOOR_COLOR)
	for side in [-1, 1]:
		Greybox.box(_nav, Transform3D(Basis(), Vector3(0, 1.5, side * (half + 0.5))), Vector3(SIZE + 2, 3, 1), WALL_COLOR)
		Greybox.box(_nav, Transform3D(Basis(), Vector3(side * (half + 0.5), 1.5, 0)), Vector3(1, 3, SIZE + 2), WALL_COLOR)

	_barricade_loop(_at(-10, -9, 0))
	_barricade_loop(_at(11, 9, 90))
	_window_house(_at(10, -9, 0))
	_window_house(_at(-11, 9, 180))
	_long_wall(_at(-1, 1, 0))

	for rock in [Vector3(-3, 0, -13), Vector3(4, 0, 12), Vector3(-17, 0, 0), Vector3(17, 0, -1), Vector3(-4, 0, 15), Vector3(16, 0, -16)]:
		Greybox.box(_nav, Transform3D(Basis(Vector3.UP, rock.x * 0.3), rock + Vector3(0, 1.1, 0)), Vector3(2.2, 2.2, 1.6), ROCK_COLOR)
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
	Greybox.box(_nav, tile * Transform3D(Basis(), Vector3((x0 + x1) / 2.0, WALL_H / 2.0, z)), Vector3(x1 - x0, WALL_H, WALL_T), WALL_COLOR)


## A straight wall in tile space, running along Z from z0 to z1 at x.
func _wall_z(tile: Transform3D, z0: float, z1: float, x: float) -> void:
	Greybox.box(_nav, tile * Transform3D(Basis(), Vector3(x, WALL_H / 2.0, (z0 + z1) / 2.0)), Vector3(WALL_T, WALL_H, z1 - z0), WALL_COLOR)


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


func _barricade(tile: Transform3D, x: float, z: float) -> void:
	var b := Barricade.new()
	b.transform = tile * Transform3D(Basis(), Vector3(x, 0, z))
	add_child(b)
	barricades.append(b)


## Tile 1: a wall with a barricade in the middle. Loop around the ends or through the gap.
func _barricade_loop(tile: Transform3D) -> void:
	_wall_x(tile, -4.5, -1.0, 0)
	_barricade(tile, 0, 0)
	_wall_x(tile, 1.0, 4.5, 0)
	_wall_z(tile, -2.5, 0.2, -4.5)


## Tile 2: a 6 x 6 m room with a doorway on one side and a vault window on the other.
func _window_house(tile: Transform3D) -> void:
	var h := 3.0
	var w := WINDOW_W / 2.0
	_wall_x(tile, -h, -w, -h)
	_window(tile, 0, -h)
	_wall_x(tile, w, h, -h)
	_wall_x(tile, -h, -1.1, h)
	_wall_x(tile, 1.1, h, h)
	_wall_z(tile, -h - WALL_T / 2.0, h + WALL_T / 2.0, -h)
	_wall_z(tile, -h - WALL_T / 2.0, h + WALL_T / 2.0, h)


## Tile 3: a long wall with a window and a barricade, with short side walls to break line of sight.
func _long_wall(tile: Transform3D) -> void:
	var w := WINDOW_W / 2.0
	_wall_x(tile, -6, -w, 0)
	_window(tile, 0, 0)
	_wall_x(tile, w, 3, 0)
	_barricade(tile, 4, 0)
	_wall_x(tile, 5, 7, 0)
	_wall_z(tile, 0, 3, -6)
	_wall_z(tile, -3, 0, 7)


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	sun.shadow_enabled = true
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.35, 0.55)
	sky_mat.sky_horizon_color = Color(0.55, 0.6, 0.66)
	sky_mat.ground_horizon_color = Color(0.4, 0.4, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.63, 0.68)
	env.fog_density = 0.006
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

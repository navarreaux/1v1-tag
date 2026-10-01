extends RefCounted
## Helpers for building placeholder ("greybox") geometry out of plain boxes.

const WORLD_LAYER := 1
const PLAYER_LAYER := 2

static var _materials := {}


static func material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_materials[color] = m
	return _materials[color]


## Adds a solid box. `xform` places it; `size` is in meters.
static func box(parent: Node, xform: Transform3D, size: Vector3, color: Color, solid := true) -> Node3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material(color)
	if not solid:
		mesh.transform = xform
		parent.add_child(mesh)
		return mesh
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.transform = xform
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.add_child(mesh)
	parent.add_child(body)
	return body

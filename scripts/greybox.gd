extends RefCounted
## Helpers for building geometry out of boxes and rounded shapes, with a cartoon look.

const WORLD_LAYER := 1
const PLAYER_LAYER := 2

static var _materials := {}


static var _outline: StandardMaterial3D


## A cartoon material: flat toon shading with a soft rim light and a dark outline,
## so shapes read clearly like in a mobile runner game.
static func material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_TOON
		m.roughness = 0.6
		m.rim_enabled = true
		m.rim = 0.35
		m.rim_tint = 0.6
		m.next_pass = outline()
		_materials[color] = m
	return _materials[color]


## Drawn behind every mesh, slightly puffed out, to give everything an ink outline.
static func outline() -> StandardMaterial3D:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.albedo_color = Color(0.08, 0.07, 0.12)
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.025
	return _outline


enum Shape { BALL, PILL, ROD }


## Adds a rounded, look-only shape that fills a `size` box: BALL is an ellipsoid,
## PILL a capsule (rounded ends along Y) and ROD a cylinder along Y.
static func round(parent: Node, xform: Transform3D, size: Vector3, color: Color, kind := Shape.BALL) -> MeshInstance3D:
	# Meshes are built at their real width and height (so outlines keep the same thickness)
	# and only stretched front to back.
	var mesh := MeshInstance3D.new()
	var r := size.x / 2.0
	match kind:
		Shape.BALL:
			var sm := SphereMesh.new()
			sm.radius = r
			sm.height = size.y
			sm.radial_segments = 16
			sm.rings = 8
			mesh.mesh = sm
		Shape.PILL:
			var cm := CapsuleMesh.new()
			cm.radius = minf(r, size.y / 2.0)
			cm.height = size.y
			cm.radial_segments = 12
			cm.rings = 4
			mesh.mesh = cm
		Shape.ROD:
			var cy := CylinderMesh.new()
			cy.top_radius = r
			cy.bottom_radius = r
			cy.height = size.y
			cy.radial_segments = 14
			mesh.mesh = cy
	mesh.material_override = material(color)
	mesh.transform = xform.scaled_local(Vector3(1, 1, size.z / size.x))
	parent.add_child(mesh)
	return mesh


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

class_name EITerrainSector
extends Node3D
## One authored 32 m sector, rendered as independently culled 16 m pieces.
## Tile attributes and indices stay unchanged. Keeping the source arrays (not
## a second GPU mesh) allows the optional deformation system to use its usual
## contiguous tile layout. Cache materials are shared by every piece.
const SIDE := 16
const TILE_VERTICES := 9
const TILE_INDICES := 24
const CHANNELS := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV,
	Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]
var _arrays: Array
var _material: Material
var _override: Material
var _layers: int
var _bounds: AABB
var _parts: Array[MeshInstance3D] = []
var _meshes: Array[ArrayMesh] = []
var _subdivided := false
var tile_origin := Vector2i.ZERO


static func preferred() -> bool:
	var args := OS.get_cmdline_user_args()
	return DisplayServer.get_name() != "headless" and Portability.compatibility() and not args.has("--ei-whole-terrain") \
		and (OS.has_feature("android") or args.has("--ei-terrain-pieces"))


func configure(arrays: Array, material: Material, layers: int, subdivided: bool) -> void:
	_arrays = arrays
	_material = material
	_layers = layers
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_bounds = AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		_bounds = _bounds.expand(vertex)
	_rebuild(subdivided)


func get_aabb() -> AABB:
	return _bounds


func set_subdivided(value: bool) -> void:
	if _subdivided != value:
		_rebuild(value)


func set_base_material(material: Material) -> void:
	if _material == material: return
	_material = material
	# Soft-ground deformation can temporarily replace a piece's mesh. Update
	# its retained source, so restoring it uses the current terrain options,
	# without overwriting the live trail material or a cache override.
	for mesh in _meshes:
		mesh.surface_set_material(0, material)


func get_surface_override_material(_surface: int) -> Material:
	return _override


func set_surface_override_material(_surface: int, material: Material) -> void:
	_override = material
	for piece in _parts:
		piece.set_surface_override_material(0, material)


func deformation_surface() -> MeshInstance3D:
	set_subdivided(false)
	return _parts[0]


func _rebuild(subdivided: bool) -> void:
	for piece in _parts:
		piece.free()
	_parts.clear()
	_meshes.clear()
	_subdivided = subdivided
	if not subdivided:
		_add_piece(_arrays)
		return
	for y in [0, 8]:
		for x in [0, 8]:
			_add_piece(_piece_arrays(x, y))


func _add_piece(arrays: Array) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	_meshes.append(mesh)
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.layers = _layers
	piece.set_surface_override_material(0, _override)
	add_child(piece)
	_parts.append(piece)


func _piece_arrays(x: int, y: int) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	# Empty typed packed arrays preserve all five authored attribute channels.
	for channel in CHANNELS:
		arrays[channel] = _arrays[channel].slice(0, 0)
	var indices := PackedInt32Array()
	var source: PackedInt32Array = _arrays[Mesh.ARRAY_INDEX]
	for row in range(y, y + 8):
		var first := row * SIDE + x
		for channel in CHANNELS:
			arrays[channel].append_array(_arrays[channel].slice(first * TILE_VERTICES,
				(first + 8) * TILE_VERTICES))
		var offset := (row - y) * 8 * TILE_VERTICES - first * TILE_VERTICES
		for i in range(first * TILE_INDICES, (first + 8) * TILE_INDICES):
			indices.append(source[i] + offset)
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays

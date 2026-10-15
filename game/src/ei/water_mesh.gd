class_name EIWaterMesh
extends MeshInstance3D
## Retain only the immutable channels used by visual water queries. Reading
## these back from the GPU when mist or wildlife enters a new sector stalls
## the rendering thread. Packed arrays share storage with the upload input.
var _query_arrays: Array
var _source: WeakRef


func configure(arrays: Array, material: Material) -> void:
	_query_arrays = []
	_query_arrays.resize(Mesh.ARRAY_MAX)
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX]:
		_query_arrays[channel] = arrays[channel]
	var uploaded := ArrayMesh.new()
	uploaded.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	uploaded.surface_set_material(0, material)
	mesh = uploaded
	_source = weakref(uploaded)


static func query_arrays(node: MeshInstance3D) -> Array:
	if node is EIWaterMesh and node._source != null and node._source.get_ref() == node.mesh:
		return node._query_arrays
	# Synthetic/custom geometry and replaced meshes retain the ordinary path.
	return node.mesh.surface_get_arrays(0)

class_name FirstPersonBody
extends RefCounted
## A local view mesh: lower the neck into its collar, then close its open rim.
## The rest of the torso, UVs, skin weights and original mesh stay unchanged.
## This runs once on entering first person, never during animation updates.

static func make(source: ArrayMesh, surface: int, first: int, count: int,
		center: Vector3, collar: float, radius: float) -> ArrayMesh:
	var result := ArrayMesh.new()
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		if s == surface:
			_close_neck(arrays, first, count, center, collar, radius)
		result.add_surface_from_arrays(source.surface_get_primitive_type(s), arrays)
		result.surface_set_material(s, source.surface_get_material(s))
	return result


static func _close_neck(a: Array, first: int, count: int, center: Vector3,
		collar: float, radius: float) -> void:
	var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var tangents: PackedFloat32Array = a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES] if a[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS] if a[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var lowered := {}
	var keys := {}
	for i in range(first, first + count):
		var v := vertices[i]
		# Work inside the neck column only; raised armour shoulders stay intact.
		if v.y > collar and Vector2(v.x - center.x, v.z - center.z).length() < radius:
			lowered[i] = true
		keys[i] = v.snapped(Vector3.ONE * 0.00001)
	# Position keys weld UV/normal seams for topology only. The original
	# distinct vertices keep their own texture coordinates and skin weights.
	var edges := {}
	for t in range(0, indices.size(), 3):
		if indices[t] < first or indices[t] >= first + count: continue
		for j in 3:
			var i := indices[t + j]
			var k := indices[t + (j + 1) % 3]
			var edge := [keys[i], keys[k]]
			var reverse := [keys[k], keys[i]]
			if edges.has(reverse): edges.erase(reverse)
			else: edges[edge] = [i, k]
	# A garment may have its own open hem near the collar. Cap each complete
	# neck rim separately, without bridging it to unrelated clothing edges.
	var pending: Array = edges.values()
	var rims := []
	while not pending.is_empty():
		var rim := [pending.pop_back()]
		var connected := {keys[rim[0][0]]:true, keys[rim[0][1]]:true}
		var growing := true
		while growing:
			growing = false
			for i in range(pending.size()-1, -1, -1):
				var edge: Array = pending[i]
				if connected.has(keys[edge[0]]) or connected.has(keys[edge[1]]):
					connected[keys[edge[0]]] = true
					connected[keys[edge[1]]] = true
					rim.append(edge); pending.remove_at(i); growing = true
		var complete := rim.size() >= 3
		for edge: Array in rim:
			complete = complete and lowered.has(edge[0]) and lowered.has(edge[1])
		if complete: rims.append(rim)
	for i: int in lowered:
		vertices[i].y = collar
		normals[i] = Vector3.UP
		if not tangents.is_empty():
			for j in 4: tangents[i * 4 + j] = [1.0, 0.0, 0.0, 1.0][j]
	for rim: Array in rims:
		var rim_vertices := {}
		for edge: Array in rim:
			rim_vertices[keys[edge[0]]] = edge[0]
			rim_vertices[keys[edge[1]]] = edge[1]
		var at := Vector3.ZERO
		var front: int = rim_vertices.values()[0]
		for i: int in rim_vertices.values():
			at += vertices[i]
			if vertices[i].z > vertices[front].z: front = i
		at /= rim_vertices.size()
		# The front/back neck UVs are separate atlas islands. Interpolating
		# across them samples unrelated (even transparent) texels. Fill the
		# closed collar with the opaque front-neck texel instead.
		var tex := uv[front]
		for i: int in lowered: uv[i] = tex
		# Reverse each boundary edge so the cap shares it with the neck band.
		# Duplicate cap vertices for a flat normal without changing the chest.
		for edge: Array in rim:
			var start := vertices.size()
			for i: int in [edge[1], edge[0], -1]:
				vertices.append(at if i == -1 else vertices[i])
				normals.append(Vector3.UP)
				uv.append(tex)
				if not tangents.is_empty(): tangents.append_array([1.0, 0.0, 0.0, 1.0])
				if not bones.is_empty():
					var b: int = edge[0] if i == -1 else i
					bones.append_array(bones.slice(b * 4, b * 4 + 4))
					weights.append_array(weights.slice(b * 4, b * 4 + 4))
			indices.append_array([start, start + 1, start + 2])
	a[Mesh.ARRAY_VERTEX] = vertices
	a[Mesh.ARRAY_NORMAL] = normals
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_INDEX] = indices
	if not tangents.is_empty(): a[Mesh.ARRAY_TANGENT] = tangents
	if not bones.is_empty():
		a[Mesh.ARRAY_BONES] = bones
		a[Mesh.ARRAY_WEIGHTS] = weights

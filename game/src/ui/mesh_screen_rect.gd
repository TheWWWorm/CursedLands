extends RefCounted
## A drawn figure part's screen rectangle: native 5a7640/5a7a70 copy the
## renderer's bounds after transforming the actual mesh. In 4e9010 a partly
## clipped mesh goes through TLP+94 and +88 before 4e86b0 collects bounds;
## 4e8900 collects all projected vertices when the mesh is wholly inside.
## No AABB corners or vertices behind the near plane belong in that rect.

# Array payloads may outlive a zone through EIFigure's shared templates.
# Evict cold entries individually; retain no strong Node/Resource references.
const SOURCE_LIMIT := 32 * 1024 * 1024
const RECT_LIMIT := 8 * 1024 * 1024
const META_LIMIT := 4096
static var _kernel: RefCounted = _make_kernel()


static func _make_kernel() -> RefCounted:
	return ClassDB.instantiate("ScreenRectKernel") if not OS.get_cmdline_user_args().has("--ei-script-picking") and ClassDB.class_exists("ScreenRectKernel") else null


static var _meshes := {}   # weak mesh, stable resource revision, optional arrays
static var _views := {}    # camera -> exact adjusted transform/projection context
static var _rects := {}    # part -> exact pose/context and projected result
static var _revision := 0
static var _stamp := 0
static var _new_entries := 0
static var _source_bytes := 0
static var _rect_bytes := 0


static func _mesh_meta(mesh: Mesh) -> Dictionary:
	var id := mesh.get_instance_id()
	if _meshes.has(id) and _meshes[id].ref.get_ref() == mesh:
		_stamp += 1
		_meshes[id].stamp = _stamp
		return _meshes[id]
	_revision += 1
	_stamp += 1
	var data := {"ref": weakref(mesh), "surfaces": [], "revision": _revision,
		"loaded": false, "bytes": 0, "stamp": _stamp}
	_meshes[id] = data
	var changed := _mesh_changed.bind(id)
	if not mesh.changed.is_connected(changed):
		mesh.changed.connect(changed)
	_new_entry()
	return data


## Only geometry used by exact bounds is retained. Morph normals/tangents,
## which previously shared these arrays, never contribute to projection.
static func _mesh_data(mesh: Mesh) -> Dictionary:
	var data := _mesh_meta(mesh)
	if data.loaded:
		return data
	var surfaces := []
	var bytes := 512
	for i in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(i)
		if a.is_empty() or a[Mesh.ARRAY_VERTEX] == null:
			continue
		var shapes := []
		if mesh is ArrayMesh:
			for shape: Array in mesh.surface_get_blend_shape_arrays(i):
				var vertices: PackedVector3Array = shape[Mesh.ARRAY_VERTEX] if shape[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
				shapes.append(vertices)
				bytes += vertices.size() * 12 + 64
		var surface := {"vertices": a[Mesh.ARRAY_VERTEX], "indices": a[Mesh.ARRAY_INDEX],
			"bones": a[Mesh.ARRAY_BONES], "weights": a[Mesh.ARRAY_WEIGHTS],
			"shapes": shapes, "primitive": mesh.surface_get_primitive_type(i), "extrema": _extrema(a[Mesh.ARRAY_VERTEX])}
		surfaces.append(surface)
		bytes += surface.vertices.size() * 12 + 512
		for array in [surface.indices, surface.bones, surface.weights]:
			if array != null:
				bytes += array.size() * 4 + 64
	if bytes > SOURCE_LIMIT:
		# An unusually large source is returned for this call, never retained.
		data = data.duplicate()
		data.surfaces = surfaces
	else:
		data.surfaces = surfaces
		data.bytes = bytes
		data.loaded = true
		_source_bytes += bytes
		_trim_sources(mesh.get_instance_id())
	return data


## Exact immutable extrema only decide whether the original per-vertex
## outcode loop can be skipped. They never become the returned rectangle.
static func _extrema(vertices: PackedVector3Array) -> Array:
	if vertices.is_empty():
		return []
	var lo := vertices[0]
	var hi := lo
	for point: Vector3 in vertices:
		lo = lo.min(point)
		hi = hi.max(point)
	return [lo, hi]


static func _rigid_class(surface: Dictionary, xf: Transform3D, planes: Array[Plane]) -> int:
	if surface.extrema.is_empty() or surface.vertices.size() < 16:
		return 0
	var lo: Vector3 = surface.extrema[0]
	var hi: Vector3 = surface.extrema[1]
	var corners := PackedVector3Array()
	for x in [lo.x, hi.x]:
		for y in [lo.y, hi.y]:
			for z in [lo.z, hi.z]:
				corners.append(Vector3(x, y, z))
	corners = xf * corners
	var local_max := lo.abs().max(hi.abs())
	var magnitude := xf.basis.x.abs() * local_max.x + xf.basis.y.abs() * local_max.y + xf.basis.z.abs() * local_max.z + xf.origin.abs()
	var inside := true
	for plane: Plane in planes:
		var minimum := INF
		var maximum := -INF
		for point: Vector3 in corners:
			var distance := plane.distance_to(point)
			minimum = minf(minimum, distance)
			maximum = maxf(maximum, distance)
		# Deliberately broad compared with binary32's transform/dot error
		# bound. Cancellation, scaled parents and plane offsets contribute.
		# Every uncertain boundary retains the original polygon clipping.
		var guard := (plane.normal.abs().dot(magnitude) + absf(plane.d) + 1.0) * 0.0001
		if minimum > guard:
			return -1
		if maximum >= -guard:
			inside = false
	return 1 if inside else 0


static func _drop_arrays(data: Dictionary) -> void:
	_source_bytes -= int(data.bytes)
	data.bytes = 0
	data.surfaces = []
	data.loaded = false


static func _mesh_changed(id: int) -> void:
	if _meshes.has(id):
		_drop_arrays(_meshes[id])
		_revision += 1
		_meshes[id].revision = _revision


static func _trim_sources(keep_id: int) -> void:
	if _source_bytes <= SOURCE_LIMIT:
		return
	var cold := []
	for id: int in _meshes:
		if id != keep_id and _meshes[id].loaded:
			cold.append([_meshes[id].stamp, id])
	cold.sort()
	for entry: Array in cold:
		_drop_arrays(_meshes[entry[1]])
		if _source_bytes <= SOURCE_LIMIT * 3 / 4:
			break


static func _arrays(mesh: Mesh) -> Array:
	return _mesh_data(mesh).surfaces


static func _new_entry() -> void:
	_new_entries += 1
	if _new_entries < 128:
		return
	_new_entries = 0
	for id: int in _meshes.keys():
		if _meshes[id].ref.get_ref() == null:
			_drop_arrays(_meshes[id])
			_meshes.erase(id)
	if _meshes.size() > META_LIMIT:
		var cold := []
		for id: int in _meshes:
			cold.append([_meshes[id].stamp, id])
		cold.sort()
		for i in _meshes.size() - META_LIMIT:
			var id: int = cold[i][1]
			_drop_arrays(_meshes[id])
			_meshes.erase(id)
	for id: int in _views.keys():
		if _views[id].ref.get_ref() == null:
			_views.erase(id)
	for id: int in _rects.keys():
		if _rects[id].ref.get_ref() == null:
			_drop_rect(id)


static func _camera_exited(id: int) -> void:
	_views.erase(id)


static func _part_exited(id: int) -> void:
	_drop_rect(id)


static func _drop_rect(id: int) -> void:
	if _rects.has(id):
		_rect_bytes -= int(_rects[id].bytes)
		_rects.erase(id)


## Camera3D uses this exact adjusted/interpolated transform, projection and
## viewport size for both its frustum and unproject_position implementation.
static func camera_context(cam: Camera3D) -> Dictionary:
	if cam == null or not cam.is_inside_tree():
		return {}
	var id := cam.get_instance_id()
	var key := [cam.get_camera_projection(), cam.get_camera_transform(), cam.get_viewport().get_visible_rect().size]
	if _views.has(id) and _views[id].ref.get_ref() == cam and _views[id].key == key:
		return _views[id]
	_revision += 1
	var xf: Transform3D = key[1]
	var view := {"ref": weakref(cam), "key": key, "planes": cam.get_frustum(), "revision": _revision,
		"projection": key[0], "inverse_basis": xf.basis.transposed(), "origin": xf.origin, "size": key[2]}
	_views[id] = view
	var exited := _camera_exited.bind(id)
	if not cam.tree_exiting.is_connected(exited):
		cam.tree_exiting.connect(exited)
	_new_entry()
	return view


## Keep native Camera3D arithmetic ordering: float32 basis/projection/divide,
## then its double literal pixel mapping and final float32 Vector2 store.
static func _project(point: Vector3, view: Dictionary) -> Vector2:
	var local: Vector3 = view.inverse_basis * (point - view.origin)
	var projected: Vector4 = view.projection * Vector4(local.x, local.y, local.z, 1.0)
	if projected.w == 0.0:
		return Vector2.ZERO
	var normal := Vector3(projected.x, projected.y, projected.z) / projected.w
	var size: Vector2 = view.size
	return Vector2((normal.x * 0.5 + 0.5) * size.x, (-normal.y * 0.5 + 0.5) * size.y)


## Bind poses and named/indexed bones resolve exactly as in _posed. Bone,
## bind and skeleton changes therefore invalidate a skinned part's result.
static func _skin_poses(mi: MeshInstance3D) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	if mi.skin == null:
		return poses
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if skel == null:
		return poses
	for i in mi.skin.get_bind_count():
		var name := mi.skin.get_bind_name(i)
		var bone := skel.find_bone(name) if not name.is_empty() else mi.skin.get_bind_bone(i)
		poses.append(skel.get_bone_global_pose(bone) * mi.skin.get_bind_pose(i) if bone >= 0 else Transform3D.IDENTITY)
	return poses


## EI's morph frames are normalized full vertex arrays. The optional smooth
## joints body uses the same current skin poses as its rendered mesh.
static func _posed(mi: MeshInstance3D, s: Dictionary) -> PackedVector3Array:
	var base: PackedVector3Array = s.vertices
	var deforming := mi.skin != null
	for k in s.shapes.size():
		deforming = deforming or not is_zero_approx(mi.get_blend_shape_value(k))
	if not deforming:
		return base
	# Packed array variants share mutable contents; every deformation must
	# own its destination even when a prior instance used the same source.
	var vs: PackedVector3Array = base.duplicate()
	for k in s.shapes.size():
		var w := mi.get_blend_shape_value(k)
		if is_zero_approx(w):
			continue
		var shape: PackedVector3Array = s.shapes[k]
		if shape.size() != vs.size():
			continue
		for i in vs.size():
			vs[i] += (shape[i] - base[i] if (mi.mesh as ArrayMesh).blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else shape[i]) * w
	if mi.skin == null or s.bones == null or s.weights == null:
		return vs
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if skel == null or s.weights.is_empty():
		return vs
	var poses: Array[Transform3D] = []
	for i in mi.skin.get_bind_count():
		var name := mi.skin.get_bind_name(i)
		var bone := skel.find_bone(name) if not name.is_empty() else mi.skin.get_bind_bone(i)
		poses.append(skel.get_bone_global_pose(bone) * mi.skin.get_bind_pose(i) if bone >= 0 else Transform3D.IDENTITY)
	var stride := int(s.weights.size() / vs.size())
	for i in vs.size():
		var p := Vector3.ZERO
		for j in stride:
			var at := i * stride + j
			var b := int(s.bones[at])
			if b >= 0 and b < poses.size():
				p += (poses[b] * vs[i]) * float(s.weights[at])
		vs[i] = p
	return vs


## Frustum plane normals point outwards (Camera3D.is_position_in_frustum).
static func _clip(poly: PackedVector3Array, planes: Array[Plane]) -> PackedVector3Array:
	for plane: Plane in planes:
		if poly.is_empty():
			break
		var next := PackedVector3Array()
		var prev := poly[poly.size() - 1]
		var dp := plane.distance_to(prev)
		for point: Vector3 in poly:
			var d := plane.distance_to(point)
			if (d <= 0.0) != (dp <= 0.0):
				next.append(prev.lerp(point, dp / (dp - d)))
			if d <= 0.0:
				next.append(point)
			prev = point
			dp = d
		poly = next
	return poly


static func of(mi: MeshInstance3D, cam: Camera3D) -> Rect2i:
	return of_context(mi, cam, camera_context(cam))


## One context can serve every part in one synchronous screen_rects call.
## No approximation is introduced: unchanged inputs reuse the exact result.
static func of_context(mi: MeshInstance3D, cam: Camera3D, view: Dictionary) -> Rect2i:
	if mi.mesh == null or not mi.is_visible_in_tree() or cam == null or view.is_empty():
		return Rect2i()
	var planes: Array[Plane] = view.planes
	if planes.size() != 6:
		return Rect2i()
	var xf := mi.get_global_transform_interpolated()
	var data := _mesh_meta(mi.mesh)
	var weights := PackedFloat64Array()
	for i in mi.mesh.get_blend_shape_count():
		weights.append(mi.get_blend_shape_value(i))
	var key := [data.revision, view.revision, xf, weights, _skin_poses(mi) if mi.skin != null else []]
	var id := mi.get_instance_id()
	if _rects.has(id) and _rects[id].ref.get_ref() == mi and _rects[id].key == key:
		_stamp += 1
		_rects[id].stamp = _stamp
		return _rects[id].rect
	data = _mesh_data(mi.mesh)
	if _kernel != null:
		var surfaces := []
		for s: Dictionary in data.surfaces:
			surfaces.append([xf * _posed(mi, s), s.indices if s.indices != null else PackedInt32Array(), s.primitive])
		return _remember(mi, key, _kernel.bounds(surfaces, planes, view.projection, view.inverse_basis, view.origin, view.size))
	var deforming := mi.skin != null
	for value in weights:
		deforming = deforming or not is_zero_approx(value)
	var points := PackedVector3Array()
	for s: Dictionary in data.surfaces:
		var classification: int = 0 if deforming else _rigid_class(s, xf, planes)
		if classification < 0:
			continue
		var vs: PackedVector3Array = xf * _posed(mi, s)
		if classification > 0:
			points.append_array(vs)
			continue
		var outside := 0
		var common := 63
		for i in vs.size():
			var code := 0
			for j in planes.size():
				if planes[j].is_point_over(vs[i]):
					code |= 1 << j
			outside |= code
			common &= code
		if common != 0:
			continue
		if outside == 0:
			points.append_array(vs)
			continue
		var idx: PackedInt32Array = s.indices if s.indices != null else PackedInt32Array()
		if idx.is_empty():
			for i in vs.size():
				idx.append(i)
		if s.primitive == Mesh.PRIMITIVE_TRIANGLES:
			for i in range(0, idx.size() - 2, 3):
				points.append_array(_clip(PackedVector3Array([vs[idx[i]], vs[idx[i + 1]], vs[idx[i + 2]]]), planes))
		elif s.primitive == Mesh.PRIMITIVE_TRIANGLE_STRIP:
			for i in idx.size() - 2:
				points.append_array(_clip(PackedVector3Array([vs[idx[i]], vs[idx[i + 1]], vs[idx[i + 2]]]), planes))
	if points.is_empty():
		return _remember(mi, key, Rect2i())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector3 in points:
		var screen := _project(p, view)
		lo = lo.min(screen)
		hi = hi.max(screen)
	# Drawn parts copy renderer 4e86b0/4e8900's FISTP bounds, with nearest
	# ties to even. TLP startup changes precision only; scoped game math RC
	# changes restore their old mode. The standalone 5a8e60 __ftol helper
	# truncates instead, but is not the rectangle copied by the draw path.
	var start := Vector2i(_pixel(lo.x), _pixel(lo.y))
	var end := Vector2i(_pixel(hi.x), _pixel(hi.y))
	return _remember(mi, key, Rect2i(start, end - start) if end.x > start.x and end.y > start.y else Rect2i())


static func _remember(mi: MeshInstance3D, key: Array, rect: Rect2i) -> Rect2i:
	var id := mi.get_instance_id()
	_stamp += 1
	# Conservative per-entry bookkeeping, plus actual variable array payloads.
	var bytes: int = 1024 + key[3].size() * 8 + key[4].size() * 128
	if _rects.has(id):
		var data: Dictionary = _rects[id]
		_rect_bytes += bytes - int(data.bytes)
		data.key = key
		data.rect = rect
		data.bytes = bytes
		data.stamp = _stamp
	else:
		_rects[id] = {"ref": weakref(mi), "key": key, "rect": rect, "bytes": bytes, "stamp": _stamp}
		_rect_bytes += bytes
		var exited := _part_exited.bind(id)
		if not mi.tree_exiting.is_connected(exited):
			mi.tree_exiting.connect(exited)
		_new_entry()
	if _rect_bytes > RECT_LIMIT:
		var cold := []
		for cached_id: int in _rects:
			cold.append([_rects[cached_id].stamp, cached_id])
		cold.sort()
		for entry: Array in cold:
			_drop_rect(entry[1])
			if _rect_bytes <= RECT_LIMIT * 3 / 4:
				break
	return rect


static func _pixel(x: float) -> int:
	var f := floorf(x)
	var d := x - f
	return int(f) + 1 if d > 0.5 or (d == 0.5 and int(f) % 2 != 0) else int(f)

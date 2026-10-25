extends GroundMarks
## Exact pre-change method, for an isolated same-scene timing control.
func _sole_contact(n: Node3D) -> Dictionary:
	if n.has_meta(EIFigureGeometry.META):
		var box := n.global_transform * EIFigureGeometry.box(n.get_meta(EIFigureGeometry.META))
		var centre := box.get_center()
		if box.position.y > world.terrain.ground_at(centre.x, -centre.z) + 0.09:
			return {}
	var points := PackedVector3Array()
	var bottom := INF
	# Smoothed figures retain the authored part mesh for gameplay geometry,
	# but render it in one skinned body. Its sole still follows this foot bone.
	# There is no MeshInstance child after switching to direct controls.
	if n.has_meta("weld_mesh") and n.is_visible_in_tree():
		var mesh: ArrayMesh = n.get_meta("weld_mesh")[0]
		for vertex: Vector3 in _sole_vertices(mesh):
			var p := n.global_transform * vertex
			points.append(p)
			bottom = minf(bottom, p.y)
	for child: Node in n.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var transform := mi.global_transform
		for vertex: Vector3 in _sole_vertices(mi.mesh):
			var p := transform * vertex
			points.append(p)
			bottom = minf(bottom, p.y)
	if points.is_empty():
		return {}
	# Use the actual sole/tip, not the ankle pivot or the whole shin's box.
	var forward := Vector2(n.global_basis.z.x, -n.global_basis.z.z).normalized()
	if forward.length_squared() < 0.1: forward = Vector2.UP
	var across := Vector2(forward.y, -forward.x)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p: Vector3 in points:
		if p.y > bottom + 0.035:
			continue
		var xy := Vector2(p.x, -p.z)
		var local := Vector2(xy.dot(across), xy.dot(forward))
		lo = lo.min(local)
		hi = hi.max(local)
	var mid := (lo + hi) * 0.5
	var p := across * mid.x + forward * mid.y
	if bottom > world.terrain.ground_at(p.x, p.y) + 0.075:
		return {}
	var extent := ((hi - lo) * 0.5).clamp(Vector2(0.025, 0.045), Vector2(0.32, 0.46))
	return {"p": p, "extent": extent, "angle": forward.angle() - PI * 0.5, "height": bottom}


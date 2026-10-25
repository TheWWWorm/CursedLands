extends GroundMarkProjection
## Untouched place() from 3c0e375d for the same-scene comparison.
func place(mark: GroundMarks.Mark, rebuild := false) -> void:
	_centre = Vector2(mark.x, mark.y)
	_across = Vector2(mark.decal.basis.x.x, -mark.decal.basis.x.z)
	_along = Vector2(mark.decal.basis.z.x, -mark.decal.basis.z.z)
	_half = Vector2(maxf(mark.a, 0.01), maxf(mark.b, 0.01))
	_height = mark.decal.position.y
	var material: ShaderMaterial = mark.projection.material_override
	material.set_shader_parameter("centre_height",_height + world.global_position.y)
	material.set_shader_parameter("animated_projection",not mark.foot)
	if not mark.foot:
		# Blood keeps turning for its entire lifetime. Re-clipping and
		# tessellating every pool at every tick causes a frame-time feedback
		# loop once several kills leave marks behind. Clip a conservative patch
		# once; the shader projects the exact current rectangle onto that patch.
		material.set_shader_parameter("projection_center",_centre)
		material.set_shader_parameter("projection_axes",Vector4(
			_across.x/(_half.x*2.0),_across.y/(_half.x*2.0),
			_along.x/(_half.y*2.0),_along.y/(_half.y*2.0)))
		var grown := Vector2(mark.a,mark.b) + Vector2.ONE * mark.grow * maxi(mark.grow_left,0)
		var radius := maxf(_half.length(),grown.max(Vector2.ONE*0.01).length())
		var origin := Vector3(mark.x,mark.y,_height)
		if not rebuild and mark.projection.mesh != null and origin.is_equal_approx(mark.projection_origin) \
				and radius <= mark.projection_radius + 0.0001:
			return
		mark.projection_radius = radius
		mark.projection_origin = origin
		_across = Vector2.RIGHT; _along = Vector2.DOWN
		_half = Vector2.ONE * radius
	_verts.clear(); _uvs.clear(); _grids.clear(); _normals.clear(); _colors.clear()
	var radius := _across.abs() * _half.x + _along.abs() * _half.y
	_bounds = Rect2(_centre - radius, radius * 2.0)
	var terrain := world.terrain
	var first := Vector2i((_bounds.position - Vector2.ONE).floor()).max(Vector2i.ZERO)
	var last := Vector2i((_bounds.end + Vector2.ONE).ceil()).min(Vector2i(terrain.size_ei()) - Vector2i.ONE)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var corners: Array[Vector2] = [Vector2(x,y),Vector2(x+1,y),Vector2(x,y+1),Vector2(x+1,y+1)]
			var points: Array[Vector3] = []
			for grid in corners:
				var i := int(grid.y) * terrain.grid_w + int(grid.x)
				var xy := grid + terrain.land_xy[i]
				points.append(Vector3(xy.x,terrain.heights[i],-xy.y))
			for ids: Array in [[2,1,0],[1,2,3]]:
				triangle([points[ids[0]],points[ids[1]],points[ids[2]]],
					[corners[ids[0]],corners[ids[1]],corners[ids[2]]], 4 if Gfx.on("gfx_soft_ground") else 0, true)
	for ref in receivers:
		var receiver := ref.get_ref() as MeshInstance3D
		if receiver == null or receiver.mesh == null or not receiver.is_visible_in_tree(): continue
		var xf := world.global_transform.affine_inverse() * receiver.global_transform
		var box := xf * receiver.get_aabb()
		if not Rect2(Vector2(box.position.x,-box.end.z),Vector2(box.size.x,box.size.z)).intersects(_bounds): continue
		for arrays: Array in receiver_arrays(receiver.mesh):
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for j in range(0,count-2,3):
				var p: Array[Vector3] = []
				for k in 3: p.append(xf * vertices[indices[j+k] if not indices.is_empty() else j+k])
				triangle(p,[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO],0,false)
	var mesh := ArrayMesh.new()
	if not _verts.is_empty():
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=_verts; arrays[Mesh.ARRAY_NORMAL]=_normals
		arrays[Mesh.ARRAY_TEX_UV]=_uvs; arrays[Mesh.ARRAY_TEX_UV2]=_grids; arrays[Mesh.ARRAY_COLOR]=_colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mark.projection.mesh = mesh


extends "res://tools/tests/terrain_snow_contours.gd"
## A level crest is the counterexample to height-variance-only refinement:
## subdividing its wall cannot bend the straight edge shared with its cap.

func geometry_for(terrain: EITerrain, field: TerrainCliff) -> RefCounted:
	# Source-only headless iteration can use the new builder with an unchanged
	# qualified executable/PCK. Normal regression runs use its packaged source.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snow-builder-source="):
			return load(arg.trim_prefix("--snow-builder-source=")).new(terrain,field)
	return field.geometry


func deform_for() -> Node:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snow-deform-source="):
			return load(arg.trim_prefix("--snow-deform-source=")).new()
	return SoftGroundDeform.new()


func dense_tile(source: Array, tile: int) -> Array:
	var dense := []; dense.resize(Mesh.ARRAY_MAX)
	for channel in EITerrainSector.CHANNELS: dense[channel] = source[channel].slice(0,0)
	var indices := PackedInt32Array()
	var authored: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	for tri in 8:
		var at := tile*24+tri*3
		SoftGroundDeform._subdivide(dense,indices,source,authored[at],authored[at+1],authored[at+2])
	dense[Mesh.ARRAY_INDEX] = indices
	return dense

func shading_and_crest(source: Array, result: Array) -> void:
	var positions: PackedVector3Array = result[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = result[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = result[Mesh.ARRAY_TEX_UV]
	var ids: PackedInt32Array = result[Mesh.ARRAY_INDEX]
	var crest := 0; var bad_height := 0; var bad_normal := 0; var shared := {}
	var offset := 0.0; var walls := 0; var alignment := 0.0
	var authored := {}
	for i in source[Mesh.ARRAY_VERTEX].size(): authored[source[Mesh.ARRAY_TEX_UV][i]] = source[Mesh.ARRAY_VERTEX][i]
	for index in ids:
		var p := positions[index]; var grid := uv[index]
		var distance := Vector2(p.x,-p.z).distance_to(grid)
		offset = maxf(offset,distance)
		if p.y == 16.0 and distance > 0.005: crest += 1
		var cell := grid.floor().clamp(Vector2.ZERO,Vector2(31,31)); var f := grid-cell
		var expected_height: float
		if f.x+f.y<=1.0:
			expected_height = authored[cell].y*(1.0-f.x-f.y)+authored[cell+Vector2.RIGHT].y*f.x+authored[cell+Vector2.DOWN].y*f.y
		else:
			expected_height = authored[cell+Vector2.ONE].y*(f.x+f.y-1.0)+authored[cell+Vector2.RIGHT].y*(1.0-f.y)+authored[cell+Vector2.DOWN].y*(1.0-f.x)
		if absf(p.y-expected_height)>0.00001: bad_height += 1
		if shared.has(grid) and normals[index].normalized().distance_to(shared[grid]) > 0.00001: bad_normal += 1
		shared[grid] = normals[index].normalized()
	for i in range(0,ids.size(),3):
		var a := ids[i]; var b := ids[i+1]; var c := ids[i+2]
		# Godot's front-facing terrain uses clockwise winding.
		var geometric := (positions[c]-positions[a]).cross(positions[b]-positions[a]).normalized()
		if geometric.y > 0.2: continue
		walls += 1
		alignment += geometric.dot((normals[a]+normals[b]+normals[c]).normalized())
	check(crest > 20, "level snowy crests gain a curved silhouette shared with their caps: %d" % crest)
	check(offset <= 0.30001, "snow-only geometry stays within 30 cm: %.6f" % offset)
	check(bad_height == 0, "all interpolated authored heights remain exact: %d" % bad_height)
	check(bad_normal == 0, "shared curved edges retain coherent normals: %d" % bad_normal)
	check(walls > 100 and alignment/maxi(walls,1) > 0.75, "wall shading follows the geometric faces: %.6f" % (alignment/maxi(walls,1)))
	print("SNOW_ROUNDING_METRICS ",JSON.stringify({"crest_samples":crest,"max_offset":offset,"bad_heights":bad_height,"normal_seams":bad_normal,"wall_alignment":alignment/maxi(walls,1),"triangles":ids.size()/3}))

func dense_preserved(source: Array, builder: RefCounted) -> void:
	var tile := -1
	for key: int in builder.patches:
		var patch: Array = builder.patches[key]
		if patch[Mesh.ARRAY_VERTEX].size()>24: tile = key; break
	check(tile>=0,"rounding has a refined snow tile for the deformation check")
	if tile<0:return
	var dense := dense_tile(source,tile)
	var indices: PackedInt32Array = dense[Mesh.ARRAY_INDEX]
	var authored: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var combined := source.duplicate(true)
	var first: int = combined[Mesh.ARRAY_VERTEX].size()
	for channel in EITerrainSector.CHANNELS: combined[channel].append_array(dense[channel])
	combined[Mesh.ARRAY_INDEX] = PackedInt32Array()
	for row in 256:
		if row != tile: combined[Mesh.ARRAY_INDEX].append_array(authored.slice(row*24,row*24+24))
		else:
			for index in indices: combined[Mesh.ARRAY_INDEX].append(first+index)
	var result: Array = builder.arrays(combined)
	var retained := 0
	for index in result[Mesh.ARRAY_INDEX]:
		if index>=first and index<first+dense[Mesh.ARRAY_VERTEX].size(): retained += 1
	check(retained == indices.size(), "active footprints retain their complete 16-way tessellation")
	check(result[Mesh.ARRAY_TEX_UV].slice(first,first+dense[Mesh.ARRAY_VERTEX].size()) == dense[Mesh.ARRAY_TEX_UV]
		and result[Mesh.ARRAY_COLOR].slice(first,first+dense[Mesh.ARRAY_VERTEX].size()) == dense[Mesh.ARRAY_COLOR], "footprint texture coordinates and lighting channels stay exact")
	check(result == builder.arrays(combined), "cached dense snow geometry is deterministic")
	var sparse: Array = builder.arrays(source)
	var shared := {}; var mismatches := 0; var matched := 0
	for index in sparse[Mesh.ARRAY_INDEX]:
		if roundi(sparse[Mesh.ARRAY_TEX_UV2][index].y) == tile:
			shared[sparse[Mesh.ARRAY_TEX_UV][index]] = sparse[Mesh.ARRAY_VERTEX][index]
	for i in dense[Mesh.ARRAY_VERTEX].size():
		var grid: Vector2 = dense[Mesh.ARRAY_TEX_UV][i]
		if shared.has(grid):
			matched += 1
			if result[Mesh.ARRAY_VERTEX][first+i].distance_to(shared[grid])>0.00001: mismatches += 1
	check(matched>20 and mismatches==0, "dense snow and installed contour share the same surface: %d" % mismatches)


func boundary_continuity(terrain: EITerrain, source: Array, builder: RefCounted) -> void:
	var tile := 7*16+8
	var field := Field.new(terrain)
	field.eligible.fill(255)
	var rock: RefCounted = builder.get_script().new(terrain,field)
	rock.prepare(source)
	field.eligible.fill(0); field.eligible[tile] = 255
	var mixed: RefCounted = builder.get_script().new(terrain,field)
	mixed.prepare(source)
	check(mixed.patches[tile] == rock.patches[tile], "adjacent rock retains its exact existing contour and normals")
	var result: Array = mixed.arrays(source)
	var shared := {}; var seam_count := 0; var position_seams := 0; var normal_seams := 0
	for index in result[Mesh.ARRAY_INDEX]:
		var grid: Vector2 = result[Mesh.ARRAY_TEX_UV][index]
		var point: Vector3 = result[Mesh.ARRAY_VERTEX][index]
		var normal: Vector3 = result[Mesh.ARRAY_NORMAL][index].normalized()
		if shared.has(grid):
			seam_count += 1
			if point.distance_to(shared[grid][0])>0.00001: position_seams += 1
			if normal.distance_to(shared[grid][1])>0.00001: normal_seams += 1
		shared[grid] = [point,normal]
	check(seam_count>1000 and position_seams==0, "snow and original rock contour positions join exactly: %d" % position_seams)
	check(normal_seams==0, "snow and original rock contour normals join exactly: %d" % normal_seams)
	field.eligible[tile] = 0; field.geometry_eligible[tile] = 0
	var guarded: RefCounted = builder.get_script().new(terrain,field)
	guarded.prepare(source)
	check(not guarded.patches.has(tile), "unsupported neighbouring material keeps its authored triangles")
	result = guarded.arrays(source)
	var boundary_samples := 0; var boundary_changed := 0
	for index in result[Mesh.ARRAY_INDEX]:
		var grid: Vector2 = result[Mesh.ARRAY_TEX_UV][index]
		if not (((grid.x==16.0 or grid.x==18.0) and grid.y>=14.0 and grid.y<=16.0) \
			or ((grid.y==14.0 or grid.y==16.0) and grid.x>=16.0 and grid.x<=18.0)): continue
		boundary_samples += 1
		var point: Vector3 = result[Mesh.ARRAY_VERTEX][index]
		if Vector2(point.x,-point.z).distance_to(grid)>0.00001 or result[Mesh.ARRAY_NORMAL][index].distance_to(Vector3.UP)>0.00001: boundary_changed += 1
	check(boundary_samples>40 and boundary_changed==0, "unsupported material boundaries keep original positions and normals: %d" % boundary_changed)


func shadow_matches(rec: Dictionary, label: String) -> void:
	var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
	var shadow := (rec.shadow as WeakRef).get_ref() as MeshInstance3D
	check(shadow!=null and shadow.mesh!=null, label+" installs a touched-tile shadow surface")
	if shadow==null or shadow.mesh==null:return
	var visible := node.mesh.surface_get_arrays(0)
	var cast := shadow.mesh.surface_get_arrays(0)
	var first: int = rec.arrays[Mesh.ARRAY_VERTEX].size()
	var count: int = cast[Mesh.ARRAY_VERTEX].size()
	check(visible[Mesh.ARRAY_VERTEX].slice(first,first+count)==cast[Mesh.ARRAY_VERTEX], label+" shadow positions match the visible curved footprint mesh")
	check(visible[Mesh.ARRAY_NORMAL].slice(first,first+count)==cast[Mesh.ARRAY_NORMAL], label+" shadow normals match the visible curved footprint mesh")
	check(cast[Mesh.ARRAY_INDEX].size()==SoftGroundDeform.SUBDIV*SoftGroundDeform.SUBDIV*8*3, label+" keeps exactly the touched tile's shadow coverage")


func shadow_lifecycle(terrain: EITerrain, source: Array, builder: RefCounted) -> void:
	var field := Field.new(terrain); field.geometry = builder; terrain._cliffs = field
	terrain._land_mat = ShaderMaterial.new(); terrain._land_mat.shader = Shader.new()
	terrain._land_mat.shader.code = "shader_type spatial;"
	add_child(terrain); terrain.set_process(false)
	var sector := EITerrainSector.new(); sector.name = "Sector_0_0"; terrain.add_child(sector)
	sector.configure(source,terrain._land_mat,6,false); sector.set_cliff_geometry(builder)
	var soft = deform_for(); soft.terrain = terrain; terrain.add_child(soft); soft.set_process(false)
	var rec: Dictionary = soft._sector(Vector2i.ZERO)
	var tile := 7*16+8
	rec.tiles[tile] = dense_tile(source,tile)
	soft._rebuild(rec)
	shadow_matches(rec,"script rebuild")
	var kernel: Object = ClassDB.instantiate("SoftGroundMeshJob")
	check(kernel!=null and kernel.configure(source,{tile:null}),"native footprint worker accepts the curved crest tile")
	if kernel!=null:
		kernel.run()
		var result: Array = kernel.read_result()
		var original := result.duplicate(true)
		var previous: Mesh = (rec.shadow as WeakRef).get_ref().mesh
		soft._apply_mesh(rec,result[0],result[1],true)
		check(rec.has("shadow_pending") and (rec.shadow as WeakRef).get_ref().mesh==previous,"native shadow publication remains deferred")
		soft._publish_shadow(Vector2i.ZERO)
		shadow_matches(rec,"deferred native publish")
		check(result==original,"publishing curved shadows does not mutate the native worker snapshot")
	terrain._cliffs = null; sector.set_cliff_geometry(null); soft.refresh_geometry()
	shadow_matches(rec,"cliff Off")
	terrain._cliffs = field; sector.set_cliff_geometry(builder); soft.refresh_geometry()
	shadow_matches(rec,"cliff On")
	var shadow_ref: WeakRef = rec.shadow
	soft.clear()
	check(shadow_ref.get_ref()==null and soft.sectors.is_empty(),"clearing footprints removes their curved shadow mesh")
	remove_child(terrain)


func signed_offsets(terrain: EITerrain, builder: RefCounted) -> void:
	for pattern in 4:
		for y in 33:
			for x in 33:
				var dx := 125.0 if x%2==0 else -125.0
				var dy := 125.0 if y%2==0 else -125.0
				if pattern==0:dy=0.0
				elif pattern==1:dx=0.0
				elif pattern==3:
					dx=roundf(sin((x+y)*0.8)*50.0); dy=roundf(cos((x-y)*0.7)*50.0)
				terrain.land_xy[y*33+x]=Vector2(dx,dy)/252.0
		var field := Field.new(terrain)
		check(field.rejected_geometry==0,"signed XY fixture has valid original triangles: %d"%pattern)
		var source := source_mesh(terrain)
		var candidate: RefCounted = builder.get_script().new(terrain,field)
		candidate.prepare(source)
		var result: Array = candidate.arrays(source)
		var original := {}; var shared := {}
		for i in source[Mesh.ARRAY_VERTEX].size(): original[source[Mesh.ARRAY_TEX_UV][i]]=source[Mesh.ARRAY_VERTEX][i]
		var positions: PackedVector3Array = result[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = result[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = result[Mesh.ARRAY_TEX_UV]
		var ids: PackedInt32Array = result[Mesh.ARRAY_INDEX]
		var bad := 0; var seams := 0; var folded := 0; var max_offset := 0.0
		for index in ids:
			var p := positions[index]; var grid := uv[index]
			var cell := grid.floor().clamp(Vector2.ZERO,Vector2(31,31)); var f := grid-cell
			var authored: Vector3
			if f.x+f.y<=1.0:authored=original[cell]*(1.0-f.x-f.y)+original[cell+Vector2.RIGHT]*f.x+original[cell+Vector2.DOWN]*f.y
			else:authored=original[cell+Vector2.ONE]*(f.x+f.y-1.0)+original[cell+Vector2.RIGHT]*(1.0-f.y)+original[cell+Vector2.DOWN]*(1.0-f.x)
			max_offset=maxf(max_offset,p.distance_to(authored))
			if not p.is_finite() or not normals[index].is_finite() or absf(p.y-authored.y)>0.00001:bad+=1
			# Snow may inset a cosmetic ridge anchor; original source and
			# collision arrays remain immutable, and its height stays exact.
			if shared.has(grid) and (p.distance_to(shared[grid][0])>0.00001 or normals[index].normalized().distance_to(shared[grid][1])>0.00001):seams+=1
			shared[grid]=[p,normals[index].normalized()]
		for i in range(0,ids.size(),3):
			var a:=positions[ids[i]];var b:=positions[ids[i+1]];var c:=positions[ids[i+2]]
			var grid:Vector2=(uv[ids[i]]+uv[ids[i+1]]+uv[ids[i+2]])/3.0
			var cell:=grid.floor().clamp(Vector2.ZERO,Vector2(31,31));var f:=grid-cell
			var pa:Vector3=original[cell];var pb:Vector3=original[cell+Vector2.RIGHT];var pc:Vector3=original[cell+Vector2.DOWN]
			if f.x+f.y>1.0:pa=original[cell+Vector2.ONE];var swap:=pb;pb=pc;pc=swap
			if (c-a).cross(b-a).length_squared()<1e-14 or (c-a).cross(b-a).dot((pb-pa).cross(pc-pa))<=0.0:folded+=1
		var intersecting:=crossings(result)
		check(bad==0 and max_offset<=0.30002,"signed XY refinement retains heights and its 30 cm presentation bound: %d"%pattern)
		check(seams==0,"signed XY refinement has continuous edge positions and normals: %d"%pattern)
		check(folded==0,"narrow signed XY triangles retain nonzero area and winding: %d/%d"%[pattern,folded])
		check(intersecting==0,"narrow signed XY contours do not intersect: %d/%d"%[pattern,intersecting])
		print("SNOW_OFFSET_METRICS ",JSON.stringify({"pattern":pattern,"max_offset":max_offset,"bad":bad,"seams":seams,"folded":folded,"intersections":intersecting}))
	terrain.land_xy.fill(Vector2.ZERO)


func planes(terrain: EITerrain, builder: RefCounted) -> void:
	terrain.heights.fill(0.0)
	var flat := source_mesh(terrain)
	var field := Field.new(terrain)
	var plain: RefCounted = builder.get_script().new(terrain,field)
	plain.prepare(flat)
	check(plain.arrays(flat)==flat, "flat snowy floors retain byte-identical mesh channels")
	for y in 33:
		for x in 33: terrain.heights[y*33+x] = x*4.0
	terrain.land_n.fill(Vector3(-4,1,0).normalized())
	var slope := source_mesh(terrain)
	field = Field.new(terrain)
	plain = builder.get_script().new(terrain,field)
	plain.prepare(slope)
	var result: Array = plain.arrays(slope)
	var changed := 0
	for index in result[Mesh.ARRAY_INDEX]:
		var grid: Vector2 = result[Mesh.ARRAY_TEX_UV][index]
		if result[Mesh.ARRAY_VERTEX][index].distance_to(Vector3(grid.x,grid.x*4.0,-grid.y))>0.00001: changed += 1
	check(changed==0, "planar snowy slopes remain on their original surface")
	check(result[Mesh.ARRAY_INDEX].size()==slope[Mesh.ARRAY_INDEX].size(), "planar snowy slopes do not allocate unneeded subdivisions")


func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	Gfx.ensure_globals()
	var terrain := snow_fixture()
	if terrain != null:
		# The crest changes direction while remaining level. A straight ridge
		# needs no PN curvature; these small ledges expose the reported wedges.
		for y in 33:
			for x in 33: terrain.heights[y*33+x] = 16.0 if x+y>=32+(int(y/4)%2) else 0.0
		var source := source_mesh(terrain); var original := source.duplicate(true)
		var field := Field.new(terrain)
		var builder := geometry_for(terrain,field)
		check(builder!=null,"snow owns a bounded presentation builder")
		if builder!=null:
			builder.prepare(source)
			var result: Array = builder.arrays(source)
			inspect(source,result,false,0.30002)
			shading_and_crest(source,result)
			dense_preserved(source,builder)
			boundary_continuity(terrain,source,builder)
			shadow_lifecycle(terrain,source,builder)
			check(source==original,"rounding leaves original vertex, collision and material input untouched")
			signed_offsets(terrain,builder)
			planes(terrain,builder)
		terrain.free()
	TexUpscale.shutdown()
	print("SNOW_ROUNDING ",checks," checks ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)

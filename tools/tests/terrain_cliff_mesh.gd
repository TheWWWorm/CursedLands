extends "res://tools/tests/terrain_cliffs.gd"

func source_mesh(terrain: EITerrain) -> Array:
	var points := PackedVector3Array()
	for y in 33:
		for x in 33:
			var offset := terrain.land_xy[y*33+x]
			points.append(Vector3(x+offset.x,terrain.heights[y*33+x],-y-offset.y))
	var source := terrain._mesh_arrays([points,terrain.land_n],terrain.land_tile,PackedInt32Array())
	# Parametric grid coordinates let this test compare independently emitted
	# edge vertices without using the refinement implementation to predict them.
	for i in source[Mesh.ARRAY_VERTEX].size():
		var tile := roundi(source[Mesh.ARRAY_TEX_UV2][i].y)
		source[Mesh.ARRAY_TEX_UV][i]=Vector2(tile%16,tile/16)*2+Vector2(i%3,(i%9)/3)
	return source

func shifted_boundary() -> void:
	var terrain := fixture(0)
	# Signed MPR displacement bytes can put an anchor just beyond the nearest
	# metre. Eligibility belongs to its original tile, not its rounded position.
	var offset := Vector2(-128.0/252.0,127.0/252.0)
	terrain.land_xy.fill(offset)
	for y in 33:
		for x in 33:terrain.heights[y*33+x]=16.0 if x+y>=32 else 0.0
	terrain.land_tile[7*16+8]=1
	var source := source_mesh(terrain)
	var field := Field.new(terrain,rules())
	field.geometry.prepare(source)
	var result:Array=field.geometry.arrays(source)
	var checked:=0;var displaced:=0
	for index in result[Mesh.ARRAY_INDEX]:
		var grid:Vector2=result[Mesh.ARRAY_TEX_UV][index]
		if not (((grid.x==16.0 or grid.x==18.0) and grid.y>=14.0 and grid.y<=16.0) \
			or ((grid.y==14.0 or grid.y==16.0) and grid.x>=16.0 and grid.x<=18.0)):continue
		checked+=1
		var a:=Vector2i(grid.floor());var f:=grid-Vector2(a)
		var height:=lerpf(lerpf(terrain.heights[a.y*33+a.x],terrain.heights[a.y*33+a.x+1],f.x),
			lerpf(terrain.heights[(a.y+1)*33+a.x],terrain.heights[(a.y+1)*33+a.x+1],f.x),f.y)
		var expected:=Vector3(grid.x+offset.x,height,-grid.y-offset.y)
		if result[Mesh.ARRAY_VERTEX][index].distance_to(expected)>0.00001:displaced+=1
	check(checked>40 and displaced==0,"shifted unsupported boundaries remain stationary: %d"%displaced)
	terrain.free()

func orientation(a:Vector2,b:Vector2,c:Vector2)->float:
	# Scalar arithmetic stays in double precision. The engine's float32
	# segment helper can report an interior hit for nearly collinear segments
	# that only share an endpoint, especially far along a terrain grid.
	return (float(b.x)-a.x)*(float(c.y)-a.y)-(float(b.y)-a.y)*(float(c.x)-a.x)

func crossings(result: Array) -> int:
	# A curved cave wall may overhang in XZ. Test actual wall intersections
	# in horizontal cross sections, rather than treating overhangs as flipped
	# 3D faces. Heights are unchanged by the presentation refinement.
	var points:PackedVector3Array=result[Mesh.ARRAY_VERTEX]
	var ids:PackedInt32Array=result[Mesh.ARRAY_INDEX]
	var count:=0
	for level in [0.37,1.37,2.37,3.37,5.37,7.37,9.37,11.37,13.37,15.37]:
		var segments:=[]
		for i in range(0,ids.size(),3):
			var hits:=PackedVector2Array()
			for edge in 3:
				var a:=points[ids[i+edge]];var b:=points[ids[i+(edge+1)%3]]
				if (a.y-level)*(b.y-level)<0.0:
					var p:=a.lerp(b,(level-a.y)/(b.y-a.y));hits.append(Vector2(p.x,p.z))
			if hits.size()==2:segments.append(hits)
		for i in segments.size():
			var a:PackedVector2Array=segments[i]
			for j in range(i+1,segments.size()):
				var b:PackedVector2Array=segments[j]
				if orientation(a[0],a[1],b[0])*orientation(a[0],a[1],b[1]) < -1e-12 \
					and orientation(b[0],b[1],a[0])*orientation(b[0],b[1],a[1]) < -1e-12:count+=1
	return count

func inspect(source: Array, result: Array) -> void:
	var shared := {}; var seams := 0; var moved := 0; var bad := 0; var folded := 0
	var points: PackedVector3Array=result[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array=result[Mesh.ARRAY_TEX_UV]
	var ids: PackedInt32Array=result[Mesh.ARRAY_INDEX]
	var original := {}
	for i in source[Mesh.ARRAY_VERTEX].size(): original[source[Mesh.ARRAY_TEX_UV][i]]=source[Mesh.ARRAY_VERTEX][i]
	for index in ids:
		var p:=points[index]; var grid:=uv[index]
		if shared.has(grid):
			seams+=1
			if p.distance_to(shared[grid])>0.00001: bad+=1
		else: shared[grid]=p
		if original.has(grid) and p!=original[grid]: bad+=1
		if Vector2(p.x,-p.z).distance_to(grid)>0.001:moved+=1
		if not p.is_finite() or Vector2(p.x,-p.z).distance_to(grid)>0.60001: bad+=1
	for i in range(0,ids.size(),3):
		var a:=points[ids[i]];var b:=points[ids[i+1]];var c:=points[ids[i+2]]
		var grid:Vector2=(uv[ids[i]]+uv[ids[i+1]]+uv[ids[i+2]])/3.0
		var cell:=grid.floor().clamp(Vector2.ZERO,Vector2(31,31));var f:=grid-cell
		var pa:Vector3=original[cell];var pb:Vector3=original[cell+Vector2.RIGHT];var pc:Vector3=original[cell+Vector2.DOWN]
		if f.x+f.y>1.0:pa=original[cell+Vector2.ONE];var swap:=pb;pb=pc;pc=swap
		if (c-a).cross(b-a).dot((pb-pa).cross(pc-pa))<=0.0000001:folded+=1
	check(moved>100,"tall staircase walls gain curved contours")
	check(seams>1000 and bad==0,"shared edges are continuous, anchors exact and offsets bounded: %d"%bad)
	check(folded==0,"refined wall faces retain their 3D orientation: %d"%folded)
	var intersecting:=crossings(result)
	check(intersecting==0,"curved wall sections do not cross each other: %d"%intersecting)
	check(ids.size()>source[Mesh.ARRAY_INDEX].size() and ids.size()<source[Mesh.ARRAY_INDEX].size()*3,"only tall walls add a bounded triangle budget")
	var floor_exact:=true;var identities:=true
	for i in range(0,ids.size(),3):
		var tile:=roundi(result[Mesh.ARRAY_TEX_UV2][ids[i]].y)
		for k in 3:
			var index:=ids[i+k]
			identities=identities and roundi(result[Mesh.ARRAY_TEX_UV2][index].y)==tile
			if points[index].y==0.0:floor_exact=floor_exact and Vector2(points[index].x,-points[index].z)==uv[index]
	check(floor_exact,"flat floors remain exactly on their original planes")
	check(identities,"every refined triangle retains one original material identity")

func mesh_tile_points(mesh:Mesh,tile:int)->Dictionary:
	var arrays:=mesh.surface_get_arrays(0);var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var uv2:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2];var found:={}
	for index in arrays[Mesh.ARRAY_INDEX]:
		if roundi(uv2[index].y)==tile:found[points[index]]=true
	return found

func snow_lifecycle(terrain:EITerrain)->void:
	terrain.land_tile[2*16+2]=1;terrain.tile_types[1]=12
	var field:=Field.new(terrain,rules());terrain._cliffs=field
	var source:=source_mesh(terrain)
	terrain._land_mat=ShaderMaterial.new();terrain._land_mat.shader=Shader.new()
	terrain._land_mat.shader.code="shader_type spatial;"
	add_child(terrain);terrain.set_process(false)
	var sector:=EITerrainSector.new();sector.name="Sector_0_0";terrain.add_child(sector)
	sector.configure(source,terrain._land_mat,6,false);sector.set_cliff_geometry(field.geometry)
	var node:=sector.deformation_surface();var retained:=node.mesh
	var tile:int=field.geometry.patches.keys()[field.geometry.patches.size()/2]
	var expected:=mesh_tile_points(node.mesh,tile)
	var soft:=SoftGroundDeform.new();soft.terrain=terrain;terrain.add_child(soft);soft.set_process(false)
	soft._add_mark({"p":Vector2(5,5),"extent":Vector2(.12,.2),"angle":.3,"time":0.0})
	soft._process(0);soft._finish_mesh_jobs(true)
	check(node.mesh!=retained and mesh_tile_points(node.mesh,tile)==expected,"snow rebuild retains the complete cliff patch")
	var rec:Dictionary=soft.sectors[Vector2i.ZERO];var touched:Array=rec.tiles.keys()
	terrain._cliffs=null;sector.set_cliff_geometry(null);soft.refresh_geometry()
	check(soft.sectors[Vector2i.ZERO].tiles.keys()==touched and node.mesh!=retained,"cliff Off preserves active snow footprints")
	check(mesh_tile_points(node.mesh,tile).size()<expected.size(),"cliff Off restores original wall triangles beside the footprints")
	terrain._cliffs=field;sector.set_cliff_geometry(field.geometry);soft.refresh_geometry()
	check(mesh_tile_points(node.mesh,tile)==expected,"cliff On restores identical walls beside active footprints")
	check(is_same(rec.arrays,source) and sector.deformation_arrays()==source,"snow lifecycle keeps its original contiguous input")
	soft.clear()
	check(node.mesh==retained and mesh_tile_points(node.mesh,tile)==expected,"snow expiry restores the current curved source mesh")
	remove_child(terrain)

func _ready() -> void:
	var terrain := fixture(0)
	for y in 33:
		for x in 33:terrain.heights[y*33+x]=16.0 if x+y>=32 else 0.0
	var source := source_mesh(terrain)
	var saved:=source.duplicate(true)
	var field:=Field.new(terrain,rules())
	check(field.geometry!=null,"verified high walls own a contour builder")
	if field.geometry!=null:
		field.geometry.prepare(source)
		var result:Array=field.geometry.arrays(source)
		inspect(source,result)
		check(source==saved,"refinement never mutates the contiguous deformation input")
		var patches:int=field.geometry.patches.size()
		field.geometry.prepare(source)
		check(field.geometry.patches.size()==patches and field.geometry.arrays(source)==result,"repeated preparation and rendering are deterministic")
		var mat:=StandardMaterial3D.new();var sector:=EITerrainSector.new()
		sector.configure(source,mat,6,false);add_child(sector)
		var surface:=sector.deformation_surface();var retained:=surface.mesh
		sector.set_cliff_geometry(field.geometry)
		check(surface.mesh==retained and sector.visual_arrays()==result,"option updates preserve retained mesh and use the same PT arrays")
		check(sector.deformation_arrays()==saved,"snow still receives the original 9-vertex tile layout")
		var full:=sector.visual_arrays()
		sector.set_subdivided(true)
		var piece_triangles:=0
		for mesh in sector._meshes:piece_triangles+=mesh.surface_get_array_index_len(0)/3
		check(piece_triangles==full[Mesh.ARRAY_INDEX].size()/3,"culled pieces retain every refined triangle once")
		sector.set_cliff_geometry(null)
		check(sector.visual_arrays()==saved,"Off restores the exact authored geometry")
		sector.free()
		GameData.options.gfx_soft_ground=0
		var ground:RefCounted=load("res://src/game/fx/raytrace_ground.gd").new()
		ground.configure(terrain);ground._sectors[1]=saved
		terrain._cliffs=field;ground.configure(terrain)
		check(ground._sectors.is_empty(),"cliff changes invalidate retained PT ground geometry")
		var scene:RefCounted=load("res://src/game/fx/water_raytrace_scene.gd").new()
		scene.begin(terrain,Vector3.ZERO,-1e20);terrain._cliffs=null
		check(scene.topology_changed(),"cliff changes also invalidate water-only ray geometry")
	# Snow/unknown neighbours keep their mesh and force stationary shared
	# boundaries, while verified walls on the other side can still refine.
	terrain.land_tile[7*16+8]=1
	field=Field.new(terrain,rules());source=source_mesh(terrain)
	field.geometry.prepare(source)
	check(not field.geometry.patches.has(7*16+8),"unsupported tile gets no replacement geometry")
	inspect(source,field.geometry.arrays(source))
	snow_lifecycle(terrain)
	terrain.free()
	shifted_boundary()
	print("CLIFF_MESH ",checks," checks ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)

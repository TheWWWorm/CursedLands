extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		if failures<20:printerr("FAIL ",label)

func fixture() -> Array:
	var source := []; source.resize(Mesh.ARRAY_MAX)
	for f in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]: source[f] = PackedVector3Array()
	for f in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]: source[f] = PackedVector2Array()
	source[Mesh.ARRAY_COLOR] = PackedColorArray()
	source[Mesh.ARRAY_INDEX] = PackedInt32Array()
	var rng := RandomNumberGenerator.new(); rng.seed = 4815702
	for tile in 256:
		var base: int = source[0].size()
		for y in 3:
			for x in 3:
				source[0].append(Vector3((tile % 16) * 2 + x + rng.randf() * 0.1, rng.randf() * 20, -int(tile / 16) * 2 - y))
				source[1].append(Vector3(rng.randf(), 1, rng.randf()).normalized())
				source[4].append(Vector2(x, y) * 0.5)
				source[5].append(Vector2(rng.randi_range(0, 4096), tile))
				source[3].append(Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
		for y in 2:
			for x in 2:
				var a := base + y * 3 + x
				source[12].append_array([a + 3, a + 1, a, a + 1, a + 3, a + 4])
	return source


func _ready()->void:
	var source:=fixture()
	var original:=source.duplicate(true)
	var mat:=StandardMaterial3D.new()
	var override:=StandardMaterial3D.new()
	var sector:=EITerrainSector.new()
	sector.configure(source,mat,6,true);add_child(sector)
	check(sector._parts.size()==4,"four draw pieces")
	var covered:Dictionary={}
	var full_bound:=AABB(source[0][0],Vector3.ZERO)
	for vertex:Vector3 in source[0]:full_bound=full_bound.expand(vertex)
	check(sector.get_aabb()==full_bound,"logical full-sector bounds")
	var i:=0
	for y:int in [0,8]:
		for x:int in [0,8]:
			var arrays:=sector._piece_arrays(x,y)
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var piece:MeshInstance3D=sector._parts[i];i+=1
			check(piece.layers==6 and piece.mesh.surface_get_material(0)==mat,"layers/material retained")
			check((arrays[0] as PackedVector3Array).size()==576 and indices.size()==1536,"no duplicate vertices between pieces")
			var previous:=Vector3.INF
			for tile_y in 8:
				for tile_x in 8:
					var local:=tile_y*8+tile_x
					var authored:=(y+tile_y)*16+x+tile_x
					check(not covered.has(authored),"tile covered once")
					covered[authored]=true
					for vertex in 9:
						for channel in EITerrainSector.CHANNELS:
							check(arrays[channel][local*9+vertex]==source[channel][authored*9+vertex],"exact vertex attribute")
					for index in 24:
						check(indices[local*24+index]-local*9==source[12][authored*24+index]-authored*9,"triangle order/winding retained")
	check(covered.size()==256 and source==original,"all geometry retained; input unchanged")
	sector.set_surface_override_material(0,override)
	for piece in sector._parts:check(piece.get_active_material(0)==override,"cache material propagated")
	var old:WeakRef=weakref(sector._parts[0])
	var surface:=sector.deformation_surface()
	check(old.get_ref()==null and not sector._subdivided and sector._parts.size()==1,"old pieces released for deformation")
	check(surface.get_active_material(0)==override,"material survives layout switch")
	var full:=ArrayMesh.new();full.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source)
	check(surface.mesh.surface_get_arrays(0)==full.surface_get_arrays(0),"whole-sector deformation layout preserved")
	sector.set_surface_override_material(0,null)
	check(surface.get_active_material(0)==mat,"cache eviction restores source material")
	var terrain:=EITerrain.new();terrain._land_mat=ShaderMaterial.new()
	terrain._land_mat.shader=Shader.new();terrain._land_mat.shader.code="shader_type spatial;"
	terrain.sectors_x=1;terrain.sectors_y=1;add_child(terrain)
	remove_child(sector);sector.name="Sector_0_0";terrain.add_child(sector)
	var soft:=SoftGroundDeform.new();soft.terrain=terrain;terrain.add_child(soft);soft.set_process(false)
	var before:=surface.mesh
	soft._add_mark({"p":Vector2(8,8),"extent":Vector2(.12,.2),"angle":.3,"time":0.0})
	soft._process(0);soft._finish_mesh_jobs(true)
	check(not soft.sectors.is_empty() and surface.mesh!=before,"real deformation installed through logical sector")
	var dense_material := surface.mesh.surface_get_material(0)
	var replacement := StandardMaterial3D.new()
	sector.set_base_material(replacement)
	check(surface.mesh.surface_get_material(0)==dense_material,"base change preserves live deformation material")
	check(before.surface_get_material(0)==replacement,"base change reaches retained deformation source")
	soft.clear()
	check(surface.mesh==before and soft.sectors.is_empty(),"deformation cleanup restores full mesh")
	check(surface.get_active_material(0)==replacement,"deformation cleanup restores current base material")
	sector.set_subdivided(true)
	check(sector._parts.size()==4 and not is_instance_valid(surface),"return to pieces releases full GPU mesh")
	sector.set_surface_override_material(0,override)
	sector.set_subdivided(false)
	sector.set_subdivided(true)
	for piece in sector._parts:check(piece.get_active_material(0)==override,"cache material survives repeated switch")
	sector.set_base_material(mat)
	for piece in sector._parts:check(piece.get_active_material(0)==override,"base change preserves cache ownership")
	sector.set_surface_override_material(0,null)
	for piece in sector._parts:check(piece.get_active_material(0)==mat,"cache eviction uses current base across rebuilt pieces")
	terrain.free()
	print("TERRAIN_SECTOR checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

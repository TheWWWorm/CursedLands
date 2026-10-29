extends Node
## The presentation terrain build computes its sectors' mesh arrays and
## liquid vertex data on worker lanes. Its sector and water meshes must equal
## a serial recomputation from the same sector bytes, its child order must
## stay Sector_x_y / Water_x_y per sector, and its shared height rows, water
## levels and ground records must equal the (unchanged, serial) headless
## build's.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		if failures<20:printerr("FAIL ",label)

func query(arrays:Array)->Array:
	var out:=[];out.resize(Mesh.ARRAY_MAX)
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_INDEX]:out[channel]=arrays[channel]
	return out

func uploaded(arrays:Array)->Array:
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh.surface_get_arrays(0)

func _ready()->void:
	var zone:=CampaignMap.load_from(GameData.texts).zone("gz1g")
	var map_name:String=zone.mpr
	var started:=Time.get_ticks_usec()
	var lanes:=EITerrain.load_map(map_name,true)
	var lane_ms:=(Time.get_ticks_usec()-started)/1000.0
	check(lanes!=null,"presentation build of %s"%map_name)
	var count:=lanes.sectors_x*lanes.sectors_y
	print("terrain_build_lanes: %s, %d sectors, presentation build %.1f ms, %d lanes"%[map_name,count,lane_ms,Portability.wide_lanes(count)])
	started=Time.get_ticks_usec()
	var plain:=EITerrain.load_map(map_name,false)
	var plain_ms:=(Time.get_ticks_usec()-started)/1000.0
	print("terrain_build_lanes: headless build %.1f ms"%plain_ms)
	check(plain!=null and plain.get_child_count()==0,"the headless build places no sector nodes")
	# The shared rows of the serial phase equal the headless build's.
	check(lanes.heights==plain.heights and lanes.grid_w==plain.grid_w,"heights equal the headless build's")
	check(lanes.land_xy==plain.land_xy,"land_xy equals the headless build's")
	check(lanes.land_n==plain.land_n,"land_n equals the headless build's")
	check(lanes._height_range==plain._height_range and lanes.height_range()==plain.height_range() and lanes._height_range.x<lanes._height_range.y,"height range equals the headless build's (%s)"%str(lanes._height_range))
	check(lanes.water==plain.water and lanes.water_base==plain.water_base and lanes.water_mat==plain.water_mat,"water levels and materials equal the headless build's")
	check(lanes.water_tile==plain.water_tile,"water tiles equal the headless build's")
	check(lanes.ground==plain.ground and lanes.liquid_ground==plain.liquid_ground,"ground types equal the headless build's")
	check(lanes.land_tile==plain.land_tile,"land tiles equal the headless build's")
	# A serial recomputation of every sector from its bytes, with the helpers
	# of the headless terrain (its rows are rewritten with the same values).
	var arc:=EIResArchive.open_path(GameData.root.path_join("maps/%s.mpr"%map_name))
	var prefix:=EITerrain.resolve_map_prefix(arc,map_name)
	check(prefix==lanes.resource_prefix,"sector prefix %s"%prefix)
	var water_layer:int=lanes.WaterReflection.WATER_LAYER
	var expected_order:PackedStringArray=[]
	var water_sectors:=0;var sector_matches:=0;var water_matches:=0;var water_nodes_ok:=0;var job_matches:=0
	for sy in lanes.sectors_y:
		for sx in lanes.sectors_x:
			var d:=arc.read("%s%03d%03d.sec"%[prefix,sx,sy])
			check(d.size()>5 and d.decode_u32(0)==EITerrain.SEC_MAGIC,"sector %d,%d present"%[sx,sy])
			var liquids:=d[4]!=0
			var land:=plain._read_vertices(d,5,sx,sy,true)
			var tex_off:=5+EITerrain.VERTS*EITerrain.VERTS*8*(2 if liquids else 1)
			var land_tex:=plain._read_u16s(d,tex_off)
			var water_ref:=[]
			# The lane job itself, on the record _build keeps (copies: the job
			# places the liquid vertices and appends the underwater colours).
			var record:={"sx":sx,"sy":sy,"land":land.duplicate(true),"land_tex":land_tex,"wverts":[],"water_mats":PackedInt32Array(),"water_tex":PackedInt32Array()}
			if liquids:
				var water_mats:=plain._read_u16s(d,tex_off+1024)
				var vert_mats:=plain._vertex_materials(water_mats)
				var wverts:=plain._read_vertices(d,5+EITerrain.VERTS*EITerrain.VERTS*8,sx,sy,false)
				record.wverts=wverts.duplicate(true);record.water_mats=water_mats;record.water_tex=plain._read_u16s(d,tex_off+512)
				plain._liquid_xy(wverts[0],land[0],water_mats,sx,sy)
				land.append(plain._underwater(land[0],wverts[0],vert_mats))
				water_ref=plain._mesh_arrays(wverts,plain._read_u16s(d,tex_off+512),water_mats,Vector2i.ZERO,vert_mats)
			var land_ref:=plain._mesh_arrays(land,land_tex,PackedInt32Array(),Vector2i(sx,sy)*EITerrain.TILES)
			var job:Array=plain._sector_arrays(record)
			if job.size()==2 and job[0]==land_ref and job[1]==water_ref:job_matches+=1
			elif failures<20:printerr("FAIL sector %d,%d lane job differs from the serial recomputation"%[sx,sy])
			expected_order.append("Sector_%d_%d"%[sx,sy])
			var sector:=lanes.get_node_or_null("Sector_%d_%d"%[sx,sy]) as EITerrainSector
			if sector!=null and sector._arrays==land_ref and sector.tile_origin==Vector2i(sx,sy)*EITerrain.TILES:sector_matches+=1
			elif failures<20:printerr("FAIL sector %d,%d mesh arrays differ from the serial recomputation"%[sx,sy])
			var wm:=lanes.get_node_or_null("Water_%d_%d"%[sx,sy]) as EIWaterMesh
			if water_ref.is_empty():
				check(wm==null,"no water node for a sector without liquid tiles (%d,%d)"%[sx,sy])
				continue
			expected_order.append("Water_%d_%d"%[sx,sy])
			water_sectors+=1
			if wm!=null and EIWaterMesh.query_arrays(wm)==query(water_ref) and wm.mesh.surface_get_arrays(0)==uploaded(water_ref):water_matches+=1
			elif failures<20:printerr("FAIL water %d,%d mesh arrays differ from the serial recomputation"%[sx,sy])
			if wm!=null and wm.layers==water_layer and wm.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and wm.extra_cull_margin==8.0 and wm.mesh.surface_get_material(0)==lanes._water_mat:water_nodes_ok+=1
	check(sector_matches==count,"every sector mesh equals the serial recomputation (%d of %d)"%[sector_matches,count])
	check(job_matches==count,"every sector's lane job (_sector_arrays) equals the serial recomputation (%d of %d)"%[job_matches,count])
	check(water_sectors>0,"the map has liquid sectors (%d)"%water_sectors)
	check(water_matches==water_sectors,"every water mesh equals the serial recomputation (%d of %d)"%[water_matches,water_sectors])
	check(water_nodes_ok==water_sectors,"water nodes keep their layer, shadow, cull margin and material")
	var order:PackedStringArray=[]
	for child in lanes.get_children():
		var n:=String(child.name)
		if n.begins_with("Sector_") or n.begins_with("Water_"):order.append(n)
	check(order==expected_order,"children run Sector_x_y, Water_x_y per sector in the authored order (%d)"%order.size())
	check(lanes.heights==plain.heights and lanes.land_xy==plain.land_xy and lanes.land_n==plain.land_n,"the recomputation rewrote the headless rows with the same values")
	# A second lane build is identical: the lanes' scheduling leaves no trace.
	var again:=EITerrain.load_map(map_name,true)
	var same:=0
	for name in expected_order:
		var a:=lanes.get_node(name);var b:=again.get_node_or_null(name)
		if b==null:continue
		if a is EITerrainSector and a._arrays==b._arrays:same+=1
		elif a is EIWaterMesh and EIWaterMesh.query_arrays(a)==EIWaterMesh.query_arrays(b):same+=1
	check(same==expected_order.size(),"a repeated lane build is identical (%d of %d nodes)"%[same,expected_order.size()])
	print("TERRAIN_BUILD_LANES ",checks," checks ",failures," failures")
	lanes.free();plain.free();again.free()
	get_tree().quit(1 if failures else 0)

extends "res://tools/tests/path_trace_sharc_live.gd"
## Reproduce the photographed Gipat cave entrance, including the upward
## authored lighting normals on geometrically near-vertical wall triangles.
func wall_picks(field: TerrainCliff) -> Array:
	var probes:=[]
	for py in [100,240]:
		for px in [650,800,950,1100,1250]:
			var origin:=camera.project_ray_origin(Vector2(px,py));var direction:=camera.project_ray_normal(Vector2(px,py))
			var best:=INF;var record:={}
			for y in range(55,115):
				for x in range(0,45):
					var vi:=y*t.grid_w+x
					for indices in [Vector3i(vi,vi+1,vi+t.grid_w),Vector3i(vi+1,vi+t.grid_w+1,vi+t.grid_w)]:
						var a:=field._point(t,indices.x);var b:=field._point(t,indices.y);var c:=field._point(t,indices.z)
						var hit:Variant=Geometry3D.ray_intersects_triangle(origin,direction,a,b,c)
						if hit==null or origin.distance_squared_to(hit)>=best:continue
						best=origin.distance_squared_to(hit)
						var bc:=Geometry3D.get_triangle_barycentric_coords(hit,a,b,c)
						var n:=t.land_n[indices.x]*bc.x+t.land_n[indices.y]*bc.y+t.land_n[indices.z]*bc.z
						var ti:=(y/2)*field.tile_size.x+x/2;var code:=t.land_tile[ti]
						record={"pixel":[px,py],"tile":[x/2,y/2],"index":ti,"slot":code&16383,"eligible":field.eligible[ti],
							"authored_up":absf(n.normalized().y),"geometric_up":absf((b-a).cross(c-a).normalized().y),"point":str(hit)}
			probes.append(record)
	return probes

func region_difference(a: Image,b: Image,rect: Rect2i) -> float:
	var total:=0.0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var d:=a.get_pixel(x,y)-b.get_pixel(x,y)
			total+=(absf(d.r)+absf(d.g)+absf(d.b))/3.0
	return total/(rect.size.x*rect.size.y)

func vertical_detail(a: Image,rect: Rect2i) -> float:
	var total:=0.0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var d:=a.get_pixel(x,y)-a.get_pixel(x,y+4)
			total+=(absf(d.r)+absf(d.g)+absf(d.b))/3.0
	return total/(rect.size.x*rect.size.y)

func run() -> void:
	cave=true
	var context:=await setup_sharc()
	if context.is_empty():get_tree().quit(1);return
	var game: Game=context[1];var session: Session=context[0]
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt),"cave PT baseline settles")
	var field: TerrainCliff=t._cliffs
	if field==null:check(false,"cave cliff field exists");await finish_live(context,rt);return
	var heights:=t.heights.duplicate();var xy:=t.land_xy.duplicate();var normals:=t.land_n.duplicate();var codes:=t.land_tile.duplicate()
	var target:=0;var admitted:=0
	for y in range(35,47):
		for x in range(2,15):
			var ti:=y*field.tile_size.x+x;var code:=t.land_tile[ti]
			if (code&16383)<2 or (code&16383)>13:continue
			var vi:=(y*2+1)*t.grid_w+x*2+1
			if absf(t.land_n[vi].y)>0.5:continue
			target+=1
			if field.eligible[ti]>0:admitted+=1
	check(target>10,"reported cave view has many steep rock transition tiles")
	check(admitted==target,"reported steep two-rock walls receive vertical texture mapping: %d/%d"%[admitted,target])
	var probes:=wall_picks(field);var supported:=0;var misleading:=0
	for probe: Dictionary in probes:
		if probe.is_empty():continue
		if probe.eligible>0:supported+=1
		if probe.geometric_up<0.3 and probe.authored_up>0.75:misleading+=1
	check(supported==probes.size(),"all photographed wall probes have verified cliff material identities: %d/%d"%[supported,probes.size()])
	check(misleading>=4,"actual near-vertical cave faces have misleading upward lighting normals")
	var packed_ok:=rt.device!=null
	if rt.device!=null:
		var data: PackedByteArray=rt.device.terrain.data
		var rows:Variant=field.get("blend_rows")
		packed_ok=rows!=null
		if rows!=null:
			var start:=data.decode_u32(40)+((field.grid_size.x*field.grid_size.y+3)&~3)
			for probe: Dictionary in probes:
				if probe.is_empty():continue
				var i:int=probe.index
				if rows[i].r<=0:continue
				packed_ok=packed_ok and (data.decode_u32(data.decode_u32(8)+i*4)&(1<<25))!=0
				for k in 4:packed_ok=packed_ok and data.decode_float(start+i*16+k*4)==rows[i][k]
	check(packed_ok,"traced material snapshot preserves all four cliff donor codes")
	# Let the visible FPS counter and reconstruction settle after compilation.
	await frames(90);await capture("wall-pt")
	check(await select_sharc(rt,true),"SHaRC renders the corrected cave materials")
	await frames(90);await capture("wall-pt-sharc")
	check(rt.device!=null and rt.device.sharc.active and rt.device.nrd_active,"cache and denoiser remain active on corrected walls")
	GameData.options.pt_mode=0;Gfx.apply_env(game._env);await frames(30)
	check(rt.device==null and not Gfx.path_trace_active,"leaving corrected PT releases the scene and cache")
	var raster:=await capture("wall-raster")
	var blank:=Image.create(field.tile_size.x,field.tile_size.y,false,Image.FORMAT_R8)
	field.tiles.update(blank);await frames(8)
	var original:=await capture("wall-original-mapping")
	var wall:=Rect2i(760,60,260,200);var floor:=Rect2i(1050,640,120,80)
	var changed:=region_difference(raster,original,wall);var retained:=region_difference(raster,original,floor)
	var detail_before:=vertical_detail(original,wall);var detail_after:=vertical_detail(raster,wall)
	check(changed>0.01,"the photographed striped wall changes in actual raster output")
	check(detail_after>detail_before*1.5,"wall texture gains vertical detail instead of long stripes: %.6f -> %.6f"%[detail_before,detail_after])
	check(retained<0.002,"level cave floor retains its authored pixels: %.6f"%retained)
	field.tiles.update(Image.create_from_data(field.tile_size.x,field.tile_size.y,false,Image.FORMAT_R8,field.eligible));await frames(8)
	check(region_difference(raster,await capture("wall-restored"),wall)<0.002,"restoring cliff eligibility restores the corrected wall")
	check(t.heights==heights and t.land_xy==xy and t.land_n==normals and t.land_tile==codes,"mapping leaves geometry, authored lighting normals and tile codes unchanged")
	var report:={"map":t.resource_prefix,"camera":str(camera.global_transform),"checks":checks,"failures":failures,"probes":probes,
		"wall_difference":changed,"floor_difference":retained,"vertical_detail_before":detail_before,"vertical_detail_after":detail_after}
	FileAccess.open(out.path_join("cave-wall.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	print("CAVE_WALL ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)

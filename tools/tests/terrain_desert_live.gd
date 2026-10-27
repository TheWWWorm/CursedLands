extends "res://tools/tests/terrain_cave_wall.gd"
## Real LiA Suslanger terrain, using original dry-ground material identities.
func run() -> void:
	map_name="zone3"; resolution=Vector2i(1920,1080)
	var context:=await setup_route()
	if context.is_empty():get_tree().quit(1);return
	var game:Game=context[1];var session:Session=context[0]
	var rt:Node=game.get_node("SceneRaytrace")
	var field:TerrainCliff=t._cliffs
	check(field!=null,"desert cliff field exists")
	if field==null:get_tree().quit(1);return
	var heights:=t.heights.duplicate();var xy:=t.land_xy.duplicate();var normals:=t.land_n.duplicate()
	var rules:={}
	for atlas in int(t.get_meta("textures_count",0)):
		rules[atlas]=TerrainCliff.Tiles.blend_corners(GameData.load_original_image("%s%03d"%[t.resource_prefix,atlas]))
	var score:=-INF;var focus:=Vector3.ZERO;var outward:=Vector3.ZERO;var selected:=-1
	for y in range(16,t.sectors_y*32-16):
		for x in range(16,t.grid_w-16):
			var tile:=(y/2)*field.tile_size.x+x/2;var code:=t.land_tile[tile]&16383
			var corners:PackedByteArray=rules.get(code>>6,PackedByteArray())
			if corners.size()!=256:continue
			var family:=corners[(code&63)*4]
			if family<200 or family>=253 or corners.slice((code&63)*4,((code&63)+1)*4).count(family)!=4:continue
			var vi:=y*t.grid_w+x
			var a:=field._point(t,vi);var b:=field._point(t,vi+1);var c:=field._point(t,vi+t.grid_w)
			var geometric:=(b-a).cross(c-a).normalized()
			var tall:=maxf(a.y,maxf(b.y,c.y))-minf(a.y,minf(b.y,c.y))
			if geometric.y<0.001 or geometric.y>0.2 or tall<5:continue
			var center:=(a+b+c)/3.0
			var facing:=Vector3(geometric.x,0,geometric.z).normalized()
			var eye:=center+facing*11+Vector3.UP*3
			var clear:=true
			for fraction in [0.25,0.5,0.75,1.0]:
				var probe:=center.lerp(eye,fraction)
				if t.height_at(probe.x,-probe.z)>probe.y-0.5:clear=false
			if not clear:continue
			var candidate:=tall-Vector2(x,y).distance_to(Vector2(t.grid_w,t.sectors_y*32)*0.5)*0.02
			if candidate>score:
				score=candidate;focus=center;outward=Vector3(geometric.x,0,geometric.z).normalized();selected=tile
	check(selected>=0,"original desert map contains a tall dry-ground wall")
	if selected<0:get_tree().quit(1);return
	check(field.eligible[selected]>0,"dry-ground wall receives cliff mapping")
	camera.global_position=focus+outward*11+Vector3.UP*3;camera.look_at(focus)
	for unit:GameUnit in session.world.units.values():
		unit.set_process(false);unit.set_physics_process(false)
		if unit.model!=null and unit.model.player!=null:unit.model.player.pause()
	check(await ready_scene(rt),"actual desert wall prepares native PT")
	await frames(90);await capture("desert-pt")
	check(rt.device!=null and rt.device.output_ready() and Gfx.path_trace_active,"desert wall retains active traced lighting")
	GameData.options.pt_mode=0;Gfx.apply_env(game._env);await frames(30)
	if t.color_cache!=null:t.color_cache.clear();t.color_cache.set_process(false)
	await frames(12);var raster:=await capture("desert-raster")
	var blank:=Image.create(field.tile_size.x,field.tile_size.y,false,Image.FORMAT_R8)
	field.tiles.update(blank);await frames(12);var original:=await capture("desert-original-mapping")
	var wall:=Rect2i(800,400,320,200)
	var changed:=region_difference(raster,original,wall)
	var before:=vertical_detail(original,wall);var after:=vertical_detail(raster,wall)
	check(changed>0.01,"dry-ground projection changes the visible wall: %.6f"%changed)
	check(after>before*1.5,"projected wall restores vertical texture detail: %.6f -> %.6f"%[before,after])
	field.tiles.update(Image.create_from_data(field.tile_size.x,field.tile_size.y,false,Image.FORMAT_R8,field.eligible));await frames(12)
	check(region_difference(raster,await capture("desert-restored"),wall)<0.002,"restoring eligibility restores the rendered desert wall")
	check(t.heights==heights and t.land_xy==xy and t.land_n==normals,"original collision heights, anchors and lighting records remain unchanged")
	FileAccess.open(out.path_join("desert-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,
		"map":map_name,"resource_prefix":t.resource_prefix,"tile":selected,"camera":str(camera.global_transform),
		"wall_difference":changed,"vertical_detail_before":before,"vertical_detail_after":after},"\t"))
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	print("DESERT_LIVE ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)

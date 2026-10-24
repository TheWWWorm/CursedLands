extends "res://tools/tests/path_trace_camera_routes.gd"
## Close receiver coverage before/after real authored snow footfalls.
func run() -> void:
	resolution=Vector2i(1920,1080)
	var context:=await setup_route()
	if context.is_empty():get_tree().quit(1);return
	var game: Game=context[1]
	var rt: Node=game.get_node("SceneRaytrace")
	var soft: SoftGroundDeform=t.details.soft_ground
	var point:=Vector2.INF
	var obstacles:=[]
	for object: Node3D in game.world.objects.values()+game.world.units.values():
		obstacles.append(Vector2(object.global_position.x,-object.global_position.z))
	for y in range(140,200):
		for x in range(110,180):
			var p:=Vector2(x+0.5,y+0.5)
			if not soft.step_allowed(p) or t.ground_type(p.x,p.y)!=9:continue
			if obstacles.any(func(at: Vector2):return at.distance_to(p)<6.0):continue
			var h:=t.height_at(p.x,p.y)
			if absf(t.height_at(p.x+1,p.y)-h)>0.2 or absf(t.height_at(p.x,p.y+1)-h)>0.2:continue
			point=p;break
		if point.is_finite():break
	check(point.is_finite(),"find a dry authored snow walking surface")
	if not point.is_finite():get_tree().quit(1);return
	var focus:=Vector3(point.x,t.height_at(point.x,point.y),-point.y)
	camera.global_position=focus+Vector3(0.01,6,0);camera.look_at(focus)
	check(await ready_scene(rt),"close snow scene is ready")
	var sector: EITerrainSector
	for child in t.get_children():
		if child is EITerrainSector:sector=child;break
	var source:=sector.deformation_arrays()
	var source_vertices: PackedVector3Array=source[Mesh.ARRAY_VERTEX].duplicate()
	var ground: RefCounted=rt._ground_cache
	var lifted: Array=ground.arrays(source,sector.get_instance_id())
	var hits: int=ground.cache_hits
	ground.configure(t)
	var reused: Array=ground.arrays(source,sector.get_instance_id())
	check(ground.cache_hits==hits+1 and reused[Mesh.ARRAY_VERTEX]==lifted[Mesh.ARRAY_VERTEX],"recenter reuses identical lifted terrain geometry")
	check(source[Mesh.ARRAY_VERTEX]==source_vertices,"cached lifting preserves original terrain arrays")
	GameData.options.gfx_soft_ground=0;ground.configure(t)
	check(ground.tiles==null and ground._sectors.is_empty() and ground.arrays(source)==source,"disabling soft ground invalidates cached lift")
	GameData.options.gfx_soft_ground=1;ground.configure(t)
	check(ground.tiles!=null and ground._sectors.is_empty(),"restoring soft ground rebuilds from the current terrain tables")
	await receiver_coverage();var before:=receiver_counts.duplicate()
	DirAccess.rename_absolute(out.path_join("terrain-receivers.png"),out.path_join("snow-before.png"))
	for offset: Vector2 in [Vector2.ZERO,Vector2(0.4,0),Vector2(-0.4,0),Vector2(0,0.4)]:
		soft.add_step(point+offset,Vector2(0.25,0.35),0.3)
	for i in 24:
		soft._process(0);soft._finish_mesh_jobs(true);await frames(1);observe(rt,"footfall")
	check(not soft.sectors.is_empty(),"production footfalls install real dense snow geometry")
	var inactive:=samples.filter(func(row: Dictionary):return not row.active or not row.global_active).size()
	check(inactive==0,"PT stays active while snow geometry changes: "+str(inactive))
	await receiver_coverage()
	await save_buffers(rt,"snow-tracks")
	FileAccess.open(out.path_join("snow-tracks.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"point":str(point),"before":before,"after":receiver_counts,
		"inactive_frames":inactive,"samples":samples},"\t"))
	game.queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)

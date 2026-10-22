extends "res://tools/tests/scene_raytrace_live.gd"
## Matched campaign views plus raw/filter captures, with the same settings
## usable against the pre-material export. No display post-processing.
var raw_images: Array[Image]=[]
signal raw_ready
func ready_materials(owner: Node) -> bool:
	# Option/NoiseTexture updates can invalidate an active snapshot after the
	# old helper's initial check. Require the current topology to stay ready.
	var stable:=0
	for i in 1800:
		await frames(1)
		if owner._failed:return false
		if owner.stats.get("active",false) and owner._scene!=null and not owner._scene.topology_changed():stable+=1
		else:stable=0
		if stable>=30:return true
	print("TERRAIN_READY_TIMEOUT ",owner.stats)
	return false

func read_raw(owner: Node) -> void:
	var d: Object=owner.device
	raw_images.clear()
	for index in [0,1,2,3]:
		raw_images.append(Image.create_from_data(d._size.x,d._size.y,false,Image.FORMAT_RGBAH,d._rd.texture_get_data(d._raw[index],0)))
	raw_ready.emit.call_deferred()

func cliff_site(origin: Vector3) -> Dictionary:
	var field: TerrainCliff=t._cliffs
	var best:=-INF;var result:={}
	if field==null:return result
	for y in range(2,field.tile_size.y-2):
		for x in range(2,field.tile_size.x-2):
			if field.eligible[y*field.tile_size.x+x]==0:continue
			var i:=(y*2+1)*t.grid_w+x*2+1
			var point: Vector3=field._point(t,i);var n: Vector3=t.land_n[i]
			var distance:=point.distance_to(origin)
			if distance<12 or distance>70:continue
			var side:=TerrainCliff.side_weight(n,field.guards[i]/255.0)
			var score:=side-distance*0.003
			if side>0.6 and score>best:best=score;result={"point":point,"normal":n}
	return result

func buffers(owner: Node,label: String) -> void:
	RenderingServer.call_on_render_thread(read_raw.bind(owner));await raw_ready
	for i in 4:raw_images[i].save_exr(out.path_join(label+"-raw-%s.exr"%i))
	owner.device.output.get_image().save_exr(out.path_join(label+"-filtered.exr"))
	owner.device.guide.get_image().save_exr(out.path_join(label+"-normal.exr"))
	owner.device.shadow1.get_image().save_exr(out.path_join(label+"-material.exr"))

func run() -> void:
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_terrain_cliffs":1,"gfx_materials":1,"gfx_foliage_light":1,
		"pt_mode":2,"pt_accumulation":1,"q_rt_lighting":1},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_materials(rt),"terrain materials prepare in campaign")
	var initial:=camera.global_transform;var site:=cliff_site(camera.global_position)
	check(not site.is_empty(),"nearby river cliffs include an authored projection site")
	for view in ["river-noon","cliff-noon","cliff-evening","cliff-night"]:
		if view=="cliff-noon" and not site.is_empty():
			camera.global_position=site.point+Vector3(site.normal.x,0,site.normal.z).normalized()*10.0+Vector3.UP*3.0
			camera.look_at(site.point)
		session.state.world_time=18.0 if view=="cliff-evening" else 0.0 if view=="cliff-night" else 12.0
		game._update_daylight(false)
		check(await ready_materials(rt),"terrain view prepares: "+view)
		await frames(150);await shot(view);await buffers(rt,view)
		rows.append({"view":view,"camera":str(camera.global_transform),"stats":rt.stats.duplicate()})
		check(rt.stats.accumulation_frames>=100,"terrain history settles: "+view)
	# The new controller reports exact retained terrain identities and bytes.
	if rt.stats.has("terrain_material_triangles"):
		check(rt.stats.terrain_material_triangles>100 and rt.stats.terrain_material_bytes>64,"terrain snapshot contains tile identities and material data")
		check(rt.device.terrain.atlas==t._detail_atlases,"PT retains the raster terrain atlas")
		var previous: Object=rt._scene
		GameData.options.gfx_terrain_cliffs=0;t.apply_gfx()
		for i in 240:
			await frames(1)
			if rt._scene!=previous:break
		check(rt._scene!=previous and await ready_materials(rt),"cliff-only option change rebuilds traced materials")
		check(rt.device.terrain.data.decode_u32(40)==0,"disabled cliffs clear the traced projection guards")
		GameData.options.gfx_terrain=2;GameData.options.gfx_terrain_cliffs=1;t.apply_gfx()
		await frames(90);check(await ready_materials(rt),"natural transitions rebuild traced materials")
		await frames(150);await shot("cliff-transitions");await buffers(rt,"cliff-transitions")
		check(rt.device.terrain.data.decode_u32(56)>0 if t._transitions and t._transitions.admitted>0 else rt.device.terrain.data.decode_u32(56)==0,"natural transition metadata follows raster admission")
		GameData.options.gfx_terrain=0;t.apply_gfx();await frames(90)
		check(await ready_materials(rt) and rt.device.terrain.data.decode_u32(0)==0,"original terrain disables the detailed path sampler")
	camera.global_transform=initial
	GameData.options.pt_mode=0;Gfx.apply_env(game._env);await frames(20)
	check(rt.device==null,"conventional lighting restores after terrain materials")
	FileAccess.open(out.path_join("path-terrain-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"views":rows},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_TERRAIN_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)

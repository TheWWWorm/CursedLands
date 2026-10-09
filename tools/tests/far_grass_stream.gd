extends "far_grass.gd"

func no_overlap(stream: RefCounted) -> bool:
	var keys: Array = stream._chunks.keys()
	for i in keys.size():
		for j in range(i+1,keys.size()):
			if Far.contains_tile(keys[i],keys[j]) or Far.contains_tile(keys[j],keys[i]): return false
	return true

func pending_job(field: RefCounted, key: Vector3i) -> RefCounted:
	var job := Far.Job.new(); job.configure(field,key); job.run(); return job

func settle(stream: RefCounted, details: TerrainDetails, camera: Camera3D, label: String) -> void:
	var deadline := Time.get_ticks_msec()+12000
	var ticks := 0
	while Time.get_ticks_msec()<deadline:
		stream.tick(details,camera,Vector3(64,4,-64),0.02)
		check(stream._chunks.size()<=Far.MAX_TILES and stream._pending.size()<=5,"bounded stream "+label)
		check(no_overlap(stream),"one representation per tile region "+label)
		ticks+=1
		var complete: bool = not stream._wanted.is_empty() and stream._pending.is_empty() and stream._work==null and not stream._camera_signature.is_empty()
		for key: Vector3i in stream._wanted:
			if not stream._chunks.has(key): complete=false; break
		if complete: break
		await get_tree().process_frame
		OS.delay_msec(1)
	var complete: bool = stream._work==null and stream._pending.is_empty() and not stream._camera_signature.is_empty()
	for key: Vector3i in stream._wanted:
		if not stream._chunks.has(key): complete=false
	check(complete,"stream settles with all wanted tiles "+label)
	rows.append({"case":label,"ticks":ticks,"diagnostic":stream.diagnostic()})

func _ready() -> void:
	GameData.options.gfx_grass=1; GameData.options.gfx_wind=0; GameData.options.gfx_biome_cover=0
	var details := fixture(128)
	add_child(details.terrain); details.terrain.add_child(details)
	details.terrain.set_process(false); details.set_process(false)
	var camera := Camera3D.new(); add_child(camera)
	camera.position=Vector3(64,9,-5); camera.fov=65.0; camera.far=260.0
	camera.look_at(Vector3(64,4,-90))
	await get_tree().process_frame
	var stream := details._far_grass
	details._queue.append(Vector2i.ZERO)
	stream.tick(details,camera,Vector3(64,4,-64),0.02)
	check(stream._field==null and stream._work==null,"near queue has priority before far snapshot and work")
	details._queue.clear()
	await settle(stream,details,camera,"initial")
	check(stream._count>1000,"initial visible far coverage is substantial")
	var previous_pose := camera.transform
	stream._poll=0.2
	camera.look_at(Vector3(20,4,-90))
	stream.tick(details,camera,Vector3(64,4,-64),0.001)
	check(stream._planner.forward.dot(-camera.global_basis.z)>0.9999,"camera turn replans immediately before the periodic poll")
	check(stream._camera_signature[0]==camera.get_camera_transform(),"camera turn records the actual view without forced invalidation")
	check(no_overlap(stream),"camera turn cannot publish overlapping parent and child tiles")
	camera.transform=previous_pose
	await settle(stream,details,camera,"camera-turn-return")
	camera.set_orthogonal(80.0,0.05,260.0); stream._poll=0.0
	stream.tick(details,camera,Vector3(64,4,-64),0.02)
	check(stream._planner.planes==camera.get_frustum(),"projection-only camera change replans visible grass")
	camera.set_perspective(65.0,0.05,260.0); stream._camera_signature.clear(); stream._poll=0.0
	await settle(stream,details,camera,"perspective-return")
	var before := stream._chunks.size()
	stream._planner.limit=2; stream._camera_signature.clear(); stream._poll=0.0
	stream.tick(details,camera,Vector3(64,4,-64),0.02)
	check(stream._chunks.size()==before,"coarsening retains old children while its parent builds")
	await settle(stream,details,camera,"coarsen")
	check(stream._chunks.size()<=2,"explicit coarsening reaches requested budget")
	stream._planner.limit=Far.MAX_TILES; stream._camera_signature.clear(); stream._poll=0.0
	await settle(stream,details,camera,"refine")
	check(stream._max_upload_tiles<=4,"refinement publishes at most four children atomically")
	check(stream._chunks.size()==stream._planner.diagnostic.tiles,"all intermediate parents eventually refine to the actual view plan")
	# A direct publication witness: three children must never replace their
	# parent while the fourth is still missing.
	stream.clear(); details.prepare_grass()
	stream._owner=details; stream._field=Far.Field.new(); stream._field.capture(details)
	stream._geometry=Far.mesh(); stream._material=Far.material()
	var parent_key := Vector3i(0,0,1)
	var parent := pending_job(stream._field,parent_key)
	var node := Far.install(parent,stream._geometry,stream._material)
	details.add_child(node); stream._chunks[parent_key]=node; stream._count=parent.count
	stream._wanted.assign([Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(0,1,0),Vector3i(1,1,0)])
	for i in 3: stream._pending[stream._wanted[i]]=pending_job(stream._field,stream._wanted[i])
	stream._commit_ready()
	check(stream._chunks.size()==1 and stream._chunks.has(parent_key),"incomplete replacement retains its whole visible parent")
	stream._pending[stream._wanted[3]]=pending_job(stream._field,stream._wanted[3])
	stream._commit_ready()
	check(stream._chunks.size()==4 and not stream._chunks.has(parent_key) and no_overlap(stream),"complete refinement switches once without double geometry")
	# Flood/option/world clear must join outstanding work and discard all
	# staging; a subsequent field must reflect the changed native water.
	stream._work=Far.Job.new(); stream._work.configure(stream._field,Vector3i(2,2,0))
	stream._task=WorkerThreadPool.add_task(stream._work.run)
	var image: Image = details._images[0]
	details.terrain.water.fill(10.0)
	details.water_changed()
	check(stream._field==null and stream._work==null and stream._task<0 and stream._pending.is_empty() and stream._chunks.is_empty(),"native water barrier joins and clears far work")
	details._images[0]=image
	details.prepare_grass()
	await settle(stream,details,camera,"flood")
	check(stream._count==0,"a fresh flooded field cannot restore old dry grass")
	details._grass=false
	stream.tick(details,camera,Vector3(64,4,-64),0.02)
	check(stream._chunks.is_empty() and stream._field==null,"grass off frees far geometry and snapshot")
	camera.free(); details.terrain.free()
	FileAccess.open("user://far-grass-stream.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("FAR_GRASS_STREAM checks=",checks," failures=",failures," rows=",JSON.stringify(rows))
	get_tree().quit(1 if failures else 0)

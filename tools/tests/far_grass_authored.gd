extends "far_grass.gd"

func _ready() -> void:
	for key in GfxDetect.keys():
		if key.begins_with("gfx_"): GameData.options[key] = 0
	GameData.options.gfx_grass = 1; GameData.options.gfx_far_view = 1
	var campaign := CampaignMap.load_from(GameData.texts)
	var total := 0; var blocked_roots := 0
	for id in ["bz2g","bz4g"]:
		var zone: Dictionary = campaign.zone(id)
		check(not zone.is_empty(),"original zone "+id)
		if zone.is_empty(): continue
		var world := GameWorld.new(); add_child(world); world.set_process(false); world.set_physics_process(false)
		world.zone = zone
		var map := EIMapScene.load_map(zone.mpr,zone.get("mob",""),false)
		world.add_child(map); world.map=map; world.terrain=map.terrain
		var terrain := map.terrain
		terrain.set_process(false)
		var details := terrain.details
		details.set_process(false); details.prepare_grass()
		var began := Time.get_ticks_usec()
		var field := Far.Field.new(); field.capture(details)
		var snapshot_us := Time.get_ticks_usec()-began
		var near_key := Vector2i(int(field.size.x/16),int(field.size.y/16))
		var before := details.instances(near_key)
		var camera := Camera3D.new(); world.add_child(camera); camera.current=true
		var point := Vector2(field.size)*0.5
		camera.position = Vector3(point.x,terrain.height_at(point.x,point.y)+6.0,-point.y+28.0)
		camera.fov=65.0; camera.far=260.0
		camera.look_at(Vector3(point.x,terrain.height_at(point.x,point.y),-point.y-80.0))
		await get_tree().process_frame
		var planner := Far.Planner.new()
		var selected: Array[Vector3i] = planner.select(camera,field,details.global_transform)
		var accepted := 0; var times := []; var candidates := 0
		for key: Vector3i in selected:
			var job := Far.Job.new(); job.configure(field,key); job.run()
			accepted+=job.count; candidates+=job.attempted; times.append(job.elapsed_us)
			for i in job.count:
				var p := Vector2(job.buffer[i*20+3],-job.buffer[i*20+11])
				check(details.grass_allowed(p),"far original root preserves type/triangle/path/water/scenery eligibility "+id)
				check(not field.patch(p).is_empty(),"far original footprint remains supported "+id)
			# A sampled rejected ordinary native root must not enter the far field.
			for local: Vector2 in [Vector2(2.17,3.83),Vector2(10.27,11.19),Vector2(18.87,19.01)]:
				var p := Vector2(key.x,key.y)*Far.TILE*float(1<<key.z)+local
				if p.x>=field.size.x or p.y>=field.size.y: continue
				if not details.grass_allowed(p):
					blocked_roots+=1; check(field.patch(p).is_empty(),"far field retains an original rejection "+id)
		var after := details.instances(near_key)
		check(before==after,"far generation leaves native near seed/output unchanged "+id)
		times.sort()
		rows.append({"case":"original-map","zone":id,"mpr":zone.mpr,"size":field.size,
			"selected_tiles":selected.size(),"candidates":candidates,"accepted":accepted,"triangles":accepted*Far.TRIANGLES,
			"packed_bytes":accepted*80,"snapshot_owned_bytes":field.owned_bytes,"snapshot_us":snapshot_us,
			"job_median_us":times[times.size()/2] if not times.is_empty() else 0,"job_max_us":times[-1] if not times.is_empty() else 0,
			"job_sum_us":times.reduce(func(a,b):return a+b,0),"scenery_buckets":field.scenery.size(),"plan":planner.diagnostic})
		total+=accepted
		world.free()
	check(total>500 and blocked_roots>5,"real maps include substantial growing and excluded ground")
	FileAccess.open("user://far-grass-authored.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("FAR_GRASS_AUTHORED checks=",checks," failures=",failures," rows=",JSON.stringify(rows))
	get_tree().quit(1 if failures else 0)

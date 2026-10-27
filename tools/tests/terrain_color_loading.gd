extends "res://tools/tests/terrain_color_reuse.gd"
func run() -> void:
	GameData.options.gfx_terrain=1; GameData.options.gfx_soft_ground=0
	camera=Camera3D.new(); add_child(camera); camera.position=Vector3(16,30,0); camera.look_at(Vector3(16,0,-16)); camera.current=true
	var terrain := make_terrain(.5)
	var cache := terrain.color_cache
	if not cache.has_method("_job_limit"):
		check(false,"loading uses a distinct bounded CPU preparation budget")
		terrain.free(); finish(); return
	var node: Node3D = terrain.get_node("Sector_0_0")
	for preparing in [false,true]:
		cache.clear(); TerrainColorCache.clear_shared(); cache.refresh()
		for i in 8:
			var key := Vector2i(i%3, i/3)
			cache._wanted.append({"key":key,"node":node}); cache._wanted_keys[key]=true
		cache.call("_start_jobs", preparing)
		var count := cache._jobs.size()
		if preparing:
			check(count==mini(8,OS.get_processor_count()),"loading starts independent native bakes across available cores")
		else:
			check(count==2,"live streaming retains its two-job bound")
		cache._finish(true)
		var identical := true
		for key: Vector2i in cache._resident:
			var expected: Image = cache._field.bake(key,cache._density())
			var actual: Texture2D = cache._resident[key].material.get_shader_parameter("baked_ground")
			identical = identical and actual.get_image().get_data() == expected.get_data()
		check(identical and cache._jobs.is_empty(),"all jobs join and produce the exact serial pixels: " + str(preparing))
	# An authored HD atlas can reach the maximum density. The loading batch
	# shrinks instead of allocating eight huge temporary images at once.
	terrain._atlas_source_size=terrain.texture_size*12
	var limit: int = cache.call("_job_limit",true)
	var side := cache._density()*18
	check(limit*(side*side*4*4/3+64)<=64*1024*1024,"large pages stay within the temporary loading memory budget")
	check(int(cache.call("_job_limit",false))==2,"larger loading work never changes the streaming policy")
	terrain.free(); finish()
func finish() -> void:
	camera.queue_free()
	print("TERRAIN_COLOR_LOADING ",checks," checks ",failures.size()," failures")
	get_tree().quit(int(not failures.is_empty()))

extends "res://tools/tests/terrain_color_reuse.gd"
## The world is built ahead of its reveal: the colour cache is created on a
## terrain that is not yet in the tree, its loading bakes start early
## (prepare_start) and are pumped while other work runs, and prepare joins
## them with every page baked exactly once and the serial pixels.
const SECTORS := 3

func make_ahead_terrain(weather: float) -> EITerrain:
	# Like make_terrain, but nine sectors, not in the tree and not prepared.
	var t := TestTerrain.new()
	t.sectors_x=SECTORS; t.sectors_y=SECTORS; t.texture_size=128; t.tile_size=32; t._atlas_source_size=128
	var pixels := Image.create(128,128,false,Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128: pixels.set_pixel(x,y,Color(float(x)/128.0,float(y)/128.0,.25))
	var images: Array[Image] = [EITerrain.padded_atlas(pixels,32,EITerrain.TERRAIN_GUTTER)]
	t._detail_atlases=Texture2DArray.new(); t._detail_atlases.create_from_images(images)
	t.land_tile.resize(48*48); t.land_tile.fill(0)
	var shader := Shader.new(); shader.code=SOURCE
	t._land_mat=ShaderMaterial.new(); t._land_mat.shader=shader
	t._land_mat.set_shader_parameter("probe_weather",weather)
	for y in SECTORS:
		for x in SECTORS:
			var sector := MeshInstance3D.new(); sector.name="Sector_%d_%d"%[x,y]
			var mesh := PlaneMesh.new(); mesh.size=Vector2(32,32); sector.mesh=mesh
			sector.position=Vector3(16+32*x,0,-16-32*y); t.add_child(sector)
	return t

func job_keys(cache: TerrainColorCache) -> Dictionary:
	var keys := {}
	for row: Dictionary in cache._jobs: keys[row.key]=true
	return keys

func pixels_identical(cache: TerrainColorCache) -> bool:
	var identical := not cache._resident.is_empty()
	for key: Vector2i in cache._resident:
		var expected: Image = cache._field.bake(key,cache._density())
		var actual: Texture2D = cache._resident[key].material.get_shader_parameter("baked_ground")
		identical = identical and actual != null and actual.get_image().get_data() == expected.get_data()
	return identical

func run() -> void:
	GameData.options.gfx_terrain=1; GameData.options.gfx_soft_ground=0
	camera=Camera3D.new(); add_child(camera); camera.position=Vector3(48,120,-48)
	camera.look_at(Vector3(48,0,-48),Vector3(0,0,-1)); camera.current=true
	TerrainColorCache.clear_shared()
	var wanted_pages := SECTORS*SECTORS
	# 1. Creation out of the tree: the world is built before it is shown.
	var terrain := make_ahead_terrain(.25)
	var cache := TerrainColorCache.create(terrain); terrain.color_cache=cache; cache.set_process(false)
	check(not terrain.is_inside_tree() and not cache.is_inside_tree() and cache._enabled and cache._sectors.size()==wanted_pages,
		"cache created on a terrain outside the tree is enabled and knows every sector")
	if not cache._enabled or not cache.has_method("prepare_start") or not cache.has_method("prepare_pump"):
		check(false,"loading exposes prepare_start and prepare_pump"); terrain.free(); finish(); return
	# Out of the tree a sector's world box must still be its own: an identity
	# fallback would pile every page at the origin and mis-select the view.
	var placed := true
	for record: Dictionary in cache._sectors:
		var box: AABB = record.box
		placed = placed and box.get_center().distance_to(record.node.position)<.01 and absf(box.size.x-32)<.01 and absf(box.size.z-32)<.01
	check(placed,"sector boxes are placed at their sectors before the terrain enters the tree")
	# 2. prepare_start (still ahead of the reveal) returns with a bounded
	# batch of bakes in flight.
	cache.prepare_start(camera)
	add_child(terrain)
	var limit: int = cache._job_limit(true)
	check(cache._wanted.size()==wanted_pages,"the loading view selects every sector: "+str(cache._wanted.size()))
	var started := job_keys(cache)
	check(cache._jobs.size()==mini(limit,cache._wanted.size()) and cache._jobs.size()>0 and started.size()==cache._jobs.size()
		and started.size()==cache._building.size() and started.keys().all(func(k): return cache._building.has(k))
		and cache._resident.is_empty() and cache.built==0,
		"prepare_start leaves the bounded first batch in flight and nothing resident: "+str(cache._jobs.size())+"/"+str(limit))
	# 3. Pumping between other loading work joins finished pages and starts
	# the rest within the same bound; no page is started twice.
	var active := started.duplicate()
	var duplicate := false; var over := false; var pumps := 0
	while not cache._jobs.is_empty() and pumps<4000:
		OS.delay_msec(5); cache.prepare_pump(); pumps+=1
		var now := job_keys(cache)
		over = over or now.size()>limit
		for key in now:
			if not active.has(key):
				if started.has(key): duplicate=true
				started[key]=true
		active=now
	check(cache._jobs.is_empty() and not duplicate and not over and started.size()==wanted_pages,
		"pumping starts every wanted page exactly once within the bound: pumps="+str(pumps)+" started="+str(started.size()))
	cache.prepare(camera)
	check(cache._jobs.is_empty() and cache._building.is_empty() and cache._resident.size()==wanted_pages
		and cache.built==wanted_pages and cache.discarded==0 and cache.reused==0,
		"prepare after pumping joins with every page resident, built once and nothing discarded: built="+str(cache.built)+" discarded="+str(cache.discarded))
	# 4. Early, pumped bakes produce the exact serial pixels.
	check(pixels_identical(cache),"every pumped page matches the serial bake pixels")
	# 5. A disabled cache starts nothing from the early entry points.
	cache.clear()
	cache.prepare_start(camera); cache.prepare_pump()
	check(not cache._enabled and cache._jobs.is_empty() and cache._building.is_empty() and cache._resident.is_empty() and cache._wanted.is_empty(),
		"prepare_start and prepare_pump on a disabled cache start nothing")
	terrain.free()
	# 6. prepare directly after prepare_start (no pumps) joins the early batch
	# and bakes the remainder, each page exactly once.
	TerrainColorCache.clear_shared()
	var second := make_ahead_terrain(.75)
	var late := TerrainColorCache.create(second); second.color_cache=late; late.set_process(false)
	add_child(second)
	late.prepare_start(camera)
	var early := late._jobs.size()
	late.prepare(camera)
	check(early==mini(limit,wanted_pages) and late._jobs.is_empty() and late._building.is_empty() and late._resident.size()==wanted_pages
		and late.built==wanted_pages and late.discarded==0 and late.reused==0,
		"prepare straight after prepare_start ends with every page resident exactly once: built="+str(late.built))
	check(pixels_identical(late),"pages joined by prepare match the serial bake pixels")
	second.free(); finish()

func finish() -> void:
	camera.queue_free()
	print("TERRAIN_COLOR_AHEAD ",checks," checks ",failures.size()," failures")
	get_tree().quit(int(not failures.is_empty()))

extends Node
const Far = preload("res://src/game/fx/far_grass.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func fixture(side := 64) -> TerrainDetails:
	var terrain := EITerrain.new()
	terrain.map_name = "far-grass-footprint-28513"
	terrain.sectors_x = side/32; terrain.sectors_y = side/32; terrain.grid_w = side+1
	terrain.texture_size = 512; terrain.tile_size = 64
	terrain.heights.resize((side+1)*(side+1)); terrain.heights.fill(4.0)
	terrain.land_xy.resize(terrain.heights.size())
	terrain.surface.resize(side*side); terrain.surface.fill(-INF)
	terrain.water.resize(side*side); terrain.water.fill(-INF)
	terrain.ground.resize(side*side); terrain.land_tile.resize(side*side/4)
	var details := TerrainDetails.new(); details.terrain = terrain; details._grass = true
	var image := Image.create(512,512,false,Image.FORMAT_RGBA8); image.fill(Color(0.18,0.46,0.14))
	details._images[0] = image; details._scenery_signature = [0,0,0,terrain.surface_rev]
	details.prepare_grass()
	return details

func _ready() -> void:
	var details := fixture()
	var begin := Time.get_ticks_usec()
	var field := Far.Field.new(); field.capture(details)
	rows.append({"case":"green-snapshot","us":Time.get_ticks_usec()-begin,"owned_bytes":field.owned_bytes})
	check(field.sampler.native == details._grass_field,"borrows original native sampling field")
	check(not field.patch(Vector2(11.5,18.5)).is_empty(),"green ground supports a full patch")
	var generator := Far.Job.new(); generator.configure(field,Vector3i.ZERO)
	generator.run()
	check(generator.attempted==Far.CELLS*Far.CELLS and generator.count>250,"bounded substantial far generation")
	check(generator.buffer.size()==generator.count*20,"only packed transform/color/custom output")
	var incremental := Far.Job.new(); incremental.configure(field,Vector3i.ZERO)
	var previous := 0
	while not incremental.step(8):
		check(incremental.attempted-previous<=8,"fallback yields every eight candidate cells")
		previous = incremental.attempted
	check(incremental.buffer==generator.buffer,"incremental fallback equals worker generation")
	var coarse := Far.Job.new(); coarse.configure(field,Vector3i(0,0,1)); coarse.run()
	var fine_roots := {}
	for y in 2:
		for x in 2:
			var fine := Far.Job.new(); fine.configure(field,Vector3i(x,y,0)); fine.run()
			for i in fine.count: fine_roots[Vector2(fine.buffer[i*20+3],fine.buffer[i*20+11])] = true
	for i in coarse.count:
		check(fine_roots.has(Vector2(coarse.buffer[i*20+3],coarse.buffer[i*20+11])),"coarsening keeps a deterministic subset")
	rows.append({"case":"green-job","us":generator.elapsed_us,"attempted":generator.attempted,"accepted":generator.count,"packed_bytes":generator.buffer.size()*4})
	var geometry := Far.mesh()
	var vertices: PackedVector3Array = geometry.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices.size()==18,"six opaque triangles per patch")
	for vertex: Vector3 in vertices:
		check(Vector2(vertex.x,vertex.z).length()+0.04<=Far.FOOTPRINT,"all geometry and maximum wind inside supported footprint")
	var node := Far.install(generator,geometry,Far.material())
	check(node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"far patches add no shadow pass")
	check(node.get_child_count()==0,"no interaction or biome geometry")
	node.free()
	var native := details._grass_field
	details._grass_field = null
	var scalar := Far.Field.new(); scalar.capture(details)
	details._grass_field = native
	details._cover_field = field.sampler
	var borrowed := Far.Field.new(); borrowed.capture(details)
	check(borrowed.borrowed_cover and borrowed.owned_bytes==0 and borrowed.sampler==details._cover_field,"existing immutable cover snapshot is reused without terrain/palette copies")
	details._cover_field=null
	for i in 90:
		var p := Vector2(float(i%10)*5.17+1.11,float(i/10)*5.43+0.84)
		check(field.allowed(p)==scalar.allowed(p),"native and scalar immutable sampling agree")
	# Later source mutation must not alter an already-published worker field.
	details.terrain.heights.fill(30.0); details.terrain.water.fill(99.0)
	(details._images[0] as Image).fill(Color.RED)
	var concurrent := Far.Job.new(); concurrent.configure(field,Vector3i.ZERO)
	var task := WorkerThreadPool.add_task(concurrent.run)
	WorkerThreadPool.wait_for_task_completion(task)
	check(concurrent.buffer==generator.buffer,"terrain/image mutation cannot reach a retained worker")
	details.terrain.free(); details.free()
	# A narrow original-atlas painted stripe lies inside the footprint but
	# between its root and all eight perimeter sample points.
	details = fixture()
	var original: Image = details._images[0]
	for y in original.get_height(): original.set_pixel(35,y,Color(0.4,0.2,0.12))
	var path := Far.Field.new(); path.capture(details)
	check(not path.allowed(Vector2(0.92,18.0)).is_empty(),"painted-path control has an eligible root")
	rows.append({"case":"one-pixel-path-approximation","eligible_root":not path.allowed(Vector2(0.92,18.0)).is_empty(),
		"patch_admitted":not path.patch(Vector2(0.92,18.0)).is_empty(),"limitation":"Root plus modest perimeter checks can miss a one-pixel interior stripe; native grass uses root eligibility. No claim of all-pixel masking."})
	for y in original.get_height():
		for x in range(31,40): original.set_pixel(x,y,Color(0.4,0.2,0.12))
	var broad_path := Far.Field.new(); broad_path.capture(details)
	check(broad_path.patch(Vector2(0.92,18.0)).is_empty(),"ordinary painted path under the patch is excluded")
	details._scenery[Vector2i(2,2)] = [{"inverse":Transform3D.IDENTITY,"box":AABB(Vector3(19.35,3.9,-20.6),Vector3(1.4,1.0,1.2))}]
	var blocked := Far.Field.new(); blocked.capture(details)
	check(blocked.patch(Vector2(19.6,20.0)).is_empty(),"expanded original scenery excludes the complete far silhouette")
	for y in range(16,18):
		for x in range(16,18): details.terrain.water[y*64+x] = 5.0
	var wet := Far.Field.new(); wet.capture(details)
	check(wet.patch(Vector2(18.15,17.0)).is_empty(),"dry root cannot overhang adjacent native water cells")
	details.terrain.free(); details.free()
	# The planner must cover a low-angle wide view to the camera far plane,
	# including corners beyond a radial circle of the same radius.
	details = fixture(512)
	field = Far.Field.new(); field.capture(details)
	var camera := Camera3D.new(); add_child(camera)
	camera.position = Vector3(256,8,-90); camera.fov = 65.0; camera.far = 260.0
	camera.look_at(Vector3(256,4,-180))
	await get_tree().process_frame
	var planner := Far.Planner.new()
	var selected: Array[Vector3i] = planner.select(camera,field)
	check(not selected.is_empty() and selected.size()<=Far.MAX_TILES,"visible plan obeys far tile ceiling")
	var unseen := 0; var covered := 0
	for y in range(1,511,5):
		for x in range(1,511,5):
			var point := Vector3(x,4,-y)
			var visible := true
			for plane: Plane in camera.get_frustum():
				if plane.distance_to(point)>0.0: visible = false; break
			if not visible: continue
			var found := false
			for key: Vector3i in selected:
				if planner.box(key).has_point(point): found = true; break
			covered += 1
			if not found: unseen += 1
	check(covered>500 and unseen==0,"every sampled visible ground point belongs to a planned tile")
	rows.append({"case":"260m-plan","visible_ground_samples":covered,"uncovered":unseen,"diagnostic":planner.diagnostic.duplicate()})
	planner.limit = 4
	selected = planner.select(camera,field)
	check(selected.size()<=4 and planner.diagnostic.coarsened,"budget coarsens explicitly instead of truncating wanted tiles")
	for key: Vector3i in selected: check(key.z>=planner.diagnostic.coarsen_bias,"coarse plan uses the reported sample spacing")
	rows.append({"case":"forced-coarsening","diagnostic":planner.diagnostic.duplicate()})
	camera.far = 100.0; planner.limit = Far.MAX_TILES
	selected = planner.select(camera,field)
	check(planner.diagnostic.far_plane==100.0,"Far view off uses the original 100 m plane")
	planner.planes.assign([Plane(Vector3(-1,0,0),-24.10)])
	check(planner.visible(planner.box(Vector3i.ZERO)),"frustum keeps a leaf crossing its root tile edge")
	camera.free(); details.terrain.free(); details.free()
	FileAccess.open("user://far-grass.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("FAR_GRASS checks=",checks," failures=",failures," rows=",JSON.stringify(rows))
	get_tree().quit(1 if failures else 0)

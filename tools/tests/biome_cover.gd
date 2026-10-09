extends Node
## Placement, worker lifetime and real-map rendering of optional dry-land cover.
const Cover = preload("res://src/game/fx/biome_cover.gd")
const Geometry = preload("res://src/game/fx/biome_cover_mesh.gd")
var checks := 0
var failures := 0
var rows := []
var only_kind := -1 # Isolate a species while retaining the authored map/scenery.

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count := 10) -> void:
	for i in count:
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		await get_tree().process_frame

func delta(a: Image,b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var changed := 0; var over := 0; var peak := 0
	for i in range(0,aa.size(),4):
		var d := maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		changed += int(d>0); over += int(d>2); peak = maxi(peak,d)
	return {"changed":changed,"over_2":over,"peak":peak}

func snap(view: SubViewport,label: String) -> Image:
	await frames()
	var image := view.get_texture().get_image(); image.save_png("user://cover-"+label+".png"); return image

func fixture() -> TerrainDetails:
	var t := EITerrain.new(); t.map_name = "cover-fixture"; t.sectors_x = 1; t.sectors_y = 1; t.grid_w = 33
	t.texture_size = 512; t.tile_size = 64
	t.heights.resize(33*33); t.land_xy.resize(33*33)
	t.ground.resize(32*32); t.water.resize(32*32); t.surface.resize(32*32)
	t.water.fill(-INF); t.surface.fill(-INF); t.land_tile.resize(16*16)
	for y in 33:
		for x in 33:
			var i := y*33+x; t.heights[i] = x*0.014+y*0.006
			if x>0 and x<32 and y>0 and y<32: t.land_xy[i] = Vector2(sin(i)*0.07,cos(i)*0.07)
	for y in 32:
		for x in 32:
			t.ground[y*32+x] = 0 if x<16 else 11
			if y<2: t.ground[y*32+x] = 7
			if x<4 and y>12: t.water[y*32+x] = 3
			if x>24 and y>16: t.surface[y*32+x] = 5
	for y in 16:
		for x in 16: t.land_tile[y*16+x] = ((x/8)<<6)|((x+y)%4<<14)|((x+y)%64)
	var d := TerrainDetails.new(); d.terrain = t; d._cover = true
	for i in 2:
		var img := Image.create(128,128,false,Image.FORMAT_RGBA8)
		img.fill(Color(0.12,0.35,0.08) if i==0 else Color(0.43,0.32,0.18)); d._images[i] = img
	d.prepare_grass(); d._cover_field.biome = "gipat"
	d._index_tree(Vector2(12,12),1); d._index_tree(Vector2(20,12),2)
	return d

func rules() -> void:
	var field := Cover.new(); var green := {"type":0,"colour":Color(0.1,0.35,0.08)}
	var dry := {"type":11,"colour":Color(0.4,0.32,0.2)}
	field.biome = "gipat"
	check(field.weights(green,Vector3.ZERO,Vector3(1,0,0))[Cover.Kind.FLOWER]>0,"meadow flowers need a patch")
	check(field.weights(green,Vector3.ZERO,Vector3.ZERO)[Cover.Kind.FLOWER]==0,"meadow stays bare between flower patches")
	check(field.weights({"type":0,"colour":Color(0.4,0.2,0.1)},Vector3.ZERO,Vector3.ONE)[0]==0,"painted non-green meadow is not filled with flowers")
	check(field.weights(dry,Vector3.ZERO,Vector3.ZERO)[1]>0,"dry ground receives dry tufts")
	check(field.weights({"type":11,"colour":green.colour},Vector3.ZERO,Vector3.ONE)[1]==0,"dry rule does not duplicate existing green grass")
	var broad := field.weights(green,Vector3(1,0,0),Vector3.ONE)
	var pine := field.weights(green,Vector3(0,1,0),Vector3.ONE)
	var bare := field.weights(green,Vector3(0,0,1),Vector3.ONE)
	check(broad[2]>0 and broad[3]==0,"broadleaf litter stays separate from needles")
	check(pine[3]>0 and pine[2]==0,"conifers shed needles rather than broad leaves")
	check(bare[2]==0 and bare[3]==0 and bare[4]>0,"bare wood supplies twigs only")
	check(Cover.tree_kind({"template":"nafltr71"})==0 and Cover.tree_kind({"template":"nafltr77"})==0,"cacti and mushrooms do not become litter trees")
	for type in [6,7,8,10,13,14,15]:
		var weights := field.weights({"type":type,"colour":green.colour},Vector3.ONE,Vector3.ONE)
		check(weights == PackedFloat32Array([0,0,0,0,0,0,0]),"liquid/road/ice/unknown/cliff excluded "+str(type))
	field.biome = "ingos"
	var snow := field.weights({"type":9,"colour":Color.WHITE},Vector3.ONE,Vector3.ONE)
	check(snow[2]==0 and snow[3]>0 and snow[1]>0,"snow accepts sparse straw/needles and no broad leaves")
	field.biome = "suslanger"
	check(field.weights(dry,Vector3.ONE,Vector3.ONE)[2]==0,"desert never inherits northern forest litter")
	for context in ["cave","unknown"]:
		field.biome = context
		var weights := field.weights(green,Vector3.ONE,Vector3.ONE)
		check(weights[0]==0 and weights[1]==0 and weights[2]==0 and weights[5]>0,"conservative context "+context)

func snapshot_and_jobs() -> void:
	var d := fixture(); var field := d._cover_field; var rng := RandomNumberGenerator.new(); rng.seed = 329571
	for i in 300:
		var p := Vector2(rng.randf_range(0,32),rng.randf_range(0,32))
		var expected := d.surface_sample(p); var native := field.native; field.native = null
		check(field.sample(p)==expected,"script cover uses authored triangle/UV "+str(i)); field.native = native
		check(field.sample(p)==expected,"native cover uses authored triangle/UV "+str(i))
	check(field.dry_surface(Vector2(2,20)).is_empty(),"submerged roots rejected")
	check(field.dry_surface(Vector2(28,20)).is_empty(),"bridge/floor roots rejected")
	check(field.pressure_allowed(Vector2(20,6)),"dry plants admit ground pressure with grass disabled")
	var expected := {}; var total := 0; var jobs := []; var kinds := {}
	for y in 4:
		for x in 4:
			var key := Vector2i(x,y); var data := d.instances(key)
			check(data.transforms.is_empty(),"cover-only mode creates no grass instances")
			expected[key] = data.cover; total += data.cover.records.size()
			for r: Dictionary in data.cover.records:
				kinds[r.kind] = int(kinds.get(r.kind,0))+1
				check(r.p.x>=key.x*8 and r.p.x<(key.x+1)*8 and r.p.y>=key.y*8 and r.p.y<(key.y+1)*8,"exclusive chunk ownership")
			var job := d._chunk_job(key)
			jobs.append({"key":key,"job":job,"task":WorkerThreadPool.add_task(Callable(job,"run"))})
	d._grass = true
	var together := d.instances(Vector2i(1,1))
	check(not together.transforms.is_empty() and not together.cover.records.is_empty(),"one job can return both grass and cover")
	if d._native_grass:
		var combined := d._chunk_job(Vector2i(1,1))
		jobs.append({"key":Vector2i(1,1),"job":combined,"task":WorkerThreadPool.add_task(Callable(combined,"run")),"combined":together})
	d._grass = false
	# The running jobs must retain their original terrain, images and tree lists.
	d.terrain.heights.fill(99); d.terrain.water.fill(99)
	for image: Image in d._images.values(): image.fill(Color.RED)
	d._trees.clear()
	for record: Dictionary in jobs:
		WorkerThreadPool.wait_for_task_completion(record.task)
		check(record.job.read_result().cover==expected[record.key],"immutable parallel snapshot "+str(record.key))
		if record.has("combined"):
			check(record.job.read_result()==record.combined,"combined native grass/cover survives source mutation")
	check(total>100 and kinds.has(0) and kinds.has(1) and kinds.has(2) and kinds.has(3) and kinds.has(5),"synthetic distribution exercises meadow, dry and forest cover")
	for i in 4:
		var key := Vector2i(i,0); var job := d._chunk_job(key)
		d._grass_jobs.append({"key":key,"generation":d._grass_generation,"kernel":job,"task":WorkerThreadPool.add_task(Callable(job,"run"))})
	d.water_changed()
	check(d._grass_jobs.is_empty() and d._cover_field==null and d._grass_field==null,"water change joins and discards both generators")
	rows.append({"case":"immutable-snapshot","records":total,"kinds":kinds})
	d.terrain.free(); d.free()

func authored() -> void:
	var campaign := CampaignMap.load_from(GameData.texts)
	var ids := ["gz1g","gz3g","gz11k","gz15h","gz5g"]
	if OS.get_cmdline_user_args().has("--cover-astral"): ids = ["gz16g","gz7g","gz21k"]
	for id in ids:
		var zone: Dictionary = campaign.zone(id)
		if zone.is_empty(): continue
		print("COVER_STAGE load ",id)
		var terrain := EITerrain.load_map(zone.mpr)
		print("COVER_STAGE loaded ",id)
		check(terrain!=null,"authored terrain "+id)
		if terrain==null: continue
		var d := terrain.details
		check(d!=null,"cover-only terrain creates its streamer "+id)
		if d==null: terrain.free(); continue
		d.set_process(false); d.prepare_grass()
		print("COVER_STAGE prepared ",id)
		var field := d._cover_field
		check(field!=null,"authored cover snapshot "+id)
		if field==null: terrain.free(); continue
		var keys: Array[Vector2i] = []
		var limit := Vector2i(terrain.size_ei()/8.0)
		for y in 8:
			for x in 8: keys.append(Vector2i((x+0.5)*limit.x/8,(y+0.5)*limit.y/8))
		var path := "maps/%s.mob" % zone.get("mob",zone.mpr)
		if GameFiles.exists(GameData.root.path_join(path)):
			var mob := EIMob.load_bytes(GameData.read_file(path)); var tree_samples := {}
			for info: Dictionary in mob.objects:
				var kind := Cover.tree_kind(info)
				if info.get("template","")=="nafltr75" and not (info.parts as PackedStringArray).is_empty() and not "crownlea" in info.parts:
					check(kind==3,"authored missing crown contributes only woody litter")
				if kind==0: continue
				var p := Vector2(info.position.x,info.position.y); d._index_tree(p,kind)
				if int(tree_samples.get(kind,0))<8:
					keys.append(Vector2i((p/8).floor())); tree_samples[kind] = int(tree_samples.get(kind,0))+1
		var counts := {}; var total := 0; var times := []; var bytes := 0
		for key in keys:
			var start := Time.get_ticks_usec()
			var data := field.build(key,[],d._trees.get(key,[])); times.append(Time.get_ticks_usec()-start)
			bytes += var_to_bytes(data.arrays).size()
			for record: Dictionary in data.records:
				counts[record.kind] = int(counts.get(record.kind,0))+1; total+=1
				if record.get("underwater",false):
					check(not field.sea_surface(record.p).is_empty(),"authored underwater root "+id)
					check(is_finite(field.sea.ceiling(record.p,Cover.RADII[record.kind]*float(record.scale)+0.04)),"authored complete submerged footprint "+id)
				else:
					check(terrain.water_at(record.p.x,record.p.y)<=float(record.height)-0.06,"authored dry-water gate "+id)
					check(field.footprint(record.p,field.dry_surface(record.p),record.kind,Cover.RADII[record.kind]*float(record.scale)),"authored footprint "+id)
		times.sort()
		check(total>0,"authored placements "+id)
		rows.append({"case":"authored-metadata","id":id,"map":zone.mpr,"biome":field.biome,"chunks":keys.size(),"records":total,"counts":counts,
			"build_us_median":times[times.size()/2],"build_us_max":times[-1],"serialized_mesh_bytes":bytes,"scenery_loaded":false})
		print("COVER_AUTHORED ",JSON.stringify(rows[-1]))
		terrain.free()

func build(d: TerrainDetails,p: Vector2) -> Dictionary:
	d.prepare_grass(); d.set_process(false)
	var focus := Vector2i((p/8).floor()); d._focus = focus; var all := {}; var records := 0; var vertices := 0
	for y in range(focus.y-1,focus.y+2):
		for x in range(focus.x-1,focus.x+2):
			var key := Vector2i(x,y); var data := d.instances(key)
			if only_kind>=0 and data.has("cover"):
				data.cover.records = data.cover.records.filter(func(r: Dictionary): return int(r.kind)==only_kind)
				data.cover.arrays = Geometry.new().build(data.cover.records,key,d._cover_field.sea if not d._cover_field.sea.tiles.is_empty() else null)
			if data.has("cover"): records += data.cover.records.size(); vertices += (data.cover.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if not d._chunks.has(key): d._install_chunk(key,data)
			all[key] = data.get("cover",{})
	var view := Vector3(p.x,d.terrain.height_at(p.x,p.y),-p.y)
	d._material.set_shader_parameter("view_position",view)
	if d._cover_material: d._cover_material.set_shader_parameter("view_position",view)
	return {"records":records,"vertices":vertices,"data":all}

func camera_clear(d: TerrainDetails,focus: Vector3) -> bool:
	var from := focus+Vector3(0,0.4,0); var to := focus+Vector3(2.7,2.8,3.5)
	for i in 16:
		var point := from.lerp(to,float(i)/15.0); var p := Vector2(point.x,-point.z)
		var hit := d.surface_sample(p)
		if hit.is_empty() or float(hit.height)>point.y-0.15: return false
		for record: Dictionary in d._scenery.get(Vector2i((p/8).floor()),[]):
			var inverse: Transform3D = record.inverse
			if (record.box as AABB).intersects_segment(inverse*from,inverse*to)!=null: return false
	return true

func choose_cover(d: TerrainDetails,requested: int) -> Dictionary:
	# Keep temporary snapshot references out of the asynchronous render test.
	var chosen := {}; var score := 0; var size := d.terrain.size_ei()
	# Beach debris can be sparse enough to occupy only a single even chunk.
	var step := 1 if requested in [Cover.Kind.WRACK,Cover.Kind.SHELL] else 2
	var margin := step-1
	for y in range(margin,int(size.y/8)-margin,step):
		for x in range(margin,int(size.x/8)-margin,step):
			var key := Vector2i(x,y); var records := d._cover_field.records(key,d._scenery.get(key,[]),d._trees.get(key,[]))
			var flowers := records.filter(func(r: Dictionary): return int(r.kind)==requested)
			if flowers.size()>score:
				for candidate: Dictionary in flowers:
					if camera_clear(d,Vector3(candidate.p.x,candidate.height,-candidate.p.y)):
						chosen = candidate; score = flowers.size(); break
	return chosen

func render_fixture() -> void:
	var id := "gz1g"; var requested := Cover.Kind.FLOWER
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cover-zone="): id = arg.trim_prefix("--cover-zone=")
		if arg.begins_with("--cover-kind="): requested = int(arg.trim_prefix("--cover-kind="))
	var view := SubViewport.new(); view.size = Vector2i(800,600); view.own_world_3d = true
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	world.zone = CampaignMap.load_from(GameData.texts).zone(id)
	var map := EIMapScene.load_map(world.zone.mpr,world.zone.get("mob",""),false)
	world.add_child(map); world.map = map; world.terrain = map.terrain
	var t := map.terrain; t.set_process(false); var d := t.details
	check(d!=null,"cover-only render creates its streamer")
	if d==null: view.free(); return
	d.set_process(false); d.prepare_grass()
	var chosen := choose_cover(d,requested)
	check(not chosen.is_empty(),"authored cover survives complete scenery exclusion")
	if chosen.is_empty(): view.free(); return
	var p: Vector2 = chosen.p; var focus := Vector3(p.x,chosen.height,-p.y)
	var camera := Camera3D.new(); view.add_child(camera); camera.position = focus+Vector3(2.7,2.8,3.5); camera.look_at(focus); camera.current = true
	if chosen.get("underwater",false):
		camera.position.y = maxf(camera.position.y,t.water_at(p.x,p.y)+2.8); camera.look_at(focus)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.13,0.20,0.28); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); sun.shadow_enabled = true; view.add_child(sun)
	var lamp := OmniLight3D.new(); lamp.position = focus+Vector3(1,2,1); lamp.omni_range = 8; lamp.light_energy = 1.0; lamp.shadow_enabled = true; view.add_child(lamp)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO); RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	GameData.options["gfx_biome_cover"] = 0; d.apply_options(); await frames(160)
	if d._grass: build(d,p)
	# The standalone fixture does not run Game's options controller. Prove
	# the old tree wind's TIME animation separately before fixing that input.
	process_mode = Node.PROCESS_MODE_ALWAYS; get_tree().paused = true; Engine.time_scale = 1
	var original_time := await snap(view,"original-wind-control")
	rows.append({"case":"original-wind-control","difference":delta(original_time,await snap(view,"original-wind-control-later"))})
	Gfx.set_foliage_wind(false)
	get_tree().paused = false; Engine.time_scale = 0; process_mode = Node.PROCESS_MODE_INHERIT
	await frames(160)
	var off := await snap(view,"off")
	check(delta(off,await snap(view,"off-stable")).changed==0,"initial scene settles before cover comparison")
	GameData.options["gfx_biome_cover"] = 1; d.apply_options(); var built := build(d,p)
	await frames(160); var on := await snap(view,"on")
	var difference := delta(off,on); check(difference.over_2>30,"authored cover is visibly drawn")
	rows.append({"case":"render","zone":id,"kind":requested,"point":str(p),"records":built.records,"vertices":built.vertices,"difference":difference,
		"draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	var grass_count := 0
	for chunk: MultiMeshInstance3D in d._chunks.values(): grass_count += chunk.multimesh.instance_count
	check(grass_count>0 if d._grass else grass_count==0,"grass and cover switches remain independent")
	GameData.options["gfx_vegetation_interaction"] = 1; d.apply_options(); build(d,p)
	var field := d.interaction; field.focus = Vector2(p.x,-p.y); d._cover_material.set_shader_parameter("vegetation_focus",field.focus)
	# Mobile's first frames after changing the animated shader can differ in
	# a few shadow pixels. Settle this transition just like the on-state above.
	await frames(160)
	var empty_pressure := await snap(view,"empty-pressure")
	check(delta(empty_pressure,await snap(view,"empty-pressure-stable")).changed==0,"empty pressure settles before variant comparison")
	# Interaction expands scenery clearance to contain bent tips. Near walls
	# that can remove plants before any pressure arrives. Compare the shader
	# against the same geometry, and record that intended placement change.
	d._cover_material.shader = Geometry.shader(false,false,false,not d._cover_field.sea.tiles.is_empty())
	var same_geometry := await snap(view,"interaction-clearance-control")
	check(delta(same_geometry,empty_pressure).changed==0,"empty pressure preserves identical cover geometry")
	rows.append({"case":"interaction-clearance","difference":delta(on,same_geometry)})
	d._apply_grass_material()
	var contacts: Array[Dictionary] = [{"id":1,"p":Vector2(p.x,-p.y),"extent":Vector2(0.8,0.8),"angle":0.0}]
	for i in 10: field.advance(contacts,Vector2(p.x,-p.y),0.05)
	var pressed := await snap(view,"pressed")
	difference = delta(same_geometry,pressed)
	check(difference.over_2>10 if requested in [Cover.Kind.FLOWER,Cover.Kind.DRY,Cover.Kind.REED,Cover.Kind.CATTAIL] else difference.changed==0,"plants bend while rigid litter stays fixed")
	rows.append({"case":"pressure","difference":difference})
	for node: MultiMeshInstance3D in d._chunks.values(): d.remove_child(node); d.add_child(node)
	check(delta(pressed,await snap(view,"shadow-refresh")).changed==0,"cover shadows match forced refresh")
	GameData.options["gfx_wind"] = 1; d.apply_options(); t._waves.advance(0.3); d._update_motion(focus)
	var phase: float = d._cover_material.get_shader_parameter("wind_phase")
	check(is_equal_approx(phase,d._material.get_shader_parameter("wind_phase")),"both generators share the pausable wind phase")
	process_mode = Node.PROCESS_MODE_ALWAYS; get_tree().paused = true; Engine.time_scale = 1
	var held := await snap(view,"paused")
	check(delta(held,await snap(view,"paused-later")).changed==0,"paused cover remains fixed while wall time advances")
	get_tree().paused = false; Engine.time_scale = 0; process_mode = Node.PROCESS_MODE_INHERIT
	GameData.options["gfx_wind"] = 0; GameData.options["gfx_vegetation_interaction"] = 0; d.apply_options(); build(d,p)
	var data: Dictionary = built.data; d.water_changed(); build(d,p)
	check(build(d,p).data==data,"clear/reload produces the same cover records and mesh")
	check(delta(on,await snap(view,"rebuilt")).changed==0,"clear/reload restores the cover image")
	d._stream(Vector2i((p/8).floor()))
	check(d._wanted_chunks.size()<=TerrainDetails.MAX_CHUNKS,"cover shares the existing bounded stream")
	var field_ref := weakref(d._cover_field)
	GameData.options["gfx_biome_cover"] = 0; d.apply_options()
	if d._grass: build(d,p)
	await frames(40)
	check(field_ref.get_ref()==null and d._chunks.values().all(func(n: Node): return n.get_node_or_null("BiomeCover")==null),"disabling cover releases its snapshot and meshes")
	check(delta(off,await snap(view,"off-restored")).changed==0,"off-on-off restores the original scene")
	view.free(); await frames()

func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[option] = 0
	GameData.options["gfx_biome_cover"] = 1
	if OS.get_cmdline_user_args().has("--cover-kind-only"):
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--cover-kind="): only_kind = int(arg.trim_prefix("--cover-kind="))
	if OS.get_cmdline_user_args().has("--cover-with-grass"): GameData.options["gfx_grass"] = 1
	if OS.get_cmdline_user_args().has("--cover-water-fx"): GameData.options["gfx_water"] = 1
	Engine.max_fps = 120; Engine.time_scale = 0; DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals()
	if not OS.get_cmdline_user_args().has("--cover-authored-only"):
		rules(); print("COVER_STAGE rules"); snapshot_and_jobs(); print("COVER_STAGE snapshot")
	if DisplayServer.get_name()=="headless": authored()
	else: await render_fixture()
	TexUpscale.shutdown(); await frames(12)
	FileAccess.open("user://biome-cover.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("BIOME_COVER checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

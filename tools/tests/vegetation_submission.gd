extends "biome_cover.gd"
## Geometry/streaming invariants and same-scene submission controls.

func shape_record(kind: int, i: int) -> Dictionary:
	return {"kind":kind,"p":Vector2(9.0+i*2.0,11.0),"height":0.7+i*0.1,
		"seed":0.21+i*0.17,"scale":0.8+i*0.17,"angle":i*1.8,"normal":Vector3(0.2,1,0.3).normalized(),
		"colour":Color(0.3,0.45,0.17),"flower":0.2,"snow":false,"cold":false,
		"anchor":Vector4(4,7,0.2,0.3)}

func geometry_rules() -> void:
	var baseline: Script
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lod-baseline="): baseline = load(arg.trim_prefix("--lod-baseline="))
	var totals := Vector2i.ZERO
	for kind in 14:
		var placed: Array[Dictionary] = []
		for i in 3: placed.append(shape_record(kind,i))
		var geometry := Geometry.new(); var arrays := geometry.build(placed,Vector2i(1,1))
		if baseline: check(arrays==baseline.new().build(placed,Vector2i(1,1)),"near vertex/index attributes unchanged kind "+str(kind))
		var far := geometry.far_indices; var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var roots: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]; var seeds: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var anchors: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]; var plants := {}; var nonzero := 0
		for i in range(0,far.size(),3):
			var a := far[i]; var b := far[i+1]; var c := far[i+2]
			check(a>=0 and b>=0 and c>=0 and maxi(a,maxi(b,c))<vertices.size(),"valid far indices")
			check(roots[a]==roots[b] and roots[a]==roots[c] and seeds[a]==seeds[b] and seeds[a]==seeds[c],"far triangles never cross plants or thinning seeds")
			for offset in 4: check(anchors[a*4+offset]==anchors[b*4+offset] and anchors[a*4+offset]==anchors[c*4+offset],"far triangle retains its ground anchor")
			if (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).length_squared()>1e-16: nonzero+=1; plants[roots[a]]=true
		check(plants.size()==placed.size(),"all plants survive native LOD kind "+str(kind))
		check(nonzero==far.size()/3,"far faces remain nondegenerate kind "+str(kind))
		var near: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		check(far.size()<=near.size(),"LOD never adds geometry")
		totals += Vector2i(near.size(),far.size())
		rows.append({"case":"kind-indices","kind":kind,"plants":placed.size(),"near":near.size(),"far":far.size(),"detail_size":geometry.lod_error})
	check(totals.y<totals.x*0.75,"representative far geometry removes substantial indices")
	print("SUBMISSION_GEOMETRY ",totals)

func root_bounds() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 572718
	var d:=TerrainDetails.new(); var node:=TerrainDetails.Chunk.new(); node.multimesh=MultiMesh.new()
	for basis: Basis in [Basis.IDENTITY,Basis(Vector3.UP,0.7).scaled(Vector3(0.8,2,1.3)),Basis(Vector3.RIGHT,0.1),Basis(Vector3.UP,2.3).scaled(Vector3(-1,1,2))]:
		var transform := Transform3D(basis,Vector3(12,5,-3))
		for trial in 240:
			var key := Vector2i(rng.randi_range(-6,6),rng.randi_range(-6,6))
			var focus := Vector2(rng.randf_range(-90,90),rng.randf_range(-90,90))
			d._cache_root_bounds(key,node,transform); d._cull_chunk(node,focus)
			var bound:=focus.distance_squared_to(focus.clamp(node.plant_bounds.position,node.plant_bounds.end)) if not node.tilted else 0.0
			for i in 8:
				var root := transform*Vector3((key.x+rng.randf())*8,rng.randf_range(-90,90),-(key.y+rng.randf())*8)
				check(bound<=focus.distance_squared_to(Vector2(root.x,root.z))+0.001,"root rectangle is conservative under transform")
				check(node.plants_submitted or focus.distance_to(Vector2(root.x,root.z))>=36.0,"actual culling never removes a live sampled root")
	var box:=TerrainDetails._root_bounds(Vector2i.ZERO,Transform3D.IDENTITY)
	check(is_equal_approx(Vector2(-36,-4).distance_squared_to(Vector2(-36,-4).clamp(box.position,box.end)),1296),"distance uses closest edge rather than chunk center")
	node.free(); d.free()

func culling_lifetime() -> void:
	var d := fixture(); add_child(d); d.set_process(false); var t := d.terrain
	var data := d.instances(Vector2i.ZERO); d._install_chunk(Vector2i.ZERO,data)
	var node: TerrainDetails.Chunk = d._chunks[Vector2i.ZERO]
	check(node.visible and not d._cull_focus.is_finite(),"manual install stays visible before first camera focus")
	node.mounds = MeshInstance3D.new(); node.add_child(node.mounds)
	d._update_submissions(Vector2(-36.08,-4))
	check(node.visible and not node.mounds.visible,"margin retains plants while farther mounds are already faded")
	d._update_submissions(Vector2(-36.7,-4))
	check(not node.visible and node.multimesh.visible_instance_count==0,"fully faded parent submits no grass")
	d._update_submissions(Vector2(-36.66,-4))
	check(not node.visible,"skipped small movement stays beyond the actual fade end")
	d._update_submissions(Vector2(-35.99,-4))
	check(node.visible and node.multimesh.visible_instance_count==-1,"entering the live fade restores grass")
	d._update_submissions(Vector2(-31.99,-4))
	check(node.mounds.visible,"mounds return before their live fade")
	d._update_submissions(Vector2(1000,1000))
	var key := Vector2i(1,1); d._install_chunk(key,d.instances(key))
	check(not (d._chunks[key] as TerrainDetails.Chunk).visible,"late worker install respects last valid focus")
	d._update_submissions(Vector2(4,-4))
	check(node.visible and node.mounds.visible,"teleport back restores existing chunk")
	d._update_submissions(Vector2(-20.3,-4)); d._update_submissions(Vector2(-19.99,-4))
	check(d._view_focus!=d._cull_focus,"fixture moves inside the cached allowance")
	var late_key:=Vector2i(2,0); d._install_chunk(late_key,d.instances(late_key))
	check((d._chunks[late_key] as TerrainDetails.Chunk).visible,"newly installed live root uses the latest view, not the cached scan")
	# Many sub-frame moves accumulate relative to the last scan, not to the
	# previous call. Neither hidden plants nor mounds may cross a live fade.
	for i in 720:
		var focus:=Vector2(-36+sin(i*0.02)*6,-4+cos(i*0.03)*11)
		d._update_submissions(focus)
		var actual:=focus.distance_to(focus.clamp(Vector2(0,-8),Vector2(8,0)))
		check(node.plants_submitted or actual>=36,"cached movement never suppresses live plants")
		check(node.mounds_submitted or actual>=32,"cached movement never suppresses live mounds")
	d.position.x = 200; d._update_submissions(Vector2(4,-4))
	check(node.visible and node.mounds.visible and node.multimesh.visible_instance_count==0,"transformed parent retains still-visible mound only")
	d.rotation.x = 0.1; d._update_submissions(Vector2(4,-4))
	check(node.multimesh.visible_instance_count==-1,"tilted roots use conservative retention")
	d.water_changed()
	check(not d._cull_focus.is_finite() and d._chunks.is_empty(),"flood/option clear invalidates culling state")
	d.free(); t.free()

func counts(view: SubViewport) -> Dictionary:
	return {"visible_draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_primitives":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow_draws":view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_primitives":view.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}

func focus_submissions(d: TerrainDetails,p: Vector3,enabled: bool) -> void:
	d._material.set_shader_parameter("view_position",p)
	if d._cover_material: d._cover_material.set_shader_parameter("view_position",p)
	if d._mound_material: d._mound_material.set_shader_parameter("view_position",p)
	d._submission_culling=enabled; d._cull_focus=Vector2.INF
	d._update_submissions(Vector2(p.x,p.z))

func timing(view:SubViewport,d:TerrainDetails,focus:Vector3) -> void:
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	for mode in [0,1,2,2,1,0]:
		focus_submissions(d,focus,mode>0)
		for node:TerrainDetails.Chunk in d._chunks.values():
			if node.cover: node.cover.lod_bias=(4 if d.interaction else 1) if mode==2 else 10000
		var cpu:=[]; var gpu:=[]; var maintenance:=[]; var total_cost:=0; var scans:=0
		for i in 88:
			var at:=focus+Vector3(sin(i*0.1)*0.8,0,cos(i*0.1)*0.8)
			d._material.set_shader_parameter("view_position",at)
			if d._cover_material:d._cover_material.set_shader_parameter("view_position",at)
			if d._mound_material:d._mound_material.set_shader_parameter("view_position",at)
			var started:=Time.get_ticks_usec()
			var previous_focus:=d._cull_focus
			if mode>0:d._update_submissions(Vector2(at.x,at.z))
			var cost:=Time.get_ticks_usec()-started
			await frames(1)
			if i>=24:
				total_cost+=cost; scans+=int(previous_focus!=d._cull_focus)
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
				maintenance.append(cost)
		cpu.sort();gpu.sort();maintenance.sort()
		rows.append({"case":"render-cost","mode":mode,"viewport_cpu_median_ms":cpu[32],"viewport_gpu_median_ms":gpu[32],"maintenance_median_us":maintenance[32],"maintenance_mean_us":total_cost/64.0,"scans":scans,"samples":64,"counts":counts(view)})

func authored_submission() -> void:
	var id := "gz1g"; var kind := Cover.Kind.FLOWER
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cover-zone="): id=arg.trim_prefix("--cover-zone=")
		if arg.begins_with("--cover-kind="): kind=int(arg.trim_prefix("--cover-kind="))
	var view := SubViewport.new(); view.size=Vector2i(800,600); view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	world.zone=CampaignMap.load_from(GameData.texts).zone(id)
	var map := EIMapScene.load_map(world.zone.mpr,world.zone.get("mob",""),false)
	world.add_child(map); world.map=map; world.terrain=map.terrain
	var t:=map.terrain; t.set_process(false); var d:=t.details; d.set_process(false); d.prepare_grass()
	var chosen:=choose_cover(d,kind)
	check(not chosen.is_empty(),"authored submission witness survives full scenery")
	if chosen.is_empty(): view.free(); return
	var p:Vector2=chosen.p; var focus:=Vector3(p.x,chosen.height,-p.y)
	var key:=Vector2i((p/8).floor()); d._focus=key; d._stream(key)
	var work:=d._queue.duplicate(); d._queue.clear(); var index_counts:=Vector2i.ZERO; var roots:=0
	var baseline:Script
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lod-baseline="): baseline=load(arg.trim_prefix("--lod-baseline="))
	var build_times:=[]; var before_times:=[]
	for chunk:Vector2i in work:
		var data:=d.instances(chunk)
		if baseline and not data.cover.records.is_empty():
			var started:=Time.get_ticks_usec()
			var old_arrays:Array=baseline.new().build(data.cover.records,chunk,d._cover_field.sea if not d._cover_field.sea.tiles.is_empty() else null)
			before_times.append(Time.get_ticks_usec()-started)
			started=Time.get_ticks_usec(); var geometry:=Geometry.new()
			var new_arrays:=geometry.build(data.cover.records,chunk,d._cover_field.sea if not d._cover_field.sea.tiles.is_empty() else null)
			build_times.append(Time.get_ticks_usec()-started)
			check(old_arrays==new_arrays,"authored full vertex attributes remain exact")
		if not data.cover.lods.is_empty():
			index_counts+=Vector2i((data.cover.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),(data.cover.lods.values()[0] as PackedInt32Array).size())
		roots+=data.cover.records.size(); d._install_chunk(chunk,data)
	var camera:=Camera3D.new(); view.add_child(camera); camera.current=true
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.13,0.20,0.28); view.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); sun.shadow_enabled=true; view.add_child(sun)
	var lamp:=OmniLight3D.new(); lamp.position=focus+Vector3(1,2,1); lamp.omni_range=8; lamp.shadow_enabled=true; view.add_child(lamp)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75)); Gfx.set_foliage_wind(false)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO); RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=88
	camera.position=focus+Vector3(15,72,40); camera.look_at(focus)
	focus_submissions(d,focus,false)
	if d.interaction:
		var contacts:Array[Dictionary]=[{"id":1,"p":Vector2(focus.x,focus.z),"extent":Vector2(1,1),"angle":0.0}]
		for i in 12:d.interaction.advance(contacts,Vector2(focus.x,focus.z),0.05)
		d._cover_material.set_shader_parameter("vegetation_focus",d.interaction.focus)
		if d._grass:d._material.set_shader_parameter("vegetation_focus",d.interaction.focus)
	if OS.get_cmdline_user_args().has("--submission-hide-scenery"):
		map.get_node("Objects").hide()
	await frames(120)
	for i in 5:
		var centre:Vector3=focus+[Vector3.ZERO,Vector3(4.05,0,0),Vector3(7.99,0,-7.99),Vector3(120,0,-120),Vector3.ZERO][i]
		focus_submissions(d,centre,false)
		var before:=await snap(view,"cull-%d-off"%i); var before_count:=counts(view)
		check(delta(before,await snap(view,"cull-%d-off-stable"%i)).changed==0,"culling baseline settled")
		focus_submissions(d,centre,true)
		var after:=await snap(view,"cull-%d-on"%i); var difference:=delta(before,after); var after_count:=counts(view)
		check(difference.changed==0,"fully faded culling preserves rendered pixels "+str(i))
		check(after_count.visible_primitives<=before_count.visible_primitives and after_count.shadow_primitives<=before_count.shadow_primitives,"culling does not increase submissions")
		rows.append({"case":"authored-culling","zone":id,"focus":str(centre),"difference":difference,"before":before_count,"after":after_count,
			"hidden_chunks":d._chunks.values().filter(func(n:TerrainDetails.Chunk):return not n.visible).size()})
	# LOD is selected by normal projected size, never by a forced threshold.
	# A large instance bias supplies a same-pack full-detail control.
	focus_submissions(d,focus,true)
	for item:Dictionary in [{"name":"near","offset":Vector3(2.7,2.8,3.5),"fov":60.0},
		{"name":"middle","offset":Vector3(8,12,16),"fov":60.0},{"name":"wide","offset":Vector3(18,28,36),"fov":60.0}]:
		camera.projection=Camera3D.PROJECTION_PERSPECTIVE; camera.fov=item.fov; camera.position=focus+item.offset; camera.look_at(focus)
		for node:TerrainDetails.Chunk in d._chunks.values():
			if node.cover: node.cover.lod_bias=10000
		var full:=await snap(view,"lod-"+item.name+"-full"); var full_count:=counts(view)
		for node:TerrainDetails.Chunk in d._chunks.values():
			if node.cover: node.cover.lod_bias=4 if d.interaction else 1
		var lod:=await snap(view,"lod-"+item.name+"-auto"); var lod_count:=counts(view)
		check(lod_count.visible_primitives<=full_count.visible_primitives,"automatic LOD never adds primitives")
		rows.append({"case":"authored-lod","zone":id,"distance":item.name,"difference":delta(full,lod),"before":full_count,"after":lod_count})
		for node:TerrainDetails.Chunk in d._chunks.values():
			if node.cover: node.cover.lod_bias=10000
		check(delta(full,await snap(view,"lod-"+item.name+"-restored")).changed==0,"restoring full detail restores image")
	# Include a moving focus scan and the stationary early return separately.
	var costs:=[]; var idle_costs:=[]; var total_cost:=0; var scan_count:=0
	for i in 240:
		var at:=Vector2(focus.x+sin(i*0.1)*0.8,focus.z+cos(i*0.1)*0.8)
		var previous_focus:=d._cull_focus
		var started:=Time.get_ticks_usec(); d._update_submissions(at); var cost:=Time.get_ticks_usec()-started; costs.append(cost); total_cost+=cost
		scan_count+=int(previous_focus!=d._cull_focus)
		started=Time.get_ticks_usec(); d._update_submissions(at); idle_costs.append(Time.get_ticks_usec()-started)
	costs.sort(); idle_costs.sort(); build_times.sort(); before_times.sort()
	rows.append({"case":"maintenance-cost","zone":id,"chunks":d._chunks.size(),"cover_roots":roots,"near_indices":index_counts.x,"far_indices":index_counts.y,
		"culling_moving_median_us":costs[120],"culling_moving_p95_us":costs[228],"culling_idle_median_us":idle_costs[120],
		"culling_moving_mean_us":total_cost/240.0,"actual_scans":scan_count,"movement_samples":240,
		"geometry_before_median_us":before_times[before_times.size()/2] if not before_times.is_empty() else 0,
		"geometry_candidate_median_us":build_times[build_times.size()/2] if not build_times.is_empty() else 0})
	if OS.get_cmdline_user_args().has("--submission-timing"): await timing(view,d,focus)
	view.free(); await frames()

func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[option] = 0
	GameData.options["gfx_biome_cover"] = 1
	Engine.max_fps = 120; Engine.time_scale = 0; DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals()
	geometry_rules(); root_bounds(); culling_lifetime()
	if DisplayServer.get_name()!="headless":
		if OS.get_cmdline_user_args().has("--cover-with-grass"): GameData.options["gfx_grass"]=1
		if OS.get_cmdline_user_args().has("--submission-interaction"): GameData.options["gfx_vegetation_interaction"]=1
		await authored_submission()
	TexUpscale.shutdown(); await frames(12)
	FileAccess.open("user://vegetation-submission.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("VEGETATION_SUBMISSION checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

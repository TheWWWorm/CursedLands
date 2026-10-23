extends "res://tools/tests/path_trace_performance.gd"
## A representative original prop group in the real campaign renderer.
## Toggle the same bound maps for an interleaved comparison of both raster
## receivers and ray hits. Scene geometry, lighting and ray budget stay fixed.
func bounds_of(root: Node3D) -> AABB:
	var bounds:=AABB();var first:=true
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null or not mesh.is_visible_in_tree():continue
		var b:=mesh.global_transform*mesh.get_aabb()
		bounds=b if first else bounds.merge(b);first=false
	return bounds

func changed_surface(before: Image,after: Image,old_guide: Image,new_guide: Image) -> Dictionary:
	var pixels:=0;var error:=0.0
	for y in range(0,new_guide.get_height(),2):
		for x in range(0,new_guide.get_width(),2):
			var a:=old_guide.get_pixel(x,y);var b:=new_guide.get_pixel(x,y)
			if a.a<=0 or absf(a.a-b.a)>0.002 or Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()<0.015:continue
			var px:=mini(int((x+0.5)*after.get_width()/new_guide.get_width()),after.get_width()-1)
			var py:=mini(int((y+0.5)*after.get_height()/new_guide.get_height()),after.get_height()-1)
			var ca:=before.get_pixel(px,py);var cb:=after.get_pixel(px,py)
			error+=absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b);pixels+=1
	return {"changed_normal_pixels":pixels,"displayed_surface_difference":error/maxf(pixels*3,1)}

func run() -> void:
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	game.set_process_input(false);game.set_process_unhandled_input(false)
	# Original precipitation advances independently of the paused world. Keep
	# stochastic drops out of material comparison images and measurement masks.
	for child in game.get_children():
		if child is FxRainSnow:child.process_mode=Node.PROCESS_MODE_DISABLED;child.hide()
	var visual_only:=OS.get_cmdline_user_args().has("--pt-visual-only")
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,
		"gfx_foliage_light":1,"gfx_terrain_cliffs":1,"character_light":0,"pt_mode":2,
		"pt_accumulation":0,"q_rt_lighting":1},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	var root:=Node3D.new();session.world.add_child(root);session.world.objects["pt_surface_audit"]=root
	var tree: Node3D=session.world.objects[4442]
	var origin:=tree.global_position+Vector3(6,0,0);var best:=INF
	for radius: float in [8.0,14.0,20.0,28.0]:
		for direction in 24:
			var p:=tree.global_position+Vector3(cos(direction*TAU/24.0),0,sin(direction*TAU/24.0))*radius
			p.y=t.height_at(p.x,-p.z)
			var water:=t.water_at(p.x,-p.z)
			if is_finite(water) and p.y<water+0.2:continue
			var slope:=0.0
			for offset: Vector2 in [Vector2(-2,0),Vector2(2,0),Vector2(0,-1),Vector2(0,1)]:
				slope=maxf(slope,absf(t.height_at(p.x+offset.x,-p.z+offset.y)-p.y))
			var score:=slope+radius*0.002
			if score<best:best=score;origin=p
	root.global_position=origin
	var materials:={};var templates:=[]
	# Use records from the original maps, retaining their actual complexion
	# and visible part selection instead of guessing the correct mesh variant.
	for source: Array in [["zone1","bridge00","stbr1"],["zone13","stone03","nast6"],["zone1","columnruins01","stst13"]]:
		var mob:=EIMob.load_bytes(FileAccess.get_file_as_bytes(GameData.root.path_join("maps/"+source[0]+".mob")))
		var record:={}
		for o: Dictionary in mob.objects:
			if o.texture==source[1] and o.template==source[2] and o.kind in ["OBJECT","LEVER"]:record=o;break
		check(not record.is_empty(),"original map contains authored prop "+source[1])
		if record.is_empty():continue
		var model:=EIFigure.instantiate(record.template,record.texture,record.complexion,record.parts,false,true)
		check(model!=null,"instantiate original prop "+source[1])
		if model==null:continue
		root.add_child(model);templates.append(record.template)
		var bounds:=bounds_of(model)
		# Fit the pilot group at comparable physical sizes without editing the
		# original figure or changing its UV layout.
		model.scale*=3.0/maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z)) if templates.size()==1 else 1.8/maxf(bounds.size.y,0.1)
		bounds=bounds_of(model)
		model.global_position+=Vector3((templates.size()-2)*2.0,0,0)+origin-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			for i in mesh.mesh.get_surface_count():
				var mat:=mesh.get_active_material(i) as ShaderMaterial
				if mat!=null and mat.get_shader_parameter("surface_detail_tex") is Texture2D:materials[mat.get_instance_id()]=mat
	check(materials.size()>=3,"all three original props bind authored data maps")
	if failures.size()>0:get_tree().quit(1);return
	var bounds:=bounds_of(root);var target:=bounds.get_center()
	camera.global_position=target+Vector3(0.25,0.18,1).normalized()*maxf(bounds.size.y*2.2,bounds.size.x*1.28)
	camera.look_at(target);camera.fov=45
	t.apply_gfx();Gfx.apply_env(game._env)
	get_window().min_size=Vector2i(1,1);get_window().size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var rt: Node=game.get_node("SceneRaytrace")
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before);process_priority=102
	var captures:={};var layer_counts:=[]
	for enabled: bool in ([false,true] if visual_only else [false,true,true,false]):
		for material: ShaderMaterial in materials.values():material.set_shader_parameter("surface_detail_enabled",enabled)
		check(await ready_snapshot(rt),"prop snapshot settles with maps "+str(enabled))
		if not rt.stats.get("active",false):get_tree().quit(1);return
		var mapped:=0;var uploaded:=0;var pilot_mapped:=0
		for g: Dictionary in rt._scene.geometries:mapped+=int(g.get("detail_layer",-1)>=0)
		for g: Dictionary in rt.device._geometry:uploaded+=int(g.get("detail_layer",-1)>=0)
		for entry: Dictionary in rt._scene.instances:
			var mesh: Node3D=entry.node.get_ref()
			if mesh!=null and root.is_ancestor_of(mesh):pilot_mapped+=int(rt._scene.geometries[entry.geometry].get("detail_layer",-1)>=0)
		check(mapped==uploaded and (pilot_mapped>=3 if enabled else pilot_mapped==0),"controller preserves the current detail descriptors "+str(enabled))
		layer_counts.append(rt._scene.images.size())
		await frames(64);await get_tree().create_timer(2.2,true,false,true).timeout
		var started:=Time.get_unix_time_from_system()
		gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();sampling=not visual_only
		for i in (0 if visual_only else 120):await frames(1)
		sampling=false
		runs.append({"mapped":enabled,"rt_gpu_ms":summary(gpu_samples.duplicate()),"gpu_stages_ms":stage_summary(),
			"controller_cpu_ms":summary(cpu_samples.duplicate()),"stats":rt.stats.duplicate(),
			"sample_started_unix":started,"sample_ended_unix":Time.get_unix_time_from_system()})
		if not captures.has(enabled):
			captures[enabled]=await capture("props-authored" if enabled else "props-legacy")
			rt.device.guide.get_image().save_exr(out.path_join("props-authored-normal.exr" if enabled else "props-legacy-normal.exr"))
			rt.device.shadow1.get_image().save_exr(out.path_join("props-authored-material.exr" if enabled else "props-legacy-material.exr"))
	var difference:=mean_difference(captures[true],captures[false])
	check(difference>0.0002,"authored maps change the displayed campaign image")
	check(layer_counts[1]>=layer_counts[0] and layer_counts[1]-layer_counts[0]<=3,"shared maps reuse background layers without duplicating every prop")
	# A fixed warm inspection light makes the close surface response legible.
	# It is created after the benchmark and is not a campaign lighting change.
	var key:=OmniLight3D.new();game.add_child(key);key.add_to_group(Gfx.POINT_LIGHT_GROUP)
	key.light_color=Color(1.0,0.8,0.56);key.light_energy=5;key.omni_range=7;key.light_size=0.14
	var close_differences:=[]
	for index in [1,2]:
		var object: Node3D=root.get_child(index);var box:=bounds_of(object);var center:=box.get_center()
		# stst13 includes a long fallen beam and an upright at its +X end.
		# Inspect the upright instead of framing the whole disconnected ruin.
		if index==2:center.x=box.end.x-box.size.y*0.5
		camera.global_position=center+Vector3(0.25,0.18,1).normalized()*(box.size.y*1.65 if index==2 else maxf(box.size.y*1.65,box.size.x*0.85))
		camera.look_at(center);key.global_position=center+Vector3(2.7,0.8,1.0)
		var close:={};var guides:={}
		for enabled: bool in [false,true]:
			for material: ShaderMaterial in materials.values():material.set_shader_parameter("surface_detail_enabled",enabled)
			rt._collect_lights(center)
			check(await ready_snapshot(rt),"close inspection settles "+str(index)+" "+str(enabled))
			await frames(64);await get_tree().create_timer(2.2,true,false,true).timeout
			close[enabled]=await capture("close-%s-%s"%[templates[index],"authored" if enabled else "legacy"])
			guides[enabled]=rt.device.guide.get_image()
		var delta:=changed_surface(close[false],close[true],guides[false],guides[true]);close_differences.append(delta)
		check(delta.changed_normal_pixels>100 and delta.displayed_surface_difference>0.002,
			"mapped surface pixels change in close inspection "+str(index)+": "+str(delta))
	FileAccess.open(out.path_join("path-surface-detail-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,
		"failures":failures,"runs":runs,"templates":templates,"camera":str(camera.global_transform),"image_difference":difference,
		"close_differences":close_differences,"layer_counts":layer_counts,"viewport":str(get_viewport().get_visible_rect().size),
		"visual_only":visual_only,"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name()},"\t"))
	set_process(false);before.queue_free();session.world.objects.erase("pt_surface_audit")
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)

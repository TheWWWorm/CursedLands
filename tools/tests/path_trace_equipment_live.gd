extends "res://tools/tests/path_trace_material_performance.gd"
## Original equipped figures in the campaign renderer, with interleaved old/new
## hit programs. Geometry, colour textures, lighting and tracing budget match.
func authored_item(table: String,kind: String,material_type: String) -> String:
	for row: Dictionary in GameData.db.table(table):
		if String(row.get("type","")).to_lower()!=kind or String(row.get("material_type","")).to_lower()!=material_type:continue
		for mat: Dictionary in GameData.db.table("materials"):
			if String(mat.get("type","")).to_lower()==material_type:
				return String(row.name).to_lower()+"."+String(mat.name).to_lower()
	return ""

func metal_pixels(rt: Node) -> int:
	var image: Image=rt.device.shadow1.get_image();var count:=0
	for y in range(0,image.get_height(),2):
		for x in range(0,image.get_width(),2):
			if (int(roundf(image.get_pixel(x,y).a))>>6)>15:count+=1
	return count

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pt-hit-reference="):hit_reference=arg.trim_prefix("--pt-hit-reference=")
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,
		"gfx_foliage_light":1,"gfx_terrain_cliffs":1,"character_light":1,"pt_mode":2,
		"pt_accumulation":0,"q_rt_lighting":1},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	var root:=Node3D.new();session.world.add_child(root);session.world.objects["pt_equipment_audit"]=root
	var tree: Node3D=session.world.objects[4442]
	var origin:=tree.global_position+Vector3(6,0,0)
	var best:=INF
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
	origin.y=t.height_at(origin.x,-origin.z);root.global_position=origin
	var sword:=authored_item("weapons","sword","metal")
	var armor: Array[String]=[]
	for kind: String in ["plate","leggings","helm"]:
		var item:=authored_item("armors",kind,"metal")
		if not item.is_empty():armor.append(item)
	print("EQUIPMENT_OUTFIT ",armor," weapon=",sword)
	check(not sword.is_empty() and armor.size()==3,"original database supplies a complete metal outfit")
	var bounds:=AABB();var bounded:=false
	var maps:={};var selected_material: ShaderMaterial
	for i in 2:
		var record:={"prototype":"Human Hero","armors":armor if i==0 else [],"weapons":[sword]}
		var model:=EIUnitModel.create(record,false,false)
		check(model!=null,"create original equipped figure "+str(i))
		if model==null:continue
		root.add_child(model);model.position.x=(float(i)-0.5)*1.4
		model.set_process(false);model.rotation.y=-0.25
		if model.player:
			model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			model.act("idle",1,0.0);model.player.seek(0.3,true);model.player.speed_scale=0
		model.flush_pending_pose()
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if not mesh.is_visible_in_tree() or mesh.mesh==null:continue
			var box:=mesh.global_transform*mesh.get_aabb()
			bounds=bounds.merge(box) if bounded else box;bounded=true
			for surface in mesh.mesh.get_surface_count():
				var mat:=mesh.get_active_material(surface) as ShaderMaterial
				if mat==null:continue
				var tex:=mat.get_shader_parameter("surface_tex") as Texture2D
				if tex!=null:
					maps[tex.get_instance_id()]=tex
					if i==0:selected_material=mat
	check(bounded and maps.size()>=2,"real figures carry composed body and weapon masks")
	for tex: Texture2D in maps.values():
		var im:=tex.get_image();im.convert(Image.FORMAT_RGBA8)
		var data:=im.get_data();var peak:=0
		for at in range(2,im.get_width()*im.get_height()*4,4):peak=maxi(peak,data[at])
		print("EQUIPMENT_MASK ",tex.get_instance_id()," size=",im.get_size()," metal_peak=",peak)
	if not bounded or failures.size()>0:get_tree().quit(1);return
	var target:=bounds.get_center()
	var distance:=maxf(bounds.size.y*2.1,bounds.size.x*1.25)
	camera.global_position=target+Vector3(0.3,0.12,1).normalized()*distance
	camera.look_at(target);camera.fov=45
	t.apply_gfx();Gfx.apply_env(game._env)
	get_window().min_size=Vector2i(1,1);get_window().size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"equipped campaign scene prepares")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	var mapped:=0
	for geometry: Dictionary in rt._scene.geometries:
		if geometry.get("surface_layer",-1)>=0:mapped+=1
	check(mapped>0,"campaign snapshot retains original equipment masks")
	var uploaded:=0
	for geometry: Dictionary in rt.device._geometry:
		if geometry.get("surface_layer",-1)>=0:uploaded+=1
	check(uploaded==mapped,"render-thread descriptors retain all collected material-map indices")
	var receiver_count:=0;var receiver_layers:={}
	for entry: Dictionary in rt._scene.instances:
		var mesh: Node3D=entry.node.get_ref()
		if mesh!=null and root.is_ancestor_of(mesh):
			receiver_count+=int((entry.mask&1)!=0)
			var geo: Dictionary=rt._scene.geometries[entry.geometry]
			receiver_layers[geo.get("surface_layer",-1)]=true
	print("EQUIPMENT_RECEIVERS ",receiver_count," layers=",receiver_layers)
	var reference_images:={};var reference_metals:={}
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before);process_priority=102
	for reference: bool in [true,false,false,true]:
		RenderingServer.call_on_render_thread(select_hit.bind(rt.device,reference))
		check(await hit_selected,"bind equipment comparison shader "+str(reference))
		await frames(64)
		# Keep startup/pipeline compilation outside both timed samples and the
		# FPS overlay's trailing window in the comparison captures.
		await get_tree().create_timer(2.2,true,false,true).timeout
		gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();sampling=true
		for i in 120:await frames(1)
		sampling=false
		runs.append({"reference":reference,"rt_gpu_ms":summary(gpu_samples.duplicate()),"gpu_stages_ms":stage_summary(),
			"controller_cpu_ms":summary(cpu_samples.duplicate()),"stats":rt.stats.duplicate()})
		if not reference_images.has(reference):
			reference_images[reference]=await capture("equipment-before" if reference else "equipment-after")
			reference_metals[reference]=metal_pixels(rt)
			rt.device.shadow1.get_image().save_exr(out.path_join("equipment-before-material.exr" if reference else "equipment-after-material.exr"))
	var difference:=mean_difference(reference_images[true],reference_images[false])
	check(reference_metals[false]>reference_metals[true]+100,"actual character pixels acquire their mapped metal response")
	check(difference>0.0005,"material maps change the displayed campaign image")
	RenderingServer.call_on_render_thread(select_hit.bind(rt.device,false));await hit_selected
	var previous: Object=rt._scene
	var changed:=Image.create(16,16,false,Image.FORMAT_RGBA8);changed.fill(Color(0.08,0.92,0))
	selected_material.set_shader_parameter("surface_tex",ImageTexture.create_from_image(changed))
	check(previous.topology_changed(),"live mask replacement is detected without changing colour texture or mesh")
	check(await ready_snapshot(rt),"live mask replacement prepares a new snapshot")
	check(rt._scene!=previous and not rt._scene.topology_changed(),"updated material settles without continuous rebuilds")
	FileAccess.open(out.path_join("path-equipment-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,
		"failures":failures,"runs":runs,"mapped_geometries":mapped,"unique_masks":maps.size(),"metal_pixels":reference_metals,
		"image_difference":difference,"outfit":armor,"weapon":sword,"camera":str(camera.global_transform),
		"viewport":str(get_viewport().get_visible_rect().size),"texture_layers":rt._scene.images.size(),
		"texture_bytes":rt._scene.images.reduce(func(total: int,im: Image):return total+im.get_data_size(),0)},"\t"))
	set_process(false);before.queue_free();session.world.objects.erase("pt_equipment_audit")
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)

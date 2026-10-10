extends "clouds.gd"
## Persistent field ownership, frame-aligned updates, release and fallback.
const Field = preload("res://src/game/fx/cloud_shadow_field.gd")

static func _texture_status(job: Dictionary) -> void:
	job.live=RenderingServer.get_rendering_device().texture_is_valid(job.rid)
	job.done.post()

func texture_live(rid: RID) -> bool:
	var job:={"rid":rid,"live":false,"done":Semaphore.new()}
	RenderingServer.call_on_render_thread(_texture_status.bind(job));job.done.wait()
	return job.live

func _ready() -> void:
	GameData.options.merge({"gfx_clouds":3,"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":0},true)
	Gfx.ensure_globals();Gfx.apply_surface_options();Engine.time_scale=0;Engine.max_fps=0;process_mode=Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",SUN)
	var clouds:=Clouds.new()
	var frame: Dictionary=clouds.sample(0,"field-lifecycle","Ingos",Vector4(.8,.6,.8,1),.52,0,12,false).duplicate(true)
	var views: Array[SubViewport]=[];var owners: Array[Node3D]=[]
	for i in 2:
		var view:=SubViewport.new();view.size=Vector2i(128,128);view.own_world_3d=true
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view);views.append(view)
		var owner:=Node3D.new();view.add_child(owner);owners.append(owner)
	var supported:=RenderingServer.get_current_rendering_method()=="forward_plus" and Clouds.VolumeNoise.supported()
	for cycle in 3:
		GameData.options.gfx_clouds=2+cycle%2;Gfx.apply_surface_options()
		Gfx.set_cloud_frame(owners[0].get_instance_id(),frame)
		await frames(4)
		Gfx.set_cloud_frame(owners[0].get_instance_id(),frame)
		await frames(4)
		if not supported:
			check(Gfx._cloud_shadow_field==null,"unsupported renderer allocates no shared field")
			check(not Clouds.shadow_source().contains("cv_shadow_field"),"unsupported renderer retains its existing source")
			Gfx.clear_clouds();continue
		var active:=Gfx._cloud_shadow_field
		check(active!=null,"active world creates a shared shadow field")
		check(active.view.get_parent()==views[0],"producer is a child of the receiving viewport")
		check(active.view.size==Vector2i(512,512) and active.view.use_hdr_2d,"bounded HDR grid")
		check(active.view.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"daylight updates every rendered frame")
		check(Clouds.shadow_source().contains("cv_shadow_field"),"Forward+ consumers use the shared field")
		var first:=active.view.get_texture().get_image()
		check(first.get_format() in [Image.FORMAT_RGBH,Image.FORMAT_RGBAH],"16-bit storage is active")
		for i in 8:Gfx.set_cloud_frame(owners[0].get_instance_id(),frame);await frames(1)
		check(active.view.get_texture().get_image().get_data()==first.get_data(),"held cloud state keeps exact field pixels")
		var current_view:=active.view
		var old_rid:=RenderingServer.texture_get_rd_texture(current_view.get_texture().get_rid())
		check(texture_live(old_rid),"producer has a live GPU texture")
		Gfx.clear_clouds(owners[1].get_instance_id())
		check(Gfx._cloud_shadow_field==active and active.view==current_view,"inactive world cannot clear active field")
		var night:=frame.duplicate(true);night.state.y=0.0
		Gfx.set_cloud_frame(owners[0].get_instance_id(),night);await frames(3)
		check(active.view==current_view and active.view.render_target_update_mode==SubViewport.UPDATE_DISABLED,"night suspends field work without reallocating")
		Gfx.set_cloud_frame(owners[0].get_instance_id(),frame);await frames(3)
		check(active.view==current_view and active.view.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"daylight resumes the same field")
		var old:=weakref(current_view);current_view=null
		Gfx.set_cloud_frame(owners[1].get_instance_id(),frame);await frames(4)
		Gfx.set_cloud_frame(owners[1].get_instance_id(),frame);await frames(4)
		check(old.get_ref()==null,"viewport switch destroys the previous producer")
		check(not texture_live(old_rid),"viewport switch releases the old GPU texture")
		check(active.view.get_parent()==views[1],"new receiver renders after its own producer")
		check(views[0].get_child_count()==1 and views[1].get_child_count()==2,"one bounded producer survives ownership transfer")
		var gone:=weakref(active.view)
		var final_rid:=RenderingServer.texture_get_rd_texture(active.view.get_texture().get_rid())
		GameData.options.gfx_clouds=0;Gfx.apply_surface_options();await frames(4)
		check(Gfx._cloud_shadow_field==null and gone.get_ref()==null,"disabling clouds releases the field")
		check(not texture_live(final_rid),"disabling clouds releases the GPU texture")
		check(views[0].get_child_count()==1 and views[1].get_child_count()==1,"no viewport children accumulate after toggles")
	# Exercise attach followed immediately by release, before deferred parenting.
	if supported:
		GameData.options.gfx_clouds=3;Gfx.apply_surface_options();Gfx.set_cloud_frame(owners[0].get_instance_id(),frame)
		var pending:=weakref(Gfx._cloud_shadow_field.view)
		Gfx.clear_clouds();await frames(4)
		check(pending.get_ref()==null and views[0].get_child_count()==1,"pending attachment is also released on a rapid toggle")
	Gfx.clear_clouds()
	for view: SubViewport in views:view.free()
	TexUpscale.shutdown();await frames(8)
	FileAccess.open("user://cloud-shadow-field-lifecycle.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"supported":supported},"\t"))
	print("CLOUD_SHADOW_FIELD checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

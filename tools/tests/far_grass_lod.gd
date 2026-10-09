extends "far_grass.gd"

func frames(count:=10) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func capture(view: SubViewport, name: String) -> Image:
	await frames(12)
	var image:=view.get_texture().get_image()
	image.save_png("user://far-lod-"+name+".png")
	return image

func difference(a: Image,b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGB8); b.convert(Image.FORMAT_RGB8)
	var aa:=a.get_data(); var bb:=b.get_data(); var changed:=0; var over:=0; var peak:=0
	for i in range(0,aa.size(),3):
		var d:=maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		changed+=int(d>0); over+=int(d>2); peak=maxi(peak,d)
	return {"changed":changed,"over_2":over,"peak":peak}

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	Engine.time_scale=0; Engine.max_fps=120; Gfx.ensure_globals()
	var details:=fixture(256)
	var field:=Far.Field.new(); field.capture(details)
	var parent:=Vector3i(2,3,1)
	var coarse:=Far.Job.new(); coarse.configure(field,parent); coarse.run()
	var children: Array=[]
	for y in 2:
		for x in 2:
			var job:=Far.Job.new(); job.configure(field,Vector3i(parent.x*2+x,parent.y*2+y,0)); job.run(); children.append(job)
	var roots:={}
	for job: RefCounted in children:
		for i in job.count:
			if job.buffer[i*20+18]>=1.0: roots[Vector2(job.buffer[i*20+3],job.buffer[i*20+11])]=job.buffer.slice(i*20,i*20+17)
	check(roots.size()==coarse.count,"every surviving fine root has exactly one parent")
	for i in coarse.count:
		var p:=Vector2(coarse.buffer[i*20+3],coarse.buffer[i*20+11])
		check(roots.has(p) and roots[p]==coarse.buffer.slice(i*20,i*20+17),"parent preserves transform, colour and wind seed")
	var view:=SubViewport.new(); view.size=Vector2i(1000,750); view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera:=Camera3D.new(); view.add_child(camera); camera.current=true; camera.fov=24; camera.far=260
	camera.position=Vector3(120,10,-42); camera.look_at(Vector3(120,4,-168))
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment); view.add_child(env)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.1,0.15,0.2)
	var sun:=DirectionalLight3D.new(); view.add_child(sun); sun.rotation_degrees=Vector3(-45,-35,0)
	Gfx.update_original(env.environment,sun,null,12,false)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(200,260,0))
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	var mesh:=Far.mesh(); var material:=Far.material()
	material.set_shader_parameter("view_position",Vector3(120,4,-42)); material.set_shader_parameter("breeze",0)
	material.set_shader_parameter("stream_clock",1.0)
	var fine_nodes: Array=[]
	for job: RefCounted in children:
		var node:=Far.install(job,mesh,material); view.add_child(node); fine_nodes.append(node)
	var coarse_node:=Far.install(coarse,mesh,material); view.add_child(coarse_node); coarse_node.visible=false
	await frames(40)
	var fine:=await capture(view,"fine")
	for node: Node3D in fine_nodes: node.visible=false
	coarse_node.visible=true
	var low:=await capture(view,"coarse")
	check(difference(fine,low).changed==0,"distance replacement is pixel-exact after fine-only roots fade")
	rows.append({"kind":"distance_swap","difference":difference(fine,low)})
	coarse_node.visible=false
	var empty:=await capture(view,"empty")
	check(difference(fine,empty).over_2>200,"LOD witness contains visible distant grass")
	# A newly exposed tile arrives smoothly, while a retained parent root does
	# not shrink a second time during refinement.
	var arriving:=Far.install(coarse,mesh,material,1.0,99); view.add_child(arriving)
	material.set_shader_parameter("stream_clock",1.0)
	var start:=await capture(view,"arrival-start")
	material.set_shader_parameter("stream_clock",1.125)
	var middle:=await capture(view,"arrival-middle")
	material.set_shader_parameter("stream_clock",1.25)
	var end:=await capture(view,"arrival-end")
	check(difference(start,empty).changed==0,"new tile starts with no visible sudden appearance")
	check(difference(start,middle).over_2>0 and difference(middle,end).over_2>0,"new tile has an intermediate coverage state")
	check(difference(end,low).changed==0,"arrival ends at the unchanged deterministic grass bed")
	rows.append({"kind":"arrival","start_middle":difference(start,middle),"middle_end":difference(middle,end)})
	view.free(); details.terrain.free(); details.free()
	FileAccess.open("user://far-grass-lod.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("FAR_GRASS_LOD checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

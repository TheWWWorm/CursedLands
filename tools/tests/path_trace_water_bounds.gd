extends "res://tools/tests/path_trace_transmission_live.gd"
## Hold the real campaign water and transport fixed, then move the bounded
## scene away. Distant water must converge to its ordinary raster background,
## rather than use rays whose underwater terrain was omitted from the scene.
func error_at(a: Image,b: Image,points: Array[Vector2i]) -> float:
	var error:=0.0
	for p in points:
		var x:=a.get_pixelv(p);var y:=b.get_pixelv(p)
		error+=absf(x.r-y.r)+absf(x.g-y.g)+absf(x.b-y.b)
	return error/maxi(points.size()*3,1)

func coverage_error(centre: Vector3,eye: Vector3,points: Array[Vector2i],label := "") -> float:
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(centre.x,centre.y,centre.z,0))
	RenderingServer.global_shader_parameter_set(&"ei_rt_eye",eye)
	RenderingServer.global_shader_parameter_set(&"ei_pt_trans_active",0.0)
	await frames(3);await RenderingServer.frame_post_draw
	var ordinary:=get_viewport().get_texture().get_image()
	RenderingServer.global_shader_parameter_set(&"ei_pt_trans_active",1.0)
	await frames(3);await RenderingServer.frame_post_draw
	var traced:=get_viewport().get_texture().get_image()
	if not label.is_empty():traced.save_png(out.path_join(label+".png"))
	return error_at(traced,ordinary,points)

func coverage_handoff(centre: Vector3,near_image: Image,near_error: float,points: Array[Vector2i]) -> void:
	var eye:=camera.get_camera_transform().origin
	# Exercise the real water composition with the controller's actual eye
	# and snapshot uniforms. Hold its camera projection and transport textures
	# fixed so reprojection noise and a changed background cannot hide a jump.
	# A completed travel snapshot changes centre by sixteen metres in one
	# frame, unlike the small spatial steps used by the safety-bound test.
	var far_eye:=eye+Vector3.UP*64.0
	var old_error:=await coverage_error(far_eye-Vector3.UP*16.0,far_eye,points,"handoff-before")
	var new_error:=await coverage_error(far_eye,far_eye,points,"handoff-after")
	check(absf(new_error-old_error)<.003,"sixteen-metre snapshot promotion does not pop distant water: %.6f"%absf(new_error-old_error))
	check(maxf(old_error,new_error)<.003,"distant water uses ordinary transparency on both sides of the handoff")
	# The eye changes continuously during traversal, while a retained scene's
	# centre stays fixed between promotions. Every sample uses the unchanged
	# authored water shader and matching transmission; only coverage moves.
	var values:=[];var previous:=near_error;var maximum_step:=0.0;var blended:=false
	for rise in range(0,49):
		var label:="eye-%d"%rise if rise in [32,48] else ""
		var error:=await coverage_error(centre,eye+Vector3.UP*rise,points,label)
		values.append({"rise":rise,"error":error})
		maximum_step=maxf(maximum_step,absf(error-previous));previous=error
		blended=blended or (error>near_error*.15 and error<near_error*.85)
	check(blended,"continuous eye travel blends refraction before leaving its supported range")
	check(previous<.003,"continuous eye travel reaches ordinary distant transparency: %.6f"%previous)
	check(maximum_step<near_error*.2,"one-metre eye steps retain continuous water colour: %.6f"%maximum_step)
	await coverage_error(centre,eye,points)
	await RenderingServer.frame_post_draw
	check(error_at(get_viewport().get_texture().get_image(),near_image,points)<.003,"returning the eye restores nearby refraction")
	rows.append({"case":"snapshot-handoff-and-eye-travel","handoff_before_error":old_error,
		"handoff_after_error":new_error,"maximum_eye_step":maximum_step,"eye_values":values})

func run() -> void:
	GameData.options.merge({"pt_mode":1,"pt_refraction":1,"pt_accumulation":0,"q_rt_lighting":0,"pt_restir":0,"pt_target_fps":0,"pt_ray_reconstruction":0,"rtx_upscaling":0},true)
	var context:=await setup();Engine.max_fps=30
	var rt: Node=context[1].get_node("SceneRaytrace")
	check(await ready_transport(rt),"campaign water transport is ready")
	if rt.device==null or not rt.device.transmission.active:await finish_transport(context,rt);return
	await frames(20);rt.set_process(false)
	var centre: Vector3=rt._center
	RenderingServer.global_shader_parameter_set(&"ei_pt_trans_active",0.0)
	await frames(4);var ordinary:=await capture("ordinary")
	RenderingServer.global_shader_parameter_set(&"ei_pt_trans_active",1.0)
	await frames(4);var near_image:=await capture("near")
	var points: Array[Vector2i]=[]
	for y in range(0,ordinary.get_height(),2):
		for x in range(0,ordinary.get_width(),2):
			var a:=ordinary.get_pixel(x,y);var b:=near_image.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.03:points.append(Vector2i(x,y))
	check(points.size()>100,"visible water exercises real refraction")
	var near_error:=error_at(near_image,ordinary,points)
	var values:=[];var maximum_step:=0.0;var previous:=near_error;var blended:=false
	for rise in range(40,91,2):
		RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(centre.x,centre.y+rise,centre.z,0))
		# The same bound also changes opaque bed lighting. Compare transport
		# On/Off at this bound, not with the differently lit initial frame.
		RenderingServer.global_shader_parameter_set(&"ei_pt_trans_active",0.0)
		await frames(3);await RenderingServer.frame_post_draw
		var reference:=get_viewport().get_texture().get_image()
		RenderingServer.global_shader_parameter_set(&"ei_pt_trans_active",1.0)
		await frames(3);await RenderingServer.frame_post_draw
		var current:=get_viewport().get_texture().get_image()
		var error:=error_at(current,reference,points)
		values.append({"rise":rise,"error":error})
		maximum_step=maxf(maximum_step,absf(error-previous));previous=error
		blended=blended or (error>near_error*.15 and error<near_error*.85)
		if rise in [40,60,66,72,90]:current.save_png(out.path_join("rise-%d.png"%rise))
	check(previous<.003,"outside the bounded scene water matches ordinary transparency: %.6f"%previous)
	check(blended,"water blends through the boundary instead of switching abruptly")
	check(maximum_step<near_error*.4,"small scene moves retain continuous water colour: %.6f"%maximum_step)
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(centre.x,centre.y,centre.z,0))
	await frames(4)
	var restored:=await capture("restored")
	check(error_at(restored,near_image,points)<.003,"nearby water retains its traced appearance")
	rows.append({"pixels":points.size(),"near_error":near_error,"maximum_step":maximum_step,"values":values})
	await coverage_handoff(centre,near_image,near_error,points)
	FileAccess.open(out.path_join("water-bounds.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":rows},"\t"))
	rt.set_process(true)
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PT_WATER_BOUNDS ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)

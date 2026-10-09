extends "camera_depth_of_field_render.gd"
## Frozen native near-only / near+far comparators across the guard patch.
## Each screenshot must be pixel-identical between the old and new runtimes.
var reference_directory:=""

func compare_capture(name: String) -> void:
	var capture:=await picture(name)
	if reference_directory.is_empty():return
	var reference:=Image.load_from_file(reference_directory.path_join("dof-"+name+".png"))
	check(reference!=null,"reference image exists: "+name)
	if reference==null:return
	capture.convert(Image.FORMAT_RGBA8);reference.convert(Image.FORMAT_RGBA8)
	check(capture.get_data()==reference.get_data(),"legacy native pixels unchanged: "+name)

func _ready() -> void:
	if DisplayServer.get_name()=="headless":
		print("CAMERA_DOF_LEGACY requires a rendered run");get_tree().quit(1);return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dof-reference="):reference_directory=arg.trim_prefix("--dof-reference=")
	setup();aim(25)
	print("DOF_NATIVE_GUARD ",OS.has_feature("ei_far_dof_guard"))
	await compare_capture("legacy-off")
	for shape in [RenderingServer.DOF_BOKEH_BOX,RenderingServer.DOF_BOKEH_HEXAGON,RenderingServer.DOF_BOKEH_CIRCLE]:
		for quality in [RenderingServer.DOF_BLUR_QUALITY_LOW,RenderingServer.DOF_BLUR_QUALITY_MEDIUM]:
			RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(shape)
			RenderingServer.camera_attributes_set_dof_blur_quality(quality,false)
			for far_enabled in [false,true]:
				var attributes:=CameraAttributesPractical.new()
				attributes.dof_blur_near_enabled=true
				attributes.dof_blur_near_distance=18
				attributes.dof_blur_near_transition=4
				attributes.dof_blur_far_enabled=far_enabled
				attributes.dof_blur_far_distance=40
				attributes.dof_blur_far_transition=80
				attributes.dof_blur_amount=0.027
				camera.attributes=attributes
				await compare_capture("legacy-%d-%d-%s"%[shape,quality,"near-far" if far_enabled else "near"])
	camera.attributes=null;viewport.queue_free();await frames(2)
	print("CAMERA_DOF_LEGACY %d checks %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)

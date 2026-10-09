extends Node
## Deterministic foreground/focus/far-field/Canvas separation, all real pixels.
var checks:=0
var failures:=0
var viewport: SubViewport
var camera: Camera3D
var fx: CameraDepthOfField
var boards: Array[MeshInstance3D]=[]
const SIZE:=Vector2i(1280,720)

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("%s %s"%["PASS" if ok else "FAIL",label])

func frames(n:=5) -> void:
	for i in n: await get_tree().process_frame

func picture(name: String) -> Image:
	await frames()
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	check(image.save_png("user://dof-"+name+".png")==OK,"capture "+name)
	return image

func region(image: Image,rect: Rect2) -> PackedByteArray:
	return image.get_region(Rect2i(Vector2(SIZE)*rect.position,Vector2(SIZE)*rect.size)).get_data()

func board(rect: Rect2,depth: float,colours: Vector2i,stripes:=false) -> void:
	var mesh:=MeshInstance3D.new();mesh.mesh=QuadMesh.new()
	var extent:=tan(deg_to_rad(camera.fov)*0.5)*depth
	mesh.mesh.size=Vector2(extent*2.0*float(SIZE.x)/SIZE.y,extent*2.0)*rect.size
	var centre:=rect.get_center()
	mesh.set_meta("local_at",Vector3((centre.x-0.5)*extent*2.0*float(SIZE.x)/SIZE.y,(0.5-centre.y)*extent*2.0,-depth))
	var shader:=Shader.new()
	shader.code="shader_type spatial; render_mode unshaded, fog_disabled, cull_disabled; uniform bool stripes=false; uniform vec3 a; uniform vec3 b; void fragment(){ ALBEDO = stripes && fract(UV.x*320.0)>0.5 ? b : a; }"
	var material:=ShaderMaterial.new();material.shader=shader
	var palette:=[Color(0.03,0.03,0.03),Color(0.8,0.8,0.8),Color(1,0,0),Color(0,1,0),Color(0,0,1)]
	material.set_shader_parameter("a",Vector3(palette[colours.x].r,palette[colours.x].g,palette[colours.x].b))
	material.set_shader_parameter("b",Vector3(palette[colours.y].r,palette[colours.y].g,palette[colours.y].b))
	material.set_shader_parameter("stripes",stripes)
	mesh.material_override=material;viewport.add_child(mesh);boards.append(mesh)

func aim(pitch: float) -> Vector3:
	camera.global_transform=Transform3D(Basis.from_euler(Vector3(-deg_to_rad(pitch),0,0)),Vector3(0,20,0))
	for mesh in boards: mesh.global_transform=camera.global_transform*Transform3D(Basis.IDENTITY,mesh.get_meta("local_at"))
	return camera.global_position-camera.global_basis.z*20.0

func setup() -> void:
	viewport=SubViewport.new();viewport.size=SIZE;viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(0,0.5,0.6)
	viewport.add_child(environment)
	camera=Camera3D.new();camera.fov=55;camera.far=1000;viewport.add_child(camera);camera.make_current()
	board(Rect2(0.03,0.24,0.94,0.35),160,Vector2i(3,4),true)
	board(Rect2(0.03,0.65,0.94,0.30),20,Vector2i(0,1),true)
	board(Rect2(0.28,0.20,0.08,0.52),12,Vector2i(2,2))
	var ui:=CanvasLayer.new();viewport.add_child(ui)
	var panel:=ColorRect.new();panel.position=Vector2(20,20);panel.size=Vector2(440,90);ui.add_child(panel)
	var ui_shader:=Shader.new();ui_shader.code="shader_type canvas_item; void fragment(){ COLOR=mod(floor(FRAGCOORD.x/2.0)+floor(FRAGCOORD.y/2.0),2.0)>0.5 ? vec4(1,0.1,1,1) : vec4(1,1,0.1,1); }"
	panel.material=ShaderMaterial.new();panel.material.shader=ui_shader
	fx=CameraDepthOfField.new();add_child(fx);fx.set_process(false)

func _ready() -> void:
	if DisplayServer.get_name()=="headless":
		print("CAMERA_DOF_RENDER requires a rendered run");get_tree().quit(1);return
	print("DOF_KERNEL quality=",ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_bokeh_quality")," shape=",ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_bokeh_shape"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dof-quality="):
			var quality:=int(arg.get_slice("=",1))
			RenderingServer.camera_attributes_set_dof_blur_quality(quality,false)
			print("DOF_TEST_QUALITY override=",quality)
	setup()
	# Actual dialogue font and translucent HUD background over focused detail.
	var text_layer:=CanvasLayer.new();viewport.add_child(text_layer)
	var backing:=ColorRect.new();backing.position=Vector2(610,510);backing.size=Vector2(560,150);backing.color=Color(0,0,0,0.7);text_layer.add_child(backing)
	var words:=Control.new();words.position=backing.position;words.size=backing.size;text_layer.add_child(words)
	words.draw.connect(func():
		words.draw_string(DialogPanel.font(),Vector2(8,42),"Magician here - no one at all, in fact.",HORIZONTAL_ALIGNMENT_LEFT,-1,24,DialogPanel.TEXT_COLOR)
		words.draw_string(DialogPanel.font(),Vector2(8,82),"Maybe you wish to fight me? Old Dragon",HORIZONTAL_ALIGNMENT_LEFT,-1,24,DialogPanel.TEXT_COLOR))
	var target:=aim(25)
	print("DOF_NATIVE_GUARD ",OS.has_feature("ei_far_dof_guard"))
	fx.update(camera,target,0.1,false)
	var before:=await picture("low-off")
	fx.update(camera,target,0.1,true)
	var after:=await picture("low-on")
	check(region(before,Rect2(0.025,0.035,0.32,0.1))==region(after,Rect2(0.025,0.035,0.32,0.1)),"Canvas UI pixels remain exact")
	check(region(before,Rect2(0.29,0.25,0.06,0.4))==region(after,Rect2(0.29,0.25,0.06,0.4)),"foreground interior stays exact")
	check(region(before,Rect2(0.46,0.70,0.45,0.20))==region(after,Rect2(0.46,0.70,0.45,0.20)),"focused detail and translucent dialogue-font UI remain exact")
	check(region(before,Rect2(0.5,0.05,0.45,0.1))==region(after,Rect2(0.5,0.05,0.45,0.1)),"sky away from horizon keeps exact pixels")
	var far_before:=region(before,Rect2(0.5,0.30,0.4,0.2))
	var far_after:=region(after,Rect2(0.5,0.30,0.4,0.2))
	var changed:=0;var error:=0
	for i in far_before.size():
		changed+=int(far_before[i]!=far_after[i]);error+=absi(int(far_before[i])-int(far_after[i]))
	print("DOF_FAR_DELTA changed=",changed," absolute=",error)
	check(changed>100 if CameraDepthOfField.supported() else changed==0,"supported low view blurs far detail; unsupported runtimes stay unchanged")
	var bleed:=0.0
	for x in range(461,470):
		for y in range(240,370): bleed=maxf(bleed,after.get_pixel(x,y).r-before.get_pixel(x,y).r)
	print("DOF_EDGE distant_red_bleed=",bleed)
	check(bleed==0.0,"foreground colour does not make a distant halo")
	check(before.get_region(Rect2i(358,180,103,230)).get_data()==after.get_region(Rect2i(358,180,103,230)).get_data(),"foreground silhouette edge remains exact")
	check(before.get_region(Rect2i(640,162,400,11)).get_data()==after.get_region(Rect2i(640,162,400,11)).get_data(),"sky at terrain horizon remains exact")
	fx.update(camera,target,0.1,false)
	var restored:=await picture("low-restored")
	check(before.get_data()==restored.get_data() and camera.attributes==null,"switching off restores exact image and attributes")
	target=aim(60)
	var tactical_before:=await picture("tactical-off")
	fx.update(camera,target,0.1,true)
	var tactical_after:=await picture("tactical-on")
	check(tactical_before.get_data()==tactical_after.get_data() and camera.attributes==null,"tactical view is exactly unchanged when option is enabled")
	# A new target settles smoothly at low pitch. Camera scale changes rederive
	# the radius; they cannot leave an inherited viewport effect behind.
	target=aim(25);fx.update(camera,target,0.1,true)
	if CameraDepthOfField.supported():
		var amount: float=camera.attributes.dof_blur_amount
		viewport.scaling_3d_scale=0.75;fx.update(camera,target,0.1,true)
		check(is_equal_approx(camera.attributes.dof_blur_amount,amount*0.75),"render scale recalculates blur radius")
	else:check(fx._attributes==null,"unsupported runtime retains no effect allocation")
	fx.clear();viewport.queue_free();await frames(2)
	print("CAMERA_DOF_RENDER %d checks %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)

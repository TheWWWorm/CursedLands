extends "res://tools/tests/scene_raytrace_device.gd"
## The same visible surface and traced illumination must not change colour
## when a neighbouring acceleration snapshot is published. Its real geometry
## bound remains mandatory, as do the existing surface/occlusion checks.
var rows: Array[Dictionary]=[]

func centre_colour() -> Color:
	await frames(4);await RenderingServer.frame_post_draw
	var im:=get_viewport().get_texture().get_image();var sum:=Color(0,0,0,0)
	for y in range(im.get_height()/2-4,im.get_height()/2+5):
		for x in range(im.get_width()/2-4,im.get_width()/2+5):sum+=im.get_pixel(x,y)
	return sum/81.0

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Gfx.ensure_globals();GameData.options.merge({"pt_mode":1,"rtx_upscaling":0,"fsr_upscaling":0,"q_aa":0,"render_scale":4,"gfx_cloud_shadows":0},true)
	GameData.resolution_size="1280x720";GameData.options.display_mode=0
	GameData.options.resolution=GameData.resolutions().find(Vector2i(1280,720));GameData._apply_window()
	await frames(12);GameData._window_gen+=1;get_window().borderless=true;get_window().size=Vector2i(1280,720)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color.BLACK;env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;add_child(env)
	camera=Camera3D.new();add_child(camera);camera.position=Vector3(0,0,12);camera.current=true;camera.fov=55
	var mesh:=QuadMesh.new();mesh.size=Vector2(20,20)
	var mat:=ShaderMaterial.new();mat.shader=Gfx.make_shader("""
shader_type spatial;
render_mode cull_disabled,ambient_light_disabled,fog_disabled;
varying vec3 ei_e;
varying float ei_k;
void vertex() {ei_e=vec3(0.0);ei_k=0.0;}
void fragment() {ALBEDO=vec3(1.0);ROUGHNESS=1.0;SPECULAR=0.0;}
""",true,true)
	var object:=MeshInstance3D.new();object.mesh=mesh;object.material_override=mat;add_child(object)
	RenderingServer.global_shader_parameter_set(&"ei_ambient",Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_sun",Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(500,1000,0))
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(1,1,1,72))
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",1.0)
	RenderingServer.global_shader_parameter_set(&"ei_pt_rr_active",0.0)
	var extent:=Vector2i(640,360)
	var light_image:=Image.create(extent.x,extent.y,false,Image.FORMAT_RGBAH);light_image.fill(Color(.02,.4,.04,1))
	var light:=ImageTexture.create_from_image(light_image)
	var dark_image:=Image.create(extent.x,extent.y,false,Image.FORMAT_RGBAH);dark_image.fill(Color(0,0,0,63))
	var dark:=ImageTexture.create_from_image(dark_image)
	var guide_image:=Image.create(extent.x,extent.y,false,Image.FORMAT_RGBAH);guide_image.fill(Color(0,0,1,12))
	var guide:=ImageTexture.create_from_image(guide_image)
	RenderingServer.global_shader_parameter_set(&"ei_rt_guide",guide)
	RenderingServer.global_shader_parameter_set(&"ei_rt_gi",light)
	for key in [&"ei_rt_shadow0",&"ei_rt_shadow1",&"ei_pt_direct_sun"]:RenderingServer.global_shader_parameter_set(key,dark)
	var view:=Projection(camera.global_transform.affine_inverse());var vp:=camera.get_camera_projection()*view
	for pair in [[&"ei_rt_view_projection",vp],[&"ei_rt_inverse_view_projection",vp.inverse()],[&"ei_rt_view",view],[&"ei_rt_eye",camera.position]]:
		RenderingServer.global_shader_parameter_set(pair[0],pair[1])
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(0,0,0,96))
	var reference:=await centre_colour()
	check(reference.g>.3 and reference.g>reference.r*2,"real material composition visibly consumes the traced green illumination")
	for shift in [48,64,80]:
		RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(shift,0,0,96))
		var colour:=await centre_colour();var error:=absf(colour.g-reference.g)
		check(error<.003,"snapshot centre %d preserves unchanged near-surface illumination (%.6f)"%[shift,error])
		rows.append({"centre_x":shift,"green":colour.g,"error":error})
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(110,0,0,96))
	check((await centre_colour()).g<reference.g*.05,"outside retained geometry still rejects incomplete trace coverage")
	RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(0,0,0,96))
	guide_image.fill(Color(0,0,1,8));guide.update(guide_image)
	check((await centre_colour()).g<reference.g*.05,"a nearer unrelated traced surface cannot supply the receiver")
	FileAccess.open("user://pt-coverage-handoff.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO);RenderingServer.global_shader_parameter_set(&"ei_pt_active",0.0)
	for key in [&"ei_rt_guide",&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1",&"ei_pt_direct_sun"]:RenderingServer.global_shader_parameter_set(key,null)
	object.queue_free();camera.queue_free();await frames(4);finish()

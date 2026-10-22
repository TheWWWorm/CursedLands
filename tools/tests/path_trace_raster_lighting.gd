extends "res://tools/tests/scene_raytrace_device.gd"
## Compare actual raster pixels with a saved receiver implementation. Cover
## full PT, its radius fade, rejected guides, ordinary RT and raster fallback.
const Receiver = preload("res://src/game/fx/scene_raytrace_shader.gd")
const SOURCE := """shader_type spatial;
render_mode cull_disabled,ambient_light_disabled;
const vec3 ei_ambient=vec3(0),ei_material_diffuse=vec3(1),ei_e=vec3(0),ei_sun=vec3(1),ei_sun_dir=vec3(0,0,1),ei_surface=vec3(0);
const float ei_k=0.0,ei_leaf=0.0;
varying vec3 ei_vpos;
vec3 ei_lin(vec3 c){return c;}
vec3 ei_srgb(vec3 c){return c;}
void fragment() {ALBEDO=vec3(0.4);ei_vpos=VERTEX;}
void light() {DIFFUSE_LIGHT+=vec3(0.25);SPECULAR_LIGHT+=vec3(0.125);}
"""
var results := []

func centre(image: Image) -> Color:
	var total:=Color(0,0,0,0)
	for y in range(350,370):
		for x in range(630,650):total+=image.get_pixel(x,y)
	return total/400.0

func run() -> void:
	var reference_path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg.begins_with("--receiver-reference="):reference_path=arg.trim_prefix("--receiver-reference=")
	DirAccess.make_dir_recursive_absolute(out)
	var reference: Script=load(reference_path)
	check(reference!=null,"load saved receiver implementation")
	if reference==null:finish();return
	get_window().size=Vector2i(1280,720);get_window().borderless=true;Gfx.ensure_globals()
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=8;camera.position=Vector3(0,0,12);camera.current=true
	var object:=MeshInstance3D.new();object.mesh=QuadMesh.new();object.mesh.size=Vector2(8,8);add_child(object)
	var light:=DirectionalLight3D.new();add_child(light)
	var materials: Array[ShaderMaterial]=[]
	for implementation: Script in [reference,Receiver]:
		var material:=ShaderMaterial.new();material.shader=Shader.new();material.shader.code=implementation.inject(SOURCE,false);materials.append(material)
	await frames(4)
	var view:=Projection(camera.global_transform.affine_inverse());var vp:=camera.get_camera_projection()*view
	RenderingServer.global_shader_parameter_set(&"ei_rt_inverse_view_projection",vp.inverse())
	RenderingServer.global_shader_parameter_set(&"ei_rt_view_projection",vp)
	RenderingServer.global_shader_parameter_set(&"ei_rt_view",view)
	RenderingServer.global_shader_parameter_set(&"ei_rt_eye",camera.position)
	var textures: Array[ImageTexture]=[]
	for colour: Color in [Color(0,0,1,12),Color(0.2,0.3,0.4,1),Color(0.03,0.04,0.05,1),Color(0.7,0.6,0.5,1)]:
		var image:=Image.create(1280,720,false,Image.FORMAT_RGBAF);image.fill(colour);textures.append(ImageTexture.create_from_image(image))
	var names:=[&"ei_rt_guide",&"ei_rt_gi",&"ei_rt_shadow0",&"ei_rt_shadow1"]
	for i in 4:RenderingServer.global_shader_parameter_set(names[i],textures[i])
	for test: Array in [["full-pt",1.0,0.0,12.0,1.0],["pt-fade",1.0,66.0,12.0,1.0],
		["outside-radius",1.0,80.0,12.0,1.0],["depth-mismatch",1.0,0.0,10.0,1.0],
		["ordinary-rt",0.0,0.0,12.0,1.0],["disabled",0.0,0.0,12.0,0.0]]:
		RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(test[4],1,1,72))
		RenderingServer.global_shader_parameter_set(&"ei_pt_active",test[1])
		RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(test[2],0,0,0))
		var image:=textures[0].get_image();image.fill(Color(0,0,1,test[3]));textures[0].update(image)
		var captures: Array[Image]=[]
		for material: ShaderMaterial in materials:
			object.material_override=material;await frames(12);await RenderingServer.frame_post_draw
			captures.append(get_viewport().get_texture().get_image())
		var a:=centre(captures[0]);var b:=centre(captures[1]);var error:=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
		check(error<=1.0/255.0,"saved/current raster lighting agrees: "+test[0])
		check(b.r>0.05 and b.g>0.05 and b.b>0.05,"receiver produces visible lighting: "+test[0])
		results.append({"case":test[0],"reference":[a.r,a.g,a.b],"current":[b.r,b.g,b.b],"max_error":error})
		captures[1].save_png(out.path_join(test[0]+".png"))
	check(absf(results[0].current[0]-results[5].current[0])>0.05,"PT and conventional controls have distinct lighting")
	check(absf(results[1].current[0]-results[0].current[0])>0.01,"radius fade actually exercises mixed lighting")
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	for key in names:RenderingServer.global_shader_parameter_set(key,null)
	FileAccess.open(out.path_join("path-raster-lighting.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results,"reference_sha256":FileAccess.get_sha256(reference_path)},"\t"))
	object.queue_free();light.queue_free();camera.queue_free();await frames(8);finish()

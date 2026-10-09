extends "water_interaction.gd"
## Probe the production contact-light function through the production shader
## composer. A uniform cloud shadow must match reducing only the original sun.
var view: SubViewport

func capture(label: String) -> Image:
	await frames(10); await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	image.save_png("user://cloud-contact-"+label+".png")
	return image

func shadow(strength: float) -> void:
	RenderingServer.global_shader_parameter_set(&"ei_cloud_state",Vector4(0.5,strength,160,1))

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"gfx_clouds":1,"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":3},true)
	Gfx.ensure_globals(); Gfx.apply_surface_options()
	Engine.time_scale=0; Engine.max_fps=120; process_mode=Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	view=SubViewport.new(); view.size=Vector2i(64,64); view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.position=Vector3(0,0,2); camera.current=true
	var mesh := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size=Vector2(4,4); mesh.mesh=quad; view.add_child(mesh)
	var source := "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvarying vec3 ei_e;\nvarying float ei_k;\n"
	source+=GroundContactShader.FUNCTIONS.get_slice("vec3 contact_vertex_normal",0)
	source+="\nvoid vertex() { ei_e=vec3(0.0); ei_k=1.0; }\nvoid fragment() { vec3 d; vec3 s; contact_light(vec3(0.0),vec3(0.0,1.0,0.0),d,s); ALBEDO=ei_lin(d); }\n"
	var material := ShaderMaterial.new(); material.shader=Gfx.make_shader(source,true,true); mesh.material_override=material
	var white := Image.create(4,4,true,Image.FORMAT_R8); white.fill(Color.WHITE); white.generate_mipmaps()
	var white_texture := ImageTexture.create_from_image(white)
	RenderingServer.global_shader_parameter_set(&"ei_cloud_noise",white_texture)
	RenderingServer.global_shader_parameter_set(&"ei_cloud_phases",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",Vector3.UP)
	var sun := Color(0.8,0.7,0.6); var ambient := Color(0.1,0.1,0.1)
	Gfx.set_light(ambient,sun); shadow(0.0); await frames(60)
	var off := await capture("sun-off")
	shadow(0.28); var on := await capture("sun-on")
	shadow(0.0); Gfx.set_light(ambient,Color(sun.r*0.72,sun.g*0.72,sun.b*0.72))
	var expected := await capture("sun-reference")
	check(difference(off,expected).peak_delta>10,"independent reduced-sun reference changes actual probe pixels")
	check(difference(on,expected).changed_pixels==0,"contact band shares exact terrain cloud attenuation before native byte packing")
	Gfx.set_light(ambient,sun); shadow(0.0)
	check(difference(off,await capture("night-clear")).changed_pixels==0,"zero night shadow restores exact contact sunlight")
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",Vector3.ZERO)
	var no_sun := await capture("ambient-off"); shadow(0.28)
	check(difference(no_sun,await capture("ambient-on")).changed_pixels==0,"contact cloud shading leaves ambient exact")
	RenderingServer.global_shader_parameter_set(&"ei_pl0",Vector4(0,3,0,10))
	RenderingServer.global_shader_parameter_set(&"ei_plc0",Vector4(0.9,0.5,0.2,0))
	var local_on := await capture("local-on"); shadow(0.0)
	check(difference(local_on,await capture("local-off")).changed_pixels==0,"contact cloud shading leaves wrapped local light exact")
	rows.append({"renderer":RenderingServer.get_current_rendering_method(),"old_to_shadow":difference(off,on),"shadow_to_reference":difference(on,expected)})
	view.free(); Gfx.clear_clouds(); TexUpscale.shutdown(); UnitWounds.shutdown(); await frames(12)
	FileAccess.open("user://cloud-contact.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("CLOUD_CONTACT checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)

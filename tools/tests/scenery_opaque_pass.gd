extends "ground_contact.gd"
## A screen-reading surface must see solid scenery in the opaque scene copy.
## Exercise real pixels, including cutouts, contact variants and camera fades.
func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"gfx_ground_contact":1},true)
	Gfx.ensure_globals(); Gfx.apply_surface_options()
	for i in 24: await get_tree().process_frame
	var view := SubViewport.new(); view.size = Vector2i(SIZE,SIZE); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color.MAGENTA
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR; view.add_child(env)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 2
	camera.near = 0.01; camera.far = 100; view.add_child(camera)
	camera.position = Vector3(16,1,-12); camera.look_at(Vector3(16,1,-16)); camera.current = true
	var sun := DirectionalLight3D.new(); sun.light_specular = Gfx.SUN_MARK; view.add_child(sun)
	Gfx.set_light(Color.WHITE,Color.BLACK)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,200,0))
	var terrain := terrain_fixture(); view.add_child(terrain)
	var owner := owner_fixture(terrain)
	var base := base_material()
	var wall := object_fixture(terrain,base); owner.register(wall.get_parent())
	var contact := wall.material_override as ShaderMaterial
	var cutout := Image.create(8,8,false,Image.FORMAT_RGBA8)
	cutout.fill(Color(0.7,0.05,0.03,1)); cutout.fill_rect(Rect2i(2,0,3,8),Color.TRANSPARENT)
	var cutout_texture := ImageTexture.create_from_image(cutout)
	base.set_shader_parameter("albedo_tex",cutout_texture); contact.set_shader_parameter("albedo_tex",cutout_texture)
	var copy := object_fixture(terrain,null); copy.position.z += 1
	var sample := ShaderMaterial.new(); sample.shader = Shader.new()
	sample.shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D scene : hint_screen_texture, filter_nearest;
void fragment() { ALBEDO=textureLod(scene,SCREEN_UV,0.0).rgb; }
"""
	copy.material_override = sample
	var fade := CameraFade._dither_material(contact)
	for msaa in [Viewport.MSAA_DISABLED,Viewport.MSAA_4X]:
		view.msaa_3d = msaa
		for material: ShaderMaterial in [base,contact,fade]:
			wall.material_override = material
			copy.hide(); var direct := await capture(view)
			copy.show(); var refracted := await capture(view)
			var difference := compare(direct,refracted,Rect2i(4,4,248,248))
			check(difference.peak <= 2.0/255.0,"solid scenery is present in screen copy: "+str([msaa,material==contact,material==fade,difference]))
			var surface := refracted.get_pixel(24,96); var hole := refracted.get_pixel(112,96)
			check(surface.r>0.6 and surface.g<0.1 and surface.b<0.1,"screen copy contains the object colour")
			check(hole.r>0.95 and hole.b>0.95 and hole.g<0.05,"alpha cutout remains open")
		# The explicitly smoothed tree variant retains its original alpha pass.
		var tree := base.duplicate() as ShaderMaterial
		tree.shader = Gfx.make_shader(EIFigure.OBJECT_A2C_SHADER)
		wall.material_override = tree
		var leaf := await capture(view)
		var pixel := leaf.get_pixel(24,96)
		check(pixel.r>0.95 and pixel.b>0.95,"tree atlas keeps its separate smoothed edge pass")
	# Early alpha rejection must match the original final scissor test,
	# including filtered edge pixels and derivatives used by relief/contact.
	copy.hide()
	GameData.options["gfx_materials"] = 1
	GameData.options["gfx_foliage_light"] = 1
	Gfx.apply_surface_options()
	Gfx.set_light(Color(0.2,0.2,0.2),Color(0.8,0.8,0.8))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",Vector3(0.5,0.7,0.5).normalized())
	var gradient := Image.create(16,16,false,Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			gradient.set_pixel(x,y,Color(float(y%3)/2.0,float(x%5)/4.0,float((x+y)%7)/6.0,float(x)/15.0))
	var edge_texture := ImageTexture.create_from_image(gradient)
	var foliage := base_material(true)
	foliage.set_shader_parameter("foliage_mask",texture(Color(0.5,1.0,0.0)))
	var plant := object_fixture(terrain,foliage); owner.register(plant.get_parent())
	var foliage_contact := plant.material_override as ShaderMaterial
	plant.get_parent().hide()
	var tree := base.duplicate() as ShaderMaterial
	tree.shader = Gfx.make_shader(EIFigure.OBJECT_A2C_SHADER)
	for msaa in [Viewport.MSAA_DISABLED,Viewport.MSAA_4X]:
		view.msaa_3d = msaa
		for material: ShaderMaterial in [base,contact,fade,foliage,foliage_contact,tree]:
			material.set_shader_parameter("albedo_tex",edge_texture)
			material.set_shader_parameter("surface_profile",Vector4(0.1,0.7,0.0,0.8))
			wall.material_override = material
			wall.set_instance_shader_parameter("cam_fade",0.375 if material==fade else 0.0)
			var optimized := material.shader.code
			var early := "if (ALPHA < 0.5) { discard; }"
			check(optimized.contains(early),"cutout variant has early rejection")
			material.shader.code = optimized.replace(early,"")
			var before := await capture(view)
			material.shader.code = optimized
			var after := await capture(view)
			var difference := compare(before,after,Rect2i(0,0,SIZE,SIZE))
			check(difference.peak<=1.0/255.0,"early cutouts retain rendered edges: "+str([msaa,material==contact,material==foliage_contact,difference]))
	view.free(); await get_tree().process_frame
	print("SCENERY_OPAQUE_PASS ",checks," checks; failures=",failures)
	TexUpscale.shutdown(); get_tree().quit(int(failures>0))

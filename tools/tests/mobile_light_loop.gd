extends Node
## Render the production Mobile light loops against the expanded reference.
## Vary light membership, normals and materials; compare GPU pixels, including
## the overflow and no-sun paths. A parser-only run cannot qualify this change.
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func frames(count := 12) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func difference(a: Image, b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var peak := 0; var changed := 0; var over := 0
	for i in range(0, aa.size(), 4):
		var d := maxi(absi(aa[i]-bb[i]), maxi(absi(aa[i+1]-bb[i+1]), absi(aa[i+2]-bb[i+2])))
		peak = maxi(peak, d); changed += int(d > 0); over += int(d > 2)
	return {"peak":peak, "changed_pixels":changed, "pixels_over_2":over}

func _ready() -> void:
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		printerr("MOBILE_LIGHT_LOOP requires the Mobile renderer"); get_tree().quit(2); return
	GameData.options.merge(GfxPresets.values(GfxPresets.MEDIUM), true)
	GameData.options.merge({"gfx_cloud_shadows":0,"gfx_volumetric":0,"gfx_weather_surfaces":0}, true)
	Gfx.ensure_globals(); Gfx.set_foliage_wind(false); Gfx.apply_surface_options()
	var view := SubViewport.new(); view.size = Vector2i(384,256); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.position = Vector3(0,0,6); camera.current = true
	var environment := Environment.new(); Gfx.setup_original_env(environment)
	environment.background_mode = Environment.BG_COLOR; camera.environment = environment
	var sun := DirectionalLight3D.new(); view.add_child(sun); sun.light_specular = Gfx.SUN_MARK
	sun.rotation_degrees = Vector3(-25,30,0)
	var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32: image.set_pixel(x,y,Color(.12+x*.025,.18+y*.021,.25+float((x+y)%7)*.08,1.0))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	var sources := [EIFigure.OBJECT_SHADER, EIFigure.OBJECT_SHADER.replace("shader_type spatial;", "shader_type spatial;\n#define EI_TERRAIN_LIGHT"), EIFigure.FOLIAGE_SHADER]
	var materials: Array[ShaderMaterial] = []
	for i in sources.size():
		var draw := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size = Vector2(1.5,2.8)
		draw.mesh = quad; view.add_child(draw); draw.position.x = (i-1)*1.65
		draw.rotation_degrees = Vector3(7*i,-13*i,0)
		var material := ShaderMaterial.new(); draw.material_override = material; materials.append(material)
		material.set_shader_parameter("albedo_tex",texture); material.set_shader_parameter("foliage_mask",texture)
		material.set_shader_parameter("surface_profile",Vector4(.65,.35,.4,.45))
		material.set_shader_parameter("ei_material_emissive",Vector3(.03,.07,.02))
		material.set_shader_parameter("wind",0.0)
	var lights: Array[OmniLight3D] = []
	for i in 6:
		var light := OmniLight3D.new(); view.add_child(light); light.add_to_group(Gfx.POINT_LIGHT_GROUP)
		light.position = Vector3(-2.5+i, .25*(i%3-1), 1.2+.2*i); light.omni_range = 5.0
		light.omni_attenuation = 0.0; light.light_color = Color(.15+.13*i,.8-.1*i,.2+.07*i)
		if i%2 == 0: Gfx.mark_additive(light)
		lights.append(light)
	var spot := SpotLight3D.new(); view.add_child(spot); spot.position = Vector3(0,1,3); spot.visible = false
	spot.light_color = Color(.2,.4,.7); spot.spot_range = 8.0
	for state in ["sun","one","two","four","overflow","no-sun","move","colour","spot","local","local-srgb","shadow","original","restore"]:
		var count := 0 if state == "sun" else (1 if state == "one" else (2 if state == "two" else (4 if state == "four" else 6)))
		for i in lights.size(): lights[i].visible = i < count
		sun.visible = state != "no-sun"
		Gfx.set_sun_direction(sun.global_basis.z.normalized() if sun.visible else Vector3.ZERO)
		Gfx.set_light(Color(.18,.22,.2),Color(.55,.62,.57))
		if state == "move": lights[1].position += Vector3(2,1,-.5)
		if state == "colour": lights[2].light_color = Color(.9,.08,.13); lights[4].light_energy = .2
		spot.visible = state == "spot"
		if state in ["local","local-srgb"]: lights[5].light_specular = .023 if state == "local" else .025
		lights[0].shadow_enabled = state == "shadow"
		GameData.options.gfx_materials = 0 if state == "original" else 1
		Gfx.apply_surface_options(); Gfx.update_pass_lights(get_tree(),Vector3.ZERO,sun)
		var variants: Array = [[],[]]
		for compact in 2:
			Gfx._compact_mobile_lighting = bool(compact)
			for i in sources.size():
				var shader := Shader.new(); shader.code = Gfx.compose(sources[i],true,i == 1)
				check(not shader.get_shader_uniform_list().is_empty(),"shader parses "+state)
				check(shader.code.contains("uniform int ei_point_light_passes") == (compact == 1 and state != "original"),"intended loop variant "+state)
				variants[compact].append(shader)
		for i in materials.size(): materials[i].shader = variants[0][i]
		await frames(24)
		var before := view.get_texture().get_image()
		for i in materials.size(): materials[i].shader = variants[1][i]
		await frames(24)
		var after := view.get_texture().get_image()
		var delta := difference(before,after)
		check(delta.pixels_over_2 == 0,"GPU lighting preserved "+state)
		for i in materials.size(): materials[i].shader = variants[0][i]
		await frames()
		var repeat := difference(before,view.get_texture().get_image())
		check(repeat.changed_pixels == 0,"reference remains stable "+state)
		rows.append({"state":state,"candidate":delta,"reference_repeat":repeat})
		if state in ["overflow","no-sun","restore"]:
			before.save_png("user://mobile-light-loop-"+state+"-reference.png")
			after.save_png("user://mobile-light-loop-"+state+"-candidate.png")
	Gfx._compact_mobile_lighting = true; Gfx.clear_baked_pass_lights(); view.free()
	TexUpscale.shutdown(); UnitWounds.shutdown()
	FileAccess.open("user://mobile-light-loop.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("MOBILE_LIGHT_LOOP checks=",checks," failures=",failures)
	get_tree().quit(int(failures > 0))

extends Node
## Compare every live particle variant against the unspecialized shader on GPU.
## Also exercise option transitions and newly created material invalidation.
var checks := 0
var failures := 0
var rows := []
var changes := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func difference(a: Image, b: Image) -> Dictionary:
	var aa := a.get_data(); var bb := b.get_data(); var peak := 0; var over := 0
	for i in aa.size():
		var d := absi(aa[i] - bb[i]); peak = maxi(peak, d); over += int(d > 1)
	return {"peak":peak, "channels_over_1":over}

func original(key: int) -> Shader:
	var code := ParticleFx.EFFECT_SHADER.code
	if key & 1: code = code.replace("blend_mix", "blend_add")
	if key & 2: code = code.replace("depth_draw_never,", "depth_draw_never, depth_test_disabled,")
	if key & 6: code = ParticleFx.WaterReflection.screen_effect_source(code)
	var shader := Shader.new(); shader.code = code
	return shader

func _ready() -> void:
	Engine.max_fps = 120
	GameData.options.merge({"gfx_soft_particles":0,"gfx_lit_particles":0,"gfx_bloom":0,"gfx_firelight":0},true)
	Gfx.ensure_globals()
	var view := SubViewport.new(); view.size = Vector2i(128,128); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.position = Vector3(0,0,4); camera.current = true
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.04,.09,.15); camera.environment = env
	var wall := MeshInstance3D.new(); wall.mesh = BoxMesh.new(); view.add_child(wall)
	wall.position = Vector3(-.5,0,.1); wall.scale = Vector3(.6,3,.1)
	var opaque := StandardMaterial3D.new(); opaque.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	opaque.albedo_color = Color(.12,.31,.46); wall.material_override = opaque
	var image := Image.create(16,16,false,Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16: image.set_pixel(x,y,Color(.3+x/24.0,.8-y/30.0,.24,1.0-abs(x-7.5)/10.0))
	var texture := ImageTexture.create_from_image(image)
	var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true; multi.use_custom_data = true; multi.mesh = QuadMesh.new(); multi.instance_count = 1
	multi.custom_aabb = AABB(Vector3(-2,-2,-1),Vector3(4,4,2))
	multi.buffer = PackedFloat32Array([0,0,0,0, 0,0,1,1, .9,.8,.7,.8, .9,.8,.7,.8, 0,0,1,1])
	var draw := MultiMeshInstance3D.new(); draw.multimesh = multi; view.add_child(draw)
	var material := ShaderMaterial.new(); material.set_shader_parameter("tex",texture)
	material.set_shader_parameter("light_tint",Vector3(.8,.7,.6)); material.set_shader_parameter("boost",1.2)
	draw.material_override = material
	var ids := {}
	for key in 8:
		var shader := ParticleFx._shader(bool(key&1),bool(key&2),bool(key&4))
		ids[key] = shader.get_rid(); changes[key] = 0
		shader.changed.connect(func(): changes[key] += 1)
	for soft in [0,1,0]:
		GameData.options.gfx_soft_particles = soft
		ParticleFx._refresh_depth_shaders()
		var expected := 0 if rows.is_empty() else 1
		for key in 8:
			var shader: Shader = ParticleFx._shaders[key]
			check(changes[key] == (0 if key&2 else expected), "only depth-dependent source changes %d/%d"%[soft,key])
			check(shader.get_rid() == ids[key], "shader identity survives %d/%d"%[soft,key])
			changes[key] = 0
			material.set_shader_parameter("soft_distance",0.0 if key&2 else soft*.6)
			material.set_shader_parameter("through_alpha",.6 if key&2 else 0.0)
			material.shader = original(key); await frames(6)
			var reference := view.get_texture().get_image(); reference.convert(Image.FORMAT_RGBA8)
			multi.visible_instance_count = 0; await frames(2)
			var empty := view.get_texture().get_image(); empty.convert(Image.FORMAT_RGBA8)
			check(difference(reference, empty).channels_over_1 > 128, "fixture visibly draws particles %d/%d"%[soft,key])
			material.shader = shader; await frames(2)
			multi.visible_instance_count = 1; await frames(6)
			var actual := view.get_texture().get_image(); actual.convert(Image.FORMAT_RGBA8)
			var delta := difference(reference,actual)
			check(delta.channels_over_1 == 0, "GPU pixels preserve soft/through/additive/marker %d/%d"%[soft,key])
			rows.append({"soft":soft,"key":key,"delta":delta})
		for i in 10: ParticleFx._refresh_depth_shaders()
		check(changes.values().all(func(v):return v==0),"stable settings never recompile")
	# Exercise cache invalidation without a world: material creation is enough.
	var fx := ParticleFx.new()
	var smoke := fx._material("firesmoke",false,false,true)
	var fire := fx._material("firesmoke",true,true,false,true)
	var marker := fx._material("firesmoke",false,false,false,false,true,true)
	GameData.options.merge({"gfx_soft_particles":1,"gfx_lit_particles":1,"gfx_bloom":1,"gfx_firelight":1},true)
	Gfx.set_light(Color(.1,.2,.3),Color(.2,.1,.1))
	fx._apply_material_options()
	check(smoke.get_shader_parameter("soft_distance")==ParticleFx.SOFT_DISTANCE,"soft option reaches existing material")
	check(marker.get_shader_parameter("soft_distance")==0.0,"through marker retains separate depth behavior")
	check(smoke.get_shader_parameter("light_tint")==Vector3(.3,.3,.4),"scene tint reaches existing smoke")
	check(fire.get_shader_parameter("boost")==1.0,"firelight preserves painted fire core")
	var added := fx._material("firesmoke",true,true)
	fx._apply_material_options()
	check(added.get_shader_parameter("boost")==ParticleFx.GLOW_BOOST,"new material receives unchanged cached options")
	GameData.options.merge({"gfx_soft_particles":0,"gfx_lit_particles":0,"gfx_bloom":0,"gfx_firelight":0},true)
	fx._apply_material_options()
	check(smoke.get_shader_parameter("soft_distance")==0.0 and smoke.get_shader_parameter("light_tint")==Vector3.ONE,"disable options restores existing smoke")
	check(added.get_shader_parameter("boost")==1.0,"disable bloom restores existing glow")
	fx.free(); view.free(); TexUpscale.shutdown(); UnitWounds.shutdown()
	FileAccess.open("user://particle-shader-options.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("PARTICLE_SHADER_OPTIONS checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

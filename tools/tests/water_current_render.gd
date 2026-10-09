extends "water_current.gd"
## Real map appearance/clock controls, then isolated production shader helpers.

func clock_at(t: EITerrain,seconds: float,material: ShaderMaterial=null) -> void:
	t._waves=EIWaterWaves.new(); t._waves.advance(seconds); t._update_wave_parameters()
	if material:
		material.set_shader_parameter("wave_ticks",t._waves.time_ticks())
		material.set_shader_parameter("river_phase",t._water_mat.get_shader_parameter("river_phase"))

func diagnostic(t: EITerrain,body: String) -> ShaderMaterial:
	var source := t._water_mat.shader.code
	var start := source.find("void fragment() {")
	var end := source.find("{",start)+1; var depth := 1
	while end<source.length() and depth>0:
		if source[end]=="{": depth+=1
		if source[end]=="}": depth-=1
		end+=1
	source=source.substr(0,start)+"void fragment() {\n"+body+"\n}"+source.substr(end)
	source=source.replace("ambient_light_disabled","unshaded, fog_disabled")
	var shader := Shader.new(); shader.code=source
	var mat := ShaderMaterial.new(); mat.shader=shader; mat.render_priority=t._water_mat.render_priority
	for uniform: Dictionary in shader.get_shader_uniform_list():
		var value: Variant=t._water_mat.get_shader_parameter(uniform.name)
		if value!=null: mat.set_shader_parameter(uniform.name,value)
	for node in t.get_children():
		if node is MeshInstance3D and String(node.name).begins_with("Water_"): node.material_override=mat
	return mat

func current_texture(vector: Vector2) -> ImageTexture:
	var image := Image.create(1,1,false,Image.FORMAT_RGBAF)
	image.fill(Color(vector.x,vector.y,0,1)); return ImageTexture.create_from_image(image)

func rendered_current() -> void:
	var view := SubViewport.new(); view.size=Vector2i(640,480); view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	world.process_mode=Node.PROCESS_MODE_PAUSABLE
	var map := EIMapScene.new(); world.add_child(map); world.map=map
	var flat := "--current-flat" in OS.get_cmdline_user_args()
	var zone := "zone1" if flat else "zone8"
	GameData.options["gfx_water_current"]=1
	var t := EITerrain.load_map(zone); map.add_child(t); map.terrain=t; world.terrain=t; t.set_process(false)
	t._water_mat.set_shader_parameter("waves",0.0)
	var info := scan(t); var p: Array=info.focus_xyz
	if flat: p=[89.4,t.water_at(89.4,24.14),-24.14]
	check(p.size()==3,"a suitable water focus exists")
	if p.size()!=3: view.free(); return
	var focus := Vector3(p[0],p[1],p[2])
	var camera := Camera3D.new(); view.add_child(camera); camera.position=focus+Vector3(4,6,7); camera.look_at(focus); camera.current=true
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.15,0.25,0.35); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	await frames(50)
	GameData.options["gfx_water_current"]=0; t.apply_gfx(); t._water_mat.set_shader_parameter("waves",0.0)
	var off := await snap(view,"current-off")
	GameData.options["gfx_water_current"]=1; t.apply_gfx(); t._water_mat.set_shader_parameter("waves",0.0)
	var on := await snap(view,"current-on"); var changed := delta(off,on)
	check(changed.changed==0 if flat else changed.over_2>20,"level water retains exact pixels" if flat else "authored slope visibly changes water detail")
	rows.append({"case":"appearance","map":zone,"focus":str(focus),"difference":changed})
	clock_at(t,0.225)
	check(delta(on,await snap(view,"current-moved")).over_2>20,"current surface moves with the terrain clock")
	clock_at(t,0)
	check(delta(on,await snap(view,"current-reset")).changed==0,"current clock reset restores exact pixels")
	Engine.time_scale=1; t.set_process(true)
	get_tree().paused=true; await held(t,view,"current-tree-pause"); get_tree().paused=false
	world.process_mode=Node.PROCESS_MODE_DISABLED; await held(t,view,"current-inactive-world")
	world.process_mode=Node.PROCESS_MODE_PAUSABLE
	var session := Session.new(); world.session=session
	session.lmp_travel=preload("res://src/game/lmp_travel.gd").new(session)
	await held(t,view,"current-lmp-hold")
	world.session=null; session.free(); t.set_process(false); Engine.time_scale=0; clock_at(t,0)
	GameData.options["gfx_water_current"]=0; t.apply_gfx(); t._water_mat.set_shader_parameter("waves",0.0)
	check(delta(off,await snap(view,"current-off-restored")).changed==0,"disabling restores the previous water program exactly")
	GameData.options["gfx_water_current"]=1; GameData.options["gfx_water_interaction"]=1
	t.apply_gfx(); t._water_mat.set_shader_parameter("waves",0.0)
	check(delta(on,await snap(view,"current-empty-contacts")).changed==0,"empty contact variant retains current appearance")
	# Both variants retain the rain cover when SurfaceWeather publishes it late.
	var covered := Image.create(1,1,false,Image.FORMAT_RF); covered.fill(Color(1000,0,0))
	t.set_rain_cover(covered)
	check(t._water_mat.get_shader_parameter("rain_cover")==t._rain_cover,"combined shader receives live rain cover")
	GameData.options["gfx_water_interaction"]=0; t.apply_gfx(); t._water_mat.set_shader_parameter("waves",0.0)
	t.set_rain_cover(covered)
	check(t._water_mat.get_shader_parameter("rain_cover")==t._rain_cover,"current-only shader receives live rain cover")
	GameData.options["gfx_water"]=0; t.apply_gfx()
	check(t._current==null,"original-water option releases current field")
	GameData.options["gfx_water"]=1; GameData.options["gfx_water_interaction"]=1; t.apply_gfx(); t._water_mat.set_shader_parameter("waves",0.0)
	# Isolate only the production detail function: other surf/glint/foam clocks
	# must not masquerade as a phase-wrap failure. Constant flow is a fixture.
	var mat := diagnostic(t,"vec2 slope=river_surface(wpos.xz,wave_ticks*0.055,false,dFdx(wpos.xz),dFdy(wpos.xz)); ALBEDO=vec3(slope*2.0+0.5,0.5); ALPHA=1.0;")
	mat.set_shader_parameter("water_current",current_texture(Vector2(-0.12,0.05)))
	clock_at(t,0,mat); var zero := await snap(view,"current-diagnostic-zero")
	clock_at(t,0.225,mat); var motion := delta(zero,await snap(view,"current-diagnostic-motion"))
	check(motion.over_2>20,"isolated production flow normals animate")
	clock_at(t,9.0,mat); var period := delta(zero,await snap(view,"current-diagnostic-ten-periods"))
	check(period.changed==0,"ten advection periods return to the same normals without growing shear")
	clock_at(t,3600.0,mat); var hour := delta(zero,await snap(view,"current-diagnostic-hour"))
	check(hour.peak<=2,"an hour of game time retains bounded advection")
	clock_at(t,0.8999,mat); var before := await snap(view,"current-before-wrap")
	clock_at(t,0.9001,mat); var wrap := delta(before,await snap(view,"current-after-wrap"))
	check(wrap.peak<=2,"phase wrap is visually continuous")
	rows.append({"case":"isolated-advection","motion":motion,"period":period,"hour":hour,"wrap":wrap})
	mat=diagnostic(t,"float footprint=max(length(dFdx(wpos.xz)),length(dFdy(wpos.xz))); float foam=water_unit_contact(wpos,footprint,river_flow.xy,wave_ticks*0.055).z; ALBEDO=vec3(foam); ALPHA=1.0;")
	var positions := PackedVector4Array(); positions.resize(16); positions[0]=Vector4(focus.x,focus.z,focus.y,0.35)
	var movement := PackedVector4Array(); movement.resize(16); movement[0]=Vector4(0,1,0,0)
	var presence := PackedVector2Array(); presence.resize(16); presence[0]=Vector2(1,0)
	mat.set_shader_parameter("water_contact_count",1); mat.set_shader_parameter("water_contact_position",positions)
	mat.set_shader_parameter("water_contact_motion",movement); mat.set_shader_parameter("water_contact_presence",presence)
	mat.set_shader_parameter("water_current",current_texture(Vector2.ZERO)); clock_at(t,0,mat)
	var still := await snap(view,"current-stationary-still-water")
	mat.set_shader_parameter("water_current",t._current.texture)
	var tail := delta(still,await snap(view,"current-stationary-river"))
	check(tail.changed==0 if flat else tail.over_2>10,"standing in level water has no downstream foam" if flat else "stationary body gains downstream foam from the authored current")
	rows.append({"case":"stationary-body","difference":tail})
	mat=null; view.free(); await frames(10)

func _ready() -> void:
	for key in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_biome_cover","gfx_vegetation_interaction","gfx_wind","gfx_water_interaction","gfx_water_caustics","gfx_water_current","gfx_weather_surfaces","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync","q_aa"]: GameData.options[key]=0
	GameData.options["gfx_water"]=1; GameData.options["gfx_water_reflections"]=0
	Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=120; process_mode=Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; RenderingServer.set_render_loop_enabled(true)
	await rendered_current(); TexUpscale.shutdown(); await frames()
	FileAccess.open("user://water-current-render.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("WATER_CURRENT_RENDER checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)

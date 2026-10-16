extends "water_interaction.gd"
## Rendered lava from the original Suslanger cave; fixed camera and lighting.
func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"auto_graphics":0,"gfx_water":1,"gfx_water_reflections":0,
		"q_aa":0,"q_shadows":0,"confine_mouse":0,"vsync":0,"fps_limit":120},true)
	Gfx.ensure_globals(); Engine.time_scale=0; process_mode=Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true)
	var view := SubViewport.new(); view.size=Vector2i(960,600); view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.current=true; camera.fov=65
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(.05,.03,.02);view.add_child(env)
	Gfx.set_light(Color(.3,.3,.3),Color(.5,.5,.5))
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(180,260,0))
	var world := GameWorld.new();view.add_child(world);world.set_process(false);world.set_physics_process(false)
	var terrain := EITerrain.load_map("zone16");world.add_child(terrain);world.terrain=terrain;terrain.set_process(false)
	var point := Vector3.INF;var best := INF;var width := terrain.sectors_x*32
	for i in terrain.water.size():
		if not is_finite(terrain.water[i]) or terrain.liquid_ground[i]!=13:continue
		var p := Vector2(i%width+.5,i/width+.5)
		if terrain.water[i] < terrain.height_at(p.x,p.y)+.2:continue
		var d := p.distance_squared_to(terrain.size_ei()*.5)
		if d<best:best=d;point=Vector3(p.x,terrain.water[i],-p.y)
	check(point.is_finite(),"authored cave has exposed lava")
	camera.position=point+Vector3(0,9,9);camera.look_at(point)
	print("LAVA_SITE ",point," shader=",terrain._water_mat.shader.code.contains("float heat"))
	terrain._process(7.37)
	var first := await snap(view,"lava-start")
	terrain._process(1.0)
	var next := await snap(view,"lava-1s")
	var d := difference(first,next);rows.append({"seconds":1,"difference":d})
	print("LAVA_MOTION ",JSON.stringify(d))
	check(d.pixels_over_2>=10000,"lava visibly changes within one game second")
	terrain._process(2.0)
	var later := await snap(view,"lava-3s");d=difference(next,later);rows.append({"seconds":2,"difference":d})
	check(d.pixels_over_2>=10000,"lava continues flowing")
	var held := await snap(view,"lava-paused")
	check(difference(later,held).changed_pixels==0,"held terrain time holds lava animation")
	var before := float(terrain._water_mat.get_shader_parameter("wave_ticks"))
	terrain.set_wind(Vector3(0,0,1),0.0);terrain._process(.5)
	check(float(terrain._water_mat.get_shader_parameter("wave_ticks"))>before,"lava clock advances in a windless cave")
	FileAccess.open("user://lava-animation.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	view.free();TexUpscale.shutdown();await frames(5)
	print("LAVA_ANIMATION ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)

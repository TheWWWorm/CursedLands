extends Node
## Isolate enhanced-water surface detail from geometric waves and vegetation.
## Uses the actual World -> Map -> Terrain hierarchy and a real render target.
var checks := 0
var failures := 0
var rows := []

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)

func frames(n := 20) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func delta(a: Image,b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var count := 0; var over := 0; var peak := 0
	for i in range(0,aa.size(),4):
		var d := maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		count+=int(d>0); over+=int(d>2); peak=maxi(peak,d)
	return {"changed":count,"over_2":over,"peak":peak}

func snap(view: SubViewport,label: String) -> Image:
	await frames()
	var image := view.get_texture().get_image(); image.save_png("user://water-detail-"+label+".png"); return image

func held(t: EITerrain,view: SubViewport,label: String) -> void:
	var before := t._waves.time_ticks(); var a := await snap(view,label)
	await frames(30); var difference := delta(a,await snap(view,label+"-later"))
	check(t._waves.time_ticks()==before,label+" holds the owning terrain clock")
	check(difference.changed==0,label+" holds the rendered surface detail")
	rows.append({"case":label,"difference":difference})

func run() -> void:
	var view := SubViewport.new(); view.size=Vector2i(640,480); view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	world.process_mode=Node.PROCESS_MODE_PAUSABLE
	var map := EIMapScene.new(); world.add_child(map); world.map=map
	var t := EITerrain.load_map("zone1"); map.add_child(t); map.terrain=t; world.terrain=t; t.set_process(false)
	t._water_mat.set_shader_parameter("waves",0.0)
	var p := Vector2(89.4,24.14); var focus := Vector3(p.x,t.water_at(p.x,p.y),-p.y)
	var camera := Camera3D.new(); view.add_child(camera); camera.position=focus+Vector3(3,3,5); camera.look_at(focus); camera.current=true
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.15,0.25,0.35); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	await frames(60); var zero := await snap(view,"zero")
	check(delta(zero,await snap(view,"zero-stable")).changed==0,"initial surface has settled before changing its clock")
	t._waves.advance(7.0); t._update_wave_parameters()
	var moved := delta(zero,await snap(view,"seven-seconds"))
	check(moved.over_2>20,"game-time advance moves detail with geometry and wall time frozen")
	rows.append({"case":"game-clock-advance","difference":moved})
	t._waves=EIWaterWaves.new(); t._update_wave_parameters()
	check(delta(zero,await snap(view,"reset")).changed==0,"resetting terrain time restores exactly the same surface")
	Engine.time_scale=1.0; t.set_process(true)
	get_tree().paused=true; await held(t,view,"tree-pause"); get_tree().paused=false
	world.process_mode=Node.PROCESS_MODE_DISABLED; await held(t,view,"inactive-world")
	world.process_mode=Node.PROCESS_MODE_PAUSABLE
	var session := Session.new(); world.session=session
	session.lmp_travel=preload("res://src/game/lmp_travel.gd").new(session)
	await held(t,view,"lmp-hold")
	world.session=null; session.free()
	var elapsed := []
	for scale: float in [1.0,2.0]:
		Engine.time_scale=scale; await frames(4); var start := t._waves.time_ticks()
		# A fixed real-time interval does not assume the startup FPS limiter
		# has stayed at this tool's requested value.
		await get_tree().create_timer(0.3,true,false,true).timeout
		elapsed.append((t._waves.time_ticks()-start)*EIWaterWaves.TICK)
	check(elapsed[0]>0.25 and elapsed[1]/elapsed[0]>1.7 and elapsed[1]/elapsed[0]<2.3,"game speed scales the shared detail clock")
	check(is_equal_approx(t._water_mat.get_shader_parameter("wave_ticks"),t._waves.time_ticks()),"material retains the live terrain clock")
	rows.append({"case":"speed","seconds_1x":elapsed[0],"seconds_2x":elapsed[1]})
	t.set_process(false); Engine.time_scale=0
	var before := await snap(view,"before-options")
	GameData.options["gfx_water"]=0; t.apply_gfx()
	GameData.options["gfx_water"]=1; t.apply_gfx(); t._water_mat.set_shader_parameter("waves",0.0)
	check(delta(before,await snap(view,"after-options")).changed==0,"water option round trip retains the detail phase")
	view.free(); await frames()

func _ready() -> void:
	for key in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_biome_cover","gfx_vegetation_interaction","gfx_wind","gfx_water_interaction","gfx_water_caustics","gfx_weather_surfaces","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[key]=0
	GameData.options["gfx_water"]=1; Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=120
	process_mode=Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; RenderingServer.set_render_loop_enabled(true)
	await run(); TexUpscale.shutdown(); await frames()
	FileAccess.open("user://water-detail-clock.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("WATER_DETAIL_CLOCK checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)

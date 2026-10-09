extends Node
## Held original-map views, Detailed/Natural/Natural/Detailed normal frames.
## Compare the same external fixture with frozen baseline/candidate packs.
const SITES := [
	{"map":"zone15","tile":Vector2i(69,19),"label":"three-families"},
	{"map":"zone12","tile":Vector2i(67,127),"label":"four-families"},
	{"map":"zone11","tile":Vector2i(69,87),"label":"existing-pair"},
]
var checks:=0
var failures:=0
var rows:=[]

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)

func tick() -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

func settle(count: int) -> void:
	for i in count:await tick()

func distribution(values: Array) -> Dictionary:
	var ordered:=values.duplicate();ordered.sort()
	return {"min":ordered[0],"median":ordered[ordered.size()/2],"p95":ordered[int(ordered.size()*0.95)],"max":ordered.back()}

func measure(view: SubViewport,terrain: EITerrain,site: Dictionary,mode: int,arm: int) -> void:
	GameData.options.gfx_terrain=mode;Gfx.apply_surface_options();terrain.apply_gfx()
	await settle(96)
	var cpu:=[];var gpu:=[];var wall:=[];var draws:=[];var primitives:=[];var invalid:=0
	var start:=Engine.get_frames_drawn()
	for i in 240:
		var begin:=Time.get_ticks_usec();await tick();wall.append((Time.get_ticks_usec()-begin)/1000.0)
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		var ms:=RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
		gpu.append(ms);invalid+=int(not is_finite(ms) or ms<=0.0)
		draws.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		primitives.append(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
	check(invalid==0,"positive finite GPU timestamps "+site.label+" arm "+str(arm))
	check(Engine.get_frames_drawn()>=start+240,"normal frame clock advances "+site.label)
	check(draws.min()>0 and primitives.min()>0,"visible original geometry submitted "+site.label)
	check(Engine.max_fps==0 and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED,"uncapped timing "+site.label)
	var field:=terrain._transitions
	var field_info: Dictionary={"admitted":field.admitted,"build_us":field.build_us,"bytes":field.tiles.get_image().get_data().size()} if field else {}
	rows.append({"map":site.map,"tile":[site.tile.x,site.tile.y],"label":site.label,"mode":mode,"arm":arm,
		"warmup_frames":96,"sample_frames":240,"viewport_cpu_ms":distribution(cpu),"viewport_gpu_ms":distribution(gpu),
		"frame_wall_ms":distribution(wall),"visible_draws":distribution(draws),"visible_primitives":distribution(primitives),"field":field_info})
	if arm<2:
		var pixels:=view.get_texture().get_image();pixels.convert(Image.FORMAT_RGBA8)
		check(pixels.save_png("user://junction-cost-"+site.label+"-mode"+str(mode)+".png")==OK,"capture actual timed view")
	print("TERRAIN_JUNCTION_COST_ROW ",JSON.stringify(rows.back()))

func scene(site: Dictionary) -> void:
	GameData.options.gfx_terrain=1;Gfx.apply_surface_options()
	var view:=SubViewport.new();view.size=Vector2i(1920,1080);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	var terrain:=EITerrain.load_map(site.map);view.add_child(terrain);terrain.set_process(false);terrain.apply_gfx()
	var x: int=site.tile.x*2+1;var y: int=site.tile.y*2+1;var index:=y*terrain.grid_w+x
	var center:=Vector2(x,y)+terrain.land_xy[index]
	var focus:=Vector3(center.x,terrain.heights[index],-center.y)
	var camera:=Camera3D.new();view.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=10
	camera.position=focus+Vector3(0,20,0);camera.look_at(focus,Vector3.FORWARD);camera.current=true
	var env:=WorldEnvironment.new();env.environment=Environment.new();Gfx.setup_original_env(env.environment);view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);view.add_child(sun)
	Gfx.set_light(Color(0.65,0.65,0.65),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	for arm in 4:await measure(view,terrain,site,1 if arm in [0,3] else 2,arm)
	view.free();await settle(8)

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"q_aa":0,"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":0},true)
	Gfx.ensure_globals();Gfx.apply_surface_options();Engine.time_scale=0;process_mode=Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	await settle(16);Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for site: Dictionary in SITES:await scene(site)
	TexUpscale.shutdown();await settle(12)
	FileAccess.open("user://terrain-junction-cost.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,
		"viewport":[1920,1080],"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"scope":"Complete viewport cost in held original-map close views; excludes cold loads and is not game FPS or target-device acceptance."},"\t")+"\n")
	print("TERRAIN_JUNCTION_COST ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

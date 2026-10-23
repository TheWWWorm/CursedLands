extends Node
## Original village ground and footprint cells viewed from moving cameras.
var checks := 0
var failures := 0
var rows := []
var view: SubViewport
var world: GameWorld
var terrain: EITerrain
var marks: GroundMarks
var camera: Camera3D
var focus: Vector3

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)

func frames(count := 4) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func _ready() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("This footprint test requires a rendering display."); get_tree().quit(2); return
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	if OS.get_cmdline_user_args().has("--enhanced"):
		for key: String in ["gfx_terrain","gfx_materials","gfx_soft_ground","gfx_ground_contact"]: GameData.options[key]=1
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"footprints":1,"vsync":0},true)
	Gfx.ensure_globals(); Engine.max_fps=30
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	RenderingServer.set_render_loop_enabled(true)
	run.call_deferred()

func prepare_scene() -> void:
	view=SubViewport.new(); view.size=Vector2i(1280,720); view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	world=GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	if OS.get_cmdline_user_args().has("--full-scene"):
		check(world.load_map("basegipat","basecam",false),"original village and walking surfaces load")
		terrain=world.terrain
		# Test ground receipt without scenery occluding the camera, retaining
		# every authored floor in the same height query used by walking marks.
		for node: Node3D in world.map.object_nodes: node.hide()
	else:
		terrain=EITerrain.load_map("basegipat"); world.add_child(terrain); world.terrain=terrain
	terrain.set_process(false)
	marks=GroundMarks.of(world); marks.set_process(false)
	focus=Vector3(64,terrain.ground_at(64,62),-62)
	camera=Camera3D.new(); view.add_child(camera); camera.current=true; camera.far=180
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(.12,.18,.24); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(.5,.5,.5),Color(.75,.75,.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))

func run() -> void:
	prepare_scene()
	for y in 7:
		for x in 7:
			var p := Vector2(61.0+x,59.0+y)
			marks.add_footprint(p.x,p.y,.11,.25,(x+y)*.3,0,-1)
	check(marks.foot_marks.size()>30,"authored village soil accepts a full trail")
	print("FOOTPRINT_TABLE type=",terrain.mark_ground(64,62)," life=",marks.foot_marks[0].life," fade=",marks.foot_marks[0].fade)
	camera.position=focus+Vector3(0,7,8); camera.look_at(focus)
	await frames(45) # Let the actual terrain/decal pipelines and atlas settle.
	for angle: int in [0,1,2,30,60,90,120,150,180,210,240,270,300,330]:
		var yaw := deg_to_rad(float(angle))
		camera.position=focus+Vector3(sin(yaw)*8,7,cos(yaw)*8); camera.look_at(focus)
		marks.hide(); await frames()
		var clear := view.get_texture().get_image()
		marks.show(); await frames()
		var ink := view.get_texture().get_image()
		var counts := []
		for mark: GroundMarks.Mark in marks.foot_marks:
			var at := camera.unproject_position(mark.decal.global_position)
			var changed := 0
			for y in range(maxi(0,int(at.y)-22),mini(720,int(at.y)+22)):
				for x in range(maxi(0,int(at.x)-22),mini(1280,int(at.x)+22)):
					var a := clear.get_pixel(x,y); var b := ink.get_pixel(x,y)
					if a.r-b.r>.025 or a.g-b.g>.025 or a.b-b.b>.025: changed+=1
			counts.append(changed)
			check(changed>12,"footprint remains on the surface angle=%d at=%s pixels=%d"%[angle,Vector2(mark.x,mark.y),changed])
		rows.append({"angle":angle,"pixels":counts})
		if angle in [0,30,90,180]: ink.save_png("user://footprints-%d.png"%angle)
	FileAccess.open("user://footprint-surface-scene.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	view.free(); await frames()
	TexUpscale.shutdown()
	print("FOOTPRINT_SURFACE_SCENE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

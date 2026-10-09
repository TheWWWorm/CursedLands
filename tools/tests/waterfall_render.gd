extends Node
const Falls = preload("res://src/game/fx/waterfalls.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count := 4) -> void:
	for n in count: await get_tree().process_frame

func snap(view: SubViewport, name: String) -> Image:
	await frames(4); await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	image.save_png("user://waterfalls-"+name+".png")
	return image

func difference(a: Image,b: Image) -> Dictionary:
	var aa := a.get_data(); var bb := b.get_data()
	var changed := 0; var peak := 0; var sum := 0
	for i in range(0,aa.size(),4):
		var delta := 0
		for k in 3: delta = maxi(delta,absi(int(aa[i+k])-int(bb[i+k])))
		if delta: changed += 1
		peak = maxi(peak,delta); sum += delta
	return {"changed_pixels":changed,"peak_byte_delta":peak,"sum":sum}

func case(map: String, positive: bool) -> void:
	var view := SubViewport.new(); view.size=Vector2i(640,480); view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	GameData.options.gfx_waterfalls=0; GameData.options.gfx_water=1
	var terrain := EITerrain.load_map(map); world.add_child(terrain); world.terrain=terrain; terrain.set_process(false)
	check(terrain._waterfalls==null,"disabled option allocates no waterfall owner "+map)
	var focus := Vector3(160,12.5,-142)
	var direction := Vector3(0,0,1)
	var probe := Falls.Field.new(terrain)
	if positive:
		check(probe.falls.size()==1,"real positive map has one coherent drop "+map)
		if probe.falls.is_empty(): view.free(); return
		var fall: Dictionary = probe.falls[0]
		var p: Vector2 = fall.lip+fall.direction*fall.run*0.5
		focus=Vector3(p.x,(fall.top+fall.bottom)*0.5,-p.y)
		direction=Vector3(fall.direction.x,0,-fall.direction.y)
	var camera := Camera3D.new(); view.add_child(camera)
	var side := Vector3(-direction.z,0,direction.x)
	camera.position=focus+direction*12.0+side*7.0+Vector3(0,6,0); camera.look_at(focus); camera.current=true
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.15,0.25,0.35); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	await frames(60)
	var off := await snap(view,map+"-off")
	var draws := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	GameData.options.gfx_waterfalls=1; terrain.apply_gfx()
	check(terrain._waterfalls!=null,"enabled water creates owner "+map)
	if terrain._waterfalls==null: view.free(); return
	var helper: Falls = terrain._waterfalls
	var initial := await snap(view,map+"-on")
	var changed := difference(off,initial)
	var added_draws := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)-draws
	check(added_draws<=2*helper.sites.size(),"no more than two added draws per site "+map)
	if positive:
		check(changed.changed_pixels>40 and changed.peak_byte_delta>8,"exposed waterfall foam and spray are visible "+map)
		check(helper.sites.size()==1 and helper.sprites>0,"real drop has shell and spray "+map)
		for n in 20: terrain._update_wave_parameters()
		check(difference(initial,await snap(view,map+"-clock-held")).changed_pixels==0,"held terrain clock holds exact waterfall pixels "+map)
		var builds: int = helper.field.builds
		terrain._waves.advance(0.4); terrain._update_wave_parameters()
		var animated := await snap(view,map+"-flowing")
		check(difference(initial,animated).changed_pixels>10,"terrain game time moves foam and spray "+map)
		check(helper.field.builds==builds,"ordinary animation never rebuilds classification "+map)
		var owner: int = helper.field.falls[0].top_owner
		terrain.set_water_offset(owner,0.2); terrain.set_water_offset(owner,0.4); terrain.set_water_offset(owner,0.6)
		check(not helper.visible,"flood update hides stale shell immediately "+map)
		await frames()
		check(helper.visible and helper.field.builds==builds+1 and absf(helper.field.levels[owner]-0.6)<0.001,"flood writes coalesce to final levels "+map)
		await snap(view,map+"-flood")
		terrain.set_water_offset(owner,0.0); await frames()
		check(helper.field.falls==probe.falls,"restoring level restores authored drop "+map)
	else:
		check(helper.get_child_count()==0 and changed.changed_pixels==0 and added_draws==0,"ordinary river remains pixel exact with no waterfall draws "+map)
	# Compare the disabled option at the same current wave clock.
	helper.hide()
	var hidden := await snap(view,map+"-hidden-control")
	var weak := weakref(helper.field)
	GameData.options.gfx_waterfalls=0; terrain.apply_gfx()
	check(terrain._waterfalls==null and weak.get_ref()==null,"disable releases snapshot and renderer "+map)
	check(difference(hidden,await snap(view,map+"-disabled")).changed_pixels==0,"disable restores exact underlying water "+map)
	GameData.options.gfx_water=0; terrain.apply_gfx()
	var original := await snap(view,map+"-original")
	GameData.options.gfx_waterfalls=1; terrain.apply_gfx()
	check(terrain._waterfalls==null,"water dependency suppresses owner "+map)
	check(difference(original,await snap(view,map+"-dependency")).changed_pixels==0,"disabled water dependency is pixel exact "+map)
	GameData.options.gfx_water=1; terrain.apply_gfx()
	var retirement := weakref(terrain._waterfalls)
	rows.append({"map":map,"positive":positive,"focus":str(focus),"difference":changed,"added_draws":added_draws,"renderer":RenderingServer.get_current_rendering_method()})
	view.free(); await frames()
	check(retirement.get_ref()==null,"terrain retirement releases waterfall nodes "+map)

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":3},true)
	Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=120; process_mode=Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	if "--waterfall-astral" in OS.get_cmdline_user_args():
		await case("zone10",true); await case("zone26",true)
	else:
		await case("zone11",true); await case("zone13",true); await case("zone8",false)
	TexUpscale.shutdown(); await frames(12)
	FileAccess.open("user://waterfalls-render.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("WATERFALL_RENDER ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

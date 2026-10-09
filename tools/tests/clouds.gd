extends "water_interaction.gd"
## Private exported fixture for shared cloud motion, lighting and sky.
const Clouds = preload("res://src/game/fx/clouds.gd")
const SUN := Vector3(0.5,0.8660254,0.0)

class QuietGame extends Game:
	func _ready() -> void: set_process(false)
	func _process(_dt: float) -> void: pass


func analytical() -> void:
	check(Clouds.coverage("Gipat",0,0)>Clouds.coverage("Ingos",0,0) and Clouds.coverage("Ingos",0,0)>Clouds.coverage("Suslanger",0,0),"regional fair-weather coverage ordering")
	check(Clouds.coverage("Suslanger",1,0)>Clouds.coverage("Gipat",0,0),"rain builds cloud cover over dry regions")
	check(Clouds.coverage("Ingos",0,1)==Clouds.coverage("Gipat",1,0),"snow and rain both reach overcast coverage")
	check(Clouds.daylight(12)==1.0 and Clouds.daylight(0)==0.0 and Clouds.daylight(24)==0.0,"daylight wraps and night has no solar shadow")
	var a := Clouds.new(); var b := Clouds.new(); var wind := Vector4(1,0,0.6,0.2)
	a.sample(0,"zone1","Gipat",wind,0,0,12,false)
	b.sample(0,"zone1","Gipat",wind,0,0,12,false)
	check(a.frame==b.frame,"map seed is deterministic")
	var initial := a.frame.duplicate(true)
	a.sample(0,"zone1","Gipat",Vector4(0,1,1,1),1,1,1,false)
	check(a.frame==initial,"held terrain clock ignores weather, wind and hour drift")
	for n in 120: a.sample((n+1)/60.0,"zone1","Gipat",wind,0,0,12,false)
	for n in 60: b.sample((n+1)/30.0,"zone1","Gipat",wind,0,0,12,false)
	check((a.frame.phases as Vector4).is_equal_approx(b.frame.phases),"accelerated game time follows the same wind path")
	check(a.frame.phases!=initial.phases,"cloud field moves during gameplay")
	var before: Vector4=a.frame.phases
	a.sample(2.001,"zone1","Gipat",Vector4(0,1,1,1),1,0,12,false)
	var after: Vector4=a.frame.phases
	var distance := 0.0
	for i in 4: distance=maxf(distance,absf(wrapf(after[i]-before[i],-0.5,0.5)))
	check(distance<0.001,"changing wind and rain cannot jump elapsed-time displacement")
	a.sample(2.001,"zone1","Gipat",wind,0,0,12,true)
	check(a.frame.state.w==0.0,"cave transition clears clouds even at held time")
	a.sample(0,"zone1","Gipat",wind,0,0,12,false)
	check(a.frame==initial,"rewind returns to deterministic empty-time state")
	a.sample(100000000.0,"zone1","Gipat",wind,0,0,12,false)
	a.sample(100000000.1,"zone1","Gipat",wind,0,0,12,false)
	check((a.frame.phases as Vector4).is_finite() and a.frame.phases!=initial.phases,"long game clocks retain fractional motion")
	a.phase_x=0.00001; a.phase_z=0.99999; a.detail_x=0.00001; a.detail_z=0.99999
	a.sample(100000000.2,"zone1","Gipat",wind,0,0,12,false)
	var bounded := true
	for i in 4: bounded=bounded and a.frame.phases[i]>=0.0 and a.frame.phases[i]<1.0
	check(bounded,"all independent seamless phases stay bounded after wrap")
	Gfx.set_cloud_frame(123,a.frame); Gfx.clear_clouds(456)
	check(Gfx._cloud_owner==123,"retained world cannot clear the active view's globals")
	Gfx.clear_clouds(123)
	check(Gfx._cloud_owner==0 and Gfx._cloud_frame.state==Vector4.ZERO,"active world teardown clears cloud globals")
	var preview := EIUnitModel.PreviewMaterial.new()
	var preview_source := preview.shader.code
	GameData.options["gfx_clouds"]=1; Gfx.apply_surface_options()
	check(preview.shader.code==preview_source and not preview_source.contains("ei_cloud"),"UI preview material remains outside cloud-light recompilation")
	GameData.options["gfx_clouds"]=0; Gfx.apply_surface_options()
	rows.append({"case":"analytic","phase_after_wrap":str(a.frame.phases),"wind_change_phase_distance":distance})


func lifecycle() -> void:
	GameData.options["gfx_clouds"]=1
	var game := QuietGame.new(); game.process_mode=Node.PROCESS_MODE_ALWAYS; add_child(game)
	var world := GameWorld.new(); world.zone={"id":"gz11k","allod":""}
	world.process_mode=Node.PROCESS_MODE_PAUSABLE
	game.world=world; game.add_child(world); world.set_process(false); world.set_physics_process(false)
	var map := EIMapScene.new(); world.add_child(map)
	var t := EITerrain.new(); t.map_name="zone1"; map.add_child(t); world.terrain=t; map.terrain=t
	t.set_process(false)
	var session := Session.new(); session.state=CampaignState.new(); session.state.world_time=12
	world.session=session
	var sound := GameSound.new(); game.sound=sound
	sound.weather=Weather.new(null,world)
	t._update_cloud_parameters()
	check(t._clouds!=null and Gfx._cloud_owner==t.get_instance_id(),"actual World-Map-Terrain hierarchy publishes its field")
	check(is_equal_approx(Gfx._cloud_frame.state.x,0.8-0.55*0.5),"empty allod metadata falls back to the actual zone's region")
	var fair: Dictionary=t._clouds.frame.duplicate(true)
	sound.weather._shown=1; sound.weather._target=1
	t._update_cloud_parameters()
	check(t._clouds.frame==fair,"paused terrain holds weather coverage while audio weather changes")
	t._process(0.1)
	check(t._clouds.frame.state.x<fair.state.x,"actual precipitation reaches the next game-time cloud sample")
	var rainy: Dictionary=t._clouds.frame.duplicate(true)
	session.lmp_travel=preload("res://src/game/lmp_travel.gd").new(session)
	t._process(0.1)
	check(t._clouds.frame==rainy,"unregistered retained LMP world holds cloud time")
	session.lmp_travel=null
	var retained := GameWorld.new(); game.add_child(retained); retained.set_process(false); retained.set_physics_process(false)
	var other := EITerrain.new(); retained.add_child(other); other.set_process(false)
	other._update_cloud_parameters()
	check(other._clouds==null and Gfx._cloud_owner==t.get_instance_id(),"inactive Game world cannot publish global atmosphere")
	other.free(); retained.free()
	check(Gfx._cloud_owner==t.get_instance_id(),"inactive-world destruction preserves active atmosphere")
	world.zone.sky="cave"; t._update_cloud_parameters()
	check(Gfx._cloud_frame.state.w==0.0,"actual cave transition clears cloud visibility at held time")
	world.zone.erase("sky"); t._update_cloud_parameters()
	var held: Dictionary=t._clouds.frame.duplicate(true)
	Engine.time_scale=1; t.set_process(true); get_tree().paused=true
	await frames(8)
	check(t._clouds.frame==held,"SceneTree pause holds terrain-owned clouds below an always-processing Game")
	get_tree().paused=false; await frames(8)
	check(t._clouds.frame.phases!=held.phases,"unpause resumes the existing cloud phase")
	Engine.time_scale=0; t.set_process(false)
	var weak := weakref(t._clouds)
	GameData.options["gfx_clouds"]=0; Gfx.apply_surface_options(); t.apply_gfx()
	check(t._clouds==null and weak.get_ref()==null and Gfx._cloud_owner==0,"option disable releases local phase history and clears global ownership")
	GameData.options["gfx_clouds"]=1; t._update_cloud_parameters()
	check(t._clouds!=null,"re-enable creates a fresh bounded cloud history")
	game.free(); sound.free(); session.free(); Engine.time_scale=0
	check(Gfx._cloud_owner==0,"active map exit clears global cloud state")
	GameData.options["gfx_clouds"]=0; Gfx.apply_surface_options()


func cloud_image(view: SubViewport,label: String) -> Image:
	await frames(8)
	await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image()
	result.save_png("user://clouds-"+label+".png")
	return result


func rendered() -> void:
	var view := SubViewport.new(); view.size=Vector2i(640,480); view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var world := GameWorld.new(); view.add_child(world); world.set_process(false); world.set_physics_process(false)
	var t := EITerrain.load_map("zone1"); world.add_child(t); world.terrain=t; t.set_process(false)
	var p := centre(t)
	t._water_mat.set_shader_parameter("waves",0.0)
	var camera := Camera3D.new(); view.add_child(camera); camera.position=p+Vector3(0,5,16); camera.look_at(p+Vector3(0,2,0)); camera.current=true
	var actor_position := p+Vector3(-2,0,6)
	actor_position.y=t.height_at(actor_position.x,-actor_position.z)
	var actor := unit(world,9722,actor_position)
	var environment := Environment.new(); Gfx.setup_original_env(environment)
	environment.background_mode=Environment.BG_SKY; environment.sky=Sky.new()
	environment.sky.radiance_size=Sky.RADIANCE_SIZE_128; environment.sky.process_mode=Sky.PROCESS_MODE_REALTIME
	var sky := EISky.material(false); environment.sky.sky_material=sky
	EISky.update(sky,null,12,false,false)
	var env := WorldEnvironment.new(); env.environment=environment; view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-60,-90,0); view.add_child(sun)
	Gfx.set_light(Color(0.3,0.3,0.3),Color(0.9,0.9,0.9))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",SUN)
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	await frames(50)
	var base_source := t._land_mat.shader.code
	var off := await cloud_image(view,"off")
	var draw_count := view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	GameData.options["gfx_clouds"]=1; Gfx.apply_surface_options(); EISky.update(sky,null,12,false,false)
	check(t._land_mat.shader.code.contains("ei_cloud_sun(p)"),"current live terrain program receives cloud sunlight shading")
	check(sky.shader.code.contains("ei_cloud_density"),"live sky receives the same cloud density field")
	# Let native asynchronous pipeline specialization settle before the
	# empty-state comparison as well as the visible cloud captures.
	await frames(70)
	var empty := await cloud_image(view,"empty")
	check(difference(off,empty).changed_pixels==0,"empty cloud globals preserve exact original pixels")
	var field := Clouds.new(); var wind := Vector4(0.7,-0.7,0.7,0.3)
	Gfx.set_cloud_frame(t.get_instance_id(),field.sample(0,"zone1","Gipat",wind,0,0,12,false))
	await frames(70) # asynchronous seamless texture preparation/radiance settles
	var still := await cloud_image(view,"still")
	var delta := difference(empty,still)
	check(delta.pixels_over_2>1000,"cloud layer and soft surface shadows appear")
	check(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)==draw_count,"cloud layer keeps the original scene draw count")
	check(difference(still,await cloud_image(view,"held")).changed_pixels==0,"held cloud clock gives exact sky and water pixels")
	for n in 120: Gfx.set_cloud_frame(t.get_instance_id(),field.sample((n+1)*0.1,"zone1","Gipat",wind,0,0,12,false))
	var moved := await cloud_image(view,"moved")
	check(difference(still,moved).pixels_over_2>500,"integrated game-time wind moves sky and shadows")
	# Isolate world illumination from the sky/reflection contribution.
	var saved_sky := environment.sky
	environment.background_mode=Environment.BG_COLOR
	environment.sky=null
	GameData.options["gfx_water"]=0; t.apply_gfx(); t._water_mat.set_shader_parameter("waves",0.0)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",Vector3.ZERO)
	var no_sun := await cloud_image(view,"no-sun-on")
	Gfx.clear_clouds(); var no_cloud := await cloud_image(view,"no-sun-off")
	check(difference(no_sun,no_cloud).changed_pixels==0,"clouds never darken ambient or emissive light without sunlight")
	RenderingServer.global_shader_parameter_set(&"ei_pl0",Vector4(p.x,p.y+4,p.z,18))
	RenderingServer.global_shader_parameter_set(&"ei_plc0",Vector4(0.9,0.5,0.2,0))
	var point := OmniLight3D.new(); view.add_child(point); point.position=p+Vector3(0,4,0); point.omni_range=18
	var local_off := await cloud_image(view,"local-off")
	Gfx.set_cloud_frame(t.get_instance_id(),field.frame)
	check(difference(local_off,await cloud_image(view,"local-on")).changed_pixels==0,"local point-light contribution remains exact")
	point.free(); RenderingServer.global_shader_parameter_set(&"ei_pl0",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_plc0",Vector4.ZERO)
	GameData.options["gfx_water"]=1; t.apply_gfx(); t._water_mat.set_shader_parameter("waves",0.0)
	Gfx.clear_clouds(); var reflection_off := await cloud_image(view,"reflection-off")
	Gfx.set_cloud_frame(t.get_instance_id(),field.frame)
	var reflected := await cloud_image(view,"reflection-on")
	check(difference(reflection_off,reflected).pixels_over_2>20,"enhanced water reflects the shared cloud layer with no direct sunlight")
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",SUN)
	environment.sky=saved_sky
	environment.background_mode=Environment.BG_SKY
	Gfx.set_cloud_frame(t.get_instance_id(),field.sample(12,"zone1","Gipat",wind,0,0,12,true))
	check(difference(empty,await cloud_image(view,"cave-cleared")).changed_pixels==0,"cave cloud state immediately restores baseline sky and surface")
	GameData.options["gfx_clouds"]=0; Gfx.apply_surface_options(); EISky.update(sky,null,12,false,false)
	check(t._land_mat.shader.code==base_source and sky.shader.code==EISky.SHADER,"option disable removes cloud sampling from both programs")
	check(difference(off,await cloud_image(view,"restored")).changed_pixels==0,"off-on-off restores the complete view exactly")
	GameData.options["gfx_clouds"]=1; Gfx.apply_surface_options()
	var lights := EILights.load_for("Gipat",false)
	EISky.update(sky,lights,0,false,true)
	Gfx.set_light(lights.sample("ambient",0),lights.sample("sunlight",0))
	Gfx.set_cloud_frame(t.get_instance_id(),field.sample(12.1,"zone1","Gipat",wind,0,0,0,false))
	check(sky.get_shader_parameter("night")==1.0 and not sky.shader.code.contains("TIME"),"night sky and stars use the game clock in cloud mode")
	var night := await cloud_image(view,"night")
	check(difference(night,await cloud_image(view,"night-held")).changed_pixels==0,"paused night keeps stars, clouds and water exact")
	GameData.options["gfx_clouds"]=0; Gfx.apply_surface_options(); EISky.update(sky,lights,0,false,true)
	rows.append({"case":"rendered","renderer":RenderingServer.get_current_rendering_method(),"initial":delta,"movement":difference(still,moved),"draws":draw_count})
	world.erase_unit(actor.uid); actor.free(); view.free(); await frames(12)


func _ready() -> void:
	for option in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	for key in ["confine_mouse","vsync"]: GameData.options[key]=0
	GameData.options["gfx_water"]=1; GameData.options["gfx_water_reflections"]=1
	GameData.options["gfx_materials"]=int("--clouds-materials" in OS.get_cmdline_user_args())
	GameData.options["fps_limit"]=3
	Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=120; process_mode=Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	analytical()
	if not "--clouds-analytic" in OS.get_cmdline_user_args(): await lifecycle()
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		RenderingServer.set_render_loop_enabled(true)
		await rendered()
	TexUpscale.shutdown(); UnitWounds.shutdown(); await frames(12)
	FileAccess.open("user://clouds.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("CLOUDS checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)

extends "ground_contact.gd"
## Shared vegetation wind: deterministic drive, ownership, pause and real trees.
const Wind = preload("res://src/game/fx/weather_wind.gd")
var witness: SubViewport

class QuietGame extends Game:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process(false); set_process_unhandled_input(false)

func frames(n := 12) -> void:
	for i in n:
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		await get_tree().process_frame

func delta(a: Image,b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var changed := 0; var over := 0; var peak := 0
	for i in range(0,aa.size(),4):
		var d := maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		changed+=int(d>0); over+=int(d>2); peak=maxi(peak,d)
	return {"changed":changed,"over_2":over,"peak":peak}

func snap(view: SubViewport,label: String) -> Image:
	await frames()
	var image := view.get_texture().get_image(); image.save_png("user://weather-wind-"+label+".png"); return image

func global_pixels() -> PackedByteArray:
	await frames(3)
	return witness.get_texture().get_image().get_data()

func setup_witness() -> void:
	if DisplayServer.get_name()=="headless": return
	witness=SubViewport.new(); witness.size=Vector2i(16,4); witness.disable_3d=true
	witness.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(witness)
	var rect := ColorRect.new(); rect.size=Vector2(16,4); witness.add_child(rect)
	var material := ShaderMaterial.new(); var shader := Shader.new()
	shader.code="""shader_type canvas_item;
global uniform vec4 ei_wind_state;
global uniform vec4 ei_wind_phases;
void fragment() {
 vec4 encoded = UV.x < 0.5 ? vec4(ei_wind_state.xy*0.5+0.5,ei_wind_state.zw) : ei_wind_phases / 6.28318530718;
 COLOR = vec4(encoded.rgb,1.0);
 if (UV.y > 0.5) { COLOR.rgb = vec3(encoded.w); }
}"""
	material.shader=shader; rect.material=material

func pure() -> void:
	# Independent unsigned Python oracle, including signed/high lattice bits.
	for row in [[0,0,0.0],[1,-1,0.9963839054107666],[0xffffffff,4294967297,0.611850380897522],
		[0xb5297a4d,73,0.3717341423034668],[0x811c9dc5,-4294967297,0.12774348258972168]]:
		check(Wind.lattice(row[0],row[1])==row[2],"unsigned lattice oracle "+str(row))
	var seed_value := Wind.map_seed("zone1")
	var rng := RandomNumberGenerator.new(); rng.seed = 831090
	var maximum := 0.0
	for i in 1000:
		var time := rng.randf_range(0,604800); var direction := Vector2(rng.randf_range(-1,1),rng.randf_range(-1,1))
		var force := rng.randf(); var rain := rng.randf(); var snow := rng.randf()
		var frame := Wind.sample(time,seed_value,direction,force,rain,snow)
		check(frame==Wind.sample(time,seed_value,direction,force,rain,snow),"same time gives identical wind")
		var state: Vector4 = frame.state; var phases: Vector4 = frame.phases
		check(absf(Vector2(state.x,state.y).length()-1)<0.000001 and state.z>=0 and state.z<=1 and state.w>=0 and state.w<=1,"bounded unit direction and drive")
		var calm := Wind.sample(time,seed_value,direction,force)
		check(calm.phases==phases,"storm never multiplies elapsed time")
		check(state.z>=(calm.state as Vector4).z,"weather never weakens the wind drive")
		var indoors := Wind.sample(time,seed_value,direction,force,rain,snow,true)
		check(indoors==Wind.sample(time,seed_value,direction,force,0,0,true),"indoor frame ignores precipitation")
		var q := clampf((state.w-0.1)/0.9,0,1)
		# Independent triangle inequality for every possible position/phase.
		var envelope := (0.32+0.06*q+0.18+0.03*q+0.10+0.06*q)/0.75*0.04*state.z
		maximum=maxf(maximum,envelope)
		check(envelope<=0.04000001,"all orientations retain the 4 cm clearance")
	for time: float in [TAU/Wind.TRAVEL,3600.0,86400.0,604800.0]:
		var a: Vector4 = Wind.sample(time-0.00001,seed_value,Vector2.ZERO,0.4).phases
		var b: Vector4 = Wind.sample(time+0.00001,seed_value,Vector2.ZERO,0.4).phases
		for i in 4: check(absf(sin(a[i])-sin(b[i]))<0.0001 and absf(cos(a[i])-cos(b[i]))<0.0001,"phase continuity across wrap/hour/day")
	var one := EIWaterWaves.new(); var many := EIWaterWaves.new()
	one.advance(12.345)
	for i in 12345: many.advance(0.001)
	var a := Wind.sample(one.time_ticks()*EIWaterWaves.TICK,seed_value,Vector2.ZERO,one.force)
	var b := Wind.sample(many.time_ticks()*EIWaterWaves.TICK,seed_value,Vector2.ZERO,many.force)
	check((a.phases as Vector4).is_equal_approx(b.phases) and (a.state as Vector4).is_equal_approx(b.state),"frame partition does not change the wind")
	var weather := Weather.new(null,null)
	for mode in [1,2]:
		weather._shown=mode; weather._target=mode; weather._start=10; weather._fade=20
		for row in [[0.0,0.0],[10.0,0.0],[20.0,0.5],[30.0,1.0],[40.0,1.0]]:
			check(is_equal_approx(Wind.precipitation(weather,row[0],mode),row[1]),"rain/snow fade in")
		weather._target=0
		for row in [[10.0,1.0],[20.0,0.5],[30.0,0.0],[40.0,0.0]]:
			check(is_equal_approx(Wind.precipitation(weather,row[0],mode),row[1]),"rain/snow fade out")
		weather._shown=0; weather._fade=0
		check(Wind.precipitation(weather,40,mode)==0,"completed fade endpoint")
	rows.append({"case":"pure","sampled_frames":1000,"max_analytic_sway_m":maximum})

func attach_world(game: Game) -> GameWorld:
	var world := GameWorld.new(); game.add_child(world)
	world.set_process(false); world.set_physics_process(false); world.process_mode=Node.PROCESS_MODE_PAUSABLE
	var map := EIMapScene.new(); world.add_child(map); world.map=map
	var terrain := terrain_fixture(); terrain.map_name="zone1"; map.add_child(terrain)
	map.terrain=terrain; world.terrain=terrain
	return world

func make_game(parent: Node) -> Game:
	var game := QuietGame.new(); parent.add_child(game)
	game.sound=GameSound.new(); game.world=attach_world(game)
	game.sound.weather=Weather.new(null,game.world)
	return game

func owners() -> void:
	var game := make_game(self); var terrain := game.world.terrain; terrain.set_process(false)
	var base := terrain.wind_frame(); var water := [terrain._waves.phase,terrain._waves.amplitude,terrain._waves.gradient]
	game.sound.weather._shown=1; game.sound.weather._target=1
	check(terrain.wind_frame()==base,"weather cannot move a held terrain clock")
	terrain._waves.advance(0.055); var rain := terrain.wind_frame()
	check((rain.state as Vector4).z>(base.state as Vector4).z,"current world rain raises the drive")
	check(terrain._waves.amplitude==water[1] and terrain._waves.gradient==water[2],"visual storm leaves original water wind intact")
	var hidden := attach_world(game); hidden.visible=false; hidden.terrain.set_process(false)
	game.sound.weather.world=hidden; terrain._waves.advance(0.055)
	var dry := Wind.sample(terrain._waves.time_ticks()*EIWaterWaves.TICK,Wind.map_seed("zone1"),Vector2.ZERO,terrain._waves.force)
	check(terrain.wind_frame()==dry,"old-world rain cannot reach the new terrain")
	terrain._update_wind_parameters()
	var sentinel := Wind.sample(4,1,Vector2.LEFT,0.2,1)
	var current_pixels := await global_pixels() if witness else PackedByteArray()
	Gfx.set_wind_frame(sentinel)
	var sentinel_pixels := await global_pixels() if witness else PackedByteArray()
	if witness: check(current_pixels!=sentinel_pixels,"GPU witness detects a different world wind")
	hidden.terrain._update_wind_parameters()
	if witness: check(await global_pixels()==sentinel_pixels,"hidden world cannot publish foliage wind")
	hidden.visible=true; hidden.terrain._update_wind_parameters()
	if witness: check(await global_pixels()==sentinel_pixels,"non-current world cannot publish even when visible")
	game.simulation_only=true; terrain._update_wind_parameters()
	if witness: check(await global_pixels()==sentinel_pixels,"server-only view cannot publish foliage wind")
	game.simulation_only=false; game.sound.weather.world=game.world
	GameData.options["gfx_wind"]=0; terrain._waves.advance(2); terrain.apply_gfx()
	if witness: check(await global_pixels()==sentinel_pixels,"disabled wind leaves the cached global state alone")
	var toggle_frame := terrain.wind_frame(); Gfx.set_wind_frame(toggle_frame)
	var toggle_pixels := await global_pixels() if witness else PackedByteArray()
	Gfx.set_wind_frame(sentinel); GameData.options["gfx_wind"]=1
	get_tree().paused=true; terrain.apply_gfx()
	if witness: check(await global_pixels()==toggle_pixels,"enabling wind while paused publishes the current terrain sample")
	get_tree().paused=false
	game.world.zone["sky"]="cave"; terrain._waves.advance(0.055)
	var cave := terrain.wind_frame()
	check((cave.state as Vector4).z<0.2,"cave wind is sheltered")
	game.sound.weather._shown=0; game.sound.weather._target=0
	terrain._wind_key.clear(); check(terrain.wind_frame()==cave,"cave ignores a scripted storm")
	game.sound.free(); game.free()
	var menu := MenuScene.new(); menu.set_process(false)
	var map := EIMapScene.new(); map.process_mode=Node.PROCESS_MODE_DISABLED; menu.add_child(map)
	var t := EITerrain.new(); t.map_name="zonemainmenunew"; map.add_child(t); t.set_process(false)
	map.terrain=t
	menu.sound.weather=Weather.new(null,null); menu.sound.weather._shown=2; menu.sound.weather._target=2
	var expected := Wind.sample(0,Wind.map_seed(t.map_name),Vector2.ZERO,t._waves.force,0,1)
	Gfx.set_wind_frame(expected)
	var expected_pixels := await global_pixels() if witness else PackedByteArray()
	if witness: check(expected_pixels!=sentinel_pixels,"menu witness distinguishes outgoing and incoming wind")
	Gfx.set_wind_frame(sentinel)
	add_child(menu)
	check(t.wind_frame()==expected,"menu gets its own snow/wind state after gameplay")
	if witness: check(await global_pixels()==expected_pixels,"real menu ready publishes before the first clock tick")
	menu.free()
	rows.append({"case":"ownership","rain":rain.state,"dry":dry.state,"cave":cave.state})

func held(t: EITerrain,view: SubViewport,label: String) -> void:
	var before := t._waves.time_ticks(); var frame := t.wind_frame()
	var a: Image = await snap(view,label) if view else null
	await frames(30)
	check(t._waves.time_ticks()==before and t.wind_frame()==frame,label+" holds the owning terrain clock and wind")
	if view:
		var difference := delta(a,await snap(view,label+"-later"))
		check(difference.changed==0,label+" holds the rendered tree")
		rows.append({"case":label,"difference":difference})

func live() -> void:
	var view: SubViewport
	if DisplayServer.get_name()!="headless":
		view=SubViewport.new(); view.size=Vector2i(512,512); view.own_world_3d=true
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; view.positional_shadow_atlas_size=1024; add_child(view)
	var game := make_game(view if view else self); var world := game.world; var t := world.terrain
	t.set_process(false); t._update_wind_parameters()
	if view:
		var tree := EIFigure.instantiate("nafltr56","tree02",Vector3(0.5,0.5,0.5),PackedStringArray(),false,true)
		world.add_child(tree); tree.position=Vector3(16,0,-16)
		var floor_mesh := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size=Vector2(30,30)
		floor_mesh.mesh=plane; floor_mesh.material_override=base_material(false); floor_mesh.position=tree.position; view.add_child(floor_mesh)
		var light := OmniLight3D.new(); light.position=tree.position+Vector3(4,9,6)
		light.omni_range=25; light.omni_attenuation=0; light.light_energy=0.7; light.light_specular=Gfx.LOCAL_SPECULAR
		view.add_child(light); Gfx.set_local_shadow(light,true)
		var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); view.add_child(sun)
		var environment := WorldEnvironment.new(); environment.environment=Environment.new(); Gfx.setup_original_env(environment.environment)
		environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color(0.15,0.2,0.25); view.add_child(environment)
		var camera := Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=11
		view.add_child(camera); camera.position=tree.position+Vector3(8,7,12); camera.look_at(tree.position+Vector3(0,3,0)); camera.current=true
		await frames(120); var zero := await snap(view,"zero")
		check(delta(zero,await snap(view,"zero-stable")).changed==0,"unchanged terrain time is visibly stable")
		t._waves.advance(7); t._update_wind_parameters()
		var difference := delta(zero,await snap(view,"seven-seconds"))
		check(difference.over_2>20,"terrain time moves the real authored tree")
		rows.append({"case":"tree-motion","difference":difference})
		var moved := await snap(view,"before-shadow-refresh")
		world.remove_child(tree); world.add_child(tree)
		check(delta(moved,await snap(view,"shadow-refresh")).changed==0,"animated foliage shadows match forced refresh")
		t._waves=EIWaterWaves.new(); t._update_wind_parameters()
		var reset := delta(zero,await snap(view,"reset"))
		rows.append({"case":"reset","difference":reset})
		check(reset.changed==0,"resetting terrain clock exactly restores tree and shadows")
	Engine.time_scale=1; t.set_process(true)
	get_tree().paused=true; await held(t,view,"tree-pause"); get_tree().paused=false
	world.process_mode=Node.PROCESS_MODE_DISABLED; await held(t,view,"inactive-world")
	world.process_mode=Node.PROCESS_MODE_PAUSABLE
	var session := Session.new(); world.session=session
	session.lmp_travel=preload("res://src/game/lmp_travel.gd").new(session)
	if view:
		Gfx.set_wind_frame(t.wind_frame()); var expected_pixels := await global_pixels()
		Gfx.set_wind_frame(Wind.sample(90,43,Vector2.LEFT,1,1))
		t._process(1)
		check(await global_pixels()==expected_pixels,"held arrival replaces the previous view's wind without ticking")
	await held(t,view,"lmp-hold"); world.session=null; session.free()
	var elapsed := []
	for scale: float in [1.0,2.0]:
		Engine.time_scale=scale; await frames(4); var start := t._waves.time_ticks()
		await get_tree().create_timer(0.3,true,false,true).timeout
		elapsed.append((t._waves.time_ticks()-start)*EIWaterWaves.TICK)
	check(elapsed[0]>0.25 and elapsed[1]/elapsed[0]>1.7 and elapsed[1]/elapsed[0]<2.3,"game speed scales the shared wind clock")
	rows.append({"case":"clock","elapsed":elapsed})
	t.set_process(false); Engine.time_scale=0
	game.sound.free()
	if view: view.free()
	else: game.free()
	await frames()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for key in ["gfx_hd_textures","gfx_volumetric","gfx_terrain","gfx_soft_ground","gfx_weather_surfaces","gfx_materials","gfx_grass","gfx_biome_cover","confine_mouse","vsync"]: GameData.options[key]=0
	GameData.options["gfx_wind"]=1; EIFigure.set_wind(true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	Engine.max_fps=120; Engine.time_scale=0; RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals()
	Gfx.set_light(Color(0.3,0.3,0.3),Color(0.6,0.6,0.6))
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",Vector3(0.4,0.7,0.5).normalized())
	setup_witness(); pure(); await owners(); await live()
	if witness: witness.free()
	TexUpscale.shutdown(); await frames()
	FileAccess.open("user://weather-wind.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("WEATHER_WIND checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

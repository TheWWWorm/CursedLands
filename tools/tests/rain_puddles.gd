extends Node
var checks := 0
var failures := 0
var view: SubViewport
var terrain: EITerrain
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)
func capture(name: String, wet: float, enabled: bool) -> PackedByteArray:
	GameData.options.gfx_rain_puddles=int(enabled)
	Gfx.apply_surface_options(); Gfx.set_surface_weather(wet,wet)
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	image.save_png("user://puddles-"+name+".png")
	return image.get_data()
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"gfx_original":0,"gfx_materials":1,"gfx_weather_surfaces":1,"gfx_water":0,"gfx_grass":0,"gfx_taa":0,"gfx_clouds":0},true)
	Gfx.ensure_globals()
	view=SubViewport.new(); view.size=Vector2i(800,600); view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var campaign:=CampaignMap.load_from(GameData.texts)
	terrain=EITerrain.load_map(campaign.zone("gz1h").mpr)
	if terrain==null: printerr("FAIL original terrain loads");get_tree().quit(1);return
	view.add_child(terrain);terrain.set_process(false)
	var point:=Vector3(24,terrain.height_at(24,430),-430)
	var camera:=Camera3D.new(); view.add_child(camera)
	camera.position=point+Vector3(0,14,12); camera.look_at(point); camera.make_current()
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment); view.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); view.add_child(sun)
	Gfx.set_light(Color(0.6,0.6,0.6),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var off:=await capture("wet-off",1.0,false)
	var on:=await capture("wet-on",1.0,true)
	var restored:=await capture("wet-restored",1.0,false)
	var dry:=await capture("dry-off",0.0,false)
	var dry_on:=await capture("dry-on",0.0,true)
	check(on!=off,"puddles are visible on actual rain-soaked LiA terrain")
	check(off==restored,"turning puddles off restores ordinary wet terrain exactly")
	check(dry==dry_on,"dry terrain stays pixel-identical with puddles enabled")
	var roof:=Image.create(terrain.sectors_x*EITerrain.SECTOR,terrain.sectors_y*EITerrain.SECTOR,false,Image.FORMAT_RF)
	roof.fill(Color(10000,0,0));terrain.set_rain_cover(roof)
	var sheltered:=await capture("sheltered-off",1.0,false)
	check(sheltered==await capture("sheltered-on",1.0,true),"sheltered ground never collects rain puddles")
	var wet:=0.0
	for i in 18:wet=SurfaceWeather.advance_wetness(wet,1.0,1.0)
	check(is_equal_approx(wet,1.0),"rain accumulates over time")
	for i in 80:wet=SurfaceWeather.advance_wetness(wet,0.0,1.0)
	check(is_zero_approx(wet),"puddles dry after rainfall")
	print("RAIN_PUDDLES ",checks," checks ",failures," failures")
	view.free(); get_tree().quit(1 if failures else 0)

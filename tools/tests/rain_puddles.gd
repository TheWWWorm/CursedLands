extends Node
var checks := 0
var failures := 0
var view: SubViewport
var terrain: EITerrain
var rows := []
func difference(a: PackedByteArray, b: PackedByteArray) -> Dictionary:
	var changed := 0; var readable := 0; var peak := 0
	for i in range(0,a.size(),4):
		var d := maxi(absi(a[i]-b[i]),maxi(absi(a[i+1]-b[i+1]),absi(a[i+2]-b[i+2])))
		changed += int(d>2); readable += int(d>12); peak=maxi(peak,d)
	return {"pixels_over_2":changed,"pixels_over_12":readable,"peak":peak}
func site() -> Vector2:
	var best := Vector2(24,430); var score := -INF
	var size := terrain.size_ei()
	for y in range(16,int(size.y)-16,8):
		for x in range(16,int(size.x)-16,8):
			var suitable := 0
			for dy in [-4,0,4]:
				for dx in [-4,0,4]:
					var p := Vector2(x+dx,y+dy)
					var h := terrain.height_at(p.x,p.y)
					if terrain.ground_type(p.x,p.y) in [0,5,9,10,11,12,13]:continue
					if terrain.water_at(p.x,p.y)>h-.1:continue
					if absf(terrain.height_at(p.x+.5,p.y)-terrain.height_at(p.x-.5,p.y))>.1:continue
					if absf(terrain.height_at(p.x,p.y+.5)-terrain.height_at(p.x,p.y-.5))>.1:continue
					suitable+=1
			var value := suitable-Vector2(x,y).distance_to(size*.5)*.0001
			if value>score:score=value;best=Vector2(x,y)
	return best
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)
func capture(name: String, wet: float, enabled: bool, rain := -1.0) -> PackedByteArray:
	GameData.options.gfx_rain_puddles=int(enabled)
	Gfx.apply_surface_options(); Gfx.set_surface_weather(wet,wet if rain<0.0 else rain)
	terrain.apply_gfx()
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png("user://puddles-"+name+".png")
	return image.get_data()
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"gfx_original":0,"gfx_materials":1,"gfx_weather_surfaces":1,"gfx_water":0,"gfx_grass":0,"gfx_taa":0,"gfx_clouds":0},true)
	Gfx.ensure_globals()
	view=SubViewport.new(); view.size=Vector2i(800,600); view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var campaign:=CampaignMap.load_from(GameData.texts)
	var map_name := String(campaign.zone("gz1h").get("mpr",""))
	var automatic_site := false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_name=arg.trim_prefix("--map=");automatic_site=true
		if arg.begins_with("--terrain-detail="):GameData.options.gfx_terrain=int(arg.trim_prefix("--terrain-detail="))
	terrain=EITerrain.load_map(map_name)
	if terrain==null: printerr("FAIL original terrain loads");get_tree().quit(1);return
	view.add_child(terrain);terrain.set_process(false)
	var at:=site() if automatic_site else Vector2(24,430)
	var point:=Vector3(at.x,terrain.height_at(at.x,at.y),-at.y)
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
	check(terrain._land_mat.get_shader_parameter("macro_tex")!=null,"puddle depressions have their texture independently of terrain detail")
	var after_rain:=await capture("after-rain",1.0,true,0.0)
	var drying:=await capture("drying",0.65,true,0.0)
	var restored:=await capture("wet-restored",1.0,false)
	var dry:=await capture("dry-off",0.0,false)
	var dry_on:=await capture("dry-on",0.0,true)
	var visible := difference(on,off)
	check(int(visible.pixels_over_2)>100,"puddles visibly affect exposed terrain")
	check(int(visible.pixels_over_12)>1000,"pooled water has readable contrast from the normal isometric camera")
	check(int(visible.pixels_over_2)<view.size.x*view.size.y/10,"standing water stays sparse in the isometric view at full wetness")
	check(after_rain==on,"puddles remain when rain stops and accumulated wetness remains")
	check(drying!=off and drying!=after_rain,"puddles recede gradually as the ground dries")
	check(off==restored,"turning puddles off restores ordinary wet terrain exactly")
	check(dry==dry_on,"dry terrain stays pixel-identical with puddles enabled")
	camera.position=point+Vector3(0,2.5,12); camera.look_at(point)
	var low_off:=await capture("low-wet-off",1.0,false,0.0)
	var low_on:=await capture("low-after-rain",1.0,true,0.0)
	var low_visible:=difference(low_on,low_off)
	check(int(low_visible.pixels_over_2)>100,"puddles remain visible from a shallow viewing angle")
	camera.position=point+Vector3(0,14,12); camera.look_at(point)
	var macro:Texture2D=terrain._land_mat.get_shader_parameter("macro_tex")
	macro.get_image().save_png("user://puddles-noise.png")
	var roof:=Image.create(terrain.sectors_x*EITerrain.SECTOR,terrain.sectors_y*EITerrain.SECTOR,false,Image.FORMAT_RF)
	roof.fill(Color(10000,0,0));terrain.set_rain_cover(roof)
	var sheltered:=await capture("sheltered-off",1.0,false)
	check(sheltered==await capture("sheltered-on",1.0,true),"sheltered ground never collects rain puddles")
	var wet:=0.0
	for i in 18:wet=SurfaceWeather.advance_wetness(wet,1.0,1.0)
	check(is_equal_approx(wet,1.0),"rain accumulates over time")
	for i in 80:wet=SurfaceWeather.advance_wetness(wet,0.0,1.0)
	check(is_zero_approx(wet),"puddles dry after rainfall")
	FileAccess.open("user://rain-puddles.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"map":map_name,"site":str(at),"detail":GameData.option("gfx_terrain"),"visible":visible,"low_visible":low_visible,"after_rain_equal":after_rain==on,"drying":difference(drying,after_rain)},"\t"))
	print("RAIN_PUDDLES ",checks," checks ",failures," failures")
	view.free(); get_tree().quit(1 if failures else 0)

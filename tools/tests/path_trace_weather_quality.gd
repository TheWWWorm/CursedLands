extends "res://tools/tests/path_trace_camera_routes.gd"
## Moving, textured first-person terrain and rain at the reported Low setting.
func run() -> void:
	map_name="zone1";resolution=Vector2i(1920,1080)
	var context:=await setup_route()
	if context.is_empty():get_tree().quit(1);return
	var session: Session=context[0];var game: Game=context[1]
	var rt: Node=game.get_node("SceneRaytrace")
	var leader: GameUnit=game.direct.leader()
	check(leader!=null,"ruins supplies a player for the eye camera")
	if leader==null:get_tree().quit(1);return
	var diagnostic:=camera
	camera=game.rig.camera;camera.make_current();diagnostic.queue_free()
	game.direct._set_view_mode(3);game.direct.tilt=-0.12;game.direct.apply_camera()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	check(await ready_scene(rt),"ruins first person prepares")
	print("QUALITY_CAMERA ",camera.global_transform)
	for weather in [0,1]:
		game.sound.weather.on_event({"w":weather,"fade":0.0},game.sound._ticks)
		game._update_daylight(false)
		await frames(32)
		for i in 8:await frames(1);await save_buffers(rt,"weather%d-held%02d"%[weather,i])
		print("QUALITY_WEATHER ",weather," ",Gfx.sun," ",Gfx.ambient," ",rt.stats)
	var original:=camera.global_transform
	var rain_energy:=Gfx.sun.srgb_to_linear().r
	if rt.device.frame_bytes()>=752:check(rain_energy<0.2,"actual rain reaches the shared scene lighting")
	for i in 120:
		camera.global_transform=original
		camera.global_position+=original.basis.x*(sin(float(i)*0.02)*2.0)
		camera.rotate_y(sin(float(i)*0.025)*0.25)
		session.state.world_time+=1.0/30.0/60.0;game._update_daylight(false)
		await frames(1);observe(rt,"moving")
		if i in [20,40,60,80,100,119]:await save_buffers(rt,"motion-%03d"%i)
	await receiver_coverage()
	if rt.device.frame_bytes()>=752:
		for cloud_mode in [1,2,0]:
			GameData.options.gfx_clouds=cloud_mode;GameData.options.gfx_cloud_shadows=1;t.apply_gfx()
			game._update_daylight(false)
			check(await ready_scene(rt),"cloud mode settles with PT: %d"%cloud_mode)
			await frames(12)
			var cloud: PackedFloat32Array=rt._path_cloud_frame()
			check(int(cloud[3])==cloud_mode,"shared cloud field reaches PT mode %d"%cloud_mode)
			await shot("cloud-mode-%d"%cloud_mode)
		# Keep accumulating through the actual twenty-world-tick precipitation fade.
		game.sound.set_process(false)
		game.sound.weather.on_event({"w":0,"fade":20.0},game.sound._ticks)
		var resets:=0
		for i in 90:
			game.sound._tick_acc+=1.0/30.0;game._update_daylight(false)
			game.sound.weather.tick(game.sound._ticks+game.sound._tick_acc/GameSound.TICK)
			await frames(1)
			if not rt.stats.get("history_reused",false):resets+=1
		check(resets<4,"rain fade preserves responsive history: %d resets"%resets)
		check(rt.stats.get("active",false),"cloud and weather transitions keep PT active")
	FileAccess.open(out.path_join("weather-quality.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples,"coverage":receiver_counts,"stats":rt.stats},"\t"))
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)

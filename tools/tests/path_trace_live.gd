extends "res://tools/tests/scene_raytrace_live.gd"
const PathDevice = preload("res://src/game/fx/path_trace_device.gd")
func run() -> void:
	var context:=await setup();var game: Game=context[1]
	GameData.options.gfx_water_reflections=0;GameData.options.rt_shadows=0;GameData.options.rt_gi=0;t.apply_gfx()
	await get_tree().create_timer(0.3,true,false,true).timeout
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	await get_tree().create_timer(2.0,true,false,true).timeout
	var rt: Node=game.get_node("SceneRaytrace")
	var original:=await capture("river-conventional")
	check(not Gfx.path_trace_active and game._env.tonemap_mode==Environment.TONE_MAPPER_LINEAR,"conventional campaign retains original exposure")
	GameData.options.pt_mode=1;GameData.options.q_rt_lighting=1;Gfx.apply_env(game._env)
	check(await ready_scene(rt),"path tracing prepares with both old RT toggles off")
	if rt.stats.get("active",false):
		check(rt.device is PathDevice,"main view uses the multi-bounce pipeline")
		check(Gfx.path_trace_active and game._env.tonemap_mode==Environment.TONE_MAPPER_AGX,"working path output enables the HDR display profile")
		check(rt.stats.path_tracing and rt.stats.path_bounces==2,"two-bounce mode reaches the runtime")
		await get_tree().create_timer(2.0,true,false,true).timeout
		var two:=await capture("river-path-2")
		check(mean_difference(original,two)>0.005,"path lighting replaces the actual world lighting")
		var responsive_pose:=camera.global_transform;camera.rotate_y(0.01);await frames(2)
		var moving_frame: PackedByteArray=rt._frame(camera,Vector2i(960,540),1)
		check(moving_frame.decode_float(82*4)>0.5,"responsive mode retains reprojection through small camera motion")
		var original_fov:=camera.fov;camera.fov+=1.0
		var zoom_frame: PackedByteArray=rt._frame(camera,Vector2i(960,540),1)
		check(zoom_frame.decode_float(82*4)<0.5,"projection changes invalidate responsive history")
		camera.fov=original_fov
		camera.global_transform=responsive_pose;await frames(12)
		var device: Object=rt.device
		GameData.options.pt_mode=2;GameData.options.pt_accumulation=1;await frames(80)
		check(rt.device==device and rt.stats.path_bounces==4,"four-bounce mode reuses scene resources")
		check(rt.stats.accumulation_frames>60,"frozen outdoor scene accumulates progressively: "+str(rt.stats))
		var four:=await capture("river-path-4-still")
		check(mean_difference(two,four)>0.0001,"four-bounce accumulated view changes the image")
		var pose:=camera.global_transform;camera.rotate_y(0.04);await frames(2)
		check(rt.stats.accumulation_frames<=3,"camera motion resets progressive history")
		camera.global_transform=pose;await frames(12)
		check(rt.stats.accumulation_frames>=8,"stationary camera starts accumulating again")
		GameData.options.q_rt_lighting=0;await frames(4)
		check(rt.stats.size==[640,360] and rt.stats.accumulation_frames<=5,"quality resize resets accumulation and follows window dimensions")
		GameData.options.pt_mode=0;Gfx.apply_env(game._env);await frames(20)
		check(rt.device==null and not rt.stats.active,"turning path tracing off releases its resources")
		check(not Gfx.path_trace_active and game._env.tonemap_mode==Environment.TONE_MAPPER_LINEAR and game._env.tonemap_exposure==1,"turning path tracing off restores original display and exposure")
		var restored:=await capture("river-restored")
		check(mean_difference(original,restored)<0.005,"turning off restores the original lighting image")
	FileAccess.open(out.path_join("path-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":rt.stats},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_TRACE_LIVE ",checks," checks ",failures.size()," failures");get_tree().quit(1 if not failures.is_empty() else 0)

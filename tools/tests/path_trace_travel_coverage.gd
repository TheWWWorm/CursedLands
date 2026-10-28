extends "res://tools/tests/water_raytrace_artifact.gd"
## Fresh LiA gz3h at the user's doorway camera. A 140 m / 60 frame traverse
## deliberately outruns the old 1.5 ms gather and sixteen-BLAS-per-frame build.
## Fixed daylight and held end pose separate streaming from time-of-day changes.
var use_rr:=false
var night:=false
var output_size:=Vector2i(1920,1080)
var travel_rows: Array[Dictionary]=[]

func detail(image: Image) -> float:
	# Bare soil below/right of the doorway, away from cacti, actors and the HUD.
	var size:=image.get_size();var energy:=0.0;var mean:=0.0;var count:=0
	for y in range(int(size.y*.46),int(size.y*.59)):
		for x in range(int(size.x*.45),int(size.x*.58)):
			var c:=image.get_pixel(x,y);var a:=image.get_pixel(x+1,y);var b:=image.get_pixel(x,y+1)
			energy+=absf(c.g-a.g)+absf(c.g-b.g);mean+=c.g;count+=1
	return energy/maxf(mean*2.0,.00001)

func native() -> Dictionary:
	return RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge()!=null else {}

func ground_colour(image: Image) -> Vector3:
	# Broad bare ground in the night route; excludes the moving actors and sky.
	var size:=image.get_size();var colour:=Vector3.ZERO
	for y in range(int(size.y*.6),int(size.y*.85),3):
		for x in range(int(size.x*.45),int(size.x*.7),3):
			var c:=image.get_pixel(x,y);colour+=Vector3(c.r,c.g,c.b)
	return colour/maxf(colour.x+colour.y+colour.z,.00001)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		elif arg=="--travel-rr":use_rr=true
		elif arg=="--travel-night":night=true
		elif arg=="--travel-4k":output_size=Vector2i(3840,2160)
	DirAccess.make_dir_recursive_absolute(out)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"q_aa":0,"q_shadows":2,"q_aniso":4,"vsync":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"gfx_terrain":1,"gfx_materials":1,"gfx_sky":1,"gfx_terrain_cliffs":1,"gfx_depth_of_field":0,
		"autosave":0,"show_tutorial":0,"unit_fog":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"pt_mode":0,"rt_shadows":0,"rt_gi":0,"pt_accumulation":0,"pt_sharc":0,"pt_restir":0,"pt_refraction":0,
		"q_rt_lighting":0,"pt_ray_reconstruction":int(use_rr),"rtx_upscaling":4 if use_rr else 0,
		"rtx_frame_generation":0,"fsr_upscaling":0,"fsr_frame_generation":0,"render_scale":4},true)
	GameData.resolution_size="%dx%d"%[output_size.x,output_size.y];GameData.options.resolution=GameData.resolutions().find(output_size)
	GameData._apply_window();Engine.max_fps=30;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var session:=Session.new();add_child(session)
	var game:=Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0));session.state.world_time=.2 if night else 12.0
	session._enter_zone("gz3h",1,false);session.set_physics_process(false)
	session.world.vm.instances.clear();game.direct.set_process(false)
	game.hud.hide();game.hud.process_mode=Node.PROCESS_MODE_DISABLED
	camera=game.rig.camera;camera.fov=55
	var destination:=Vector3(95.1568603515625,19.3930511474609,-170.164657592773)
	var start_rotation:=Vector3(-.557967960834503,.740298569202423,0)
	var end_rotation:=start_rotation
	var start:=destination+Vector3(140,0,0)
	if night:
		start=Vector3(380.195434570313,68.7970733642578,-30.5365180969238)
		destination=Vector3(291.292266845703,16.6690902709961,-46.170093536377)
		start_rotation=Vector3(-1.04357123374939,.188298419117928,0)
		end_rotation=Vector3(-.45773920416832,1.2862982749939,0)
	var direction:=-Basis.from_euler(start_rotation).z
	game.rig.hold_view(start,start+direction*30.0)
	for unit: GameUnit in session.world.units.values():
		unit.orders.clear();unit.order={};unit._perceive_next=INF;unit.ai_next=INF;unit.action="idle"
	t=session.world.terrain;GameData.options.pt_mode=1;game._apply_options()
	await frames(20);GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED
	get_window().borderless=true;get_window().size=output_size;RtxGraphics.apply_upscaling(get_window())
	var rt: Node=game.get_node("SceneRaytrace");var stable:=0
	for i in 1800:
		await frames(1)
		if rt.stats.get("active",false) and not rt.stats.get("rebuilding",false):stable+=1
		else:stable=0
		if stable>=12:break
	check(stable>=12,"reported LiA area reaches a complete initial PT scene")
	check(get_window().size==output_size,"travel comparison uses the recorded native output size: "+str(get_window().size))
	if use_rr:check(rt._rr_active and native().get("rr_active",false),"native RR is running before travel")
	if stable<12:await finish_travel(session,game);return
	var initial: int=rt._snapshot_generation;var first_promotion:=-1;var active:=0;var eye_error:=0.0
	var moving: Image;var held: Image;var before:=native();var completion_centre:=Vector3.INF
	for i in 151:
		# Match the game rig's update phase: set the pose before the controller
		# at priority 101 queues its trace, never from the previous draw callback.
		await get_tree().process_frame
		var amount:=minf(float(i)/60.0,1.0)
		var position:=start.lerp(destination,amount)
		direction=-Basis.from_euler(start_rotation.lerp(end_rotation,amount)).z
		game.rig.hold_view(position,position+direction*30.0)
		await RenderingServer.frame_post_draw
		eye_error=maxf(eye_error,camera.global_position.distance_to(rt._previous_camera.origin))
		if rt.stats.get("active",false) and Gfx.path_trace_active:active+=1
		if rt._snapshot_generation>initial and first_promotion<0:first_promotion=i
		travel_rows.append({"frame":i,"generation":rt._snapshot_generation,"centre":str(rt._center),
			"distance":camera.global_position.distance_to(rt._center),"active":rt.stats.get("active",false),
			"gather_cursor":rt._gather._cursor if rt._gather!=null else -1,
			"pending_stage":rt._pending_stage,"pending_ready":rt._pending_ready,
			"build_cursor":rt._pending_device._build_cursor if rt._pending_device!=null else -1,
			"resource_stage":rt._pending_device._build_resource_stage if rt._pending_device!=null else -1,
			"building":rt.stats.get("rebuilding",false),"stats":rt.stats.duplicate(true) if i in [60,90,120,150] else {}})
		if i==60:moving=get_viewport().get_texture().get_image();moving.save_png(out.path_join("moving-end.png"))
		if i==90:held=get_viewport().get_texture().get_image();held.save_png(out.path_join("held.png"))
		if i==60:completion_centre=rt._center
	check(active==151,"PT remains active throughout travel and the held destination")
	check(eye_error<.001,"captured camera and queued trace use the same movement update (%.6f)"%eye_error)
	check(first_promotion>=0 and first_promotion<=60,"replacement catches the camera before the route ends (%d)"%first_promotion)
	check(completion_centre.distance_to(destination)<=32.0,"destination has complete near-field coverage when travel ends")
	check(not rt.stats.has("replacement_failure"),"travel does not exceed snapshot or native resource budgets")
	if night:
		var colour_shift:=ground_colour(moving).distance_to(ground_colour(held))
		check(colour_shift<.04,"held night ground does not switch from conventional brown to PT purple (%.6f)"%colour_shift)
		rows.append({"moving_colour":str(ground_colour(moving)),"held_colour":str(ground_colour(held)),"colour_shift":colour_shift})
	if use_rr:
		var after:=native();var resets:=int(after.get("rr_resets",0))-int(before.get("rr_resets",0))
		check(int(after.get("rr_evaluations",0))-int(before.get("rr_evaluations",0))>=140,"native RR evaluates the whole route")
		check(resets<=2,"continuous travel avoids repeated native RR resets (%d)"%resets)
		var moving_detail:=detail(moving);var held_detail:=detail(held)
		check(held_detail>.002,"held soil contains measurable texture detail")
		check(moving_detail>=held_detail*.70,"moving soil retains its fine pattern (%.6f / %.6f)"%[moving_detail,held_detail])
		rows.append({"before":before,"after":after,"moving_detail":moving_detail,"held_detail":held_detail})
	# A player can stop before reaching a predicted region. Do not publish a
	# complete but distant snapshot over a still-valid nearby scene.
	for i in 8:
		await get_tree().process_frame
		var position:=destination+Vector3((i+1)*1.5,0,0)
		game.rig.hold_view(position,position+direction*30.0);await RenderingServer.frame_post_draw
	await frames(8)
	var pending: Object=rt._gather if rt._gather!=null else rt._pending_scene
	check(pending==null or pending.center.distance_to(camera.global_position)<=32.0,"stopping early cancels the distant prediction")
	check(rt.stats.get("active",false) and Gfx.path_trace_active,"stopping a predicted route keeps valid PT visible")
	FileAccess.open(out.path_join("travel.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"first_promotion":first_promotion,"frames":travel_rows,"rr":rows},"\t"))
	await finish_travel(session,game)

func finish_travel(session: Session,game: Game) -> void:
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	print("PT_TRAVEL_COVERAGE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)

extends Node
## Real solo tournament, including the round transition and all nine live boards.
var screen: ArenaPveScreen
var results := []
var seconds := 15.0
var profile := false
var cycles := 1
var wave := 12
var speed := 1
var diagnose := false
var round_transitions := false
var new_roster := false
var expanded_roster := false
var rank := 1
var overview := false
var scout := false
var disabled_gfx: Array[String] = []
var freeze_overlay := false
var skip_picking := false
var render_times := []
var render_started := 0

func frames(n := 1) -> void:
	for i in n: await get_tree().process_frame

func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate(); sorted.sort()
	var window := 0.0; var first := 0; var minimum := INF; var elapsed := 0.0; var minimum_at := 0.0
	for index in values.size():
		window += float(values[index]); elapsed += float(values[index])
		while first < index and window-float(values[first]) >= 1000.0:
			window-=float(values[first]); first+=1
		if window>=1000.0:
			var fps := 1000.0*(index-first+1)/window
			if fps < minimum: minimum = fps; minimum_at = elapsed / 1000.0
	return {"frames":values.size(), "fps":1000.0 * values.size() / values.reduce(func(a,b):return a+b,0.0), "min_1s_fps":minimum if minimum!=INF else null, "minimum_at_seconds":minimum_at, "median_ms":sorted[sorted.size()/2], "p95_ms":sorted[int(sorted.size()*0.95)], "p99_ms":sorted[int(sorted.size()*0.99)], "max_ms":sorted.back()}

func census() -> Dictionary:
	var clocks := []; var units := []; var effects := []; var profiles := []
	for battle: ArenaPveMatch in [screen.battle] + screen._tournament_battles.boards.values():
		clocks.append(battle.world.time)
		units.append(battle.world.unit_rows().size())
		var fx := battle.world.get_node_or_null("ParticleFx") as ParticleFx
		effects.append(fx.effects.size() if fx else 0)
		if profile: profiles.append(battle.world.profile_us.duplicate())
	return {"clocks":clocks,"time_scale":Engine.time_scale,"units":units,"effects":effects,"profiles":profiles,"pipelines":pipelines(),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}

func pipelines()->Array:
	var values:=[]
	for key in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		values.append(RenderingServer.get_rendering_info(key))
	return values

func callbacks() -> Array:
	var scripts := {}
	for node in get_tree().root.find_children("*", "", true, false):
		if node == self or not node.can_process() or not node.is_processing() or not node.has_method("_process"): continue
		var script: Script = node.get_script()
		if not script: continue
		var before := Time.get_ticks_usec()
		node.call("_process", 1.0/120.0)
		var key := script.resource_path
		if not scripts.has(key): scripts[key] = {"path":key,"us":0,"count":0}
		scripts[key].us += Time.get_ticks_usec()-before; scripts[key].count += 1
	var rows := scripts.values(); rows.sort_custom(func(a,b):return a.us>b.us)
	return rows.slice(0,20)

func diagnostic_frames() -> Dictionary:
	var samples := []; var gpu := []; var cpu := []; var previous := Time.get_ticks_usec()
	for i in 100:
		await frames(); var now := Time.get_ticks_usec()
		if i>20:
			samples.append((now-previous)/1000.0)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(screen.field.view.get_viewport_rid()))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(screen.field.view.get_viewport_rid()))
		previous=now
	return {"frames":stats(samples),"gpu":stats(gpu),"render_cpu":stats(cpu)}

func _ready() -> void: run.call_deferred()

func run() -> void:
	await frames(24)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds = float(arg.get_slice("=",1))
		if arg.begins_with("--cycles="): cycles = int(arg.get_slice("=",1))
		if arg.begins_with("--wave="): wave = int(arg.get_slice("=",1))
		if arg.begins_with("--speed="): speed = clampi(int(arg.get_slice("=",1)), 1, 2)
		if arg == "--profile-sim": profile = true
		if arg == "--diagnose": diagnose = true
		if arg == "--round-transitions": round_transitions = true
		if arg == "--new-roster": new_roster = true
		if arg == "--expanded-roster": expanded_roster = true
		if arg.begins_with("--rank="): rank = clampi(int(arg.get_slice("=",1)),0,2)
		if arg == "--overview": overview = true
		if arg == "--scout": scout = true
		if arg == "--freeze-overlay": freeze_overlay = true
		if arg == "--skip-picking": skip_picking = true
		if arg.begins_with("--disable-gfx="): disabled_gfx.assign(arg.get_slice("=",1).split(",",false))
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"display_mode":0,"pad_enabled":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	for option: String in disabled_gfx: GameData.options[option] = 0
	GameData._window_gen += 1; GameData.arena_mode = 1; GameData.arena_speed = speed
	Engine.max_fps = 0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(2560,1440)
	screen = ArenaPveScreen.new(); add_child(screen); await frames(8)
	if freeze_overlay: screen.field.set_process(false); screen.field.overlay.hide()
	if skip_picking: screen.field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if diagnose:
		RenderingServer.viewport_set_measure_render_time(screen.field.view.get_viewport_rid(),true)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
		RenderingServer.frame_pre_draw.connect(func(): render_started = Time.get_ticks_usec())
		RenderingServer.frame_post_draw.connect(func(): render_times.append((Time.get_ticks_usec()-render_started)/1000.0))
	screen._seed_input.text = "7319"; screen._begin(); screen.run.auto_save = false
	for cycle in cycles:
		print("SOLO_PREPARE_BEGIN ",cycle)
		var begin := Time.get_ticks_usec()
		screen.run.wave = wave + cycle; screen.run.stage = "prepare"; screen.run.lives = 100
		for player in 9:
			var company := (screen.run as ArenaTournamentRun).company(player)
			company.army.clear(); company.wave = screen.run.wave; company.training = 126
			company.gold = 50; company.auto_save = false; company.lives = company.life_limit()
			var families := [31,32,33,34,35,36,37,38,39] if expanded_roster else [24,25,26,27,28,29,22] if new_roster else [7,9,10,11,17,18,22]
			for family in families: company._recruit(family,rank,10)
			company.arrange()
		(screen.run as ArenaTournamentRun)._prepare_round()
		for plan: Dictionary in screen.run.bot_plans: plan.done = true
		screen._refresh(); screen._tournament_battles.synchronize()
		var prepare_ms := (Time.get_ticks_usec()-begin)/1000.0
		var pointer := screen.field.get_global_rect().get_center()
		Input.warp_mouse(pointer)
		var motion := InputEventMouseMotion.new(); motion.position = pointer
		Input.parse_input_event(motion)
		await frames(30)
		var before := census()
		var idle := []; var previous := Time.get_ticks_usec()
		for i in 120:
			await frames(); var now := Time.get_ticks_usec(); idle.append((now-previous)/1000.0); previous=now
		var samples := []; var transition := []; var slow_frames := []; var battle_gpu := []; var battle_cpu := []; var root_gpu := []
		begin = Time.get_ticks_usec(); previous=begin
		screen._tournament_battles.request_start()
		while screen.run.stage == "prepare":
			await frames(); var now := Time.get_ticks_usec(); transition.append((now-previous)/1000.0); previous=now
			if now-begin>60000000: push_error("Battle did not start"); get_tree().quit(1); return
		var start_ms := (Time.get_ticks_usec()-begin)/1000.0
		for battle: ArenaPveMatch in [screen.battle] + screen._tournament_battles.boards.values():
			battle.world.profile_simulation=profile
		if overview: screen._show_boards()
		var battle_start := census()
		var started := Time.get_ticks_usec(); previous=started
		render_times.clear()
		var next_scout := started + 4000000; var watched := 0
		while Time.get_ticks_usec()-started < int(seconds*1000000) and screen.run.stage == "fight":
			if scout and Time.get_ticks_usec() >= next_scout:
				watched = (watched + 1) % 9; screen._show_player(watched)
				next_scout += 4000000
			await frames(); var now := Time.get_ticks_usec(); samples.append((now-previous)/1000.0)
			if diagnose:
				battle_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(screen.field.view.get_viewport_rid()))
				battle_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(screen.field.view.get_viewport_rid()))
				root_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			if now-previous>25000: slow_frames.append({"at":(now-started)/1000000.0,"ms":(now-previous)/1000.0,"clock":screen.battle.world.time,"pipelines":pipelines()})
			previous=now
		var result := {"wave":screen.run.wave,"speed":speed,"rank":rank,"new_roster":new_roster,"expanded_roster":expanded_roster,"overview":overview,"scout":scout,"battle_start":battle_start,"window_size":str(get_window().size),"profile":profile,"prepare_ms":prepare_ms,"start_ms":start_ms,"idle":stats(idle),"transition":stats(transition),"battle":stats(samples),"before":before,"after":census(),"wall_seconds":(Time.get_ticks_usec()-started)/1000000.0,"slow_frames":slow_frames}
		if profile: result.callbacks = callbacks()
		result.disabled_gfx = disabled_gfx; result.frozen_overlay = freeze_overlay
		result.skip_picking = skip_picking
		result.diagnose = diagnose
		result.pointer = str(screen.field.pointer_position())
		if diagnose:
			result.render_wall = stats(render_times)
			result.battle_render = {"field_gpu":stats(battle_gpu),"field_cpu":stats(battle_cpu),"root_gpu":stats(root_gpu)}
			RenderingServer.viewport_set_measure_render_time(screen.field.view.get_viewport_rid(),true)
			for battle: ArenaPveMatch in [screen.battle] + screen._tournament_battles.boards.values(): battle.world.process_mode=Node.PROCESS_MODE_DISABLED
			result.frozen=await diagnostic_frames()
			screen.field.view.render_target_update_mode=SubViewport.UPDATE_DISABLED
			result.no_field=await diagnostic_frames()
		if round_transitions: result.next_round = await transition_round()
		results.append(result); print("SOLO_FRAME_TIME ",JSON.stringify(result))
		if cycle==0 and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://arena-solo.png")
		if not round_transitions:
			for battle: ArenaPveMatch in [screen.battle] + screen._tournament_battles.boards.values():
				battle.phase=ArenaMatch.Phase.FINISHED; battle.world.process_mode=Node.PROCESS_MODE_DISABLED
	FileAccess.open("user://arena-solo-frame-time.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	screen.queue_free(); await frames(6); TexUpscale.shutdown(); get_tree().quit()

func retired_resources() -> Array:
	var refs := []
	for battle: ArenaPveMatch in [screen.battle] + screen._tournament_battles.boards.values():
		refs.append(weakref(battle.world))
		for unit: GameUnit in battle.world.unit_rows(): refs.append(weakref(unit))
	return refs

func transition_round() -> Dictionary:
	if screen._tournament_battles is ArenaSoloBattles and screen.run.stage == "fight":
		# Short samples force local outcomes before native combat has ended.
		# Stop that same worker round too, matching a real settled transition;
		# otherwise the fixture benchmarks new preparation plus an old fight.
		var connection: ArenaOnlineSession = screen._tournament_battles.connection
		connection._send(1,{"t":"solo_clock","round":screen.run.wave,"paused":true,"speed":speed})
		await get_tree().create_timer(.1).timeout
	var refs := retired_resources()
	var terrains := ([screen.battle] + screen._tournament_battles.boards.values()).map(func(b):return b.world.terrain.get_instance_id())
	for battle: ArenaPveMatch in [screen.battle] + screen._tournament_battles.boards.values():
		if battle.phase == ArenaMatch.Phase.FIGHT:
			battle.world.process_mode = Node.PROCESS_MODE_DISABLED
			battle.phase = ArenaMatch.Phase.FINISHED; battle.winner = 0
			battle.finished.emit(0)
		battle.settle_remaining = 0.0
	screen._result_remaining = 1000.0
	await frames(3)
	if screen._tournament_battles is ArenaSoloBattles:
		screen.run.resolve(0,screen.battle.world.time,[0,0],[1,0])
		for player in screen.run.alive_players(): screen.run.record_board(player,0,[1,0])
	assert(screen.run.stage == "result", "Transition fixture must settle the actual run")
	var started := Time.get_ticks_usec()
	if diagnose: RenderingServer.viewport_set_measure_render_time(screen.field.view.get_viewport_rid(),true)
	screen.run.advance()
	var synchronous_ms := (Time.get_ticks_usec()-started)/1000.0
	var previous := started; var values := []
	var render_gpu:=[];var process:=[];var physics:=[]
	for i in 30:
		await frames(); var now := Time.get_ticks_usec()
		values.append((now-previous)/1000.0); previous = now
		if diagnose: render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(screen.field.view.get_viewport_rid()))
		process.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
	return {"synchronous_ms":synchronous_ms,"frames":stats(values),"render_gpu":stats(render_gpu),"process":stats(process),"physics":stats(physics),"callbacks":callbacks() if OS.get_cmdline_user_args().has("--arena-timing") else [],"retained_old_resources":refs.filter(func(r):return r.get_ref()!=null).size(),"tracked_resources":refs.size(),"reused_terrain":terrains == ([screen.battle] + screen._tournament_battles.boards.values()).map(func(b):return b.world.terrain.get_instance_id()),"after":census()}

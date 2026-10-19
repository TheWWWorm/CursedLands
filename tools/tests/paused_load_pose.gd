extends "local_host_campaign.gd"
## Real saved game through the same private authority used by solo play.
## Checks the displayed native pose while both gameplay clocks stay paused.
var session: Session
var game: Game

func assert_pose(gait: int, label: String) -> void:
	var units := session.party_units(0)
	check(not units.is_empty(),label+" restored hero exists")
	if units.is_empty(): return
	var u: GameUnit = units[0]
	var expected := EIUnitModel.ST_LIE if gait==0 else EIUnitModel.ST_WARRY if gait==1 else EIUnitModel.ST_NEUTRAL
	check(get_tree().paused,label+" gameplay remains paused")
	check(u.gait()==gait and u.model.pose_state==expected,label+" saved posture is already displayed")
	check(u.transform.basis.is_equal_approx(Basis(Vector3.UP,u.facing+GameUnit.MODEL_YAW_OFFSET)),label+" facing is already displayed")
	if DisplayServer.get_name()!="headless":
		check(await until(func():return LoadingScreen._current==null,10),"loading cover closes while gameplay stays paused")
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("user://paused-load-gait-%d.png"%gait)==OK,"capture paused posture before any manual evaluation")
	var helper := preload("paused_spawn_pose.gd").new()
	var before := helper.body_pose(u)
	u.model.player.advance(0.0)
	check(before==helper.body_pose(u),label+" no late pose correction at first animation evaluation")
	helper.free()
	check(u.model._resume.is_empty(),label+" no stance transition is queued")
	var time := session.world.time
	for i in 6: await get_tree().process_frame
	check(get_tree().paused and session.world.time==time,label+" inspecting the pose does not unpause simulation")

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,
		"control_mode":1,"autosave":0,"show_tutorial":0,"auto_graphics":0,"confine_mouse":0,"display_mode":0},true)
	if DisplayServer.get_name()!="headless":
		for i in 16: await get_tree().process_frame
		GameData._window_gen+=1
		get_window().mode=Window.MODE_WINDOWED
		for i in 8: await get_tree().process_frame
		get_window().size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	for gait: int in [0,1,2]:
		var state := CampaignState.new(); state.ensure_hero(0,"Human Hero"); state.current_zone="gz1g"
		state.heroes[0][0].gait=gait
		state.play_clock={"paused":true,"speed":gait%2}
		check(state.save(SaveInfo.path("paused-pose-"+str(gait)))==OK,"prepared saved gait "+str(gait))
	session=Session.new(); get_parent().add_child(session)
	game=Game.new(); game.session=session; session.game=game; get_parent().add_child(game)
	if not OS.get_cmdline_user_args().has("--in-process"):
		check(await session.local_host.start(0,1,true)==OK,"solo simulation worker starts")
	if failures: await finish(); return
	for gait: int in [0,1,2]:
		game.hud.log_msg("Discarded future loot: 40")
		session.state.money=9340
		game.hud.text_window.build_listing(9340,[])
		check(await session.load_game_shown("paused-pose-"+str(gait)),"paused solo save loads")
		check(await until(func():return session.world!=null and not session._remote_loading and not session.loading_game,30),"solo world arrives")
		await assert_pose(gait,"worker gait "+str(gait))
		check(game.speed==gait%2,"saved speed remains selected")
		check(not game.hud.text_window.messages.get_parsed_text().contains("Discarded future loot"),"load clears messages from the discarded timeline")
		check(not game.hud.text_window.listing.get_parsed_text().contains("9340"),"collected-items listing uses restored purse")
	# Close the real load menu into its asynchronous load operation. The
	# previously running field must remain paused during its cover/startup.
	get_tree().paused=false
	game.hud._open_menu()
	var panel:=game.hud._save_load
	panel.open(false)
	var index:=panel.saves.find_custom(func(info:SaveInfo):return info.slot=="paused-pose-1")
	check(index>=0,"fixture appears in real load menu")
	panel._select(index);panel._load()
	check(get_tree().paused,"accepting Load does not release the menu pause")
	check(await until(func():return game.hud._load_pause_before==null and not session.loading_game and not session._remote_loading,30),"menu load finishes")
	await assert_pose(1,"menu load")
	await finish()

func finish() -> void:
	if is_instance_valid(game):
		game.set_process(false); game.set_physics_process(false); game.set_process_unhandled_input(false)
		if is_instance_valid(game.direct):
			game.direct.set_process(false); game.direct._control_id=-2; game.direct._move_id=-1
	if is_instance_valid(session):
		session.set_process(false); session.set_physics_process(false)
		await session.local_host.stop()
	get_tree().paused=false
	if is_instance_valid(game): game.queue_free()
	if is_instance_valid(session): session.queue_free()
	for i in 8: await get_tree().process_frame
	TexUpscale.shutdown()
	print("PAUSED_LOAD_POSE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

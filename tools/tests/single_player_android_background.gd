extends Node
## Physical Android test. After DEVICE_BACKGROUND_READY, send Home, keep the
## app in the background for at least ten seconds, then reopen the same app.
## Use the private profile with user://fixtures/gz1h.sav; no performance claim.
var checks := 0
var failures := 0
var session: Session
var game: Game
var phase := 0
var left_at := 0
var before := 0.0
var autosave_before := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func until(predicate: Callable, seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	session=Session.new();get_parent().add_child(session);get_parent().session=session
	game=Game.new();game.session=session;session.game=game
	get_parent().add_child(game);get_parent().game=game
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var f:=FileAccess.open(SaveInfo.path("background_fixture"),FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes("user://fixtures/gz1h.sav"));f.close()
	check(await session.load_game_shown("background_fixture"),"single-player load")
	check(session.local_host.single_player and not session.multiplayer_game,"local single-player worker")
	if session.world==null:
		await session.local_host.stop();get_tree().quit(1);return
	check(await until(func():return session.world.time>1.0),"simulation running before Home")
	if FileAccess.file_exists(SaveInfo.path("autosave")):
		autosave_before=FileAccess.get_modified_time(SaveInfo.path("autosave"))
	phase=1
	print("DEVICE_BACKGROUND_READY ",JSON.stringify({"autosave_before":autosave_before,"path":ProjectSettings.globalize_path(SaveInfo.path("autosave"))}))

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and phase==1:
		before=session.world.time
		left_at=Time.get_ticks_msec()
		phase=2
		print("DEVICE_BACKGROUND_LEFT sim=",before)
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN and phase==2:
		phase=3
		print("DEVICE_BACKGROUND_RETURNED")
		verify_resume.call_deferred()

func verify_resume() -> void:
	var away_ms:=Time.get_ticks_msec()-left_at
	check(away_ms>=10000,"at least ten seconds in background")
	check(get_tree().paused and game.hud._esc_open,"backgrounding opens paused single-player menu")
	var answer:=await session.local_host.request("measure_save")
	check(answer.get("ok",false),"worker still responds after foregrounding")
	await get_tree().create_timer(0.5,true,false,true).timeout
	var after:=session.world.time
	check(after-before<=1.0,"worker does not simulate the background interval")
	check(FileAccess.file_exists(SaveInfo.path("autosave")),"background autosave exists")
	check(FileAccess.get_modified_time(SaveInfo.path("autosave"))>autosave_before,"background autosave is fresh")
	var saved:=CampaignState.load_from(SaveInfo.path("autosave"))
	check(saved!=null and saved.current_zone=="gz1h" and saved.heroes.has(0),"autosave contains authoritative campaign")
	game.hud._close_menu()
	check(await until(func():return session.world.time>after),"closing the menu resumes simulation")
	await session.local_host.stop()
	check(not session.local_host._process_alive(),"worker exits after background lifecycle")
	var result:={"checks":checks,"failures":failures,"background_ms":away_ms,"sim_before":before,"sim_after":after,"background_sim_delta":after-before}
	var f:=FileAccess.open("user://single-background-result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"  "));f.close()
	print("DEVICE_BACKGROUND_RESULT ",JSON.stringify(result))
	get_tree().quit(1 if failures else 0)

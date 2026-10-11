extends Node
## Real Android service, original campaign, disposable named slots.
var s: Session
var g: Game
var checks := 0
var failures := 0
var dialogs := 0
var advance_dialogue := true
var speeches := []
var rows := []

class ObservedSession extends Session:
	var probe: Node
	func _say(e: Dictionary) -> void:
		probe.speeches.append(e.duplicate(true))
		super._say(e)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
	rows.append({"ok":ok,"label":label})

func until(predicate: Callable, seconds := 15.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func _process(_dt: float) -> void:
	if advance_dialogue and g and g.hud and g.hud._dialog.visible:
		var d := g.hud._dialog
		if d._topics.is_empty() and d._mode in [DialogPanel.PLAYING, DialogPanel.LAST]:
			dialogs += 1
			d._skip(); d._next()

func progress(label: String) -> void:
	var before := s.world.time
	check(await until(func(): return s.world.time > before + 0.2, 6), label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	s=ObservedSession.new();s.probe=self;get_parent().add_child(s)
	g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	await s.new_campaign(false)
	check(s.local_host.frontend and s.local_host.single_player,"new original campaign uses real Android worker")
	check(await until(func():return s.world!=null and not s.loading_game and not s._remote_loading),"new game finishes loading")
	if not s.world:
		await finish();return
	await progress("new game simulation advances")
	check(await until(func():return not speeches.is_empty()),"original opening speech runs")
	check(await until(func():return not g.hud._dialog.visible),"original opening dialogue finishes")
	await progress("simulation advances after dialogue")
	for i in 2:
		g.hud._open_menu()
		var answer := await s.local_host.request("save",{"slot":"android_report_probe","camera":s.local_host.view()})
		check(answer.get("ok",false) and FileAccess.file_exists(SaveInfo.path("android_report_probe")),"save from paused menu succeeds %d"%i)
		g.hud._close_menu()
		await progress("simulation advances after saving %d"%i)
		check(await s.load_game_shown("android_report_probe"),"saved game loads %d"%i)
		await progress("simulation advances after loading %d"%i)
	# Prepare the original campaign's captive arrival, then let the real
	# service, briefing UI and completion RPCs run the authored conversation.
	var st:=CampaignState.new();st.ensure_hero(0,"Human Hero")
	st.current_zone="bz4g";st.visited["bz4g"]=true
	st.set_var(0,"b.bz4g.Ha29",1)
	check(st.save(SaveInfo.path("android_dialog_probe"))==OK,"prepare disposable original captive arrival")
	check(await s.load_game_shown("android_dialog_probe"),"load original captive arrival through service")
	check(await until(func():return dialogs>0),"original captive dialogue opens on local client")
	check(await until(func():return s.state.get_var(0,"b.bz4g.Ha29")==2),"client finishes original dialogue through authority")
	await progress("simulation advances after original captive dialogue")
	# Replay service lifecycle independently of owner focus to test either
	# notification order. The running owner's requested clock is unchanged.
	var service := Engine.get_singleton("EISimulation")
	service.set_active(false)
	await get_tree().create_timer(0.8,true,false,true).timeout
	var held := s.world.time
	await get_tree().create_timer(0.4,true,false,true).timeout
	check(s.world.time==held,"Android suspends the separate simulation")
	service.set_active(true)
	await get_tree().create_timer(0.5,true,false,true).timeout
	check(not get_tree().paused,"owner still requests a running clock")
	await progress("resumed service restores the owner's running clock")
	var answer := await s.local_host.request("save",{"slot":"android_report_probe","camera":s.local_host.view()})
	check(answer.get("ok",false),"service answers save after resume")
	# Recover baseline to permit clean shutdown, and preserve explicit pause.
	g.hud._open_menu()
	service.set_active(false)
	await get_tree().create_timer(0.4,true,false,true).timeout
	service.set_active(true)
	await get_tree().create_timer(0.6,true,false,true).timeout
	held=s.world.time
	await get_tree().create_timer(0.4,true,false,true).timeout
	check(get_tree().paused and s.world.time==held,"resume preserves intentional menu pause")
	g.hud._close_menu()
	await progress("closing resumed menu releases pause")
	await finish()

func finish() -> void:
	await s.local_host.stop()
	check(not s.local_host._process_alive(),"worker shuts down")
	var f:=FileAccess.open("user://android-freeze.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"dialogs":dialogs,"speeches":speeches,"rows":rows},"  "));f.close()
	print("ANDROID_FREEZE_REPORT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

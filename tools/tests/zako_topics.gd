extends "coop_story.gd"
## Exercise the normal interact -> topics -> staged conversation -> close path
## on two actual ENet peers. Direct play_named fixtures do not cover this path.
var checks := 0
var failures: Array[String] = []
var samples: Array = []

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	for i in 8:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("user://zako-topics-"+label+".png")==OK,"capture actual "+label+" viewport")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func advance_until(predicate: Callable, count := 800) -> bool:
	for i in count:
		if predicate.call(): return true
		host.world._tick(GameUnit.TICK)
		await get_tree().process_frame
	return predicate.call()

func camera_input(g: Game, label: String) -> void:
	check(not g.rig.held, label+": dialogue camera released")
	check(not g.hud.blocks_camera(), label+": HUD accepts camera input")
	# Headless/SubViewport fixtures do not receive desktop focus events.
	# Deliver the normal focus notification; do not alter camera lock flags.
	g.rig.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	if g.direct.active():
		g.direct._process(0.016)
		check(g.direct.usable(),label+": direct control resumes for the selected owner")
		var heading := g.direct.heading
		var view := g.rig.camera.global_transform
		var motion := InputEventMouseMotion.new();motion.relative=Vector2(80,-24)
		check(g.direct.handle_input(motion),label+": direct camera accepts mouse input")
		g.direct.apply_camera(0.016)
		check(not is_equal_approx(g.direct.heading,heading) and not g.rig.camera.global_transform.is_equal_approx(view),label+": direct view actually turns after dialogue")
		return
	g.rig.set_process(false)
	g.rig.distance=20.0
	if g.rig.modern():g.rig._snap()
	g.rig._apply()
	var before := g.rig.camera.global_transform
	var wheel := InputEventMouseButton.new()
	wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true
	g.rig._unhandled_input(wheel)
	for i in 12:g.rig._process(0.055)
	check(g.rig.distance<20.0 and not g.rig.camera.global_transform.is_equal_approx(before),label+": wheel changes the camera")
	var yaw := g.rig.yaw
	g.rig.pad_turn=0.5;g.rig._process(0.1);g.rig.pad_turn=0.0
	check(not is_equal_approx(yaw,g.rig.yaw),label+": camera rotates after close")
	g.rig.set_process(true)

func scenario(player: int, closer: int, overlay: bool, style: int, control: int) -> void:
	var label := "actor=%d closer=%d journal=%s camera=%d control=%d" % [player,closer,overlay,style,control]
	GameData.options.camera_style=style
	GameData.options.control_mode=control
	var world := host.world
	var b := world.vm.briefings
	world.vm.instances.clear();b._check=INF
	world.dialog_movers.clear();world.dialog_actors.clear()
	for key: String in host.state.gs_keys(0,"b.",true):host.state.set_var(0,key,3)
	host.state.set_var(0,"b.Zaku.S64",1)
	var npc: GameUnit = world.vm._by_name("Zaku")
	if npc==null:
		check(false,"actual Zako NPC exists");return
	var hero: GameUnit = host.party_units(player)[0]
	var other: GameUnit = host.party_units(1-player)[0]
	for unit: GameUnit in [hero,other,npc]:unit.orders.clear();unit.order={}
	hero.pos=npc.pos+Vector2(1.5,0)
	other.pos=npc.pos+Vector2(7,0)
	hero.position.y=world._stand_z(hero.pos)
	other.position.y=world._stand_z(other.pos)
	check(npc.village_talk_ready(),label+": NPC ready before interaction")
	host.sync_state()
	var game: Game = hg if player==0 else cg
	var panel := game.hud._dialog
	game.issue({"t":"interact","units":[hero.uid],"target":npc.uid})
	if not await advance_until(func():return panel.visible and panel._mode==DialogPanel.TOPICS):
		check(false,label+": interaction reaches topics");return
	check(true,label+": interaction reaches topics")
	var choice := -1
	for i in panel._topics.options.size():
		if panel._topics.options[i].var=="b.Zaku.S64":choice=i
	check(choice>=0,label+": authored S64 topic offered")
	if choice<0:return
	# A remote conversation may interrupt another player's journal.
	var spectator: Game = cg if player==0 else hg
	if overlay:spectator.hud.toggle_journal()
	panel._on_topic(choice)
	var playing := await advance_until(func():return b.active=="b.Zaku.S64" and b._pending_dialog.is_empty() and hg.hud._dialog._mode>=DialogPanel.PLAYING and cg.hud._dialog._mode>=DialogPanel.PLAYING)
	check(playing,label+": staged dialogue plays on both peers")
	if not playing:return
	check(hg.rig.held and cg.rig.held,label+": both cameras frame dialogue")
	if player==1 and closer==0 and not overlay and style==1:await capture("dialogue")
	var finish_panel := (hg if closer==0 else cg).hud._dialog
	finish_panel._skip();finish_panel._finish()
	check(await until(func():return b.active.is_empty() and not hg.hud._dialog.visible and not cg.hud._dialog.visible),label+": either peer closes conversation")
	for i in 4:world._tick(GameUnit.TICK);await get_tree().process_frame
	check(host.state.get_var(0,"b.Zaku.S64")==2,label+": topic marked completed")
	if overlay:
		check(spectator.hud._journal.visible,label+": interrupted journal restored")
		spectator.hud.toggle_journal()
	for g: Game in [hg,cg]:camera_input(g,label+(" host" if g==hg else " guest"))
	if player==1 and closer==0 and not overlay and style==1:await capture("restored")
	samples.append({"player":player,"closer":closer,"journal":overlay,"camera_style":style,"control_mode":control,"host_held":hg.rig.held,"guest_held":cg.rig.held,"host_blocked":hg.hud.blocks_camera(),"guest_blocked":cg.hud.blocks_camera()})

func _ready() -> void:
	if GameData.campaign_id!=CampaignProfile.ORIGINAL:
		printerr("FAIL Zako topic fixture requires the original campaign");get_tree().quit(1);return
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"scroll_border":0,"pad_enabled":0,"control_mode":1},true)
	PadInput.active="kbm"
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var h := branch("ZakoTopicHost",true);host=h.s;hg=h.g
	var c := branch("ZakoTopicGuest",false);client=c.s;cg=c.g
	require(host.host(29986,2)==OK and client.join("127.0.0.1",29986)==OK)
	require(await until(func():return host.players.size()==2))
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero")
	await host.enter_zone("bz14h",1,false)
	require(await until(func():return client.world!=null and client.zone_id=="bz14h" and not client._remote_loading))
	host.set_physics_process(false);host.world.set_process(false);host.world.set_physics_process(false)
	var direct := "--direct" in OS.get_cmdline_user_args()
	# Headless direct-control checks leave the desktop pointer free.
	if direct and DisplayServer.get_name()!="headless":
		printerr("FAIL direct fixture requires headless mode");get_tree().quit(2);return
	for control in ([2,3] if direct else [1]):
		for style in ([1] if direct else [0,1]):
			for player in [0,1]:
				for closer in [0,1]:
					for overlay in [false,true]:await scenario(player,closer,overlay,style,control)
	for g: Game in [hg,cg]:g.direct.set_process(false)
	host.online=false;client.online=false
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root in branches:root.queue_free()
	for i in 10:await get_tree().process_frame
	FileAccess.open("user://zako_topics.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":samples},"\t"))
	print("ZAKO_TOPICS ",checks," checks ",failures.size()," failures")
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)

func _process(_dt: float) -> void:pass

extends "coop_story.gd"
var checks:=0
var failures:=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _ready():
	if GameData.campaign_id!=CampaignProfile.ORIGINAL:
		printerr("FAIL Zako fixture requires the original campaign");get_tree().quit(1);return
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"scroll_border":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var h:=branch("Host",true);host=h.s;hg=h.g
	var c:=branch("Client",false);client=c.s;cg=c.g
	require(host.host(29893,2)==OK);require(client.join("127.0.0.1",29893)==OK)
	require(await until(func():return host.players.size()==2))
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero")
	for row:Array in [["bz14h","s64","b.zaku.s64"],["bz18h","s71","b.bz18h.s71"],["bz7g","r72_1","b.rick.r72_1"]]:
		await host.enter_zone(row[0],1,false)
		require(await until(func():return client.world!=null and client.zone_id==row[0] and not client._remote_loading))
		host.set_physics_process(false);host.world.set_process(false);host.world.set_physics_process(false)
		for i in 4:host.world._tick(GameUnit.TICK)
		host.world.vm.briefings.play_named(row[1],row[2],0,null,true)
		require(await until(func():return hg.hud._dialog.visible and cg.hud._dialog.visible))
		check(hg.rig.held and cg.rig.held,row[1]+" dialogue takes both cameras")
		hg.hud._dialog._skip();hg.hud._dialog._finish()
		require(await until(func():return not cg.hud._dialog.visible))
		for i in 240:
			host.world._tick(GameUnit.TICK)
			for g:Game in [hg,cg]:
				if g.hud._dialog.visible:g.hud._dialog._skip();g.hud._dialog._finish()
			await get_tree().process_frame
		for g:Game in [hg,cg]:
			g.rig._window_focused=true
			check(not g.rig.held,row[1]+" camera released on "+("host" if g==hg else "client"))
			check(not g.hud.blocks_camera(),row[1]+" camera input restored on "+("host" if g==hg else "client"))
			g.rig.set_process(false)
			g.rig.distance=20.0
			if g.rig.modern():g.rig._snap()
			g.rig._apply()
			var before_camera:=g.rig.camera.global_transform
			var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true
			g.rig._unhandled_input(wheel)
			for frame in 12:g.rig._process(0.055)
			check(g.rig.distance<20.0 and not g.rig.camera.global_transform.is_equal_approx(before_camera),row[1]+" camera really zooms after Zako dialogue")
			var before_yaw:=g.rig.yaw
			g.rig.pad_turn=0.5;g.rig._process(0.1);g.rig.pad_turn=0.0
			check(not is_equal_approx(g.rig.yaw,before_yaw),"camera really rotates after Zako dialogue")
			g.rig.set_process(true)
		print("DIALOG_STATE ",row[1]," host ",hg.rig.held," ",hg.hud.blocks_camera()," client ",cg.rig.held," ",cg.hud.blocks_camera())
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root in branches:root.queue_free()
	for i in 10:await get_tree().process_frame
	FileAccess.open("user://zako_dialogue.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("ZAKO_DIALOGUE ",checks," checks ",failures.size()," failures")
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
func _process(_dt:float):pass

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
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"auto_graphics":0,"show_tutorial":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var seed:=CampaignState.new();seed.ensure_hero(0,"Human Hero");seed.current_zone="bz18h"
	seed.set_var(0,"b.bz18h.s71",1)
	seed.save(SaveInfo.path("zako-seed"))
	host=Session.new();get_parent().add_child(host);hg=Game.new();hg.session=host;host.game=hg;get_parent().add_child(hg)
	var error:=await host.local_host.start(29966,2)
	check(error==OK,"actual authority process starts")
	if error!=OK:get_tree().quit(1);return
	check(await host.load_game_shown("zako-seed"),"owner loads Zako scene through worker")
	var root:=SubViewport.new();root.name="GuestPeer";root.size=Vector2i(800,600);root.own_world_3d=true;add_child(root);branches.append(root)
	var api:=SceneMultiplayer.new();api.root_path=root.get_path();get_tree().set_multiplayer(api,root.get_path())
	var main:=Node.new();main.name="Main";root.add_child(main)
	client=Session.new();main.add_child(client);cg=Game.new();cg.session=client;client.game=cg;main.add_child(cg)
	require(client.join("127.0.0.1",29966)==OK)
	require(await until(func():return client.world!=null and not client.loading_game and not client._remote_loading))
	check(await until(func():return hg.hud._dialog.visible and cg.hud._dialog.visible),"original Zako briefing reaches both real peers")
	hg.hud._dialog._skip();hg.hud._dialog._finish()
	var deadline:=Time.get_ticks_msec()+6000
	while Time.get_ticks_msec()<deadline:
		for g:Game in [hg,cg]:
			if g.hud._dialog.visible:g.hud._dialog._skip();g.hud._dialog._finish()
		await get_tree().process_frame
	for g:Game in [hg,cg]:
		g.rig._window_focused=true
		check(not g.rig.held and not g.hud.blocks_camera(),"camera unlocked after original actor removal and follow-up on "+("owner" if g==hg else "guest"))
		g.rig.set_process(false)
		g.rig.distance=20.0
		if g.rig.modern():g.rig._snap()
		g.rig._apply()
		var before_camera:=g.rig.camera.global_transform
		var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true
		g.rig._unhandled_input(wheel)
		for frame in 12:g.rig._process(0.055)
		check(g.rig.distance<20.0 and not g.rig.camera.global_transform.is_equal_approx(before_camera),"camera really zooms after Zako dialogue")
		var before_yaw:=g.rig.yaw
		g.rig.pad_turn=0.5;g.rig._process(0.1);g.rig.pad_turn=0.0
		check(not is_equal_approx(g.rig.yaw,before_yaw),"camera really rotates after Zako dialogue")
		g.rig.set_process(true)
	# The console must reach the real authority; spoofed guest fields cannot.
	var before:=host.state.money
	host.submit({"t":"console","line":"give 0 money 7","request":7})
	check(await until(func():return host.state.money==before+7),"owner console mutation reaches worker and replicates")
	client.submit({"t":"console","line":"give 0 money 999","player":0,"request":8})
	await get_tree().create_timer(.25,true,false,true).timeout
	check(host.state.money==before+7,"guest cannot forge console ownership")
	host.submit({"t":"console","line":"@GodMode(0,1)","request":9})
	check(await until(func():return host.state.god_modes.get(0,0)==1 and client.state.god_modes.get(0,0)==1),"owner GodMode command reaches worker and both peers")
	check(host.party_units(0)[0].god_mode() and client.party_units(0)[0].god_mode(),"replicated flag applies to the correct owner on both peers")
	check(not client.party_units(1)[0].god_mode(),"host mode does not silently grant guest immunity")
	client.submit({"t":"console","line":"@GodMode(1,1)","player":0,"request":10})
	await get_tree().create_timer(.25,true,false,true).timeout
	check(not host.state.god_modes.has(1),"guest cannot forge a GodMode grant")
	host.submit({"t":"console","line":"@GodMode(0,0)","request":11})
	check(await until(func():return host.state.god_modes.is_empty() and client.state.god_modes.is_empty()),"disabling GodMode replicates without leaving a stale flag")
	var responses:Dictionary={}
	host.console_output.connect(func(rows,request):responses[request]=rows)
	var hero:GameUnit=host.party_units(0)[0]
	host.submit({"t":"console","line":"inspect selected","selection":[hero.uid],"request":12})
	check(await until(func():return responses.has(12)),"selected-unit inspection returns from worker")
	check(responses.get(12,[]).size()==2,"worker resolves frontend selection IDs")
	host.submit({"t":"console","line":"god on","request":13})
	check(await until(func():return host.state.god_modes.get(0,0)==1 and client.state.god_modes.get(0,0)==1),"god shorthand replicates through real worker")
	client.submit({"t":"console","line":"god off","player":0,"request":14})
	await get_tree().create_timer(.25,true,false,true).timeout
	check(host.state.god_modes.get(0,0)==1,"guest cannot forge shorthand ownership")
	host.submit({"t":"console","line":"god off","request":15})
	host.submit({"t":"console","line":"time 14 freeze","request":16})
	check(await until(func():return is_equal_approx(host.state.world_time,14) and is_equal_approx(client.state.world_time,14)),"scene clock shorthand replicates")
	host.submit({"t":"console","line":"heal selected","selection":[hero.uid],"request":17})
	check(await until(func():return responses.has(17)),"healing selected unit returns from worker")
	check(not responses.get(17,[]).is_empty() and responses[17][0].contains(hero.display_name),"worker reports the healed unit by name")
	DeveloperConsole.run("report worker.txt")
	check(await until(func():return FileAccess.file_exists("user://console/worker.txt")),"diagnostic report waits for worker response")
	check(FileAccess.get_file_as_string("user://console/worker.txt").contains("bz18h"),"report includes authoritative zone")
	client.multiplayer.multiplayer_peer.close();await host.local_host.stop()
	for branch_root in branches:branch_root.queue_free()
	hg.queue_free();host.queue_free()
	for i in 10:await get_tree().process_frame
	FileAccess.open("user://zako_worker.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("ZAKO_WORKER ",checks," checks ",failures.size()," failures")
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
func _process(_dt:float):pass

extends "coop_trade.gd"
## Real map entry/revisit, full save load and ENet delivery of independent clocks.
const P := preload("res://src/game/script/script_parser.gd")
var trace: Array = []

func stop(s: Session) -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	if s.world.vm: s.world.vm.instances.clear()
	s.game.set_process(false); s.game.rig.set_process(false)

func enter(id: String) -> void:
	var previous := client.world.get_instance_id() if client.world else 0
	await host.enter_zone(id,1,false); stop(host)
	check(await until(func():return client.world!=null and client.world.get_instance_id()!=previous and not client.loading_game and not client._remote_loading),"guest completes entry to "+id)
	stop(client)

func snapshot(phase: String, hour: float, elapsed: float, fixed: bool) -> void:
	for peer_session: Session in [host,client]:
		var name := "host" if peer_session==host else "guest"
		trace.append({"phase":phase,"peer":name,"hour":peer_session.state.world_time,
			"gtime":peer_session.state.get_var(0,"gtime"),"fixed":peer_session.world.clock_fixed})
		check(absf(wrapf(peer_session.state.world_time-hour,-12.0,12.0))<0.00002,phase+" / scene hour / "+name)
		check(absf(peer_session.state.get_var(0,"gtime")-elapsed)<0.00002,phase+" / campaign hours / "+name)
		check(peer_session.world.clock_fixed==fixed,phase+" / freeze state / "+name)

func command(op: String, value: float) -> void:
	var args := [[P.N_NUM,0.0],[P.N_STR,"gtime"]]
	if op!="GSDelVar": args.append([P.N_NUM,value])
	host.world.vm._call(op,args,ScriptVM.Instance.new())
	host.sync_state()
	check(await until(func():return client.state.get_var(0,"gtime")==host.state.get_var(0,"gtime")),op+" reaches guest")

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	host=peer("CampaignClockHost",true);client=peer("CampaignClockGuest",false)
	check(host.host(30047,2)==OK and client.join("127.0.0.1",30047)==OK,"campaign clock peers connect")
	if failures: get_tree().quit(2); return
	check(await until(func():return host.players.size()==2),"two campaign clock players")
	var first_map := "gz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "gz1g"
	var second_map := "gz2h" if GameData.campaign_id==CampaignProfile.ASTRAL else "gz5g"
	if not host.zone_exists(first_map) or not host.zone_exists(second_map):
		printerr("Campaign-clock fixture maps are unavailable"); get_tree().quit(2); return
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Clock Guest")
	host.state.set_var(0,"gtime",35.75);host.state.set_scene_hour(0.3);host.set_physics_process(false)
	# Native zone-entry captures: copied gtime is converted to hour modulo 24
	# after map/party load. These real transitions also exercise saved rates.
	await enter(first_map)
	snapshot("fresh map",11.75,35.75,false)
	host.world.vm._call("FixWorldTime",[[P.N_NUM,0.3]],ScriptVM.Instance.new())
	check(await until(func():return client.world.clock_fixed and is_equal_approx(client.state.world_time,0.3)),"freeze reaches guest")
	await command("GSSetVar",19.0)
	snapshot("set while frozen",0.3,19.0,true)
	check(host.save_game("campaign-clock-coop")==OK,"save scene with different clocks")
	var previous := client.world.get_instance_id()
	check(await host.load_game("campaign-clock-coop"),"full saved-game load")
	stop(host)
	check(await until(func():return client.world!=null and client.world.get_instance_id()!=previous and not client.loading_game and not client._remote_loading),"guest completes full load")
	stop(client)
	snapshot("full load preserves scene",0.3,19.0,true)
	await enter(second_map)
	snapshot("fresh destination",19.0,19.0,false)
	await command("GSSetVar",50.5)
	snapshot("set while running",19.0,50.5,false)
	await enter(first_map)
	snapshot("revisit restores rate but resets hour",2.5,50.5,true)
	await command("GSDelVar",0.0)
	snapshot("delete while frozen",2.5,0.0,true)
	check(not host.state.gs_keys().has("gtime") and not client.state.gs_keys().has("gtime"),"deleted campaign clock stays absent on both peers")
	await enter(second_map)
	snapshot("revisit after delete",0.0,0.0,false)
	FileAccess.open("user://campaign-clock-coop.json",FileAccess.WRITE).store_string(JSON.stringify({"campaign":GameData.campaign_id,"checks":checks,"failures":failures,"trace":trace},"\t"))
	host.online=false;client.online=false
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root:Node in roots: root.queue_free()
	for i in 12: await get_tree().process_frame
	print("CAMPAIGN_CLOCK_COOP ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)

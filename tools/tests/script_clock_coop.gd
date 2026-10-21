extends "coop_trade.gd"
## Installed LiA cz1h freeze, actual ENet delivery, frontend time and full load.
const P := preload("res://src/game/script/script_parser.gd")
var trace: Array = []

func stop(s: Session) -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.game.set_process(false); s.game.rig.set_process(false)

func _ready() -> void:
	if GameData.campaign_id != CampaignProfile.ASTRAL: printerr("LiA assets required"); get_tree().quit(2); return
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	host=peer("ClockHost",true);client=peer("ClockGuest",false)
	check(host.host(30046,2)==OK and client.join("127.0.0.1",30046)==OK,"clock peers connect")
	if failures: get_tree().quit(2); return
	check(await until(func():return host.players.size()==2),"two clock players")
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Clock Guest")
	host.state.set_var(0,"gtime",35.75);host.set_physics_process(false)
	await host.enter_zone("cz1h",1,false);stop(host)
	check(await until(func():return client.world!=null and not client._remote_loading and not client.loading_game),"guest loads actual cz1h")
	stop(client)
	# Start the installed routine directly; its Sleep(10) suspends before
	# the staged dialogue actors begin moving. No authored body is rewritten.
	var vm := host.world.vm;vm.instances.clear()
	var elapsed := host.state.get_var(0,"gtime")
	vm.spawn("VTriger#0#1",[null]);vm._run(vm.instances[-1])
	check(vm.time_fixed and is_equal_approx(host.state.world_time,0.3),"authored prison scene freezes at 00:18")
	check(host.state.get_var(0,"gtime")==elapsed,"authored night reset preserves elapsed campaign time")
	host.sync_state()
	check(await until(func():return is_equal_approx(client.state.world_time,host.state.world_time)),"host scene hour reaches guest")
	check(client.state.get_var(0,"gtime")==elapsed,"elapsed campaign time reaches guest separately")
	var hour := client.state.world_time
	for i in 20: client.game._process(0.25)
	trace.append({"phase":"frozen","host":host.state.world_time,"guest":client.state.world_time,"elapsed":elapsed})
	check(client.state.world_time==hour,"guest daylight stays frozen between network packets")
	check(host.save_game("clock-coop")==OK,"save actual frozen co-op scene")
	var previous_guest_world := client.world.get_instance_id()
	check(await host.load_game("clock-coop"),"load actual frozen co-op scene")
	stop(host)
	check(await until(func():return client.world!=null and client.world.get_instance_id()!=previous_guest_world and not client.loading_game and not client._remote_loading),"guest completes saved-world load")
	stop(client)
	check(host.world.vm.time_fixed,"authored freeze flag survives full load")
	check(host.state.get_var(0,"gtime")==elapsed and client.state.get_var(0,"gtime")==elapsed,"both campaign timers survive full load")
	hour=client.state.world_time
	for i in 20: client.game._process(0.25)
	check(client.state.world_time==hour,"loaded guest daylight remains frozen")
	# Native RunWorldTime release is tested without skipping through an
	# unrelated quest. Automatic reliable delivery must work without an
	# explicit full-state refresh.
	host.world.vm._call("RunWorldTime",[[P.N_NUM,19.0]],ScriptVM.Instance.new())
	for i in 20: await get_tree().process_frame
	check(is_equal_approx(client.state.world_time,19.0),"clock release reaches guest without a full-state poll")
	hour=client.state.world_time;client.game._process(0.25)
	check(client.state.world_time>hour,"guest daylight resumes after release")
	check(host.state.get_var(0,"gtime")==elapsed,"release does not overwrite campaign time")
	FileAccess.open("user://script-clock-coop.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"trace":trace},"\t"))
	host.online=false;client.online=false
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root:Node in roots: root.queue_free()
	for i in 12: await get_tree().process_frame
	print("SCRIPT_CLOCK_COOP ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)

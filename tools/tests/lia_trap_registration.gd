extends "coop_save_effects.gd"
## Prepared original zone13 activation over actual loopback ENet. Native
## child conditions/damage are unchanged; this is not a played route.
const Traps := preload("res://src/game/script/story_coop_traps.gd")
func loaded() -> bool:
	return client.world != null and client.zone_id == "gz13g" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func connect_guest() -> bool:
	client=branch(true);GameData.player_name="Trap Guest"
	check(client.join("127.0.0.1",29954)==OK,"guest connects over ENet")
	var ready:=await until(loaded,30.0)
	check(ready,"guest receives original trap map")
	if ready:freeze(client)
	return ready

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"revive":1,"control_mode":1,"confine_mouse":0},true)
	var changed:=ScriptParser.parse(EIMob.load_bytes(GameData.read_file("maps/zone13.mob")).script_text)
	changed.scripts["Trap#0#3"].blocks[0].body[2][2][1][1]=1.0
	Traps.apply(changed,"gz13g")
	check(not changed.scripts.has("Trap#0#1"+Traps.WATCH),"modified authored damage fails the source guard")
	host=branch(false);host.state=CoopProgress.fresh_state();host.set_physics_process(false)
	check(host.host(29954,2)==OK,"host opens isolated trap session")
	await host.enter_zone("gz13g",1,false);freeze(host)
	var vm:=host.world.vm;vm.instances.clear()
	var h:GameUnit=host.party_units(0)[0];var safe:=h.pos
	for st:Array in vm.ast.scripts["VCheck#0#1"].blocks[0].body:
		if st[0]==ScriptParser.S_CALL and st[1]=="AddRectToArea":vm._call(st[1],st[2],ScriptVM.Instance.new())
	for i in 2:
		var root:="Trap#%d#1"%i
		check(vm.ast.scripts.has(root+Traps.WATCH),"original trap %d admits participant adapter"%i)
		h.pos=Vector2(45,64) if i==0 else Vector2(75,69)
		vm.spawn(root,[null],"VCheck#0#1");ticks(6)
		check(h.dead,"original trap kills present host %d"%i)
		Revive.finish(host,h);h.pos=safe;h.resync_drawn();ticks(3)
	check(vm.instances.filter(func(inst):return inst.sname.ends_with(Traps.WATCH)).size()==2,"activation remains saved after native one-shot children finish")
	if not await connect_guest():done.call_deferred();return
	var u:=visitor();check(u!=null,"late guest has an authoritative actor")
	if u==null:done.call_deferred();return
	for i in 2:
		u.pos=Vector2(45,64) if i==0 else Vector2(75,69);u.resync_drawn();ticks(6)
		check(u.dead,"original trap now kills late arrival %d"%i)
		check(await sync_visitor(u),"client sees late-arrival trap death")
		Revive.finish(host,u);ticks(5)
		check(not u.dead,"revival preserves consumed participant registration")
	check(host.save_game("spent-zone13")==OK,"save consumed traps")
	check(await host.load_game_shown("spent-zone13"),"load consumed traps with guest connected");freeze(host)
	check(await until(loaded),"guest receives reloaded trap state");freeze(client)
	vm=host.world.vm;u=visitor();ticks(5)
	check(u!=null and not u.dead,"save/load cannot re-arm a consumed guest")
	var old_root:Node=branches.back();branches.erase(old_root)
	var peer:=client.multiplayer.multiplayer_peer
	client.online=false;client.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new();peer.close();old_root.queue_free()
	check(await until(func():return host.players.size()==1),"host observes guest disconnect")
	if not await connect_guest():done.call_deferred();return
	u=visitor();ticks(6)
	check(u!=null and not u.dead,"reconnection retains consumed participant identity")
	host.state.set_var(0,"q.gz13g.q17g.2",2.0);ticks(3)
	check(not vm.instances.any(func(inst):return inst.sname=="Trap#0#1"+Traps.WATCH),"completed quest stops admitting new participants")
	host.state.set_var(0,"q.gz13g.q17g.2",0.0)
	u.pos=Vector2(45,64);u.resync_drawn()
	vm.spawn("Trap#0#1",[null],"VCheck#0#1");ticks(6)
	check(u.dead,"deliberate authored reactivation re-arms the same guest")
	check(await sync_visitor(u),"client receives reactivated trap death")
	done.call_deferred()

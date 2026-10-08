extends "story_coop_traps_net.gd"
## A real ENet guest and four prepared host actors use the production lift.
## Movement/use commands cross normal RPC; original mover scripts remain live.
## Unrelated AI is held still. This does not measure network performance.
var riders: Array[GameUnit] = []

func loaded() -> bool:
	return client.world != null and client.zone_id == host.zone_id and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func run_ticks(count: int) -> void:
	for i in count:
		host.world.time += GameUnit.TICK
		host.world.vm.tick(GameUnit.TICK);host.world.lever_sys.tick()
		for u: GameUnit in riders: u.tick(GameUnit.TICK)
		if i % 30 == 0: await frames(1)
	host._send_snapshot_records(riders.map(func(u:GameUnit):return u.snapshot()),host.world.time)
	await frames(4)

func offset(s: Session) -> float:
	return s.world.objects[2240358].get_meta("ei").position.z

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	host=branch(false);check(host.host(29938,2)==OK,"open real Catacombs host")
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero")
	for i in range(1,4):
		var h:Dictionary=host.state.heroes[0][0].duplicate(true)
		h.merc=i;h.unit_name="merc"+str(i);h.party="";h.controller=0;h.name="Rider "+str(i)
		host.state.mercs[i]=h
	host.state.set_var(0,"q.gz1d2.q03h",1);host.set_physics_process(false)
	await host.enter_zone("gz1d2",1,false);freeze(host)
	client=branch(true);GameData.player_name="Lift Guest"
	check(client.join("127.0.0.1",29938)==OK,"join as actual guest")
	check(await until(loaded),"client receives Catacombs")
	if failures:await finish();return
	freeze(client)
	check(host.party_units(0).size()==4 and host.party_units(1).size()==1,"four host riders and one independently owned guest")
	if failures:await finish();return
	for nid:int in [2240358,338779,1357456,1983521,2251726,2338355]:
		var a:Dictionary=host.world.objects[nid].get_meta("ei")
		var b:Dictionary=client.world.objects[nid].get_meta("ei")
		check(a.position==b.position and a.complexion==b.complexion,"peers load identical deck/frame/control geometry "+str(nid))
	var guest:=visitor()
	riders.assign(host.party_units(0));riders.insert(2,guest)
	for i in riders.size():
		var u:=riders[i];u.pos=Vector2(30.+1.5*(i%2),54.-1.5*floori(i/2.))
		u.ai_next=INF;u._perceive_next=INF;host.world.nav.track_unit(u)
	await run_ticks(30)
	host.world.vm._use_lever(riders[0],1369841);await run_ticks(950)
	check(await until(func():return is_equal_approx(offset(client),28.654)),"client receives original lift recall")
	var slots:Array[Vector2]=[Vector2(32.25,63.25),Vector2(30.75,63.25),Vector2(29.25,63.25),Vector2(32.25,61.75),Vector2(30.75,61.75)]
	for i in riders.size():
		var u:=riders[i];var input:=client if u==guest else host
		input.submit({"t":"move","units":[u.uid],"x":slots[i].x,"y":slots[i].y})
		check(await until(func():return not u.orders.is_empty() or not u.order.is_empty()),"ordinary boarding command arrives "+str(i))
		await run_ticks(400)
		var z:=host.world.ground_at(u.pos.x,u.pos.y)
		check(z>33.0 and z<33.3 and not u.order_failed,"rider physically boards "+str(i))
	client.submit({"t":"use_lever","units":[guest.uid],"target":1357456})
	check(await until(func():return guest.has_meta("interact") or not guest.is_idle()),"client switch command reaches authority")
	await run_ticks(950)
	check(is_equal_approx(offset(host),-0.3) and await until(func():return is_equal_approx(offset(client),-0.3)),"both peers reach lower stop")
	check(riders.all(func(u):return host.world.ground_at(u.pos.x,u.pos.y)<5.0),"all five riders descend")
	check(await sync_visitor(guest),"client receives its rider at lower stop")
	var ids:Array=host.party_units(0).map(func(u):return u.uid)
	client.submit({"t":"use_lever","units":[guest.uid],"target":338779})
	check(await until(func():return guest.has_meta("interact") or not guest.is_idle()),"client up-switch command arrives")
	await run_ticks(950)
	check(is_equal_approx(offset(host),28.654) and await until(func():return is_equal_approx(offset(client),28.654)),"guest beside controls raises lift on both peers")
	client.submit({"t":"use_lever","units":[guest.uid],"target":1357456})
	check(await until(func():return guest.has_meta("interact") or not guest.is_idle()),"client can use down switch again")
	await run_ticks(950)
	host.submit({"t":"move","units":ids,"x":31.0,"y":68.0});await run_ticks(600)
	check(host.party_units(0).all(func(u):return u.pos.y>66.0 and not u.order_failed),"one host group click unloads its riders")
	client.submit({"t":"move","units":[guest.uid],"x":29.0,"y":71.0})
	check(await until(func():return not guest.is_idle()),"client unload command arrives")
	await run_ticks(600)
	check(guest.pos.distance_to(Vector2(29,71))<.5 and not guest.order_failed,"guest walks off lower deck")
	check(host.save_game("catacomb_network")==OK,"save stopped co-op lift")
	check(await host.load_game_shown("catacomb_network"),"reload co-op lift checkpoint");freeze(host)
	check(await until(loaded),"client receives reloaded lift checkpoint");freeze(client)
	check(is_equal_approx(offset(host),-0.3) and is_equal_approx(offset(client),-0.3),"reload preserves lower stop on both peers")
	check(absf(client.world.objects[338779].get_meta("ei").position.x-28.72972)<.001,"client reload preserves relocated controls")
	await finish()

func finish() -> void:
	for s:Session in [host,client]:
		if is_instance_valid(s):
			s.online=false
			if s.multiplayer.multiplayer_peer:s.multiplayer.multiplayer_peer.close()
	for root:Node in branches:
		if is_instance_valid(root):root.queue_free()
	await frames(8)
	print("CATACOMB_CAPACITY_NET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

extends "coop_story.gd"
## A real ENet client issues direct-control commands to another session. No
## client supplied target/damage is trusted; generation and ownership apply.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(n := 12) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":1},true)
	var h := branch("Host",true);host=h.s;hg=h.g
	var c := branch("Guest",false);client=c.s;cg=c.g
	require(host.host(29917,2)==OK)
	GameData.player_name="Direct Guest"
	require(client.join("127.0.0.1",29917)==OK)
	require(await until(func():return host.players.size()==2 and client.my_index==1))
	host.set_physics_process(false);client.set_physics_process(false)
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Direct Guest")
	await host.enter_zone("bz1g",1,false)
	host.world.set_physics_process(false);host.world.set_process(false);host.world.vm.instances.clear()
	require(await until(func():return client.zone_id=="bz1g" and not client.loading_game and not host.loading_game))
	client.world.set_physics_process(false)
	var own: GameUnit=host.party_units(0)[0]
	var guest: GameUnit=host.party_units(1)[0]
	guest.blocked=false;guest.order={};guest.orders.clear();guest._anim_lock=0;guest._attack_cd=0
	client.submit({"t":"direct_control","leader":guest.uid});await frames()
	check(guest.direct_controlled and not own.direct_controlled,"client enables manual control only for its hero")
	client.submit({"t":"direct_control","leader":own.uid});await frames()
	check(not own.direct_controlled and not guest.direct_controlled,"client cannot seize the host hero")
	client.submit({"t":"direct_attack","units":[guest.uid],"direction":Vector3.RIGHT});await frames()
	check(guest.orders.is_empty(),"authority rejects guest direct attack in the real village")
	guest.orders.clear()
	# Send a valid known spell through the direct-cast alias too, so the
	# safe-zone check, not the spell/ownership validator, must refuse it.
	var spell := "healing{}"
	guest.get_meta("hero").spells.append(spell)
	client.submit({"t":"direct_cast","unit":guest.uid,"spell":spell,"target":guest.uid});await frames()
	check(guest.orders.is_empty(),"authority rejects guest third-person spell in the real village")
	guest.orders.clear()
	client.submit({"t":"attack","units":[guest.uid],"target":own.uid});await frames()
	check(guest.orders.is_empty(),"classic attack stays blocked in the same village")
	await host.enter_zone("gz1g",1,false)
	host.world.set_physics_process(false);host.world.set_process(false);host.world.vm.instances.clear()
	require(await until(func():return client.zone_id=="gz1g" and not client.loading_game and not host.loading_game \
		and not client._remote_loading and not client._zone_holding and client._pool_epoch==host._load_serial))
	client.world.set_physics_process(false)
	own=host.party_units(0)[0];guest=host.party_units(1)[0]
	guest.blocked=false;guest.order={};guest.orders.clear();guest._anim_lock=0;guest._attack_cd=0
	client.submit({"t":"direct_attack","units":[guest.uid],"direction":Vector3.RIGHT});await frames()
	check(guest.orders.size()==1 and guest.orders[0].type=="direct_attack","guest direction attack reaches authority in the field")
	check(not guest.orders.is_empty() and guest.orders[0].get("direction")==Vector3.RIGHT,"authority preserves normalized aim")
	guest.orders.clear()
	var own_orders := own.orders.duplicate(true)
	client.submit({"t":"direct_attack","units":[own.uid],"direction":Vector3.RIGHT});await frames()
	check(own.orders == own_orders,"foreign-unit direct attack cannot replace the host's arrival orders")
	client._rpc_cmd.rpc_id(1,{"t":"direct_attack","units":[guest.uid],"direction":Vector3.RIGHT,
		"_zone":"gz1g","_generation":host._load_serial-1});await frames()
	check(guest.orders.is_empty(),"previous load generation cannot attack in current area")
	guest.blocked=true
	client.submit({"t":"direct_attack","units":[guest.uid],"direction":Vector3.RIGHT});await frames()
	check(guest.orders.is_empty(),"script trap/blocked actor refuses network attack")
	guest.blocked=false
	client.submit({"t":"direct_attack","units":[guest.uid],"direction":Vector3(NAN,0,0)});await frames()
	check(guest.orders.is_empty(),"non-finite aim is rejected over network")
	# New projectile event is presentation-only on the client.
	var delivered := {}
	client.world.child_entered_tree.connect(func(n: Node):
		if n is Projectile and n._direct: delivered["hit"] = n.apply_hit)
	host.broadcast({"t":"direct_arrow","a":guest.uid,"direction":Vector3.RIGHT,"start":DirectCombat.origin(guest)})
	check(await until(func():return delivered.has("hit")),"free arrow event reaches the client")
	check(not delivered.get("hit",true),"client arrow cannot deal duplicate damage")
	host.online=false;client.online=false
	host.multiplayer.multiplayer_peer.close();client.multiplayer.multiplayer_peer.close()
	for node in branches:node.queue_free()
	await frames()
	print("DIRECT_COOP ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

extends "coop_story.gd"
## Controlled moving actor over real ENet in the full LiA Portal population.
## Isolates transport from AI cost; this is not a frame-rate benchmark.
class ObservedSession extends Session:
	var sizes: Array[int]=[]
	func _send_snap(snaps: Array, time: float, recipient := 0) -> void:
		sizes.append(var_to_bytes(snaps).size())
		super._send_snap(snaps,time,recipient)
func branch(label: String, main: bool) -> Dictionary:
	var root: Node=Node.new() if main else SubViewport.new()
	if root is SubViewport:root.size=Vector2i(1280,720);root.own_world_3d=true
	root.name=label;add_child(root);branches.append(root)
	var api:=SceneMultiplayer.new();api.root_path=root.get_path();get_tree().set_multiplayer(api,root.get_path())
	var s:=ObservedSession.new();root.add_child(s)
	var g:=Game.new();g.session=s;s.game=g;root.add_child(g)
	return {"s":s,"g":g}
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1},true)
	var a:=branch("Host",true);host=a.s;hg=a.g
	var b:=branch("Guest",false);client=b.s;cg=b.g
	require(host.host(29930,2)==OK);GameData.player_name="Stream Guest"
	require(client.join("127.0.0.1",29930)==OK)
	require(await until(func():return host.players.size()==2 and client.my_index==1))
	host.set_physics_process(false);client.set_physics_process(false)
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Stream Guest")
	await host.enter_zone("gz1h",1,false)
	host.world.set_physics_process(false);host.world.set_process(false);host.world.vm.instances.clear()
	require(await until(func():return client.zone_id=="gz1h" and not client._remote_loading and not client.party_units(1).is_empty(),60))
	var u: GameUnit=host.party_units(1)[0]
	var v: GameUnit=client.party_units(1)[0]
	hg.process_mode=Node.PROCESS_MODE_DISABLED;cg.process_mode=Node.PROCESS_MODE_DISABLED
	var from:=u.pos
	if host.multiplayer.multiplayer_peer is NetSim:
		host.multiplayer.multiplayer_peer._rng.seed=1492
		client.multiplayer.multiplayer_peer._rng.seed=1493
	var history: Dictionary={}
	for o: GameUnit in host.world.units.values():history[o.uid]=o
	u.set_meta("noticed",history.duplicate())
	print("SNAPSHOT_POPULATION ",host.world.units.size()," actor_bytes=",var_to_bytes(u.snapshot()).size())
	var results:=[]
	Engine.max_fps=60
	for rate in [1.0,2.0]:
		Engine.time_scale=rate
		var sizes: Array=(host as ObservedSession).sizes;sizes.clear()
		var times: Array[int]=[]
		var last: int=v.net_view._last_ms
		var first_update:=true
		var start:=Time.get_ticks_msec()
		var before:=start
		var end:=start+8000
		var max_error:=0.0
		while Time.get_ticks_msec()<end:
			var now:=Time.get_ticks_msec()
			var elapsed: float=(now-before)/1000.0
			before=now
			u.pos=from+Vector2(sin((now-start)*0.001*rate)*3,0)
			u.action="walk";u._move_speed=3.0
			u.set_meta("noticed",history.duplicate())
			host.world.time+=elapsed*rate
			host._exit_t=10.0 # no perception pruning/exits in this transport stress fixture
			host._tick_world_session(elapsed*rate)
			if int(v.net_view._last_ms)!=last:
				if not first_update:times.append(int(v.net_view._last_ms)-last)
				first_update=false
				last=v.net_view._last_ms
			max_error=maxf(max_error,u.pos.distance_to(v.pos))
			await get_tree().process_frame
		times.sort();sizes.sort()
		results.append({"rate":rate,"updates":times.size(),"gap_p95_ms":times[int(times.size()*.95)] if not times.is_empty() else -1,"gap_max_ms":times[-1] if not times.is_empty() else -1,"packet_count":sizes.size(),"packet_max_bytes":sizes[-1] if not sizes.is_empty() else 0,"packet_bytes":sizes.reduce(func(sum,n):return sum+n,0),"max_error":max_error})
	Engine.time_scale=1.0
	print("SNAPSHOT_DELIVERY ",JSON.stringify(results))
	history.clear();u.set_meta("noticed",{})
	host.online=false;client.online=false
	for session: Session in [host,client]:
		var peer:=session.multiplayer.multiplayer_peer
		peer.close()
		# NetSim's signal closures retain their wrapper after close in old builds.
		if peer is NetSim:
			for signal_name in ["peer_connected","peer_disconnected"]:
				for connection in peer.inner.get_signal_connection_list(signal_name):
					peer.inner.disconnect(signal_name,connection.callable)
	for node in branches:node.queue_free()
	for i in 8:await get_tree().process_frame
	get_tree().quit()

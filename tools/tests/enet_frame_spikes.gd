extends Node
## Real ENet ACK timing: slow frontend polling must not suppress fresh party
## snapshots for seconds after the frame spike. No simulated packet loss.
class Probe extends Node:
	var arrivals: Array[int] = []
	@rpc("authority","call_remote","unreliable")
	func snap(party: bool, _padding: PackedByteArray) -> void:
		if party: arrivals.append(Time.get_ticks_msec())
	@rpc("authority","call_remote","reliable")
	func ping() -> void: pass
var failures:=0
func _ready() -> void:
	get_tree().multiplayer_poll=false
	Engine.max_fps=120
	var reports:=[]
	for fixed in [false,true]: reports.append(await exercise(fixed))
	if reports[0].minimum_throttle!=0 or reports[0].max_gap_ms<1000:
		failures+=1;printerr("FAIL baseline must reproduce ENet snapshot starvation")
	if reports[1].minimum_throttle!=32 or reports[1].max_gap_ms>450:
		failures+=1;printerr("FAIL rate-bounded snapshots must survive frontend frame spikes")
	print("ENET_FRAME_SPIKES ",JSON.stringify(reports)," failures=",failures)
	get_tree().quit(1 if failures else 0)
func exercise(fixed: bool) -> Dictionary:
	var roots: Array[Node] = []
	var apis: Array[SceneMultiplayer] = []
	var probes: Array[Probe] = []
	for side in 2:
		var root:=Node.new();root.name="Server" if side==0 else "Client";add_child(root);roots.append(root)
		var api:=SceneMultiplayer.new();api.root_path=root.get_path();get_tree().set_multiplayer(api,root.get_path());apis.append(api)
		var probe:=Probe.new();probe.name="Probe";root.add_child(probe);probes.append(probe)
	var server:=ENetMultiplayerPeer.new();var client:=ENetMultiplayerPeer.new()
	server.create_server(29965,1);client.create_client("127.0.0.1",29965)
	apis[0].multiplayer_peer=server;apis[1].multiplayer_peer=client
	var deadline:=Time.get_ticks_msec()+5000
	while (apis[0].get_peers().is_empty() or client.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED) and Time.get_ticks_msec()<deadline:
		apis[0].poll();apis[1].poll();await get_tree().process_frame
	var peer:=server.get_peer(client.get_unique_id())
	peer.throttle_configure(1000 if fixed else 5000,32 if fixed else 2,0 if fixed else 2)
	peer.ping_interval(100)
	var payload:=PackedByteArray();payload.resize(900)
	var started:=Time.get_ticks_msec();var next_client:=started;var next_send:=started
	var minimum:=32
	var next_host:=started
	var observations:=[]
	var next_observation:=started
	while Time.get_ticks_msec()-started<28000:
		var now:=Time.get_ticks_msec();var elapsed:=now-started
		var server_frame:=now>=next_host
		if server_frame:
			apis[0].poll();next_host=now+33
		if now>=next_client:
			apis[1].poll()
			next_client=now+(180 if elapsed>=12000 and elapsed<20000 else 0)
		if server_frame and now>=next_send:
			next_send=now+100
			for chunk in 9:probes[0].snap.rpc(chunk==0,payload)
			probes[0].ping.rpc()
		if now>=next_observation:
			next_observation=now+1000
			observations.append([elapsed,peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE),peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)])
		minimum=mini(minimum,int(peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)))
		await get_tree().process_frame
	var gap:=0;var previous:=started
	for stamp in probes[1].arrivals:
		gap=maxi(gap,stamp-previous);previous=stamp
	gap=maxi(gap,Time.get_ticks_msec()-previous)
	var result:={"fixed":fixed,"minimum_throttle":minimum,"max_gap_ms":gap,"party_updates":probes[1].arrivals.size(),"samples":observations,"deceleration":peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_DECELERATION)}
	server.close();client.close()
	for root in roots:root.free()
	await get_tree().process_frame
	return result

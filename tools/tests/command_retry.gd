extends Node
## Duplicate/reordered transport copies retain exactly-once ordered actions.
## The ENet test delays canonical reliable packets for three seconds and
## loses fast copies, then checks the real Session dispatch and acknowledgements.
class ObservedSession extends Session:
	var applied := []
	func apply_command(cmd: Dictionary, player := 0) -> void:
		applied.append([cmd.get("test_id"), player])
class DelayedReliable extends NetSim:
	var hold := false
	var lose_fast := 0
	var dropped := 0
	func _put_packet_script(buffer: PackedByteArray) -> Error:
		if hold and _mode == TRANSFER_MODE_UNRELIABLE and _channel == 2 and lose_fast > 0:
			lose_fast -= 1; dropped += 1
			return OK
		latency = 6.0 if hold and _mode == TRANSFER_MODE_RELIABLE else 0.0
		return super._put_packet_script(buffer)
var checks := 0
var failures := 0
var roots := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func until(f: Callable, ms := 6000) -> bool:
	var end := Time.get_ticks_msec()+ms
	while Time.get_ticks_msec()<end:
		if f.call(): return true
		await get_tree().process_frame
	return bool(f.call())
func peer(label: String) -> ObservedSession:
	var n := Node.new(); n.name=label; add_child(n); roots.append(n)
	var api := SceneMultiplayer.new(); api.root_path=n.get_path()
	get_tree().set_multiplayer(api,n.get_path())
	var s := ObservedSession.new(); n.add_child(s); s.set_physics_process(false)
	return s
func _ready() -> void:
	GameData.options.merge({"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0},true)
	var tx := NetInput.new(); var rx := NetInput.new()
	var first := tx.prepare({"t":"move","units":[11],"to":Vector2(20,30)})
	var trade := tx.prepare({"t":"trade","sell":["tiny potion 1"],"buy":[]})
	var stop := tx.prepare({"t":"direct_move","units":[11],"direction":Vector2.ZERO})
	check(rx.receive(stop).is_empty() and rx.receive(trade).is_empty(),"later copies wait for the missing earlier order")
	var ready := rx.receive(first)
	check(ready==[first,trade,stop],"reordered move, trade and final stop dispatch in original order")
	check(rx.receive(first).is_empty() and rx.receive(trade).is_empty() and rx.receive(stop).is_empty(),"late reliable copies cannot repeat any side effect")
	check(rx.last==3 and rx.waiting.is_empty(),"ordered receive window releases its storage")
	check(rx.receive({"_input_seq":3+NetInput.WINDOW+1}).is_empty() and rx.waiting.is_empty(),"far-future sequence cannot allocate an unbounded receive window")
	check(rx.receive({"_input_seq":"4"}).is_empty() and rx.receive({"_input_seq":-1}).is_empty(),"invalid sequence types and values are rejected")
	tx.acknowledge(4)
	check(tx.pending.size()==3,"impossible acknowledgement cannot discard unprocessed input")
	tx.acknowledge(2)
	check(tx.pending.keys()==[3],"cumulative acknowledgement keeps the last unconfirmed stop")
	tx.acknowledge(1)
	check(tx.pending.keys()==[3],"stale acknowledgement leaves pending input intact")
	check(bytes_to_var(tx.packet())==[stop],"retry packet includes an unconfirmed final action without a later click")
	var original := {"units":[7]}; var copy := tx.prepare(original); original.units[0]=8
	check(copy.units==[7],"queued command owns its nested data")
	var large := tx.prepare({"t":"trade","sell":"x".repeat(2000)})
	check(not tx.pending.has(large._input_seq) and large._input_seq==5,"large commands retain a reliable sequence without UDP fragmentation")
	for i in NetInput.WINDOW+10: tx.prepare({"t":"move","to":Vector2(i,i)})
	check(tx.pending.size()==NetInput.WINDOW and tx.packet().size()<=NetInput.PACKET_BYTES,"retry memory and datagram size remain bounded during an outage")
	var host := peer("RetryHost"); var guest := peer("RetryGuest")
	check(host.host(29979,2)==OK,"authority listens on an isolated ENet port")
	var udp := ENetMultiplayerPeer.new()
	check(udp.create_client("127.0.0.1",29979)==OK,"independent multiplayer API opens the guest connection")
	udp.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	var delayed := DelayedReliable.new(); delayed.inner=udp
	udp.peer_connected.connect(delayed._on_connected); udp.peer_disconnected.connect(delayed._on_disconnected)
	guest.is_host=false; guest.online=true; guest.multiplayer.multiplayer_peer=delayed; guest._pool_epoch=0
	check(await until(func():return host.players.size()==2 and guest.players.size()==2),"guest completes normal identity and protocol handshake")
	if failures: get_tree().quit(1); return
	for i in 5: await get_tree().process_frame
	delayed.hold=true; delayed.lose_fast=2
	var started := Time.get_ticks_msec()
	for id in [1,2,3]: guest.submit({"t":"test","test_id":id})
	check(await until(func():return host.applied.size()==3,1000),"lost UDP copies retry before the three-second reliable backlog")
	check(host.applied==[[1,1],[2,1],[3,1]] and delayed.dropped==2,"all three orders execute once and in order for the authenticated guest")
	check(await until(func():return guest._input_out.pending.is_empty(),1000),"authority acknowledgement stops fast retries")
	await until(func():return Time.get_ticks_msec()-started>3400)
	check(host.applied==[[1,1],[2,1],[3,1]],"real delayed canonical packets do not execute the orders again")
	guest.submit({"t":"test","test_id":4,"payload":"x".repeat(2000)})
	guest.submit({"t":"test","test_id":5})
	await until(func():return host._input_in[guest.multiplayer.get_unique_id()].waiting.has(5),1000)
	check(host.applied.size()==3,"fast later order cannot overtake a large reliable-only action")
	check(await until(func():return host.applied.size()==5),"reliable-only action releases following input on arrival")
	check(host.applied.slice(3)==[[4,1],[5,1]],"mixed reliable and fast actions retain exact ordering")
	var pid := guest.multiplayer.get_unique_id()
	host.loading_game=true
	host._receive_cmd({"_input_seq":6,"test_id":6,"_zone":"","_generation":0},pid)
	host.loading_game=false; host.zone_id="new"; host._load_serial=1
	host._receive_cmd({"_input_seq":7,"test_id":7,"_zone":"","_generation":0},pid)
	host._receive_cmd({"_input_seq":8,"test_id":8,"_zone":"new","_generation":1},pid)
	check(host.applied.size()==6 and host.applied[-1]==[8,1],"loading and stale-world orders consume their sequence without entering the new world")
	host._receive_cmd({"_input_seq":9,"test_id":9,"_zone":"new","_generation":1},999)
	check(host.applied.size()==6 and not host._input_in.has(999),"unknown peer cannot create a command stream or dispatch an action")
	host.players[999]={"index":2,"name":"Other"}
	host._receive_cmd({"_input_seq":1,"test_id":9,"_zone":"new","_generation":1},999)
	check(host.applied[-1]==[9,2] and host._input_in[pid].last==8,"each authenticated peer owns an independent sequence")
	host.players.erase(999); host._input_in.erase(999)
	guest.multiplayer.multiplayer_peer.close()
	check(await until(func():return host.players.size()==1 and not host._input_in.has(pid)),"disconnect releases the peer's receive window")
	check(guest.join("127.0.0.1",29979)==OK and await until(func():return host.players.size()==2),"same session can reconnect after the delayed transport closes")
	guest.zone_id="new"; guest._pool_epoch=1
	guest.submit({"t":"test","test_id":10})
	check(await until(func():return host.applied.size()==8) and guest._input_out.serial==1 and host.applied[-1]==[10,1],"reconnected client starts a fresh ordered stream")
	guest.online=false; host.online=false
	guest.multiplayer.multiplayer_peer.close(); host.multiplayer.multiplayer_peer.close()
	for n: Node in roots: n.queue_free()
	for i in 8: await get_tree().process_frame
	print("COMMAND_RETRY %d checks %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)

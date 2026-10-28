extends Node
## Real loopback ENet: owner-only frame motion, ordinary remote delivery,
## chunk membership and the same-time paused refresh path.
class CaptureSession extends Session:
	var received := []
	func _ready() -> void:
		name = "Session"
		set_process(false); set_physics_process(false)
		local_host = LocalHost.new(); local_host.session = self
		_pool_epoch = 0; _load_serial = 0
	func _apply_snap(snaps: Array, time: float, serial := -1, _precise_bodies := false) -> void:
		received.append({"rows":snaps,"time":time,"serial":serial})
	func _exit_tree() -> void:
		local_host.free()

var checks := 0
var failures := 0
var roots: Array[Node] = []

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func branch(label: String) -> CaptureSession:
	var root := Node.new(); root.name = label; add_child(root); roots.append(root)
	var api := SceneMultiplayer.new(); api.root_path = root.get_path()
	get_tree().set_multiplayer(api,root.get_path())
	var session := CaptureSession.new(); root.add_child(session)
	return session

func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func ids(session: CaptureSession) -> Array:
	var found := []
	for packet: Dictionary in session.received:
		for row: Array in packet.rows: found.append(int(row[0]))
	found.sort()
	return found

func _ready() -> void:
	var host := branch("Host")
	var owner := branch("Owner")
	var guest := branch("Guest")
	var server := ENetMultiplayerPeer.new()
	check(server.create_server(0,2)==OK,"server starts on a private ephemeral port")
	host.multiplayer.multiplayer_peer = server
	var port := server.get_host().get_local_port()
	for peer: CaptureSession in [owner,guest]:
		var client := ENetMultiplayerPeer.new()
		check(client.create_client("127.0.0.1",port)==OK,"client connects")
		peer.multiplayer.multiplayer_peer = client
	if not await until(func(): return host.multiplayer.get_peers().size()==2 and owner.multiplayer.get_unique_id()>1 and guest.multiplayer.get_unique_id()>1):
		check(false,"both clients complete connection");get_tree().quit(1);return
	host.local_host.worker = true
	host.local_host.owner_peer = owner.multiplayer.get_unique_id()
	var actor := GameUnit.new()
	var rows := []
	for i in 18:
		actor.uid = 100+i
		actor.controller = 0 if i%3==0 else 1 if i%3==1 else -1
		rows.append(actor.snapshot())
	host._send_snapshot_records(rows,1.0)
	check(await until(func(): return ids(guest).size()==18 and ids(owner).size()==12),"all MTU chunks reach the intended clients")
	check(ids(guest)==range(100,118),"remote guest retains every actor including the owner party")
	check(ids(owner)==range(100,118).filter(func(id):return id%3!=1),"owner receives ordinary guest and NPC updates only")
	owner.received.clear(); guest.received.clear()
	var frame: Array = rows[0].duplicate(true); frame[1] = 1.125
	host._send_snapshot_records([frame],1.0,host.local_host.owner_peer)
	check(await until(func():return not owner.received.is_empty()),"dedicated same-time frame snapshot reaches owner")
	check(owner.received.size()==1 and owner.received[0].rows[0]==frame,"owner receives the exact frame record once")
	check(guest.received.is_empty(),"dedicated owner stream is private to its recipient")
	owner.received.clear();guest.received.clear()
	host.local_host.worker = false
	host._send_snapshot_records(rows,2.0)
	check(await until(func():return ids(owner).size()==18 and ids(guest).size()==18),"inline host retains normal broadcast delivery")
	actor.free()
	for session: CaptureSession in [host,owner,guest]: session.multiplayer.multiplayer_peer.close()
	for root in roots: root.queue_free()
	for i in 4: await get_tree().process_frame
	print("LOCAL_OWNER_DELIVERY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

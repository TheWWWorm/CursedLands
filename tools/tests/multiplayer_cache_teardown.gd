extends Node
## Real ENet RPC cache ownership through disconnect/reconnect and scene removal.
## Old engines log nonexistent tree_exited disconnects while all RPCs succeed.
class RpcNode extends Node:
	var received := 0
	@rpc("any_peer", "call_remote", "reliable")
	func ping() -> void:
		received += 1

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	for cycle in 3:
		var owner := Node.new(); owner.name = "Owner"
		var guest := Node.new(); guest.name = "Guest"
		add_child(owner); add_child(guest)
		var host_mp := SceneMultiplayer.new(); var guest_mp := SceneMultiplayer.new()
		get_tree().set_multiplayer(host_mp, owner.get_path())
		get_tree().set_multiplayer(guest_mp, guest.get_path())
		var server := ENetMultiplayerPeer.new(); var client := ENetMultiplayerPeer.new()
		check(server.create_server(0, 2) == OK, "create server")
		check(client.create_client("127.0.0.1", server.host.get_local_port()) == OK, "create client")
		host_mp.multiplayer_peer = server; guest_mp.multiplayer_peer = client
		var names := ["NetStatus", "Session", "LocalHost", "PlayerSwap"]
		for name: String in names:
			var a := RpcNode.new(); a.name = name; owner.add_child(a)
			var b := RpcNode.new(); b.name = name; guest.add_child(b)
		var end := Time.get_ticks_msec() + 5000
		while guest_mp.get_unique_id() == 1 or host_mp.get_peers().is_empty():
			await get_tree().process_frame
			if Time.get_ticks_msec() > end: break
		check(host_mp.get_peers().size() == 1, "real loopback connected")
		for name: String in names:
			owner.get_node(name).ping.rpc_id(guest_mp.get_unique_id())
			guest.get_node(name).ping.rpc_id(1)
		while Time.get_ticks_msec() < end:
			await get_tree().process_frame
			if (owner.get_node("PlayerSwap") as RpcNode).received == 1 and (guest.get_node("PlayerSwap") as RpcNode).received == 1: break
		for name: String in names:
			check((owner.get_node(name) as RpcNode).received == 1, name + " owner receives")
			check((guest.get_node(name) as RpcNode).received == 1, name + " guest receives")
		for node in owner.get_children() + guest.get_children():
			check(node.get_signal_connection_list("tree_exited").size() == 1, "RPC installed one cache callback")
		# Match main.gd: clear RPC caches before the nodes leave their trees.
		if cycle < 2:
			host_mp.multiplayer_peer = OfflineMultiplayerPeer.new()
			guest_mp.multiplayer_peer = OfflineMultiplayerPeer.new()
			for node in owner.get_children() + guest.get_children():
				check(node.get_signal_connection_list("tree_exited").is_empty(), "cache disconnect releases exact callback")
		owner.free(); guest.free()
		get_tree().set_multiplayer(null, NodePath(str(get_path()) + "/Owner"))
		get_tree().set_multiplayer(null, NodePath(str(get_path()) + "/Guest"))
		for i in 3: await get_tree().process_frame
	var result := {"checks": checks, "failures": failures}
	FileAccess.open("user://multiplayer-cache-teardown.json", FileAccess.WRITE).store_string(JSON.stringify(result))
	print("MULTIPLAYER_CACHE_TEARDOWN ", JSON.stringify(result))
	get_tree().quit(1 if failures else 0)

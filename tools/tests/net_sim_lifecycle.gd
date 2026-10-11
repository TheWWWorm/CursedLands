extends Node
func _ready() -> void:
	var server:=ENetMultiplayerPeer.new();server.create_server(29966,1)
	var client:=ENetMultiplayerPeer.new();client.create_client("127.0.0.1",29966)
	var host:=NetSim.wrap(server) as NetSim;var guest:=NetSim.wrap(client) as NetSim
	if host==null or guest==null:printerr("Pass --netsim=120,40,2");get_tree().quit(1);return
	var end:=Time.get_ticks_msec()+5000
	while host._peers.is_empty() and Time.get_ticks_msec()<end:
		host.poll();guest.poll();await get_tree().process_frame
	var id:=guest.get_unique_id()
	host.set_target_peer(id);host.put_packet(PackedByteArray([1,2,3]))
	host.disconnect_peer(id,true);guest.close()
	for i in 20:host.poll();await get_tree().process_frame
	var ok:=host._out.is_empty() and host._peers.is_empty()
	host.close()
	var weak_host:WeakRef=weakref(host);var weak_guest:WeakRef=weakref(guest)
	host=null;guest=null
	ok=ok and weak_host.get_ref()==null and weak_guest.get_ref()==null
	print("NET_SIM_LIFECYCLE ","PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

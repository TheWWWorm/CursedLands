extends "arena_online.gd"
func _ready() -> void:
	GameData.options.net_lan=1
	var host:=ArenaOnlineSession.new();host.player_name="Worm";host.password="secret";add_child(host)
	check(host.host(29827)==OK,"host starts with discovery")
	var finder:=LanDiscovery.new();finder.discovery_port=ArenaOnlineSession.LAN_PORT;finder.protocol=ArenaOnlineSession.PROTOCOL;finder.modes=PackedStringArray(["autochess"]);add_child(finder);finder.scan(true)
	check(await wait_for(func():return finder.list().size()==1),"local lobby appears without an address")
	var row:Dictionary=finder.list()[0]
	check(row.name=="Worm" and row.port==29827 and row.players==1 and row.max==9 and row.pw and not row.ws,"discovered room details match authority")
	check(row.protocol==ArenaOnlineSession.PROTOCOL and row.mode=="autochess","autochess discovery has its own protocol and mode")
	var coop:=LanDiscovery.new();coop.discovery_port=ArenaOnlineSession.LAN_PORT;add_child(coop);coop.scan(true)
	await get_tree().create_timer(0.65).timeout
	check(coop.list().is_empty(),"co-op browser excludes autochess rooms")
	var guest:=ArenaOnlineSession.new();guest.password="secret";add_child(guest)
	check(guest.join(row.address)==OK,"discovered address connects")
	check(await wait_for(func():return guest.my_seat==1),"discovered room joins")
	check(await wait_for(func():return finder.list()[0].players==2),"room player count refreshes")
	guest.close();host.close()
	check(await wait_for(func():return finder.list().is_empty()),"closed lobby expires")
	check(host.host(29827,true)==OK,"WebSocket host starts")
	check(await wait_for(func():return finder.list().size()==1),"WebSocket lobby appears")
	row=finder.list()[0]
	check(row.ws and row.address.begins_with("ws://") and row.port==29827,"WebSocket discovery preserves transport and port")
	host.close();host.queue_free();guest.queue_free();finder.queue_free();coop.queue_free();await frames(4)
	print("ARENA_LAN_DISCOVERY ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

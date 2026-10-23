extends Node
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func wait_for(predicate: Callable, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return predicate.call()

func frames(count := 12) -> void:
	for index in count: await get_tree().process_frame

func _ready() -> void:
	var host := ArenaOnlineSession.new(); host.player_name = "Host"; add_child(host)
	var guest := ArenaOnlineSession.new(); guest.player_name = "Guest"; add_child(guest)
	check(host.host(29821, false) == OK, "equipment host listens")
	var older := ArenaOnlineSession.new(); older.player_name = "Older build"; add_child(older)
	check(older.join("127.0.0.1:29821") == OK, "older protocol probe connects transport")
	older._connected = true
	check(await wait_for(func(): return older.peer != null and older.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "older protocol reaches handshake")
	older._send(1, {"t":"hello","protocol":1,"version":ProjectSettings.get_setting("application/config/version"),"hash":NetStatus.world_hash(),"name":"Older build","password":""})
	check(await wait_for(func(): return older.peer == null) and host.members.size() == 1, "previous protocol cannot join equipment game with same release label")
	older.queue_free()
	check(guest.join("127.0.0.1:29821") == OK, "equipment guest connects")
	check(await wait_for(func(): return guest.my_seat == 1), "guest obtains independent company")
	if guest.my_seat != 1: get_tree().quit(1); return
	guest.request("ready")
	check(await wait_for(func(): return host.members.values().all(func(member): return member.ready)), "guest readiness reaches host")
	check(host.start_game(11379).is_empty(), "host starts equipment test game")
	check(await wait_for(func(): return guest.started and not guest.last_state.is_empty()), "guest receives authoritative initial state")
	host.game.set_process(false)
	guest.request("buy", [0]); host.request("buy", [0])
	var company := host.game.run.company(1)
	check(await wait_for(func(): return company.army.size() == 1 and host.game.run.army.size() == 1), "both humans own a recruit")
	var uid := int(company.army[0].uid)
	company.offer_items_after(3); host.game.run.offer_items_after(3); host.game.updated.emit()
	check(await wait_for(func(): return guest.view.item_offers.size() == 3), "three reward choices reach remote UI model")
	var chosen := company.item_offers[1]
	var intent: Array = []
	var projection := ArenaOnlineView.new()
	projection.submit = func(action: String, args: Array): intent.assign([action,args])
	projection.choose_item(1)
	check(intent == ["choose_item", [1]] and projection.items.is_empty(), "view sends item choice intent without local mutation")
	guest.view.choose_item(1)
	check(await wait_for(func(): return company.items.size() == 1 and guest.view.items.size() == 1 and guest.view.item_offers.is_empty()), "host chooses one item and synchronizes inventory")
	check(company.items[0].kind == chosen and host.game.run.items.is_empty(), "choice affects only sender's company")
	guest.view.equip_item(int(company.items[0].uid), uid)
	check(await wait_for(func(): return company.item_for(uid) == chosen and guest.view.item_for(uid) == chosen), "authoritative equipment assignment reaches guest")
	check(guest.view.army[0].item == chosen, "guest derived army field stays synchronized")
	var inventory := company.items.duplicate(true)
	check(not host.game.command(1, "equip_item", [0,uid]).is_empty(), "host rejects invalid item UID")
	check(not host.game.command(1, "equip_item", [int(company.items[0].uid),9999]).is_empty(), "host rejects nonexistent carrier")
	check(not host.game.command(1, "choose_item", [1.5]).is_empty(), "host rejects fractional reward index")
	check(not host.game.command(2, "equip_item", [int(company.items[0].uid),uid]).is_empty(), "unowned bot seat cannot submit item commands")
	check(company.items == inventory, "invalid commands preserve ownership")
	guest.view.undo()
	check(await wait_for(func(): return company.item_for(uid).is_empty() and guest.view.item_for(uid).is_empty()), "network undo returns item to stash")
	guest.view.equip_item(int(company.items[0].uid), uid)
	check(await wait_for(func(): return company.item_for(uid) == chosen), "item can be re-equipped before bell")
	var host_first := host.game.run.item_offers[0]
	host.game.start_round()
	check(host.game.run.stage == "fight" and host.game.run.items.size() == 1 and host.game.run.items[0].kind == host_first, "early online start conserves unchosen host reward")
	var battle := host.game.encounter(1)
	check(battle.run.items == company.items and battle.run.items != [], "board owns independent inventory copy")
	check(battle.world.unit_rows().any(func(unit): return unit.get_meta("arena_placement", {}).get("team") == 0 and unit.get_meta("arena_placement", {}).get("item") == chosen), "authoritative battlefield receives equipped kind")
	var before := company.snapshot()
	check(not host.game.command(1, "equip_item", [int(company.items[0].uid),0]).is_empty() and company.snapshot() == before, "host freezes carriers during combat")
	var frame := host.game.board_frame(1,true)
	var replica := ArenaOnlineMatch.new(); replica.rendered = false; replica.run = guest.view
	add_child(replica); var parent := Node3D.new(); add_child(parent); replica._world_parent = parent
	replica.apply_board(frame)
	check(replica.world.unit_rows().any(func(unit): return unit.get_meta("arena_placement", {}).get("team") == 0 and unit.get_meta("arena_placement", {}).get("item") == chosen), "network actor snapshot preserves frozen equipment")
	# Mutating a source inventory after the bell cannot mutate the combat copy.
	company.items[0].unit_uid = 0; company._sync_items()
	check(battle.run.item_for(uid) == chosen, "live company inventory cannot mutate frozen board copy")
	replica.queue_free(); parent.queue_free(); guest.close(); host.close(); guest.queue_free(); host.queue_free()
	await frames(3)
	print("ARENA_EQUIPMENT_ONLINE ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

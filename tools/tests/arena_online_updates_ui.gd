extends "arena_expansion_ui.gd"
## Real guest commands: discovery with default settings, immediate merge
## feedback and authoritative evolved-unit sale previews.
func until(predicate: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<end: await frames(1)
	return predicate.call()

func _ready() -> void:
	OS.add_logger(errors); await frames(24)
	GameData.options.merge({"confine_mouse":0,"auto_graphics":0,"net_upnp":0,"gfx_hd_textures":0},true)
	GameData.options.erase("net_lan")
	GameData._window_gen+=1; get_window().mode=Window.MODE_WINDOWED; get_window().size=Vector2i(1280,800)
	var host := ArenaOnlineSession.new(); host.player_name="LAN fixture"; add_child(host)
	check(host.host(29851)==OK and host.lan.listening(),"normal autochess host advertises without a net_lan setting")
	var panel := ArenaOnlinePanel.new(); add_child(panel); panel.open(); panel.page=NetworkPanel.JOIN_COOP; panel.addresses=PackedStringArray()
	check(await until(func():return panel._items().any(func(item):return item.g.get("name","")=="LAN fixture")),"join screen discovers lobby without typing an address")
	check(panel._items()[0].g.protocol==ArenaOnlineSession.PROTOCOL,"discovered autochess protocol is accepted")
	panel.queue_free(); await frames(3)
	var guest := ArenaOnlineSession.new(); guest.player_name="Guest fixture"; add_child(guest)
	check(guest.join("127.0.0.1:29851")==OK and await until(func():return guest.my_seat==1),"guest joins over ENet")
	guest.request("ready")
	check(await until(func():return host.members.values().all(func(member):return member.ready)),"guest becomes ready")
	check(host.start_game(7319).is_empty(),"tournament starts")
	host.game.set_process(false)
	check(await until(func():return guest.started),"guest receives initial state")
	var online := ArenaOnlineScreen.new(); online.connection=guest; add_child(online); screen=online
	var company := host.game.run.company(1)
	company.army.clear(); company.gold=100; company.training=126
	var kept := int(company._recruit(0,0,1).uid); company._recruit(0,0,1); company.arrange()
	company.shop.assign([{"family":0,"rank":0,"locked":false},{"family":2,"rank":0,"locked":false}])
	host.game.boards._sync_board(1); host._dirty=true
	check(await until(func():return screen.run.army.size()==2 and screen.run.gold==100),"guest receives prepared purchase fixture")
	var events := []
	screen._evolution_notice.shown.connect(func(event):events.append(event.duplicate(true)))
	screen._recruit_offer(0)
	check(await until(func():return screen.run.unit(kept).get("rank",-1)==1),"merging purchase is acknowledged")
	check(await until(func():return events.size()==1),"upgrade notice appears without another purchase")
	check(events[0].old_rank==0 and events[0].rank==1 and events[0].from!=events[0].to,"notice compares distinct before and after forms")
	await shot("online-upgrade")
	screen._recruit_offer(1); await frames(40)
	check(events.size()==1 and screen._evolution_notice.pending.is_empty(),"unrelated purchase cannot repeat old upgrade")
	for rank in [1,2]:
		var uid := int(company._recruit(15,rank,9 if rank==1 else 27).uid)
		company.unit(uid).deployed=false; host._dirty=true
		check(await until(func():return not screen.run.unit(uid).is_empty()),"evolved reserve arrives")
		screen.selected_uid=uid; screen._update_sell_target()
		var quote := company.sale_value(company.unit(uid)); var bank := company.gold
		check(screen._sell_target.visible and screen._sell_target.text==RemakeText.t("Sell · +%d gold")%quote,"visible sale target uses the host's %d-star quote"%(rank+1))
		await shot("online-sale-"+str(rank+1))
		screen._sell_selected()
		check(await until(func():return screen.run.unit(uid).is_empty() and screen.run.gold==bank+quote),"guest receives exactly the quoted sale proceeds")
	guest.close(); host.close(); screen.queue_free(); screen=null; guest.queue_free(); host.queue_free(); await frames(6)
	check(errors.messages.filter(func(message):return not message.begins_with("NO GRAB")).is_empty(),"no runtime/render errors: "+str(errors.messages))
	print("ARENA_ONLINE_UPDATES_UI ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

extends "coop_trade.gd"
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"coop_share_loot":0},true)
	host=peer("MarketHost",true);client=peer("MarketGuest",false)
	check(host.host(29979,2)==OK and client.join("127.0.0.1",29979)==OK,"Astral peers connect")
	check(await until(func():return host.players.size()==2),"two campaign players")
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Guest")
	host.set_physics_process(false)
	await host.enter_zone("bz5h",1,false)
	check(await until(func():return client.world!=null and not client._remote_loading),"both players enter original black market")
	host.world.set_process(false);host.world.set_physics_process(false);host.world.vm.instances.clear()
	host.swap._publish()
	check(not host.swap.separate_bags(0,1),"ordinary class guests share a bag")
	# The original Shaina party change gives a class guest a separate purse.
	# It can happen without a new network join or a different zone id.
	host.state.current_party="Shaina"
	check(CoopProgress.GuestRoles.ensure(host,1),"actual temporary-party operation creates guest purse")
	host.swap._process(0)
	for i in 10:await get_tree().process_frame
	check(host.swap.can_swap_with(1) and client.swap.can_swap_with(0),"new separate purse enables trade on both peers")
	for s:Session in [host,client]:
		var strip:BaseStrip
		for child:Node in s.game.hud._safe_root.get_children():
			if child is BaseStrip:strip=child
		strip._process(0)
		check(strip.visible and strip._cells.size()==2,"player strip appears after purse ownership change")
		check(strip._cells.size()==2 and strip._cells.all(func(cell):return cell[1]!=null),"both visible player cells have portraits")
	var old:=host.state.money
	host.state.money=500
	var purse:=host.coop.purse_entry(1);purse.purse.money=600
	host.swap.send({"t":"request","to":1});client.swap.send({"t":"request","to":0})
	check(await until(func():return host.swap.partner()==1 and client.swap.partner()==0),"portrait trade requests pair both players")
	host.swap.cancel_all()
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root in roots:root.queue_free()
	for i in 5:await get_tree().process_frame
	print("ASTRAL_SWAP ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)

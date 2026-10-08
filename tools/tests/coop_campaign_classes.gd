extends "coop_story.gd"
## Actual campaign database + ENet guest deployment, transfer and reload.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame

func guest_alive(label: String) -> void:
	var hs := host.party_units(1)
	var cs := cg.my_units()
	check(hs.size() == 1 and hs[0].hp > 0 and not hs[0].dead and not hs[0].proto.is_empty(), label + " authority guest has a living native body")
	check(cs.size() == 1 and cs[0].controller == 1 and cs[0].hp > 0 and not cs[0].proto.is_empty(), label + " client controls the same living guest")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	GameData.hero_class = "Human Mercenary Warrior"   # also an older saved preference
	var h := branch("Host",true);host=h.s;hg=h.g
	var c := branch("Guest",false);client=c.s;cg=c.g
	require(host.host(29915,2) == OK)
	GameData.player_name = "Campaign Guest"
	require(client.join("127.0.0.1",29915) == OK)
	require(await until(func():return host.players.size()==2 and client.my_index==1))
	var pid := 0
	for key in host.players:
		if int(host.players[key].index)==1:pid=int(key)
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	for choice: String in Session.COOP_CLASSES + ["Human Hero", "unknown"]:
		host.players[pid].hero = choice
		var chosen := host._hero_proto(1)
		check(not GameData.db.find("monster_prototypes",chosen).is_empty(), "available authority choice for " + choice)
		if not astral and choice in Session.COOP_CLASSES:
			check(chosen == choice, "base class selection preserved: " + choice)
	host.players[pid].hero = "Human Mercenary Warrior"
	var panel := NetworkPanel.new()
	check(not GameData.db.find("monster_prototypes",panel.hero_class()).is_empty(), "network class selector returns an available prototype")
	panel.free()
	host.state = CampaignState.new()
	host.state.ensure_hero(0,"Human Hero")
	host.state.ensure_hero(1,host._hero_proto(1),"Campaign Guest")
	var scene_id := "bz1h" if astral else "gz1g"
	await host.enter_zone(scene_id,1,false)
	require(await until(func():return client.zone_id==scene_id and not client.loading_game and not host.loading_game))
	await frames(15)
	guest_alive("initial deployment")
	var legacy := CampaignState.new()
	legacy.ensure_hero(1,"Human Hero","Old name")
	legacy.heroes[1][0].prototype = "Human Mercenary Warrior"
	legacy.heroes[1][0].str = 61.0
	legacy.heroes[1][0].exp = 654.0
	legacy.heroes[1][0].quick = ["rune:e1"]
	legacy.ensure_hero(1,host._hero_proto(1),"New name")
	check(not GameData.db.find("monster_prototypes",legacy.heroes[1][0].prototype).is_empty(), "old missing class is repaired")
	check(legacy.heroes[1][0].str == 61 and legacy.heroes[1][0].exp == 654 and legacy.heroes[1][0].quick == ["rune:e1"] and legacy.heroes[1][0].name == "New name", "repair retains progress, items and current name")
	var known := CampaignState.new();known.ensure_hero(1,"Human Hero","Kept")
	known.ensure_hero(1,host._hero_proto(1),"Kept")
	check(known.heroes[1][0].prototype == "Human Hero", "valid existing template is preserved")
	if astral:
		# An old serialized missing class is repaired by the real load path,
		# without resetting the owner's earned attributes and experience.
		host.state.heroes[1][0].prototype = "Human Mercenary Warrior"
		host.state.heroes[1][0].str = 61.0
		host.state.heroes[1][0].exp = 654.0
	check(host.save_game("campaign_class")==OK,"guest saves")
	check(await host.load_game_shown("campaign_class"),"guest save loads")
	require(await until(func():return not client.loading_game and not host.loading_game))
	await frames(15)
	guest_alive("after save/load")
	if astral:
		check(host.state.heroes[1][0].str == 61 and host.state.heroes[1][0].exp == 654 and client.state.heroes[1][0].str == 61, "real network load retains the repaired player's progress")
	await host.enter_zone(scene_id,1,false)
	require(await until(func():return not client.loading_game and not host.loading_game))
	await frames(15)
	guest_alive("after zone transfer")
	host.online=false;client.online=false
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root in branches:root.queue_free()
	await frames()
	print("COOP_CAMPAIGN_CLASSES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

func _process(_dt: float) -> void: pass

extends "story_coop_traps_net.gd"
## Village talk in co-op over ENet (bz2g, Airy): the guest's click opens a
## topic list on the guest only, with the guest's hero standing still; the
## pick stages the walk on both peers; the host cannot skip the guest's walk,
## the guest's Space does; the guest's hero ends by Airy on both peers.
const TOPIC := "b.daughter.z0_1"

func loaded() -> bool:
	return client.world != null and client.zone_id == "bz2g" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func airy(s: Session) -> GameUnit:
	for u: GameUnit in s.world.unit_rows():
		if String(u.info.get("name", "")).to_lower() == "daughter": return u
	return null

func space(s: Session) -> void:
	var e := InputEventKey.new(); e.keycode = KEY_SPACE; e.pressed = true
	s.game.hud._dialog._unhandled_input(e)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"scroll_border":0,"control_mode":1},true)
	TutorialPanel.auto_show = false
	host = branch(false); check(host.host(0,2)==OK,"open host")
	host.state = CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	host.state.set_var(0,"b.bz2g.z0",2.0)
	await host.enter_zone("bz2g",1,false)
	host.state.set_var(0,TOPIC,1.0); host.sync_state()
	client = branch(true); GameData.player_name = "Village Guest"
	check(client.join("127.0.0.1",host.host_port)==OK,"connect guest")
	check(await until(loaded),"guest receives the village")
	if client.world == null: await finish(); return
	var a_host := airy(host)
	var guest_hero: GameUnit = host.party_units(1)[0] if not host.party_units(1).is_empty() else null
	check(a_host != null and guest_hero != null,"Airy and the guest's hero are in the village")
	if guest_hero == null: await finish(); return
	check(await until(func(): var r := airy(client); return r != null and client.game.can_talk_to(r), 30),"the guest sees Airy ready to talk")
	var start := guest_hero.pos
	client.game.order_on(airy(client), false)
	check(await until(func(): return client.game.hud._dialog.visible and client.game.hud._dialog._mode == DialogPanel.TOPICS, 10),
		"the guest's click opens the topic list on the guest")
	await frames(10)
	check(not host.game.hud._dialog.visible,"the host's screen shows no topic list")
	check(guest_hero.pos.distance_to(start) < 0.05 and guest_hero.order.get("type","") != "follow" and not guest_hero.has_meta("interact"),
		"the guest's hero stands still while the list is open")
	client.game.hud._dialog._on_topic(0)
	check(await until(func(): return not host.world.vm.briefings._pending_dialog.is_empty() \
		and client.game.hud._dialog._mode == DialogPanel.STAGING and host.game.hud._dialog._mode == DialogPanel.STAGING, 10),
		"picking the topic stages the walk on both peers")
	check(host.world.vm.briefings.active_player == 1 and host.world.dialog_movers.has(guest_hero),"the guest's hero is the one walking")
	space(host)
	await frames(20)
	check(not host.world.vm.briefings._pending_dialog.is_empty() and host.world.dialog_movers.has(guest_hero),"the host's Space does not skip the guest's walk")
	space(client)
	check(await until(func(): return host.world.vm.briefings._pending_dialog.is_empty() \
		and client.game.hud._dialog._mode in [DialogPanel.PLAYING, DialogPanel.LAST] \
		and host.game.hud._dialog._mode in [DialogPanel.PLAYING, DialogPanel.LAST], 10),
		"the guest's Space starts the conversation on both peers")
	check(guest_hero.pos.distance_to(a_host.pos) < 4.0,"the guest's hero stands by Airy (%.1f m from %.1f m)" % [guest_hero.pos.distance_to(a_host.pos), start.distance_to(a_host.pos)])
	check(await until(func(): var r: GameUnit = client.world.units.get(guest_hero.uid); return r != null and r.pos.distance_to(guest_hero.pos) < 0.5, 10),
		"the guest's own screen shows its hero by Airy")
	client.game.hud._dialog._finish()
	check(await until(func(): return host.state.get_pvar(1,TOPIC) == 2.0 and not client.game.hud._dialog.visible, 15),"the guest completes the conversation")
	print("VILLAGE_TALK_COOP ", JSON.stringify({"checks":checks,"failures":failures}))
	await finish()

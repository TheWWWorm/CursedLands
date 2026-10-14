extends "story_coop_traps_net.gd"
## Real authored village actors on ENet. Prepare topic availability without
## advancing unrelated quests, then exercise actual dialogue UI and completion.
var npc_id := 0
var topic := ""

func loaded() -> bool:
	return client.world != null and client.zone_id == "bz1g" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game

func npc(s: Session) -> GameUnit:
	return s.world.units.get(npc_id)

func ready_npc(s: Session) -> void:
	npc(s)._talk_command=0; npc(s)._talk_posted=9
	# Replica readiness is carried separately in the unit snapshot.
	npc(s)._talk_remote_ready=true

func lit(s: Session, refresh := true) -> bool:
	var m := s.game.marks
	if refresh: m._refresh_talk_units()
	m._update_lit()
	return npc(s) in m._lit

func silent(s: Session) -> void:
	freeze(s)
	# Network state batches still need Session physics; only stop the world.
	s.set_physics_process(true)
	s.game.selected.clear()
	s.game.marks.set_process(false)
	s.game.hud._dialog.set_process(false)
	if s.world.vm:
		s.world.vm.instances.clear()
		s.world.vm.briefings.active = ""
		s.world.vm.briefings._pending_dialog = {}
		s.world.vm.briefings._check = INF

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0,"select_type":1,"control_mode":1},true)
	host = branch(false); check(host.host(29947,2)==OK,"open highlight host")
	host.state = CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	host.set_physics_process(false)
	await host.enter_zone("bz1g",1,false); silent(host)
	var elder: GameUnit = host.world.vm._by_name("Elder")
	check(elder != null,"original village elder exists")
	if elder == null: await finish(); return
	npc_id = elder.uid
	topic = "b.elder.s1"
	for key: String in host.state.gs_keys(0,"b.",true): host.state.set_var(0,key,2)
	host.state.set_var(0,topic,1)
	host.state.set_var(0,"b.elder.constr1",1)
	elder.command({"type":"stop"}); elder._talk_command=0; elder._talk_posted=9
	check(lit(host),"ordinary pending speech highlights original actor")
	# Expired cached membership must be invalidated before the scan deadline.
	host.state.set_var(0,topic,2)
	check(not lit(host,false),"completed speech clears immediately, even with shop topic left")
	host.state.set_var(0,topic,1)
	check(lit(host),"newly offered speech highlights again")
	elder.hidden=true
	check(not lit(host,false),"hidden actor is never a conversation cue")
	elder.hidden=false
	elder._talk_command=1
	check(not lit(host,false),"busy actor loses cached highlight immediately")
	elder._talk_command=0
	check(lit(host),"ready actor can regain cue")
	host.world.erase_unit(npc_id)
	check(not lit(host,false),"removed actor cannot retain cached cue")
	host.world.set_unit(npc_id,elder)
	check(lit(host),"restored registered actor can highlight")
	host.world.zone.type="combat"
	check(not lit(host,false),"field play does not advertise village-only conversation")
	host.world.zone.type="brief"
	host.state.set_var(0,topic,2)
	check(not lit(host),"shop-only topics never count as new speech")
	host.state.set_var(0,"b.elder.ConStr2",1)
	check(not lit(host),"shop prefix filter also handles mixed case")
	host.state.set_var(0,topic,1)
	# Other white-light reasons survive suppression of the talk reason.
	host.game.hud._dialog.show_topics({"player":0,"uid":npc_id,"options":[{"var":topic,"title":"Speech"}]})
	check(not lit(host),"topic list hides the attention cue")
	host.game.marks.flash(elder,4)
	check(lit(host),"electrical hit flash remains independent during dialogue")
	host.game.marks._flash.clear()
	GameData.options.select_type=0; host.game.selected.assign([elder])
	check(lit(host),"selection remains independent during dialogue")
	host.game.selected.clear(); GameData.options.select_type=1
	host.game.hud._dialog.visible=false
	check(lit(host),"cancelling topics restores a still-pending cue")
	client=branch(true); GameData.player_name="Highlight Guest"
	check(client.join("127.0.0.1",29947)==OK,"connect highlight guest")
	check(await until(loaded),"guest receives actual village and pending topic")
	if client.world == null: await finish(); return
	silent(client)
	for s:Session in [host,client]:
		ready_npc(s)
		check(lit(s),"peer %d sees pending speech"%s.my_index)
	npc(client)._talk_remote_ready=false
	check(not lit(client,false),"guest immediately respects a busy actor snapshot")
	ready_npc(client)
	# Authoritative staging event must hide the cue before the next scan.
	host.world.vm.briefings.play_named("s1",topic,1,elder,false,true)
	check(await until(func():return client.game.hud._dialog.visible),"staging reaches guest")
	for s:Session in [host,client]:
		check(not lit(s,false),"peer %d removes highlight during staging"%s.my_index)
	# Finish walking and final facing independently of this cue-only fixture.
	for i in 2:
		host.world.dialog_movers.clear(); host.world.vm.briefings.staging_tick()
	check(await until(func():return client.game.hud._dialog._mode != DialogPanel.STAGING),"phrases reach guest")
	for s:Session in [host,client]:
		# Finished staging leaves a talk-ready actor. The dialog itself must
		# suppress the cue even when a snapshot no longer marks it busy.
		ready_npc(s)
		check(not lit(s),"peer %d has no cue during phrases"%s.my_index)
	# A local finish hides the panel before its reliable command round trip.
	client.game.hud._dialog.visible=false
	check(not lit(client),"local UI close cannot relight before host confirmation")
	# Observe the exact close-event boundary while campaign delivery is delayed.
	host.broadcast({"t":"dialog_close","id":topic,"completed":topic,"player":1})
	check(await until(func():return not host.game.hud._dialog.visible and not client.game.hud._dialog.visible),"close event reaches both panels")
	await frames(4)
	check(client.state.get_pvar(1,topic)==1,"close boundary still has old guest topic state")
	check(not lit(client),"consumed topic stays dark before campaign state arrives")
	# Finish through real authority; it sets the topic and queues a state
	# update after restoring the player's purse, even without reward changes.
	host.world.vm.ast.scripts.clear()
	host.world.vm.briefings.complete(1,topic,true)
	check(await until(func():return client.state.get_pvar(1,topic)==2),"completion promptly delivers consumed topic to guest")
	for s:Session in [host,client]:
		ready_npc(s)
		check(not lit(s),"peer %d stays dark with only shop entries"%s.my_index)
	# New authoritative offers, including repeatable topics, are not muted.
	host.state.set_var(0,topic,1); host.sync_state()
	check(await until(func():return client.state.get_pvar(1,topic)==1),"renewed topic reaches guest")
	for s:Session in [host,client]:
		check(lit(s,false),"peer %d immediately shows renewed speech after state event"%s.my_index)
	print("DIALOGUE_HIGHLIGHTS ",checks," checks ",failures," failures")
	await finish()

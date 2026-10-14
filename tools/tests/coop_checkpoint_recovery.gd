extends "story_coop_traps_net.gd"
## Optional private save-pair validation. Inputs are separate recovery copies,
## never overwritten. Exercise actual solo loading, ENet bring/hello and
## progress-package save/load; keep the host's authored VM snapshot intact.
var host_path := ""
var guest_path := ""

func loaded() -> bool:
	return client.world != null and client.zone_id==host.zone_id and client.my_index==1 \
		and not client.loading_game and not client._remote_loading and not client._zone_holding

func quiet(s:Session) -> void:
	freeze(s); s.set_physics_process(true)
	if s.world.vm: s.world.vm.briefings._check=INF
	s.game.set_process(false)

func _ready() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint-host="):host_path=arg.trim_prefix("--checkpoint-host=")
		if arg.begins_with("--checkpoint-guest="):guest_path=arg.trim_prefix("--checkpoint-guest=")
	check(not host_path.is_empty() and not guest_path.is_empty(),"private recovery paths were supplied")
	if failures: await finish();return
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	var h:=CampaignState.load_from(host_path)
	var own:=CampaignState.load_from(guest_path)
	check(h!=null and own!=null,"both recovered saves load")
	if h==null or own==null:await finish();return
	check(h.current_zone=="bz8k" and own.current_zone==h.current_zone and own.day==h.day,"host and friend share the Ingos/day checkpoint")
	var guest_name:=String(h.coop.host.joiners.values()[0].name)
	var expected_hero:Dictionary=own.heroes[0][0].duplicate(true)
	var expected_bag:=CoopProgress.main_bag(own).duplicate(true)
	# First prove the returned file can resume as a real single-player game.
	var solo:=branch(false)
	check(solo._load_state("private-recovery",own),"friend copy resumes through normal solo load")
	quiet(solo)
	check(solo.party_units(0).size()==1,"solo continuation deploys only its protagonist")
	check(solo.party_units(0)[0].pos.distance_to(expected_hero.pos)<0.03,"solo continuation resumes friend's Ingos position")
	check(solo.world.vm._by_name("Hero")==solo.party_units(0)[0],"original scripts resolve the recovered protagonist")
	check(solo.state.get_var(0,"b.Shopper.Tr49_1")==h.get_var(0,"b.Shopper.Tr49_1"),"completed dialogue sequence remains at its saved step")
	if DisplayServer.get_name()!="headless":
		await frames(8)
		solo.game.get_viewport().get_texture().get_image().save_png("user://recovered-ingos-solo.png")
	solo.get_parent().queue_free(); await frames(8)
	host=branch(false); GameData.player_name="Recovery Host"
	check(host.host(29958,2)==OK,"host recovered campaign over ENet")
	check(host._load_state("private-recovery",h),"host resumes unchanged Ingos world")
	quiet(host)
	check(host._loaded_absent_players==[1],"save load remembers the absent guest")
	var host_unit:GameUnit=host.party_units(0)[0]
	var host_after_load:=host.world.nav.nearest_walkable(host_unit.pos+Vector2(2,0))
	host_unit.pos=host_after_load;host_unit.resync_drawn()
	# Temporary test profile only: the selected origin stays byte-for-byte.
	check(own.save(SaveInfo.path("recovered-guest-origin"))==OK,"stage guest origin in isolated test profile")
	var source_bytes:=FileAccess.get_file_as_bytes(SaveInfo.path("recovered-guest-origin"))
	CoopProgress.bring_slot="recovered-guest-origin"
	client=branch(true); GameData.player_name=guest_name
	check(client.join("127.0.0.1",29958)==OK,"friend joins using recovered personal save")
	check(await until(loaded),"recovered pair completes actual ENet join")
	if client.world==null:await finish();return
	quiet(client); CampaignState.watch=host.coop._on_var
	var e:Dictionary=host.coop.joiners.get(guest_name,{})
	check(e.get("clean",false) and e.get("present",false) and e.get("in_sync",false),"ordinary bring/hello restores full story continuity")
	check(host.party_units(1).size()==1 and host.party_units(1)[0].pos.distance_to(expected_hero.pos)<0.03,"friend retains current Ingos position when rejoining")
	check(host_unit.pos.distance_to(host_after_load)<0.03,"restoring the guest does not rewind the host's movement")
	check(host._loaded_absent_players.is_empty(),"the saved arrival position is consumed once")
	check(host.state.heroes[1][0].exp==expected_hero.exp and host.coop.bag_of(1)==expected_bag.items,"rejoining retains own skills and bag")
	# Genuine post-completion objective remaining in the supplied host save.
	host.state.set_var(0,"q.gz10g.q36ag.12",2)
	host.state.day+=1
	host.coop._sent_hash.clear(); host.coop.send_all()
	check(await until(func():return not client.coop.last_merged.is_empty()),"friend receives an actual saved progress package")
	var merged:CampaignState
	check(await until(func():
		var save:=CampaignState.load_from(SaveInfo.path(client.coop.last_merged))
		return save!=null and save.day==host.state.day),"new shared day reaches the friend save")
	merged=CampaignState.load_from(SaveInfo.path(client.coop.last_merged))
	check(merged!=null and merged.current_zone==host.zone_id and merged.get_var(0,"q.gz10g.q36ag.12")==2,"location and completed-quest update persist together")
	check(merged!=null and CoopProgress.main_bag(merged)==expected_bag,"repeated network merge preserves personal wealth")
	check(FileAccess.get_file_as_bytes(SaveInfo.path("recovered-guest-origin"))==source_bytes,"network updates leave selected origin untouched")
	check(host.save_game("recovery-authority-roundtrip")==OK,"host continuity survives ordinary save")
	var saved:=CampaignState.load_from(SaveInfo.path("recovery-authority-roundtrip"))
	check(saved!=null and saved.coop.host.joiners[guest_name].clean,"host saves the continuing checkpoint")
	CoopProgress.bring_slot=""
	print("COOP_CHECKPOINT_RECOVERY checks=",checks," failures=",failures)
	await finish()

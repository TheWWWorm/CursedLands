extends "story_coop_traps_net.gd"
## Load an earlier playthrough's already-resurrected Terror, join a real guest,
## transfer through Catacombs and return, then save/reload both peers.
## The supplied source save is read-only; all writes use a disposable profile.
var saved_portal := {}

func loaded() -> bool:
	return client.world != null and client.zone_id == host.zone_id and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	var path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.trim_prefix("--save=")
	var source := CampaignState.load_from(path)
	check(source != null,"read earlier playthrough save")
	if source == null: await finish(); return
	saved_portal = source.zones.get("gz1h",{}).duplicate(true)
	check(source.get_var(0,"q.gz1h.q02h.2") == 2.0 and saved_portal.get("units",{}).has(666666),
		"source contains live Terror after its completed escape removal")
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	check(DirAccess.copy_absolute(path,SaveInfo.path("terror_source")) == OK,"copy checkpoint into isolated profile")
	host = branch(false); check(host.host(29941,2) == OK,"open real host")
	host.set_physics_process(false)
	check(await host.load_game_shown("terror_source"),"load contaminated save through normal load path")
	freeze(host)
	check(host.zone_id == "gz1h","checkpoint opens Portal")
	check(not host.world.units.has(666666),"completed escape Terror is absent before world ticks")
	check(host.state.get_var(0,"q.gz1h.q02h") == source.get_var(0,"q.gz1h.q02h"),"repair does not change quest completion")
	check(host.state.money == source.money and host.state.items == source.items,"repair does not change money or inventory")
	var untouched := true
	for id: int in saved_portal.units:
		if id == 666666: continue
		var u: GameUnit = host.world.units.get(id)
		var row: Array = saved_portal.units[id]
		untouched = untouched and u != null
		if u: untouched = untouched and u.pos.distance_to(Vector2(row[0],row[1])) < 0.01 and is_equal_approx(u.hp,float(row[2]))
	check(untouched,"other saved Portal inhabitants keep positions and health")
	client = branch(true); GameData.player_name = "Terror Guest"
	check(client.join("127.0.0.1",29941) == OK,"join repaired world")
	check(await until(loaded),"guest receives Portal")
	if failures > 5 or client.world == null: await finish(); return
	freeze(client)
	check(not client.world.units.has(666666),"late guest does not receive removed Terror")
	for target: String in ["gz1d2", "gz1h"]:
		await host.enter_zone(target,1,false)
		freeze(host)
		check(await until(loaded),"both peers finish full world transfer to " + target)
		freeze(client)
	check(not host.world.units.has(666666) and not client.world.units.has(666666),"Terror stays absent after Catacombs return on both peers")
	check(host.save_game("terror_repaired") == OK,"save repaired return to Portal")
	var repaired := CampaignState.load_from(SaveInfo.path("terror_repaired"))
	check(repaired.zones.gz1h.removed.has(666666) and not repaired.zones.gz1h.units.has(666666),"new save records the removal permanently")
	check(await host.load_game_shown("terror_repaired"),"reload repaired Portal save")
	freeze(host)
	check(await until(loaded),"client completes reload")
	freeze(client)
	check(not host.world.units.has(666666) and not client.world.units.has(666666),"reload remains free of resurrected Terror")
	await finish()

func finish() -> void:
	for s: Session in [client,host]:
		if is_instance_valid(s):
			s.online=false
			if s.multiplayer.multiplayer_peer: s.multiplayer.multiplayer_peer.close()
	for root: Node in branches:
		if is_instance_valid(root): root.queue_free()
	await frames(8)
	print("TERROR_REVISIT_NET ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)

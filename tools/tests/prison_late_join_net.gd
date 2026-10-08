extends "story_coop_traps_net.gd"
## Real ENet arrival after the native prison startup has armed its checks.
## Freeze unrelated AI/combat; manually advance the original script threads.

func loaded() -> bool:
	return client.world != null and client.zone_id == "gz15h" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func connect_guest() -> bool:
	client = branch(true); GameData.player_name = "Prison Guest"
	check(client.join("127.0.0.1",29933) == OK,"connect late prison guest")
	var ready := await until(loaded)
	check(ready,"late guest receives running prison map")
	if ready: freeze(client)
	return ready

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0},true)
	host = branch(false); check(host.host(29933,2) == OK,"open prison host")
	host.state = CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	host.state.set_var(0,"q.gz15h.q60h",1); host.set_physics_process(false)
	await host.enter_zone("gz15h",1,false); freeze(host)
	var leader: GameUnit = host.party_units(0)[0]; leader.pos = Vector2(10,10); leader.resync_drawn()
	ticks(12)
	var vm := host.world.vm
	check(vm.instances.any(func(i):return i.sname=="VCheck#0#106" and not i.killed),"native startup arms the original escape rectangle")
	# Keep the actual pending native check, removing unrelated quest/cutscene
	# threads so the fixture can inspect delivery before automatic map travel.
	vm.instances = vm.instances.filter(func(i):return i.sname=="VCheck#0#106")
	if not await connect_guest(): await finish(); return
	var guest := visitor(); check(guest != null,"late guest has a controllable actor")
	if guest == null: await finish(); return
	guest.pos = Vector2(209,318); guest.resync_drawn(); ticks(5)
	check(host.state.get_var(0,"q.gz15h.q60h")==2,"late guest alone completes the authored prison objective")
	check(leader.pos==Vector2(10,10),"host stays outside the objective rectangle")
	host.sync_state()
	check(await until(func():return client.state.get_var(0,"q.gz15h.q60h")==2,10),"client receives completed quest state")
	check(host.save_game("prison-late-guest")==OK,"save completed late-guest objective")
	check(await host.load_game_shown("prison-late-guest"),"load completed late-guest objective")
	freeze(host)
	if not await until(loaded): check(false,"saved prison delivery"); await finish(); return
	freeze(client); ticks(3)
	check(host.state.get_var(0,"q.gz15h.q60h")==2 and client.state.get_var(0,"q.gz15h.q60h")==2,"completed objective persists on both peers")
	client.multiplayer.multiplayer_peer.close()
	var old_root: Node = branches.back(); branches.erase(old_root); old_root.queue_free()
	check(await until(func():return host.players.size()==1),"host observes guest disconnect")
	if not await connect_guest(): await finish(); return
	ticks(3)
	check(host.world.vm._world_done.has("VCheck#0#106") and host.state.get_var(0,"q.gz15h.q60h")==2,"reconnect retains the spent shared trigger")
	await finish()

extends "coop_story.gd"
## The host sends the zone message before it prepares the static navigation
## and services its ENet peer while the preparation runs, so a client spawns
## its replicas meanwhile; the preparation still completes before the host's
## load ends.
var checks := 0
var fails: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails.append(label)
		printerr("FAIL ", label)

## Records, when the zone message's records are serialised, whether the
## live units' movement classes were already prepared.
class ProbeSession extends Session:
	var records_calls := 0
	var prepared_at_records := {}
	func _unit_records() -> Array:
		records_calls += 1
		if records_calls == 1 and world and world.nav:
			for u: GameUnit in world.units.values():
				if u.dead: continue
				for cls: int in [u.move_class(), u._classes[2]]:
					if not prepared_at_records.has(cls):
						prepared_at_records[cls] = world.nav.native_graph(world.nav.layer(cls)).components_prepared
		return super()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp": 0, "net_websocket": 0, "net_directory": 0, "net_lan": 0, "auto_graphics": 0,
		"autosave": 0, "show_tutorial": 0}, true)
	GameData.player_name = "Publish Host"
	# The host branch with the probe session (coop_story.branch makes a plain one).
	var root := Node.new()
	root.name = "Host"
	add_child(root)
	branches.append(root)
	var api := SceneMultiplayer.new()
	api.root_path = root.get_path()
	get_tree().set_multiplayer(api, root.get_path())
	var probe := ProbeSession.new()
	root.add_child(probe)
	hg = Game.new()
	hg.session = probe
	probe.game = hg
	root.add_child(hg)
	host = probe
	var c := branch("Client", false)
	client = c.s
	cg = c.g
	require(host.host(29967, 3) == OK)
	GameData.player_name = "Publish Guest"
	require(client.join("127.0.0.1", 29967) == OK)
	require(await until(func(): return host.players.size() == 2 and client.players.size() == 2))
	host.state.ensure_hero(0, "Human Hero")
	host.state.ensure_hero(1, "Human Hero")
	check(ClassDB.class_exists("TerrainSearchKernel"), "the native navigation kernel is available")
	await host.enter_zone("gz1g", 1, false)
	check(host.world != null and host.zone_id == "gz1g", "the host enters the zone")
	check(probe.records_calls >= 1, "the zone message serialised the records")
	var classes: Array = probe.prepared_at_records.keys()
	check(not classes.is_empty(), "the live units name their movement classes (%d)" % classes.size())
	check(not classes.is_empty() and classes.all(func(cls: int) -> bool: return not probe.prepared_at_records[cls]),
		"the zone message's records are serialised before the static navigation preparation")
	var nav: NavGrid = host.world.nav
	check(not classes.is_empty() and classes.all(func(cls: int) -> bool: return nav.native_graph(nav.layer(cls)).components_prepared),
		"the host still prepares every live class before its load ends")
	for cls: int in classes:
		var stats: Dictionary = nav.native_graph(nav.layer(cls))._terrain_kernel.topology_stats()
		check(int(stats.weighted_blocks) >= int(stats.components), "class %d: the occupied components' route weights are prepared" % cls)
	require(await until(func(): return client.world != null and not client.loading_game and client.zone_id == "gz1g", 120.0))
	check(client.world.units.size() == host.world.units.size(),
		"the client spawned every record (%d of %d)" % [client.world.units.size(), host.world.units.size()])
	# An rpc transmits its first packets as it is put; the rest of a large
	# reliable message needs the peer serviced, which the preparation's wait
	# does (Portability.group's pump, NetStatus.service).
	var enet_host: ENetConnection = NetSim.enet_of(host.multiplayer).get_host()
	enet_host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)   # reset the counter
	host.sync_state()
	check(enet_host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS) > 0, "an rpc transmits its packet as it is put")
	# Reference containers: a lambda captures plain values by copy.
	var main_thread := OS.get_thread_caller_id()
	var pumped := {"calls": 0, "threads": {}}
	var pump := func() -> void:
		pumped.calls += 1
		pumped.threads[OS.get_thread_caller_id()] = true
	var done: Array = []
	done.resize(16)
	done.fill(0)
	Portability.group(func(i: int) -> void:
		OS.delay_msec(20)
		done[i] = 1, 16, true, pump)
	check(done.count(1) == 16, "a pumped group still runs every job")
	check(pumped.calls > 0 and pumped.threads.size() == 1 and pumped.threads.has(main_thread),
		"the pumped wait calls the pump on the caller's thread (%d calls)" % pumped.calls)
	var pool_pumped := {"calls": 0}
	Portability.group(func(_i: int) -> void: OS.delay_msec(20), 2, false, func() -> void: pool_pumped.calls += 1)
	check(pool_pumped.calls > 0, "the pool path pumps as well (%d calls)" % pool_pumped.calls)
	print("ZONE_PUBLISH_ORDER ", checks, " checks ", fails.size(), " failures")
	get_tree().quit(1 if fails.size() else 0)

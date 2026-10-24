extends Node
## Separate-process acceptance: six rounds include both creeps and PvP.
var connection: ArenaOnlineSession
var checks := 0
var failures: Array[String] = []
var hosting := false
var expansion := false
var rabbit_blasts := 0
var finished := false
var frames_received := 0
var fight_frames := 0
var rounds_seen: Array[int] = []
var pvp_seen: Array[int] = []
var last_ready := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL ", message)

func wait_for(predicate: Callable, seconds := 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return predicate.call()

func _process(dt: float) -> void:
	if connection == null or connection.last_state.is_empty(): return
	if hosting and connection.game and not finished:
		# Accelerate only the fixture's authority, never either replica.
		connection.game.advance_clock(minf(dt * 8, 0.4))
	if not rounds_seen.has(connection.view.wave): rounds_seen.append(connection.view.wave)
	if connection.view.global_stage == "fight" and not connection.view.is_creep_round() and not pvp_seen.has(connection.view.wave):
		pvp_seen.append(connection.view.wave)
	if connection.view.stage == "prepare" and last_ready != connection.view.wave:
		last_ready = connection.view.wave
		for offer in 3: connection.request("buy", [offer])
		connection.request("arrange")
		connection.request("ready")
	if hosting and connection.game.run.wave >= 6 and connection.game.run.stage == "result": finished = true

func _ready() -> void:
	GameData.options.merge({"net_upnp":0,"net_lan":0,"auto_graphics":0,"confine_mouse":0}, true)
	var transport := "enet"
	var port := 30210
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--peer-role="): hosting = arg.ends_with("host")
		elif arg.begins_with("--peer-transport="): transport = arg.get_slice("=",1)
		elif arg.begins_with("--peer-port="): port = int(arg.get_slice("=",1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="):
			GameData.campaign_roots[CampaignProfile.ASTRAL] = arg.trim_prefix("--astral-path=")
			expansion = true
	if expansion:
		check(ArenaExpansion.mount(), "independent process mounts LiA")
		GameData.arena_character = "lia_hero" if hosting else "lia_merc8"
	connection = ArenaOnlineSession.new()
	connection.expansion = expansion
	connection.effects_received.connect(func(data):
		for event: Dictionary in data.get("events", []):
			if event.get("effect", "") == "popper_blast": rabbit_blasts += 1)
	connection.player_name = "Host process" if hosting else "Guest process"
	add_child(connection)
	connection.board_received.connect(func(data):
		frames_received += 1
		if int(data.phase) == ArenaMatch.Phase.FIGHT: fight_frames += 1)
	if hosting:
		check(connection.host(port,transport == "websocket") == OK,"host listens")
		print("ARENA_ONLINE_LISTENING ", transport)
		check(await wait_for(func():return connection.members.size() == 2),"independent guest joins")
		check(await wait_for(func():return connection.members.values().all(func(member):return member.ready)),"guest becomes ready")
		check(connection.start_game(194731).is_empty(),"host starts tournament")
		if connection.game:
			connection.game.set_process(false)
			if expansion:
				for seat in [0, 1]:
					var company := connection.game.run.company(seat)
					company.army.clear()
					for family in [32, 33, 35] if seat == 0 else [32, 34, 37]: company._recruit(family, 0, 1)
					company.arrange()
				connection.game._prepare(); connection._dirty = true
	else:
		check(connection.join(("ws://" if transport == "websocket" else "") + "127.0.0.1:%d" % port) == OK,"guest connects")
		check(await wait_for(func():return connection.my_seat == 1),"guest has separate seat")
		connection.request("ready")
	check(await wait_for(func():return connection.view.wave == 6 and connection.view.global_stage == "result",150),"six native rounds finish across processes")
	finished = true
	check(rounds_seen == [1,2,3,4,5,6],"every round reaches the replica")
	check(pvp_seen == [4,6],"both PvP rounds reach the replica")
	check(frames_received > 20 and fight_frames > 10,"live battle snapshots arrive")
	check(connection.view.army.size() > 0,"own purchases remain in the company")
	check(connection.view.rivals.all(func(rival):return rival.shop.is_empty()),"other players' offers stay private")
	if expansion:
		check(connection.view.expansion and connection.view.rivals.all(func(r): return r.expansion), "expansion mode reaches every company")
		check(connection.view.commander == ("lia_hero" if hosting else "lia_merc8"), "native LiA identity reaches the correct seat")
		check(connection.view.army.any(func(entry): return String(entry.prototype).begins_with(ArenaExpansion.PREFIX)), "LiA recruits survive rounds and snapshots")
		check(rabbit_blasts > 0, "rabbit death effects arrive from the authority")
	var report := {"role":"host" if hosting else "client","transport":transport,"checks":checks,
		"health":connection.last_state.get("health",[]),"placements":connection.last_state.get("placements",[]),
		"expansion":expansion,"rabbit_blasts":rabbit_blasts,"rounds":rounds_seen,"pvp_rounds":pvp_seen,"board_frames":frames_received,"fight_frames":fight_frames}
	if hosting:
		check(await wait_for(func():return connection.members.size() == 1),"guest leaves after the sixth result")
		check(not connection.game.run.humans.has(1),"computer takes over the departed company")
	else: connection.close()
	report.checks = checks; report["failures"] = failures
	var file := FileAccess.open("user://online-peer.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	connection.close()
	print("ARENA_ONLINE_PEER ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

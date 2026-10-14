extends Node
## Optional private Ingos save regression. Supply --quest-save=/path/quick.sav
## and an isolated user profile. The authority runs in the shipping worker;
## both clients walk normally into the original Mine1 trigger. No quest flags
## or VM instances are changed. A matching guest is derived only in the test
## profile from the save's retained personal context, purse and tally.
const PartyProgress = preload("res://src/game/coop_party_progress.gd")
const QUEST := "q.gz12k.q54k"
var host: Session
var guest: Session
var checks := 0
var failures := 0
var port := 29984

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func until(test: Callable, seconds := 45.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if test.call(): return true
		await get_tree().process_frame
	return bool(test.call())

func pause(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func hero(s: Session) -> GameUnit:
	var units := s.party_units(s.my_index)
	return units[0] if not units.is_empty() else null

func ready(s: Session) -> bool:
	return s.world != null and hero(s) != null and not s.loading_game \
		and not s._remote_loading and not s._zone_holding

func move(s: Session, destination: Vector2) -> void:
	s.submit({"t":"move", "units":[hero(s).uid], "x":destination.x, "y":destination.y})

func merged() -> CampaignState:
	return CampaignState.load_from(SaveInfo.path(guest.coop.last_merged)) if guest.coop.last_merged else null

func stop_host() -> void:
	await host.net.leave()
	await host.local_host.stop()

func finish() -> void:
	if is_instance_valid(host): await stop_host()
	if is_instance_valid(guest):
		guest.online = false
		guest.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	print("QUEST_CHECKPOINT_WORKER ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var source := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--quest-save="): source = arg.trim_prefix("--quest-save=")
		if arg.begins_with("--quest-port="): port = arg.trim_prefix("--quest-port=").to_int()
	GameData.options.merge({"autosave":0, "show_tutorial":0, "net_upnp":0,
		"net_lan":0, "net_directory":0, "net_websocket":0, "auto_graphics":0, "control_mode":1}, true)
	var saved := CampaignState.load_from(source)
	check(saved != null and saved.current_zone == "gz12k", "load supplied Ingos checkpoint")
	if failures: await finish(); return
	var source_bytes := FileAccess.get_file_as_bytes(source)
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	check(saved.save(SaveInfo.path("quest-source")) == OK, "stage unchanged host checkpoint in test profile")
	var own := CampaignState.load_from(source)
	var entry: Dictionary = own.coop.host.joiners.values()[0]
	var personal := PartyProgress.read(entry.party_context)
	check(personal != null, "retained guest has a complete personal context")
	if failures: await finish(); return
	PartyProgress.apply(own, personal)
	own.heroes.erase(1)
	own.items = entry.purse.items.duplicate(true)
	own.money = entry.purse.money
	own.coop = {"applied":{String(entry.sid):{"seq":int(entry.seq)}}}
	check(own.save(SaveInfo.path("quest-guest")) == OK, "stage matching personal guest checkpoint")
	host = Session.new(); get_parent().add_child(host)
	var game := Game.new(); game.session = host; host.game = game; get_parent().add_child(game)
	check(await host.local_host.start(port, 2, false) == OK, "start actual authoritative worker")
	check(await host.load_game_shown("quest-source"), "load original save through worker RPC")
	if failures: await finish(); return
	var viewport := SubViewport.new(); viewport.size = Vector2i(640,360); viewport.own_world_3d = true; add_child(viewport)
	var api := SceneMultiplayer.new(); api.root_path = viewport.get_path(); get_tree().set_multiplayer(api, viewport.get_path())
	var main := Node.new(); main.name = "Main"; viewport.add_child(main)
	guest = Session.new(); main.add_child(guest)
	var guest_game := Game.new(); guest_game.session = guest; guest.game = guest_game; main.add_child(guest_game)
	GameData.player_name = String(entry.name); CoopProgress.bring_slot = "quest-guest"
	check(guest.join("127.0.0.1", port) == OK, "connect second player over ENet")
	check(await until(func(): return ready(guest) and guest.my_index == 1), "both players finish loading")
	check(await until(func(): return merged() != null), "guest receives automatic progress save")
	if failures: await finish(); return
	var initial := merged()
	check(initial.current_zone == "gz12k" and not initial.zones.gz12k.vm.is_empty(), "automatic progress includes resumable world and VM")
	check(host.state.get_var(0, QUEST + ".3") != 2, "mine entrance objective starts pending")
	var mine := Vector2.ZERO
	for row: Dictionary in host.world.mob.objects:
		if int(row.get("nid", 0)) == 5657: mine = Vector2(row.position.x, row.position.y)
	check(mine != Vector2.ZERO, "resolve authored Mine1 location")
	for s: Session in [host, guest]: move(s, mine)
	check(await until(func(): return host.state.get_var(0, QUEST + ".3") == 2 or not host.local_host._process_alive(), 60), "reach native mine quest transition")
	await pause(6)
	check(host.local_host._process_alive(), "server survives automatic quest-progress checkpoint")
	if failures: await finish(); return
	check(host.state.get_var(0, QUEST) == 2 and host.state.get_var(0, "q.gz14k.q55k") == 1, "original quest completes and starts Find the Princess")
	check(await until(func():
		var st := merged()
		return st != null and st.get_var(0, QUEST + ".3") == 2 and st.zones.gz12k.vm != initial.zones.gz12k.vm),
		"guest saves completed objective with updated world checkpoint")
	for cycle in 2:
		var before := [hero(host).pos, hero(guest).pos]
		var time_before := host.world.time
		for i in 2: move([host,guest][i], before[i] + Vector2(-4,-4))
		await pause(5)
		for i in 2: check(hero([host,guest][i]).pos.distance_to(before[i]) > 2, "player %d moves after quest, cycle %d" % [i,cycle])
		check(host.world.time > time_before + 3, "authority keeps simulating after quest")
	var result := await host.local_host.request("save", {"slot":"quest-after"})
	check(result.get("ok", false) and not result.get("queued", true), "full host save succeeds after quest")
	var after := CampaignState.load_from(SaveInfo.path("quest-after"))
	check(after != null and after.get_var(0, QUEST + ".3") == 2 and not after.zones.gz12k.vm.is_empty(), "saved host checkpoint is current")
	check(after != null and after.coop.host.joiners.values()[0].clean, "guest remains eligible for full progress checkpoints")
	check(await host.load_game_shown("quest-after"), "reload completed quest while guest stays connected")
	check(await until(func(): return ready(host) and ready(guest) and guest._pool_epoch == host._pool_epoch), "both clients receive restored world")
	if failures: await finish(); return
	var restored := hero(host).pos
	move(host, restored + Vector2(-3,-3))
	check(await until(func(): return hero(host).pos.distance_to(restored) > 2, 8), "movement works after co-op reload")
	await stop_host()
	check(not host.local_host._process_alive(), "menu teardown terminates server")
	check(await host.local_host.start(port, 2, false) == OK, "immediately host again on the same port")
	check(await host.load_game_shown("quest-after"), "recreated session loads saved quest progress")
	check(FileAccess.get_file_as_bytes(source) == source_bytes, "supplied source save remains unchanged")
	await finish()

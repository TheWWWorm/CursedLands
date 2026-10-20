extends "coop_story.gd"
## Actual desktop authority process, owner frontend and remote ENet guest.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,
		"show_tutorial":0,"auto_graphics":0,"coop_clock":1,"coop_guest_clock":3,"coop_guest_saves":3},true)
	var seed := CampaignState.new()
	seed.ensure_hero(0,"Human Hero"); seed.current_zone = "gz15h"
	seed.coop[CoopPermissions.KEY] = CoopPermissions.defaults()
	seed.play_clock = {"paused":true,"speed":0,"field_speed":0}
	check(seed.save(SaveInfo.path("permissions-seed")) == OK, "worker seed saved")
	GameData.player_name = "Worker Permission Host"
	host = Session.new(); get_parent().add_child(host)
	hg = Game.new(); hg.session = host; host.game = hg; get_parent().add_child(hg)
	var error := await host.local_host.start(29964,2)
	check(error == OK, "separate authority starts")
	if error != OK: get_tree().quit(1); return
	check(host.local_host.frontend and not host.is_host, "owner is a remote presentation peer")
	var child := host.local_host.process_id
	check(await host.load_game_shown("permissions-seed"), "authority loads fixture")
	GameData.player_name = "Worker Permission Guest"
	# Production worker RPCs are relative to /root, hence Main/Session.
	var guest_root := SubViewport.new(); guest_root.name = "GuestPeer"
	guest_root.size = Vector2i(1280,720); guest_root.own_world_3d = true; add_child(guest_root)
	branches.append(guest_root)
	var api := SceneMultiplayer.new(); api.root_path = guest_root.get_path()
	get_tree().set_multiplayer(api,guest_root.get_path())
	var main := Node.new(); main.name = "Main"; guest_root.add_child(main)
	client = Session.new(); main.add_child(client)
	cg = Game.new(); cg.session = client; client.game = cg; main.add_child(cg)
	require(client.join("127.0.0.1",29964) == OK)
	check(await until(func(): return client.world != null and not client.loading_game and client.clock_paused), "guest joins a paused authority")
	check(client.can_change_clock(2) and client.can_quick_save_load(false), "worker replicates saved default grants")
	cg.set_speed(2)
	check(await until(func(): return host.clock_speed == 1 and client.clock_speed == 1 and not host.clock_paused), "guest accelerates real authority")
	var pid := client.multiplayer.get_unique_id()
	host.set_player_permission(pid,CoopPermissions.SPEED,false)
	check(await until(func(): return not client.can_change_clock(2)), "owner frontend revokes guest permission")
	client.submit({"t":"clock","sector":1,"player":0}); await frames(24)
	check(host.clock_speed == 1, "worker rejects forged host identity")
	cg.set_speed(0)
	check(await until(func(): return host.clock_paused), "guest pauses real authority")
	var time := host.world.time
	await get_tree().create_timer(.5,true,false,true).timeout
	check(is_equal_approx(time,host.world.time), "authority simulation remains stopped")
	cg._key_action("quicksave")
	check(await until(func(): return FileAccess.file_exists(SaveInfo.path("quick"))), "F5 triggers authority quicksave")
	var saved := CampaignState.load_from(SaveInfo.path("quick"))
	check(saved != null and bool(saved.play_clock.paused) and int(saved.coop[CoopPermissions.KEY].players["worker permission guest"]) == 13, "worker checkpoint includes pause and individual permissions")
	host.set_player_permission(pid,CoopPermissions.SPEED,true)
	check(await until(func(): return client.can_change_clock(2)), "permission can be re-enabled through owner")
	cg.set_speed(1)
	check(await until(func(): return not host.clock_paused and host.clock_speed == 0), "guest resumes before reload")
	var epoch := host._pool_epoch
	cg._key_action("quickload")
	check(await until(func(): return host._pool_epoch > epoch and not host.loading_game and not client.loading_game and host.clock_paused), "F8 reloads host quicksave for both peers")
	check(not client.can_change_clock(2) and client.can_change_clock(0), "quickload restores saved individual grants")
	GameData.set_option("show_fps",1); await frames(12)
	check(not client.can_change_clock(2), "frontend settings synchronization retains loaded grants")
	client.multiplayer.multiplayer_peer.close()
	await host.local_host.stop()
	check(not OS.is_process_running(child), "authority shuts down cleanly")
	for root in branches: root.queue_free()
	hg.queue_free(); host.queue_free()
	get_tree().paused=false; Engine.time_scale=1; await frames()
	print("LOCAL_HOST_PERMISSIONS ",checks," checks ",failures," failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)

extends "arena_expansion_ui.gd"
var lobby: ArenaOnlineLobby
var client: ArenaOnlineSession
func wait_for(predicate: Callable, seconds := 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return predicate.call()
func _ready() -> void:
	OS.add_logger(errors); await frames(12)
	hold_preparation=false
	GameData._window_gen+=1
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"net_upnp":0,"net_lan":0},true)
	GameData.arena_character="hero"
	var lang:="en"; var dimensions:=Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--online-ui="):
			var spec:=arg.get_slice("=",1).split(",");lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	RemakeText.lang=lang
	get_tree().root.mode=Window.MODE_WINDOWED; get_tree().root.size=dimensions;get_tree().root.position=Vector2i.ZERO
	await frames(8)
	lobby=ArenaOnlineLobby.new();add_child(lobby);await frames(16)
	check(lobby.panel is NetworkPanel,"online lobby reuses co-op window")
	check(not lobby.panel.pad_targets().any(func(target):return target.id=="setup"),"controller cannot focus hidden campaign setup")
	check(lobby.panel.target_point("mode:host_coop").x>0 and lobby.panel.target_point("mode:join_coop").x>0,"host and join are separate choices")
	await shot("online-"+lang+"-modes")
	await click(lobby.panel.target_point("mode:join_coop"));await frames(6)
	check(lobby.panel.page==NetworkPanel.JOIN_COOP,"join choice opens address and password")
	await shot("online-"+lang+"-join")
	var other_host:=ArenaOnlineSession.new();other_host.player_name="Friend";add_child(other_host)
	check(other_host.host(29918)==OK,"friend hosts for join screen")
	DisplayServer.clipboard_set("127.0.0.1:29918")
	await click(lobby.panel.target_point("paste"));await frames(4)
	check(lobby.panel.selected_address()=="127.0.0.1:29918","shared Paste control fills the host address")
	await click(lobby.panel.target_point("ok"))
	check(await wait_for(func():return lobby.connection!=null and lobby.connection.my_seat==1),"join window connects as guest")
	await frames(10)
	await click(lobby.panel.target_point("ok"))
	check(await wait_for(func():return other_host.members.values().all(func(member):return member.ready)),"guest Ready button reaches host")
	check(lobby.panel._ok_label()==RemakeText.t("Not ready"),"guest can cancel readiness")
	await shot("online-"+lang+"-joined")
	await click(lobby.panel.target_point("cancel"));await frames(8)
	check(not lobby.panel.joining and lobby.panel.addresses.has("127.0.0.1:29918"),"disconnect retains recent address")
	other_host.close();other_host.queue_free()
	lobby.panel.go_back();await frames(6)
	await click(lobby.panel.target_point("mode:host_coop"));await frames(6)
	check(lobby.panel.page==NetworkPanel.HOST_COOP,"host choice opens connection rows")
	check(lobby.panel._rows()[-1].value==RemakeText.t("Off"),"transport choice is translated")
	await click(lobby.panel.target_point("row:commander") + Vector2(lobby.panel.kv().x * 260, 0));await frames(4)
	check(GameData.arena_character=="merc1", "online character choice responds to pointer input")
	await shot("online-"+lang+"-host")
	if ArenaLocalHost.available():
		lobby.panel.port_text="29917";lobby.panel._primary()
		var cancelled_child := lobby.connection.local_host.process_id
		check(lobby.connection.local_host.starting and not lobby.panel._ok_enabled(), "startup locks Start until ownership is confirmed")
		lobby._stop(); lobby._stop()
		check(await wait_for(func(): return not lobby.panel.hosting and not lobby._stopping), "repeated Stop cancels startup once")
		check(cancelled_child > 0 and not _worker_running(cancelled_child), "cancelled startup has no orphan process")
	lobby.panel.player_name="Host";lobby.panel.port_text="29917";lobby.panel._primary()
	check(await wait_for(func(): return lobby.connection != null and lobby.connection.owns_game()), "host frontend owns the room before guests join")
	GameData.arena_character="merc6"
	client=ArenaOnlineSession.new();client.player_name="Guest";add_child(client)
	check(client.join("127.0.0.1:29917")==OK,"rendered guest joins")
	check(await wait_for(func():return client.my_seat==1),"guest reaches lobby")
	GameData.arena_character="merc1"
	await frames(12);await shot("online-"+lang+"-lobby")
	if not lobby.panel._share.is_empty():
		await click(lobby.panel.target_point("copy:0"))
		check(DisplayServer.clipboard_get()==lobby.panel._share[0][0],"host Copy control shares the autochess port")
	client.request("ready")
	await wait_for(func():return lobby.connection.members.values().all(func(member):return member.ready))
	check(lobby.connection.start_game(7319).is_empty(),"lobby starts match")
	check(await wait_for(func():return lobby.screen!=null),"online match screen opens")
	screen=lobby.screen
	await frames(16)
	if lobby.connection.game: lobby.connection.game.set_process(false)
	check(screen.run.commander=="merc1" and client.view.commander=="merc6", "worker transports each human character choice")
	check(screen._commander_portrait.commander=="merc1", "online owner portrait uses host character")
	screen._recruit_offer(0);await frames(20)
	screen._recruit_offer(1);await frames(20)
	client.request("buy",[0]);await frames(20)
	check(screen.run.army.size()==2,"host shop receives accepted purchases")
	check(screen.battle.world.unit_rows().size()==2,"own board renders authoritative army")
	check(not screen._speed.visible and not screen._pause.visible,"online clock controls are not local")
	await shot("online-"+lang+"-prepare")
	var card: ArenaCreatureCard = screen._shop.get_child(2).get_child(0)
	await move(card.get_global_rect().get_center())
	var wiki_key := InputEventKey.new(); wiki_key.pressed = true; wiki_key.keycode = KEY_F7; wiki_key.physical_keycode = KEY_F7
	get_viewport().push_input(wiki_key); await frames(8)
	check(screen._wiki != null and screen._wiki.visible and screen._wiki.current == "creature/" + card.prototype.to_lower().uri_encode(), "F7 opens the hovered online recruit")
	check(screen.battle.phase != ArenaMatch.Phase.PAUSED and not get_tree().paused, "online wiki does not pause the match")
	var time_before: float = lobby.connection.view.preparation_left
	if lobby.connection.game: lobby.connection.game.set_process(true)
	await get_tree().create_timer(0.7).timeout
	if lobby.connection.game: lobby.connection.game.set_process(false)
	check(lobby.connection.view.preparation_left < time_before, "authoritative online countdown advances while wiki is open")
	bounded(screen._wiki, "online wiki")
	await shot("online-"+lang+"-wiki")
	var escape := InputEventKey.new(); escape.pressed = true; escape.keycode = KEY_ESCAPE
	get_viewport().push_input(escape); await frames(4)
	check(not screen._wiki.visible and not screen._modal_layer.visible, "Escape closes the online wiki and restores board controls")

	screen._show_menu();await frames(6)
	check(screen.battle.phase!=ArenaMatch.Phase.PAUSED,"menu does not pause online play")
	bounded(screen._modal_panel,"online menu")
	await shot("online-"+lang+"-menu")
	screen._close_modal()
	screen._guide();await frames(8)
	bounded(screen._modal_panel,"online guide")
	await shot("online-"+lang+"-guide")
	screen._close_modal()
	screen._fight();client.request("ready")
	check(await wait_for(func():return lobby.connection.view.global_stage=="fight"),"all humans ready starts battle")
	if lobby.connection.game: lobby.connection.game.set_process(true)
	await get_tree().create_timer(3).timeout
	check(screen.battle.phase in [ArenaMatch.Phase.FIGHT,ArenaMatch.Phase.FINISHED],"host combat reaches rendered replica")
	await shot("online-"+lang+"-combat")
	screen._show_player(1);await frames(30)
	check(screen.field.match_state.world!=null and not screen.field.match_state.world.authority,"scouting receives a presentation-only board")
	check(screen._commander_portrait.commander=="merc6", "scouting switches to the guest portrait")
	await shot("online-"+lang+"-scout")
	screen._show_boards();await frames(50)
	check(screen.field.showing_boards(),"overview opens")
	await shot("online-"+lang+"-overview")
	screen._show_player(0);await frames(12)
	client.close();await frames(20)
	check(lobby.connection.members.size()==1,"disconnect takeover during rendered match")
	var child := lobby.connection.local_host.process_id
	var worker_log := lobby.connection.local_host._config + ".log"
	lobby.queue_free();client.queue_free();screen=null;await frames(10)
	if child > 0:
		check(await wait_for(func(): return not _worker_running(child)), "closing the lobby releases its authority")
		check(not FileAccess.get_file_as_string(worker_log).contains("ERROR:"), "authority log has no runtime errors")
		check(not FileAccess.file_exists("user://crash/running_%d.cfg" % child), "authority exits cleanly")
	check(errors.messages.is_empty(),"no runtime or rendering errors: "+str(errors.messages))
	print("ARENA_ONLINE_UI ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _worker_running(pid: int) -> bool:
	# The host owns waitpid; do not reap its child a second time during teardown.
	return FileAccess.file_exists("/proc/%d/stat" % pid) if OS.get_name() == "Linux" else OS.is_process_running(pid)

extends "coop_story.gd"
## Real ENet peers and original camp briefing; controllable presentation
## completion models a fast host and a client still decoding/loading.

class HeldMovie extends MoviePlayer:
	var starts := 0
	func play(_movie: String) -> void:
		starts += 1
		_state = PLAYING
		visible = true
	func _process(_delta: float) -> void: pass

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1

func held_movie(g: Game) -> HeldMovie:
	g.hud._movie.queue_free()
	var m := HeldMovie.new()
	m.hud = g.hud
	g.hud._movie = m
	g.hud._add_ui(m)
	m.finished.connect(g.hud._movie_finished)
	return m

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_directory":0,"net_lan":0,"auto_graphics":0,"autosave":0,"scroll_border":0},true)
	await get_tree().process_frame
	var h := branch("Host",true); host=h.s; hg=h.g
	var c := branch("Client",false); client=c.s; cg=c.g
	require(host.host(29895,2)==OK)
	GameData.player_name="Coop Story Guest"
	require(client.join("127.0.0.1",29895)==OK)
	require(await until(func(): return host.players.size()==2))
	var hm := held_movie(hg)
	var cm := held_movie(cg)
	host.state=CampaignState.new()
	host.state.ensure_hero(0,"Human Hero")
	host.state.ensure_hero(1,"Human Hero","Coop Story Guest")
	host.state.set_var(0,"b.bz1h.brief_2",1)
	host.broadcast({"t":"movie","name":"teleprt1.bik"})
	await host.enter_zone("bz1h",1,false)
	require(await until(func(): return client.world != null and client.zone_id=="bz1h" and not client._remote_loading))
	check(hm.starts==1 and cm.starts==1,"zone replay does not restart the movie")
	var t := host.world.time
	for i in 25: await get_tree().process_frame
	check(host.world.time==t,"host simulation remains still while peers present the movie")
	check(not hg.hud._dialog.visible and not cg.hud._dialog.visible,"original Kel dialogue waits behind movie")
	var serial := int(host._movie_ev.serial)
	hm.stop()
	for i in 10: await get_tree().process_frame
	check(host.movie_active() and hm.visible and not hm._skip.visible,"finished host waits visibly for client")
	check(host.world.time==t and not hg.hud._dialog.visible,"host completion alone cannot start dialogue")
	var esc:=InputEventKey.new();esc.pressed=true;esc.keycode=KEY_ESCAPE
	hm._unhandled_input(esc)
	check(hm.visible and host.movie_active(),"Escape cannot hide peer waiting screen")
	host.save_game("deferred_movie")
	check(not FileAccess.file_exists(SaveInfo.path("deferred_movie")),"save waits for movie handoff")
	host._movie_ack(client.multiplayer.get_unique_id(),serial-1)
	check(host.movie_active(),"stale acknowledgement cannot release a later movie")
	get_tree().paused=true
	cm.stop()
	require(await until(func(): return not host.movie_active() and not client.movie_active()))
	check(get_tree().paused,"movie completion preserves existing player pause")
	check(not hm.visible and not cm.visible,"release dismisses both modal screens")
	require(await until(func():return FileAccess.file_exists(SaveInfo.path("deferred_movie"))))
	check(CampaignState.load_from(SaveInfo.path("deferred_movie")).current_zone=="bz1h","deferred save persists completed movie handoff")
	get_tree().paused=false
	require(await until(func(): return hg.hud._dialog.visible and cg.hud._dialog.visible))
	check(host.world.vm.briefings.active=="b.bz1h.brief_2","authored camp briefing starts after both completions")
	print("MOVIE_CAST ",host._dialog_ev)
	for u: GameUnit in host.world.units.values():
		if u.has_meta("hero") or u.uid == ScriptVM.name_id("merc2"):
			print("MOVIE_ACTOR ",u.uid," ",u.info.get("name")," pos=",u.pos," facing=",u.facing," height=",u.position.y," radius=",u.body_radius())
	print("MOVIE_SHOT ",DialogCamera.shot(host.world,host._dialog_ev.cast,host._dialog_ev.phrases[0],true))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--shot="))
			hg.hud._dialog._next()
			for i in 3: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--shot=").get_basename()+"-kir.png")
	host.broadcast({"t":"movie","name":"queued-a"})
	host.broadcast({"t":"movie","name":"queued-b"})
	require(await until(func(): return cm.starts==2))
	var first := int(host._movie_ev.serial)
	hm.stop(); cm.stop()
	require(await until(func(): return hm.starts==3 and cm.starts==3))
	host._movie_ack(1,first)
	check(host._movie_wait.has(1),"old completion cannot acknowledge queued movie")
	hm.stop()
	client.multiplayer.multiplayer_peer.close()
	require(await until(func(): return not host.movie_active()))
	check(not hm.visible,"disconnect releases remaining host without input lock")
	host.broadcast({"t":"movie","name":"cancel-on-load"})
	host._cancel_movie()
	check(not host.movie_active() and not hm.visible,"load cancellation clears presentation")
	host.multiplayer.multiplayer_peer.close()
	for root in branches: root.queue_free()
	for i in 10: await get_tree().process_frame
	print("MOVIE_GATE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

func _process(_dt: float) -> void: pass

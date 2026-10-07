extends Node

var host: Session
var client: Session
var hg: Game
var cg: Game
var branches: Array[Node] = []
var scene := "bz1r"
var single := false
var save_path := ""
var guest_at := Vector2.INF
var elapsed := 0.0
var next_log := 0.0
var started := false
var done := false
var events: Array = []
var reload_around := false
var legacy_save := false
var reload_done := false

func branch(label: String, main: bool) -> Dictionary:
	var root: Node = Node.new() if main else SubViewport.new()
	if root is SubViewport:
		root.size = Vector2i(1280, 720)
		root.own_world_3d = true
	root.name = label
	add_child(root)
	branches.append(root)
	var api := SceneMultiplayer.new()
	api.root_path = root.get_path()
	get_tree().set_multiplayer(api, root.get_path())
	var s := Session.new()
	root.add_child(s)
	var g := Game.new()
	g.session = s
	s.game = g
	root.add_child(g)
	return {"s": s, "g": g}

func require(ok: bool) -> void:
	if not ok:
		push_error("Scene fixture setup or wait failed")
		get_tree().quit(2)

func until(predicate: Callable, seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="): scene = arg.trim_prefix("--scene=")
		if arg == "--single": single = true
		if arg.begins_with("--save="): save_path = arg.trim_prefix("--save=")
		if arg == "--reload-around": reload_around = true
		if arg == "--legacy-save": legacy_save = true
		if arg.begins_with("--guest-at="):
			var xy := arg.trim_prefix("--guest-at=").split(",")
			guest_at = Vector2(float(xy[0]),float(xy[1]))
	GameData.options.merge({"net_upnp":0,"net_directory":0,"net_lan":0,"auto_graphics":0,"autosave":0,"scroll_border":0},true)
	await get_tree().process_frame
	var h := branch("Host",true)
	host = h.s
	hg = h.g
	if not single:
		var c := branch("Client",false)
		client = c.s
		cg = c.g
		require(host.host(29894,2) == OK)
		GameData.player_name = "Coop Story Guest"
		require(client.join("127.0.0.1",29894) == OK)
		require(await until(func(): return host.players.size() == 2))
	if not save_path.is_empty():
		host.state = CampaignState.load_from(save_path)
	else:
		host.state = CampaignState.new()
		host.state.ensure_hero(0, "Human Hero")
		if not single: host.state.ensure_hero(1, "Human Hero", "Coop Story Guest")
	await host.enter_zone(scene,1,false)
	if client:
		require(await until(func(): return client.world != null and client.zone_id == scene and not client._remote_loading))
	if client and guest_at != Vector2.INF:
		var hero := client.party_units(1)[0] as GameUnit
		cg.issue({"t":"move","units":[hero.uid],"x":guest_at.x,"y":guest_at.y})
	started = true
	require(await until(func(): return done, 100.0))
	await finish()

func _process(dt: float) -> void:
	if not started or done: return
	if reload_around and not reload_done:
		for u: GameUnit in host.world.units.values():
			if u.order.get("story_move",false) and ((scene=="bz1r" and u.order.to.distance_to(Vector2(50,150))<.01) or (scene=="cz1h" and u.uid==ScriptVM.name_id("merc2") and u.order.to.distance_to(Vector2(300.5,61))<.01)):
				reload_done=true
				started=false
				reload_scene.call_deferred()
				return
	elapsed += dt
	for g: Game in [hg, cg]:
		if g == null or g.hud == null: continue
		var hud := g.hud
		if hud._tutorial.visible: hud._tutorial.close()
		if hud._movie.visible: hud._movie.stop()
		if hud._dialog.visible and hud._dialog._mode == DialogPanel.PLAYING:
			hud._dialog._skip()
		elif hud._dialog.visible and hud._dialog._mode == DialogPanel.LAST:
			hud._dialog._finish()
	if elapsed >= next_log:
		next_log += 5.0
		var units := []
		for u: GameUnit in host.world.units.values():
			if u.has_meta("hero") or String(u.info.get("name","")).to_lower() in ["first","merc2"]:
				units.append({"id":u.uid,"name":u.display_name,"owner":u.controller,"pos":str(u.pos),"order":str(u.order),"failed":u.order_failed,"path":str(u.path),"blocked":u.blocked})
		var vm := host.world.vm
		var scripts := []
		for inst: ScriptVM.Instance in vm.instances:
			if inst.sname in ["VTriger#0#1","VCheck#0#1","VCheck#0#2"]:
				scripts.append({"name":inst.sname,"frames":inst.frames.size(),"wait_unit":str(inst.wait_unit),"wait":inst.wait_until})
		print("SCENE_STATE ",JSON.stringify({"time":elapsed,"zone":host.zone_id,"units":units,"scripts":scripts,"active":vm.briefings.active,"vars":host.state.vars}))
	if host.zone_id != scene and not host.loading_game:
		done = true
	if elapsed > 45.0: done = true

func reload_scene() -> void:
	host.save_game("scene_reload")
	if legacy_save:
		var saved:=CampaignState.load_from(SaveInfo.path("scene_reload"))
		saved.zones[scene].vm.erase("story_orders")
		saved.save(SaveInfo.path("scene_reload"))
	require(await host.load_game_shown("scene_reload"))
	if client: require(await until(func():return not client.loading_game and not client._remote_loading))
	print("SCENE_RELOAD ",scene," legacy=",legacy_save)
	started=true

func finish() -> void:
	var success := host.zone_id != scene and (single or client.zone_id == host.zone_id)
	print("SCENE_RESULT ",JSON.stringify({"scene":scene,"single":single,"passed":success,"host":host.zone_id,"client":client.zone_id if client else "","elapsed":elapsed,"reloaded":reload_done,"legacy_save":legacy_save}))
	if client: client.multiplayer.multiplayer_peer.close()
	if not single: host.multiplayer.multiplayer_peer.close()
	for root in branches: root.queue_free()
	for i in 10: await get_tree().process_frame
	get_tree().quit(0 if success else 1)

extends "coop_trade.gd"
## Actual gz11g OgreChest1: original OChest#1 reward, wait and pose reset.
## Normal click/use on each ENet peer, real routing/animation, full save/load.
## Hero skill/start are prepared; unrelated NPCs and scripts are held still.
## Permission oracle: original_lever_use.json, not the chest's visual pose.
const CHEST := 3435027
const P := preload("res://src/game/script/script_parser.gd")
var trace: Array = []

func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame

func peer(label: String, main: bool) -> Session:
	var view := SubViewport.new(); view.name=label; view.size=Vector2i(1280,720)
	view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(view); roots.append(view)
	var api := SceneMultiplayer.new(); api.root_path=view.get_path()
	get_tree().set_multiplayer(api,view.get_path())
	var s := Session.new(); view.add_child(s)
	var g := ObservedGame.new(); g.session=s; s.game=g; view.add_child(g)
	if main:
		var display := TextureRect.new(); display.texture=view.get_texture()
		display.mouse_filter=Control.MOUSE_FILTER_IGNORE
		display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(display)
	return s

func freeze(s: Session) -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.game.rig.set_process(false); s.game.direct.set_process(false)
	s.game.get_node("UnitFog").set_process(false)
	s.game.hud._tutorial.close(); s.game.hud._dialog.visible=false

func loaded() -> bool:
	return client.world!=null and client.zone_id==host.zone_id and client.my_index==1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch==host._load_serial

func enable(yes: bool) -> void:
	host.world.vm._call("EnableLever",[[P.N_CALL,"GetObject",[[P.N_NUM,CHEST]]],[P.N_NUM,int(yes)]],ScriptVM.Instance.new())

func point_for(s: Session) -> Vector2:
	var obj: Node3D = s.world.objects[CHEST]
	var cam := s.game.rig.camera
	cam.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.global_position=obj.global_position+Vector3(0,8,6)
	cam.look_at(obj.global_position+Vector3.UP*.5)
	var context := GameUnit.MeshScreenRect.camera_context(cam)
	for mi: MeshInstance3D in s.world.lever_sys._morph[CHEST].meshes:
		var rect := GameUnit.MeshScreenRect.of_context(mi,cam,context)
		if rect.has_area(): return rect.get_center()
	return cam.unproject_position(obj.global_position+Vector3.UP*.5)

func hand(s: Session) -> bool:
	var p := point_for(s)
	s.game._lever_pick_key=[]
	s.game.selected.assign([s.party_units(s.my_index)[0]])
	var motion := InputEventMouseMotion.new(); motion.position=p; motion.global_position=p
	s.game.get_viewport().push_input(motion,true); s.game._update_cursor()
	return s.game.pick_lever(p)==CHEST and s.game.cursor.kind=="cursor_use"

func record(label: String) -> void:
	var states := []
	for s: Session in [host,client]:
		states.append({"player":s.my_index,"state":int(s.world.levers[CHEST].state),
			"enabled":bool(s.world.levers[CHEST].get("enabled",true)),"usable":s.world.lever_sys.usable(CHEST),"hand":hand(s)})
	trace.append({"label":label,"time":host.world.time,"peers":states,"money":host.state.money})

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await frames(); await RenderingServer.frame_post_draw
	for s: Session in [host,client]:
		s.game.get_viewport().get_texture().get_image().save_png("user://chest-%s-%s.png"%[label,"host" if s==host else "guest"])

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"unit_fog":0,"control_mode":1,"scroll_border":0,"smile_faces":0},true)
	host=peer("ChestHost",true); client=peer("ChestGuest",false)
	check(host.host(29985,2)==OK and client.join("127.0.0.1",29985)==OK,"chest peers connect")
	check(await until(func():return host.players.size()==2),"two chest players")
	host.state=CampaignState.new(); host.state.ensure_hero(0,"Human Hero"); host.state.ensure_hero(1,"Human Hero","Guest")
	host.set_physics_process(false)
	await host.enter_zone("gz11g",1,false); freeze(host)
	check(await until(loaded),"both peers load original gz11g")
	if not loaded(): await finish(); return
	freeze(client)
	check(host.world.objects[CHEST].get_meta("ei").name=="OgreChest1","fixture uses authored OgreChest1")
	check(host.world.vm.ast.scripts.has("OChest#1"),"authored chest reward/reset script is loaded")
	for owner in [0,1]:
		var w := host.world
		w.vm.instances.clear()
		# Fresh controlled permission and pose for each independent operator.
		w.lever_sys.restore_row(CHEST,[0,0.0,true,{"use_v":1}])
		client.world.lever_sys.restore_row(CHEST,[0,0.0,true,{"use_v":1}])
		host.state.set_var(0,"q.gz11g.ochest",1)
		var position: Vector3 = w.objects[CHEST].get_meta("ei").position
		for who in [0,1]:
			var actor: GameUnit=host.party_units(who)[0]
			actor.command({"type":"wait","t":0.0}); actor.blocked=false; actor.stats.dex=100.0
			actor.pos=w.nav.nearest_walkable_for(actor,Vector2(position.x,position.y)+Vector2(-4 if who==owner else -9,2))
			actor._sync_transform(); w.nav.track_unit(actor)
		var operator: GameUnit=host.party_units(owner)[0]
		host._send_snapshot_records(host.party_units(0).map(func(u):return u.snapshot())+host.party_units(1).map(func(u):return u.snapshot()),w.time)
		await frames(10)
		check(host.lever_science_ok(operator,CHEST),"prepared operator meets authored lock skill %d"%owner)
		check(hand(host) and hand(client),"both peers show the unused chest hand %d"%owner)
		record("available-%d"%owner)
		if owner==1: await capture("available")
		w.vm.spawn("OChest#1",[w.objects[CHEST]])
		var before := host.state.money
		var input := host if owner==0 else client
		input.game.order_on(null,false,point_for(input))
		check(await until(func():return operator.has_meta("interact")),"player %d click reaches authority"%owner)
		var saw_open := false
		for tick in 500:
			w.time+=GameUnit.TICK; w._logic_step+=1
			w.vm.tick(GameUnit.TICK); operator.tick(GameUnit.TICK); w.lever_sys.tick()
			if int(w.levers[CHEST].state)==1: saw_open=true
			if saw_open and int(w.levers[CHEST].state)==0: break
			if tick%10==0: await frames(1)
		print("CHEST_OPERATOR ",owner," ",operator.pos," ",operator.order," failed=",operator.order_failed," open=",saw_open)
		check(saw_open,"player %d walks and uses the original chest"%owner)
		check(host.state.money==before+100,"original chest script awards exactly 100 gold %d"%owner)
		check(int(w.levers[CHEST].state)==0,"original Sleep(40) branch closes the chest %d"%owner)
		await frames(12)
		check(int(client.world.levers[CHEST].state)==0,"closed pose replicates to guest %d"%owner)
		check(not w.lever_sys.usable(CHEST) and not client.world.lever_sys.usable(CHEST),"script closure preserves consumed permission on both peers %d"%owner)
		check(not hand(host) and not hand(client),"closed spent chest offers no hand on either peer %d"%owner)
		record("spent-%d"%owner)
		if owner==1: await capture("spent")
		operator.command({"type":"wait","t":0.0})
		host.apply_command({"t":"use_lever","target":CHEST,"units":[operator.uid]},owner)
		check(not operator.has_meta("interact"),"authority rejects a stale second use %d"%owner)
		operator.command({"type":"wait","t":0.0}); operator.remove_meta("interact")
	check(host.save_game("spent-astral-chest")==OK,"save spent closed chest")
	check(await host.load_game_shown("spent-astral-chest"),"full co-op save reload succeeds"); freeze(host)
	check(await until(loaded),"guest receives restored map")
	if loaded():
		freeze(client)
		check(not host.world.lever_sys.usable(CHEST) and not client.world.lever_sys.usable(CHEST),"save reload preserves consumed permission on both peers")
		check(not hand(host) and not hand(client),"save reload preserves absent hand on both peers")
		record("reloaded-spent")
		# Separate controlled native contract: explicit EnableLever works even
		# at a terminal pose; no chest reward script is restarted here.
		host.world.vm.instances.clear()
		var duration := host.world.lever_sys.set_state(CHEST,1,0)
		host.broadcast({"t":"lever","nid":CHEST,"state":1,"time":duration})
		enable(true); await frames(12)
		check(host.world.lever_sys.usable(CHEST) and client.world.lever_sys.usable(CHEST),"explicit enable at terminal pose reaches both peers")
		check(hand(host) and hand(client),"explicit enable restores hand at terminal pose")
		record("explicit-enable")
	await finish()

func finish() -> void:
	FileAccess.open("user://astral-chest-permission.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"trace":trace,
		"scope":"Real LiA map, original chest script, prepared skill/start, live operator route/animation, ENet and full save/load; unrelated simulation held still. Native permission captured separately."},"\t"))
	for s: Session in [host,client]:
		s.online=false
		if s.multiplayer.multiplayer_peer: s.multiplayer.multiplayer_peer.close()
	for root in roots: root.queue_free()
	await frames(8)
	print("ASTRAL_CHEST_PERMISSION ",checks," checks ",failures," failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)

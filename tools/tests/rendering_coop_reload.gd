extends "coop_story.gd"
## Real ENet host and guest, each with a rendered world. They deliberately
## share one RenderingDevice, so this is a stricter allocation stress case
## than two PCs, not a claim to reproduce two independent Windows drivers.
var failures:Array[String]=[]
var rows:Array=[]
var deadline:=0
func _process(_dt):
	if Time.get_ticks_msec()>deadline:
		printerr("FAIL co-op rendering timeout");get_tree().quit(1)
func _ready():
	process_mode=Node.PROCESS_MODE_ALWAYS;deadline=Time.get_ticks_msec()+600000
	if DisplayServer.get_name()=="headless":
		printerr("FAIL requires two rendered worlds");get_tree().quit(2);return
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"net_websocket":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_voice":0,"volume_stream":0,"display_mode":0,"resolution":1,"fps_limit":1,"pt_mode":0,"rtx_upscaling":0,"rtx_frame_generation":0,"fsr_upscaling":0,"fsr_frame_generation":0,"q_aa":0},true)
	Gfx.apply_quality(get_viewport());Engine.max_fps=30
	for i in 6:await get_tree().process_frame
	get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1600,900)
	var h:=branch("Host",true);host=h.s;hg=h.g
	var c:=branch("Guest",false);client=c.s;cg=c.g
	host.message.connect(func(t):print("HOST_MESSAGE ",t))
	client.message.connect(func(t):print("GUEST_MESSAGE ",t))
	client.net.refused.connect(func(a,b):print("GUEST_REFUSED ",a," ",b))
	var guest_view:=branches[1] as SubViewport
	guest_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	if host.host(0,2)!=OK:
		printerr("FAIL start co-op rendering host");get_tree().quit(1);return
	GameData.player_name="Rendering Guest"
	if client.join("127.0.0.1",host.host_port)!=OK:
		printerr("FAIL start co-op rendering peers");get_tree().quit(1);return
	if not await until(func():return host.players.size()==2 and client.players.size()==2):
		printerr("FAIL co-op rendering handshake");get_tree().quit(1);return
	# Both ENet peers share this main thread. Cold D3D12 pipeline compilation
	# can stall it for over a minute under Wine, unlike two independent PCs.
	# Extend only this fixture's transport deadline; retain normal game code.
	for s:Session in [host,client]:
		var peer:=s.multiplayer.multiplayer_peer as ENetMultiplayerPeer
		for id in s.multiplayer.get_peers():
			peer.get_peer(id).set_timeout(0,300000,300000)
	for cycle in 4:
		var previous:Array=[]
		for s:Session in [host,client]:
			if s.world:previous.append(weakref(s.world))
		if not await host.load_game_shown("descriptor-gz1h"):
			failures.append("load "+str(cycle));break
		if not await until(func():return client.world!=null and client.zone_id==host.zone_id and not client.loading_game and not client._remote_loading and client._pool_epoch==host._load_serial,120):
			print("COOP_DIAGNOSTIC ",JSON.stringify({"host_players":host.players,"guest_players":client.players,"guest_zone":client.zone_id,"guest_loading":client.loading_game,"remote_loading":client._remote_loading,"epoch":client._pool_epoch,"serial":host._load_serial,"host_online":host.online,"guest_online":client.online}))
			failures.append("guest arrival "+str(cycle));break
		while ShaderCompilationScreen.active():await get_tree().process_frame
		# Each isolated viewport needs its own explicit camera. The ordinary
		# campaign camera's global focus selection belongs to the main window.
		for game:Game in [hg,cg]:
			game.rig.set_process(false);game.direct.set_process(false)
			var party:=game.world.party_units()
			if party.is_empty():failures.append("empty rendered party "+str(cycle));continue
			var hero:GameUnit=party[0]
			var focus:=EISpace.pos(hero.pos.x,hero.pos.y,game.world.ground_at(hero.pos.x,hero.pos.y)+1)
			var camera:=game.rig.camera
			camera.current=true;camera.global_position=focus+Vector3(12,18,15);camera.look_at(focus);camera.reset_physics_interpolation()
		for i in 30:await RenderingServer.frame_post_draw
		for reference:WeakRef in previous:
			if reference.get_ref()!=null:failures.append("retained world "+str(cycle))
		var row:={"cycle":cycle,"host_zone":host.zone_id,"guest_zone":client.zone_id,"same_generation":client._pool_epoch==host._load_serial,"old_worlds_freed":previous.all(func(r):return r.get_ref()==null),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"vram":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}
		rows.append(row);print("COOP_RENDER_SAMPLE ",JSON.stringify(row))
		if cycle==3:
			get_viewport().get_texture().get_image().save_png("user://descriptor-coop-host.png")
			guest_view.get_texture().get_image().save_png("user://descriptor-coop-guest.png")
	client.online=false;host.online=false
	client.set_physics_process(false);host.set_physics_process(false)
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root:Node in branches:root.queue_free()
	for i in 8:await get_tree().process_frame
	TexUpscale.shutdown()
	var result:={"rows":rows,"failures":failures}
	FileAccess.open("user://descriptor-coop.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("COOP_RENDER_RELOAD ",JSON.stringify(result));get_tree().quit(0 if failures.is_empty() else 1)

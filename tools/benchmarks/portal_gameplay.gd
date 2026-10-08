extends Node
## Bounded Portal gameplay benchmark: normal commands/combat, measured frame
## intervals and actual simulation progress. See README for fixture/settings.

var session:Session
var game:Game
var cfg:Dictionary
var sweep:Camera3D
var controlled:Array=[]
var recording:=false
var started:=0
var next_move:=2000
var next_census:=0
var timeline:Array=[]
var census:Array=[]
var commands:Array=[]
var wings:Dictionary={}

func _ready()->void:
	var config_path := "user://bench.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gameplay-config="): config_path=arg.trim_prefix("--gameplay-config=")
	cfg=JSON.parse_string(FileAccess.get_file_as_string(config_path))
	GameData.options.merge({"autosave":0,"net_lan":0,"net_upnp":0,"net_directory":0,"scroll_border":0,"coop_clock":1,"vsync":0,"fps_limit":0},true)
	GameData.options.merge(cfg.get("options",{}),true)
	if cfg.get("graphics","configured") == "original":
		GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
		if not GfxDetect.original_look_on(GameData.options):
			push_error("Original look preset did not apply");get_tree().quit(1);return
	GameData.difficulty=GameData.option("difficulty")
	GameData._apply_display()
	Engine.max_fps=0
	seed(519826)
	await get_tree().process_frame
	session=Session.new();get_parent().add_child(session);get_parent().session=session
	game=Game.new();game.session=session;session.game=game
	get_parent().add_child(game);get_parent().game=game
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var f:=FileAccess.open(SaveInfo.path("device_fixture"),FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(String(cfg.save)));f.close()
	GameData.player_name="RetroidBench"
	if cfg.get("host",false):
		var e:Error = await session.start_host(29901,6) if cfg.get("isolated",false) else session.host(29901,6)
		if e!=OK:push_error("Device host failed "+str(e));get_tree().quit(1);return
	# Same-build inline control bypasses only automatic worker startup.
	var loaded := session.load_game("device_fixture") if cfg.get("inline_single",false) and not cfg.get("host",false) \
		else await session.load_game_shown("device_fixture")
	if not loaded:
		push_error("Device save load failed");get_tree().quit(1);return
	var w:=session.world
	if session.zone_id!="gz1h" or w.units.size()!=415:
		push_error("Unexpected Portal fixture: %s / %s" % [session.zone_id,w.units.size()]);get_tree().quit(1);return
	if session.local_host.frontend:
		if session.local_host.single_player:
			get_tree().paused=true
			session.local_host._sync_single_clock()
			await session.local_host.request("measure_save")
		else:
			await session.local_host.request("clock", {"sector":0})
	else:
		w.process_mode=Node.PROCESS_MODE_DISABLED
	session.set_physics_process(false)
	print("DEVICE_READY ",session.zone_id," units=",w.units.size())
	for i in 30:await get_tree().process_frame
	if int(cfg.get("players",1))>1:
		var deadline:=Time.get_ticks_msec()+180000
		while (session.players.size()<int(cfg.players) or session._zone_holding) and Time.get_ticks_msec()<deadline:await get_tree().process_frame
		if session.players.size()<int(cfg.players):push_error("Device peer timeout");get_tree().quit(1);return
	controlled=game.my_units().map(func(u):return u.uid)
	if cfg.get("terror",false):
		sweep=Camera3D.new();add_child(sweep)
		sweep.far=game.rig.camera.far; sweep.near=game.rig.camera.near; sweep.fov=game.rig.camera.fov
	else:
		sweep=game.rig.camera
		game.rig.distance=CameraRig.M_DEFAULT_DISTANCE
	sweep.make_current()
	_follow(0.0)
	for i in 5:await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var sim:=w.time
	var before:=Time.get_ticks_usec()
	var previous:=before
	started=Time.get_ticks_msec()
	recording=true
	if session.multiplayer_game:
		session.set_coop_clock(int(cfg.get("speed",2)))
	else:
		Engine.time_scale=float(cfg.get("speed",2))
		get_tree().paused=false
		session.local_host._sync_single_clock()
	w._frame_ms=-1
	w.process_mode=Node.PROCESS_MODE_PAUSABLE
	session.set_physics_process(true)
	if cfg.get("profile",false):ei_profile_begin()
	print("DEVICE_MEASURE_BEGIN ",cfg.name)
	while Time.get_ticks_usec()-before<float(cfg.get("seconds",30))*1e6:
		await get_tree().process_frame
		var now:=Time.get_ticks_usec()
		timeline.append([now-before,now-previous,w.time])
		previous=now
	recording=false
	if cfg.get("profile",false):ei_profile_end()
	var after:=Time.get_ticks_usec()
	var frames:Array=timeline.map(func(r):return float(r[1])/1000.0)
	frames.sort()
	var result:={"name":cfg.name,"original_look":GfxDetect.original_look_on(GameData.options),"isolated":session.local_host.frontend,"worker_handle":session.local_host.process_id,"zone":session.zone_id,"camera_far":sweep.far,"camera_near":sweep.near,"camera_fov":sweep.fov,"camera_mode":"terror close view" if cfg.get("terror",false) else "gameplay terrain-aware camera","controlled":controlled.map(func(uid):
		var u:GameUnit=session.world.units.get(uid)
		return {"uid":uid,"dead":u.dead,"hp":u.hp,"pos":u.pos} if u else {"uid":uid}
	),"wall_seconds":(after-before)/1e6,"fps":timeline.size()*1e6/(after-before),"sim_seconds":w.time-sim,"timeline":timeline,"frame_ms":{"p50":frames[frames.size()/2],"p95":frames[int(frames.size()*.95)],"p99":frames[int(frames.size()*.99)],"max":frames[-1]},"units":w.units.size(),"census":census,"commands":commands,"wing_keys":wings.size(),"players":session.players.size(),"online":session.online,"options":GameData.options.duplicate(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"viewport_size":[get_viewport().size.x,get_viewport().size.y],"render_scale":get_viewport().scaling_3d_scale,"engine":Engine.get_version_info(),"native":ClassDB.class_exists("TerrainSearchKernel"),"config":cfg}
	result.single_player_worker=session.local_host.single_player
	result.multiplayer_game=session.multiplayer_game
	result.fixture_version=2
	result.difficulty_runtime=GameData.difficulty
	f=FileAccess.open("user://"+String(cfg.name)+".json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
	print("DEVICE_MEASURE_DONE ",JSON.stringify({"name":cfg.name,"fps":result.fps,"frame_ms":result.frame_ms,"sim_seconds":result.sim_seconds,"native":result.native,"renderer":result.renderer}))
	get_viewport().get_texture().get_image().save_png("user://"+String(cfg.name)+".png")
	Engine.time_scale=1.0
	if session.local_host.frontend:await session.local_host.stop()
	session.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
	get_tree().quit()

func _focus()->GameUnit:
	if cfg.get("terror",false):
		var terror:GameUnit=session.world.units.get(666666)
		if terror and not terror.dead:return terror
	var found:GameUnit
	for uid in controlled:
		var u:GameUnit=session.world.units.get(uid)
		if u:
			found=u
			if not u.dead:break
	return found

func _follow(t:float)->void:
	var focus:=_focus()
	if focus==null:return
	var at:=focus.global_position+Vector3(0,1.5,0)
	if cfg.get("terror",false):
		sweep.position=focus.global_position+Vector3(0,7,20)
		sweep.look_at(focus.global_position+Vector3(0,2,0))
		return
	game.rig.yaw=t*.06
	game.rig.focus(focus.global_position)

func _process(_dt:float)->void:
	if not recording:return
	var elapsed:=Time.get_ticks_msec()-started
	_follow(elapsed/1000.0)
	if elapsed>=next_move:
		next_move+=8000
		for uid in controlled:
			var u:GameUnit=session.world.units.get(uid)
			if u==null or u.dead:continue
			var direction:=(Vector2(session.world.nav.size)*.25-u.pos).normalized()
			var monster:GameUnit=session.world.units.get(666666)
			if cfg.get("terror",false) and monster:direction=(u.pos-monster.pos).normalized()
			var target:=u.pos+direction*8
			game.issue({"t":"move","units":[uid],"x":target.x,"y":target.y,"run":true})
			commands.append({"wall_ms":elapsed,"uid":uid,"from":u.pos,"to":target})
	if elapsed>=next_census:
		next_census+=500
		var moving:=0;var fighting:=0;var dead:=0;var visible_count:=0
		var monsters:=[]
		for u:GameUnit in session.world.unit_rows():
			if u.uid in [666666,980429,997048,997052,997054,997058]:
				var wing:EIAnimPart=u.model.find_child("r_wingbone1",true,false) if u.model else null
				if wing:wings[str(wing.animation_key)]=true
				monsters.append({"uid":u.uid,"dead":u.dead,"hp":u.hp,"pos":u.pos,"action":u.action,"wing":wing.animation_key if wing else null})
			if u.dead:dead+=1
			if u.visible:visible_count+=1
			if u.action in ["walk","run","crawl"]:moving+=1
			if u.action.begins_with("cast") or u.action.begins_with("attack"):fighting+=1
		census.append({"wall_ms":elapsed,"sim":session.world.time,"moving":moving,"fighting":fighting,"dead":dead,"visible":visible_count,"creatures":monsters})

# Named no-ops are intercepted only by the PRIVATE sampling engine.
func ei_profile_begin()->void:
	pass
func ei_profile_end()->void:
	pass

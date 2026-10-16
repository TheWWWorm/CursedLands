extends Node
## External --tool driver. No campaign saves, release files or gameplay code
## are modified. Each invocation uses an isolated user:// and one JSON shot.

var spec := {}
var out := ""
var game: Game
var session: Session
var hero: GameUnit
var enemies: Array[GameUnit] = []
var wiki: WikiPanel
var focus := Vector3.ZERO
var recording := false
var index := 0
var first_frame := 0
var total := 0
var report := {}
var probe := false
var language := "en"
var coordination := ""
var coop_start := {}
var encounter_start := []
var movement_samples := []
var touch_events := 0
var touch_point := Vector2.ZERO
var touch_cue: Node2D
var hit_samples := []
var last_health := {}
var camera_initialized := false
var smooth_heading := 0.0
var smooth_tilt := 0.0
var weather_proof := {}

class TouchCue extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO,30,Color(1,1,1,0.25))
		draw_circle(Vector2.ZERO,30,Color(1,1,1,0.9),false,3,true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	process_physics_priority = -100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-spec="): spec = JSON.parse_string(FileAccess.get_file_as_string(a.trim_prefix("--shot-spec=")))
		elif a.begins_with("--shot-output="): out = a.trim_prefix("--shot-output=")
		elif a.begins_with("--trailer-language="): language = a.trim_prefix("--trailer-language=")
		elif a.begins_with("--coordination="): coordination = a.trim_prefix("--coordination=")
		elif a == "--trailer-probe": probe = true
	if spec.is_empty() or out.is_empty():
		printerr("TRAILER_ERROR missing shot spec or output"); get_tree().quit(2); return
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _run() -> void:
	seed(int(spec.get("seed", 6519)))
	_apply_ultra()
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"render_scale":4,"q_aa":3,
		"q_shadows":3,"cam_see_through":0,"unit_fog":0,"cam_follow":0,"control_mode":0,
		"volume_stream":0,"volume_voice":0,"volume_sfx":85,"direct_hints":0},true)
	for key: String in ["gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_water_current","gfx_water_waves",
		"gfx_waterfalls","gfx_cloud_shadows","gfx_cloud_reflections","gfx_biome_cover","gfx_vegetation_interaction",
		"gfx_ambient_wildlife","gfx_ambient_particles","gfx_weather_mist","gfx_ground_contact"]:
		GameData.options[key]=1
	GameData.options.gfx_clouds=3
	GameData.options.gfx_terrain=2
	GameData.options.merge(spec.get("options",{}),true)
	if not spec.get("hud",false):
		GameData.options.show_path=0
		GameData.options.select_type=0
		GameData.options.show_flying_hp=0
	if spec.get("hd",false):
		var err := ModStore.create_profile("Trailer")
		if err.is_empty(): err=ModStore.set_packages(["community.hd-lands-textures@1.5.0"])
		if err.is_empty(): err=GameData.open(GameData.root)
		if not err.is_empty():
			printerr("TRAILER_ERROR HD Lands: ",err);get_tree().quit(2);return
	RemakeText.lang=language
	GameData.options_changed.emit()
	GameData._apply_audio()
	Engine.max_fps=0
	await frames(20)
	GameData._window_gen+=1
	var root:=get_tree().root
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(int(spec.get("width",3840)),int(spec.get("height",2160)))
	root.content_scale_size=Vector2i.ZERO
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
	if spec.get("kind","world")=="wiki":
		wiki=WikiPanel.new();add_child(wiki);wiki.open()
		await frames(30)
		var matches:=wiki.catalog.search(String(spec.get("search","")),String(spec.get("category","Creatures")))
		if not matches.is_empty(): wiki.navigate(matches[0])
		await frames(20)
		if wiki._preview:wiki._preview.zoom_by(0.55)
	else:
		session=Session.new();session.name="Session";get_tree().current_scene.add_child(session)
		game=Game.new();game.name="Game";game.session=session;session.game=game;get_tree().current_scene.add_child(game)
		# Autoload input routing resolves the normal current-scene owners.
		get_tree().current_scene.game=game;get_tree().current_scene.session=session
		session.multiplayer.peer_connected.connect(_offline_peer)
		if spec.get("kind","")=="coop":
			GameData.player_name="Ari"
			if session.host(0,Session.MAX_PLAYERS)!=OK:
				printerr("TRAILER_ERROR could not host co-op");get_tree().quit(2);return
			FileAccess.open(coordination+"/ready",FileAccess.WRITE).store_string(str(session.host_port))
			if not await _wait_for(func():return session.players.size()==2):return
		session.state=CampaignState.new()
		session.state.ensure_hero(0,session._hero_proto(0))
		if spec.get("kind","")=="coop": session.state.ensure_hero(1,"Human Mercenary Warrior","Mira")
		session.state.world_time=float(spec.get("hour",14))
		await session.enter_zone(String(spec.get("zone","gz1g")),int(spec.get("entrance",1)),false)
		get_tree().paused=false
		if session.world==null or session.party_units(0).is_empty():
			printerr("TRAILER_ERROR zone did not load");get_tree().quit(2);return
		# Authored camera shots must not trigger intro/tutorial dialogue.
		session.world.vm.instances.clear()
		# Action takes must keep the normal command queue running: direct
		# controls submit through Session, just like real keyboard/gamepad input.
		if spec.get("kind","") not in ["coop","combat"] and spec.get("camera","") not in ["first","third"]:session.set_physics_process(false)
		hero=session.party_units(0)[0]
		if not _dress(hero):return
		for u: GameUnit in session.world.unit_rows():
			u.orders.clear();u.order={};u.blocked=false;u._anim_lock=0
			u._perceive_next=INF;u.ai_next=INF;u.action="idle"
			if u.model: u.model.act("idle",1,0)
		if spec.has("hero"):
			var requested:=Vector2(float(spec.hero[0]),float(spec.hero[1]))
			hero.pos=session.world.nav.nearest_walkable(requested)
			if hero.pos.distance_to(requested)>2.0:
				printerr("TRAILER_ERROR player approach is not walkable: ",requested);get_tree().quit(2);return
			hero._sync_transform(0)
			session.world.nav.track_unit(hero)
		game.selected.assign([hero])
		game.hud._close_menu()
		game.hud._menu.hide()
		game.hud._wiki_button.hide()
		get_tree().paused=false
		focus=hero.global_position
		if spec.has("focus"):
			focus=Vector3(float(spec.focus[0]),session.world.ground_at(float(spec.focus[0]),float(spec.focus[1]))+float(spec.get("focus_height",0)),-float(spec.focus[1]))
		if spec.has("focus_world"):focus=_vector(spec.focus_world)
		if spec.get("anchor","")=="lava": focus=_lava_anchor()
		if spec.has("enemies"): _prepare_combat()
		if spec.get("hide_party",false):
			for actor: GameUnit in session.party_units(0):actor.hide()
		game.hud.visible=bool(spec.get("hud",false))
		game.cursor.hide();game.cursor.set_process(false)
		if spec.get("camera","") in ["first","third"]:
			GameData.options.control_mode=3 if spec.camera=="first" else 2
			game.rig.release();game.rig._window_focused=true
			game.direct.heading=deg_to_rad(float(spec.get("heading",0)))
			game.direct.tilt=float(spec.get("tilt",-0.05))
			GameData.options_changed.emit()
			# The shot supplies ordinary control commands. Physical mouse
			# events from other capture windows must not move this camera.
			game.direct.set_process_input(false)
			PadInput.active="pad"
			PadInput.set_process_input(false)
			PadInput.field.set_process(false)
		else: _camera(0)
		if spec.get("weather","")=="rain":
			var weather:=game.sound.weather
			if weather.type!=1:
				printerr("TRAILER_ERROR rain is not native to this zone");get_tree().quit(2);return
			weather.state=1
			Weather._countdown=10000
			weather.on_event({"w":1,"fade":0.0},game.sound._ticks)
		if spec.get("input","")=="touch":
			TouchInput.pinned=true;TouchInput.enabled=true;TouchInput.mode_changed.emit()
			PadInput.set_process_input(false)
			if spec.has("touch_demo"):
				var layer:=CanvasLayer.new();layer.layer=127;add_child(layer)
				touch_cue=TouchCue.new();layer.add_child(touch_cue);touch_cue.hide()
		elif spec.get("input","")=="gamepad":
			PadInput._set_active("pad")
			GameData.options.pad_enabled=1
		await frames(int(spec.get("warmup_frames",120)))
		if spec.get("kind","")=="coop":
			if not await _wait_for(func():return FileAccess.file_exists(coordination+"/loaded")):return
			var other: GameUnit=session.party_units(1)[0]
			if not _dress(other):return
			if spec.has("hero"):
				other.pos=_point(spec.guest) if spec.has("guest") else hero.pos+Vector2(1.5,1.0);other._sync_transform(0)
				session.world.nav.track_unit(other)
				await frames(60)
			focus=(hero.global_position+other.global_position)*0.5
			coop_start={"players":session.players.duplicate(true),"guest_start":[other.pos.x,other.pos.y],"max_players":session.max_players}
			FileAccess.open(coordination+"/go",FileAccess.WRITE).store_string(JSON.stringify({"target":enemies[0].uid if not enemies.is_empty() else -1,"walk":spec.get("guest_walk",[])}))
			var to:=session.world.nav.nearest_walkable(hero.pos+Vector2(7,0))
			if not spec.has("enemies"):session.apply_command({"t":"move","units":[hero.uid],"x":to.x,"y":to.y,"run":false},0)
			if not await _wait_for(func():return FileAccess.file_exists(coordination+"/command")):return
		if spec.get("input","")=="touch" and game.hud.touch_actions and spec.get("touch_demo","")!="combat":
			if spec.get("touch_panel","menu")=="aim":game.hud.touch_actions._show_aim()
			else:game.hud.touch_actions._show_menu()
		if spec.get("input","")=="gamepad" and PadInput.field:
			PadInput.field.open_wheel("system","system")
		# Native game music is a separate replaceable edit track.
		if spec.get("export_music",false):
			var music:=EIAudio.music(String(spec.get("music_track","main")))
			if music: FileAccess.open(out+"-music.mp3",FileAccess.WRITE).store_buffer(music.data)
		if spec.get("camera","") in ["first","third"]:
			for f in 90:
				_camera(0);await frames(1)
		if spec.has("enemies"):
			_start_combat()
			for f in int(spec.get("pre_roll",0)):
				_camera(0);_action(f)
				await frames(1)
		if spec.has("walk"):
			var p:=Vector2(float(spec.walk[0]),float(spec.walk[1]))
			session.apply_command({"t":"move","units":[hero.uid],"x":p.x,"y":p.y,"run":false},0)
		print("TRAILER_SCENE ",JSON.stringify({"hero":[hero.pos.x,hero.pos.y],"focus":[focus.x,focus.y,focus.z],"map":session.world.zone.get("mpr"),"terrain_atlas":session.world.terrain._atlases.get_width(),"enemies":enemies.map(func(u):return u.proto.get("name",""))}))
	if spec.get("weather","")=="rain":
		var weather_state:={"shown":game.sound.weather._shown,"target":game.sound.weather._target,"options":_graphics_report()}
		for child in game.get_children():
			if child is SurfaceWeather:weather_state.merge({"surface_rain":child.rain,"wetness":child.wetness,"cover_ready":child._cover_ready,"cover_queue":child._cover_queue.size()})
		weather_proof=weather_state
		print("TRAILER_WEATHER ",JSON.stringify(weather_state))
	await frames(12)
	_camera(0)
	await RenderingServer.frame_post_draw
	var picture:=get_viewport().get_texture().get_image()
	picture.save_png(out+"-start.png")
	if probe:
		if spec.has("scout_locations"):
			for view: Dictionary in spec.scout_locations:
				var at:=Vector2(float(view.center[0]),float(view.center[1]))
				var target:=Vector3(at.x,session.world.ground_at(at.x,at.y)+float(view.get("lift",1.0)),-at.y)
				var eye:=target+_vector(view.get("eye",[0,3,10]))
				if view.has("eye_map"):
					var e:Array=view.eye_map
					eye=Vector3(float(e[0]),session.world.ground_at(float(e[0]),float(e[1]))+float(e[2]),-float(e[1]))
				print("TRAILER_SCOUT ",JSON.stringify({"name":view.name,"eye":[eye.x,eye.y,eye.z],"target":[target.x,target.y,target.z]}))
				game.rig.hold_view(eye,target)
				await frames(24)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out+"-scout-"+String(view.name)+".png")
		elif spec.has("scout_views"):
			for view: Dictionary in spec.scout_views:
				game.rig.hold_view(_vector(view.eye),_vector(view.target))
				await frames(24)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out+"-scout-"+String(view.name)+".png")
		elif game and spec.get("kind","") not in ["combat","coop"] and not spec.get("camera","") in ["first","third"]:
			var old: Array=spec.get("eye_from",[-16,12,20])
			var radius:=Vector2(float(old[0]),float(old[2])).length()
			for angle in 8:
				var rad:=float(angle)*TAU/8
				spec.eye_from=[sin(rad)*radius,float(old[1]),cos(rad)*radius]
				_camera(0)
				await frames(12)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out+"-angle-%d.png"%(angle*45))
		if game and (spec.get("kind","") in ["combat","coop"] or spec.get("camera","") in ["first","third"]):
			for step in int(spec.frames):
				_camera(float(step)/maxf(float(spec.frames)-1,1))
				_action(step+int(spec.get("pre_roll",0)))
				await frames(1)
				if step==int(spec.frames)/2:
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(out+"-middle.png")
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out+"-end.png")
			print("TRAILER_ACTION ",JSON.stringify(_action_report()))
			FileAccess.open(out+".json",FileAccess.WRITE).store_string(JSON.stringify({"action":_action_report(),"hit_samples":hit_samples,"movement_samples":movement_samples,"authored_encounter":encounter_start},"\t"))
		if not coordination.is_empty():FileAccess.open(coordination+"/done",FileAccess.WRITE).store_string("done")
		get_tree().quit();return
	total=int(spec.get("frames",240))
	first_frame=Engine.get_frames_drawn()
	report={"id":spec.id,"start_frame":first_frame,"frames":total,"fps":60,"width":picture.get_width(),"height":picture.get_height(),
		"campaign":GameData.campaign_id,"language":language,"seed":spec.get("seed",6519),"hd_packages":ModStore.profile().packages,
		"renderer":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info(),"staged":true,"graphics":_graphics_report(),"wardrobe":spec.get("wardrobe","offscreen"),"equipment":spec.get("equipment",{}),"authored_encounter":encounter_start}
	if spec.has("minimum_current"):
		var current:RefCounted=session.world.terrain._current
		if current==null:
			printerr("TRAILER_ERROR water currents are disabled");get_tree().quit(2);return
		var value:Vector3=current.sample(Vector2(focus.x,focus.z))
		report["water_current"]={"focus":[focus.x,focus.y,focus.z],"flow":[value.x,value.y],"speed":Vector2(value.x,value.y).length()}
	if not coop_start.is_empty(): report["coop"]=coop_start
	if game and game.sound.weather:
		report["weather"]={"native_type":game.sound.weather.type,"shown":game.sound.weather._shown,"target":game.sound.weather._target}
		report["weather"].merge(weather_proof)
	print("TRAILER_START ",JSON.stringify(report))
	recording=true

func _physics_process(_dt: float) -> void:
	# Native direct input has a 500 ms network watchdog. Offline rendering
	# can take longer than that between simulation frames. Keep only the
	# current input alive while filming; normal step/stop commands still
	# control movement, and native navigation/animation/damage stay intact.
	if hero and game and spec.get("camera","") in ["first","third"]:
		if not hero.direct_steering.is_empty():
			hero.direct_steering.until=Time.get_ticks_msec()+10000
		if hero.direct_look_until>0:hero.direct_look_until=Time.get_ticks_msec()+10000

func _process(_dt: float) -> void:
	if session and session.state: session.state.world_time=float(spec.get("hour",14))
	if game and game.rig:
		game.rig._window_focused=true
		game.hud.visible=bool(spec.get("hud",false))
		if spec.get("input","")=="gamepad":game.hud._field.hide()
		game.cursor.hide()
		game.hud._wiki_button.hide()
		if not spec.get("hud",false):
			game.marks.hide()
			if game.direct._overlay:game.direct._overlay.hide()
	if not recording:return
	var t:=float(index)/maxi(total-1,1)
	_camera(t)
	_action(index+int(spec.get("pre_roll",0)))
	if wiki and wiki._preview: wiki._preview.turn_by(0.002)
	index+=1
	if index==total/2:_middle.call_deferred()
	if index>=total:
		recording=false
		_finish.call_deferred()

func _camera(t: float) -> void:
	if not game:return
	if spec.get("camera","") in ["first","third"]:
		var wanted_heading:=deg_to_rad(float(spec.get("heading",0))+t*float(spec.get("pan",0)))
		var wanted_tilt:=float(spec.get("tilt",-0.1))
		if spec.get("track_enemy",false) and not enemies.is_empty() and not enemies[0].dead:
			wanted_heading=(enemies[0].pos-hero.pos).angle()
			if spec.camera=="third":wanted_heading+=asin(clampf(0.55/hero.pos.distance_to(enemies[0].pos),0.0,0.7))
			if spec.camera=="first":
				var aim:=enemies[0].global_position+Vector3.UP*maxf(enemies[0].figure_half_z,0.35)
				var head:=enemies[0].model.find_child("hd",true,false) as Node3D
				if head:aim=head.global_position
				var eye:=game.rig.camera.global_position
				var delta:=aim-eye
				wanted_tilt=clampf(atan2(delta.y,Vector2(delta.x,delta.z).length()),float(spec.get("minimum_tilt",-1.2)),1.1)
		if not camera_initialized:
			smooth_heading=wanted_heading;smooth_tilt=wanted_tilt;camera_initialized=true
		var ease:=1.0-exp(-float(spec.get("camera_response",5.0))/60.0)
		smooth_heading=lerp_angle(smooth_heading,wanted_heading,ease)
		smooth_tilt=lerpf(smooth_tilt,wanted_tilt,ease)
		game.direct.heading=smooth_heading
		game.direct.tilt=smooth_tilt
		if spec.has("camera_distance"):game.direct.zoom=float(spec.camera_distance)
		game.direct.apply_camera(1.0/60.0)
		return
	var ease:=t*t*(3.0-2.0*t)
	var a: Array=spec.get("eye_from",[-16,12,20])
	var b: Array=spec.get("eye_to",[-9,10,22])
	var offset:=Vector3(float(a[0]),float(a[1]),float(a[2])).lerp(Vector3(float(b[0]),float(b[1]),float(b[2])),ease)
	var target:=focus
	if spec.get("follow",false): target=hero.global_position+Vector3.UP*0.6
	game.rig.camera.fov=float(spec.get("fov",55))
	if spec.has("eye_world_from"):
		var eye:=_vector(spec.eye_world_from).lerp(_vector(spec.get("eye_world_to",spec.eye_world_from)),ease)
		game.rig.hold_view(eye,target)
	else:game.rig.hold_view(target+offset,target)

func _prepare_combat() -> void:
	var world:=session.world
	for entry: Dictionary in spec.get("enemies",[]):
		var nid:=int(entry.get("nid",0))
		var originals:=world.mob.objects.filter(func(o):return int(o.get("nid",0))==nid)
		var u: GameUnit=world.units.get(nid)
		if originals.is_empty() or u==null or u.dead:
			printerr("TRAILER_ERROR missing original encounter actor: ",nid);get_tree().quit(2);return
		var authored: Dictionary=originals[0]
		if String(authored.get("prototype",""))!=String(entry.prototype):
			printerr("TRAILER_ERROR original encounter prototype differs: ",nid);get_tree().quit(2);return
		var p: Vector3=authored.position
		# Reset this original actor at its authored location. Never clone or
		# relocate enemies to an unrelated landmark for the trailer.
		u.pos=Vector2(p.x,p.y);u._sync_transform(0);world.nav.track_unit(u)
		enemies.append(u);u.ai_next=INF;u._perceive_next=INF
		last_health[u.uid]=u.hp
		encounter_start.append({"nid":nid,"prototype":entry.prototype,"position":[p.x,p.y],"texture":authored.get("texture",""),"initial_hp":u.hp,"initial_severed":u.severed_mask()})
	print("TRAILER_ENCOUNTER ",JSON.stringify(encounter_start))
	for u: GameUnit in enemies:
		print("TRAILER_REACH ",JSON.stringify({"nid":u.uid,"distance":hero.pos.distance_to(u.pos),"melee_reach":hero.melee_reach(u),"enemy_stats":u.stats}))
	if not enemies.is_empty() and not spec.has("focus_world"):focus=(hero.global_position+enemies[0].global_position)*0.5+Vector3.UP*float(spec.get("combat_focus_lift",0.0))
	if spec.has("weapon"):
		hero.get_meta("hero").weapons=[String(spec.weapon)]
		session._refresh_hero(hero)
	if spec.has("spell"):
		hero.get_meta("hero").spells=[String(spec.spell)]
		hero.mana=hero.max_mana
		if not Spells.known_usable(hero,String(spec.spell)):
			printerr("TRAILER_ERROR hero cannot use staged spell: ",spec.spell);get_tree().quit(2)

func _start_combat() -> void:
	if not coordination.is_empty():FileAccess.open(coordination+"/action",FileAccess.WRITE).store_string("start")
	hero._perceive_next=0
	for u: GameUnit in enemies:
		u.ai_next=0;u._perceive_next=0
		if not spec.get("wait_for_hit",false):
			session.world.ai.on_attacked(u,hero)
			u.facing=(hero.pos-u.pos).angle()
			u.command({"type":"attack","target":hero})
	if not enemies.is_empty() and not spec.has("spell") and not spec.get("camera","") in ["first","third"] and spec.get("touch_demo","")!="combat":
		session.apply_command({"t":"attack","units":[hero.uid],"target":enemies[0].uid},0)

func _lava_anchor() -> Vector3:
	var terrain:=session.world.terrain
	var w:=terrain.sectors_x*EITerrain.SECTOR
	var h:=terrain.sectors_y*EITerrain.SECTOR
	var best:=INF
	var target:=focus
	for y in range(2,h-2,2):
		for x in range(2,w-2,2):
			if not LocalLighting._exposed_lava(terrain,x,y,w,h):continue
			if LocalLighting._exposed_lava(terrain,x-2,y,w,h) and LocalLighting._exposed_lava(terrain,x+2,y,w,h) and LocalLighting._exposed_lava(terrain,x,y-2,w,h) and LocalLighting._exposed_lava(terrain,x,y+2,w,h):continue
			var p:=Vector3(x+0.5,terrain.water[y*w+x],-(y+0.5))
			var score:=p.distance_squared_to(focus)
			if score<best:best=score;target=p
	return target

func _finish() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out+"-end.png")
	report["action"]=_action_report()
	report["movement_samples"]=movement_samples
	report["hit_samples"]=hit_samples
	if spec.get("touch_demo","")=="combat":report["touch"]={"events":touch_events,"inventory_open":game.hud._inventory.visible,"enabled":TouchInput.enabled}
	if spec.get("touch_demo","")=="inventory":
		report["touch"]={"events":touch_events,"inventory_open":game.hud._inventory.visible,"enabled":TouchInput.enabled}
	report["end_frame"]=Engine.get_frames_drawn()
	report["simulation_seconds"]=session.world.time if session and session.world else 0
	if not coop_start.is_empty():
		var other: GameUnit=session.party_units(1)[0]
		report.coop["guest_end"]=[other.pos.x,other.pos.y]
		report.coop["players_at_end"]=session.players.size()
		report.coop["client_command"]=JSON.parse_string(FileAccess.get_file_as_string(coordination+"/command"))
		FileAccess.open(coordination+"/done",FileAccess.WRITE).store_string("done")
	FileAccess.open(out+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TRAILER_DONE ",JSON.stringify(report))
	TexUpscale.shutdown()
	get_tree().quit()

func _middle() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out+"-middle.png")

func _wait_for(predicate: Callable) -> bool:
	var deadline:=Time.get_ticks_msec()+600000
	while not predicate.call():
		if Time.get_ticks_msec()>deadline:
			printerr("TRAILER_ERROR co-op synchronization timeout");get_tree().quit(2);return false
		OS.delay_msec(3)
		await get_tree().process_frame
	return true

func _apply_ultra() -> void:
	# The highest published graphics preset, explicitly pinned for every take.
	for row in GameData.OPTIONS:
		if String(row[0]).begins_with("gfx_"):GameData.options[row[0]]=int(row[2])-1
	GameData.options.merge({"graphics_preset":8,"q_aa":3,"q_shadows":3,"q_aniso":4,"q_shadow_fit":1,"render_scale":4,"auto_graphics":0},true)

func _graphics_report() -> Dictionary:
	var result:={}
	for key: String in GameData.options:
		if key.begins_with("gfx_") or key.begins_with("q_") or key in ["render_scale","auto_graphics","graphics_preset"]:result[key]=GameData.options[key]
	return result

func _vector(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

func _point(a: Array) -> Vector2:
	return Vector2(float(a[0]),float(a[1]))

func _action(frame: int) -> void:
	for u: GameUnit in enemies:
		if u.hp < float(last_health.get(u.uid,u.hp)):
			var event:={"frame":frame,"nid":u.uid,"damage":float(last_health[u.uid])-u.hp,"hp":u.hp,"severed":u.severed_mask()}
			hit_samples.append(event)
			print("TRAILER_DAMAGE ",JSON.stringify(event))
			if probe:_impact_image.call_deferred(frame)
		last_health[u.uid]=u.hp
	if spec.get("touch_demo","")=="combat" and frame in [6,12,90,96,180,186]:
		if frame%2==0:
			var pressed:=frame in [6,90,180]
			if pressed and not enemies.is_empty():
				touch_point=game.rig.camera.unproject_position(enemies[0].global_position+Vector3.UP*enemies[0].figure_half_z)
				touch_cue.position=touch_point;touch_cue.show()
			elif not pressed:touch_cue.hide()
			var touch:=InputEventScreenTouch.new()
			touch.index=0;touch.position=touch_point;touch.pressed=pressed
			Input.parse_input_event(touch);touch_events+=1
	if spec.get("touch_demo","")=="inventory" and frame in [18,24]:
		if frame==18:
			touch_point=game.hud.touch_actions._grid.get_child(0).get_global_rect().get_center()
			touch_cue.position=touch_point;touch_cue.show()
		else:touch_cue.hide()
		var event:=InputEventScreenTouch.new()
		event.index=0;event.position=touch_point;event.pressed=frame==18
		Input.parse_input_event(event)
		touch_events+=1
	if spec.get("input","")=="gamepad" and PadInput.field and frame%60==0:
		PadInput.field.wheel.cycle(1)
	if game and spec.get("camera","") in ["first","third"]:
		game.direct._neutral=false
		var retreat:=spec.has("keep_distance") and not enemies.is_empty() and hero.pos.distance_to(enemies[0].pos)<float(spec.keep_distance)
		var approach:bool=spec.get("approach",false) and not enemies.is_empty() and hero.pos.distance_to(enemies[0].pos)>hero.melee_reach(enemies[0])*0.9
		var advance:=frame<int(spec.get("advance_frames",0))
		game.direct.step(Vector2.UP if advance else (Vector2.DOWN if retreat else (Vector2.UP if approach else Vector2.ZERO)),1.0/60.0)
		if frame%12==0:movement_samples.append({"frame":frame,"pos":[hero.pos.x,hero.pos.y],"action":hero.action,"moving":advance or retreat or approach})
	if game and spec.get("camera","") in ["first","third"] and spec.has("enemies") and not spec.has("spell") and frame%24==0 and frame>=int(spec.get("advance_frames",0)):
		game.direct._neutral=false
		if frame==0:print("TRAILER_CONTROL ",JSON.stringify({"usable":game.direct.usable(),"active":game.direct.active(),"pointer":game.direct.pointer,"held":game.rig.held,"focus":game.rig._window_focused,"blocks":game.hud.blocks_camera(),"transition":game.direct.transitioning(),"movie":session.movie_active(),"controller":hero.controller,"is_host":session.is_host,"blocked":hero.blocked,"direct_controlled":hero.direct_controlled,"weapon":hero.info.get("weapons",[]),"stats":hero.stats}))
		if spec.has("aim_part") or spec.has("aim_parts"):
			var direction:=(game.direct.aim_point()-DirectCombat.origin(hero)).normalized()
			var command:={"t":"direct_attack","units":[hero.uid],"direction":direction,"aim":int(spec.get("aim_part",-1))}
			if spec.has("aim_parts") and not enemies.is_empty():
				for part in spec.aim_parts:
					if not enemies[0].severed_mask() & (1 << int(part)):
						command.aim=int(part);break
			command.merge(game.direct.aim_view(hero));game.issue(command)
		else:game.direct.attack()
		if frame%48==0:print("TRAILER_ATTACK ",JSON.stringify({"frame":frame,"orders":hero.orders.map(func(o):return String(o.get("type",""))),"action":hero.action,"cooldown":hero._attack_cd,"lock":hero._anim_lock,"pending":hero._pending_hit,"uid":hero.uid,"registered":session.world.units.get(hero.uid)==hero}))
	if game and spec.has("spell") and spec.get("spell_frames",[1,150]).any(func(value):return int(value)==frame) and not enemies.is_empty() and not enemies[0].dead:
		session.apply_command({"t":"cast","unit":hero.uid,"spell":String(spec.spell),"target":enemies[0].uid},0)

func _action_report() -> Dictionary:
	return {"paused":get_tree().paused,"hero": {"hp":hero.hp,"mana":hero.mana,"dead":hero.dead,"pos":[hero.pos.x,hero.pos.y],"order":String(hero.order.get("type","")),"action":hero.action,"attack_cooldown":hero._attack_cd,"pending_hit":hero._pending_hit,"direct_contacts":hero.direct_hit_serial} if hero else {},
		"enemies":enemies.map(func(u):return {"name":u.proto.get("name",""),"hp":u.hp,"max_hp":u.max_hp,"severed":u.severed_mask(),"dead":u.dead,"pos":[u.pos.x,u.pos.y],"action":u.action})}

func _dress(actor: GameUnit) -> bool:
	if not spec.has("equipment"):return true
	for item: String in Array(spec.equipment.get("armors",[]))+Array(spec.equipment.get("weapons",[])):
		var info:=Items.info(item)
		if info.row.is_empty() or info.mat.is_empty() or String(info.row.get("material_type","")).to_lower()!=String(info.mat.get("type","")).to_lower() or Items.look(item).is_empty():
			printerr("TRAILER_ERROR invalid wardrobe item: ",item);get_tree().quit(2);return false
	var h: Dictionary=actor.get_meta("hero")
	for skill: String in spec.equipment.get("skills",{}):
		if not skill in Skills.LIST or int(spec.equipment.skills[skill]) not in range(0,101):
			printerr("TRAILER_ERROR invalid staged skill: ",skill);get_tree().quit(2);return false
	h.merge(spec.equipment,true)
	session._refresh_hero(actor)
	return true

func _impact_image(frame: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out+"-hit-%04d.png"%frame)
	await frames(8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out+"-hit-%04d-plus08.png"%frame)

func _offline_peer(pid: int) -> void:
	# Ultra offline rendering may block longer than a real-time network load.
	# Extend only this private recording connection; gameplay is unchanged.
	var enet:=NetSim.enet_of(session.multiplayer)
	if enet==null or (not session.is_host and pid!=1):return
	var peer:=enet.get_peer(pid)
	if peer:peer.set_timeout(0,600000,600000)

extends "local_host_campaign.gd"
## Report #47 follow-up: a prepared LiA gate passage through the real solo
## authority, measuring both replicated and rendered positions. This does not
## reproduce the reporter's save, build, equipment, graphics or whole scene.
var rows: Array[Dictionary] = []
var start := Vector2(127,136)
var goal := Vector2(145,135)
var gate := 4306

func draw_point(u: GameUnit) -> Vector2:
	return Vector2(u.global_position.x,-u.global_position.z)

func animation_point(u: GameUnit) -> Array:
	return [u.model.player.current_animation,u.model.player.current_animation_position] if u.model and u.model.player else []

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://mine-passage-"+name+".png")

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"show_fps":1,
		"volume_sfx":0,"volume_stream":0,"volume_voice":0,"autosave":0,
		"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"free_run":0},true)
	check(GameData.campaign_id==CampaignProfile.ASTRAL,"LiA data selected")
	check(DisplayServer.get_name()!="headless","rendered frontend selected")
	if failures:get_tree().quit(1);return
	var seed:=Session.new();add_child(seed);seed.set_physics_process(false)
	var seed_game:=Game.new();seed_game.session=seed;seed.game=seed_game;add_child(seed_game)
	seed.state.ensure_hero(0,"Human Hero")
	# Use independent companion records. Three hero records with the same
	# prototype alias through apply_hero's legacy prototype fallback.
	for id in [900001,900002]:
		seed.state.make_merc(id,{"prototype":"Human Hero","name":"merc%d"%id})
	await seed.enter_zone("gz24k",1,false)
	check(seed.world!=null,"actual mine loads")
	if failures:get_tree().quit(1);return
	var w:=seed.world
	w.set_process(false);w.set_physics_process(false);seed.set_physics_process(false)
	w.lever_sys.set_state(gate,int(w.levers[gate].states)-1,0)
	# Preserve the full authored roster, collision and AI. Disable hostility
	# explicitly: combat in this uncleared fresh map would contaminate timing.
	for u:GameUnit in w.unit_rows():u.set_meta("peace",range(32));w.nav.track_unit(u)
	var party:=seed.party_units(0)
	check(party.size()==3,"prepared hero and two companions exist")
	if failures:get_tree().quit(1);return
	var starts:=[]
	for i in party.size():
		var u:GameUnit=party[i]
		u.command({"type":"wait","t":0.0})
		u.pos=w.nav.nearest_walkable_for(u,start-Vector2(i*1.6,0))
		u.set_gait(3);u.facing=(goal-u.pos).angle();u.mana=u.max_mana
		w.nav.track_unit(u);u._sync_transform();starts.append([u.pos.x,u.pos.y])
	seed.state.play_clock={"speed":0,"paused":false}
	check(seed.save_game("mine-passage-seed")==OK,"prepared full save created")
	var saved:=CampaignState.load_from(SaveInfo.path("mine-passage-seed"))
	var records:=[saved.heroes[0][0],saved.mercs[900001],saved.mercs[900002]]
	for i in party.size():
		check(records[i].pos.distance_to(Vector2(starts[i][0],starts[i][1]))<0.1,"seed stores each distinct party position")
	var fixture:={"zone":seed.zone_id,"gate":gate,"gate_name":w.objects[gate].get_meta("ei").name,
		"starts":starts,"target":[goal.x,goal.y],"population":w.units.size(),
		"preparation":"Fresh healthy hero and two synthetic Human Hero companions; open gate; all authored actors and scripts retained; hostility neutralized."}
	seed_game.queue_free();seed.queue_free()
	for i in 6:await get_tree().process_frame
	var s:=Session.new();get_parent().add_child(s)
	var g:=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	check(await s.local_host.start(0,1,true)==OK,"separate solo authority starts")
	var camera:=Camera3D.new();g.add_child(camera);camera.fov=45;camera.far=Gfx.far_clip()
	for mode in ["group","follow"]:
		for speed in [1,2]:
			Engine.max_fps=60
			var old_world:=s.world.get_instance_id() if s.world else 0
			check(await s.load_game_shown("mine-passage-seed"),"fresh passage save restored")
			check(await until(func():return s.world!=null and s.world.get_instance_id()!=old_world and not s._remote_loading and not s.loading_game and not s.movie_active() and not is_instance_valid(LoadingScreen._current),30),"new replica and visible loading barrier finish")
			party=s.party_units(0)
			check(party.size()==3 and not s.world.authority,"three party members in the real frontend replica")
			for i in party.size():
				check(party[i].pos.distance_to(Vector2(starts[i][0],starts[i][1]))<0.1,"distinct prepared party position survives save/load")
			g.rig.set_process(false);g.direct.set_process(false)
			var aim:=(start+goal)*0.5
			var height:=s.world.ground_at(aim.x,aim.y)
			camera.position=Vector3(aim.x-10,height+30,-aim.y+10)
			camera.look_at(Vector3(aim.x,height,-aim.y));camera.make_current()
			GameData._window_gen+=1;get_tree().root.mode=Window.MODE_WINDOWED;get_tree().root.size=Vector2i(960,720)
			g.set_speed(speed);Engine.max_fps=20
			# Wait for actual post-load snapshots before measuring: the loading
			# barrier releases the worker asynchronously, and time initially is 0.
			check(await until(func():return s.world.time>1.0,10),"post-load authority snapshots arrive")
			await get_tree().create_timer(1.0,true,false,true).timeout
			if mode=="group" and speed==1:
				await capture("before")
				# PNG readback blocks the frontend. Drain its pending snapshots
				# before starting the timed movement interval.
				await get_tree().create_timer(0.5,true,false,true).timeout
			var members:=[]
			for u:GameUnit in party:
				members.append({"id":u.uid,"from":u.pos,"draw_from":draw_point(u),"distance":0.0,
					"draw_distance":0.0,"previous":u.pos,"draw_previous":draw_point(u),"max_lag":0.0,
					"hp":u.hp,"animated_frames":0,"animation_previous":animation_point(u)})
			var ids:=party.map(func(u):return u.uid)
			var wall_start:=Time.get_ticks_usec();var sim_start:=s.world.time
			var frame_start:=Engine.get_process_frames()
			s.submit({"t":"move","units":ids if mode=="group" else [ids[0]],"x":goal.x,"y":goal.y,"run":true})
			if mode=="follow":s.submit({"t":"follow","units":ids.slice(1),"target":ids[0]})
			var trace:=[];var next_sample:=0.0
			while s.world.time-sim_start<6.0 and Time.get_ticks_usec()-wall_start<15000000:
				await get_tree().process_frame
				for i in party.size():
					var u:GameUnit=party[i];var m:Dictionary=members[i];var drawn:=draw_point(u)
					m.distance+=m.previous.distance_to(u.pos);m.draw_distance+=m.draw_previous.distance_to(drawn)
					m.previous=u.pos;m.draw_previous=drawn;m.max_lag=maxf(m.max_lag,u.pos.distance_to(drawn))
					var animation:=animation_point(u)
					if u.action in ["run","walk"] and not animation.is_empty() and animation!=m.animation_previous:m.animated_frames+=1
					m.animation_previous=animation
				if s.world.time-sim_start>=next_sample:
					trace.append({"t":s.world.time-sim_start,"wall":(Time.get_ticks_usec()-wall_start)/1000000.0,"units":party.map(func(u):return {
						"p":[u.pos.x,u.pos.y],"draw":[draw_point(u).x,draw_point(u).y],"action":u.action,"speed":u._move_speed})})
					next_sample+=0.5
			var wall:=(Time.get_ticks_usec()-wall_start)/1000000.0
			var sim:=s.world.time-sim_start
			check(absf(sim/wall-(55.0/27.0 if speed==2 else 1.0))<0.3,"simulation keeps requested wall-clock rate")
			for i in party.size():
				var u:GameUnit=party[i];var m:Dictionary=members[i]
				m.progress=m.from.distance_to(u.pos);m.draw_progress=m.draw_from.distance_to(draw_point(u))
				m.start=[m.from.x,m.from.y];m.end=[u.pos.x,u.pos.y]
				m.draw_start=[m.draw_from.x,m.draw_from.y];m.draw_end=[draw_point(u).x,draw_point(u).y]
				check(m.progress>6.0,"party member makes substantial passage progress")
				# Instant packet-to-draw lag can include a frame's newly received
				# snapshots. Qualify progress over time, not an arbitrary peak cap.
				check(absf(m.progress-m.draw_progress)<1.0,"displayed distance tracks replicated progress")
				var stalled:=false
				for j in range(4,trace.size()):
					var a:Dictionary=trace[j-4].units[i];var b:Dictionary=trace[j].units[i]
					var logical:=Vector2(a.p[0],a.p[1]).distance_to(Vector2(b.p[0],b.p[1]))
					var visible_distance:=Vector2(a.draw[0],a.draw[1]).distance_to(Vector2(b.draw[0],b.draw[1]))
					if logical>2.0 and visible_distance<0.25:stalled=true
				check(not stalled,"no sustained display stall while simulation moves")
				check(m.animated_frames>0,"movement animation advances in the rendered model")
				check(u.hp==m.hp and not u.dead,"combat did not contaminate movement")
				for key in ["from","draw_from","previous","draw_previous","animation_previous"]:m.erase(key)
			var row:={"mode":mode,"speed":speed,"fps_cap":20,"fps":float(Engine.get_process_frames()-frame_start)/wall,"wall":wall,"simulation":sim,"rate":sim/wall,"members":members,"trace":trace}
			rows.append(row);print("MINE_PASSAGE_SAMPLE ",mode," / ",speed," rate=",row.rate," members=",JSON.stringify(members))
			FileAccess.open("user://mine-passage-presentation.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":fixture,"samples":rows},"\t"))
			if mode=="group" and speed==1:await capture("after")
	Engine.max_fps=60;g.set_speed(1);await s.local_host.stop();g.queue_free();s.queue_free()
	for i in 6:await get_tree().process_frame
	FileAccess.open("user://mine-passage-presentation.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,
		"fixture":fixture,"samples":rows,"limitation":"Prepared diagnostic, not a reproduction of the supplied video or original-engine comparison."},"\t"))
	TexUpscale.shutdown();UnitWounds.shutdown()
	# This standalone fixture owns its process and has freed every world.
	# Release asynchronous procedural textures before the renderer shuts down.
	Gfx.clear_clouds();Gfx._noise_cache.clear()
	for i in 3:await get_tree().process_frame
	print("MINE_PASSAGE_PRESENTATION ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

extends Node
var checks:=0
var failures:=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _ready():
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	var loaded:=Time.get_ticks_usec()
	await s.enter_zone("gz20g",1,false)
	var load_ms:=(Time.get_ticks_usec()-loaded)/1000.0
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false)
	var curse:GameUnit=s.world.units[666666]
	check(curse.info.position.z==-20.0,"original map starts Curse twenty units below ground")
	curse._sync_transform(0)
	check(is_equal_approx(curse.position.y,s.world.ground_at(curse.pos.x,curse.pos.y)-20.0),"authored placement keeps Curse below floor before reveal")
	check(MoviePlayer._converters.is_empty(),"disabled movies do not start five conversion workers during zone load")
	var native:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir()+"/fixtures/original_unit_placement.json"))
	var kernel:Object=ClassDB.instantiate("UnitPresentationKernel")
	for row:Dictionary in native.rows:
		for method:String in ["SetCP","SetCPFast"]:
			var inst:=ScriptVM.Instance.new();inst.locals.actor=curse
			s.world.vm._eval([ScriptParser.N_CALL,method,[[ScriptParser.N_VAR,"actor"],[ScriptParser.N_NUM,curse.pos.x],[ScriptParser.N_NUM,curse.pos.y],[ScriptParser.N_NUM,row.requested_z]]],inst)
			check(row.success and curse.placement_z==row.actual_z,method+" agrees with native 0x5c11d0 at z="+str(row.requested_z))
			var expected:float=s.world.ground_at(curse.pos.x,curse.pos.y)+row.actual_z
			check(is_equal_approx(curse.position.y,expected),"script presentation keeps original placement height")
			s.world.authority=false;curse.net_view.got(curse.pos,true,curse.facing)
			curse.position.y+=1.0 # force a client redraw rather than accepting the script cache
			check(kernel.sync_client(s.world,curse,0.0) and is_equal_approx(curse.position.y,expected),"compiled replica keeps original placement height")
			s.world.authority=true
	curse.placement_z=-20;curse._sync_transform(0)
	var snapshot:=curse.snapshot()
	curse.placement_z=0;curse.apply_snapshot(snapshot,true);curse._sync_transform(0)
	check(curse.placement_z==-20.0,"network snapshot retains hidden placement height")
	s.state.store_zone("gz20g",s.world)
	curse.placement_z=0;s.state.restore_zone("gz20g",s.world)
	check(curse.placement_z==-20.0,"save restores pre-reveal height")
	var events:=[]
	g.event_presented.connect(func(e):events.append(e.duplicate(true)))
	var vm:=s.world.vm
	for i in 120:vm.tick(GameUnit.TICK)
	check(curse.placement_z==-20.0,"Curse stays below floor during original Sleep(125)")
	for i in 15:vm.tick(GameUnit.TICK)
	check(curse.placement_z==0.0,"original delayed SetCP reveals Curse at ground")
	check(events.any(func(e):return e.get("t")=="fxcmd" and e.get("f")=="CreateFX"),"authored reveal emits its effect")
	print("REVEAL_EVENTS ",events.filter(func(e):return e.get("t") not in ["journal","inventory"]))
	s.state.store_zone("gz20g",s.world);curse.placement_z=-20;s.state.restore_zone("gz20g",s.world)
	check(curse.placement_z==0.0,"post-reveal reload cannot bury Curse again")
	var c:=CreditsPanel.new();add_child(c)
	for i in 12:await get_tree().process_frame
	check(c._music.stream!=null,"original Credits music resolves to bonus.mp3")
	check(c._music.playing and c._music.bus=="Movie","credits music uses isolated movie bus")
	check(GameData._movie_audio_owners.has(c.get_instance_id()),"credits owns game-audio suppression between movies")
	var before:=s.world.time
	s.broadcast({"t":"ending"})
	check(s.ending_active and s.world.process_mode==Node.PROCESS_MODE_DISABLED,"ending stops world and background auto-casts")
	s.world._deliver(1.0)
	check(s.world.time==before,"ending rejects an already queued simulation callback")
	c.queue_free();g.queue_free();s.queue_free()
	for i in 10:await get_tree().process_frame
	check(GameData._movie_audio_owners.is_empty(),"credits cleanup releases audio ownership")
	FileAccess.open("user://ending_scene.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"load_ms":load_ms},"\t"))
	print("ENDING_SCENE ",checks," checks ",failures.size()," failures")
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)

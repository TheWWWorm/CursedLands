extends "local_host_campaign.gd"
## #119: measure gameplay state, not only the displayed simulation timestamp.
var samples: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"show_tutorial":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1),true)
	var seed := Session.new(); add_child(seed)
	seed.local_host.worker = true; seed.local_host.single_player = true
	var seed_game := Game.new(); seed_game.session=seed; seed.game=seed_game; add_child(seed_game)
	seed.state.ensure_hero(0,"Human Hero")
	seed._enter_zone("gz3g",1,false)
	seed.state.god_modes[0]=1
	var hero: GameUnit = seed.world.party_units()[0]
	hero.mana=0; hero.aggressive=false
	hero.buffs.eagle_sight={"until":seed.world.time+100.0,"_effect_ticks":1800,"sense":[0,10.0]}
	seed.restore_play_clock({"speed":0,"paused":true})
	check(seed.save_game("foothills-clock-seed")==OK,"Foothills actor fixture saved")
	seed_game.queue_free();seed.queue_free()
	for i in 8: await get_tree().process_frame
	var s:=Session.new();get_parent().add_child(s)
	var g:=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	check(await s.local_host.start(0,1,true)==OK,"separate solo worker starts")
	for speed in [1,2,1,2]:
		var answer:=await s.local_host.request("load",{"slot":"foothills-clock-seed"})
		check(answer.get("ok",false),"worker loads fixture")
		check(await until(func():return s.world!=null and not s._remote_loading and LoadingScreen._current==null and ShaderCompilationScreen._current==null,60),"Foothills loading completes")
		g.set_speed(speed)
		await get_tree().create_timer(0.25,true,false,true).timeout
		hero=s.world.party_units()[0]
		var mana:=hero.mana;var ticks:=hero.effect_ticks("eagle_sight");var sim:=s.world.time
		var start:=Time.get_ticks_usec()
		await get_tree().create_timer(3.0,true,false,true).timeout
		var wall:=(Time.get_ticks_usec()-start)/1000000.0
		var row:={"sector":speed,"wall":wall,"sim":s.world.time-sim,"ticks":ticks-hero.effect_ticks("eagle_sight"),"mana":hero.mana-mana,"action":hero.action}
		samples.append(row);print("ACTOR_RATE ",JSON.stringify(row))
		check(absf(float(row.sim)/wall-(55.0/27.0 if speed==2 else 1.0))<0.2,"world follows selected rate")
		check(absf(float(row.ticks)*GameUnit.TICK/wall-(55.0/27.0 if speed==2 else 1.0))<0.2,"Eagle Sight follows selected rate")
		check(float(row.mana)>0.0,"mana regenerates while idle")
	for i in [0,2]:
		check(float(samples[i+1].mana)/maxf(0.1,float(samples[i].mana))>1.7,"accelerated mana recovery is faster")
	await s.local_host.stop();g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	FileAccess.open("user://foothills-actor-clock.json",FileAccess.WRITE).store_string(JSON.stringify(samples,"\t"))
	print("FOOTHILLS_ACTOR_CLOCK ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)

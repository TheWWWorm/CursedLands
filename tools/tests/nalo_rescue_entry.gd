extends "nalo_rescue_return.gd"
## Explicit prepared q60h return checkpoint, then only normal UI/world commands.
func _run() -> void:
	evidence.setup="Prepared original HeroAlone/q60h-complete/Kr60-offered village boundary. The actual Kr60 conversation and native party/quest handoff are not prepared or directly invoked."
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-save="): input_path=arg.trim_prefix("--resume-save=")
		if arg=="--completed":completed=true
	for opt: Array in GameData.OPTIONS:
		if String(opt[0]).begins_with("gfx_"): GameData.options[opt[0]]=0
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"control_mode":1},true)
	TutorialPanel.auto_show=false
	s=Session.new(); add_child(s); s.set_physics_process(false)
	game=Game.new(); game.session=s; s.game=game; add_child(game)
	if input_path.is_empty():
		s.state.ensure_hero(0,"Human Hero")
		s.state.create_party("HeroAlone"); s.state.add_party_unit("HeroAlone","Hero","Human Hero Hadagan")
		s.state.copy_stats("Hero","HeroAlone::Hero"); s.state.set_current_party("HeroAlone")
		s.state.set_var(0,"q.gz15h.q60h",2)
		s.state.set_var(0,"b.bz13h.Hns59",2)
		s.state.set_var(0,"b.Nalo.Kr60",1)
		await s.enter_zone("bz13h",1,false)
	else:
		evidence.input=input_path
		evidence.setup="Fresh process resumes a prior test checkpoint without campaign/actor edits. Its earlier q60h boundary was explicitly prepared."
		DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
		if not check(DirAccess.copy_absolute(input_path,SaveInfo.path("entry_input"))==OK and s.load_game("entry_input"),"fresh process loads entry checkpoint"):
			await finish();return
	s.world.set_process(false); s.world.set_physics_process(false); game.rig.set_process(false)
	evidence.cage_zones=[]
	for id:String in s.campaign.zones:
		if s.campaign.zones[id].get("cage",false):evidence.cage_zones.append(id)
	if completed:
		snapshot("completed rescue entry freshly loaded")
		check(s.zone_id=="gz15h" and s.state.current_party=="Pretty","native Nalo role and destination survive fresh load")
		check(s.state.get_var(0,"b.Nalo.Kr60")==2,"completed handoff stays complete")
		check(s.state.get_var(0,"q.gz15h.q61h")==1,"native rescue quest survives fresh load")
		check(s.party_units(0).size()==1 and s.party_units(0)[0].info.get("name","")=="Nalo" and not s.party_units(0)[0].dead,"living original Nalo protagonist survives reload")
		var saved:=CampaignState.load_from(input_path)
		for key in ["prototype","unit_name","str","dex","int","skills","armors","weapons","spells"]:
			check(s.state.heroes[0][0].get(key)==saved.heroes[0][0].get(key),"native Nalo retains "+key)
		await finish();return
	var start_time:=s.world.time
	await until(func():return s.world.time>=start_time+1.0,"native village startup settles",100)
	var npc: GameUnit=s.world.vm._by_name("Nalo")
	if not check(npc!=null,"original Nalo display actor is present"):
		await finish();return
	var hero: GameUnit=s.party_units(0)[0]
	evidence.approach={"hero":clean(hero.pos),"npc":clean(npc.pos),"blocked":hero.blocked,"pending":Briefings.pending_for(s.state,npc,0),"cage":s.world.zone.get("cage",false),"q60h":s.state.get_var(0,"q.gz15h.q60h"),"q61h":s.state.get_var(0,"q.gz15h.q61h")}
	var ignored: Array=[hero]
	for u: GameUnit in s.world.unit_rows():
		if u!=hero:ignored.append(u)
	evidence.static_route={"from_open":s.world.nav.cell_open(hero.pos,hero.move_class()),"target_open":s.world.nav.cell_open(npc.pos,hero.move_class()),"points":clean(s.world.nav.find_path(hero.pos,npc.pos,ignored,[],0.0,hero.move_class(),true)),"ignored_actors":ignored.size()}
	snapshot("prepared first-conversation boundary")
	check(s.state.get_var(0,"q.gz15h.q61h")==0,"rescue quest was not prepared")
	check(s.save_game("nalo_entry_pending")==OK,"pending first conversation saves")
	var cmd:Dictionary={"t":"interact","target":npc.uid,"units":[hero.uid],"unit":hero.uid}
	evidence.commands.append(cmd);game.issue(cmd)
	if not await until(func():return not game.hud._dialog._topics.is_empty(),"ordinary approach opens first Nalo conversation",600):
		await finish();return
	var options:Array=game.hud._dialog._topics.get("options",[])
	evidence.topics=options.duplicate(true)
	var index:=-1
	for i in options.size():
		if options[i].get("var","")=="b.Nalo.Kr60":index=i
	if not check(index>=0,"original Kr60 topic is offered"):
		await finish();return
	evidence.commands.append({"ui":"select topic","var":"b.Nalo.Kr60","index":index})
	game.hud._dialog._on_topic(index);advance_dialogue=true
	if not await until(func():return not s.loading_game and s.zone_id=="gz15h" and s.state.current_party=="Pretty","actual conversation starts native Nalo rescue"):
		await finish();return
	snapshot("native rescue arrival")
	check(s.state.get_var(0,"b.Nalo.Kr60")==2,"first Nalo conversation completes")
	check(s.state.get_var(0,"q.gz15h.q61h")==1,"native briefing starts the rescue quest")
	check(s.party_units(0).size()==1 and s.party_units(0)[0].info.get("name","")=="Nalo","original Nalo protagonist is deployed")
	check(not s.party_units(0)[0].dead,"Nalo arrives alive")
	check(s.save_game("nalo_entry_complete")==OK,"native rescue entry saves")
	await finish()

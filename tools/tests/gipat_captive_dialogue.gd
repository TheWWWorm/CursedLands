extends "nalo_rescue_return.gd"
## Prepared original camp-arrival briefing, then normal UI/script flow only.
func _run() -> void:
	evidence.setup="Prepared original bz4g arrival with b.bz4g.Ha29 offered; no topic completion or actor placement is forced."
	var hermit_first:bool="--hermit-first" in OS.get_cmdline_user_args()
	evidence.hermit_first=hermit_first
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-save="):input_path=arg.trim_prefix("--resume-save=")
		if arg=="--completed":completed=true
	for opt:Array in GameData.OPTIONS:
		if String(opt[0]).begins_with("gfx_"):GameData.options[opt[0]]=0
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"control_mode":1},true)
	TutorialPanel.auto_show=false
	s=Session.new();add_child(s);s.set_physics_process(false)
	game=Game.new();game.session=s;s.game=game;add_child(game)
	if input_path.is_empty():
		s.state.ensure_hero(0,"Human Hero")
		s.state.set_var(0,"b.bz4g.Ha29",1)
		await s.enter_zone("bz4g",1,false)
	else:
		evidence.input=input_path
		DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
		if not check(DirAccess.copy_absolute(input_path,SaveInfo.path("captive_input"))==OK and s.load_game("captive_input"),"fresh process loads captive checkpoint"):
			await finish();return
	s.world.set_process(false);s.world.set_physics_process(false);game.rig.set_process(false)
	if completed:
		snapshot("completed captive escape freshly loaded")
		check(s.zone_id=="gz4g" and s.state.current_party=="","authored field destination and original party survive reload")
		check(s.state.get_var(0,"b.HWLeader.Ha29_1")==float(1 if hermit_first else 2),"optional commander topic retains its actual completion")
		for key in ["b.bz4g.Ha29","b.OLiz.Ha29_2","b.OLiz.Ha29_3"]:
			check(s.state.get_var(0,key)==2,"completed conversation stays complete: "+key)
		var saved:=CampaignState.load_from(input_path)
		for key in ["unit_name","str","dex","int","skills","armors","weapons","spells"]:
			check(s.state.party_member("Hero").get(key)==saved.party_member("Hero").get(key),"escaped hero retains "+key)
		check(not s.party_units(0).is_empty() and s.party_units(0).all(func(u:GameUnit):return not u.dead),"escaped party remains alive")
		await finish();return
	advance_dialogue=true
	if not await until(func():return s.state.get_var(0,"b.bz4g.Ha29")==2,"original camp arrival conversation completes normally",600):
		await finish();return
	check(s.save_game("captive_arrival")==OK,"offered captive conversation checkpoint saves")
	evidence.approaches=[]
	for step:Array in [["HWLeader","b.HWLeader.Ha29_1"],["OLiz","b.OLiz.Ha29_2"],["OLiz","b.OLiz.Ha29_3"]]:
		if hermit_first and step[0]=="HWLeader":continue
		if s.state.get_var(0,step[1])==2:continue
		if step[1]=="b.OLiz.Ha29_3":
			check(s.save_game("captive_escape_offered")==OK,"pending native escape offer saves before selection")
		var npc:GameUnit=s.world.vm._by_name(step[0])
		if not check(npc!=null,"original "+step[0]+" actor exists"):
			await finish();return
		if not await until(npc.village_talk_ready,"native NPC becomes available after previous dialogue",800):
			evidence.unready={"uid":npc.uid,"order":clean(npc.order),"orders":clean(npc.orders),"talk_command":npc._talk_command,"talk_posted":npc._talk_posted}
			await finish();return
		var hero:GameUnit=s.party_units(0)[0]
		var ignored:Array=[hero]
		for u:GameUnit in s.world.unit_rows():
			if u!=hero:ignored.append(u)
		evidence.approaches.append({"topic":step[1],"hero":clean(hero.pos),"npc":clean(npc.pos),"blocked":hero.blocked,"ready":npc.village_talk_ready(),"pending":Briefings.pending_for(s.state,npc,0),"static_path":clean(s.world.nav.find_path(hero.pos,npc.pos,ignored,[],0.0,hero.move_class(),true))})
		check(s.state.get_var(0,step[1])==1,"native handler offers "+step[1])
		var cmd:Dictionary={"t":"interact","target":npc.uid,"units":[hero.uid],"unit":hero.uid}
		evidence.commands.append(cmd);game.issue(cmd)
		if not await until(func():return not game.hud._dialog._topics.is_empty(),"ordinary approach opens "+step[1],800):
			await finish();return
		var index:=-1
		var options:Array=game.hud._dialog._topics.get("options",[])
		for i in options.size():
			if options[i].get("var","")==step[1]:index=i
		if not check(index>=0,"native topic is selectable: "+step[1]):
			await finish();return
		evidence.commands.append({"ui":"select topic","index":index,"var":step[1]})
		game.hud._dialog._on_topic(index)
		if not await until(func():return s.state.get_var(0,step[1])==2,"normal dialogue completes "+step[1],800):
			await finish();return
	if not await until(func():return not s.loading_game and s.zone_id=="gz4g","native escape returns to authored field map",200):
		await finish();return
	snapshot("native cage-scene exit")
	check(s.state.get_var(0,"b.OLiz.Ha29_3")==2,"native escape conversation completes")
	check(s.state.current_party=="" and not s.party_units(0).is_empty() and s.party_units(0).all(func(u:GameUnit):return not u.dead),"original living party reaches authored escape destination")
	check(s.save_game("bz4g_cage_flow")==OK,"completed camp interlude saves normally")
	await finish()

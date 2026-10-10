extends "jun_transformation_route.gd"
## Normal topic/checkpoint helpers, with a separate LiA entry contract.
## Shaina is the original party's internal name; its merc8 body is Fairuz.
func source_receipt() -> void:
	var raw := GameData.read_file("maps/bz5h.mob")
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(raw)
	var ast := ScriptParser.parse(EIMob.load_bytes(raw).script_text)
	evidence.native_source={"path":"maps/bz5h.mob","sha256":hash.finish().hex_encode(),
		"completion":ast.scripts.get("#OnBriefingComplete",{})}
	check(not evidence.native_source.completion.is_empty(),"loaded original MOB contains disguise entry")

func snapshot(label: String) -> void:
	var row := {"label":label,"zone":s.zone_id,"party":s.state.current_party,
		"brief_23":s.state.get_var(0,"b.merc8.brief_23"),"q8h":s.state.get_var(0,"q.gz2h.q8h"),
		"heroes":clean(s.state.heroes),"parties":clean(s.state.parties),"actors":[]}
	if s.world:
		row.active=s.world.vm.briefings.active;row.unknown_calls=s.world.vm.unknown_calls.duplicate()
		for u: GameUnit in s.world.party_units():
			row.actors.append({"uid":u.uid,"name":u.info.get("name",""),"pos":clean(u.pos),"hp":u.hp,"dead":u.dead})
	evidence.trace.append(row)
	print("SHAINA_ENTRY_STATE ",label," ",row.zone," ",row.party)

func _run() -> void:
	evidence.setup="Prepared original FSusel party after q7h, with brief_23 offered in bz5h. No Shaina body, q8h stage, actor placement or travel is forced."
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-save="):input_path=arg.trim_prefix("--resume-save=")
	for opt: Array in GameData.OPTIONS:
		if String(opt[0]).begins_with("gfx_"):GameData.options[opt[0]]=0
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"control_mode":1},true)
	TutorialPanel.auto_show=false
	create_session()
	if input_path.is_empty():
		s.state.create_party("FSusel");s.state.add_party_unit("FSusel","Hero2","Hero2");s.state.set_current_party("FSusel")
		s.state.heroes[0][0].name="Disguise route protagonist"
		s.state.heroes[0][0].str=31.0;s.state.heroes[0][0].dex=29.0;s.state.heroes[0][0].int=27.0
		s.state.money=555;s.state.items=["rune:e1"]
		s.state.set_var(0,"q.gz2h.q7h",2);s.state.set_var(0,"b.merc8.brief_23",1)
		await s.enter_zone("bz5h",1,false)
	else:
		evidence.input=input_path
		evidence.setup="Fresh process resumes a prior prepared disguise-entry checkpoint without campaign/actor edits."
		DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
		if not check(DirAccess.copy_absolute(input_path,SaveInfo.path("shaina_input"))==OK and s.load_game("shaina_input"),"fresh process loads disguise checkpoint"):
			await finish();return
	s.world.set_process(false);s.world.set_physics_process(false);game.rig.set_process(false)
	source_receipt()
	expected_hero=s.state.party_member("FSusel::Hero2").duplicate(true)
	expected_bag=s.state._bag("FSusel").duplicate(true)
	evidence.expected_hero=clean(expected_hero);evidence.expected_bag=clean(expected_bag)
	snapshot("initial boundary")
	advance_dialogue=true
	if not await topic("merc8","b.merc8.brief_23"):
		await finish();return
	if not await until(func():return not s.loading_game and s.zone_id=="gz2h" and s.state.current_party=="Shaina","native briefing deploys Fairuz at the authored mission entry",300):
		await finish();return
	check(s.state.get_var(0,"q.gz2h.q8h")==1,"native dialogue starts q8h")
	var actors := s.party_units(0)
	check(actors.size()==1 and actors[0].info.get("name","")=="merc8" and not actors[0].dead,"living original Fairuz body is deployed")
	check(s.state.money==0 and s.state.items.is_empty(),"temporary role starts with its own empty bag")
	var hero := s.state.party_member("FSusel::Hero2")
	for key: String in ["name","str","dex","int","skills","perks","armors","weapons","quick","spells"]:
		check(hero.get(key)==expected_hero.get(key),"parked party keeps original protagonist "+key)
	check(s.state._bag("FSusel")==expected_bag,"parked party keeps original protagonist bag")
	check(s.state.get_var(0,"b.merc8.brief_23")==2,"entry conversation stays completed")
	checkpoint("shaina_entry_complete")
	await finish()

func finish() -> void:
	if s and s.world:check(s.world.vm.unknown_calls.is_empty(),"final world has no unresolved original calls")
	check(errors.messages.is_empty(),"native disguise entry has no runtime errors")
	evidence.checks=checks;evidence.failures=failures;evidence.errors=errors.messages
	FileAccess.open("user://shaina-entry.json",FileAccess.WRITE).store_string(JSON.stringify(clean(evidence),"\t"))
	if game:game.queue_free()
	if s:s.queue_free()
	for i in 10:await get_tree().process_frame
	TexUpscale.shutdown();OS.remove_logger(errors)
	print("SHAINA_ENTRY ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)

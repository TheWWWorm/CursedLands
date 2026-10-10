extends "nalo_rescue_return.gd"
## Prepared post-q72h return boundary, then native dialogues, timers and travel.
var stop_stage := ""
var expected_hero := {}
var expected_bag := {}
const STORY_KEYS := ["q.gz19k.q72h", "b.bz7g.R72", "b.Rick.R72_1", "JPC", "Polymorph",
	"b.Rick.R72_4", "b.Deva.D72_5", "b.Rick.R72_6", "b.Rick.R72_7"]

func snapshot(label: String) -> void:
	var row := {"label":label, "zone":s.zone_id, "party":s.state.current_party,
		"vars":{}, "heroes":clean(s.state.heroes), "parties":clean(s.state.parties),
		"money":s.state.money, "items":clean(s.state.items), "actors":[]}
	for key: String in STORY_KEYS: row.vars[key]=s.state.get_var(0,key)
	if s.world:
		row.active=s.world.vm.briefings.active
		row.unknown_calls=s.world.vm.unknown_calls.duplicate()
		for u: GameUnit in s.world.party_units():
			row.actors.append({"uid":u.uid,"name":u.info.get("name",""),"pos":clean(u.pos),
				"hp":u.hp,"dead":u.dead,"blocked":u.blocked,"order":clean(u.order)})
	evidence.trace.append(row)
	print("JUN_ROUTE_STATE ",label," ",row.zone," ",row.party," ",row.vars)

func source_receipt() -> void:
	var raw := GameData.read_file("maps/bz7g.mob")
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(raw)
	var ast := ScriptParser.parse(EIMob.load_bytes(raw).script_text)
	evidence.native_source={"path":"maps/bz7g.mob","sha256":hash.finish().hex_encode(),
		"transition":ast.scripts.get("VTriger#0#57",{}),
		"entry_gate":ast.scripts.get("VCheck#0#56",{}),
		"completion":ast.scripts.get("#OnBriefingComplete",{})}
	check(not evidence.native_source.transition.is_empty(),"loaded original MOB contains Jun transition")

func topic(actor: String, key: String) -> bool:
	if s.state.get_var(0,key)==2: return true
	var npc: GameUnit=s.world.vm._by_name(actor)
	if not check(npc!=null,"original "+actor+" actor is present"): return false
	if not await until(npc.village_talk_ready,"native "+actor+" is ready for "+key,800): return false
	check(s.state.get_var(0,key)==1,"original handler offers "+key)
	var hero: GameUnit=s.party_units(0)[0]
	var cmd := {"t":"interact","target":npc.uid,"units":[hero.uid],"unit":hero.uid}
	evidence.commands.append(cmd);game.issue(cmd)
	if not await until(func():return not game.hud._dialog._topics.is_empty(),"ordinary approach opens "+key,1000): return false
	var options: Array=game.hud._dialog._topics.get("options",[])
	var index := -1
	for i in options.size():
		if String(options[i].get("var","")).to_lower()==key.to_lower(): index=i
	evidence.commands.append({"ui":"select topic","var":key,"options":options,"index":index})
	if not check(index>=0,"original topic is selectable: "+key): return false
	game.hud._dialog._on_topic(index)
	return await until(func():return s.state.get_var(0,key)==2,"normal dialogue completes "+key,1000)

func checkpoint(slot: String) -> bool:
	snapshot(slot)
	var ok := check(s.save_game(slot)==OK,"native route saves "+slot)
	if ok: evidence.get_or_add("output_saves",{})[slot]=SaveInfo.path(slot)
	return ok

func verify_jun() -> void:
	check(s.state.current_party=="JunParty","original Jun party is current")
	var hero := s.state.party_member("JunParty::JunBoy")
	check(not hero.is_empty() and hero.prototype=="Jun Male Hero","original Jun body is selected")
	for key: String in ["name","str","dex","int","exp","exp_total","level","skills","perks","armors","weapons","quick","spells"]:
		check(hero.get(key)==expected_hero.get(key),"native transformation preserves protagonist "+key)
	check({"money":s.state.money,"items":s.state.items}==expected_bag,"native transformation preserves own bag")
	var actors := s.party_units(0)
	check(actors.size()==1 and actors[0].info.get("name","")=="JunBoy" and not actors[0].dead,"living Jun protagonist is actually deployed")

func create_session() -> void:
	s=Session.new();add_child(s);s.set_physics_process(false)
	game=Game.new();game.session=s;s.game=game;add_child(game)

func arrival_ready() -> void:
	pass

func _run() -> void:
	evidence.setup="Prepared original q72h-complete/R72-offered bz7g arrival. No dialogue completion, transformation, actor placement or later quest state is forced."
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-save="): input_path=arg.trim_prefix("--resume-save=")
		if arg.begins_with("--stop-stage="): stop_stage=arg.trim_prefix("--stop-stage=")
		if arg=="--completed": completed=true
	for opt: Array in GameData.OPTIONS:
		if String(opt[0]).begins_with("gfx_"): GameData.options[opt[0]]=0
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"control_mode":1},true)
	TutorialPanel.auto_show=false
	create_session()
	if input_path.is_empty():
		s.state.ensure_hero(0,"Human Hero","Jun route protagonist")
		s.state.heroes[0][0].str=31.0;s.state.heroes[0][0].dex=29.0;s.state.heroes[0][0].int=27.0
		s.state.money=222;s.state.items=["rune:e1"]
		s.state.set_var(0,"q.gz19k.q72h",2)
		s.state.set_var(0,"b.bz7g.R72",1)
		await s.enter_zone("bz7g",1,false)
	else:
		evidence.input=input_path
		evidence.setup="Fresh process resumes a prior prepared Jun-route checkpoint without campaign/actor edits."
		DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
		if not check(DirAccess.copy_absolute(input_path,SaveInfo.path("jun_input"))==OK and s.load_game("jun_input"),"fresh process loads Jun checkpoint"):
			await finish();return
	s.world.set_process(false);s.world.set_physics_process(false);game.rig.set_process(false)
	source_receipt()
	expected_hero=s.state.party_member("Hero").duplicate(true)
	expected_bag=s.state._bag("").duplicate(true)
	evidence.expected_hero=clean(expected_hero);evidence.expected_bag=clean(expected_bag)
	snapshot("initial boundary")
	await arrival_ready()
	if completed:
		check(s.zone_id=="gz20g","authored transformed destination survives fresh load")
		verify_jun()
		for key: String in STORY_KEYS:
			if key.begins_with("b."): check(s.state.get_var(0,key)==2,"completed dialogue survives reload: "+key)
		await finish();return
	advance_dialogue=true
	if not await until(func():return s.state.get_var(0,"b.bz7g.R72")==2,"native arrival dialogue completes",1000):
		await finish();return
	if not await until(func():return s.state.get_var(0,"b.Rick.R72_1")>=1,"native arrival offers Rick transformation",100):
		await finish();return
	if not await topic("Rick","b.Rick.R72_1"):
		await finish();return
	if s.state.get_var(0,"Polymorph")<7:
		if not await until(func():return s.state.get_var(0,"JPC")==1,"native transformation timer starts",100):
			await finish();return
		if stop_stage=="before-body":
			checkpoint("jun_before_body");await finish();return
		if not await until(func():return s.state.get_var(0,"Polymorph")>=7,"original timed transformation redeploys Jun",400):
			await finish();return
	verify_jun()
	if stop_stage=="after-body":
		checkpoint("jun_after_body");await finish();return
	if not await until(func():return s.state.get_var(0,"b.Rick.R72_4")==2,"native follow-up conversation completes",600):
		await finish();return
	for step: Array in [["Deva","b.Deva.D72_5"],["Rick","b.Rick.R72_6"],["Rick","b.Rick.R72_7"]]:
		if not await topic(step[0],step[1]):
			await finish();return
	if not await until(func():return not s.loading_game and s.zone_id=="gz20g","normal departure dialogue travels to authored Jun map",200):
		await finish();return
	verify_jun()
	checkpoint("jun_route_complete")
	await finish()

func finish() -> void:
	if s and s.world: check(s.world.vm.unknown_calls.is_empty(),"final world has no unresolved original calls")
	check(errors.messages.is_empty(),"native Jun route has no runtime errors")
	evidence.checks=checks;evidence.failures=failures;evidence.errors=errors.messages
	FileAccess.open("user://jun-route.json",FileAccess.WRITE).store_string(JSON.stringify(clean(evidence),"\t"))
	if game:game.queue_free()
	if s:s.queue_free()
	for i in 10:await get_tree().process_frame
	TexUpscale.shutdown();OS.remove_logger(errors)
	print("JUN_ROUTE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)

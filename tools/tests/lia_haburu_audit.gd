extends Node
## Direct village-entry audit, not an ordinary campaign or optional-quest run.
## Read-only source inventory and real Start/topic/save flow; no quest repair.
var checks := 0
var failures: Array[String] = []
var script_rows := []
var session: Session
var game: Game
var finished := false
var frame := 0
var entry_unknown_calls := {}
var placement := {}

class Errors extends Logger:
	var messages: Array[String] = []
	func _log_error(fn: String, file: String, line: int, code: String,
		why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind != ERROR_TYPE_WARNING: messages.append("%s %s (%s:%d %s)" % [code,why,file,line,fn])

var errors := Errors.new()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)
	return ok

func until(predicate: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline and errors.messages.is_empty():
		if predicate.call(): return check(true,label)
		await get_tree().process_frame
	if session and session.world:
		for unit: GameUnit in session.world.units.values():
			if unit.controller==0 or String(unit.info.get("name","")).to_lower()=="haburu":
				print("HABURU_STOP ",unit.uid," pos ",unit.pos," order ",unit.order," failed ",unit.order_failed," blocked ",unit.blocked," talk_ready ",unit.village_talk_ready()," interact ",unit.get_meta("interact",[]))
		print("HABURU_STOP ui ",session.command_allowed({"t":"interact"})," loading ",session.loading_game," pause ",get_tree().paused)
	return check(false,label)

func expected() -> Dictionary:
	var out := {}
	for i in range(1,6): out["BuyHaburuMain#2#%d#0"%i]=1
	return out

func inventory() -> void:
	var independent := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--haburu-source-audit="):
			var report = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--haburu-source-audit=")))
			for row: Dictionary in report.maps: independent[row.name]=row
	check(independent.size()==130,"independent shipped-source inventory is available")
	var declarations := {}; var definitions := {}; var source: ScriptParser
	var files := GameFiles.files(GameData.root.path_join("maps")); files.sort()
	for file: String in files:
		if file.get_extension().to_lower()!="mob": continue
		var mob := EIMob.load_bytes(GameData.read_file("maps/"+file))
		var ast := ScriptParser.parse(mob.script_text)
		check(ast.errors.is_empty(),"current parser accepts shipped "+file)
		check(independent.has(file) and independent[file].script_ascii_sha256==mob.script_text.sha256_text(),"independent decryption agrees "+file)
		for key: String in ast.declares: declarations[key.to_lower()]=true
		for key: String in ast.scripts: definitions[key.to_lower()]=true
		script_rows.append({"map":file,"declarations":ast.declares.size(),"definitions":ast.scripts.size(),"script_sha256":mob.script_text.sha256_text()})
		if file.to_lower()=="bz23k.mob": source=ast
	check(script_rows.size()==130,"all 130 supplied MOB scripts were parsed")
	if not check(source!=null,"Haburu original source is present"): return
	var found := {}
	for statement: Array in source.world:
		if statement[0]==ScriptParser.S_CALL and expected().has(statement[1]):
			found[statement[1]]=int(found.get(statement[1],0))+1
	check(found==expected(),"all five missing calls are unconditional WorldScript statements")
	for name: String in expected():
		check(not declarations.has(name.to_lower()) and not definitions.has(name.to_lower()),"no shipped parent/quest body defines "+name)

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	OS.add_logger(errors)
	_run.call_deferred()

func _run() -> void:
	if not check(GameData.campaign_id==CampaignProfile.ASTRAL and SaveInfo.files().is_empty(),"fresh isolated expansion profile"):
		await finish(); return
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"auto_graphics":0,"autosave":0,"confine_mouse":0,"show_tutorial":0},true)
	TutorialPanel.auto_show=false
	inventory()
	session=Session.new(); add_child(session)
	game=Game.new(); game.session=session; session.game=game; add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0))
	await session.enter_zone("bz23k",0,false)
	if not check(session.zone_id=="bz23k","actual Haburu village loads"): await finish(); return
	if not await until(func():return session.state.get_var(0,"b.Haburu.fq15")==1,"real Start offers Haburu's first topic"):
		await finish(); return
	check(session.world.vm.unknown_calls==expected(),"entry reaches exactly the five missing authored calls")
	entry_unknown_calls=session.world.vm.unknown_calls.duplicate()
	var npc: GameUnit=session.world.vm._by_name("Haburu")
	if not check(npc!=null,"authored Haburu actor exists"): await finish(); return
	var hero := session.world.units.values().filter(func(u:GameUnit):return u.controller==0 and u.has_meta("hero") and not u.get_meta("hero").has("merc"))
	if not check(hero.size()==1,"authored starting hero deployed"): await finish(); return
	print("HABURU_ACTORS ",hero[0].pos," -> ",npc.pos," talk_ready ",npc.village_talk_ready()," topics ",Briefings.pending_for(session.state,npc,0)," dead ",hero[0].dead," target_dead ",npc.dead," mine ",session.my_index," movie ",session.movie_active()," world ",game.world==session.world)
	var route := session.world.nav.find_path(hero[0].pos,npc.pos,[hero[0],npc],[],maxf(0.0,hero[0].body_radius()-NavGrid.R_REF),hero[0].move_class(),true)
	print("HABURU_ROUTE ",route," class ",hero[0].move_class()," radius ",hero[0].body_radius()," start_open ",session.world.nav.cell_open(hero[0].pos,hero[0].move_class())," target_open ",session.world.nav.cell_open(npc.pos,hero[0].move_class()))
	var ignored: Array=[hero[0]]
	for actor: GameUnit in session.world.unit_rows():
		if actor!=hero[0]: ignored.append(actor)
	var static_route := session.world.nav.find_path(hero[0].pos,npc.pos,ignored,[],0.0,hero[0].move_class(),true)
	check(route.is_empty() and static_route.is_empty(),"authored placement has no route even without all live actor stamps")
	check(session.world.nav.cell_open(hero[0].pos,hero[0].move_class()) and session.world.nav.cell_open(npc.pos,hero[0].move_class()),"both authored endpoints are individually walkable")
	placement={"hero":[hero[0].pos.x,hero[0].pos.y], "haburu":[npc.pos.x,npc.pos.y], "ignored_actors":ignored.size(), "ordinary_path_points":route.size(), "static_path_points":static_route.size()}
	game.issue({"t":"interact","target":npc.uid,"units":[hero[0].uid],"unit":hero[0].uid})
	if not await until(func():return not game.hud._dialog._topics.is_empty(),"ordinary interaction opens real topics"):
		await finish(); return
	check(session.save_game("lia_haburu_pending")==OK,"save succeeds while the authored first topic is pending")
	game.hud._dialog._on_topic(-1)
	check(session.load_game("lia_haburu_pending"),"real pending-topic save reloads")
	if not await until(func():return not session.loading_game and session.zone_id=="bz23k","pending-topic world reload finishes"):
		await finish(); return
	check(session.world.vm.briefings._original_village_topics.is_empty(),"topic UI context is not serialized into the loaded world")
	check(session.state.get_var(0,"b.Haburu.fq15")==1,"pending authored conversation survives reload")
	npc=session.world.vm._by_name("Haburu")
	hero=session.world.units.values().filter(func(u:GameUnit):return u.controller==0 and u.has_meta("hero") and not u.get_meta("hero").has("merc"))
	game.issue({"t":"interact","target":npc.uid,"units":[hero[0].uid],"unit":hero[0].uid})
	if not await until(func():return not game.hud._dialog._topics.is_empty(),"normal reloaded interaction reopens real topics"):
		await finish(); return
	var index := -1
	var options: Array=game.hud._dialog._topics.get("options",[])
	for i in options.size():
		if String(options[i].get("var",""))=="b.Haburu.fq15": index=i
	if not check(index>=0,"authored Haburu topic is selectable"): await finish(); return
	game.hud._dialog._on_topic(index)
	if not await until(func():return session.state.get_var(0,"b.Haburu.fq15")==2,"actual topic completes through normal dialogue UI"):
		await finish(); return
	check(session.world.vm.unknown_calls.is_empty(),"resumed world and topic add no unresolved operations")
	check(session.save_game("lia_haburu_audit")==OK,"completed dialogue save succeeds")
	var saved := CampaignState.load_from(SaveInfo.path("lia_haburu_audit"))
	check(saved!=null and saved.get_var(0,"b.Haburu.fq15")==2,"real campaign save preserves conversation completion")
	check(session.load_game("lia_haburu_audit"),"real completed-dialogue save reloads")
	if not await until(func():return not session.loading_game and session.zone_id=="bz23k","completed-topic world reload finishes"):
		await finish(); return
	npc=session.world.vm._by_name("Haburu")
	check(session.state.get_var(0,"b.Haburu.fq15")==2,"loaded world retains completed conversation state")
	check(not Briefings.pending_for(session.state,npc,0).any(func(e:Array):return e[1]=="fq15"),"completed first topic is absent from reloaded choices")
	check(session.world.vm.briefings._original_village_topics.is_empty(),"completed save does not restore a stale topic context")
	await finish()

func _process(_dt: float) -> void:
	if finished or game==null or game.hud==null: return
	frame+=1
	if frame%5!=0: return
	if game.hud._tutorial.visible: game.hud._tutorial.close()
	if game.hud._movie.visible: game.hud._movie.stop()
	if game.hud._dialog.visible and game.hud._dialog._topics.is_empty():
		game.hud._dialog._skip(); game.hud._dialog._next()

func finish() -> void:
	finished=true
	check(errors.messages.is_empty(),"source/dialogue audit has no runtime errors")
	var result := {"checks":checks,"failures":failures,"errors":errors.messages,"scripts":script_rows,
		"entry_unknown_calls":entry_unknown_calls, "placement":placement,
		"unknown_calls":session.world.vm.unknown_calls if session and session.world else {},
		"scope":"Direct bz23k entry, real first Haburu topic, and pending/completed save/reload. No campaign-route, full optional-quest or intended missing-shop behavior claim."}
	if game: game.queue_free()
	if session: session.queue_free()
	await get_tree().process_frame; await get_tree().process_frame
	TexUpscale.shutdown()
	OS.remove_logger(errors)
	FileAccess.open("user://lia-haburu-audit.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("LIA_HABURU_AUDIT ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)

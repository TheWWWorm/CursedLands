extends "story_coop_predicates.gd"
## Requires owned --lia-cd-root, --lia-101-root and --lia-102-root fixtures.
## Compares against the extracted official result, then exercises legacy VMs.
const Saves := preload("res://src/game/script/story_astral_patch_saves.gd")
var roots := {}
class Errors extends Logger:
	var messages: Array[String] = []
	func _log_error(fn: String, file: String, line: int, code: String, why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind != ERROR_TYPE_WARNING:messages.append("%s %s (%s:%d %s)" % [code,why,file,line,fn])
var errors := Errors.new()

func running_body(vm: ProbeVM, name: String) -> ScriptVM.Instance:
	var found := vm.instances.filter(func(i):return i.sname==name and not i.frames.is_empty())
	return found[0] if not found.is_empty() else null

func source_ast(root: String, file: String) -> ScriptParser:
	var mob := EIMob.load_bytes(FileAccess.get_file_as_bytes(root+"/maps/"+file+".mob"))
	return ScriptParser.parse(mob.script_text)

func source_vm(zone: String, file: String, edition := "cd", adapt := true) -> ProbeVM:
	raw[file]=EIMob.load_bytes(FileAccess.get_file_as_bytes(roots[edition]+"/maps/"+file+".mob")).script_text
	var vm := vm_for(zone,file,adapt)
	vm.world_bodies[""]=vm.ast.world
	return vm

func lever(id: int, enabled := false, state := 0) -> Node3D:
	var object := Node3D.new();allocations.append(object)
	object.set_meta("ei",{"nid":id,"position":Vector3.ZERO})
	s.world.objects[id]=object
	s.world.levers[id]={"state":state,"enabled":enabled}
	return object

func minimal_save() -> Dictionary:
	return {"instances":[],"globals":{},"areas":{}}

func payload_parity() -> void:
	for zone: String in AstralPatches.DATA.scripts:
		var row: Dictionary = AstralPatches.DATA.scripts[zone]
		var expected := source_ast(roots["102"],row.map)
		check(expected.errors.is_empty(),row.map+": official script parses")
		for edition: String in roots:
			var ast := source_ast(roots[edition],row.map)
			AstralPatches.apply_script(ast,zone)
			check(AstralPatches.script_fingerprint(ast)==AstralPatches.script_fingerprint(expected),row.map+" "+edition+": exact official 1.02 AST")
			var once := AstralPatches.script_fingerprint(ast)
			AstralPatches.apply_script(ast,zone)
			check(AstralPatches.script_fingerprint(ast)==once,row.map+" "+edition+": idempotent")
			Compat.apply(ast,CampaignProfile.ASTRAL,zone)
			var target := source_ast(roots["102"],row.map)
			Compat.apply(target,CampaignProfile.ASTRAL,zone)
			check(AstralPatches.script_fingerprint(ast)==AstralPatches.script_fingerprint(target),row.map+" "+edition+": remake adaptations agree")
		var custom := source_ast(roots.cd,row.map)
		custom.world.append([ScriptParser.S_CALL,"Nop",[]])
		var authored := AstralPatches.script_fingerprint(custom)
		AstralPatches.apply_script(custom,zone)
		check(AstralPatches.script_fingerprint(custom)==authored and not custom.has_meta(AstralPatches.META),row.map+": edited map is preserved")
		var base := source_ast(roots.cd,row.map)
		Compat.apply(base,CampaignProfile.ORIGINAL,zone)
		check(not base.has_meta(AstralPatches.META),row.map+": base campaign excluded")
	var target_db := EIResArchive.open_path(roots["102"]+"/res/database.res")
	var target_map := FileAccess.get_file_as_bytes(roots["102"]+"/maps/zone25.mob")
	var voices := ""
	var active_root := GameData.root
	for edition: String in roots:
		var archive := EIResArchive.open_path(roots[edition]+"/res/database.res")
		archive.astral_patches=true
		for key: String in AstralPatches.DATA.database:
			check(archive.read(key)==target_db.read_original(key),edition+": complete patched "+key)
		var original := FileAccess.get_file_as_bytes(roots[edition]+"/maps/zone25.mob")
		check(AstralPatches.map_file("maps/zone25.mob",original)==target_map,edition+": exact official map blocker")
		check(original==FileAccess.get_file_as_bytes(roots[edition]+"/maps/zone25.mob"),edition+": source file unchanged")
		GameData.root=roots[edition];EIAcks._loaded=false;EIAcks._sets.clear();EIAcks.prepare()
		var decoded := JSON.stringify(EIAcks._sets,"",true,true)
		if voices.is_empty():voices=decoded
		check(decoded==voices,edition+": runtime voice chance/context/path data agree")
	GameData.root=active_root;EIAcks._loaded=false;EIAcks._sets.clear();EIAcks.prepare()
	var altered := target_db.read_original("items.idb");altered[altered.size()-1]^=1
	check(AstralPatches.database_entry("items.idb",altered)==altered,"edited database entry preserved")
	check(Array(GameData.db.find("materials","tiger hide white").resist).all(func(x):return is_equal_approx(x,2.7)),"startup database uses official snow tiger values")
	check(is_equal_approx(GameData.db.find("armors","hadagan low shirt").absorption2[0],2.0),"startup database uses corrected secondary armor")
	# The wiki also opens LiA from another campaign without GameData.open.
	var campaign := GameData.campaign_id
	var library := GameData.campaign_roots.duplicate()
	var database := GameData.db
	GameData.campaign_id=CampaignProfile.ORIGINAL
	GameData.campaign_roots[CampaignProfile.ASTRAL]=roots.cd
	var source := WikiSource.new()
	var error := source.load_installed(CampaignProfile.ASTRAL)
	check(error.is_empty(),"alternate LiA wiki context loads")
	check(error.is_empty() and source.read(func():return Array(GameData.db.find("materials","tiger hide white").resist).all(func(x):return is_equal_approx(x,2.7))),"alternate wiki uses corrected database too")
	check(GameData.campaign_id==CampaignProfile.ORIGINAL and GameData.db==database,"alternate wiki restores the active campaign database")
	GameData.campaign_id=campaign;GameData.campaign_roots=library

func text_parity() -> void:
	var lang := RemakeText.lang
	var target := EIResArchive.open_path(roots["102"]+"/res/texts.res")
	for edition: String in roots:
		var arc := EIResArchive.open_path(roots[edition]+"/res/texts.res")
		RemakeText.lang="ru"
		for key: String in AstralPatches.DATA.texts:
			var before := EIText.ansi(arc.read_original(key)).replace("\r","")
			var expected := EIText.ansi(target.read_original(key)).replace("\r","")
			check(AstralPatches.text(key,before)==expected,edition+": exact corrected text "+key)
			check(AstralPatches.text(key,"Custom text") == "Custom text",edition+": edited text preserved "+key)
	for language: String in ["en","ru","de"]:
		RemakeText.lang=language;GameData._text_cache.clear()
		var mushrooms := GameData.text("quest q10j")
		check(mushrooms.contains({"en":"river south of Radu","ru":"у реки южнее палатки Рада","de":"Fluss südlich von Radu"}[language]),language+": corrected mushroom directions")
		check(mushrooms.count("#subobj")==4,language+": all journal objectives retained")
		check(GameData.text("unit zone3_human_citizen_f").strip_edges()==RemakeText.t("Poor townswoman"),language+": added citizen name translated")
		check(GameData.text("litem gepard_3").contains({"en":"cheetah","ru":"гепарда","de":"Geparden"}[language]),language+": corrected cheetah name")
		check(GameData.text("string version_name").contains("v1.02"),language+": effective content version")
	RemakeText.lang=lang;GameData._text_cache.clear()

func start_continuation() -> void:
	fixture()
	var old := source_vm("gz13g","zone13","cd",false)
	start(old,"Start")
	var inst := running_body(old,"Start")
	check(inst.block_index==0 and inst.frames[0].i==2,"legacy Start pauses after its Sleep")
	var saved := old.save_state()
	var waiting := inst.wait_until-old.time
	var current := source_vm("gz13g","zone13")
	current._restore(saved)
	var resumed := running_body(current,"Start")
	check(resumed.block_index==1 and resumed.frames[0].body[resumed.frames[0].i][1]=="SetCP","old Start resumes in the relocated original block")
	check(is_equal_approx(resumed.wait_until-current.time,waiting),"remaining sleep duration survives migration")
	check(s.state.get_var(0,"start_zone13")==1,"legacy visit does not repeat first-visit disabling")
	var upgraded := current.save_state()
	check(upgraded.has("lia_patch"),"new VM saves record canonical content revision")
	for edition: String in roots:
		var next := source_vm("gz13g","zone13",edition)
		next._restore(upgraded)
		var again := running_body(next,"Start")
		check(again.block_index==1 and again.frames[0].i==resumed.frames[0].i,"canonical save resumes unchanged on "+edition+" assets")

func paid_recovery() -> void:
	for case: Array in [[2,0,true],[1,0,false],[2,2,false]]:
		fixture();lever(3398867);lever(2139693)
		s.state.set_var(0,"b.shava.fq12",case[0]);s.state.set_var(0,"q.gz16g.fq12",case[1])
		s.state.set_var(0,"zone16_fq12",1)
		var vm := source_vm("gz16g","zone16")
		vm._restore(minimal_save());step(vm,20)
		check(s.world.levers[3398867].enabled==case[2] and s.world.levers[2139693].enabled==case[2],"Double Portion restores only purchased, unfinished quest levers "+str(case))
		check(s.state.items.is_empty() and s.state.quest_items.is_empty(),"lever recovery grants no items")
		var saved := vm.save_state()
		var restored := source_vm("gz16g","zone16")
		restored._restore(saved)
		check(not restored.instances.any(func(i):return i.sname=="VCheck#4#1"),"saving and loading does not repeat consumed lever setup")
	for row: Array in [["gz16g","zone16","b.shava.fq10","zone16_fq10",4955],
		["gz21k","zone21","b.Haburu.fq16","zone21_fq16",2016001],
		["gz23k","zone23","b.Haburu.fq15","zone23_fq15",4216]]:
		fixture();lever(row[4]);s.state.set_var(0,row[2],2);s.state.set_var(0,row[3],1)
		var vm := source_vm(row[0],row[1]);vm._restore(minimal_save());step(vm,20)
		check(s.world.levers[row[4]].enabled,"paid return lever recovered: "+row[0])

func suspended_setups() -> void:
	for row: Array in [["gz16g","zone16","q.gz16g.q22g","VCheck#1#1","VCheck#1#3",4948],
		["gz31j","zone31","q.gz31j.q8j","VCheck#3#1","VCheck#3#3",1008001]]:
		fixture();lever(row[5]);lever(1008002)
		s.state.set_var(0,row[2],1)
		var old := source_vm(row[0],row[1],"cd",false)
		old.areas.clear()
		start(old,row[3])
		check(running_body(old,row[3])!=null,"original setup is suspended: "+row[3])
		var vm := source_vm(row[0],row[1]);vm._restore(old.save_state())
		check(not vm.instances.any(func(i):return i.sname==row[4]),"recovery leaves pending authored watcher to its setup")
		step(vm,25)
		check(s.world.levers[row[5]].enabled,"resumed setup enables official quest lever")
		check(vm.instances.filter(func(i):return i.sname==row[4]).size()==1,"resumed setup starts new watcher exactly once")
		check(s.state.items.is_empty() and s.state.quest_items.is_empty(),"suspended setup does not replay rewards")
	fixture()
	var old := source_vm("bz31j","bz31j","cd",false)
	var world := ScriptVM.Instance.new();world.sname="WorldScript";world.killed=true
	world.frames=[{"body":old.ast.world,"i":old.ast.world.size()}];old.instances.append(world)
	var vm := source_vm("bz31j","bz31j");vm._restore(old.save_state())
	check(not vm.instances.any(func(i):return i.sname=="VCheck#0#9"),"new watcher is still pending in resumed WorldScript")
	step(vm,2)
	check(vm.instances.filter(func(i):return i.sname=="VCheck#0#9").size()==1,"resumed WorldScript inserts watcher once")
	for topic: String in ["b.BSon.brief_314","b.Baron.brief_316"]:
		fixture();old=source_vm("bz31j","bz31j","cd",false)
		var blocks: Array = old.ast.scripts["#OnBriefingComplete"].blocks
		var index := -1
		for i in blocks.size():
			if JSON.stringify(blocks[i].conds).contains(topic):index=i
		check(index>=0,"original briefing handler located: "+topic)
		var event := ScriptVM.Instance.new();event.sname="#OnBriefingComplete";event.killed=true
		event.block_index=index;event.locals={"nPlayer":0.0,"szComplete":topic}
		event.frames=[{"body":blocks[index].body,"i":1}];old.instances.append(event)
		vm=source_vm("bz31j","bz31j");vm._restore(old.save_state());step(vm,2)
		if topic=="b.BSon.brief_314":
			check(s.state.get_var(0,"b.merc2.brief_317")==0,"removed premature-offer handler is not replayed")
		else:
			check(s.state.get_var(0,"b.Stark.brief_319")==1,"shifted briefing block resumes the correct offer")
	fixture();old=source_vm("gz13g","zone13","cd",false)
	old.globals.merge({"LeverL":lever(902,true),"LeverF":lever(903,true)},true)
	vm=source_vm("gz13g","zone13");vm._restore(old.save_state())
	check(not s.world.levers[902].enabled and not s.world.levers[903].enabled,"pre-quest save receives first-visit lever correction")
	fixture();s.state.current_party="Jigran1";s.state.items=["material.Adamantium[4]"]
	s.state.set_var(0,"b.BSon.brief_318",2)
	s.world.mob=EIMob.load_bytes(FileAccess.get_file_as_bytes(roots.cd+"/maps/zone32.mob"))
	s.world.zone={"id":"gz32j","type":"game"}
	var fresh := ScriptVM.create(s.world,s)
	check(s.state.get_var(0,"b.BSon.brief_318")==3 and s.state.items==["material.Adamantium[4]"],"first load of destination preserves completed CD party transfer")
	fresh.briefings=null;fresh.instances.clear();fresh.globals.clear()

func watcher_recovery() -> void:
	fixture()
	var a := lever(901,true,1);var l := lever(902);var f := lever(903)
	s.state.set_var(0,"q.gz13g.q17g",1);s.state.set_var(0,"q.gz13g.q17g.1",2);s.state.set_var(0,"q.gz13g.q17g.2",1)
	var old := source_vm("gz13g","zone13","cd",false)
	old.globals.merge({"LeverA":a,"LeverL":l,"LeverF":f},true)
	var vm := source_vm("gz13g","zone13");vm._restore(old.save_state())
	check(vm.instances.filter(func(i):return i.sname in ["VCheck#0#3","VCheck#0#4","VCheck#0#5","VCheck#0#6"]).size()==4,"all remaining healer quest watchers are restored")
	step(vm,3);check(s.world.levers[902].enabled,"resumed healer quest enables the next lever")
	s.world.levers[902].state=1;step(vm,3)
	check(s.world.levers[903].enabled,"healer quest advances again without leaving the map")
	for row: Array in [["gz14g","zone14","VCheck#0#6"],["gz1d2","zone1dun2","Barell#4"],["bz31j","bz31j","VCheck#0#9"]]:
		fixture();vm=source_vm(row[0],row[1]);vm._restore(minimal_save())
		check(vm.instances.filter(func(i):return i.sname==row[2]).size()==1,"new world watcher recovered once: "+row[2])
		Saves.recover(vm,minimal_save())
		check(vm.instances.filter(func(i):return i.sname==row[2]).size()==1,"recovery is idempotent: "+row[2])
	fixture();s.state.current_party="Jigran1";s.state.items=["material.Adamantium[4]"]
	s.state.set_var(0,"b.BSon.brief_318",2)
	vm=source_vm("gz32j","zone32");vm._restore(minimal_save());step(vm,4)
	check(s.state.get_var(0,"b.BSon.brief_318")==3 and s.state.items==["material.Adamantium[4]"],"completed CD party transfer is not repeated")

func _ready() -> void:
	OS.add_logger(errors)
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--lia-import-pack="):continue
		var importer := PrivateDataImport.new();add_child(importer)
		var result := {"folder":"","error":""}
		importer.completed.connect(func(folder):result.folder=folder)
		importer.failed.connect(func(error):result.error=error)
		await importer.import_file(arg.trim_prefix("--lia-import-pack="))
		check(result.error.is_empty() and not result.folder.is_empty(),"original data pack imports through the normal game importer: "+result.error)
		if result.folder.is_empty():get_tree().quit(1);return
		check(GameData.open(result.folder).is_empty(),"imported CD pack opens with built-in patches")
	for arg: String in OS.get_cmdline_user_args():
		for edition: String in ["cd","101","102"]:
			var prefix := "--lia-"+edition+"-root="
			if arg.begins_with(prefix):roots[edition]=arg.trim_prefix(prefix)
	check(roots.size()==3,"three owned edition fixtures supplied")
	if roots.size()==3:
		payload_parity();text_parity();start_continuation();paid_recovery();watcher_recovery();suspended_setups()
	for vm: ProbeVM in vms:vm.briefings=null;vm.instances.clear();vm.globals.clear()
	vms.clear()
	for node: Node in allocations:
		if node is GameWorld:node.units={};node.looted.clear();node.objects.clear();node.vm=null
	for node: Node in allocations:node.free()
	OS.remove_logger(errors)
	check(errors.messages.is_empty(),"no runtime errors: "+str(errors.messages))
	print("ASTRAL_BUILTIN_PATCHES ",checks," checks ",failures," failures")
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)

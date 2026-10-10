extends Node
## Continue real rescue checkpoints through normal interaction/dialogue commands.
## Chapter entry was prepared in the earlier route; no campaign or actor edits here.
var s: Session
var game: Game
var checks := 0
var failures: Array[String] = []
var evidence := {"trace":[],"commands":[],"dialogue_controls":[],"ticks":0}
var input_path := ""
var completed := false
var advance_dialogue := false

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

func clean(v: Variant) -> Variant:
	if v is GameUnit: return {"uid":v.uid}
	if v is Dictionary:
		var out := {}
		for k in v: out[str(k)] = clean(v[k])
		return out
	if v is Array or v is PackedVector2Array:
		var out := []
		for x in v: out.append(clean(x))
		return out
	if v is Vector2: return [v.x,v.y]
	if v is Vector3: return [v.x,v.y,v.z]
	return v

func snapshot(label: String) -> void:
	var row := {"label":label,"zone":s.zone_id,"party":s.state.current_party,
		"quest":s.state.get_var(0,"q.gz15h.q61h"),"briefing":s.state.get_var(0,"b.Nalo.Kr61"),
		"key":s.have_quest_item(0,"herocagekey00"),"heroes":clean(s.state.heroes),
		"items":clean(s.state.items),"money":s.state.money,"actors":[]}
	if s.world:
		row.active=s.world.vm.briefings.active
		row.unknown_calls=s.world.vm.unknown_calls.duplicate()
		for u: GameUnit in s.world.party_units():
			row.actors.append({"uid":u.uid,"pos":clean(u.pos),"hp":u.hp,"mana":u.mana,"dead":u.dead,"order":clean(u.order),"order_failed":u.order_failed,"blocked":u.blocked,"interact":clean(u.get_meta("interact",[]))})
		if s.zone_id=="bz13h":
			row.camp_cell={"saved":s.world.lever_sys.export_row(42999),"physical_t":s.world.lever_sys.physical_t(42999)}
			var npc: GameUnit=s.world.vm._by_name("Nalo")
			if npc:row.nalo={"pos":clean(npc.pos),"order":clean(npc.order),"ready":npc.village_talk_ready(),"pending":Briefings.pending_for(s.state,npc,0)}
		if s.world.levers.has(338795):
			row.cell={"saved":s.world.lever_sys.export_row(338795),"physical_t":s.world.lever_sys.physical_t(338795)}
	evidence.trace.append(row)
	print("NALO_RELOAD_STATE ",label," zone=",s.zone_id," party=",s.state.current_party," q=",row.quest," b=",row.briefing)

func until(predicate: Callable, label: String, max_ticks := 3000) -> bool:
	for i in max_ticks:
		if predicate.call(): return check(true,label)
		if not errors.messages.is_empty(): break
		if s.world and not s.loading_game:
			s.world.set_process(false); s.world.set_physics_process(false)
			s.world._tick(GameWorld.TICK)
			if s.world and not s.loading_game: s._tick_world_session(GameWorld.TICK)
			evidence.ticks += 1
		if advance_dialogue and game.hud._dialog.visible and game.hud._dialog._topics.is_empty():
			var dialog=game.hud._dialog
			if dialog._mode==DialogPanel.PLAYING or dialog._mode==DialogPanel.LAST:
				evidence.dialogue_controls.append({"id":dialog._id,"phrase":dialog._i,"control":"skip then next"})
				dialog._skip(); dialog._next()
		await get_tree().process_frame
	snapshot("stopped: "+label)
	return check(false,label)

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	OS.add_logger(errors)
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-save="): input_path=arg.trim_prefix("--resume-save=")
		if arg=="--completed": completed=true
	evidence.input=input_path; evidence.completed_reload=completed
	for opt: Array in GameData.OPTIONS:
		if String(opt[0]).begins_with("gfx_"): GameData.options[opt[0]]=0
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"control_mode":1},true)
	TutorialPanel.auto_show=false
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	if not check(DirAccess.copy_absolute(input_path,SaveInfo.path("reload_input"))==OK,"checkpoint copied into private profile"):
		await finish(); return
	s=Session.new(); add_child(s); s.set_physics_process(false)
	game=Game.new(); game.session=s; s.game=game; add_child(game)
	if not check(s.load_game("reload_input"),"fresh process loads checkpoint"):
		await finish(); return
	s.world.set_process(false); s.world.set_physics_process(false); game.rig.set_process(false)
	snapshot("fresh checkpoint")
	check(s.state.get_var(0,"q.gz15h.q61h")==2,"rescue completion survives fresh load")
	check(not s.have_quest_item(0,"herocagekey00"),"consumed cell key stays absent")
	if completed:
		check(s.zone_id=="gz15h" and s.state.current_party=="","full party resumes at authored return map")
		check(s.state.get_var(0,"b.Nalo.Kr61")==2,"completed Nalo conversation stays complete")
		var stored := CampaignState.load_from(input_path)
		for key in ["unit_name","name","str","dex","int","exp","exp_total","level","skills","perks","armors","weapons","quick","spells"]:
			check(s.state.party_member("Hero").get(key)==stored.party_member("Hero").get(key),"restored hero retains "+key)
		check(not s.party_units(0).is_empty() and s.party_units(0).all(func(u: GameUnit):return not u.dead),"restored party is alive")
		await finish(); return
	if s.zone_id=="gz15h":
		check(s.state.current_party=="Pretty","pending return retains Nalo party")
		check(s.world.lever_sys.physical_t(338795)>0.999,"opened cell collision survives reload")
		if not await until(func():return not s.loading_game and s.zone_id=="bz13h" and s.state.current_party=="HeroAlone","saved native return finishes without another door command",400):
			await finish(); return
	if not check(s.zone_id=="bz13h" and s.state.current_party=="HeroAlone","authored camp and temporary hero are active"):
		await finish(); return
	snapshot("authored camp")
	check(s.state.get_var(0,"b.Nalo.Kr61")==1,"Nalo return conversation is offered")
	var main_hero := s.state.party_member("Hero").duplicate(true)
	var solo_hero := s.state.party_member("HeroAlone::Hero").duplicate(true)
	evidence.expected_main=clean(main_hero); evidence.expected_solo=clean(solo_hero)
	var npc: GameUnit=s.world.vm._by_name("Nalo")
	if not check(npc!=null,"original Nalo NPC is present"):
		await finish(); return
	var hero: GameUnit=s.party_units(0)[0]
	evidence.approach={"hero":clean(hero.pos),"npc":clean(npc.pos),"npc_uid":npc.uid,"ready":npc.village_talk_ready()}
	var ignored: Array=[hero]
	for u: GameUnit in s.world.unit_rows():
		if u!=hero:ignored.append(u)
	evidence.static_placement={"hero_open":s.world.nav.cell_open(hero.pos,hero.move_class()),"npc_open":s.world.nav.cell_open(npc.pos,hero.move_class()),"route_without_actors":clean(s.world.nav.find_path(hero.pos,npc.pos,ignored,[],0.0,hero.move_class(),true)),"ignored_actor_count":ignored.size(),"cage":s.world.zone.get("cage",false),"restrict":clean(s.world.zone.get("restrict",Vector3.ZERO)),"door_visual_t":s.world.lever_sys.figure_t(42999),"door_physical_t":s.world.lever_sys.physical_t(42999)}
	var briefing := Briefings.parse(GameData.text("briefing Kr61"))
	evidence.native_briefing={"actors":briefing.actors,"phrase_count":briefing.phrases.size()}
	if "--inspect-only" in OS.get_cmdline_user_args():
		await finish();return
	var cmd := {"t":"interact","target":npc.uid,"units":[hero.uid],"unit":hero.uid}
	evidence.command_context={"allowed":s.command_allowed(cmd),"movie":s.movie_active(),"loading":s.loading_game,"blocked":hero.blocked,"shop":s.shop_available(),"controller":hero.controller,"game_world_matches":game.world==s.world,"pending":Briefings.pending_for(s.state,npc,0),"route":clean(s.world.nav.find_path(hero.pos,npc.pos,[hero,npc],[],0.0,hero.move_class(),true))}
	evidence.commands.append(cmd); game.issue(cmd)
	snapshot("after normal interact command")
	if not await until(func():return not game.hud._dialog._topics.is_empty(),"ordinary approach opens Nalo topics"):
		await finish(); return
	var topic_index := -1
	var options: Array=game.hud._dialog._topics.get("options",[])
	evidence.topics=options.duplicate(true)
	for i in options.size():
		if String(options[i].get("var","")).to_lower()=="b.nalo.kr61": topic_index=i
	if not check(topic_index>=0,"native Kr61 topic is selectable"):
		await finish(); return
	evidence.commands.append({"ui":"select topic","index":topic_index,"var":options[topic_index].var})
	game.hud._dialog._on_topic(topic_index)
	advance_dialogue=true
	if not await until(func():return not s.loading_game and s.zone_id=="gz15h" and s.state.current_party=="","normal dialogue completes full authored party return"):
		await finish(); return
	snapshot("full party restored")
	check(s.state.get_var(0,"b.Nalo.Kr61")==2,"Kr61 completion recorded")
	check(s.state.get_var(0,"q.gz15h.q61h")==2 and not s.have_quest_item(0,"herocagekey00"),"rescue and consumed key survive chapter return")
	var restored := s.state.party_member("Hero")
	for key in ["str","dex","int","exp","exp_total","level","skills","perks","name"]:
		check(restored.get(key)==solo_hero.get(key),"native return copies temporary hero "+key)
	for key in ["unit_name","armors","weapons","quick","spells"]:
		check(restored.get(key)==main_hero.get(key),"native return preserves original hero "+key)
	check(not s.party_units(0).is_empty() and s.party_units(0).all(func(u: GameUnit):return not u.dead),"returned party is alive")
	check(s.save_game("nalo_full_return")==OK,"completed return saves normally")
	evidence.output_save=SaveInfo.path("nalo_full_return")
	await finish()

func finish() -> void:
	if s and s.world: check(s.world.vm.unknown_calls.is_empty(),"final world has no unresolved original calls")
	check(errors.messages.is_empty(),"continuation has no runtime errors")
	evidence.checks=checks; evidence.failures=failures; evidence.errors=errors.messages
	FileAccess.open("user://nalo-reload.json",FileAccess.WRITE).store_string(JSON.stringify(clean(evidence),"\t"))
	if game: game.queue_free()
	if s: s.queue_free()
	for i in 10: await get_tree().process_frame
	TexUpscale.shutdown(); OS.remove_logger(errors)
	print("NALO_RELOAD ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)

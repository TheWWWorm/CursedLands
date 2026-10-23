extends Node
## Shared loaded-map fixtures. Only the named authored quest threads advance;
## travel, enemy combat and walking are accelerated by direct map entry,
## teleportation and kill cheats. Outcomes are never assigned by the fixture.
var s: Session
var game: Game
var checks := 0
var failures: Array[String] = []
var evidence: Array = []

func check(ok: bool, label: String) -> bool:
	checks += 1
	evidence.append({"label":label,"ok":ok})
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)
	return ok

func frames(n := 2) -> void:
	for i in n: await get_tree().process_frame

func boot() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,
		"volume_stream":0,"volume_voice":0,"auto_graphics":0,"autosave":0,
		"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"net_websocket":0,"control_mode":1,"smile_faces":0},true)
	TutorialPanel.auto_show = false
	s = Session.new(); add_child(s); s.set_physics_process(false)
	game = Game.new(); game.session = s; s.game = game; add_child(game)
	s.state.ensure_hero(0,"Human Hero")
	check(GameData.campaign_id == CampaignProfile.ASTRAL,"owned Lost in Astral campaign loaded")

func freeze() -> void:
	s.set_physics_process(false)
	s.world.set_process(false); s.world.set_physics_process(false)
	game.rig.set_process(false); game.hud._tutorial.close()
	s.world.vm.briefings._check = INF

func enter(zone: String) -> void:
	await s.enter_zone(zone,1,false)
	freeze()
	# Finish the map's two-tick global bindings before selecting its quest
	# threads. This retains original named objects, Heroes and lever metadata.
	ticks(8)
	s.world.vm.instances.clear()
	s.world.vm.briefings.active = ""; s.world.vm.briefings._pending_dialog.clear()
	game.hud._dialog.hide()
	check(s.zone_id == zone and hero() != null,"loaded authored map "+zone)

func vm() -> ScriptVM: return s.world.vm
func value(key: String) -> float: return s.state.get_var(0,key)
func hero() -> GameUnit:
	for u: GameUnit in s.party_units(0):
		if not u.get_meta("hero",{}).has("merc"): return u
	return null

func ticks(n := 3) -> void:
	for i in n:
		s.world.time += ScriptVM.POLL
		vm().tick(ScriptVM.POLL)

func start(names: Array) -> void:
	for name: String in names:
		if check(vm().ast.scripts.has(name),s.zone_id+": authored thread "+name):
			vm().spawn(name,[null])
	ticks()

func teleport(point: Vector2, actor: GameUnit = null) -> void:
	var u := actor if actor != null else hero()
	if not check(u != null,"teleport target exists"): return
	u.command({"type":"wait","t":0.0}); u.pos = point; u.resync_drawn()
	ticks()

func kill(ids: Array) -> void:
	for id: int in ids:
		var u: GameUnit = s.world.units.get(id)
		if check(u != null,"authored combat target exists: "+str(id)):
			u.die(hero())
	ticks()

func use(id: int, expect_success := true) -> void:
	var object: Node3D = s.world.objects.get(id)
	if not check(object != null,"authored interactable exists: "+str(id)): return
	var h := hero()
	var p: Vector3 = object.get_meta("ei").position
	h.pos = Vector2(p.x,p.y); h.resync_drawn()
	h.stats.dex = 999.0
	s.apply_command({"t":"use_lever","units":[h.uid],"target":id},0)
	vm()._check_interactions()
	for i in 120:
		h.tick(GameUnit.TICK)
		if h.order.get("type","") != "use" and h.orders.is_empty() and not h.has_meta("interact"): break
	check(int(s.world.levers.get(id,{}).get("state",0)) == int(expect_success),
		("normal use activates " if expect_success else "unavailable use stays blocked ")+str(id))
	ticks(8)

func complete(id: String) -> void:
	var owner := id.get_slice(".",1)
	var npc: GameUnit = vm()._by_name(owner)
	if not check(value(id) == 1,"authored conversation offered: "+id): return
	if vm().briefings.active.to_lower() == id.to_lower():
		pass # An authored SendStringEvent can already be showing this topic.
	elif owner == s.zone_id:
		vm().briefings._check = 0; vm().briefings.tick(); vm().briefings._check = INF
	else:
		if not check(npc != null,"authored conversation actor exists: "+owner): return
		# Authored Start may still have a rotate/stance order queued when the
		# surrounding simulation is frozen. Finish that actor's normal order.
		for i in 240:
			if npc.village_talk_ready(): break
			npc.tick(GameUnit.TICK)
		vm().briefings.interact(hero(),npc,0)
		var options: Array = game.hud._dialog._topics.get("options",[])
		var choice := -1
		for i in options.size():
			if String(options[i].var).to_lower() == id.to_lower(): choice = i
		if not check(choice >= 0,"normal topic list contains "+id): return
		game.hud._dialog._on_topic(choice)
	for i in 900:
		s.world._tick_dialog_movers(GameUnit.TICK)
		vm().briefings.staging_tick()
		for u: GameUnit in s.world.dialog_movers.keys(): u.tick(GameUnit.TICK)
		if vm().briefings._pending_dialog.is_empty(): break
	if not check(vm().briefings.active.to_lower() == id.to_lower() and vm().briefings._pending_dialog.is_empty(),
		"normal topic selection reaches closing controls: "+id): return
	game.hud._dialog._skip(); game.hud._dialog._finish()
	ticks()
	check(value(id) in [2.0,3.0],"normal dialogue close completes "+id)
	var before := accounting()
	s.apply_command({"t":"dialog_done","id":id},0); ticks()
	check(accounting() == before,"duplicate dialogue close grants nothing: "+id)

func accounting() -> Dictionary:
	return {"money":s.state.money,"items":s.state.items.duplicate(),
		"quest_items":s.state.quest_items.duplicate(),"quests":s.state.quests.duplicate(true),
		"experience":s.state.heroes[0][0].get("exp_total",0)}

func roundtrip(slot: String, vars: Array, items: Array = []) -> void:
	var before := accounting()
	var values := vars.map(func(key): return value(key))
	check(s.save_game(slot) == OK,"save checkpoint "+slot)
	check(await s.load_game_shown(slot),"reload checkpoint "+slot)
	freeze()
	check(vars.map(func(key): return value(key)) == values,"saved quest points survive "+slot)
	for item: String in items: check(s.state.quest_items.has(item),"saved quest item survives: "+item)
	ticks(12)
	check(accounting() == before,"reload/poll does not replay rewards: "+slot)

func finish(marker: String, scope: String) -> void:
	var report := {"checks":checks,"failures":failures,"assertions":evidence,"scope":scope}
	FileAccess.open("user://"+marker.to_lower()+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	game.queue_free(); s.queue_free(); await frames(8)
	TexUpscale.shutdown()
	print(marker," ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)

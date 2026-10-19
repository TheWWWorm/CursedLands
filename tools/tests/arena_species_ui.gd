extends "arena_expansion_ui.gd"
var language := "en"

func wait_models() -> void:
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		await frames(1)
		if screen.battle._queued_formation.is_empty() and screen.battle.formation_motion.movers.is_empty() and screen._shop.get_children().all(func(box):return box.get_child(0) is Label or not box.get_child(0)._preview_pending): break
	await frames(16)

func _ready() -> void:
	OS.add_logger(errors); await frames(8)
	GameData._window_gen += 1; GameData.arena_mode=1
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"autosave":0,"net_directory":0,"net_upnp":0},true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): language=arg.trim_prefix("--lang=")
	RemakeText.lang=language
	get_window().mode=Window.MODE_WINDOWED; get_window().size=Vector2i(1280,800)
	get_window().position=Vector2i.ZERO
	get_window().grab_focus(); await frames(6)
	screen=ArenaPveScreen.new(); add_child(screen); await frames(8)
	screen._seed_input.text="7191"; screen._begin(); screen.run.auto_save=false
	screen.run.gold=80; screen.run.training=36; screen.run.army.clear()
	for pair in [[0,0],[0,1],[11,0],[16,0],[23,1],[6,1]]: screen.run._recruit(pair[0],pair[1],9)
	screen.run.arrange(); screen.run._recruit(7,0,2)
	screen.run.reserve_slots(); screen.run.shop.clear()
	for family in [0,0,11,16,21,24]: screen.run.shop.append({"family":family,"rank":0,"locked":false})
	for plan: Dictionary in screen.run.bot_plans: plan.done=true
	screen.run._touch(); await wait_models()
	var first: ArenaCreatureCard=screen._shop.get_child(0).get_child(0)
	check(first.upgrade_ready and screen._shop.get_child(1).get_child(0).upgrade_ready,"both shop copies complete owned boar")
	check(first._ownership.text.contains("★ ×1") and first._ownership.text.contains("★★ ×1"),"compact ownership shows ranks")
	check(not first._upgrade_marker.get_global_rect().intersects(screen._shop.get_child(0).get_child(1).get_global_rect()),"upgrade cue and lock do not overlap")
	for box: Control in screen._shop.get_children():
		var card: ArenaCreatureCard=box.get_child(0)
		bounded(card,"compact species offer")
		check(card.size.y <= 160,"shop reclaims vertical space")
	screen._round_banner._age=10
	await shot("species-"+language+"-planning")
	# The new species data must retain the full-bench merge and swap behaviour.
	var deployed: Dictionary=screen.run.army.filter(func(e):return e.family==11)[0]
	for n in 2:
		screen.run.shop[2]={"family":11,"rank":0,"locked":false}; screen.run._touch()
		screen._shop.get_child(2).get_child(0).pressed.emit(); await frames(8)
	check(screen.run.unit(deployed.uid).rank==1,"three matching woodsfolk merge immediately")
	screen._select(deployed.uid); screen._army_row.get_child(5).pressed.emit(); await frames(8)
	check(not screen.run.unit(deployed.uid).deployed and screen.run.reserve_slots()[5].uid==deployed.uid,"return uses chosen reserve slot")
	var outgoing: Dictionary=screen.run.army.filter(func(e):return e.deployed)[0]
	screen._select(outgoing.uid); screen._army_row.get_child(5).pressed.emit(); await wait_models()
	check(screen.run.unit(deployed.uid).deployed and screen.run.reserve_slots()[5].uid==outgoing.uid,"field and bench swap")
	var rival: ArenaRun=screen.run.company(1)
	rival.army.clear(); rival._recruit(14,1,9); rival._recruit(19,0,4); rival.arrange()
	screen._show_player(1); await frames(30)
	check(screen._damage_panel.rows.size()==2,"scouting shows the watched company")
	for box: Control in screen._shop.get_children():
		check(not screen._scout_bar.get_global_rect().intersects(box.get_child(0)._title.get_global_rect()),"scout title clears shop hover name")
	await shot("species-"+language+"-scout")
	screen._show_player(0); await frames(10)
	for resolution in [Vector2i(1280,720),Vector2i(1280,960),Vector2i(1600,900)]:
		get_window().size=resolution; await frames(8); screen.field.reset_camera()
		var safe:=screen.field.battle_screen_rect().grow(2)
		var board:=screen.battle.bounds()
		for x: float in [board.position.x,board.end.x]:
			for y: float in [board.position.y,board.end.y]:
				for z: float in [0.0,4.5]:
					check(safe.has_point(screen.field.camera.unproject_position(Vector3(x,z,-y))),"battle corners fit at "+str(resolution))
	get_window().size=Vector2i(1280,800); await frames(8)
	screen.field.reset_camera(); screen.set_process(false)
	screen._evolution_notice.clear(); screen._clear_selection()
	# Check the contents, not just the outer panel. A bounded scroll panel can
	# still hide the last rank, which was the German 1280x800 regression.
	for resolution in [Vector2i(1280,720), Vector2i(1280,800)]:
		get_window().size=resolution; await frames(8)
		for family in ArenaRules.ACTIVE_FAMILIES:
			for rank in 3:
				var id:=ArenaRules.prototype(family,rank)
				screen._inspected_unit=null
				screen._inspect(id,{"family":family,"rank":rank,"prototype":id})
				await frames(6)
				var scroll:=screen._inspect_scroll.get_v_scroll_bar()
				var label:="%s %d★ %s %s" % [id,rank+1,language,resolution]
				check(scroll.max_value<=scroll.page+1,"all creature details fit without scrolling: "+label)
				check(screen._inspect_scroll.get_global_rect().grow(1).encloses(screen._inspect_box.get_node("EvolutionPath").get_global_rect()),"last rank is fully visible: "+label)
				check(screen._rail.get_global_rect().end.y<screen._bench_panel.get_global_rect().position.y,"creature details clear reserve controls: "+label)
	var entry: Dictionary=screen.run.army.filter(func(e):return e.family==16)[0]
	screen._inspect(entry.prototype,entry); await frames(10)
	bounded(screen._rail,"localized creature details")
	check(screen._inspect_box.get_node("EvolutionPath").size.y < 80,"same-species inspector ranks stay compact")
	await shot("species-"+language+"-inspector")
	screen._hide_inspector(); screen.set_process(true)
	# Real native bolts, one per surviving enemy, with immediate authoritative
	# health deduction and no duplicate volley on a repeated UI snapshot.
	screen.run.wave=4; screen.run._prepare_round(); screen.run._touch(); await wait_models()
	var survivors := screen.battle.world.unit_rows().filter(func(u):return not u.dead and u.get_meta("arena_placement",{}).get("team",-1)==0)
	var before:=screen._result_volley.launches
	var opponent: int=screen.run.opponent_for(0)
	screen.run.rival_health[opponent-1]-=7; screen.run._touch(); await frames(15)
	check(survivors.size()>0,"survivor volley has actual sources")
	check(screen._result_volley is FlyingHP and screen._result_volley._tex != null,"player loss uses the native combat number renderer and atlas")
	check(not screen._result_volley._popups.is_empty() and not screen._result_volley._popups[0].party,"enemy health loss uses native green combat numbers")
	check(screen._lives.text==str(screen.run.lives),"loss is visible immediately")
	await shot("species-"+language+"-loss")
	await frames(25)
	check(screen._result_volley.launches-before==survivors.size(),"one native fire bolt per survivor")
	screen.run._touch(); await frames(10)
	check(screen._result_volley.launches-before==survivors.size(),"repeated snapshots cannot repeat a volley")
	var health:=screen.run.lives
	await get_tree().create_timer(3.5, true, false, true).timeout
	check(not screen._result_volley.visible and not is_instance_valid(screen._result_volley._fx),"volley releases its particle system")
	check(screen.run.lives==health,"visual effects never apply health damage")
	screen.run.lives -= 9; screen.run._touch(); await frames(6)
	check(screen._lives.text==str(screen.run.lives),"local health loss is immediate")
	check(screen._result_volley._popups.any(func(p):return p.party and p.n==9),"local health loss uses native red combat numbers")
	await shot("species-"+language+"-local-loss")
	screen._result_volley.clear()
	screen.set_process(false)
	screen.run.wave=2; screen.run.stage="prepare"; screen.run.last_result={"wave":1,"winner":0,"income":{"base":5,"interest":2,"victory":1,"streak":0,"total":8}}
	screen._round_banner._key=""; screen._round_banner.update_round(screen.run,0,4,false)
	await shot("species-"+language+"-round")
	check(screen._round_banner.position.y < 240,"notice stays above the battle")
	bounded(screen._round_banner,"visible localized round notice")
	screen.run.stage="result"; screen.run.last_result={"wave":2,"winner":1,"health_lost":7}
	screen._round_banner.update_round(screen.run,0,4,false); await frames(4)
	await shot("species-"+language+"-defeat")
	screen._round_banner.update_round(screen.run,2.1,4,false)
	check(not screen._round_banner.visible,"defeat expires after two seconds")
	if language=="en":
		screen.run.wave=4; screen.run.stage="prepare"; screen.run.last_result.clear()
		screen.run._prepare_round(); screen.run._touch(); await wait_models()
		screen.set_process(true); screen.field.reset_camera()
		var pose:=[screen.field.yaw,screen.field.pitch_offset,screen.field.zoom,screen.field.pan_offset]
		if GameData.arena_speed!=2: screen._speed.pressed.emit()
		screen._fight()
		var deadline:=Time.get_ticks_msec()+45000
		while screen.battle.phase != ArenaMatch.Phase.FIGHT and Time.get_ticks_msec()<deadline: await frames(1)
		check(screen.battle.phase==ArenaMatch.Phase.FIGHT,"native worker starts combat")
		check(screen.battle.speed==2.0 and screen._speed.text==RemakeText.t("2×"),"combat uses the normal double-speed control")
		check(pose==[screen.field.yaw,screen.field.pitch_offset,screen.field.zoom,screen.field.pan_offset],"battle preserves camera")
		await frames(90); await shot("species-"+language+"-combat")
		await frames(180)
	check(errors.messages.is_empty(),"no engine errors: "+str(errors.messages))
	print("ARENA_SPECIES_UI ",language," checks=",checks," failures=",JSON.stringify(failures))
	screen.queue_free(); screen=null; await frames(6)
	get_tree().quit(0 if failures.is_empty() else 1)

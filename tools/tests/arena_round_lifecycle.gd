extends "arena_expansion_ui.gd"
## Actual nine-board ownership, preparation, scouting and 2x pause lifecycle.
func _ready() -> void:
	await frames(24)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"vsync":0,"autosave":0},true)
	GameData.arena_mode=1;GameData.arena_speed=2
	screen=ArenaPveScreen.new();add_child(screen);await frames(6)
	screen._seed_input.text="7319";screen._begin();screen.run.auto_save=false
	await frames(24)
	var boards:=screen._tournament_battles
	check(boards.boards.size()==8,"preparation queue creates every rival")
	for round_index in 3:
		for plan: Dictionary in screen.run.bot_plans: plan.done=true
		if screen.run.army.is_empty(): screen.run._recruit(0,0,1);screen.run.arrange();screen._refresh()
		await frames(12)
		var matches: Array = [screen.battle]+boards.boards.values()
		var terrains:=matches.map(func(b):return b.world.terrain)
		var old:=matches.map(func(b):return weakref(b.world))
		var footprints:=terrains.map(func(t):return t.details.soft_ground._walkers.keys() if t.details and t.details.soft_ground else [])
		for battle: ArenaPveMatch in matches:
			check(battle.world.terrain.game_world()==battle.world,"terrain routes to current combat world")
			check(battle.world.time==0,"preparation has no combat ticks")
		screen._show_player(4)
		check(not screen.battle.world.is_visible_in_tree() and boards.boards[4].world.is_visible_in_tree(),"scouting switches whole courtyard visibility")
		check(terrains.filter(func(t):return t.publish_environment).size()==1 and boards.boards[4].world.terrain.publish_environment,"scouted courtyard owns the shared atmosphere")
		var marks := screen.battle.world.ground_marks
		var actor: GameUnit = screen.battle.world.unit_rows()[0]
		marks.queue_unit(actor); marks._drain_units()
		var step: GroundMarks.StepState = marks._units[actor.get_instance_id()]
		check(step.raw == -1.0 and step.contacts.is_empty(), "hidden boards skip pose sampling and release foot contacts")
		screen._show_player(0)
		marks.queue_unit(actor); marks._drain_units()
		check(step.raw >= 0.0, "scouting resumes current visible pose sampling")
		screen._show_boards()
		check(terrains.filter(func(t):return t.publish_environment).size()==1 and screen.battle.world.terrain.publish_environment,"overview publishes one shared atmosphere")
		marks.queue_unit(actor); marks._drain_units()
		check(step.raw == -1.0 and step.contacts.is_empty(), "overview skips subpixel foot contact work")
		for player in 9:
			var battle: ArenaPveMatch=screen.battle if player==0 else boards.boards[player]
			check(battle.world.is_visible_in_tree(),"overview shows board %d"%player)
			check(battle.world.arena_overview and not battle.world.terrain.details.visible,"overview uses distant pose/detail presentation")
			check(battle.world.global_position==ArenaTournamentBattles.board_offset(player),"actors and scenery share overview placement")
		var fx := ParticleFx.of(screen.battle.world)
		var distant := fx.spawn(0x2000,Vector3(30,30,1),1.0,null,{"secs":10.0})
		var expired := fx.spawn(0x2000,Vector3(31,30,1),1.0,null,{"secs":ParticleFx.TICK})
		fx._tick()
		check(distant != null and distant.e.parts.is_empty(),"overview retains emitters without invisible particles")
		check(not fx.effects.has(expired),"invisible emitters still expire")
		screen._show_player(0)
		check(not screen.battle.world.arena_overview and screen.battle.world.terrain.details.visible,"focused view restores close detail")
		fx._tick()
		check(not distant.e.parts.is_empty(),"scouting resumes live particle emission")
		fx.delete(distant)
		check(boards.request_start(),"round starts after staged preparation")
		var preparation_frames:=0
		var prepared := {}
		while boards.starting and preparation_frames<1500:
			check(matches.all(func(b):return b.world.time==0),"all combat clocks wait for the shared bell")
			for battle: ArenaPveMatch in matches:
				for unit: GameUnit in battle._prepared_enemies.values():
					if prepared.has(unit.get_instance_id()): continue
					prepared[unit.get_instance_id()] = [weakref(unit),battle]
					check(not unit.visible and not unit.can_process() and not battle.world.unit_rows().has(unit),"prepared opponents are hidden and outside combat")
			await frames(1);preparation_frames+=1
		check(not boards.starting and screen.run.stage=="fight","staged preparation completes")
		for entry: Array in prepared.values():
			var unit: GameUnit = entry[0].get_ref()
			check(unit != null and entry[1].world.units.get(unit.uid) == unit,"bell adopts the same prepared model")
		await frames(2)
		check(Engine.time_scale==2.0,"2x battle speed is active")
		await get_tree().create_timer(0.7).timeout
		if boards is ArenaSoloBattles:
			check(boards.boards.values().all(func(b):return b.world.process_mode==Node.PROCESS_MODE_DISABLED),"hidden worker replicas suspend presentation")
			screen._show_player(4); await get_tree().create_timer(.5).timeout
			check(boards.boards[4].world.process_mode==Node.PROCESS_MODE_INHERIT and boards.boards[4].world.time>0,"scouting resumes a current live replica")
			screen._show_boards(); await frames(2)
			check(matches.all(func(b):return b.world.process_mode==Node.PROCESS_MODE_INHERIT),"overview resumes every visible replica")
			screen._show_player(0); await frames(2)
		screen._show_menu();await get_tree().create_timer(0.4).timeout
		var paused_time:=screen.battle.world.time
		await frames(8)
		print("ARENA_PAUSE_SAMPLE ", JSON.stringify({"round":round_index,"before":paused_time,"after":screen.battle.world.time,"phase":screen.battle.phase,"boards_paused":boards.paused,"worker":boards is ArenaSoloBattles,"clock":boards._clock_state if boards is ArenaSoloBattles else []}))
		check(screen.battle.world.time==paused_time,"menu pauses combat at 2x")
		check(screen.battle.phase == ArenaMatch.Phase.PAUSED and screen.battle.world.process_mode == Node.PROCESS_MODE_DISABLED,"worker snapshots preserve the local paused phase and animations")
		check(screen.battle.presentation_root().process_mode==Node.PROCESS_MODE_DISABLED,"menu pauses retained environment")
		# Distinguish a late pre-pause snapshot from a worker that continues
		# simulating. The original prompt-pause assertion remains above.
		await get_tree().create_timer(1.0, true, false, true).timeout
		var settled_time := screen.battle.world.time
		await get_tree().create_timer(1.0, true, false, true).timeout
		print("ARENA_PAUSE_SETTLED ", JSON.stringify({"round":round_index,"before":settled_time,"after":screen.battle.world.time}))
		check(screen.battle.world.time == settled_time, "combat remains stopped after pending worker snapshots settle")
		screen._close_modal();await get_tree().create_timer(0.7).timeout
		check(screen.battle.world.time>paused_time,"closing menu resumes combat")
		for battle: ArenaPveMatch in matches:
			battle.world.process_mode=Node.PROCESS_MODE_DISABLED
			battle.phase=ArenaMatch.Phase.FINISHED;battle.winner=0;battle.finished.emit(0)
			battle.settle_remaining=0
		if boards is ArenaSoloBattles:
			screen.run.resolve(0,screen.battle.world.time,[0,0],[1,0])
			for player in screen.run.alive_players():screen.run.record_board(player,0,[1,0])
		screen._result_remaining=1000
		await frames(3)
		check(screen.run.stage=="result","every board settles before advancing")
		screen.run.advance();await frames(30)
		for index in matches.size():
			check(old[index].get_ref()==null,"old combat world is freed")
			check(matches[index].world.terrain==terrains[index],"courtyard is reused across rounds")
			check(terrains[index].game_world()==matches[index].world,"reused terrain binds new world")
			if terrains[index]._ink:
				check(terrains[index]._ink.get_child(0).marks==matches[index].world.ground_marks,"fallback footprint viewport binds new marks")
			var details: TerrainDetails=terrains[index].details
			if details and details.soft_ground:
				check(not details.soft_ground._walkers.keys().any(func(id):return id in footprints[index]),"new round releases old footprint owners")
	var environment: WeakRef=weakref(screen.battle.presentation_root())
	screen.queue_free();screen=null;await frames(8)
	check(environment.get_ref()==null,"leaving the screen releases retained courtyard")
	check(is_equal_approx(Engine.time_scale,1.0),"leaving restores normal engine speed")
	print("ARENA_ROUND_LIFECYCLE ", JSON.stringify({"checks":checks,"failures":failures}))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)

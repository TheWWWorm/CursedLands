extends Node
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL ",label)
func make_battle() -> ArenaPveMatch:
	var run:=ArenaTournamentBattles.DuelRun.new()
	var league:=ArenaTournamentRun.new();league.auto_save=false;league.begin(7191);league.wave=4
	league.pairings.assign([{"a":0,"b":1,"ghost":false}])
	for company in [league,league.rivals[0]]:
		company.army.clear();company._recruit(5,1,6);company.army[0].deployed=true;company.army[0].point=[29.0,32.0]
	run.league=league;run.player=1;run.run_seed=7191;run.wave=4;run.army=league.rivals[0].army.duplicate(true);run.auto_save=false
	var battle:=ArenaPveMatch.new();battle.run=run;battle.rendered=false;battle.drives_clock=false
	add_child(battle);battle.set_process(false);battle.set_physics_process(false);battle._world_parent=self;battle.prepare();battle.start()
	return battle
func _ready()->void:
	var battle:=make_battle()
	for tick in 2200:
		if battle.phase!=ArenaMatch.Phase.FIGHT:break
		battle.simulate_tick()
	check(battle.phase==ArenaMatch.Phase.FINISHED and battle.world.time<=90.1,"native evolved recruits cannot fight past 90 seconds")
	print("TOAD_DUEL seconds=",battle.world.time," damage=",battle.damage," reason=",battle.end_reason)
	battle.queue_free();await get_tree().process_frame
	battle=make_battle()
	battle.world.time=9.99;battle._process(0)
	check(battle.phase==ArenaMatch.Phase.FIGHT,"no stalemate before ten seconds")
	var unit:GameUnit=battle.world.unit_rows()[0]
	battle._combat_event("damage",unit,unit,0.25)
	battle.world.time=19.9;battle._process(0)
	check(battle.phase==ArenaMatch.Phase.FIGHT,"fractional positive damage resets stalemate clock")
	battle._combat_event("damage",unit,unit,0)
	battle.world.time=20.0;battle._process(0)
	check(battle.winner==-1 and battle.end_reason=="stalemate","zero-damage hits cannot postpone draw")
	battle.queue_free();await get_tree().process_frame
	battle=make_battle();battle.world.time=89.9;battle.last_damage_at=89.9;battle._process(0)
	check(battle.phase==ArenaMatch.Phase.FIGHT,"active combat lasts up to 90 seconds")
	battle.world.time=90.0;battle._process(0)
	check(battle.phase==ArenaMatch.Phase.FINISHED and battle.end_reason=="timeout","hard 90-second limit")
	var run:=ArenaTournamentRun.new();run.auto_save=false;run.begin(7191);run.live_boards=true;run.wave=4;run._prepare_round();run.finish_preparation();run.preparation_left=0;run.start_battle(true)
	var opponent:=run.opponent_for(0)
	run.resolve(-1,10,[0,0],[9,9])
	for player in range(1,9):run.record_board(player,0,[9,0])
	check(run.lives==90 and run.health(opponent)==90,"draw costs both paired owners ten health even if mirrored board differs")
	check(run.last_result.income.victory==0 and run.last_result.health_lost==10,"draw income and health shown correctly")
	var hp:=run.lives;run.record_board(0,-1,[9,9]);check(run.lives==hp,"draw settles once")
	print("ARENA_BATTLE_LIMITS ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

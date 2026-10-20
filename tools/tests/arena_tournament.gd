extends Node
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func fresh(seed_value := 7191) -> ArenaTournamentRun:
	var run := ArenaTournamentRun.new(); run.auto_save = false; run.begin(seed_value); run.finish_preparation()
	return run
func synthetic_round(run: ArenaTournamentRun) -> void:
	run.stage="fight"
	run.resolve(0,10,[20,10],[3,3])
	for index in run.pairings.size():
		if run.pairings[index].a != 0: run.record_duel(index,0,[3,0])
func _ready() -> void:
	var run := fresh();var other := fresh()
	check(run.snapshot()==other.snapshot(),"seed fixes all nine companies and pairings")
	check(run.rivals.size()==8 and run.lives==100 and run.alive_players().size()==9,"human plus eight CPUs start at 100 health")
	check(run.rivals.all(func(bot):return bot.deployed_count()>0 and bot.gold<10),"CPUs buy their own opening armies")
	check(run.save_path()!=ArenaRun.SAVE_PATH,"modes use separate saves")
	for index in 3:
		check(run.is_creep_round() and run.pairings.size()==9,"first three rounds use creeps")
		var saved:=JSON.parse_string(JSON.stringify(run.snapshot())) as Dictionary
		check(other.restore(saved) and JSON.parse_string(JSON.stringify(other.snapshot()))==saved,"preparation roundtrip")
		synthetic_round(run)
		check(run.stage=="result" and run.lives==100,"creep victory leaves health intact")
		var income:=run.gold
		run.record_duel(0,1,[0,9]);run.resolve(1,10,[0,20])
		check(run.gold==income and run.lives==100,"settlement is idempotent")
		check(other.restore(JSON.parse_string(JSON.stringify(run.snapshot()))),"result roundtrip")
		run.advance()
	check(run.wave==4 and not run.is_creep_round() and run.pairings.size()==5,"round four pairs all nine companies")
	check(not run.enemy_army().is_empty(),"opponent has a persistent purchased army")
	for placement in run.enemy_formation():check(placement.point.x>32 and not placement.has("run_uid"),"enemy formation mirrors without own-unit ID collisions")
	var hp_before:=run.health(int(run.pairings[0].b))
	synthetic_round(run);check(run.health(int(run.pairings[0].b))<hp_before,"human victory damages paired CPU")
	run.advance();check(run.is_creep_round(),"round five is creeps")
	synthetic_round(run);run.advance();var previous:=run.previous_opponent
	synthetic_round(run);run.advance();check(run.previous_opponent!=previous,"no immediate rival repeat with alternatives")
	run=fresh();run.wave=6;run._roll_shop(false);run._choose_pairings()
	check(run.pairings.size()==5 and run.pairings.filter(func(p):return p.ghost).size()==1,"odd population assigns one copied army")
	var ghost:Dictionary=run.pairings.filter(func(p):return p.ghost)[0]
	ghost.b=0
	check(other.restore(JSON.parse_string(JSON.stringify(run.snapshot()))),"odd round with a human army copy survives save/reload")
	var donor:=int(ghost.b)
	run.stage="fight";run.resolve(0,1,[1,0],[3,0])
	for index in run.pairings.size():
		var pair:Dictionary=run.pairings[index]
		if pair.a==0:continue
		run.record_duel(index,0 if int(pair.a)==donor or pair.ghost else 1 if int(pair.b)==donor else 0,[3,3])
	check(run.health(donor)==100,"copy loss cannot damage donor")
	run=fresh();run.stage="fight";var combat_save:=run.snapshot()
	check(other.restore(JSON.parse_string(JSON.stringify(combat_save))) and other.stage=="prepare" and JSON.parse_string(JSON.stringify(other.pairings))==JSON.parse_string(JSON.stringify(combat_save.pairings)) and other.lives==100,"interrupted fight restores same opponents without partial results")
	var valid:=other.snapshot()
	var old:=valid.duplicate(true)
	old.rivals.append(old.rivals[0].duplicate(true));old.rival_health.append(100);old.placements.append(0)
	old.bot_plans.append(old.bot_plans[0].duplicate(true));old.pairings.append({"a":9,"b":-1,"ghost":false})
	check(other.restore(old) and other.rivals.size()==8 and other.lives==100 and other.army==run.army and other.gold==run.gold,"ten-seat preview migrates without losing the human company")
	valid=other.snapshot()
	for field in ["rivals","rival_health","placements","pairings"]:
		var broken:=valid.duplicate(true);broken[field]=[]
		check(not other.restore(broken) and other.snapshot()==valid,"atomic rejection: "+field)
	var bad:=valid.duplicate(true);bad.rival_health[0]=-1
	check(not other.restore(bad) and other.snapshot()==valid,"negative health rejected")
	for victory in [true,false]:
		run=fresh();run.wave=11;run._roll_shop(false)
		for i in 8:run.rival_health[i]=0;run.placements[i+1]=i+2
		run.rival_health[0]=1;run.placements[1]=0;run.lives=1;run._choose_pairings()
		run.stage="fight";run.resolve(0 if victory else 1,10,[10,10],[3,3])
		check(run.stage==("won" if victory else "lost") and run.placements[0]==(1 if victory else 2),"last pair settles final rank")
		check(other.restore(JSON.parse_string(JSON.stringify(run.snapshot()))),"terminal game reloads")
	run=fresh(7192)
	for turn in 46:
		run.rival_health.fill(100); run.lives=100
		synthetic_round(run)
		check(other.restore(JSON.parse_string(JSON.stringify(run.snapshot()))),"long-running company saves at round %d"%run.wave)
		if turn<45: run.advance()
	check(run.rivals.all(func(bot):return bot.history.size()<=36),"long-game company history stays bounded")
	run=fresh(7193)
	var battle:=ArenaPveMatch.new();battle.run=run;battle.rendered=false;battle.drives_clock=false
	add_child(battle);battle._world_parent=self;battle.set_process(false);battle.set_physics_process(false)
	var stage:=Node3D.new();add_child(stage)
	var boards:=ArenaTournamentBattles.new();boards.run=run;boards.home=battle;boards.parent_stage=stage;boards.rendered=false;run.live_boards=true;add_child(boards);boards.set_process(false)
	var fights:=0
	for round_index in 100:
		ArenaTournamentRun.shop_for(run,1,run.wave,run.lives)
		battle.prepare();boards.synchronize();check(battle.start(),"native human match starts")
		boards._process(0)
		var ticks:=0
		while run.stage=="fight" and ticks<12000:
			if battle.phase==ArenaMatch.Phase.FIGHT:battle.simulate_tick()
			boards.step();ticks+=1
		check(run.stage in ["result","won","lost"] and run.board_results.size()==run.alive_players().size()+run.board_results.keys().filter(func(player):return run.health(player)<=0).size(),"all native boards settle together")
		check(other.restore(JSON.parse_string(JSON.stringify(run.snapshot()))),"native round result saves")
		fights+=run.board_results.size()
		print("NATIVE_ROUND ",run.wave," health=",run.lives," players=",run.alive_players().size()," stage=",run.stage)
		if run.stage!="result":break
		run.advance();await get_tree().process_frame
	check(fights>=35,"native creep and player rounds exercised")
	check(run.stage in ["won","lost"] and run.placements[0]>0,"full native game ends with a placement")
	check(is_equal_approx(Engine.time_scale,1.0),"background fights do not alter global speed")
	print("ARENA_TOURNAMENT ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

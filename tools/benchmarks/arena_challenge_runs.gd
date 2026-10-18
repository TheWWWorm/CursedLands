extends Node
## The same spending personalities against the expedition's authored waves.
var rows := []
func _ready() -> void:
	var native := hash(GameData.db.tables)
	var bounded_recovery := "--creep-recovery-budget" in OS.get_cmdline_user_args()
	var seeds := [7319,8316]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="): seeds=Array(arg.get_slice("=",1).split(",")).map(func(s):return int(s))
	for strategy in 4:
		for seed_value: int in seeds:
			var run := ArenaRun.new(); run.auto_save=false; run.begin(seed_value)
			var battle := ArenaPveMatch.new(); battle.run=run; battle.rendered=false; battle.drives_clock=false
			add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent=self
			var trace := []
			while run.stage not in ["won","lost"]:
				if run.stage=="result": run.advance(); continue
				if run.stage=="reward":
					var choice := 0
					for index in run.rewards.size():
						if run.rewards[index].kind=="life" and run.lives<3: choice=index
					run.choose_reward(choice); continue
				var plan := {"actions":0,"rerolls":0,"done":false}
				while not plan.done: ArenaBotPlanner.step(run,strategy+1,run.wave,run.lives*30,plan)
				battle.prepare(); battle.start()
				if bounded_recovery:
					for unit: GameUnit in battle.world.unit_rows():
						if unit.faction==2: unit.stats.health_regen=minf(float(unit.race.get("health_regen",0.0)),0.02)*0.25
				for tick in 1700:
					if battle.phase!=ArenaMatch.Phase.FIGHT: break
					battle.simulate_tick()
				if battle.phase!=ArenaMatch.Phase.FINISHED:
					push_error("Expedition fixture did not settle"); get_tree().quit(1); return
				trace.append({"wave":run.wave,"winner":battle.winner,"time":battle.world.time,"stars":run.army.filter(func(e):return e.deployed).map(func(e):return e.rank),"families":run.army.filter(func(e):return e.deployed).map(func(e):return e.family),"gold":run.gold,"capacity":run.capacity()})
				await get_tree().process_frame
			var row := {"seed":seed_value,"strategy":strategy,"outcome":run.stage,"wave":run.wave,"trace":trace,"bounded_creep_recovery":bounded_recovery}
			rows.append(row); print("CHALLENGE_RUN ",strategy," seed=",seed_value," ",run.stage," wave=",run.wave)
			FileAccess.open("user://arena-challenge-runs.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
			battle.queue_free(); await get_tree().process_frame
	get_tree().quit(0 if hash(GameData.db.tables)==native else 1)

extends Node
## Seeded policies use real native AI, spell/projectile simulation and economy.
## Comparisons are design samples, not estimates of player win rates.
var run: ArenaRun
var battle: ArenaPveMatch
var policy := "balanced"
var count := 3
var first := 1900
var challenge := 0
var armor_formula := 1
var results := []
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-policy="): policy=arg.get_slice("=",1)
		if arg.begins_with("--arena-seeds="): count=int(arg.get_slice("=",1))
		if arg.begins_with("--arena-seed-start="): first=int(arg.get_slice("=",1))
		if arg.begins_with("--arena-challenge="): challenge=clampi(int(arg.get_slice("=",1)),0,2)
		if arg.begins_with("--arena-armor-formula="): armor_formula=clampi(int(arg.get_slice("=",1)),0,1)
	var native := hash(GameData.db.tables)
	run=ArenaRun.new();run.auto_save=false
	battle=ArenaPveMatch.new();battle.rendered=false;battle.run=run
	add_child(battle);battle.set_process(false);battle._world_parent=self
	battle.mod_config.rules.armor_formula = armor_formula
	for offset in count:
		run.begin(first+offset,0,challenge)
		var trace:=[]
		while run.stage not in ["won","lost"]:
			if run.stage=="result": run.advance();continue
			if run.stage=="reward":
				var choice:=0
				for i in run.rewards.size():
					if run.rewards[i].kind=="life" and run.lives<3: choice=i
				run.choose_reward(choice);continue
			shop_turn()
			battle.prepare()
			var row:={"wave":run.wave,"gold":run.gold,"level":run.capacity(),"xp":run.experience(),"lives":run.lives,"army":run.army.filter(func(u):return u.deployed).duplicate(true),"alliances":run.alliances()}
			if not battle.start(): printerr("cannot start");get_tree().quit(1);return
			for tick in 5500:
				if battle.phase!=ArenaMatch.Phase.FIGHT:break
				battle.simulate_tick()
			if run.stage=="fight":printerr("unfinished simulation");get_tree().quit(1);return
			row.merge(run.last_result,true)
			row["timed_out"] = battle.winner == -1 and battle.world.time >= battle.time_limit()
			if battle.winner == -1:
				row["survivors"] = []
				for unit: GameUnit in battle.world.unit_rows():
					if unit.dead: continue
					row.survivors.append({"id": unit.info.prototype, "team": unit.faction, "hp": unit.hp,
						"mana": unit.mana, "pos": [unit.pos.x, unit.pos.y], "action": unit.action,
						"target": unit.target.info.prototype if is_instance_valid(unit.target) else "",
						"stats": unit.stats.duplicate(true)})
			trace.append(row)
			await get_tree().process_frame
		results.append({"seed":run.run_seed,"outcome":run.stage,"wave":run.wave,"trace":trace})
		print("ALLIANCE_RUN ",policy," seed=",run.run_seed," ",run.stage," wave=",run.wave," level=",run.capacity())
		var f:=FileAccess.open("user://alliance-runs-%s.json"%policy,FileAccess.WRITE)
		f.store_string(JSON.stringify({"policy":policy,"challenge":challenge,"armor_formula":armor_formula,"time_limit":battle.time_limit(),"results":results},"\t"))
		f.close()
	get_tree().quit(0 if hash(GameData.db.tables)==native else 1)

func strength(entry: Dictionary) -> float:
	var p:=GameData.db.find("monster_prototypes",entry.prototype)
	return float(p.get("base_level",0))*2 + int(entry.rank)*0.5 + (5.0 if ArenaRules.is_elite(int(entry.get("family",-1)),int(entry.rank)) else 0.0)

func shop_turn() -> void:
	run.arrange()
	var desired := 4 if run.wave < 5 else 5 if run.wave < 9 else 6 if run.wave < 13 else 7 if run.wave < 18 else 8 if run.wave < 24 else 9
	if policy=="reroll": desired=maxi(3,desired-1)
	if policy=="levels": desired=mini(9,desired+1)
	var bank := 10 if run.wave>=3 and run.wave<8 else 20 if run.wave>=8 and run.wave<14 else 30 if run.wave>=14 else 0
	if run.lives<3 or run.wave>=26:bank=0
	# Do not starve the opening company in order to pre-level.
	if run.army.size()>=3:
		while run.capacity()<desired and run.gold>=5+maxi(4,bank):
			if not run.train().is_empty():break
	var rolls:=0
	for step in 50:
		if run.bench_count()>=run.bench_limit():
			var reserves:=run.army.filter(func(u):return not u.deployed)
			reserves.sort_custom(func(a,b):return strength(a)<strength(b))
			if not reserves.is_empty():run.sell(reserves[0].uid)
		var selected:=-1;var best:=-INF
		var deployed:=run.army.filter(func(u):return u.deployed)
		var weakest:=0.0 if deployed.is_empty() else 99.0
		for u in deployed:weakest=minf(weakest,strength(u))
		for i in run.shop.size():
			var offer:Dictionary=run.shop[i]
			var family:=int(offer.family)
			if family<0 or not run.purchase_error(i).is_empty():continue
			if run.gold-run.offer_cost(offer)<bank and run.deployed_count()>=run.capacity():continue
			var n:=run.army.filter(func(u):return int(u.family)==family and int(u.rank)==0).size()
			var same:=run.army.any(func(u):return int(u.family)==family)
			var veterans:=run.army.filter(func(u):return int(u.family)==family and int(u.rank)==1).size()
			var p:=ArenaRules.prototype(family,0)
			var power:=strength({"prototype":p,"rank":0})
			var score:=power-weakest + n*4 + veterans*3
			if run.army.size()<run.capacity():score+=30
			if not same: score+=2
			if policy in ["beast","warrior","mage"]:
				score+=5 if family in ArenaAlliances.RULES[policy].families else -3
			if n+1>=ArenaRules.evolution_copies(family,0):score+=6
			if policy=="reroll":score+=n*5
			if score>best:best=score;selected=i
		if selected>=0 and best>=0:
			run.buy(selected);run.arrange()
		elif run.gold>=bank+4 and rolls<(4 if policy=="reroll" else 2):
			run.refresh();rolls+=1
		else:break
	run.arrange()

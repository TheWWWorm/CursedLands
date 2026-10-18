extends Node
## Paired native fights: every adjacent star promotion and equal purchase-price
## competitors. Includes all attacks, spells, target AI, terrain and alliances.
const Duel = preload("arena_roster_matchups.gd").Duel
var rows := []
func duel(a_family: int, a_rank: int, b_family: int, b_rank: int, copies: int, seed_value: int, side: int) -> Dictionary:
	var run := Duel.new(); run.auto_save=false; run.begin(seed_value)
	var other := ArenaRun.new(); other.auto_save=false; other.begin(seed_value)
	run.army.clear(); other.army.clear()
	for team in 2:
		var company: ArenaRun=run if team==0 else other
		for index in (1 if team==side else copies):
			company._recruit(a_family if team==side else b_family,a_rank if team==side else b_rank,1)
			company.army.back().deployed=true
			company.army.back().point=[27.0,32.0+(index-(copies-1)*0.5)*3.0 if team!=side else 32.0]
	run.opposing=other.army
	var battle := ArenaPveMatch.new(); battle.run=run; battle.rendered=false; battle.drives_clock=false
	add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent=self
	battle.prepare(); battle.start()
	for tick in 1700:
		if battle.phase!=ArenaMatch.Phase.FIGHT: break
		battle.simulate_tick()
	var result := {"win":int(battle.winner==side),"draw":int(battle.winner<0),"seconds":battle.world.time,"reason":battle.end_reason}
	battle.queue_free(); await get_tree().process_frame
	return result
func _ready() -> void:
	var native := hash(GameData.db.tables)
	var pairs := []
	for family in ArenaRules.ACTIVE_FAMILIES:
		for rank in [1,2]: pairs.append(["promotion",family,rank,family,rank-1,1])
	for cheap in ArenaRules.ACTIVE_FAMILIES:
		if ArenaRules.FAMILIES[cheap].cost!=1:continue
		for rival in ArenaRules.ACTIVE_FAMILIES:
			if ArenaRules.FAMILIES[rival].cost==3:pairs.append(["three_gold",cheap,1,rival,0,1])
			if ArenaRules.FAMILIES[rival].cost==5:pairs.append(["nine_vs_ten_gold",cheap,2,rival,0,2])
	for pair: Array in pairs:
		var row := {"kind":pair[0],"family":pair[1],"rank":pair[2],"opponent":pair[3],"opponent_rank":pair[4],"copies":pair[5],"wins":0,"draws":0,"trials":4,"timeouts":0,"seconds":0.0}
		for seed_value in [8519,10777]:
			for side in 2:
				var result: Dictionary=await duel(pair[1],pair[2],pair[3],pair[4],pair[5],seed_value,side)
				row.wins+=result.win;row.draws+=result.draw;row.seconds+=result.seconds/4.0
				row.timeouts+=int(result.reason=="timeout")
		rows.append(row); print("STAR_BALANCE ",JSON.stringify(row))
		FileAccess.open("user://arena-star-balance.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	get_tree().quit(0 if hash(GameData.db.tables)==native else 1)

extends Node
## Controlled replacements in mixed companies, with native armor, spells,
## movement, accuracy, regeneration and alliances. Each unordered same-price
## pair gets two seeds and both sides. Supports never duplicate either recruit.
const Duel = preload("arena_roster_teams.gd").Duel
const CONTEXTS := {
	"physical": [9, 4, 1, 12, 11, 7],
	"fire": [0, 3, 16, 15, 18, 5],
	"lightning": [14, 19, 20, 22, 26, 6],
}
var rows := []

func company(family: int, rank: int, supports: Array, seed_value: int) -> ArenaRun:
	var run := ArenaRun.new(); run.auto_save=false; run.begin(seed_value); run.army.clear()
	var front := 0; var back := 0
	for f: int in [family] + supports:
		var entry := run._recruit(f, rank if f==family else 1, 1)
		var melee := ArenaRules.recruit_role(f,int(entry.rank))=="Melee"
		var index := front if melee else back
		entry.deployed=true
		entry.point=[27.0 if melee else 23.0,32.0+[0.0,-5.0,5.0,-9.0][index]]
		if melee: front+=1
		else: back+=1
	return run

func fight(a: int, b: int, rank: int, supports: Array, seed_value: int, side: int) -> Dictionary:
	var run := Duel.new(); run.auto_save=false; run.begin(seed_value)
	var one := company(a,rank,supports,seed_value)
	var two := company(b,rank,supports,seed_value)
	run.army=one.army if side==0 else two.army
	run.opposing=two.army if side==0 else one.army
	var battle := ArenaPveMatch.new(); battle.run=run; battle.rendered=false; battle.drives_clock=false
	add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent=self
	battle.prepare(); battle.start()
	for tick in 1700:
		if battle.phase!=ArenaMatch.Phase.FIGHT: break
		battle.simulate_tick()
	var result := {"win":int(battle.winner==side),"draw":int(battle.winner<0),"seconds":battle.world.time,
		"timeout":int(battle.end_reason=="timeout")}
	assert(battle.phase==ArenaMatch.Phase.FINISHED)
	battle.queue_free(); await get_tree().process_frame
	return result

func _ready() -> void:
	var native := hash(GameData.db.tables)
	var tiers := [1,2,3,4,5]
	var families := []
	var ranks := [1,2]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tiers="): tiers=Array(arg.get_slice("=",1).split(",")).map(func(s):return int(s))
		if arg.begins_with("--families="): families=Array(arg.get_slice("=",1).split(",")).map(func(s):return int(s))
		if arg.begins_with("--ranks="): ranks=Array(arg.get_slice("=",1).split(",")).map(func(s):return int(s))
	assert(ranks.all(func(rank): return rank in [0,1,2]))
	for a in ArenaRules.ACTIVE_FAMILIES:
		var tier: int=ArenaRules.FAMILIES[a].tier
		if tier not in tiers: continue
		for b in ArenaRules.ACTIVE_FAMILIES:
			if b<=a or ArenaRules.FAMILIES[b].tier!=tier: continue
			if not families.is_empty() and a not in families and b not in families: continue
			for context: String in CONTEXTS:
				var supports: Array=CONTEXTS[context].filter(func(f):return f!=a and f!=b).slice(0,3)
				for rank in ranks:
					var row := {"a":a,"b":b,"tier":tier,"rank":rank,"context":context,"supports":supports,
						"wins":0,"draws":0,"trials":4,"timeouts":0,"seconds":0.0}
					for seed_value in [16729,23173]:
						for side in 2:
							var result := await fight(a,b,rank,supports,seed_value,side)
							row.wins+=result.win; row.draws+=result.draw
							row.timeouts+=result.timeout; row.seconds+=result.seconds/4.0
					rows.append(row)
				print("CONTEXT_PAIR ",a," ",b," ",context," rows=",rows.size())
				FileAccess.open("user://arena-balance-contexts.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	assert(hash(GameData.db.tables)==native)
	print("BALANCE_CONTEXTS rows=",rows.size()," fights=",rows.size()*4)
	get_tree().quit()

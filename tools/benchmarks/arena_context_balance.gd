extends Node
## Equal-price, mirrored native fights. A duel measures independence; a line
## measures value alongside allies. Neither is a stand-in for tournament play.
const Duel = preload("arena_roster_matchups.gd").Duel
var rows := []
var rank := 1
var tier := 0
var seeds := [8519]
var contexts := ["duel", "line"]
var families := []

func supports(a: int, b: int) -> Array:
	var candidates := ArenaRules.ACTIVE_FAMILIES.filter(func(f):
		return f!=a and f!=b and ArenaRules.recruit_role(f,rank)=="Melee")
	var price: int=ArenaRules.FAMILIES[a].cost
	candidates.sort_custom(func(x,y):
		var dx: int=absi(int(ArenaRules.FAMILIES[x].cost)-price)
		var dy: int=absi(int(ArenaRules.FAMILIES[y].cost)-price)
		return dx<dy if dx!=dy else x<y)
	return candidates.slice(0,2)

func army(company: ArenaRun, family: int, allies: Array) -> void:
	company.army.clear()
	var candidate := company._recruit(family,rank,1)
	candidate.deployed=true
	candidate.point=[27.0 if allies.is_empty() or ArenaRules.recruit_role(family,rank)=="Melee" else 22.0,32.0]
	for index in allies.size():
		var entry := company._recruit(allies[index],rank,1)
		entry.deployed=true; entry.point=[27.0,29.0+index*6.0]

func fight(a: int, b: int, allies: Array, seed_value: int, side: int) -> Dictionary:
	var run := Duel.new(); run.auto_save=false; run.begin(seed_value)
	var rival := ArenaRun.new(); rival.auto_save=false; rival.begin(seed_value)
	army(run,a if side==0 else b,allies)
	army(rival,b if side==0 else a,allies)
	run.opposing=rival.army
	var battle := ArenaPveMatch.new(); battle.run=run; battle.rendered=false; battle.drives_clock=false
	add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent=self
	battle.prepare(); battle.start()
	for tick in 1700:
		if battle.phase!=ArenaMatch.Phase.FIGHT: break
		battle.simulate_tick()
	assert(battle.phase==ArenaMatch.Phase.FINISHED,"native fixture must settle")
	var result := {"seed":seed_value,"side":side,"winner":-1 if battle.winner<0 else a if battle.winner==side else b,
		"time":battle.world.time,"reason":battle.end_reason,"damage":battle.damage.duplicate(),"survivors":[]}
	for unit: GameUnit in battle.world.unit_rows():
		if not unit.dead: result.survivors.append({"id":unit.info.prototype,"team":unit.faction,"hp":unit.hp,"max_hp":unit.max_hp})
	battle.queue_free(); await get_tree().process_frame
	return result

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rank="): rank=int(arg.get_slice("=",1))
		elif arg.begins_with("--tier="): tier=int(arg.get_slice("=",1))
		elif arg.begins_with("--contexts="): contexts=Array(arg.get_slice("=",1).split(","))
		elif arg.begins_with("--seeds="): seeds=Array(arg.get_slice("=",1).split(",")).map(func(s):return int(s))
		elif arg.begins_with("--families="): families=Array(arg.get_slice("=",1).split(",")).map(func(s):return int(s))
	var native := hash(GameData.db.tables)
	for a in ArenaRules.ACTIVE_FAMILIES:
		if tier>0 and ArenaRules.FAMILIES[a].tier!=tier: continue
		for b in ArenaRules.ACTIVE_FAMILIES:
			if b<=a or ArenaRules.FAMILIES[a].cost!=ArenaRules.FAMILIES[b].cost: continue
			if not families.is_empty() and a not in families and b not in families: continue
			for context: String in contexts:
				var allies := supports(a,b) if context=="line" else []
				var row := {"a":a,"b":b,"rank":rank,"cost":ArenaRules.FAMILIES[a].cost,"context":context,"supports":allies,"trials":[]}
				for seed_value: int in seeds:
					for side in 2: row.trials.append(await fight(a,b,allies,seed_value,side))
				rows.append(row)
				FileAccess.open("user://arena-context-balance.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
				print("CONTEXT_BALANCE ",a," ",b," ",context," winners=",row.trials.map(func(t):return t.winner)," seconds=",row.trials.map(func(t):return snappedf(t.time,.01)))
	var unchanged := hash(GameData.db.tables)==native
	print("CONTEXT_COMPLETE rows=",rows.size()," trials=",rows.size()*seeds.size()*2," native_unchanged=",unchanged)
	get_tree().quit(0 if unchanged and not rows.is_empty() else 1)

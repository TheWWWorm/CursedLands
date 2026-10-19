extends "arena_star_balance.gd"
## Compare a final form with three two-star peers at the same purchase cost.
## Native combat includes typed armor, mitigation caps, spells and alliances.
func _ready() -> void:
	var native := hash(GameData.db.tables)
	for candidate in [0,9,18]:
		for opponent in ArenaRules.ACTIVE_FAMILIES:
			if ArenaRules.FAMILIES[candidate].cost!=ArenaRules.FAMILIES[opponent].cost: continue
			var row := {"family":candidate,"opponent":opponent,"opponent_rank":1,"copies":3,"wins":0,"draws":0,"trials":8,"timeouts":0}
			for seed_value in [8519,10777,12007,22031]:
				for side in 2:
					var result: Dictionary=await duel(candidate,2,opponent,1,3,seed_value,side)
					row.wins+=result.win; row.draws+=result.draw; row.timeouts+=int(result.reason=="timeout")
			rows.append(row); print("INVESTMENT_BALANCE ",JSON.stringify(row))
			FileAccess.open("user://arena-investment-balance.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	get_tree().quit(0 if hash(GameData.db.tables)==native else 1)

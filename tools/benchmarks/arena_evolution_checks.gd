extends Node
## Native economy recipes checked in real combat, including spells/projectiles.
## Paired sides guard against first-spawn/target-order bias.
var rows := []
func _ready() -> void:
	var pairs := []
	for family in ArenaRules.FAMILIES.size():
		for rank in ArenaRules.FAMILIES[family].forms.size() - 1:
			pairs.append([ArenaRules.prototype(family, rank), ArenaRules.prototype(family, rank + 1), ArenaRules.evolution_copies(family, rank)])
	if "--arena-candidates" in OS.get_cmdline_user_args():
		pairs = [["batredm1", "batredm5", 3], ["batredm1", "batredm3", 2],
			["batredm5", "batlightm7", 3], ["goblina1", "orcfemalea3", 3],
			["goblina1", "goblina3", 2], ["orcfemalea3", "orcfemalea5", 3],
			["orcfemalea3", "orcfemalea5", 2], ["toadm4", "toadm6", 2]]
	var run := ArenaRun.new()
	run.auto_save = false
	var arena := ArenaPveMatch.new()
	arena.run = run
	arena.rendered = false
	add_child(arena)
	arena.set_process(false)
	var field := Node3D.new()
	add_child(field)
	arena._world_parent = field
	for pair: Array in pairs:
		var copies := int(pair[2]) if pair.size() > 2 else 3
		var result := {"input":pair[0], "output":pair[1], "copies":copies, "trials":24, "wins":0, "draws":0}
		for index in 12:
			for upgraded_side in 2:
				run.begin(2700 + index)
				arena.prepare()
				for unit: GameUnit in arena.world.unit_rows(): arena.world.remove_unit(unit)
				arena.formation.clear()
				for side in 2:
					for n in (1 if side == upgraded_side else copies):
						arena._spawn({"id": pair[1] if side == upgraded_side else pair[0], "team":side,
							"point":Vector2(26 if side == 0 else 38, 32 if side == upgraded_side else 28 + n * 4)})
				if not arena.start(): get_tree().quit(1); return
				for tick in 5500:
					if arena.phase != ArenaMatch.Phase.FIGHT: break
					arena.simulate_tick()
				if arena.winner == upgraded_side: result.wins += 1
				elif arena.winner == -1: result.draws += 1
				await get_tree().process_frame
		rows.append(result)
		print("EVOLUTION ", JSON.stringify(result))
		var out := FileAccess.open("user://evolution-checks.json", FileAccess.WRITE)
		out.store_string(JSON.stringify({"seed_start":2700,"seeds":12,"paired_sides":true,"results":rows}, "\t"))
	get_tree().quit()

extends Node
## Exploratory melee matchups, not a proof that a merge recipe is balanced.
## Run with original-game data and an isolated user directory (see design doc).

const SEEDS := 12
const SEED_BASE := 2400
const CANDIDATES := [
	["boarredf3", "boarredf1"],
	["boardarkf6", "boarredf3"],
	["orcmalef3", "goblinf1"],
	["orcmalef5", "orcmalef3"],
	["ogregipatf5", "orcmalef3"],
	["tigerredf4", "wolfgreyf1"],
]


func _ready() -> void:
	if DisplayServer.get_name() != "headless" or GameData.difficulty != 0 or int(GameData.option("armor_formula")) != 0:
		_fail("Requires headless, normal difficulty and original armor formula.")
		return
	var summaries := []
	for pair: Array in CANDIDATES:
		for copies in [2, 3]:
			var result := {"output": pair[0], "input": pair[1], "copies": copies,
				"output_wins": 0, "input_wins": 0, "draws": 0, "trials": []}
			for seed_index in SEEDS:
				# Each seed plays twice. Side 0 always spawns first, so swapping
				# the output's side also swaps group insertion order.
				for output_side in 2:
					var combat_seed := SEED_BASE + seed_index
					seed(combat_seed)
					var arena := ArenaMatch.new()
					add_child(arena)
					arena.set_process(false)
					var stage := Node3D.new()
					add_child(stage)
					arena.create_world(stage)
					arena.world.presentation = false
					arena.world.combat.rng.seed = combat_seed
					for side in 2:
						var count: int = 1 if side == output_side else copies
						var creature: String = pair[0] if side == output_side else pair[1]
						for n in count:
							var point := Vector2(9 if side == 0 else 23, 16 + (n - (count - 1) / 2.0) * 3)
							var error := arena.place(creature, side, point)
							if not error.is_empty():
								_fail("Placement failed: %s: %s" % [creature, error])
								return
					if not arena.start():
						_fail("Battle did not start.")
						return
					arena.world.set_process(false)
					arena.world.set_physics_process(false)
					for tick in 5500:
						if arena.phase != ArenaMatch.Phase.FIGHT: break
						arena.world._advance(GameUnit.TICK)
						arena._process(0)
					if arena.phase != ArenaMatch.Phase.FINISHED:
						_fail("Battle exceeded fixture tick cap.")
						return
					var outcome := "draw"
					if arena.winner == output_side: outcome = "output"
					elif arena.winner == 1 - output_side: outcome = "input"
					if outcome == "draw": result.draws += 1
					elif outcome == "output": result.output_wins += 1
					else: result.input_wins += 1
					result.trials.append({"seed": combat_seed, "output_side": output_side,
						"outcome": outcome, "seconds": snappedf(arena.world.time, 0.001)})
					arena.queue_free()
					stage.queue_free()
					await get_tree().process_frame
			summaries.append(result)
			print("ARENA_EVOLUTION ", result.output, " vs ", copies, " ", result.input,
				": ", result.output_wins, "/", SEEDS * 2, " output wins; ", result.draws, " draws")
	var output := FileAccess.open("user://arena-evolutions.json", FileAccess.WRITE)
	if output == null:
		_fail("Cannot write research results.")
		return
	output.store_string(JSON.stringify({"fixture_version": 1, "cases": summaries,
		"engine": Engine.get_version_info().string, "seed_base": SEED_BASE,
		"seeds_per_case": SEEDS, "trials_per_case": SEEDS * 2,
		"armor_formula": GameData.option("armor_formula"), "difficulty": GameData.difficulty,
		"limit_seconds": ArenaMatch.TIME_LIMIT, "tick_seconds": GameUnit.TICK,
		"scope": "Native melee stats/AI; headless flat field; paired sides and group insertion order. No projectiles, mixed teams, economy or full runs."}, "\t"))
	output.close()
	get_tree().quit()


func _fail(message: String) -> void:
	printerr("ARENA_EVOLUTION_ERROR ", message)
	get_tree().quit(1)

class_name ArenaTournamentBattles
extends Node
## Simulate the other boards with native combat in bounded work per frame.
## No hidden simulation changes the visible battle's clock, sound or settings.
var run: ArenaTournamentRun
var simulation: ArenaPveMatch
var _round := -1
var _queue: Array[int] = []
var _active := -1

class DuelRun extends ArenaRun:
	var opponents: Array[Dictionary] = []
	var opposing_army: Array[Dictionary] = []
	func enemy_formation() -> Array[Dictionary]: return opponents
	func enemy_army() -> Array[Dictionary]: return opposing_army
	func resolve(_winner: int, _seconds: float, _damage: Array, _survivors: Array = [0,0]) -> void: pass

func _exit_tree() -> void:
	if is_instance_valid(simulation) and is_instance_valid(simulation.world):
		simulation.world.process_mode = Node.PROCESS_MODE_DISABLED

func _process(_dt: float) -> void:
	if run == null or run.stage != "fight": return
	if _round != run.wave:
		_round = run.wave
		_queue.clear()
		for index in run.pairings.size():
			if int(run.pairings[index].a) != 0 and not run.results.has(index): _queue.append(index)
	step(2500)

func step(budget_usec := 2500) -> void:
	var until := Time.get_ticks_usec() + budget_usec
	while Time.get_ticks_usec() < until and run.stage == "fight":
		if _active < 0:
			if _queue.is_empty(): return
			_start(_queue.pop_front())
		if simulation.phase == ArenaMatch.Phase.FIGHT: simulation.simulate_tick()
		if simulation.phase == ArenaMatch.Phase.FINISHED:
			var survivors := [0,0]
			for unit: GameUnit in simulation.world.unit_rows():
				if not unit.dead:
					var placement: Dictionary = unit.get_meta("arena_placement", {})
					survivors[int(placement.get("team",0))] += int(placement.get("rank",0)) + 1
			var index := _active
			_active = -1
			run.record_duel(index, simulation.winner, survivors)

func _start(index: int) -> void:
	_active = index
	if simulation == null:
		simulation = ArenaPveMatch.new()
		simulation.rendered = false
		simulation.drives_clock = false
		add_child(simulation)
		simulation._world_parent = self
		simulation.set_process(false); simulation.set_physics_process(false)
	var pair: Dictionary = run.pairings[index]
	var duel := DuelRun.new()
	duel.auto_save = false
	duel.run_seed = run.run_seed + index * 997
	duel.wave = run.wave
	duel.army = run.company(int(pair.a)).army.duplicate(true)
	if int(pair.b) < 0:
		duel.opponents = run.creeps()
	else:
		duel.opposing_army = run.company(int(pair.b)).army.duplicate(true)
		duel.opponents = ArenaTournamentRun.formation_for(duel.opposing_army, 1)
	simulation.run = duel
	simulation._round_key = ""
	simulation.prepare()
	if simulation.team_count(0) == 0 or simulation.team_count(1) == 0:
		simulation.winner = -1 if simulation.team_count(0) == simulation.team_count(1) else 0 if simulation.team_count(0) > 0 else 1
		simulation.phase = ArenaMatch.Phase.FINISHED
	else:
		simulation.start()
		simulation.world.set_process(false); simulation.world.set_physics_process(false)

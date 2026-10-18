extends Node
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL ",label)
func fresh() -> ArenaOnlineTournament:
	var run := ArenaOnlineTournament.new(); run.begin(7319); run.stage="fight"
	return run
func _ready() -> void:
	var run := fresh()
	var bank := run.gold
	run.resolve(1,15,[0,100],[0,7])
	check(run.lives==90 and run.stage=="fight","home defeat charges health before other boards finish")
	check(run.gold==bank and run.last_result.health_lost==10,"loss feedback precedes shared income")
	run.record_board(0,1,[0,7]); check(run.lives==90,"duplicate result cannot charge twice")
	var saved := run.snapshot()
	var restored := ArenaTournamentRun.new(); restored.auto_save=false
	check(saved.lives==100 and restored.restore(saved) and restored.lives==100 and restored.stage=="prepare","interrupted save replays at original health")
	run.record_board(1,1,[0,5])
	check(run.health(1)==92 and run.company(1).last_result.health_lost==8,"guest loses health immediately too")
	for player in range(2,9): run.record_board(player,0,[3,0])
	check(run.stage=="result" and run.lives==90 and run.health(1)==92,"shared settlement does not charge losses again")
	check(run.company(1).last_result.health_lost==8,"guest recap retains the full earlier loss")
	run=fresh(); run.lives=1
	run.resolve(1,15,[0,100],[0,7])
	check(run.lives==0 and run.stage=="fight","lethal home defeat waits for remaining boards")
	for player in range(1,8): run.record_board(player,0,[3,0])
	check(run.stage=="fight","eliminated player does not shorten the round's participant count")
	run.record_board(8,0,[3,0])
	check(run.stage=="result" and run.placements[0]==9,"last board settles eliminated player's place")
	run=fresh(); run.resolve(1,15,[0,100],[0,7]); run.record_board(1,1,[0,5])
	run.rollback_round_health()
	check(run.lives==100 and run.health(1)==100,"worker interruption rolls back partial health")
	print("ARENA_RESULT_HEALTH ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

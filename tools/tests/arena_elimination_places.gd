extends Node
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL ",label)
func _ready() -> void:
	var run := ArenaTournamentRun.new(); run.auto_save=false; run.live_boards=true; run.begin(7191)
	# Creep rounds deal no player damage; fight a player round instead.
	run.wave=4; run._choose_pairings()
	check(not run.is_creep_round() and run.defeat_damage(3)>2,"fixture defeats are lethal for both rivals")
	run.stage="fight"; run.rival_health[0]=1; run.rival_health[1]=2
	run.record_board(1,1,[0,3])
	check(run.health(1)==0 and run.placements[1]==0,"rank stays pending while other boards are fighting")
	run.record_board(2,1,[0,3])
	for player in range(3,9): run.record_board(player,0,[3,0])
	run.resolve(0,5,[0,0],[3,0])
	check(run.stage=="result","all boards settle together")
	check(run.placements[1]==9 and run.placements[2]==8,"same-round elimination ranks use remaining health")
	for player in 9:
		check(run.health(player)>0 or run.placements[player]>0,"every settled eliminated player has a finishing place")
	print("ARENA_ELIMINATION_PLACES ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(int(failures>0))

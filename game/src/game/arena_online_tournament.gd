class_name ArenaOnlineTournament
extends ArenaTournamentRun
## Host-only rules. Every human owns one ordinary company; absent seats use
## the existing paid bot policy. Seat zero's elimination cannot stop the room.
var humans := {}

func _init() -> void:
	auto_save = false
	live_boards = true

func computer_controls(player: int) -> bool: return not humans.has(player)
func continues_after_elimination() -> bool: return true
func round_savings(player: int) -> int: return company(player).battle_savings
func save() -> bool: return false
func load_saved() -> bool: return false

func start_battle(allow_empty := false) -> String:
	var error := super.start_battle(allow_empty)
	if error.is_empty():
		for rival in rivals:
			rival.stage = "fight"
			rival.battle_savings = rival.gold
	return error

func record_board(player: int, winner: int, survivors: Array) -> void:
	if lives <= 0 and _human_result.is_empty():
		_human_result = {"wave":wave,"winner":-1,"seconds":0.0,"damage":[0,0],"gold":0}
	super.record_board(player, winner, survivors)

func _settle_round() -> void:
	var before := rival_health.duplicate()
	super._settle_round()
	for index in rivals.size():
		var rival := rivals[index]
		if board_results.has(index + 1):
			var result: Dictionary = board_results[index + 1]
			rival.last_result = rival.history[-1].duplicate(true)
			# The shared settlement can make both sides draw even when one
			# mirrored board finished with a win. Preserve its income/streak result.
			if int(result.winner) == -1 or (rival.last_result.winner == 1 and result.winner == 0):
				rival.last_result.winner = -1
			rival.last_result["health_lost"] = int(before[index]) - health(index + 1)
			rival.history[-1] = rival.last_result.duplicate(true)
		rival.stage = "result" if health(index + 1) > 0 else "lost"

func _prepare_round() -> void:
	super._prepare_round()
	for rival in rivals:
		rival.combine_ready()
		rival._undo.clear()

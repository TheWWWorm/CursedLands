class_name ArenaOnlineBoards
extends ArenaTournamentBattles
## The same scouting layout, backed exclusively by received board snapshots.
func synchronize() -> void:
	if parent_stage == null: return
	for player in range(1, ArenaTournamentRun.PLAYER_COUNT):
		if boards.has(player): continue
		var holder := Node3D.new(); parent_stage.add_child(holder); holders[player] = holder
		var battle := ArenaOnlineMatch.new()
		battle.run = DuelRun.new(); battle.run.auto_save = false
		battle.run.league = run; battle.run.player = player
		battle.rendered = rendered
		add_child(battle); battle._world_parent = holder
		boards[player] = battle
		battle.visual_event.connect(func(event):
			if viewed_player == player: board_event.emit(event))
	_apply_view()

func _process(_dt: float) -> void:
	if overview: _apply_view()

func request_start(_allow_empty := false) -> bool: return false

func watched_match() -> ArenaPveMatch:
	var battle := super.watched_match()
	battle.prepare()
	return battle

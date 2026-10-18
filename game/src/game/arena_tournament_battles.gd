class_name ArenaTournamentBattles
extends Node
## Nine live home boards share a 3×3 map. A focused view draws one board;
## the overview draws them all while native combat keeps running independently.
const MAP_SEATS := [1, 2, 3, 4, 0, 5, 6, 7, 8]
const BOARD_SIZE := 64.0
signal board_changed(player: int)
var run: ArenaTournamentRun
var boards := {}
var holders := {}
var parent_stage: Node3D
var home: ArenaPveMatch
var viewed_player := 0
var paused := false
var rendered := true
var overview := false
var _round := -1
var _started := false
var starting := false
var _start_queue: Array[int] = []
var _allow_empty := false

class DuelRun extends ArenaRun:
	var league: ArenaTournamentRun
	var player := 1
	func arrivals_at_start() -> bool: return true
	func enemy_formation() -> Array[Dictionary]:
		return league.creeps() if league.opponent_for(player) < 0 else ArenaTournamentRun.formation_for(enemy_army(), 1)
	func enemy_army() -> Array[Dictionary]:
		var opponent := league.opponent_for(player)
		if opponent < 0: return []
		return league.company(opponent).army
	func resolve(winner: int, _seconds: float, _damage: Array, survivors: Array = [0,0]) -> void:
		league.record_board(player, winner, survivors)


func _exit_tree() -> void:
	for holder in holders.values():
		if is_instance_valid(holder): holder.queue_free()


func synchronize() -> void:
	if parent_stage == null or home == null or run.stage != "prepare" or run.rivals.size() != ArenaTournamentRun.PLAYER_COUNT - 1: return
	if _round != run.wave:
		_round = run.wave; _started = false; starting = false; _start_queue.clear()
		for player in range(1, ArenaTournamentRun.PLAYER_COUNT):
			if run.health(player) <= 0: continue
			_sync_board(player)
		viewed_player = viewed_player if run.health(viewed_player) > 0 else 0
		_apply_view()
		board_changed.emit(viewed_player)


func _sync_board(player: int) -> void:
	var match_node: ArenaPveMatch = boards.get(player)
	if match_node == null:
		var holder := Node3D.new()
		parent_stage.add_child(holder)
		holder.visible = player == viewed_player
		holders[player] = holder
		match_node = ArenaPveMatch.new()
		match_node.drives_clock = false
		match_node.rendered = rendered
		match_node.run = DuelRun.new()
		match_node.run.auto_save = false
		match_node.run.league = run
		match_node.run.player = player
		add_child(match_node)
		match_node._world_parent = holder
		boards[player] = match_node
		if not rendered:
			match_node.set_process(false); match_node.set_physics_process(false)
		match_node.visual_event.connect(func(event):
			if viewed_player == player: board_event.emit(event))
	var company := run.company(player)
	match_node.run.army = company.army.duplicate(true)
	match_node.run.run_seed = run.run_seed + player * 997
	match_node.run.wave = run.wave
	match_node.run.stage = "prepare"
	match_node.prepare()
	company.deployment_check = match_node.recruitment_clear
	_apply_view()
	board_changed.emit(player)


signal board_event(event: Dictionary)

func watched_match() -> ArenaPveMatch:
	return home if viewed_player == 0 else boards.get(viewed_player, home)


func watch(player: int) -> void:
	overview = false
	viewed_player = player if player == 0 or boards.has(player) else 0
	_apply_view()
	board_changed.emit(viewed_player)


func show_all() -> void:
	overview = true
	_apply_view()
	board_changed.emit(viewed_player)


static func board_offset(player: int) -> Vector3:
	var cell := MAP_SEATS.find(player)
	return Vector3((cell % 3) * BOARD_SIZE, 0, -(cell / 3) * BOARD_SIZE)


func _apply_view() -> void:
	if is_instance_valid(home.world):
		home.world.visible = overview or viewed_player == 0
		_place_world(home.world, board_offset(0) if overview else Vector3.ZERO)
	for id: int in holders:
		holders[id].visible = overview or id == viewed_player
		_place_world(holders[id], board_offset(id) if overview else Vector3.ZERO)
	for match_node: ArenaPveMatch in [home] + boards.values():
		if not is_instance_valid(match_node.world): continue
		var fx := match_node.world.get_node_or_null("ParticleFx") as ParticleFx
		if fx: fx.sync_visibility()
	if rendered: Gfx.set_border(Vector2.ONE * (192 if overview else 64), 8.0)


func _place_world(node: Node3D, at: Vector3) -> void:
	if node.position == at: return
	node.position = at
	node.reset_physics_interpolation()
	for child in node.find_children("*", "Node3D", true, false):
		if child is GameUnit: child.resync_drawn()


func request_start(allow_empty := false) -> bool:
	if starting: return true
	if run.stage != "prepare" or (home.team_count(0) == 0 and not allow_empty): return false
	run.finish_preparation()
	_allow_empty = allow_empty
	_start_queue.assign(run.alive_players())
	starting = true
	run.preparing_battle = true
	run.changed.emit()
	return true


func _prepare_start_frame() -> void:
	if not _start_queue.is_empty():
		var player: int = _start_queue.pop_front()
		if player > 0: _sync_board(player)
		var encounter := home if player == 0 else boards[player] as ArenaPveMatch
		encounter.prepare_opponent_models()
		return
	starting = false; _started = true
	run.preparing_battle = false
	if _allow_empty: home.expire_preparation()
	else: home.start()
	for player in range(1, ArenaTournamentRun.PLAYER_COUNT):
		if run.health(player) <= 0: continue
		var encounter: ArenaPveMatch = boards[player]
		if encounter.team_count(0) > 0: encounter.start()
		else: run.record_board(player, 1, [0, encounter.run.enemy_formation().size()])
	_apply_view()


func _process(dt: float) -> void:
	if parent_stage == null or run.rivals.size() != ArenaTournamentRun.PLAYER_COUNT - 1: return
	for match_node: ArenaPveMatch in boards.values():
		match_node.formation_motion.paused = paused
		if paused and match_node.phase == ArenaMatch.Phase.FIGHT: match_node.toggle_pause()
		elif not paused and match_node.phase == ArenaMatch.Phase.PAUSED: match_node.toggle_pause()
	if paused: return
	synchronize()
	if starting:
		_prepare_start_frame()
		return
	if run.stage == "prepare":
		for player in run.advance_bots(dt / maxf(Engine.time_scale, 0.001)):
			_sync_board(player)
	elif run.stage == "fight" and not _started:
		_started = true
		for player in range(1, ArenaTournamentRun.PLAYER_COUNT):
			if run.health(player) <= 0: continue
			_sync_board(player)
			var match_node: ArenaPveMatch = boards[player]
			if match_node.team_count(0) > 0: match_node.start()
			else:
				run.record_board(player, 1, [0, match_node.run.enemy_formation().size()])
		_apply_view()


## Research uses the same concurrent boards, advancing one native tick each.
func step() -> void:
	for match_node: ArenaPveMatch in boards.values():
		if match_node.phase == ArenaMatch.Phase.FIGHT: match_node.simulate_tick()

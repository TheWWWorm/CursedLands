class_name ArenaOnlineScreen
extends ArenaPveScreen
var connection: ArenaOnlineSession

func _ready() -> void:
	network_play = true; landing = false
	run = connection.view
	Engine.time_scale = 1.0
	super._ready()
	connection.board_received.connect(_board)
	connection.effects_received.connect(_effects)
	connection.notice.connect(_feedback)
	connection.closed.connect(_disconnected)

func _create_battle() -> ArenaPveMatch: return ArenaOnlineMatch.new()
func _create_boards() -> ArenaTournamentBattles: return ArenaOnlineBoards.new()

func _board(data: Dictionary) -> void:
	if int(data.round) != run.wave: return
	var player := connection.view.seats.find(int(data.seat))
	_tournament_battles.synchronize()
	var match_node: ArenaOnlineMatch = battle if player == 0 else _tournament_battles.boards.get(player)
	if match_node:
		match_node.apply_board(data)
		_tournament_battles._apply_view()

func _effects(data: Dictionary) -> void:
	if int(data.round) != run.wave: return
	var player := connection.view.seats.find(int(data.seat))
	var match_node: ArenaOnlineMatch = battle if player == 0 else _tournament_battles.boards.get(player)
	if match_node: match_node.apply_effects(data)

func _fight() -> void: connection.request("ready")
func _show_player(player: int) -> void:
	super._show_player(player)
	connection.watch(player)
func _show_boards() -> void:
	super._show_boards()
	connection.watch(-1)

func _refresh() -> void:
	super._refresh()
	var ready_now := connection.view.ready_seats.has(connection.my_seat)
	_start.text = RemakeText.t("Not ready" if ready_now else "Ready")
	_start.tooltip_text = RemakeText.t("Start when every human is ready, or when the timer ends. Changing your army cancels ready.")
	if run.lives <= 0 and connection.view.global_stage != "won":
		_hint(RemakeText.t("You have been eliminated. You can keep watching."))

func _process(dt: float) -> void:
	_result_remaining = connection.view.result_left
	super._process(dt)
	if run.lives <= 0 and connection.view.global_stage != "won":
		_phase.text = RemakeText.t("Place #%d") % run.placements[0]

func _build_result() -> void:
	_wrap(_dock, RemakeText.t("First place" if run.stage == "won" else "Eliminated"), 28, GOLD)
	_wrap(_dock, RemakeText.t("Place #%d") % run.placements[0], 20)
	_button(_dock, RemakeText.t("Leave game"), func(): exit_requested.emit(), "")

func _menu_action(id: int) -> void:
	if id != 2: super._menu_action(id); return
	_open_modal(RemakeText.t("Leave game"), 480)
	_wrap(_modal_box, RemakeText.t("Leaving closes the online game for everyone.") if connection.is_host else RemakeText.t("A computer will take over your army if you leave."), 16)
	_button(_modal_box, RemakeText.t("Cancel"), _close_modal, "")
	_button(_modal_box, RemakeText.t("Leave game"), func(): exit_requested.emit(), "")

func _disconnected(text: String) -> void:
	_open_modal(RemakeText.t("Connection lost"), 480)
	_wrap(_modal_box, text, 16)
	_button(_modal_box, RemakeText.t("Main menu"), func(): exit_requested.emit(), "")

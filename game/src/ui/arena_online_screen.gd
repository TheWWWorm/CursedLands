class_name ArenaOnlineScreen
extends ArenaPveScreen
var connection: ArenaOnlineSession
var _previous_army: Array = []
var _have_roster := false

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

func _fight() -> void:
	_cancel_item()
	connection.request("ready")
func _show_player(player: int) -> void:
	super._show_player(player)
	connection.watch(player)
func _show_boards() -> void:
	super._show_boards()
	connection.watch(-1)

func _refresh() -> void:
	super._refresh()
	# Purchases are asynchronous. Compare the acknowledged army when its
	# state arrives, rather than reading the previous purchase's merge list.
	if _have_roster: _present_evolutions(_previous_army)
	_previous_army=run.army.duplicate(true); _have_roster=true
	_speed.visible = run.stage == "fight"
	_speed.disabled = not connection.owns_game()
	_update_speed()
	var ready_now := connection.view.ready_seats.has(connection.my_seat)
	_start.text = RemakeText.t("Not ready" if ready_now else "Ready")
	_start.tooltip_text = RemakeText.t("Start when every human is ready, or when the timer ends. Changing your army cancels ready.")
	if run.lives <= 0 and connection.view.global_stage != "won":
		_hint(RemakeText.t("You have been eliminated. You can keep watching."))

func _process(dt: float) -> void:
	Engine.time_scale = float(connection.view.battle_speed) if connection.view.global_stage == "fight" else 1.0
	_result_remaining = connection.view.result_left
	super._process(dt)
	if run.lives <= 0 and connection.view.global_stage != "won" and _tournament_battles.viewed_player == 0:
		_phase.text = RemakeText.t("Place #%d") % run.placements[0] if run.placements[0]>0 else RemakeText.t("Defeat")

func _build_result() -> void:
	_wrap(_dock, RemakeText.t("First place" if run.stage == "won" else "Eliminated"), 28, GOLD)
	_wrap(_dock, RemakeText.t("Place #%d") % run.placements[0], 20)
	_button(_dock, RemakeText.t("Leave game"), func(): exit_requested.emit(), "")

func _menu_action(id: int) -> void:
	if id != 2: super._menu_action(id); return
	_open_modal(RemakeText.t("Leave game"), 480)
	_wrap(_modal_box, RemakeText.t("Leaving closes the online game for everyone.") if connection.owns_game() else RemakeText.t("A computer will take over your army if you leave."), 16)
	_button(_modal_box, RemakeText.t("Cancel"), _close_modal, "")
	_button(_modal_box, RemakeText.t("Leave game"), func(): exit_requested.emit(), "")

func _disconnected(text: String) -> void:
	_open_modal(RemakeText.t("Connection lost"), 480)
	_wrap(_modal_box, text, 16)
	_button(_modal_box, RemakeText.t("Main menu"), func(): exit_requested.emit(), "")

func _toggle_speed() -> void:
	if connection.owns_game(): connection.request("speed", [3 - connection.view.battle_speed])

func _update_speed() -> void:
	_speed.text = RemakeText.t("1×" if connection.view.battle_speed == 1 else "2×")
	_speed.tooltip_text = RemakeText.t("Battle speed") + "\n" + RemakeText.t("The host controls battle speed for everyone.")
	if _tooltips: _tooltips.capture(_speed)

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	super._exit_tree()

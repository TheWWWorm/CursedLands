class_name ArenaOnlineView
extends ArenaTournamentRun
## Read-only, locally oriented projection. UI actions send intents; only the
## host's reply changes money, army, shops, health or the round.
var submit: Callable
var seat := 0
var seats: Array[int] = []
var names: Array[String] = []
var ready_seats: Array[int] = []
var can_revert := false
var connected := true
var _ui_key := 0
var global_stage := "prepare"
var result_left := 4.0
var battle_speed := 1
var fighting_seats: Array = []
var sale_quotes := {}

func _init() -> void:
	auto_save = false

func apply_state(data: Dictionary) -> void:
	seat = int(data.seat)
	seats.assign([seat])
	for player in PLAYER_COUNT:
		if player != seat: seats.append(player)
	_copy_company(self, data.companies[seat])
	sale_quotes.clear()
	for quote: Array in data.get("sale_quotes",[]):
		if quote.size()==2: sale_quotes[int(quote[0])] = int(quote[1])
	run_seed = int(data.seed); wave = int(data.round); wave_limit = MAX_ROUNDS
	preparation_left = float(data.left); result_left = float(data.result_left)
	preparing_battle = bool(data.staging)
	global_stage = String(data.stage)
	battle_speed = clampi(int(data.get("speed", 1)), 1, 2)
	fighting_seats = data.get("fighting", [])
	stage = global_stage
	if global_stage == "won": stage = "won" if int(data.placements[seat]) == 1 else "lost"
	lives = int(data.health[seat])
	rivals.clear(); rival_health.clear(); placements.clear(); names.clear()
	for local in PLAYER_COUNT:
		var server := seats[local]
		placements.append(int(data.placements[server]))
		names.append(String(data.names[server]))
		if local == 0: continue
		var rival := ArenaRun.new(); rival.auto_save = false
		_copy_company(rival, data.companies[server])
		rivals.append(rival); rival_health.append(int(data.health[server]))
	pairings.clear()
	for pairing: Dictionary in data.pairings:
		var a := seats.find(int(pairing.a)); var b := seats.find(int(pairing.b))
		if b == 0 and not pairing.ghost:
			var held := a; a = b; b = held
		pairings.append({"a":a,"b":b,"ghost":bool(pairing.ghost)})
	ready_seats.assign(data.ready)
	can_revert = bool(data.undo)
	var company_ui: Dictionary = data.companies[seat].duplicate()
	# The host company owns the countdown; it is not a roster/UI change.
	company_ui.erase("preparation_left")
	var key := hash([company_ui, battle_speed, fighting_seats, data.health, data.placements, data.stage, data.ready, data.names, data.round, data.staging])
	if key != _ui_key:
		_ui_key = key
		changed.emit()

static func _copy_company(target: ArenaRun, data: Dictionary) -> void:
	for key in ["gold", "training", "battle_savings", "wave", "next_uid"]:
		target.set(key, int(data[key]))
	target.run_seed = int(data.seed)
	target.army.assign(data.army.duplicate(true)); target.shop.assign(data.shop.duplicate(true))
	target.history.assign(data.history.duplicate(true)); target.last_result = data.last_result.duplicate(true)
	target.free_refresh = bool(data.free_refresh)
	target.last_evolutions.assign(data.get("evolutions", []))
	target.items.assign(data.get("items", []).duplicate(true))
	target.item_offers.assign(data.get("item_offers", []))
	target.next_item_uid = int(data.get("next_item_uid", 1))
	target.item_reward_round = int(data.get("item_reward_round", 0))
	target._sync_items()

func player_title(player: int) -> String:
	var server := seats[player]
	if not names[player].is_empty(): return names[player]
	return super.player_title(server) if server > 0 else RemakeText.t("Computer")

func player_fighting(player: int) -> bool:
	return global_stage == "fight" and seats[player] in fighting_seats

func _intent(action: String, args: Array = []) -> String:
	if not connected: return RemakeText.t("Connection to the host was lost.")
	if submit.is_valid(): submit.call(action, args)
	return ""

func can_shop() -> bool: return connected and lives > 0 and super.can_shop()
func buy(index: int) -> String: return _intent("buy", [index])
func refresh() -> String: return _intent("refresh")
func train() -> String: return _intent("train")
func equip_item(item_uid: int, unit_uid: int) -> String: return _intent("equip_item", [item_uid, unit_uid])
func choose_item(index: int) -> String: return _intent("choose_item", [index])
func lock_offer(index: int) -> void: _intent("lock", [index])
func deploy(uid: int, point: Vector2) -> String: return _intent("deploy", [uid, point])
func bench(uid: int, slot := -1) -> String: return _intent("bench", [uid, slot])
func sale_value(entry: Dictionary) -> int:
	return int(sale_quotes.get(int(entry.uid),super.sale_value(entry)))
func sell(uid: int) -> String:
	var entry := unit(uid)
	if entry.is_empty(): return RemakeText.t("Choose a creature from your army.")
	return _intent("sell", [uid,sale_value(entry)])
func evolve(uid: int) -> String: return _intent("evolve", [uid])
func swap_from_bench(uid: int, deployed_uid: int) -> String: return _intent("swap", [uid, deployed_uid])
func arrange() -> void: _intent("arrange")
func undo() -> void: _intent("undo")
func can_undo() -> bool: return can_revert and connected and lives > 0 and stage == "prepare"
func advance() -> void: pass
func elapse_preparation(_seconds: float) -> bool: return false
func save() -> bool: return false
func load_saved() -> bool: return false
func resolve(_winner: int, _seconds: float, _damage: Array, _survivors: Array = [0,0]) -> void: pass
func record_board(_player: int, _winner: int, _survivors: Array) -> void: pass

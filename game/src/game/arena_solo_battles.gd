class_name ArenaSoloBattles
extends ArenaTournamentBattles
## Preparation/economy/saves stay local. Only frozen combat runs in a private,
## authenticated loopback worker; the visible figures consume its snapshots.
signal failed(message: String)
var connection: ArenaOnlineSession
var worker_ready := false
var worker_failed := false
var booting := false
var external_active := false
var _pending_snapshot := {}
var _initial: Array = []
var _prepared_round := -1
var _clock_state: Array = []

func _exit_tree() -> void:
	if is_instance_valid(connection): connection.close();connection.queue_free()
	super._exit_tree()

func _boot() -> void:
	booting=true
	connection=ArenaOnlineSession.new();add_child(connection)
	connection.solo_prepared.connect(_prepared)
	connection.solo_result.connect(_result)
	connection.board_received.connect(_board)
	connection.effects_received.connect(_effects)
	connection.closed.connect(_lost)
	var error := await connection.local_host.start(0,false,true)
	if not is_inside_tree(): return
	worker_ready=error==OK;worker_failed=error!=OK;booting=false
	if worker_failed: GameData.trace("Solo autochess worker unavailable (%d); using inline combat"%error)
	else:
		connection._send(1,{"t":"view","seat":-1 if overview else viewed_player})
		_send_preparation()

func synchronize() -> void:
	if _round!=run.wave:
		external_active=false;_initial.clear();_prepared_round=-1;_clock_state.clear()
	super.synchronize()

func request_start(allow_empty := false) -> bool:
	if starting: return true
	if not super.request_start(allow_empty): return false
	if not worker_failed:
		_pending_snapshot=run.snapshot()
		_send_preparation()
	return true

func _send_preparation() -> void:
	if not worker_ready or _pending_snapshot.is_empty(): return
	connection._send(1,{"t":"solo_prepare","snapshot":_pending_snapshot,"speed":GameData.arena_speed})
	_pending_snapshot={}

func _prepared(data: Dictionary) -> void:
	if int(data.round)!=run.wave or not starting: return
	if data.get("error",false):
		GameData.trace("Solo combat snapshot rejected; using inline combat")
		_inline_fallback();return
	_prepared_round=run.wave;_initial=data.boards.duplicate(true)

func _prepare_start_frame() -> void:
	if worker_failed:
		super._prepare_start_frame();return
	if not _start_queue.is_empty():
		var player: int=_start_queue.front()
		if _preparing_player!=player:
			_preparing_player=player
			if player>0: _sync_board(player)
		var encounter:=home if player==0 else boards[player] as ArenaPveMatch
		if encounter.prepare_opponent_models(1): _start_queue.pop_front()
		return
	if _prepared_round!=run.wave: return
	if not _initial.is_empty():
		var data: Dictionary=_initial.pop_front()
		var battle: ArenaPveMatch=home if int(data.seat)==0 else boards[int(data.seat)]
		battle.adopt_replica_formation(data)
		data.phase=ArenaMatch.Phase.DEPLOY
		battle.apply_board(data)
		return
	if prepare_presentation.is_valid() and not prepare_presentation.call(): return
	starting=false;_started=true;external_active=true;run.preparing_battle=false
	run.start_battle(_allow_empty)
	for battle: ArenaPveMatch in [home]+boards.values():
		if battle.external_combat:
			battle.phase=ArenaMatch.Phase.FIGHT
			battle.world.set_process(true);battle.world.set_physics_process(true)
	_apply_view();_clock_state.clear();_send_clock()

func _process(dt: float) -> void:
	if not paused and not booting and not worker_ready and not worker_failed: _boot()
	super._process(dt)
	if external_active: _send_clock()

func _send_clock() -> void:
	if not worker_ready or not external_active: return
	var stopped := paused or run.stage != "fight"
	var state := [run.wave,stopped,GameData.arena_speed]
	if state==_clock_state: return
	_clock_state=state
	connection._send(1,{"t":"solo_clock","round":run.wave,"paused":stopped,"speed":GameData.arena_speed})

func watch(player: int) -> void:
	super.watch(player)
	if worker_ready: connection._send(1,{"t":"view","seat":viewed_player})

func show_all() -> void:
	super.show_all()
	if worker_ready: connection._send(1,{"t":"view","seat":-1})

func _board(data: Dictionary) -> void:
	if not external_active or int(data.round)!=run.wave: return
	var battle: ArenaPveMatch=home if int(data.seat)==0 else boards.get(int(data.seat))
	if battle: battle.apply_board(data)

func _effects(data: Dictionary) -> void:
	if not external_active or int(data.round)!=run.wave: return
	var battle: ArenaPveMatch=home if int(data.seat)==0 else boards.get(int(data.seat))
	if battle: battle.apply_effects(data)

func _result(data: Dictionary) -> void:
	if not external_active or int(data.round)!=run.wave: return
	var player:=int(data.seat)
	if player==0: run.resolve(int(data.winner),float(data.time),data.damage,data.survivors)
	else: run.record_board(player,int(data.winner),data.survivors)

func _lost(_reason: String) -> void:
	worker_ready=false;worker_failed=true
	if not external_active:
		if starting: _inline_fallback()
		return
	external_active=false
	if run.stage!="fight": return
	# Partial outcomes must never settle a failed round. Restore its normal
	# saved preparation, keeping purchases made while combat was running.
	run.stage="prepare";run.results.clear();run.board_results.clear();run._human_result.clear()
	run.preparing_battle=false;run.preparation_left=ArenaRules.PREPARATION_SECONDS
	home._round_key="";home.prepare();_round=-1;synchronize();run.changed.emit()
	failed.emit(RemakeText.t("Battle interrupted. Your army is ready to try the round again."))


func _inline_fallback() -> void:
	worker_failed=true;worker_ready=false;_initial.clear()
	if is_instance_valid(connection): connection.close()
	if not starting:return
	# A failure may arrive after only some replicas adopted worker IDs.
	# Recreate ordinary preparation before handing every board to local AI.
	run.preparing_battle=false
	home._round_key="";home.prepare()
	_round=-1;super.synchronize()
	starting=false
	super.request_start(_allow_empty)

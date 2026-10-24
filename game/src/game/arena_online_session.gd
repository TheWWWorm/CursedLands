class_name ArenaOnlineSession
extends Node
## Dedicated packet protocol: no remote method calls or object decoding.
## ENet serves desktop/mobile; WebSocket hosts also accept browser clients.
signal lobby_changed
signal match_started
signal board_received(data: Dictionary)
signal effects_received(data: Dictionary)
signal notice(text: String)
signal closed(text: String)
signal solo_prepared(data: Dictionary)
signal solo_result(data: Dictionary)
const PORT := 27016
const LAN_PORT := 27018   # 27016 is the autochess game socket / campaign discovery port
# Equipment ownership and summoned actor state require matching builds, even
# while an unpublished branch still carries the previous public version.
const PROTOCOL := 4
const MAX_PACKET := 1048576
const HELLO_TIMEOUT := 15.0
const ERRORS := ["Online autochess requires the same game version and original game data.", "This online game has already started.", "This online game is full.", "Incorrect password.", "Connection to the host was lost.", "Could not connect to the host.", "Invalid online action.", "You have been eliminated. You can keep watching.", "The round changed. Try the action again.", "Wait for every player to be ready.", "Too many actions. Try again in a moment.", "The shop changed. Choose an offer again.", "The sale value changed. Select the creature again."]
var peer: MultiplayerPeer
var is_host := false
var expansion := false
var _expansion_hash := ""
var my_seat := -1
var members := {}
var view := ArenaOnlineView.new()
var game: ArenaOnlineGame
var lan: LanDiscovery
var upnp: UpnpPort
var local_host: ArenaLocalHost
var password := ""
var player_name := ""
var status := ""
var host_port := PORT
var websocket := false
var started := false
var last_state := {}
var _connected := false
var _elapsed := 0.0
var _send_left := 0.0
var _pending := {}
var _sequences := {}
var _budgets := {}
var _view_budgets := {}
var _views := {}
var _sent_boards := {}
var _sequence := 0
var _dirty := true
var _state_left := 0.0
var _last_frame_at := 0
var _solo_running := false
var _solo_pending: Array[Dictionary] = []
var _solo_view_group := 0

func _ready() -> void:
	view.submit = request
	local_host = ArenaLocalHost.new(); local_host.session = self; add_child(local_host)
	upnp = UpnpPort.new(); add_child(upnp)
	lan = LanDiscovery.new()
	lan.discovery_port = LAN_PORT
	lan.protocol = PROTOCOL
	lan.modes = PackedStringArray(["autochess"])
	lan.info_provider = lan_info
	add_child(lan)

func owns_game() -> bool:
	return peer != null and (is_host or (local_host != null and local_host.frontend and local_host.owned))

func host_shown(port := PORT, use_websocket := false) -> Error:
	if not ArenaLocalHost.available(): return host(port, use_websocket)
	var error := await local_host.start(port, use_websocket)
	if error == OK and not use_websocket and GameData.option("net_upnp") == 1 \
			and not Array(OS.get_cmdline_user_args()).any(func(arg): return arg.begins_with("--tool=")):
		upnp.open(port)
	return error

func host(port := PORT, use_websocket := false) -> Error:
	if expansion and not ArenaExpansion.mount(): return ERR_UNAVAILABLE
	_expansion_hash = ArenaExpansion.fingerprint() if expansion else ""
	if peer != null: return ERR_ALREADY_IN_USE
	if OS.has_feature("web"): return ERR_UNAVAILABLE
	if port < (0 if local_host.solo_combat else 1) or port > 65535: return ERR_INVALID_PARAMETER
	websocket = use_websocket
	peer = Session._websocket_peer() if websocket else ENetMultiplayerPeer.new()
	if local_host.solo_combat and peer is ENetMultiplayerPeer: peer.set_bind_ip("127.0.0.1")
	var error: Error = peer.create_server(port) if websocket else peer.create_server(port, 12)
	if error != OK: peer = null; return error
	if peer is ENetMultiplayerPeer: peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	is_host = true; my_seat = 0; host_port = peer.get_host().get_local_port() if peer is ENetMultiplayerPeer else port
	members[1] = {"seat":0,"name":clean_name(player_name),"ready":true,"commander":ArenaCommanders.valid(GameData.arena_character, expansion)}
	_views[1] = 0
	peer.peer_connected.connect(_peer_connected); peer.peer_disconnected.connect(_peer_disconnected)
	if not local_host.solo_combat and not websocket and GameData.option("net_upnp") == 1 and not Array(OS.get_cmdline_user_args()).any(func(arg): return arg.begins_with("--tool=")): upnp.open(port)
	# Public LAN lobbies advertise like campaign co-op. There is no net_lan
	# setting; unknown options read as zero and silently hid every real lobby.
	if not local_host.solo_combat: lan.listen()
	_connected = true; lobby_changed.emit()
	return OK

func lan_info() -> Dictionary:
	if not is_host or peer == null: return {}
	return {"name":clean_name(player_name), "mode":"autochess", "players":members.size(),
		"max":9, "pw":not password.is_empty(), "ws":websocket, "port":host_port, "in_game":started, "expansion":expansion}

func join(address: String) -> Error:
	if expansion and not ArenaExpansion.mount(): return ERR_UNAVAILABLE
	_expansion_hash = ArenaExpansion.fingerprint() if expansion else ""
	var parsed := Session.parse_address(address, PORT)
	websocket = String(parsed[0]).begins_with("ws://") or String(parsed[0]).begins_with("wss://")
	if String(parsed[0]).is_empty() or int(parsed[1]) < 1 or int(parsed[1]) > 65535: return ERR_INVALID_PARAMETER
	if OS.has_feature("web") and not websocket: return ERR_INVALID_PARAMETER
	peer = Session._websocket_peer() if websocket else ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(parsed[0]) if websocket else peer.create_client(parsed[0], parsed[1])
	if error != OK: peer = null; return error
	if peer is ENetMultiplayerPeer: peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	_elapsed = 0; _connected = false
	return OK

static func clean_name(value: String) -> String:
	var clean := ""
	for character in value.strip_edges():
		if character.unicode_at(0) >= 32 and character.unicode_at(0) != 127: clean += character
	return clean.left(24) if not clean.is_empty() else RemakeText.t("Player name")

func _loading_timeout(id: int) -> void:
	# Match campaign co-op: a cold scene build can exceed ENet's default
	# five-second transport timeout even while the game is still loading.
	if peer is ENetMultiplayerPeer:
		var remote := (peer as ENetMultiplayerPeer).get_peer(id)
		if remote: remote.set_timeout(0, Session.PEER_TIMEOUT_MS, Session.PEER_TIMEOUT_MS)

func _peer_connected(id: int) -> void:
	_loading_timeout(id)
	_pending[id] = Time.get_ticks_msec()

func _peer_disconnected(id: int) -> void:
	if local_host.worker and id == local_host.owner_peer:
		# poll() can emit this before the frame's state broadcast. Never send
		# another packet to the departed owner while deferred cleanup waits.
		members.erase(id)
		local_host.shutdown.call_deferred(); return
	_pending.erase(id); _sent_boards.erase(id); _views.erase(id); _budgets.erase(id); _view_budgets.erase(id); _sequences.erase(id)
	if not members.has(id): return
	var seat := int(members[id].seat)
	members.erase(id)
	if game: game.disconnect_player(seat)
	# ENet can reset several peers before poll() emits their disconnect signals.
	# Wait until every departed peer has been removed before broadcasting.
	_send_lobby.call_deferred(); _dirty = true

func _process(dt: float) -> void:
	# Networking and handshakes keep wall time at either combat speed.
	dt /= maxf(Engine.time_scale, 0.001)
	if peer == null: return
	peer.poll()
	if peer == null: return   # owner disconnect may close the worker during poll
	var connection := peer.get_connection_status()
	if not is_host:
		_elapsed += dt
		if connection == MultiplayerPeer.CONNECTION_CONNECTED and not _connected:
			_connected = true
			_loading_timeout(1)
			var hello := {"t":"hello","protocol":PROTOCOL,"version":ProjectSettings.get_setting("application/config/version"),"hash":NetStatus.world_hash(),"name":clean_name(player_name),"commander":ArenaCommanders.valid(GameData.arena_character, expansion),"expansion":expansion,"content":_expansion_hash,"password":password.left(64)}
			local_host.hello(hello)
			_send(1, hello)
		elif connection == MultiplayerPeer.CONNECTION_DISCONNECTED or (_elapsed > HELLO_TIMEOUT and my_seat < 0):
			fail("Connection to the host was lost." if started else "Could not connect to the host."); return
	var processed := 0
	while peer and peer.get_available_packet_count() > 0 and processed < 256:
		var sender := peer.get_packet_peer()
		var bytes := peer.get_packet(); processed += 1
		if bytes.size() > (MAX_PACKET if local_host.solo_combat else 4096 if is_host else MAX_PACKET): continue
		var data = bytes_to_var(bytes)
		if not data is Dictionary or not data.get("t") is String: continue
		if is_host: _from_client(sender, data)
		elif sender == 1: _from_host(data)
	# A long local shader/scene build may have queued fresh server frames.
	# Consume them before deciding the connection has gone silent.
	if not is_host and peer != null and started and Time.get_ticks_msec() - _last_frame_at > 15000:
		fail("Connection to the host was lost."); return
	if not is_host or peer == null: return
	for id: int in _pending.keys():
		if Time.get_ticks_msec() - int(_pending[id]) > HELLO_TIMEOUT * 1000:
			peer.disconnect_peer(id); _pending.erase(id)
	if game == null: return
	if local_host.solo_combat and not _solo_running: return
	_send_left -= dt; _state_left -= dt
	if _send_left > 0: return
	# A private overview has one viewer. Send one board per worker slice so
	# applying three simultaneous spell volleys cannot crowd one render frame.
	# Each board still receives ten updates per real second.
	var solo_overview := local_host.solo_combat and int(_views.get(local_host.owner_peer, 0)) < 0
	_send_left = maxf(0.0, _send_left + 0.1 / 9.0) if solo_overview else 0.1
	var delivered_seats := []
	if not local_host.solo_combat and (_dirty or _state_left <= 0):
		_dirty = false; _state_left = 0.5
		for id: int in members: _deliver(id, game.state_for(int(members[id].seat), _names()))
	for id: int in members:
		var selected := int(_views.get(id, members[id].seat))
		var seats := range(9) if selected < 0 else [selected]
		if solo_overview: seats = [_solo_view_group]
		if not _sent_boards.has(id): _sent_boards[id] = {}
		for seat: int in seats:
			if game.encounter(seat) == null: continue
			var key := game.board_key(seat)
			var full: bool = _sent_boards[id].get(seat, "") != key
			_deliver(id, game.board_frame(seat, full), full)
			_sent_boards[id][seat] = key
			if not game.events.get(seat, []).is_empty():
				_deliver(id, {"t":"effects","seat":seat,"round":game.run.wave,"generation":key,"events":game.events[seat].duplicate(true)})
			delivered_seats.append(seat)
	if solo_overview:
		# Keep the other groups' events until their snapshots are delivered.
		for seat: int in delivered_seats: game.events.erase(seat)
		_solo_view_group = (_solo_view_group + 1) % 9
	else: game.events.clear()

func _from_client(id: int, data: Dictionary) -> void:
	if data.t == "hello":
		if members.has(id) or not _pending.has(id): return
		var reason := ""
		if data.get("protocol") != PROTOCOL or data.get("version") != ProjectSettings.get_setting("application/config/version") or data.get("hash") != NetStatus.world_hash(): reason = ERRORS[0]
		elif data.get("expansion", false) != expansion or data.get("content", "") != _expansion_hash: reason = "Choose the same autochess mode. LiA autochess requires matching Lost in Astral data on every player."
		elif local_host.solo_combat and not data.has("owner"): reason = ERRORS[6]
		elif started: reason = ERRORS[1]
		elif members.size() >= 9 and not data.has("owner"): reason = ERRORS[2]
		elif data.get("password") != password.left(64): reason = ERRORS[3]
		elif data.has("owner") and not local_host.may_own(id, data.owner): reason = ERRORS[6]
		if not reason.is_empty():
			_send(id, {"t":"reject","error":reason}); return
		if not data.get("name") is String: return
		if data.has("owner"):
			local_host.claim(id)
			members[id] = members[1]; members.erase(1)
			_views.erase(1); _views[id] = 0; _pending.erase(id); _send_lobby()
			return
		var seats := members.values().map(func(member): return int(member.seat))
		var seat := 0
		while seat in seats: seat += 1
		members[id] = {"seat":seat,"name":clean_name(data.name),"ready":false,"commander":ArenaCommanders.valid(str(data.get("commander", "hero")), expansion)}
		_views[id] = seat; _pending.erase(id); _send_lobby()
		return
	if not members.has(id): return
	if local_host.packet(id, data): return
	if data.t == "view":
		if ArenaRun._integer(data.get("seat"),-1,8):
			if int(_views.get(id, -2)) != int(data.seat):
				var now := Time.get_ticks_msec()
				var budget: Dictionary = _view_budgets.get(id, {"at":now,"count":0})
				if now - int(budget.at) >= 1000: budget = {"at":now,"count":0}
				budget.count += 1; _view_budgets[id] = budget
				if budget.count > 8: return
				_views[id] = int(data.seat)
				# Solo already installed every complete frozen army at the bell.
				# Current snapshots suffice when scouting those same generations.
				if not local_host.solo_combat: _sent_boards.erase(id)
		return
	if data.t != "command" or not data.get("action") is String or not data.get("args") is Array or data.args.size() > 2 or not ArenaRun._integer(data.get("seq"),1,2147483647): return
	if int(data.seq) <= int(_sequences.get(id,0)): return
	_sequences[id] = int(data.seq)
	var now := Time.get_ticks_msec()
	var budget: Dictionary = _budgets.get(id, {"at":now,"count":0})
	if now - int(budget.at) >= 1000: budget = {"at":now,"count":0}
	budget.count += 1; _budgets[id] = budget
	if budget.count > 30: _deliver(id,{"t":"error","error":ERRORS[10]}); return
	if not started:
		if data.action == "start" and local_host.worker and id == local_host.owner_peer \
				and data.args.size() == 1 and ArenaRun._integer(data.args[0], 0, 99999999):
			var error := start_game(int(data.args[0]))
			if not error.is_empty(): _deliver(id, {"t":"error", "error":error})
		elif data.action == "ready": members[id].ready = not members[id].ready; _send_lobby()
		return
	if data.get("round") != game.run.wave:
		_deliver(id, {"t":"error","error":ERRORS[8]}); return
	if data.action in ["buy","lock"] and data.args.size() == 1 and ArenaRun._integer(data.args[0],0,5):
		var offer: Dictionary = game.run.company(int(members[id].seat)).shop[int(data.args[0])]
		if data.get("offer") != [int(offer.family),int(offer.get("rank",0))]:
			_deliver(id, {"t":"error","error":ERRORS[11]}); return
	# Rule errors are keys on the wire, translated on the receiving computer.
	var language := RemakeText.lang; RemakeText.lang = "en"
	var error := game.command(int(members[id].seat), data.action, data.args)
	RemakeText.lang = language
	if not error.is_empty(): _deliver(id, {"t":"error","error":error})
	_dirty = true

func request(action: String, args: Array = []) -> void:
	if peer == null: return
	_sequence += 1
	var data := {"t":"command","action":action,"args":args,"seq":_sequence,"round":view.wave}
	if action in ["buy","lock"] and args.size() == 1 and ArenaRun._integer(args[0],0,view.shop.size()-1):
		var offer: Dictionary = view.shop[int(args[0])]
		data["offer"] = [int(offer.family),int(offer.get("rank",0))]
	if is_host: _from_client(1,data)
	else: _send(1,data)

func start_game(seed_value := 0) -> String:
	if local_host.frontend and local_host.owned and not started:
		if members.values().any(func(member): return not member.ready): return "Wait for every player to be ready."
		request("start", [seed_value]); return ""
	if not is_host or started: return "Invalid online action."
	if members.values().any(func(member): return not member.ready): return "Wait for every player to be ready."
	started = true
	game = ArenaOnlineGame.new(); game.run.expansion = expansion; add_child(game)
	var humans := {}
	for member: Dictionary in members.values(): humans[int(member.seat)] = member.name
	game.updated.connect(func(): _dirty = true)
	game.begin(randi_range(1,99999999) if seed_value == 0 else seed_value, humans)
	for member: Dictionary in members.values():
		game.run.company(int(member.seat)).commander = ArenaCommanders.valid(str(member.get("commander", "hero")), expansion)
	var chosen := members.values().map(func(member): return ArenaCommanders.character(ArenaCommanders.valid(str(member.get("commander", "hero")), expansion)))
	var companions := (ArenaExpansion.CHARACTERS.keys() + ArenaCommanders.IDS if expansion else ArenaCommanders.IDS).filter(func(id): return id not in chosen)
	for seat in ArenaTournamentRun.PLAYER_COUNT:
		if not humans.has(seat): game.run.company(seat).commander = companions.pop_front()
	_dirty = true; _send_left = 0
	_send_lobby()
	return ""

func watch(local_seat: int) -> void:
	var server_seat := -1 if local_seat < 0 else view.seats[local_seat]
	if is_host: _views[1] = server_seat; _sent_boards.erase(1)
	else: _send(1, {"t":"view","seat":server_seat})

func _names() -> Array:
	var names := []; names.resize(9); names.fill("")
	for member: Dictionary in members.values(): names[int(member.seat)] = member.name
	return names

func _send_lobby() -> void:
	for id: int in members:
		_deliver(id, {"t":"lobby","members":members.duplicate(true),"seat":int(members[id].seat),"started":started,"expansion":expansion,"owner":local_host.worker and id == local_host.owner_peer})

func _send(id: int, data: Dictionary, reliable := true) -> void:
	if peer == null: return
	var bytes := var_to_bytes(data)
	if bytes.size() > MAX_PACKET: return
	peer.set_target_peer(id)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable or bytes.size()>1200 else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	peer.put_packet(bytes)

func _deliver(id: int, data: Dictionary, reliable := true) -> void:
	if id == 1: _from_host(data)
	else: _send(id,data,reliable)

func _from_host(data: Dictionary) -> void:
	_last_frame_at = Time.get_ticks_msec()
	match String(data.t):
		"lobby":
			members = data.members; my_seat = int(data.seat)
			local_host.welcomed(data)
			lobby_changed.emit()
		"reject": fail(String(data.error))
		"error": notice.emit(localize_error(String(data.error)))
		"state":
			var first := last_state.is_empty()
			last_state = data
			view.apply_state(data)
			started = true
			if first: match_started.emit()
		"solo_prepared": solo_prepared.emit(data)
		"solo_result": solo_result.emit(data)
		"board": board_received.emit(data)
		"effects": effects_received.emit(data)

static func localize_error(error: String) -> String:
	if error.begins_with("Collect ") and error.ends_with(" copies of this form to evolve."):
		return RemakeText.t("Collect %d copies of this form to evolve.") % int(error.get_slice(" ",1))
	return RemakeText.t(error)

func fail(reason: String) -> void:
	status = localize_error(reason)
	view.connected = false
	close()
	closed.emit(status)

func close_shown() -> void:
	var reaper := local_host.stop() if is_instance_valid(local_host) else null
	close()
	if reaper: await reaper.tree_exited

func close() -> void:
	if is_instance_valid(local_host): local_host.stop()
	if is_instance_valid(lan): lan.stop()
	if peer: peer.close(); peer = null
	if game: game.set_process(false)
	if is_instance_valid(upnp): upnp.close()

func _exit_tree() -> void: close()


func solo_packet(id: int, data: Dictionary) -> bool:
	if not local_host.solo_combat or id != local_host.owner_peer: return false
	if data.t == "solo_prepare" and data.get("snapshot") is Dictionary:
		if game == null:
			game = ArenaOnlineGame.new(); game.run.expansion = expansion; add_child(game)
			game.begin(int(data.snapshot.seed), {0:""})
		_solo_running = false; _solo_pending.clear(); _solo_view_group = 0; _send_left = 0.0; game.set_process(false)
		if not game.run.restore(data.snapshot):
			_deliver(id,{"t":"solo_prepared","round":int(data.snapshot.get("wave",0)),"error":true})
			return true
		game.battle_speed = clampi(int(data.get("speed",1)),1,2)
		game._prepare()
		var participants := game.run.alive_players()
		for player in participants:
			var battle := game.encounter(player)
			if not battle.has_meta("solo_results"):
				battle.set_meta("solo_results",true)
				battle.finished.connect(func(winner): _solo_finished(player,winner))
		game.start_round(); game.set_process(false)
		var initial := []
		for player in participants:
			initial.append(game.board_frame(player,true))
			if game.run.board_results.has(player) and not _solo_pending.any(func(result): return int(result.seat)==player):
				_solo_finished(player,int(game.run.board_results[player].winner))
		_sent_boards.clear();_sent_boards[id]={}
		for board: Dictionary in initial:_sent_boards[id][int(board.seat)]=String(board.generation)
		game.events.clear()
		_deliver(id,{"t":"solo_prepared","round":game.run.wave,"boards":initial})
		return true
	if data.t == "solo_clock" and game and data.get("round") == game.run.wave:
		_solo_running = true
		for result: Dictionary in _solo_pending: _deliver(id,result)
		_solo_pending.clear()
		game.battle_speed = clampi(int(data.get("speed",1)),1,2)
		game.set_process(not bool(data.get("paused",true)) and game.run.stage=="fight")
		return true
	return false

func _solo_finished(player: int, winner: int) -> void:
	var battle := game.encounter(player)
	var survivors := [0,0]
	for unit: GameUnit in battle.world.unit_rows():
		if not unit.dead:
			var placement: Dictionary=unit.get_meta("arena_placement",{})
			if placement.get("echo", false): continue
			survivors[int(placement.get("team",0))]+=int(placement.get("rank",0))+1
	# Full final state precedes settlement, including boards not being watched.
	var result := {"t":"solo_result","round":game.run.wave,"seat":player,
		"winner":winner,"survivors":survivors,"time":battle.world.time,"damage":battle.damage.duplicate()}
	if _solo_running:
		_deliver(local_host.owner_peer, game.board_frame(player,true))
		_deliver(local_host.owner_peer,result)
	else: _solo_pending.append(result)
	if game.run.stage != "fight": game.set_process(false)

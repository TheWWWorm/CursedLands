class_name Session
extends Node
## Runs a campaign for 1..N players.
## Host-authoritative: the host (or the single player) simulates the world,
## runs scripts and owns the campaign state. Clients send commands and receive
## the zone to load (from their own game files), unit snapshots and events.

signal players_changed
signal message(text: String)
## Client: the host sent a zone (the game view must exist before it loads).
signal zone_received
## A network character was written to its file (MpCharacter; tests).
signal mp_saved(rec: Dictionary)

const PORT := 27015
## the original: the network screen's Max Players slider 0..5 + 1 (
## default 6; hosts with it); the host counts as one.
const MAX_PLAYERS := 6
## the original: the password field is 20 bytes.
const PASSWORD_MAX := 20
const SNAP_RATE := 0.1
const SNAP_CHUNK := 8
const SNAP_BYTES := 1100    # payload budget of one snapshot packet (MTU 1392)
const LmpTravel := preload("res://src/game/lmp_travel.gd")
const TrainingRefund := preload("res://src/game/training_refund.gd")
## Characters for co-op players after the first (player 0 is the main hero).
const COOP_HEROES := ["Human Mercenary Warrior", "Human Mercenary Thief", "Human Mercenary Kania Archer", "Human Mercenary Warrior"]
## Hero prototypes a joining player may pick.
const COOP_CLASSES := ["Human Mercenary Warrior", "Human Mercenary Thief", "Human Mercenary Bodyguard",
	"Human Mercenary Shaivar", "Human Mercenary Kania Archer", "Human Mercenary Kania Thief",
	"Human Mercenary Kania Paladin", "Human Mercenary Hadagan Warrior", "Human Mercenary Hadagan Thief",
	"Human Mercenary Hadagan Rogue"]

var game: Game
var world: GameWorld
var campaign: CampaignMap
var state: CampaignState
var my_index := 0
var is_host := true
var online := false
## Transport is also used by the local single-player worker. Only this flag
## selects multiplayer gameplay rules and UI; RPC routing still uses online.
var multiplayer_game: bool:
	get: return online and (local_host == null or not local_host.single_player)
var local_host: LocalHost
## peer id -> {index, name}
var players := {1: {"index": 0, "name": "Player", "colour": 1}}
var max_players := MAX_PLAYERS   # host: this game's Max Players (host itself included)
var zone_id := ""
var _snap_t := 0.0
var _snap_count := 0
var _last_snap := {}
var _exit_t := 0.0
var _sync_t := 0.0
var _state_dirty := false
var _leave_armed := -1      # exit a deliberate ground click armed (leave-zone box, _arm_exit)
var _auto_exit := -1        # remake: exit the host party stands in (box shown / standing there on entry)
var _auto_world: GameWorld
var travel_options: Array = []   # host: destinations currently offered
var _travel_ev := {}        # host: the open global map event (for joiners)
var map_open := false       # every peer: the global map is up ("travel" until "travel_close" / a zone)
var _dialog_ev := {}        # host: the running conversation event (for joiners)
var _movie_ev := {}
var _movie_wait := {}       # peer IDs still presenting the current movie
var _movie_queue: Array[String] = []
var _movie_serial := 0
var _movie_deadline := 0
var _movie_saves := {}     # defer snapshots until presentation/dialogue handoff is complete
const MOVIE_TIMEOUT_MS := 600000   # disconnected/unresponsive presentation watchdog
var coop: CoopProgress
var net: NetStatus
var upnp: UpnpPort
## the original's own multiplayer game (LmpMode): {"base": bz1mpg.., "quest": <q>
## "pk": 0|1}; empty in the campaign (single player or the remake's co-op).
var lmp := {}
## Actual LMP only: owner-scoped base / quest worlds. Campaign co-op still
## changes its single shared world. Client generation rejects old-map packets.
var lmp_travel: RefCounted
var lmp_generation := 0
var lmp_locations := {}
## LMP: the entrance the party came into the current zone by (respawn spot).
var _lmp_entrance := 1
## Remake: what the host's Multiplayer screen is about to start — {"mode":
## "coop"} or {"mode": "lmp", "base": <base>} — told to joiners waiting in
## the lobby (a "lobby" event), so a joiner who picked the other kind of game
## is shown what the host runs. Empty until known.
var lobby_mode := {}
## Host: the game's password ("" none; the original keeps at most 20
## characters, refused joins get «lmp_wrong_password», NetStatus.refuse).
var password := ""
## Joiner: the password it joins with (the join page's Password row).
var join_password := ""
## Host: the port it hosts on (the LAN game list tells joiners).
var host_port := PORT
## Host: answers the LAN game list's queries (LanDiscovery).
var lan: LanDiscovery
## Remake: optional public directory; the default configuration is private.
var directory: Node
## The original multiplayer game's player swap (PlayerSwap; also the remake's co-op).
var swap: PlayerSwap
## Remake co-op clock, owned by the host. Kept separate from local menu
## pauses so a client's menu never changes another player's simulation.
var clock_paused := false
var clock_speed := 0
var host_clock := false
## A host save-load or campaign transfer is a reliable transaction: clients stop issuing orders
## and present their loading screen before the host rebuilds the world.
var loading_game := false
var _load_serial := 0
## Pool events need the host's epoch even for a join after a finished load.
## This wire fence is separate from the client's local load transaction.
var _pool_epoch := -1
var _load_waiting := {}
var _remote_loading := false
var _remote_load_end_serial := -1
var _loading_world_mode := Node.PROCESS_MODE_PAUSABLE
var _loading_zone_id := ""
## Monotonic water-state revisions across zone changes and same-zone reloads.
var _water_seq := 0
var _water_received := -1


func _ready() -> void:
	name = "Session"
	process_mode = Node.PROCESS_MODE_ALWAYS   # RPC / status remain live at a shared pause
	campaign = CampaignMap.load_from(GameData.texts)
	campaign.load_lmp()   # the original multiplayer maps (LmpMode)
	state = CampaignState.new()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Remake co-op: a brought hero and the joiner's own progress (CoopProgress).
	coop = CoopProgress.new()
	coop.name = "CoopProgress"
	coop.session = self
	add_child(coop)
	# Player status, chat, join / leave lines (NetStatus).
	net = NetStatus.new()
	net.name = "NetStatus"
	net.session = self
	add_child(net)
	# Router port forwarding for the host (remake option net_upnp, UpnpPort).
	upnp = UpnpPort.new()
	upnp.name = "UpnpPort"
	add_child(upnp)
	upnp.finished.connect(func(_ok, text): message.emit(text))
	lan = LanDiscovery.new()
	lan.name = "LanDiscovery"
	lan.session = self
	add_child(lan)
	directory = preload("res://src/game/internet_directory.gd").new()
	directory.name = "InternetDirectory"
	directory.session = self
	add_child(directory)
	swap = PlayerSwap.new()
	swap.name = "PlayerSwap"
	swap.session = self
	add_child(swap)
	local_host = LocalHost.new()
	local_host.name = "LocalHost"
	local_host.session = self
	add_child(local_host)
	multiplayer.connected_to_server.connect(func():
		_relax_timeout(1)   # the client's own zone builds stall as long as the host's
		if not local_host.frontend:
			coop.client_hello()
		_send_mp_char()
		if local_host.frontend:
			local_host.hello()
			return
		_rpc_hello.rpc_id(1, GameData.player_name, GameData.hero_class, NetStatus.PROTOCOL, NetStatus.world_hash(), join_password))
	multiplayer.server_disconnected.connect(func():
		_cancel_movie()
		_cancel_remote_load()
		_apply_clock(false, 0)
		var t := net.server_lost_text()
		if t:
			message.emit(t))
	GameData.options_changed.connect(_clock_options_changed)


## Movie completion belongs to presentation, not simulation time. RPCs and
## this watchdog remain live while the world/clock is paused or loading.
func movie_active() -> bool:
	return not _movie_ev.is_empty()


func _movie_ack(pid: int, serial: int) -> void:
	if not is_host or serial != int(_movie_ev.get("serial", -1)):
		return
	_movie_wait.erase(pid)
	if _movie_wait.is_empty(): _release_movie()


func _process(_dt: float) -> void:
	if not is_host or not movie_active(): return
	for pid in _movie_wait.keys():
		if int(pid) != 1 and (not online or not players.has(pid) or not CoopProgress.peer_alive(multiplayer, int(pid))):
			_movie_wait.erase(pid)
	if _movie_wait.is_empty() or Time.get_ticks_msec() >= _movie_deadline:
		_release_movie()


func _release_movie() -> void:
	if not movie_active(): return
	var serial := int(_movie_ev.serial)
	_movie_wait.clear()
	broadcast({"t":"movie_release", "serial":serial})
	_movie_ev = {}
	if not _movie_queue.is_empty():
		broadcast({"t":"movie", "name":_movie_queue.pop_front()})
	else:
		var saves := _movie_saves
		_movie_saves = {}
		for slot: String in saves:
			save_game.call_deferred(slot, saves[slot][0], saves[slot][1])


func _cancel_movie() -> void:
	_movie_queue.clear()
	_movie_saves.clear()
	if is_host:
		_release_movie()
	elif movie_active():
		_on_event({"t":"movie_release", "serial":int(_movie_ev.serial)})
	_movie_wait.clear()


# ------------------------------------------------------------------ setup

## Presentation ownership is independent of simulation authority on desktop.
func can_manage_game() -> bool:
	return is_host or (local_host != null and local_host.frontend)


func host_player_id() -> int:
	var pid := _pid_of(0)
	return pid if pid > 0 else 1


func start_host(port := PORT, limit := MAX_PLAYERS) -> Error:
	if LocalHost.available():
		return await local_host.start(port, limit)
	return host(port, limit)


func _start_single_if_needed() -> Error:
	if online or local_host.worker or not lmp.is_empty() or not LocalHost.available():
		return OK
	var error := await local_host.start(0, 1, true)
	if error != OK:
		is_host = true
		if error != ERR_SKIP:
			GameData.trace("Single-player worker unavailable (%d); using inline simulation" % error)
	return error


func host(port := PORT, limit := MAX_PLAYERS) -> Error:
	if OS.has_feature("web"):
		return ERR_UNAVAILABLE
	var solo := local_host.single_player
	var socket_mode := not solo and GameData.option("net_websocket") != 0
	var peer: MultiplayerPeer = _websocket_peer() if socket_mode else ENetMultiplayerPeer.new()
	# Remake: "*" listens on IPv4 and IPv6 at once (a dual-stack socket), so
	# friends can join by "[IPv6 address]:port" too (often reachable without
	# any port forwarding).
	if peer is ENetMultiplayerPeer:
		peer.set_bind_ip("127.0.0.1" if solo else "*")
	# ENet takes one connection more than the game has room for, so a joiner
	# beyond Max Players hears "server full" (NetStatus.refusal) instead of
	# a silent timeout.
	max_players = clampi(limit, 1, MAX_PLAYERS)
	var err: Error = peer.create_server(port) if socket_mode else peer.create_server(port, max_players + (1 if local_host.worker else 0))
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer if socket_mode else NetSim.wrap(peer)   # (tools: --netsim)
	online = true
	is_host = true
	if not solo and not socket_mode and GameData.option("net_upnp") == 1 and not Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--tool=")):
		upnp.open(port)
	my_index = 0
	players = {1: {"index": 0, "name": GameData.player_name, "colour": 1}}
	host_port = peer.get_host().get_local_port() if peer is ENetMultiplayerPeer else port
	password = password.left(PASSWORD_MAX)
	if not solo:
		lan.listen()   # the LAN game list (LanDiscovery)
		directory.reload_settings()
	_clock_options_changed()
	return OK


## Host: what the LAN game list shows of this game (LanDiscovery; the original's
## server record: name, base, quest, players, max, password).
func lan_info() -> Dictionary:
	var mode := "lmp" if not lmp.is_empty() or String(lobby_mode.get("mode", "")) == "lmp" else "coop"
	return {"name": String(players.get(host_player_id(), {}).get("name", GameData.player_name)), "mode": mode,
		"base": String(lmp.get("base", lobby_mode.get("base", ""))) if mode == "lmp" else "",
		"quest": String(lmp.get("quest", "")), "players": players.size(), "max": max_players,
		"pw": password != "", "ws": multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,
		"port": host_port, "in_game": world != null}


## Host, before the game starts: what it is about to start (lobby_mode),
## told to every joiner already connected.
func set_lobby_mode(mode: Dictionary) -> void:
	lobby_mode = mode
	if local_host.frontend:
		local_host.request("lobby", mode)
		return
	if online and is_host and world == null:
		_rpc_event.rpc({"t": "lobby", "mode": mode})


## Remake: a typed address to [host, port]: "host", "host:port", an IPv6
## literal "2001:db8::1" (no port) or "[2001:db8::1]:port" / "[::1]".
static func parse_address(text: String, default_port := PORT) -> Array:
	var a := text.strip_edges()
	if a.begins_with("ws://") or a.begins_with("wss://"):
		return [a, default_port]
	var p := default_port
	if a.begins_with("["):
		var close := a.find("]")
		if close > 0:
			var rest := a.substr(close + 1)
			a = a.substr(1, close - 1)
			if rest.begins_with(":") and rest.substr(1).is_valid_int():
				p = rest.substr(1).to_int()
	elif a.count(":") == 1 and a.get_slice(":", 1).is_valid_int():
		p = a.get_slice(":", 1).to_int()
		a = a.get_slice(":", 0)
	return [a, p]


func join(address: String, port := PORT) -> Error:
	var socket_mode := address.begins_with("ws://") or address.begins_with("wss://")
	if OS.has_feature("web") and not socket_mode:
		return ERR_INVALID_PARAMETER
	var peer: MultiplayerPeer = _websocket_peer() if socket_mode else ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address) if socket_mode else peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer if socket_mode else NetSim.wrap(peer)   # (tools: --netsim)
	online = true
	is_host = false
	_water_received = -1
	_pool_epoch = -1
	return OK


static func _websocket_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 16777216
	peer.outbound_buffer_size = 16777216
	peer.max_queued_packets = 4096
	peer.handshake_timeout = 30.0
	return peer


# ------------------------------------------------------------------ remake co-op clock

func coop_clock_enabled() -> bool:
	return multiplayer_game and lmp.is_empty() and (GameData.option("coop_clock") == 1 if is_host else host_clock)


func _clock_options_changed() -> void:
	if not multiplayer_game or not is_host:
		return
	host_clock = lmp.is_empty() and GameData.option("coop_clock") == 1
	if not host_clock:
		_apply_clock(false, 0)
	_send_clock()


func set_coop_clock(sector: int) -> void:
	if local_host.frontend:
		local_host.request("clock", {"sector": sector})
		return
	if not is_host or not coop_clock_enabled() or loading_game or map_open or world == null:
		return
	if sector == 0:
		_apply_clock(not clock_paused, clock_speed)
	elif sector in [1, 2]:
		_apply_clock(false, sector - 1)
	else:
		return
	_send_clock()


func reset_coop_clock() -> void:
	if is_host:
		_apply_clock(false, 0)
		_send_clock()
	else:
		_apply_clock(clock_paused, clock_speed)


func _apply_clock(paused: bool, rate: int) -> void:
	clock_paused = paused
	clock_speed = clampi(rate, 0, 1)
	if game:
		game.speed = clock_speed
	Engine.time_scale = 2.0 if clock_speed == 1 else 1.0
	get_tree().paused = clock_paused


func _send_clock(pid := 0) -> void:
	if not multiplayer_game or not is_host:
		return
	for peer in ([pid] if pid else players.keys()):
		if int(peer) != 1 and CoopProgress.peer_alive(multiplayer, int(peer)):
			_rpc_clock.rpc_id(int(peer), coop_clock_enabled(), clock_paused, clock_speed)


@rpc("authority", "call_remote", "reliable")
func _rpc_clock(enabled: bool, paused: bool, rate: int) -> void:
	if local_host.single_player:
		return
	host_clock = enabled
	_apply_clock(paused if enabled else false, rate if enabled else 0)


## the original: "new game" (message) plays Movies\Intro.bik
## (modal) and then starts the game. The single
## player menu plays it before calling this with `intro` false; otherwise
## (co-op, **approx.**) every peer sees it once the first zone is built.
func new_campaign(intro := true) -> void:
	if await _start_single_if_needed() == ERR_SKIP:
		return
	if local_host.frontend:
		await local_host.request("campaign", {"intro": intro})
		return
	_clear_lmp_worlds()
	if not lmp.is_empty():
		lmp = {}
		GameData.use_lmp_database(false)
		Shops.network = false
	swap.cancel_all()
	state = CampaignState.new()
	coop.campaign_started()
	for pid in players:
		state.ensure_hero(players[pid].index, _hero_proto(players[pid].index), String(players[pid].name))
	await enter_zone("gz1g", 1)
	if intro:
		broadcast({"t": "movie", "name": "intro"})


## Host: starts the original's own multiplayer game (LmpMode) on `base`: every
## peer switches to res/databaseLMP.res, each player gets a network hero with
## its own purse and bag (CoopProgress.lmp_purses) and the party starts in the
## base at its entrance 1, where the quest giver offers the base's quests
## (SideQuests.lmp_offer, as a new server's). `quest` (tests)
## takes that quest straight away.
func new_lmp_game(base: String, quest := "", pk := 0) -> bool:
	if not LmpMode.available() or not lmp_characters_ready():
		return false
	base = base.to_lower()
	quest = quest.to_lower()
	if not base in LmpMode.BASES or (quest and not LmpMode.quests_of(campaign, base).has(quest)):
		message.emit(RemakeText.t("Unknown zone ") + base + "/" + quest)
		return false
	if not GameData.use_lmp_database(true):
		message.emit(RemakeText.t("Unknown zone ") + base)
		return false
	_clear_lmp_worlds()
	swap.cancel_all()
	lmp = {"base": base, "quest": "", "last": "", "topics": [], "pk": pk}
	mp_file = MpCharacter.selected_file()   # the host plays its own selected character
	coop.joiners.clear()   # brought campaign heroes have no part in it
	coop.lmp_purses.clear()
	if online:
		_rpc_lmp.rpc(lmp)
	Shops.network = true   # the network shop table
	state = CampaignState.new()
	for pid in players:
		var idx := int(players[pid].index)
		coop.with_purse(idx, _ensure_lmp_hero.bind(idx, String(players[pid].name)))
	LmpMode.base_vars(state, base)
	_enter_zone(base, 1)   # (web / mobile: the menu holds the loading screen first)
	if quest:
		SideQuests.take_lmp(self, quest)
	else:
		SideQuests.lmp_offer(self)
	return true


## the original multiplayer game requires a selected network
## character. Check the whole lobby before replacing its campaign state;
## campaign co-op still creates its ordinary class heroes independently.
func lmp_characters_ready() -> bool:
	if not is_host:
		return false
	for pid in players:
		var data := _lmp_character(int(pid))
		if MpCharacter.accept(data).is_empty():
			var p: Dictionary = players[pid]
			message.emit(NetStatus.lmp_text("lmp_no_pers", "", "No character selected") + ": " + String(p.name))
			return false
	return true


func _lmp_character(pid: int) -> Dictionary:
	return MpCharacter.current() if pid == 1 else _mp_pending.get(pid, {})


## The connection (peer id) of player slot `idx` now, 0 = none.
func _pid_of(idx: int) -> int:
	for pid in players:
		if int(players[pid].index) == idx:
			return int(pid)
	return 0


## LMP: a player's network hero — its network character (MpCharacter: the
## host's own selected one, a client's sent on connecting, `_rpc_mp_char`)
## with its money and bag in the player's purse (runs inside
## CoopProgress.with_purse). The server takes the character as the original's
## message 8 handler does: exactly one hero record, nothing else
## checked (MpCharacter.accept, which also makes the record safe for the
## remake). A missing or refused record cannot create a substitute hero.
func _ensure_lmp_hero(idx: int, _player_name: String) -> bool:
	if state.heroes.has(idx):
		return true
	var pid := _pid_of(idx)
	var sent := _lmp_character(pid)
	var rec := MpCharacter.accept(sent) if not sent.is_empty() else {}
	if not rec.is_empty():
		state.heroes[idx] = [rec.heroes[0]]
		state.money = int(rec.money)
		state.items.clear()
		state.items.append_array(rec.items)
		CampaignState.cap_belt(rec.heroes[0], state.items)
		_mp_resend[idx] = _mp_resend_delay()
		_mp_camp[idx] = 0.0   # the login reply's 0x80
		return true
	return false


# ---------------------------------------------------------------- network characters
# the original: the client sends its character with message 8 on connecting
# (: the local party); the server keeps it by the
# player's key and sends the party back (message 0x80
# ) at the login reply, every zone change
# after a respawn, on entering a trader
# (message 4) and every 900 + rand % 901 ticks while the player
# is on the map out of danger (about 50–99 s)
# the client writes each one to its file (
# ), and again when it leaves a trader. The server
# never writes a file.

var _mp_pending := {}   # host: peer id -> the character it sent (checked when used)
var _mp_resend := {}    # host: player slot -> seconds to the periodic resend
var _mp_camp := {}      # host: player slot -> deferred login / respawn send outside a purse swap
## Client / host: the file of the character this player plays ("" none).
var mp_file := ""


static func _mp_resend_delay() -> float:
	return float(900 + randi() % 901) * GameUnit.TICK


## Client, on connecting: its selected network character (message 8).
func _send_mp_char() -> void:
	mp_file = MpCharacter.selected_file()
	var data := MpCharacter.current()
	if not data.is_empty():
		_rpc_mp_char.rpc_id(1, data)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_mp_char(data: Dictionary) -> void:
	if not is_host:
		return
	if var_to_bytes(data).size() > 262144:
		return
	_mp_pending[multiplayer.get_remote_sender_id()] = data


## Host: player `idx`'s party (its hero and purse) to its client (0x80); the
## host's own straight to its file.
func _mp_send(idx: int) -> void:
	if lmp.is_empty() or not state.heroes.has(idx) or (state.heroes[idx] as Array).is_empty():
		return
	_mp_resend[idx] = _mp_resend_delay()
	var h: Dictionary = state.heroes[idx][0]
	var e := coop.purse_entry(idx)
	var rec := MpCharacter.record(h, int(e.purse.money) if not e.is_empty() else state.money,
		e.purse.get("items", []) if not e.is_empty() else state.items)
	if idx == 0 and not local_host.worker:
		_mp_save(rec)
		return
	var pid := _pid_of(idx)
	if pid > 0 and online:
		_rpc_mp_party.rpc_id(pid, rec)


## Client: the server's copy of its party, written to its character's file
@rpc("authority", "call_remote", "reliable")
func _rpc_mp_party(rec: Dictionary) -> void:
	_mp_save(rec)


func _mp_save(rec: Dictionary) -> void:
	if mp_file.is_empty() or lmp.is_empty() or not MpCharacter.one_hero(rec):
		return
	MpCharacter.save_file(mp_file, rec)
	mp_saved.emit(rec)


## Host, every frame: pending and periodic sends.
func _mp_tick(dt: float) -> void:
	if lmp.is_empty() or world == null or coop.purse_active():
		return
	for idx in _mp_camp.keys():
		_mp_camp[idx] = float(_mp_camp[idx]) - dt
		if float(_mp_camp[idx]) <= 0.0:
			_mp_camp.erase(idx)
			_mp_send(int(idx))
	#  decrements only on a game map (= 1). An
	# overdue counter stays overdue while danger flag is nonzero.
	if not lmp_travel and shop_available():
		return
	for idx in _mp_resend.keys():
		if lmp_travel:
			var w: GameWorld = lmp_travel.owner_world(int(idx))
			if w == null or String(w.zone.get("type", "")) == "brief":
				continue
		_mp_resend[idx] = float(_mp_resend[idx]) - dt
		var safe := false
		if float(_mp_resend[idx]) <= 0.0:
			safe = bool(lmp_travel.with_world(lmp_travel.owner_world(int(idx)), _mp_safe.bind(int(idx)))) \
				if lmp_travel else _mp_safe(int(idx))
		if safe:
			_mp_send(int(idx))


func _mp_safe(player: int) -> bool:
	var sound := GameSound.instance
	if sound and sound._world == world:
		return sound.player_combat_flag(player) == 0
	# A dedicated/headless server has no Game audio node, but uses the same
	# native detection/attack predicate. This probe never enters the scene tree.
	var probe := GameSound.new()
	probe._world = world
	var safe := probe.player_combat_flag(player) == 0
	probe.free()
	return safe


## Every peer: the multiplayer game's settings; a client switches to the
## multiplayer database before the first zone comes (same channel, in order)
## and sends its table digests again (CoopDb, NetStatus).
@rpc("authority", "call_remote", "reliable")
func _rpc_lmp(settings: Dictionary) -> void:
	lmp = settings
	GameData.use_lmp_database(not lmp.is_empty())
	Shops.network = not lmp.is_empty()
	net.send_db_digests()


func _clear_lmp_worlds() -> void:
	if lmp_travel:
		for ctx: Dictionary in lmp_travel.contexts.values():
			var w: GameWorld = ctx.get("world")
			if w and w != world:
				w.queue_free()
		lmp_travel.session = null
		lmp_travel = null
	lmp_locations.clear()
	lmp_generation = 0


## Authoritative location, never a client-supplied zone lookup.
func player_zone(player: int) -> String:
	if lmp_travel:
		return lmp_travel.zone_of(player)
	if not lmp.is_empty() and lmp_locations.has(player):
		return String(lmp_locations[player].get("zone", ""))
	return zone_id


func players_same_zone(a: int, b: int) -> bool:
	if lmp.is_empty():
		return true
	if lmp_travel:
		return lmp_travel.same_place(a, b)
	return not player_zone(a).is_empty() and player_zone(a) == player_zone(b) \
		and not bool(lmp_locations.get(a, {}).get("loading", false)) \
		and not bool(lmp_locations.get(b, {}).get("loading", false))


## Leaving the multiplayer game (back to the menu): the campaign database again.
func _exit_tree() -> void:
	if lmp_travel:
		lmp_travel.session = null
		lmp_travel = null
	if not lmp.is_empty():
		lmp = {}
		GameData.use_lmp_database(false)
		Shops.network = false


## Campaign mods need not contain the original mercenary prototypes. Offer
## only characters from the active database; LiA's fallback is its native Kir.
static func coop_classes() -> Array:
	if not GameData.is_open():
		return COOP_CLASSES.duplicate()
	var choices := COOP_CLASSES.filter(func(proto: String): return not GameData.db.find("monster_prototypes", proto).is_empty())
	return choices if not choices.is_empty() else ["Human Hero"]


func _hero_proto(index: int) -> String:
	if index == 0:
		return "Human Hero"
	var choices := coop_classes()
	for p in players.values():
		if int(p.index) == index and String(p.get("hero", "")) in choices:
			return String(p.hero)
	var fallback: String = COOP_HEROES[(index - 1) % COOP_HEROES.size()]
	return fallback if fallback in choices else String(choices[0])


# ------------------------------------------------------------------ quest items

## An item added to the currently active purse. Native LMP keeps quest-item
## copies in the owner's ordinary bag (player); campaign
## co-op retains its shared story-item list.
func add_item(id: String, n := 1) -> void:
	if lmp.is_empty():
		state.add_item(id, n)
	else:
		for k in n:
			state.items.append(id)
	mark_dirty()


## Script GiveItem/GiveQuestItem names an owner explicitly in native LMP.
func give_item(player: int, id: String, n := 1) -> void:
	if lmp.is_empty():
		coop.with_purse(-1, add_item.bind(id, n), true)
	else:
		var bag := coop.owner_bag(player)
		for k in n:
			bag.append(id)
		mark_dirty()


static func _quest_item_key(id: String) -> String:
	return String(Items.info(id).row.get("name", id)).strip_edges().to_lower()


##  searches that player's bag, then the carried quest items
##  of its controlled units. A traded/escrowed item is absent
## the bag until it is received or refunded.
func have_quest_item(player: int, name: String) -> bool:
	var key := _quest_item_key(name)
	if lmp.is_empty():
		return state.quest_items.has(key)
	for it: String in coop.owner_bag(player):
		if Items.kind(it) == "quest" and _quest_item_key(it) == key:
			return true
	if world:
		for u: GameUnit in world.units.values():
			if not is_instance_valid(u) or u.controller != player:
				continue
			# Rolled pockets contain the remaining carried copies after theft;
			# info.quest_items is the map's original description.
			var carried = u.get_meta("pockets") if u.has_meta("pockets") else u.info.get("quest_items", [])
			for it in carried:
				if _quest_item_key(String(Items.parse_stack(String(it))[0])) == key:
					return true
	return false


##  removes only the first matching 0x3009 item in the player's
## bag. It does not erase a second identical copy or a unit's carried list.
func erase_quest_item(player: int, name: String) -> bool:
	var key := _quest_item_key(name)
	if lmp.is_empty():
		var removed := state.quest_items.erase(key)
		if removed:
			mark_dirty()
		return removed
	var bag := coop.owner_bag(player)
	for i in bag.size():
		if Items.kind(String(bag[i])) == "quest" and _quest_item_key(String(bag[i])) == key:
			bag.remove_at(i)
			mark_dirty()
			return true
	return false


# ------------------------------------------------------------------ zones

## Host: load a zone and deploy all players' parties at an entrance. Web /
## mobile: the loading screen is put on screen first (LoadingScreen.hold),
## before anything changes; elsewhere it returns with the zone loaded.
func enter_zone(id: String, entrance: int, autosave := true) -> void:
	if loading_game:
		return
	if lmp.is_empty() and world != null and zone_exists(id) and campaign.zone(id).has("mpr"):
		_begin_host_load(id, false)
		await _complete_zone_travel(id, entrance, _load_serial, autosave)
		return
	if LoadingScreen.deferred() and zone_exists(id):
		await LoadingScreen.hold(get_tree(), campaign.zone(id), LoadingScreen.SAVED_ZONE if state.zones.has(id) else LoadingScreen.NEW_ZONE)
	_enter_zone(id, entrance, autosave)


## The old world is frozen before this coroutine yields. In particular, a
## dialogue completion must unwind its guest-purse scope before rebuilding.
func _complete_zone_travel(id: String, entrance: int, serial: int, autosave := true) -> void:
	await _wait_load_clients()
	if not loading_game or serial != _load_serial:
		return
	if LoadingScreen.deferred():
		await LoadingScreen.hold(get_tree(), campaign.zone(id), LoadingScreen.SAVED_ZONE if state.zones.has(id) else LoadingScreen.NEW_ZONE)
	_enter_zone(id, entrance, autosave)
	_finish_host_load()


## Host: enter_zone without waiting for the loading screen (callers that need
## the zone at once; on web / mobile they hold it first themselves).
func _enter_zone(id: String, entrance: int, autosave := true) -> void:
	if lmp_travel:
		lmp_travel.request(0, id, entrance)
		return
	var z := campaign.zone(id)
	if z.is_empty() or not z.has("mpr") or not zone_exists(id):
		message.emit(RemakeText.t("Unknown zone ") + id)
		return
	swap.cancel_all()
	if world and zone_id and (not lmp.is_empty() or multiplayer_game):
		# a player whose hero is dead (or gone) when it is sent to
		# another zone is respawned first (player =).
		# Remake co-op: the same at a zone change, with the option "revive"
		# (no timed respawn, hero_died) and without it (the 5 s respawn timer
		# still pending belongs to the zone left: before, such a hero entered
		# the next zone standing, at full health and without the toll).
		for u: GameUnit in world.units.values().duplicate():
			if u.dead and u.controller >= 0 and u.has_meta("hero") and not u.get_meta("hero").has("merc"):
				coop.with_purse(u.controller, respawn.bind(u))   # its own purse and bag
	if world and zone_id:
		if String(world.zone.get("type", "game")) != "brief":
			state.store_follow(world)   # record, game zones only
		state.store_party_positions(world)
		state.collect_pets(world)
		state.store_zone(zone_id, world)
	travel_options = []
	_leave_armed = -1
	_dialog_ev = {}
	_travel_ev = {}
	map_open = false
	zone_id = id
	_last_snap.clear()
	z = _zone_variant(z)
	_movie_on_enter(id)
	GameData.trace("zone load %s (entrance %d)" % [id, entrance])
	# A zone already in the campaign state loads like a save (
	# LoadSave): its loading screen also shows frames 1 and 5.
	LoadingScreen.begin(get_tree(), z, LoadingScreen.SAVED_ZONE if state.zones.has(id) else LoadingScreen.NEW_ZONE)
	_build_world(z, true)
	# Belt items come into a zone full: the party's units are made anew from
	# the hero records with each belt item's = (the
	# records' copies are refilled as well when the units are written back,
	# ). Weapons and armour go through the plain
	# copy (world), which keeps, so
	# their charge carries over and never refills.
	for k in state.heroes:
		for h: Dictionary in state.heroes[k]:
			var q = h.get("quick", [])
			for qi in q.size():
				q[qi] = Items.with_charge(q[qi], Items.energy(q[qi]))
	_deploy_parties(z, entrance)
	if not _restoring and String(z.get("type", "game")) != "brief":
		state.apply_follow(world)   # the records' follow targets, mode 1 only
	LoadingScreen.step(8)
	state.visited[id] = true
	_lmp_entrance = entrance
	if lmp.is_empty():
		coop.zone_entered(id)
	world.vm = ScriptVM.create(world, self)
	LoadingScreen.step(9)
	_start_zone_revisit(id)
	_start_pose(z, entrance)
	_replay_local()
	if not lmp.is_empty() and lmp_travel == null:
		lmp_travel = LmpTravel.new(self)
		lmp_travel.adopt()
	if not _restoring:
		_publish_zone()
		state.replay_restored(world)   # restored units' effect visuals, lasting ground spells
		sync_state()
	# the original runs the "autosave" command shortly after a zone has
	# loaded (10th frame); the Autosave option switches it off.
	if autosave and is_host and GameData.option("autosave") and lmp.is_empty():
		save_game.call_deferred("autosave")
	LoadingScreen.step(10)
	ShaderWarmup.run(game)
	LoadingScreen.end()
	if not lmp.is_empty():
		#  (mode 2): every player's party goes to its client
		# (message 0x80), which saves it.
		for k in state.heroes:
			_mp_send(int(k))
	GameData.trace("zone ready %s" % id)


## Save loads publish only after the saved party positions / body state
## have been restored, so reliable load-end never uncovers entrance poses.
func _publish_zone() -> void:
	if world and world.authority:
		world.nav.prepare_static_navigation(world.unit_rows())
	local_host.publishing_zone()
	if online and is_host:
		if lmp_travel:
			lmp_travel.publish()
			return
		_rpc_zone.rpc(zone_id, _unit_records(), world.diplomacy, _extra_mobs(),
			String(world.zone.get("mpr", "")), _lever_states(), _load_serial)
		_send_world_state(0)


## the original (party deployment) builds a WorldScript for the
## heroes; on map "zone1" with the deploy point within sqrt(300) m of
## (54, 138) (squared 3D distance < 300) and game state != 2 it appends
## PlayAnimation(GetObjectByName("hero"), "uspecial25"): Zak wakes up lying on
## the ruins' floor at the campaign start. Only the unit named "hero" (player
## 0's Zak), also in co-op. == 2 is the native LMP-host mode
## ((2)), so LMP omits this campaign clip.
## Saved-world restoration does not rerun its deployment WorldScript.
var _restoring := false


func _start_pose(z: Dictionary, entrance: int) -> void:
	if not _restoring and game and game.rig:
		game.rig.village_start_view(z)
	if _restoring or not lmp.is_empty() or String(z.get("mpr", "")).to_lower() != "zone1":
		return
	var rect: Rect2 = z.exits.get(entrance, {}).get("deploy", Rect2())
	if rect.get_center().distance_squared_to(Vector2(54, 138)) >= 300.0:
		return
	for u: GameUnit in world.units.values():
		if u.controller == 0 and u.has_meta("hero") and not u.get_meta("hero").has("merc"):
			u.command({"type": "anim", "name": "uspecial25"})
			return


func _build_world(z: Dictionary, authority: bool, attach := true) -> void:
	var w := GameWorld.new()
	w.name = "World"
	w.zone = z
	w.authority = authority
	w.session = self
	w.presentation = not local_host.worker
	w.retain_logic_debt = local_host.worker
	_building = true   # NetStatus.keep_alive polls the network meanwhile
	w.load_map(z.mpr, z.get("mob", z.mpr), authority)
	if String(z.get("id", "")) == ENDING_ZONE:   # the end credits' movies, ahead of time
		MoviePlayer.preconvert(Array(MoviePlayer.ini_movies("Crdtfin")) + ["crdt"]
			+ Array(MoviePlayer.ini_movies("Crdtfout")))
	if authority:
		# LMP: a quest zone is the zone's .mpr with its -LMP .mob plus the
		# quest map's own <q>.mob (units, objects and script merged).
		var sq := (zone_id if bool(z.get("lmp", false)) and z.get("type", "") == "game" else "") \
			if not lmp.is_empty() else SideQuests.active_in(self, zone_id)
		if sq:
			SideQuests.spawn_units(w, sq)
		state.restore_zone(zone_id, w)
		w.item_worn.connect(_on_item_worn)
	LoadingScreen.step(6)
	EIAcks.prepare()
	world = w
	if attach:
		game.attach_world(w)
	else:
		w.visible = false
		w.process_mode = Node.PROCESS_MODE_PAUSABLE
		game.add_child(w)
	LoadingScreen.step(7)
	if w.presentation and w.terrain and w.terrain.details:
		w.terrain.details.prepare_grass()
	w.prepare_animation_bindings()
	_building = false


## True while _build_world runs (NetStatus.keep_alive).
var _building := false

const ENDING_ZONE := "gz20g"
const ENDING_UNIT := 666666


## Host: an equipped item broke (Combat.wear_item): the hero says so (ack 0x23
## armour / 0x24 weapon) and the item goes to the bag, where it waits for a
## repair in camp (tutorial it012). Crossing the critical level (codes 0x25 /
## 0x26) is acked by GameSound: no voice lines in acks.db, the
## sound is "weapons\timecrash.wav".
func _on_item_worn(u: GameUnit, item: String, kind: String) -> void:
	if not kind.begins_with("broken") or not u.has_meta("hero"):
		return
	var h: Dictionary = u.get_meta("hero")
	for k in ["weapons", "armors"]:
		var i: int = h[k].find(item)
		if i >= 0:
			h[k].remove_at(i)
			coop.bag_of(u.controller).append(item)
			notify_got(u.controller, [item], 0, true)   # flag 1
	u.ack(EIAcks.WEAPON_BROKEN if kind == "broken_weapon" else EIAcks.ARMOR_BROKEN)
	_refresh_hero(u)


func _deploy_parties(z: Dictionary, entrance: int) -> void:
	world.set_meta("pet_party", state.pet_party())
	var exit: Dictionary = z.exits.get(entrance, {})
	var rect: Rect2 = exit.get("deploy", Rect2(world.terrain.size_ei() * 0.5, Vector2(4, 4)))
	var view := deg_to_rad(float(exit.get("view", 0.0)))
	var slot := 0
	for pid in players:
		var idx: int = players[pid].index
		if lmp.is_empty():
			coop.GuestRoles.ensure(self, idx)
			preload("res://src/game/script/camp_grants.gd").catch_up(state, idx)
		for rec: Dictionary in state.party_records(idx):
			var p := rect.get_center() + Vector2(slot % 3 - 1, slot / 3) * 1.5
			p = world.nav.nearest_walkable(p)
			rec.position = Vector3(p.x, p.y, 0)
			rec.nid = world.new_uid()
			var u := world.spawn_unit(rec)
			if u:
				u.controller = idx
				u.faction = 0
				u.mode = "player"
				u.facing = view
				state.apply_hero(u)
			slot += 1
	for n in state.mercs.keys():
		var m: Dictionary = state.mercs[n]
		if not state.merc_party_active(m):
			continue   # waiting with the party in which this companion was hired
		if m.get("travel_waiting", false) and String(m.get("travel_waiting_zone", "")) == String(z.get("id", "")):
			continue   # a save in the farewell must still satisfy its empty-party gate
		if m.get("fallen", false) and not _restoring:
			# Remake option "revive": a mercenary that died in the zone left
			# behind is gone, as in the original (GameWorld.on_death). A loaded
			# save brings its body back (CampaignState.restore_party_positions).
			state.mercs.erase(n)
			continue
		if state.get_var(0, "adeadn%d" % n) >= 1.0 and not m.get("fallen", false):
			continue
		var p := world.nav.nearest_walkable(rect.get_center() + Vector2(slot % 3 - 1, slot / 3) * 1.5)
		slot += 1
		_spawn_merc(m, p, view, true)
	for pet: Dictionary in state.pets:
		if not state.pet_party_active(pet):
			continue
		var p := world.nav.nearest_walkable(rect.get_center() + Vector2(slot % 3 - 1, slot / 3) * 1.5)
		slot += 1
		_spawn_pet(pet, p, view)
	game.attach_world(world)


func _spawn_pet(pet: Dictionary, p: Vector2, facing := 0.0) -> GameUnit:
	var rec: Dictionary = pet.rec.duplicate()
	rec.position = Vector3(p.x, p.y, 0)
	rec.nid = world.new_uid()
	var u := world.spawn_unit(rec)
	if u:
		u.controller = int(pet.controller) if players_include(int(pet.controller)) else _merc_owner()
		if u.controller != int(pet.controller):
			u.set_meta("lent_of", int(pet.controller))
		u.faction = 0
		u.mode = "player"
		u.facing = facing
		u.set_meta("tame_stage", 3)
		u.set_meta("pet", pet)
		if pet.get("xp_stats") is Dictionary:
			XpRules.restore_unit_record(u, pet.xp_stats)
		if float(pet.get("hp", -1.0)) > 0.0:
			u.hp = minf(float(pet.hp), u.max_hp)
		if pet.has("mana"):
			u.mana = minf(float(pet.mana), u.max_mana)
		if pet.get("body") is Dictionary:
			CampaignState.apply_body(u, pet.body)
	return u


func _unit_records() -> Array:
	var out := []
	for u: GameUnit in world.units.values():
		out.append(_unit_record(u))
	return out


## A unit for a client: its map record plus its current state ("snap", applied
## quietly: corpses of units killed before the client came lie dead) and
## whether it still has loot. Remake-only wire format.
func _unit_record(u: GameUnit) -> Dictionary:
	var r := u.info.duplicate()
	r.nid = u.uid
	r.position = Vector3(u.pos.x, u.pos.y, 0)
	r.controller = u.controller
	r.player = u.faction
	r.snap = u.snapshot()
	r.runtime_stats = u.stats.duplicate(true)   # separate from the original mob's raw stats block
	if u.has_meta("xp_stats") and u.get_meta("xp_stats") is Dictionary:
		r.xp_stats = u.get_meta("xp_stats").duplicate(true)
	if u.has_meta("loot"):
		r.loot = true
	if u.has_meta("lmp_owner"):
		r.lmp_owner = int(u.get_meta("lmp_owner"))
		r.lmp_conn = int(u.get_meta("lmp_conn", 0))
	return r


## Client: a unit from a zone / spawn record.
func _spawn_record(r: Dictionary) -> GameUnit:
	if world.units.has(int(r.get("nid", 0))):
		return null   # already known (a spawn racing the zone message)
	var u := world.spawn_unit(r)
	if u:
		u.controller = int(r.get("controller", -1))
		if r.has("snap"):
			u.apply_snapshot(r.snap, true)
		if r.get("runtime_stats") is Dictionary:
			u.stats = r.runtime_stats.duplicate(true)
		if r.get("xp_stats") is Dictionary:
			u.set_meta("xp_stats", r.xp_stats.duplicate(true))
		if r.get("loot", false):
			u.set_meta("loot", [])
		if r.has("lmp_owner"):
			u.set_meta("lmp_owner", int(r.lmp_owner))
			u.set_meta("lmp_conn", int(r.get("lmp_conn", 0)))
	return u


@rpc("authority", "call_remote", "reliable")
func _rpc_zone(id: String, records: Array, diplo: PackedInt32Array, extra_mobs: Array, mpr := "", levers := {}, pool_epoch := 0) -> void:
	_pool_epoch = maxi(_pool_epoch, int(pool_epoch))
	if _zone_holding:
		_zone_held.append(_rpc_zone.bind(id, records, diplo, extra_mobs, mpr, levers, pool_epoch))
		return
	if game == null:
		zone_received.emit()
	if LoadingScreen.deferred():
		# Web / mobile: the screen (frame 8) is presented before the build;
		# the host's messages meanwhile wait for the new world, in order.
		_zone_holding = true
		await LoadingScreen.hold(get_tree(), campaign.zone(id), LoadingScreen.CLIENT)
		_zone_holding = false
	zone_id = id
	var z := campaign.zone(id)
	if mpr != "":
		z = z.duplicate()
		z.mpr = mpr
	GameData.trace("zone load %s (from host)" % id)
	LoadingScreen.begin(get_tree(), z, LoadingScreen.CLIENT)
	_build_world(z, false)
	LoadingScreen.step(9)
	world.diplomacy = diplo
	for f: String in extra_mobs:
		world.add_mob_objects(f)
	for nid in levers:
		world.lever_sys.restore_row(int(nid), levers[nid])
	for r: Dictionary in records:
		_spawn_record(r)
	_relink_heroes()
	LoadingScreen.step(10)
	game.attach_world(world)
	if _remote_loading:
		world.process_mode = Node.PROCESS_MODE_DISABLED
	world.prepare_animation_bindings()
	game.rig.village_start_view(z)
	ShaderWarmup.run(game)
	if not _remote_loading:
		LoadingScreen.end()
	GameData.trace("zone ready %s (from host)" % id)
	if not _remote_loading:
		net.zone_loaded()
	if _remote_loading:
		if _remote_load_end_serial == _load_serial:
			_rpc_load_end(_remote_load_end_serial)
		return   # replay / input / loading screen wait for reliable load-end
	var held := _zone_held
	_zone_held = []
	if not held.is_empty():
		GameData.trace("%d host messages held during the loading screen" % held.size())
	for c: Callable in held:
		c.call()   # a further zone holds again: the rest waits for it


## Each LMP connection loads only its own destination. Reliable events use
## that connection's generation, rather than Session's host-visible world.
@rpc("authority", "call_remote", "reliable")
func _rpc_lmp_zone(id: String, generation: int, records: Array, diplo: PackedInt32Array,
		extra_mobs: Array, mpr := "", levers := {}) -> void:
	if lmp.is_empty() or generation <= lmp_generation:
		return
	if _zone_holding:
		_zone_held.append(_rpc_lmp_zone.bind(id, generation, records, diplo, extra_mobs, mpr, levers))
		return
	lmp_generation = generation
	zone_id = id   # replay arriving during deferred presentation belongs here
	loading_game = true
	await _rpc_zone(id, records, diplo, extra_mobs, mpr, levers)
	if lmp_generation == generation and not _zone_holding:
		loading_game = false


@rpc("authority", "call_remote", "reliable")
func _rpc_lmp_event(id: String, generation: int, ev: Dictionary) -> void:
	if lmp.is_empty() or id != zone_id or generation != lmp_generation:
		return
	if _zone_holding:
		_zone_held.append(_apply_lmp_event.bind(id, generation, ev))
		return
	_apply_lmp_event(id, generation, ev)


func _apply_lmp_event(id: String, generation: int, ev: Dictionary) -> void:
	if id == zone_id and generation == lmp_generation:
		_on_event(ev)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_lmp_snap(id: String, generation: int, snaps: Array, time: float) -> void:
	if not lmp.is_empty() and id == zone_id and generation == lmp_generation:
		_apply_snap(snaps, time)


## Client, web / mobile: host messages that came while _rpc_zone waited for
## its loading screen to be presented (LoadingScreen.hold).
var _zone_holding := false
var _zone_held: Array[Callable] = []


## nid -> [state, figure t, enabled] for the zone message (levers already
## switched, EnableLever).
func _lever_states() -> Dictionary:
	var out := {}
	for nid in world.levers:
		out[nid] = world.lever_sys.export_row(int(nid))
	return out


# ------------------------------------------------------------------ world state for joiners
# Remake-only (co-op plumbing). Events that leave lasting state behind are
# remembered by the host (world meta "replay") so a client that loads the zone
# later -- a late joiner, a reconnect, or everyone after a load or zone change
# -- gets them again as the same event types: hidden / removed map objects,
# script particle sources and lights (fxcmd), the forced music (only while it still plays on the host), lasting magic
# effects on units (magicfx) and lasting ground spells (spellfx with "left"),
# plus the open conversation or global map.

## Ground spells whose effect lasts for the spell's duration.
const LASTING_SPELLFX := ["firewall", "litnwall", "acid_fog", "fireworks", "clairvoyence"]
## Spells whose visuals outlive the cast by a fixed number of ticks (one-shot
## particles, ParticleFx.ONE_SHOT: 60 ticks, Teleport's 120; the fireball
## flies first, _replay_life): replayed with their age, so they resume where
## they are (the original saves and sends its particle objects with their creation
## tick, and catches a late one up).
const SHORT_SPELLFX := ["fireball", "acid_column", "teleport", "inv_lit"]

func _replay_state() -> Dictionary:
	if not world.has_meta("replay"):
		world.set_meta("replay", {"objs": {}, "fx": {}, "magic": {}, "spells": [], "music": {}, "weather": {}, "tornado": {}, "moved": {}})
	return world.get_meta("replay")


## Host: remember an event's lasting effect on the world.
func _track(event: Dictionary) -> void:
	var t := String(event.get("t", ""))
	match t:
		"dialog": _dialog_ev = event
		"dialog_close": _dialog_ev = {}
		"travel": _travel_ev = event
		"travel_close": _travel_ev = {}
	if world == null or not world.authority:
		return
	match t:
		"hide_obj": _replay_state().objs[int(event.nid)] = 1 if event.hide else 0
		"remove_obj": _replay_state().objs[int(event.nid)] = 2
		"move_obj":
			var rs := _replay_state()
			if not rs.has("moved"):
				rs.moved = {}
			rs.moved[int(event.nid)] = event.p
		"music": _replay_state().music = event
		# Rain / snow in progress (Weather._send): a joiner starts it too;
		# the stop event clears it.
		"weather": _replay_state().weather = event if int(event.get("w", 0)) != 0 else {}
		"tornado": _replay_state().tornado[int(event.id)] = [event, world.time]
		"fxcmd":
			var a: Array = event.get("a", [])
			if a.is_empty():
				return
			var f := String(event.f)
			var fam := "p"
			if f in ["CreateFXSource", "DeleteFXSource"]:
				# Looping script sounds by id (vm.gd numbers the -1 ones).
				var skey := "s%d" % roundi(float(a[0]))
				_replay_state().fx.erase(skey)
				if f == "CreateFXSource":
					_replay_state().fx[skey] = [event]
				return
			if f == "CreateRandomizedFXSource":
				var rs := _replay_state()
				rs.fx["r%d" % rs.fx.size()] = [event]
				return
			if f.ends_with("PointLight"):
				fam = "l"
			elif f.ends_with("Lightning"):
				fam = "b"
			elif not (f.ends_with("ParticleSource") or f.begins_with("AttachParticle")):
				return   # one-shot effects (CreateFX, run points)
			var key := "%s%d" % [fam, int(a[0])]
			var fx: Dictionary = _replay_state().fx
			if f.begins_with("Delete"):
				fx.erase(key)
			elif f.begins_with("Create"):
				fx.erase(key)   # re-created: goes to the end, old commands dropped
				fx[key] = [event]
			elif fx.has(key):
				fx[key].append(event)
		"magicfx":
			_replay_state().magic["%d:%s" % [int(event.uid), String(event.code)]] = [event, world.time + float(event.get("secs", 0.0))]
		"spell_light":
			for saved: Array in _replay_state().spells:
				var ev: Dictionary = saved[0]
				if String(ev.get("light_id", "")) == String(event.get("id", "")):
					ev.teleport_ok = bool(event.get("ok", false))
					if event.get("cancel", false):
						ev.light_cancel = true
						saved[1] = minf(float(saved[1]), world.time + GameUnit.TICK)
		"spellfx":
			var sp := Spells.parse(String(event.get("spell", event.get("code", ""))))
			var code := String(sp.code)
			if not (code in LASTING_SPELLFX or code in SHORT_SPELLFX or SpellFx.life_ticks(sp) > 0):
				return
			var ev := event.duplicate()
			SpellFx.capture_event(world, ev, sp)
			var caster: GameUnit = world.units.get(int(event.get("a", -1)))
			if code in SHORT_SPELLFX:
				# Where it was cast from: the caster moves on (and a teleport's
				# caster is gone from there), unit ids change with a load.
				if caster:
					ev.fx = caster.pos.x
					ev.fy = caster.pos.y
					if code == "teleport":
						ev.fz = ParticleFx.of(world).carrier_height(caster)
					elif code == "fireball":
						var flight_from := ParticleFx.of(world).unit_point(caster, 0)
						ev.flight_from = [flight_from.x, flight_from.y, flight_from.z]
				ev.erase("a")
				ev.erase("hold")
			elif caster:   # the wall's direction as cast (the caster moves on)
				var d := Vector2(float(event.x), float(event.y)) - caster.pos
				d = d.normalized() if d.length() > 0.01 else Vector2.from_angle(caster.facing)
				ev.dx = d.x
				ev.dy = d.y
			elif event.has("fx"):   # cast without a caster: from its source point
				var d2 := Vector2(float(event.x) - float(event.fx), float(event.y) - float(event.fy))
				if d2.length() > 0.01:
					ev.dx = d2.normalized().x
					ev.dy = d2.normalized().y
			if code in ["lightning", "curse_magic"]:
				# Preserve a fallback endpoint if its carrier is gone by replay.
				# Living carriers still follow their authoritative current position.
				var particles := ParticleFx.of(world)
				if caster:
					var at := particles.unit_point(caster, 0)
					ev.fx = at.x
					ev.fy = at.y
					ev.fz = at.z
				var target: GameUnit = world.units.get(int(event.get("tu", -1)))
				if target:
					var at := particles.unit_point(target, 0)
					ev.tx = at.x
					ev.ty = at.y
					ev.tz = at.z
			# The cast time (a replayed one carries its age in ticks).
			var age := float(event.get("age", 0))
			if not event.has("age") and event.has("left") and code in LASTING_SPELLFX:
				age = maxf(0.0, float(sp.duration) - float(event.left) / GameUnit.TICK)
			var t0 := world.time - age * GameUnit.TICK
			ev.erase("age")
			ev.erase("left")
			ev.erase("replay")
			var end := t0 + maxf(_replay_life(ev, sp), SpellFx.life_ticks(sp)) * GameUnit.TICK
			var spells: Array = _replay_state().spells
			for old: Array in spells.duplicate():
				if float(old[1]) <= world.time:
					spells.erase(old)
			spells.append([ev, end, t0])


## Ticks a SHORT_SPELLFX cast stays visible: the one-shot particle's life
## (ParticleFx.spawn), after the fireball's flight (ParticleFx._fireball: n
## ticks, then the 60-tick FireBlast); otherwise the spell's duration.
static func _replay_life(ev: Dictionary, sp: Dictionary) -> float:
	match String(sp.code):
		"fireball":
			return Spells.fireball_ticks(Vector2(float(ev.get("fx", ev.x)), float(ev.get("fy", ev.y))),
				Vector2(float(ev.x), float(ev.y)), float(sp.range)) + 60.0
		"teleport":
			return 120.0
		"acid_column", "inv_lit":
			return 60.0
		"healing":
			return 60.0   # its independent2006 particle outlives the33-tick light
		"lightning", "curse_magic":
			return 8.0
		"litnwall":
			return maxf(float(sp.duration) + 2.0, 1.0)
	return maxf(float(sp.duration), 1.0)


## The particles may finish before the native light is removed. Keeping
## that light must not restart particles or extend a wall's damaging visual.
static func replay_spell(event: Dictionary, age: int) -> Dictionary:
	var ev := event.duplicate()
	var sp := Spells.parse(String(ev.get("spell", ev.get("code", ""))))
	ev.age = maxi(age, 0)
	ev.replay = true
	ev.erase("left")
	if String(sp.code) in LASTING_SPELLFX:
		var life := _replay_life(ev, sp) if String(sp.code) == "litnwall" else float(sp.duration)
		var left := maxf(life - age, 0.0) * GameUnit.TICK
		if left > 0.0:
			ev.left = left
		else:
			ev.light_only = true
	elif age >= _replay_life(ev, sp):
		ev.light_only = true
	return ev


## The remembered world events as a list of events (`local`: for the host's
## own freshly built world: only what CampaignState.restore_zone does not do).
func _replay_events(local := false) -> Array:
	var out := []
	if world == null or not world.has_meta("replay"):
		return out
	var rs := _replay_state()
	if not local:
		for nid in rs.objs:
			var v := int(rs.objs[nid])
			out.append({"t": "remove_obj", "nid": nid} if v == 2 else {"t": "hide_obj", "nid": nid, "hide": v == 1})
		for nid in rs.get("moved", {}):
			out.append({"t": "move_obj", "nid": nid, "p": rs.moved[nid]})
	# A script PlayMusic only while it still plays on the host, from where the
	# host is (holds the combat music for the track's length).
	# Never for the host's own rebuilt world: the original's zone load only sets
	# the zone music mode, nothing restores a PlayMusic.
	if not local and not rs.music.is_empty() and GameSound.instance:
		var fp: Array = GameSound.instance.music.forced_playing()
		if not fp.is_empty() and String(fp[0]) == String(rs.music.get("name", "")).to_lower().get_file().trim_suffix(".mp3"):
			var ev: Dictionary = rs.music.duplicate()
			ev.at = float(fp[1])
			out.append(ev)
	for key in rs.fx:
		out.append_array(rs.fx[key])
	if local:
		return out
	if not rs.get("weather", {}).is_empty():
		out.append(rs.weather)
	# Running tornadoes where they are now (pos + step · ticks gone).
	var torn: Dictionary = rs.get("tornado", {})
	for id in torn.keys():
		var ev: Dictionary = torn[id][0].duplicate()
		var gone := maxi(floori((world.time - float(torn[id][1])) / GameUnit.TICK + 0.000001), 0)
		if gone > float(ev.life):
			torn.erase(id)
			continue
		ev.x = float(ev.x) + float(ev.vx) * gone
		ev.y = float(ev.y) + float(ev.vy) * gone
		ev.life = float(ev.life) - gone
		ev.age = maxi(int(ev.get("age", 0)), 0) + gone
		out.append(ev)
	for key in rs.magic.keys():
		var left := float(rs.magic[key][1]) - world.time
		if left <= 0.5:
			rs.magic.erase(key)
			continue
		var ev: Dictionary = rs.magic[key][0].duplicate()
		ev.secs = left
		ev.replay = true   # already running: no start sound / burst for a joiner
		out.append(ev)
	for e: Array in rs.spells:
		var left := float(e[1]) - world.time
		if left > 0.0:
			var age := maxi(floori((world.time - float(e[2])) / GameUnit.TICK + 0.000001), 0) if e.size() > 2 else 0
			out.append(replay_spell(e[0], age))
	return out


## Host: what a client loading the current zone needs beyond the zone message
## (pid 0 = every client).
func _send_world_state(pid: int) -> void:
	var evs := _replay_events()
	if movie_active():
		if pid > 0: _movie_wait[pid] = true
		evs.append(_movie_ev)
	evs.append(_water_event())   # includes an empty list, clearing any old offsets
	if not _dialog_ev.is_empty() and world.vm and world.vm.briefings.active == String(_dialog_ev.get("id", "")):
		evs.append(_dialog_ev)
	if not travel_options.is_empty() and not _travel_ev.is_empty():
		evs.append(_travel_ev)
	for ev: Dictionary in evs:
		if lmp_travel:
			if pid == 0:
				for peer: int in lmp_travel.peers_here():
					lmp_travel.send_event(peer, ev)
			else:
				lmp_travel.send_event(pid, ev)
		elif pid == 0:
			_rpc_event.rpc(ev)
		else:
			_rpc_event.rpc_id(pid, ev)


## the changed water list, after each host logic tick. Reliable
## ordering carries the final state even when a client is still building its
## map. Revisions also reject an older replay after a newer absolute state.
func publish_water() -> void:
	if not is_host or world == null:
		return
	_water_seq += 1
	broadcast(_water_event())


func _water_event() -> Dictionary:
	return {"t": "water", "zone": zone_id, "seq": _water_seq,
		"l": world.water_levels.duplicate(true)}


## Host: a stored zone's script particle sources and lights come back with it
## (the zone script that made them does not run again). Its PlayMusic does
## not: the original's zone load only sets the zone music mode.
func _replay_local() -> void:
	if not world.presentation:
		return
	for ev: Dictionary in _replay_events(true):
		ParticleFx.of(world).on_event(ev)


## Extra .mob files merged into the current zone (AddMob, side quest maps).
## the original (zone load): gz6g loads "zone6_2.mpr" (the frozen
## lake, bz2g's script sets GS var "z.gz6g.frozen" for 72 hours) instead of
## "zone6.mpr"; the objects (.mob) stay the same.
func _zone_variant(z: Dictionary) -> Dictionary:
	if String(z.get("id", "")) == "gz6g" and is_equal_approx(state.get_var(0, "z.gz6g.frozen"), 1.0):
		z = z.duplicate()
		if not z.has("mob"):
			z.mob = z.mpr
		z.mpr = "zone6_2"
	return z


## the original: entering bz3g with GS var "movie" = 1 (set
## zone9's script) plays Movies\dcity.bik, then the var is removed.
func _movie_on_enter(id: String) -> void:
	if id == "bz3g" and is_equal_approx(state.get_var(0, "movie"), 1.0):
		state.del_var(0, "movie")
		broadcast({"t": "movie", "name": "dcity"})


func _extra_mobs() -> Array:
	var out: Array = world.get_meta("added_mobs", []).duplicate()
	if world.has_meta("quest_mob"):
		out.append("%s.mob" % world.get_meta("quest_mob"))
	return out


# ------------------------------------------------------------------ travel

## Campaign co-op has one shared travel decision, made by the host. Native
## LMP exits are routed per owner by lmp_travel instead. A new leave box needs
## a living unit; an already-open native box can still confirm after death.
func leave_player() -> int:
	return 0


func party_heroes() -> Array:
	var out := []
	for u: GameUnit in world.units.values():
		if u.controller >= 0 and u.has_meta("hero") and not u.dead:
			out.append(u)
	return out


## Host: the party leaves through an exit when all living heroes stand in its area.
## The leave-zone box (the original CInterface3D): a move click
## clears the armed exit, and with selected units in a zone exit (:
## its area, target not "none") whose GS var "z.<target>" is not 1 arms it
## . then waits until every living unit of the
## party stands in that exit and opens «leave_zone» / «leave_zone_msg» (✓ / ✗)
## once, disarming; ✓ leaves through it
## ✗ only closes. Co-op: the host's party decides (the box goes to player 0).
func _arm_exit(player: int, at: Vector2, has_units: bool, clicked_exit := -1) -> void:
	if lmp_travel:
		lmp_travel.arm_exit(player, at, has_units, clicked_exit)
		return
	if player != leave_player():
		return
	_leave_armed = -1
	if not has_units or world == null:
		return
	var n := open_exit_at(at, player)
	if n >= 0 and (GameData.option("auto_exit") == 1 or clicked_exit == n):
		_leave_armed = n


## The open exit under a deliberate ground click. The server repeats this
## lookup against the submitted point and controlled units before arming it.
func open_exit_at(at: Vector2, player := -1) -> int:
	if world == null or state == null:
		return -1
	var n := _exit_at(at)
	return n if n >= 0 and _exit_is_open(n, player) else -1


func _exit_is_open(n: int, player := -1) -> bool:
	if lmp_travel and player >= 0:
		return lmp_travel._exit_open(player, n)
	var ex: Dictionary = world.zone.get("exits", {}).get(n, {})
	var to := String(ex.get("to", "none"))
	if to.to_lower() == "none":
		return false
	var key := LmpMode.exit_var(to) if not lmp.is_empty() else "z." + to.to_lower()
	return state.get_var(0, key) != 1.0


func _exit_at(at: Vector2) -> int:
	var zone: Dictionary = world.zone
	for n in zone.get("exits", {}):
		var ex: Dictionary = zone.exits[n]
		if ex.has("remove") and String(ex.get("to", "none")).to_lower() != "none" and (ex.remove as Rect2).has_point(at):
			return n
	return -1


func _check_exits() -> void:
	if lmp_travel:
		lmp_travel.check_exits()
		return
	if String(world.zone.get("type", "")) == "brief":
		_village_exit_check()
		return
	_auto_exit_check()
	_alone_exit_check()
	if _leave_armed < 0 or not travel_options.is_empty() or (world.vm and world.vm.briefings.active):
		return
	var ex: Dictionary = world.zone.get("exits", {}).get(_leave_armed, {})
	if ex.is_empty() or not _exit_is_open(_leave_armed, leave_player()):
		_leave_armed = -1
		return
	var r: Rect2 = ex.remove
	var any := false
	var lp := leave_player()
	for h: GameUnit in party_heroes():
		if h.controller != lp or h.dead:
			continue
		any = true
		if not r.has_point(h.pos):
			return
	if any:
		broadcast({"t": "leave_box", "to": lp, "exit": _leave_armed})
		_auto_exit = _leave_armed
		_leave_armed = -1


## Remake-only (user request 2026-10-02; the original opens the box only after a
## move click inside the exit). Optional auto_exit:
## when every living
## hero of the host's party stands in one open exit's remove rect, the
## leave-zone box opens even without that click. Shown once per stay: it
## re-arms only after the party has left the rect (a ✗ leaves the party
## standing there); a party that starts the zone inside an exit is not asked
## until it has stepped out once.
func _auto_exit_check() -> void:
	if GameData.option("auto_exit") != 1:
		return
	var n := _party_exit()
	if _auto_world != world:
		_auto_world = world
		_auto_exit = n   # entering / loading inside an exit does not ask
		return
	if n < 0:
		_auto_exit = -1
		return
	if n == _auto_exit or _leave_armed >= 0 or not travel_options.is_empty() \
			or (world.vm and world.vm.briefings.active):
		return
	_auto_exit = n
	broadcast({"t": "leave_box", "to": leave_player(), "exit": n})


## Co-op (remake): a player other than the one whose party decides the exit
## (leave_player) has all its living units standing in an open exit while
## that party is not there: the leave box does not open for it (the original
##  only asks when every living unit of the
## deciding party stands in the exit, and says nothing otherwise), so it gets
## the original's line texts.res «string no_way» "- We can't leave anyone
## here!" (in the data but shown by no code of the original 1.06) in its message
## window, once per stay in that exit.
var _alone_exit := {}        # player slot -> exit it was told about
var _alone_world: GameWorld


func _alone_exit_check() -> void:
	if not online or not is_host:
		return
	if _alone_world != world:
		_alone_world = world
		_alone_exit = {}
	var lp := leave_player()
	var lp_exit := _party_exit()
	for p: Dictionary in players.values():
		var idx := int(p.index)
		if idx == lp:
			continue
		var n := -1
		var any := false
		for h: GameUnit in party_heroes():
			if h.controller != idx:
				continue
			var e := _exit_at(h.pos)
			if e < 0 or (any and e != n):
				n = -1
				break
			n = e
			any = true
		if n >= 0 and state.get_var(0, "z." + String(world.zone.exits[n].get("to", "none")).to_lower()) == 1.0:
			n = -1
		if n < 0 or n == lp_exit:
			_alone_exit.erase(idx)
			continue
		if int(_alone_exit.get(idx, -1)) == n:
			continue
		_alone_exit[idx] = n
		var text := GameData.text("string no_way").strip_edges()
		if text:
			broadcast({"t": "msg", "text": text, "to": idx})


## A village leaves by its own rule (the village screen's update
## ..): armed from the screen's build (:
##  = 1, exit = 0), it puts only the party's FIRST record (party
## the leader) into the unit list and
## on exit 0; when that unit stands in it (target not "none", GS var
## "z.<target>" != 1) it leaves at once through — no leave-zone
## box and no check of the other members, so hired mercenaries (and other
## heroes) need not be in the exit. Remake: the host's leader (co-op: the host
## decides, as for field exits); fired once per stay in the rect, so "Stay here"
## on the global map does not reopen it at once. Default policy now requires
## a deliberate exit-ground click before arrival (user request).
func _village_exit_check() -> void:
	var automatic := GameData.option("auto_exit") == 1
	var exits: Dictionary = world.zone.get("exits", {})
	var n := -1
	var inside := false
	if not exits.is_empty():
		n = exits.keys()[0]
		var ex: Dictionary = exits[n]
		var lead: GameUnit = null
		var recs: Array = state.heroes.get(0, [])
		for u: GameUnit in world.units.values():
			if u.controller == 0 and not u.dead and u.has_meta("hero") and not recs.is_empty() and u.get_meta("hero") == recs[0]:
				lead = u
		inside = lead != null and ex.has("remove") and String(ex.get("to", "none")).to_lower() != "none" \
			and (ex.remove as Rect2).has_point(lead.pos)
	if _auto_world != world:
		_auto_world = world
		_auto_exit = n if inside else -1
		if automatic:
			return
	if not inside:
		_auto_exit = -1
		return
	if (automatic and n == _auto_exit) or (not automatic and _leave_armed != n) \
			or not travel_options.is_empty() or (world.vm and world.vm.briefings.active):
		return
	var to := String(exits[n].get("to", "none"))
	if state.get_var(0, "z." + to.to_lower()) == 1.0:
		return
	_auto_exit = n
	_leave_armed = -1
	leave_zone(to, int(exits[n].get("to_exit", 1)))


## The open exit (remove rect, target not "none", GS var "z.<target>" != 1)
## holding every living hero of the host's party, else -1.
func _party_exit() -> int:
	var n := -1
	var lp := leave_player()
	for h: GameUnit in party_heroes():
		if h.controller != lp or h.dead:
			continue
		var e := _exit_at(h.pos)
		if e < 0 or (n >= 0 and e != n):
			return -1
		n = e
	if n >= 0 and state.get_var(0, "z." + String(world.zone.exits[n].get("to", "none")).to_lower()) == 1.0:
		return -1
	return n


## Single player, the original (a zone change: the leave box's ✓
## the global map, the script's LeaveToZone — every caller of leave_zone /
## _travel here): when the main hero (player record) is gone or
## dead (unit =, unit, set at death
## ), it calls player =, which outside a
## network game sends client message 9 (handler → the
## screen's slot 31: gameover.wav and the «game_over» box) and returns
## without the zone change. True when that happened.
func sp_game_over() -> bool:
	if not sp_main_hero_dead():
		return false
	travel_options = []
	broadcast({"t": "game_over"})
	return true


## Lost in Astral's GameOver/GameOverMsg builtins end the story regardless
## of the hero's health. The message arguments are authored text keys.
func script_game_over(title := "game_over", text := "game_over_msg") -> void:
	travel_options = []
	broadcast({"t": "game_over", "scripted": true, "title": title, "text": text})


## Single player: the main hero (not a mercenary) is dead or gone.
func sp_main_hero_dead() -> bool:
	if multiplayer_game or not lmp.is_empty() or world == null:
		return false
	for u: GameUnit in world.units.values():
		if u.controller == 0 and u.has_meta("hero") and not u.get_meta("hero").has("merc") and not u.dead:
			return false
	return true


## Host: go to `target` (a game/brief zone, or an edge = choice on the island map).
func leave_zone(target: String, entrance: int, player := -1, source_zone := "", source_generation := 0) -> void:
	if lmp_travel:
		var owner := 0 if player < 0 else player
		if source_zone != "" and (lmp_travel.zone_of(owner) != source_zone \
				or lmp_travel.generation_of(owner) != source_generation):
			return
		lmp_travel.request(owner, target, entrance)
		return
	if sp_game_over():
		return
	# the original: the pseudo-zone "endofgame" loads nothing and sets
	# world mode 8, which sends every player to screen 8, the "Crdt" credits
	# . zone20's script leaves there once the Curse is dead
	# (GS var q.gz20g.q73g = 2, then QuestComplete, Sleep(60), LeaveToZone).
	if target.to_lower() == "endofgame":
		broadcast({"t": "ending"})
		return
	if not lmp.is_empty():
		_lmp_leave(target, entrance)
		return
	var z := campaign.zone(target)
	if z.is_empty():
		message.emit(RemakeText.t("Unknown destination ") + target)
		return
	if z.get("type", "game") != "edge":
		travel_options = [{"zone": target, "entrance": entrance, "title": zone_title(target)}]
		# A named location is a direct transition; only edge zones open the
		# global map. Small scenes may have no selectable map piece at all.
		_travel(target, entrance)
		return
	else:
		# Native 662990 (base) / 58cdd0 (LiA): entering an edge reveals
		# its adjacent game zones. Scripts need not set these flags themselves.
		_reveal_travel_zones(target)
		# The global map's routes (CampaignMap.routes = the original)
		# from the edge; the older walk over open zones only as a fallback.
		travel_options = _route_options(target)
		if travel_options.is_empty():
			travel_options = _edge_options(target, {zone_id: true, target: true})
		# The original's map never lets the party pick a starting area (its
		# piece leads to the village, TravelMap); the remake option offers it.
		var shown := start_zones_shown()
		travel_options = travel_options.filter(func(o): return not START_ZONES.has(String(o.zone)) or shown.has(String(o.zone)))
	if travel_options.is_empty():
		push_warning("leave_zone: no route from " + target)
		return
	# "start": the starting areas the map shows as their own piece — the
	# host's option, so every peer's map agrees.
	# Include the reveal in the same reliable event: a guest-purse scope may
	# defer the full state update until after the map has already been built.
	broadcast({"t": "travel", "options": travel_options, "from": target, "start": start_zones_shown(),
		"zone_states": _travel_zone_states(target)})


## Reveal only directly adjacent game regions, never camps or further edges.
## State 2 means completed and must retain its original dimmed appearance.
func _reveal_travel_zones(edge: String) -> void:
	for id: String in _travel_zone_states(edge):
		if state.get_var(0, "z." + id) == 0.0:
			state.set_var(0, "z." + id, 1.0)
			mark_dirty()


func _travel_zone_states(edge: String) -> Dictionary:
	var out := {}
	var z := campaign.zone(edge)
	if z.get("type", "") != "edge": return out
	for ex: Dictionary in z.get("exits", {}).values():
		var id := String(ex.get("to", ""))
		if campaign.zone(id).get("type", "") == "game":
			out[id] = state.get_var(0, "z." + id)
	return out


## Remake option "start_zones" (Starting areas on the travel map). The
## campaign starts in gz1g (the original: zone "gz1g", entrance 0 =
## its "#exit 1", a one-way "none" exit). The original never lets the party
## back: map.txt routes reach it (edge gz1g_bz1g's "#exit 1" → "gz1g 2", its
## path to the village), but on Gipat the global map links a done piece
## ("z.<zone>" = 2, set by zone1's script) to the village its exits lead to
## (byte for "gipat" only), and a click on a linked piece
## travels to that village. With the option , once the zone
## has been visited, its piece is a destination like the others (objectives
## screen, its one entrance with a deploy rect: "#exit 2", 184..190 × 101..108);
## off, it is also kept out of the travel options. The other allods' starting
## areas (gz11k "FAKE DEPLOY", gz15h "First Deploy") need nothing: their
## edges lead back into them and nothing links them.
const START_ZONES := ["gz1g"]


## Host: the starting areas the travel map offers (option on, visited and
## not the zone being left: gz1g's exit to bz1g opens the map with the village
## alone, where its piece stays linked).
func start_zones_shown() -> Array:
	if not GameData.option("start_zones") or not lmp.is_empty():
		return []
	return START_ZONES.filter(func(id: String) -> bool: return id != zone_id and state.visited.has(id) and zone_exists(id))


## Host: a revisit of a starting area runs on from the level script saved
## with the zone (CampaignState.store_zone "vm"), whose intro threads have all
## ended (zone1: Said1 guards Zak's wake-up line R1, FirstComing / q.gz1g.q0g
## the village briefing). A zone state without one (a save from before the
## script was kept) would start zone1's WorldScript afresh, and its
## VTriger#0#205 closes the edges z.gz1g_gz2g / z.gz2g_gz3g again (only
## basecam's one-time b.smith.m6 reopens them) and VCheck#0#1 replays the
## villagers' flight: then the level script is not started.
func _start_zone_revisit(id: String) -> void:
	if not START_ZONES.has(id) or not state.zones.has(id) or not world or not world.vm:
		return
	if not Dictionary(state.zones[id].get("vm", {})).is_empty():
		return
	world.vm.instances = world.vm.instances.filter(func(i) -> bool: return i.sname != "WorldScript")
	GameData.trace("start zone %s revisited without a saved script: level script not started" % id)


## LMP: the base's exit names the pseudo-zone "MPGame1" — the zone of the
## quest taken (LmpMode.GAME_ZONE); a quest zone's exit names its base. The
## party goes there straight away (map-LMP.txt has no "#exit" to an edge and
## the bases' "#position" is "for single player only").
func _lmp_leave(target: String, entrance: int) -> void:
	if lmp_travel:
		lmp_travel.request(0, target, entrance)
		return
	target = target.to_lower()
	if target == LmpMode.GAME_ZONE:
		target = String(lmp.get("quest", ""))
		if target.is_empty():
			# No quest taken: GS var z.MPGame1 = 1 closes the exit (it never
			# arms, LmpMode.zone_var); a direct call stays as well.
			return
	if campaign.zone(target).is_empty() or not zone_exists(target):
		message.emit(RemakeText.t("Unknown destination ") + target)
		return
	travel_options = []
	broadcast({"t": "travel_close", "go": target})
	call_deferred("enter_zone", target, entrance)


## Every entrance a route reaches, one option each; "hours" = the route's
## time (−1 = none). A village is entered with the time of its route entry 0
## which map.txt never has, so it costs no time.
func _route_options(start: String) -> Array:
	var out := []
	for id: String in campaign.zones:
		if String(campaign.zones[id].get("type", "")) == "edge" or not zone_exists(id):
			continue
		var r := campaign.routes(start, id, func(k: String) -> float: return state.get_var(0, k))
		if campaign.zones[id].type == "brief":
			# A village is entered at entrance 0 — the original's entrances are the exits
			# in map.txt order, target exit numbers − 1 — with the
			# time of the route to it, if one reached it.
			var ex: Dictionary = campaign.zones[id].get("exits", {})
			if not r.is_empty() and not ex.is_empty():
				var e0: int = ex.keys()[0]
				out.append({"zone": id, "entrance": e0, "title": zone_title(id), "hours": maxf(float(r.get(e0, 0.0)), 0.0)})
			continue
		for e: int in r:
			out.append({"zone": id, "entrance": e, "title": zone_title(id), "hours": maxf(float(r[e]), 0.0)})
	return out


func _edge_options(edge: String, seen: Dictionary) -> Array:
	var out := []
	var z := campaign.zone(edge)
	for n in z.get("exits", {}):
		var ex: Dictionary = z.exits[n]
		var to := String(ex.get("to", ""))
		if to.is_empty() or to == "none" or seen.has(to):
			continue
		var tz := campaign.zone(to)
		if tz.is_empty():
			continue
		seen[to] = true
		if tz.get("type", "game") == "edge":
			if zone_open(to):
				out.append_array(_edge_options(to, seen))
		elif zone_open(to):
			out.append({"zone": to, "entrance": int(ex.get("to_exit", 1)), "title": zone_title(to),
				"hours": float(ex.get("passtime", 0.0))})
	return out


## False for map.txt zones whose map files are not in the installation (cut content).
func zone_exists(id: String) -> bool:
	var z := campaign.zone(id)
	if String(z.get("type", "")) == "edge":
		return true
	return GameFiles.exists(GameData.root.path_join("maps/%s.mpr" % String(z.get("mpr", ""))))


func zone_open(id: String) -> bool:
	if not zone_exists(id):
		return false
	return state.visited.has(id) or state.get_var(0, "z." + id) >= 1.0 \
		or campaign.zone(id).get("type", "") == "brief"


func zone_title(id: String) -> String:
	var t := GameData.text("zone " + id)
	return t.get_slice("\n", 0).strip_edges() if t else id


func _travel(zone: String, entrance: int) -> void:
	if loading_game or sp_game_over():   #  message 6
		return
	for o: Dictionary in travel_options:
		if o.zone == zone and int(o.entrance) == entrance:
			if not zone_exists(zone) or not campaign.zone(zone).has("mpr"):
				return
			_begin_host_load(zone, false)
			travel_options = []
			broadcast({"t": "travel_close", "go": zone})   # the zone stays frozen (Game.on_event)
			state.advance_hours(float(o.get("hours", 0.0)))
			call_deferred("_complete_zone_travel", zone, entrance, _load_serial)
			return


# ------------------------------------------------------------------ commands

func submit(cmd: Dictionary) -> void:
	if String(cmd.get("t", "")) == "movie_done":
		if is_host: _movie_ack(1, int(cmd.get("serial", -1)))
		elif online: _rpc_cmd.rpc_id(1, cmd)
		return
	if movie_active():
		return
	if loading_game:
		return
	cmd = cmd.duplicate()
	cmd._zone = zone_id
	cmd._generation = lmp_generation if not lmp.is_empty() else (_load_serial if is_host else _pool_epoch)
	if is_host:
		if lmp_travel:
			lmp_travel.command(cmd, my_index)
		else:
			coop.with_purse(my_index, apply_command.bind(cmd, my_index))
	else:
		_rpc_cmd.rpc_id(1, cmd)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_cmd(cmd: Dictionary) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if String(cmd.get("t", "")) == "movie_done":
		if players.has(pid): _movie_ack(pid, int(cmd.get("serial", -1)))
		return
	if loading_game or movie_active():
		return
	if lmp.is_empty() and (String(cmd.get("_zone", "")) != zone_id \
			or int(cmd.get("_generation", -1)) != _load_serial):
		return   # an order issued before this transfer/reload cannot enter the new world
	if players.has(pid):
		if lmp_travel:
			lmp_travel.command(cmd, int(players[pid].index))
			return
		# A joiner who brought its hero trades / loots with its own purse and bag.
		coop.with_purse(players[pid].index, apply_command.bind(cmd, players[pid].index))


## The remake's approach distance of a talk order (approx.: the original has no
## walk-and-talk, see ScriptVM._interact_reach) and the loot order mark's radius
## (the loot and steal approaches use ScriptVM._interact_reach).
const TALK_REACH := 2.2
const LOOT_REACH := 1.8


## A double-clicked order (the command's flag):
## a unit that does not stand and cannot act from where it is (
## here: the target out of reach) stands up (gait = 2) and then runs
## to it (run bit 2 while standing). The flag lasts for that
## order only (cleared when it ends).
func _double_stand(u: GameUnit, cmd: Dictionary, at: Vector2, reach: float) -> void:
	if bool(cmd.get("run", false)) and u.stance != GameUnit.STANCE_NONE and u.pos.distance_to(at) > reach:
		u.change_posture(GameUnit.STANCE_NONE)


## Packet 0x36: nearest selected unit in squared 3D
## distance, skipping those whose path cannot reach the
## interaction. If none can, keep the nearest so its order can fail normally.
func _interaction_unit(units: Array[GameUnit], target: GameUnit) -> GameUnit:
	if units.size() == 1:
		return units[0]
	var sorted := units.duplicate()
	sorted.sort_custom(func(a: GameUnit, b: GameUnit):
		var da := a.dist3(target)
		var db := b.dist3(target)
		return units.find(a) < units.find(b) if da == db else da < db)
	for u: GameUnit in sorted:
		if u.dist3(target) <= TALK_REACH:
			return u
		var p := world.nav.find_path(u.pos, target.pos, [u, target], [],
			maxf(0.0, u.body_radius() - NavGrid.R_REF), u.move_class(), true)
		if not p.is_empty() and p[-1].distance_to(target.pos) <= TALK_REACH:
			return u
	return sorted[0]


## A group may fill the Catacombs lift's narrow deck. Prefer its selected
## lead actor as before, but let another selected actor operate the switch
## when the lead cannot reach it. Do not issue orders to the other riders.
func _lever_unit(selected: Array[GameUnit], obj: Node3D) -> GameUnit:
	if selected.size() == 1 or world.vm == null:
		return selected[0]
	var p: Vector3 = obj.get_meta("ei").position
	var at := Vector2(p.x, p.y)
	var nid := int(obj.get_meta("ei").nid)
	for u: GameUnit in selected:
		if not world.vm._lever_science_ok(u, nid):
			continue
		var reach := world.vm._interact_reach(u, obj)
		if u.pos.distance_to(at) < reach:
			return u
		var route: Dictionary = world.nav.find_object_path(u, at, nid)
		var path: PackedVector2Array = route.path
		if not path.is_empty() and path[-1].distance_to(at) < reach:
			return u
	# Keep the usual failure/skill acknowledgement when no selected actor can.
	return selected[0]


## The spot of the i-th unit of a group move round the clicked point (remake).
static func group_offset(i: int) -> Vector2:
	if i == 0: return Vector2.ZERO
	var ring := 1
	i -= 1
	while i >= 6 * ring:
		i -= 6 * ring
		ring += 1
	return Vector2.from_angle(float(i) * TAU / (6 * ring)) * (1.6 * ring)


func apply_command(cmd: Dictionary, player: int) -> void:
	if world == null or movie_active() or not command_allowed(cmd):
		return
	var mine: Array[GameUnit] = []
	for id in cmd.get("units", []):
		var u: GameUnit = world.units.get(int(id))
		# The server's order handlers (
		# ) leave out units with flag (BlockUnit, say_block).
		if u and u.controller == player and not u.dead \
				and not (u.blocked and Game.block_refuses(String(cmd.get("t", "")), shop_available())):
			mine.append(u)
	var target: GameUnit = world.units.get(int(cmd.get("target", -1)))
	match String(cmd.t):
		"move":
			var c := Vector2(cmd.x, cmd.y)
			# Only a deliberate exit-ground click carries an integer exit tag.
			# Stick/line and swarm moves never count as that click.
			var tag: Variant = cmd.get("exit", -1)
			var clicked_exit: int = tag if tag is int and not bool(cmd.get("line", false)) \
					and not bool(cmd.get("swarm", false)) else -1
			var limit := village_move_limit()
			var ex: Dictionary = world.zone.get("exits", {}).get(clicked_exit, {})
			if ex.has("remove") and (ex.remove as Rect2).has_point(c) and String(ex.get("to", "none")) != "none" \
					and state.get_var(0, "z." + String(ex.to)) != 1.0:
				limit = Vector3.ZERO   # the authored open exit remains reachable
			_arm_exit(player, c, not mine.is_empty(), clicked_exit)
			# Shared identity distinguishes this click from later replacement
			# commands. Only these actors may wait briefly for one another.
			var group := {}
			if mine.size() > 1 and not cmd.get("line", false) and not cmd.get("swarm", false):
				group.members = mine.map(func(u: GameUnit): return u.uid)
			for i in mine.size():
				var off := group_offset(i)
				# A double-click move requests standing before its order starts,
				# retaining the live posture transition and clearance refusal.
				if bool(cmd.get("run", false)) and mine[i].stance != GameUnit.STANCE_NONE:
					mine[i].change_posture(GameUnit.STANCE_NONE)
				# The unit's own gait decides run / walk (the original unit)
				# "run" is the double-click flag (command).
				var mo := {"type": "move", "to": c + off, "gait": true, "run": bool(cmd.get("run", false)), "path_notice": not bool(cmd.get("line", false))}
				if not group.is_empty():
					mo.move_group = group
				if limit.z > 0.0:
					mo.village_limit = limit
					mo.to = Vector2(limit.x,limit.y) + (mo.to-Vector2(limit.x,limit.y)).limit_length(limit.z)
				if cmd.get("line", false):
					# The gamepad stick's moves (PadField): straight where the
					# line can be walked (GameUnit._do_move, NavGrid.direct_line).
					mo.line = true
				if cmd.get("swarm", false):
					# Ctrl / aimed key on the ground: packet 0x3a, the Player
					# motivation's state 2 (UnitAI.swarm_tick), round the point.
					mo.swarm = c
				mine[i].command(mo)
		"leave_exit":   # the leave-zone box's ✓
			var lx: Dictionary = world.zone.get("exits", {}).get(int(cmd.get("exit", -1)), {})
			if not lx.is_empty() and (lmp_travel != null or player == leave_player()):
				if lmp_travel:
					var exit_number := int(cmd.get("exit", -1))
					var living := world.units.values().any(func(u: GameUnit):
						return u.controller == player and u.has_meta("hero") and not u.dead)
					# The native message3 handler may receive the pending box's
					# confirmation after its hero died. The destination must still
					# be open; a living party retains the physical exit predicate.
					if not lmp_travel._exit_open(player, exit_number) \
							or (living and lmp_travel._party_exit(player) != exit_number):
						return
				leave_zone(String(lx.to), int(lx.get("to_exit", 1)), player)
		"gait":
			# HUD dial / movement keys: net message 0x35 per selected unit
			# server handler.
			for u in mine:
				u.set_gait(int(cmd.get("gait", 2)))
		"aggression":
			# HUD dial / key "swarm" (the original): net message 0x3b
			# (unit id, byte) per selected unit, applied by the server's
			# handler (unit).
			for u in mine:
				u.aggressive = bool(cmd.get("on", true))
				if u.has_meta("hero"):
					u.get_meta("hero").aggressive = u.aggressive
		"direct_control":
			var leader_id := int(cmd.get("leader",-1))
			for u: GameUnit in world.unit_rows():
				if u.controller == player: u.direct_controlled = u.uid == leader_id and not u.dead
		"direct_attack":
			var direction: Variant = cmd.get("direction")
			if not direction is Vector3 or not direction.is_finite() or not is_finite(direction.length_squared()) or direction.length_squared() < 0.5: return
			for u in mine:
				if u._attack_cd > 0.0 or u._anim_lock > 0.0 or not u._pending_hit.is_empty(): continue
				u.command({"type":"direct_attack","direction":direction.normalized()})
		"attack":
			if target:
				for u in mine:
					if u != target:   # Ctrl / aimed click may pick a party member
						# Double click: stand up and run unless in reach (case 3).
						_double_stand(u, cmd, target.pos, float(u.stats.reach) if u.stats.get("ranged", false) else u.melee_reach(target))
						u.attack(target, false, int(cmd.get("aim", -1)), bool(cmd.get("run", false)), true)
		"follow":
			# Follow order (HUD left strip, the original interaction mode 8): the
			# selected units keep following the clicked unit (Player motivation
			# state 6,; see GameUnit._follow_tick).
			if target and not target.dead:
				for u in mine:
					if u != target:
						u.command({"type": "follow", "target": target, "village_limit":village_move_limit()})
		"interact":
			if shop_available():
				# Keep the host's idle/ownership gate, then approach the NPC
				# through the ordinary cancellable order before opening topics.
				if not (target and not target.dead and not mine.is_empty() and target.village_talk_ready() \
						and not Briefings.pending_for(state, target, player).is_empty() and world.vm):
					return
				if mine[0].blocked:
					# The first village story deliberately blocks Zak until he
					# talks to the elder. Do not require walking to unlock it.
					world.vm.briefings.interact(mine[0], target, player)
					return
			if target and not mine.is_empty():
				var talker := _interaction_unit(mine, target)
				_double_stand(talker, cmd, target.pos, TALK_REACH)
				talker.command({"type": "follow", "target": target, "dist": TALK_REACH, "once": true, "run": bool(cmd.get("run", false)), "path_notice": true})
				talker.set_meta("interact", [target, player])
				# The other selected units get no order: the server's handler of
				# the use / talk packet 0x36 orders one unit only
				# (the nearest one whose path reaches the target)
				# and leaves the rest where they are.
		"cast", "direct_cast":
			var u := _hero_unit(int(cmd.get("unit", -1)), player)
			var spell := String(cmd.get("spell", "")).to_lower()
			if u and not u.dead and not u.blocked and spell in u.get_meta("hero").get("spells", []):
				var tu: GameUnit = world.units.get(int(cmd.get("target", -1)))
				u.command({"type": "cast", "spell": spell, "target": tu, "path_notice": true,
					"point": Vector2(float(cmd.get("x", u.pos.x)), float(cmd.get("y", u.pos.y)))})
		"train":
			var u := _hero_unit(int(cmd.get("unit", -1)), player)
			if u and camp_available():   # character management only in towns and camps
				var h: Dictionary = u.get_meta("hero")
				var skill := String(cmd.get("stat", ""))
				if Skills.raise(h, skill):
					Combat.hero_stats(u, h)
					sync_state()
		"perk":
			var u := _hero_unit(int(cmd.get("unit", -1)), player)
			if u and camp_available() and Perks.learn(u.get_meta("hero"), String(cmd.get("perk", ""))):
				Combat.hero_stats(u, u.get_meta("hero"))
				sync_state()
		"refund_training":
			var u := _hero_unit(int(cmd.get("unit", -1)), player)
			if u and not u.dead and camp_available():
				var h: Dictionary = u.get_meta("hero")
				if TrainingRefund.refund(h):
					Combat.hero_stats(u, h)
					sync_state()
		"equip", "unequip", "use", "give_quick", "take_quick", "select_weapon", "learn", "unlearn":
			_item_command(cmd, player)
		"buy", "sell":
			_trade(cmd, player)
		"trade":
			var ok := _trade_apply(cmd)
			_finish_trade.call_deferred(player, int(cmd.get("req", 0)), ok)
		"repair":
			_repair(cmd, player)
		"construct":
			_construct(cmd, player)
		"deconstruct":
			_deconstruct(cmd)
		"spell_constr":
			_spell_constr(cmd, player)
		"use_lever":
			var obj = world.objects.get(int(cmd.get("target", -1)))
			if obj and world.lever_sys.usable(int(cmd.target)) and not mine.is_empty():
				var p3: Vector3 = obj.get_meta("ei").position
				var operator := _lever_unit(mine, obj)
				_double_stand(operator, cmd, Vector2(p3.x, p3.y), 3.0)
				operator.command({"type": "move", "to": Vector2(p3.x, p3.y), "use_object": int(cmd.target), "gait": true, "path_notice": true,
					"run": bool(cmd.get("run", false))})
				operator.set_meta("interact", [obj, player])
		"steal":
			var thief: GameUnit = world.units.get(int(cmd.get("unit", -1)))
			if thief and thief.controller == player and not thief.blocked and target and not target.dead:
				# Approach to just inside the steal reach (ScriptVM._interact_reach).
				var sr := maxf(0.3, world.vm._interact_reach(thief, target, "steal") - 0.1)
				_double_stand(thief, cmd, target.pos, sr)
				thief.command({"type": "follow", "target": target, "dist": sr, "once": true, "run": bool(cmd.get("run", false)), "path_notice": true})
				thief.set_meta("interact", [target, player, "steal"])
		"loot":   # any dead unit (checks only = dead)
			if target and target.dead and lootable(target, player, _pid_of(player)) and not mine.is_empty():
				# Approach to just inside the loot reach (ScriptVM._interact_reach).
				var lr := maxf(0.3, world.vm._interact_reach(mine[0], target) - 0.1)
				_double_stand(mine[0], cmd, target.pos, lr)
				mine[0].command({"type": "follow", "target": target, "dist": lr, "once": true, "corpse": true, "run": bool(cmd.get("run", false)), "path_notice": true})
				mine[0].set_meta("interact", [target, player])
		"revive":   # remake option "revive": any player's unit, any party body (Revive)
			if target:
				Revive.order(self, mine, target, player, bool(cmd.get("run", false)))
		"stop":
			for u in mine:
				u.command({"type": "wait", "t": 0.1})
		"travel":
			if lmp_travel:
				# Native message6 (670dc0): a named zone for this connection,
				# including its dead hero. request validates owner/destination.
				lmp_travel.request(player, String(cmd.get("zone", "")), int(cmd.get("entrance", 1)))
			elif player == 0 or not players_include(0):
				_travel(String(cmd.zone), int(cmd.entrance))
		"side_quest":
			SideQuests.accept(self, String(cmd.get("q", "")))
		"travel_cancel":
			travel_options = []
			broadcast({"t": "travel_close"})
		"dialog_done":
			if world.vm:
				world.vm.on_briefing_complete(player, String(cmd.get("id", "")))
		"topic":   # a conversation picked from an NPC's topic list (Briefings.interact)
			if world.vm:
				world.vm.briefings.topic(player, String(cmd.get("var", "")), int(cmd.get("uid", 0)))


# ------------------------------------------------------------------ mercenaries

## `deployed`: placed with the party at a zone entry (no natural
## armour, Combat.clear_natural_armor), not hired inside the zone.
func _spawn_merc(m: Dictionary, p: Vector2, facing := 0.0, deployed := false) -> GameUnit:
	if deployed:
		m.erase("travel_waiting")   # merc_travel: farewell waits only in the old zone
		m.erase("travel_waiting_zone")
	# Co-op (remake): a joiner's mercenary whose player is away (a save loaded
	# before it rejoined) is held by a present player until it comes back
	# (_spawn_late_joiner); the record keeps its owner, so saves keep it too.
	var owner_idx := int(m.get("controller", 0))
	var lent := -1
	if not players_include(owner_idx):
		if owner_idx > 0 and state.heroes.has(owner_idx):
			lent = owner_idx
		else:
			m.controller = _merc_owner()
	var rec := state.merc_record(m)
	rec.position = Vector3(p.x, p.y, 0)
	# The mercenary keeps the id of its name (the original
	# ScriptVM.name_id): scripts and conversations find it by that id.
	rec.nid = ScriptVM.name_id(rec.name)
	if world.units.has(int(rec.nid)):
		rec.nid = world.new_uid()
	var u := world.spawn_unit(rec)
	if u:
		u.controller = int(m.controller) if lent < 0 else _merc_owner()
		if lent >= 0:
			u.set_meta("lent_of", lent)
		u.faction = 0
		u.mode = "player"
		u.facing = facing
		u.display_name = m.name
		u.set_meta("hero", m)
		if deployed:
			Combat.clear_natural_armor(u, m)
		Combat.hero_stats(u, m)
		u.aggressive = bool(m.get("aggressive", true))
		u.restore_gait(CampaignState.entry_gait(world, int(m.get("gait", 2))))
		if float(m.get("hp", -1.0)) > 0.0:
			u.hp = minf(float(m.hp), u.max_hp)
	return u


## Co-op: a new mercenary goes to the player controlling the fewest units.
func _merc_owner() -> int:
	var best := 0
	var best_n := 1 << 30
	for pl in players.values():
		var n := 0
		if world:
			for u: GameUnit in world.units.values():
				if u.controller == pl.index and not u.dead:
					n += 1
		if n < best_n:
			best_n = n
			best = pl.index
	return best


## Host: script set apartyn<N> = 1 (hired) or 0 (dismissed).
## Host: replace a player's hero units with its current roster, in place
## (script RedeployParty after SetCurrentParty).
func redeploy_party(player: int) -> void:
	var at := Vector2.INF
	var facing := 0.0
	var campaign_redeploy := player == 0 and lmp.is_empty()
	state.store_party_positions(world)
	if campaign_redeploy:
		state.collect_pets(world)
	for u: GameUnit in world.units.values():
		var character: Dictionary = u.get_meta("hero", {})
		if (u.has_meta("hero") and (u.controller == player or (campaign_redeploy and character.has("merc")))) \
				or (campaign_redeploy and CampaignState.is_pet(u)):
			if at == Vector2.INF and u.controller == player and u.has_meta("hero") and not character.has("merc"):
				at = u.pos
				facing = u.facing
			world.remove_unit(u)
			broadcast({"t": "remove", "uid": u.uid})
	if at == Vector2.INF:
		return
	var slot := 0
	for rec: Dictionary in state.party_records(player):
		var p := world.nav.nearest_walkable(at + Vector2(slot % 3 - 1, slot / 3) * 1.5 if slot else at)
		rec.position = Vector3(p.x, p.y, 0)
		rec.nid = world.new_uid()
		var u := world.spawn_unit(rec)
		if u:
			u.controller = player
			u.faction = 0
			u.mode = "player"
			u.facing = facing
			state.apply_hero(u)
			announce_unit(u)
		slot += 1
	for n in state.mercs:
		var m: Dictionary = state.mercs[n]
		if (not campaign_redeploy and int(m.get("controller", 0)) != player) or not state.merc_party_active(m) \
				or m.get("travel_waiting", false) or state.get_var(0, "adeadn%d" % n) >= 1.0:
			continue
		var p := world.nav.nearest_walkable(at + Vector2(slot % 3 - 1, slot / 3) * 1.5)
		var u := _spawn_merc(m, p, facing, true)
		if u:
			announce_unit(u)
		slot += 1
	if campaign_redeploy:
		world.set_meta("pet_party", state.pet_party())
		for pet: Dictionary in state.pets:
			if not state.pet_party_active(pet): continue
			var p := world.nav.nearest_walkable(at + Vector2(slot % 3 - 1, slot / 3) * 1.5)
			var u := _spawn_pet(pet, p, facing)
			if u: announce_unit(u)
			slot += 1
		state.replay_restored(world)
		coop.GuestRoles.redeploy(self)
	if world.vm: world.vm.resolve_script_ai_targets()
	broadcast({"t": "party"})
	sync_state()


## `player`: the one who hired it in a conversation (
##  on that player), -1 = scripts (the remake's choice: the
## player with the fewest units).
func merc_changed(n: int, hired: bool, player := -1, leave_npc := true) -> void:
	if world == null:
		return
	if not hired and player < 0 and state.mercs.get(n, {}).get("travel_waiting", false):
		return   # the farewell script removes its old unit, not the carried record
	if hired and not state.mercs.has(n):
		var npc: GameUnit = null
		for u: GameUnit in world.units.values():
			if String(u.info.get("name", "")).to_lower() == "merc%d" % n and not u.has_meta("hero"):
				npc = u
		var rec: Dictionary = npc.info.duplicate() if npc else _find_merc_record(n)
		if rec.is_empty():
			return
		var m := state.make_merc(n, rec, CampaignState.script_character(npc))
		m.controller = player if player >= 0 and players_include(player) else _merc_owner()
		if npc:
			#  adds a roster entry, not a new server unit. Keep its
			# live equipment, body, magic, stamina and pending script commands.
			m.village_mode = npc.mode
			m.village_faction = npc.faction
			_set_merc_control(npc, m, true)
			broadcast({"t": "merc_control", "uid": npc.uid, "hired": true,
				"character": m, "snap": npc.snapshot(), "stats": npc.stats})
		else:
			var heroes := party_heroes()
			var at: Vector2 = (heroes[0].pos if not heroes.is_empty() else Vector2.ZERO) + Vector2(1, 1)
			var u := _spawn_merc(m, world.nav.nearest_walkable(at))
			if u:
				announce_unit(u)
		broadcast({"t": "party"})
		sync_state()
	elif not hired and state.mercs.has(n):
		var m: Dictionary = state.mercs[n]
		state.mercs.erase(n)
		for u: GameUnit in world.units.values():
			if u.has_meta("hero") and is_same(u.get_meta("hero"), m):
				var home := false
				for r: Dictionary in (world.map.unit_records if world.map else []):
					if String(r.get("name", "")).to_lower() == "merc%d" % n:
						home = true
				if leave_npc and home and not u.dead:
					# n2 only destroys the party record (6620b0). The same mutable
					# character stays for the authored walk back and later rehire.
					_set_merc_control(u, m, false)
					broadcast({"t": "merc_control", "uid": u.uid, "hired": false,
						"character": m, "snap": u.snapshot(), "stats": u.stats})
				else:
					world.remove_unit(u)
					broadcast({"t": "remove", "uid": u.uid})
		broadcast({"t": "party"})
		sync_state()


## Mercenary membership changes on the existing server character. The host
## sends this through its authority-only reliable event RPC before roster sync.
func _set_merc_control(u: GameUnit, m: Dictionary, hired: bool) -> void:
	if hired:
		u.remove_meta("npc_character")
		u.set_meta("hero", m)
		u.controller = int(m.controller)
		u.faction = 0
		u.mode = "player"
		u.display_name = String(m.name)
		Combat.hero_stats(u, m)
		u.refresh_max_hp()
	else:
		u.remove_meta("hero")
		u.remove_meta("lent_of")
		u.controller = -1
		u.faction = int(m.get("village_faction", 0))
		u.mode = String(m.get("village_mode", "standard"))
		u.set_meta("npc_character", m.duplicate(true))
	# Explicit empty lists are mutable inventory, not absent prototype defaults.
	# The model already wears this same kit; no figure/playback reset is needed.
	u.info.armors = PackedStringArray(m.get("armors", []))
	u.info.weapons = PackedStringArray(m.get("weapons", []))
	u.info.spells = PackedStringArray(m.get("spells", []))
	u.info.quick_items = PackedStringArray(m.get("quick", []))


## Map record of mercenary N from the hub maps (for hiring outside the hub).
func _find_merc_record(n: int) -> Dictionary:
	for mob_name in ["basecam", "bz2g"]:
		var mob := EIMob.load_bytes(GameData.read_file("maps/%s.mob" % mob_name))
		if mob == null:
			continue
		for o in mob.objects:
			if o.kind == "UNIT" and String(o.get("name", "")).to_lower() == "merc%d" % n:
				return o
	return {}


# ------------------------------------------------------------------ items

const WEAPON_SLOTS := 4


## Stable player weapon cells, independent of the active-first
## weapons array used by the remake's combat code. Older saves start with
## their saved order; item wear changes retain the same cell by base item.
static func weapon_slots(h: Dictionary) -> Array:
	var left: Array = Array(h.get("weapons", [])).duplicate()
	var out := []
	for old in h.get("weapon_slots", []):
		var i := find_item(left, String(old))
		if i >= 0:
			out.append(left.pop_at(i))
	out.append_array(left)
	return out.slice(0, WEAPON_SLOTS)


## nearest living hostile unit on the issuing player's relevant
## object list. No extra distance limit or AI perception/cone test. Hostility
## is directional: the candidate's masks towards the caster's
## side, rather than the caster's opinion of the candidate.
func belt_enemy(caster: GameUnit) -> GameUnit:
	if world == null or not is_instance_valid(caster):
		return null
	var best: GameUnit
	var d := 1e38
	for u: GameUnit in UnitFog.relevant_for(self, caster.controller):
		if u.dead or not world.is_enemy(u, caster):
			continue
		var dist := caster.pos.distance_squared_to(u.pos)
		if dist < d:
			d = dist
			best = u
	return best


func _hero_unit(uid: int, player: int) -> GameUnit:
	var u: GameUnit = world.units.get(uid) if world else null
	return u if u and u.controller == player and u.has_meta("hero") else null


## Host: equipment and item use. The bag (state.items) is shared by the party.
func _item_command(cmd: Dictionary, player: int) -> void:
	var u := _hero_unit(int(cmd.get("unit", -1)), player)
	if u == null:
		return
	# Immediate belt use shares the cast messages (6374c0 / 637710 ->
	# 6707e0 / 670890); the hand-change message 670920 uses the same block
	# and dead guards. These single-unit commands bypass the units-list gate.
	if String(cmd.t) in ["use", "select_weapon"] and (u.blocked or u.dead):
		return
	var h: Dictionary = u.get_meta("hero")
	var item := String(cmd.get("item", "")).to_lower()
	# Equipment, runes and enchanting are town/camp business in the original
	# (camp_available: a village or the global map's camp); in the field only
	# the belt can be used.
	if String(cmd.t) in ["equip", "unequip", "take_quick", "learn", "unlearn"] and not camp_available():
		return
	match String(cmd.t):
		"equip":
			# The bag entry itself, with its wear / charge suffix (find_item).
			var bag_i := find_item(state.items, item)
			if bag_i < 0:
				return
			item = state.items[bag_i]
			var sl := Items.slot(item)
			if sl.is_empty() or Items.is_broken(item):
				return
			#  rejects a fifth weapon before taking it from the bag.
			if sl == "weapon" and h.weapons.size() >= WEAPON_SLOTS:
				return
			state.items.remove_at(bag_i)
			if sl == "weapon":
				#  appends to the player's list. The active
				# index changes only when this is the first weapon.
				var slots := weapon_slots(h)
				slots.append(item)
				h.weapon_slots = slots
				h.weapons.append(item)
			else:
				var keep := []
				for old in h.armors:
					if Items.slot(old) == sl:
						state.items.append(old)
					else:
						keep.append(old)
				keep.append(item)
				h.armors = keep
			_refresh_hero(u)
		"select_weapon":
			# Weapon display click: make a carried weapon the active one (field too).
			var wi: int = h.weapons.find(item)
			if wi <= 0:
				return
			h.weapon_slots = weapon_slots(h)
			h.weapons.remove_at(wi)
			h.weapons.insert(0, item)
			_refresh_hero(u)
		"unequip":
			var wi := find_item(h.weapons, item)
			var ai := find_item(h.armors, item) if wi < 0 else -1
			if wi >= 0:
				item = h.weapons[wi]
				var slots := weapon_slots(h)
				var si := find_item(slots, item)
				if si >= 0:
					slots.remove_at(si)
				h.weapon_slots = slots
				h.weapons.remove_at(wi)
				if wi == 0 and not slots.is_empty():
					#  keeps the active slot index, clamped to the
					# last after removal; the following weapon takes its place.
					var active := String(slots[clampi(si, 0, slots.size() - 1)])
					var next: int = h.weapons.find(active)
					if next > 0:
						h.weapons.remove_at(next)
						h.weapons.insert(0, active)
			elif ai >= 0:
				item = h.armors[ai]
				h.armors.remove_at(ai)
			else:
				return
			state.items.append(item)
			_refresh_hero(u)
		"give_quick":
			var bag_i := find_item(state.items, item)
			# At most four belt entries (CampaignState.BELT_SLOTS).
			if bag_i >= 0 and Items.kind(item) == "quick" and h.get("quick", []).size() < CampaignState.BELT_SLOTS:
				item = state.items[bag_i]
				state.items.remove_at(bag_i)
				h.get_or_add("quick", []).append(item)
				sync_state()
		"take_quick":
			# A belt item back to the bag: the camp screen's take-off of a quick
			# item (case 0x3006: off the player's
			# list into the bag).
			var q: Array = h.get("quick", [])
			var qi := find_item(q, item)
			if qi < 0:
				return
			item = q[qi]
			q.remove_at(qi)
			state.items.append(item)
			sync_state()
		"learn":
			# A spell container from the bag into the hero's spells (the camp's
			# drop checks: the spell's complexity
			#  within round(knowledge of its school) and
			# its stamina within the hero's).
			var bag_i := state.items.find(item)
			if bag_i < 0 or not item.begins_with("spell:"):
				return
			var known: Array = h.get_or_add("spells", [])
			#  case0x3008 caps eight objects
			# appends another spell object even when its contents match.
			if known.size() >= 8:
				return
			if not Spells.usable_by(h, u.max_mana, item.substr(6)):
				return
			state.items.remove_at(bag_i)
			known.append(item.substr(6))
			sync_state()
		"unlearn":
			# The skills screen's take-off of a spell (area 0
			#  case 0x3008: off the player's list
			#  into the bag as a spell container).
			var known: Array = h.get("spells", [])
			var sp := item.trim_prefix("spell:")
			var ki := known.find(sp)
			if ki < 0:
				return
			known.remove_at(ki)
			state.items.append("spell:" + sp)
			sync_state()
		"use":
			var q: Array = h.get("quick", [])
			var qi := find_item(q, item)
			if qi < 0 or u.dead:
				return
			# Potions / scrolls are spells in items.idb ("healing {e1}"), wands
			# carry theirs as an enchantment. the original: offensive
			# spells go to the nearest hostile unit in view
			#  — none: nothing happens ("nomagic") — everything
			# else to the holder; point spells at the target's feet.
			var sp := Items.potion_spell(item)
			if sp.is_empty():
				sp = Items.spell_of(item)
			if sp.is_empty():
				return
			# Targeted use (: one click selects the belt item, the
			# next picks the target): the holder casts it like a spell, walking
			# into range; the item goes when the cast starts (GameUnit._do_cast).
			if cmd.has("target") or cmd.has("x"):
				var tu: GameUnit = world.units.get(int(cmd.get("target", -1)))
				item = String(q[qi])   # validate the current charge, not a stale client item id
				var wand := Items.is_wand(item)
				if (not wand and int(Items.info(item).get("row", {}).get("item_id", -1)) != 8) \
						or (wand and (Items.charge(item) < float(Spells.parse(sp).mana) or u.cannot_cast())):
					return
				var point := bool(Spells.parse(sp).point)
				if not point and (tu == null or tu.dead or (not wand and tu != u)):
					return   #  mode 3: unit-target potions are self-only
				if cmd.has("target") and (tu == null or tu.dead):
					return
				var at := tu.pos if tu else Vector2(float(cmd.get("x", 0.0)), float(cmd.get("y", 0.0)))
				if point and at == Vector2.ZERO:
					return   # native point pick's (0, 0) invalid sentinel
				u.command({"type": "cast", "spell": sp, "target": null if point else tu, "item": item, "point": at})
				return
			var tgt := u
			if Spells.offensive(sp):
				tgt = belt_enemy(u)
				if tgt == null:
					return
			if Items.is_wand(item):
				if not use_charge(q, qi):
					return
			else:
				q.remove_at(qi)
			Spells.cast_unit(world, u, sp, tgt, tgt.pos)
			sync_state()


## A targeted belt use starting its cast: takes the item off the belt
## (false if it is no longer there).
func consume_quick(u: GameUnit, item: String) -> bool:
	if not u.has_meta("hero"):
		return false
	var h: Dictionary = u.get_meta("hero")
	var q: Array = h.get("quick", [])
	var qi := find_item(q, item)
	if qi < 0:
		return false
	if Items.is_wand(q[qi]):
		return use_charge(q, qi)
	q.remove_at(qi)
	sync_state()
	return true


## Index of `item` in `list`: that very string, else (a command sent before
## the item's state last changed) the first entry that is the same item
## whatever its wear / charge; -1 if none.
static func find_item(list: Array, item: String) -> int:
	var i := list.find(item)
	if i >= 0:
		return i
	var base := Items.unworn(item)
	for j in list.size():
		if list[j] is String and Items.unworn(list[j]) == base:
			return j
	return -1


## A wand use: the original allows it only while the spell's stamina
##  ≤ the charge; subtracts it, the wand stays (also
## 0), and queues the item for the clients (here the hero record
## in the synced state).
func use_charge(list: Array, i: int) -> bool:
	var sp := Items.spell_of(list[i])
	if not spend_charge(list, i, float(Spells.parse(sp).mana) if not sp.is_empty() else 0.0):
		return false
	sync_state()
	return true


##  for any charged item (wand, enchanted weapon or armour)
## `list[i]`: its charge (`Items.charge`, carried on the item string)
## loses `cost` when it holds at least that much (more than that with
## `strict`, the periodic check); false = nothing spent.
static func spend_charge(list: Array, i: int, cost: float, strict := false) -> bool:
	var it := String(list[i])
	var cur := Items.charge(it)
	if cur < cost or strict and cur <= cost:
		return false
	list[i] = Items.with_charge(it, cur - cost)
	return true


func _refresh_hero(u: GameUnit) -> void:
	_refresh_character(u, u.get_meta("hero"))


func _refresh_character(u: GameUnit, h: Dictionary) -> void:
	Combat.hero_stats(u, h)
	u.set_equipment(PackedStringArray(h.armors), PackedStringArray(h.weapons))
	broadcast({"t": "equip", "uid": u.uid, "armors": h.armors, "weapons": h.weapons, "stats": u.stats})
	sync_state()


func shop_available() -> bool:
	return world != null and String(world.zone.get("type", "")) == "brief"


## Classic safe-zone controls. Scripted attacks, casts and escape orders
## bypass player command dispatch and retain their authored behavior.
func command_allowed(cmd: Dictionary) -> bool:
	if not shop_available(): return true
	match String(cmd.get("t", "")):
		"attack", "cast", "steal", "use", "aggression": return false
		"gait": return int(cmd.get("gait",2)) >= 2
		"move": return not bool(cmd.get("swarm",false))
	return true


## The authored village view circle is also the boundary for remake free
## walking. Native story movement and conversation staging are not clipped.
func village_move_limit() -> Vector3:
	if not shop_available(): return Vector3.ZERO
	# The slave pen confines the party until the authored night escape breaks
	# its barrier. Keeping the circle afterward turns a player's run-away
	# click back toward Terror's fire, even after the script led them outside.
	if state.campaign_id == CampaignProfile.ASTRAL and zone_id == "bz1h" \
			and state.get_var(0,"bz1h_night") == 2.0:
		var barrier: GameUnit = world.units.get(1001009)
		if barrier == null or barrier.dead: return Vector3.ZERO
	return world.zone.get("restrict", Vector3.ZERO)


## Character management (equipment, belt, skills, abilities, spells): in a
## village, and at the global map's camp. The map's camp button opens the same
## camp screen ((5) → with
## constr.current 0, the dressing screen) whose put-on / take-off handlers
##  change the hero's player record and touch a
## world figure only when the hero has one (camp ≠ 0); there is
## no zone check. In the field only the belt is used.
func camp_available() -> bool:
	return shop_available() or map_open


## The trader whose camp screen is open: script var "constr.current" (set by a
## "constr<N>" topic, Briefings.topic; 0 on the camp / dressing screen). A
## command may name its trader ("shop"), as each co-op player has their own
## camp screen.
func shop_id(cmd := {}) -> int:
	var n := int(cmd.get("shop", 0)) if cmd.has("shop") else int(state.get_var(0, "constr.current"))
	return n if Shops.exists(n) and shop_available() else 0


## A trader's saved record (created on first use with the restock flag set, as
##  builds every record at a new game).
func shop_record(id: int) -> Dictionary:
	if not state.shops.has(id):
		state.shops[id] = Shops.blank()
	return state.shops[id]


## Host: a trader's camp screen opens: restock if flagged, with
## the party's best knowledge per school (over the party units).
func open_shop(id: int) -> void:
	if not Shops.exists(id):
		return
	var rec := shop_record(id)
	if bool(rec.get("restock", true)):
		var best := {}
		var party: Array = []
		for l in state.heroes.values():
			party += l
		for m: Dictionary in state.mercs.values():
			if state.merc_party_active(m):
				party.append(m)
		for h: Dictionary in party:
			for st: String in Skills.SCHOOL:
				best[st] = maxf(float(best.get(st, -1e20)), Skills.knowledge(h, st))
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		rec.goods = Shops.generate(id, rec.get("sold", {}), best, rng)
		rec.restock = false
	Shops.migrate_stock(id, rec)
	sync_state()


## Script QuestComplete in single player: every
## trader restocks the next time its screen opens.
func restock_shops() -> void:
	for id: int in Shops.records():
		shop_record(id).restock = true


func shop_stock(cmd := {}) -> Array:
	var id := shop_id(cmd)
	if id == 0:
		return []
	var out := []
	var goods: Dictionary = shop_record(id).get("goods", {})
	for it: String in goods:
		if int(goods[it]) > 0:
			out.append(it)
	return out


func shop_count(item: String, cmd := {}) -> int:
	var id := shop_id(cmd)
	return int(shop_record(id).get("goods", {}).get(item, 0)) if id else 0


## A confirmed pile settles once. In particular a guest's personal purse
## must be restored before the snapshot and acknowledgement are published.
const MAX_TRADE_ITEMS := 4096

func _trade(cmd: Dictionary, _player: int) -> void:
	var batch := cmd.duplicate()
	batch.buy = [cmd.get("item", "")] if cmd.t == "buy" else []
	batch.sell = [cmd.get("item", "")] if cmd.t == "sell" else []
	if _trade_apply(batch): sync_state()


func _finish_trade(player: int, req: int, ok: bool) -> void:
	sync_state()
	broadcast({"t":"trade_result", "to":player, "req":req, "ok":ok})


func _trade_apply(cmd: Dictionary) -> bool:
	var sid := shop_id(cmd)
	var buy: Variant = cmd.get("buy", [])
	var sell: Variant = cmd.get("sell", [])
	if sid == 0 or not buy is Array or not sell is Array: return false
	if buy.size()+sell.size() == 0 or buy.size()+sell.size() > MAX_TRADE_ITEMS: return false
	# Work on copies: a stale stock count or unaffordable purchase must not
	# leave half a deal behind. Exact item strings retain wear and charge.
	var rec := shop_record(sid).duplicate(true)
	var bag := state.items.duplicate()
	var money := state.money
	var rates := Shops.coef(sid)
	for entries: Array in [sell, buy]:
		for value in entries:
			if not value is String: return false
			var item := String(value).to_lower()
			var spellish := Items.is_spell_piece(item)
			if not (Shops.sells_spells(sid) if spellish else Shops.sells_items(sid)): return false
			if Items.kind(item) in ["", "quest"]: return false
	for value: String in sell:
		var item := value.to_lower()
		var i := bag.find(item)
		if i < 0: return false
		bag.remove_at(i)
		money += Items.deal_price(item, Items.Deal.SPELL_SELL if Items.is_spell_piece(item) else Items.Deal.SELL, rates)
		_sold_to(rec, item)
	for value: String in buy:
		var item := value.to_lower()
		if int(rec.goods.get(item,0)) <= 0: return false
		money -= Items.deal_price(item, Items.Deal.SPELL_BUY if Items.is_spell_piece(item) else Items.Deal.BUY, rates)
		_take_goods(rec.goods, item, 1)
		bag.append(item)
	if money < 0: return false
	state.money = money
	state.items = bag
	state.shops[sid] = rec
	return true


func _take_goods(goods: Dictionary, item: String, n: int) -> void:
	goods[item] = int(goods.get(item, 0)) - n
	if int(goods[item]) <= 0:
		goods.erase(item)


## What the trader does with a sold item (modes 2 / 4): it joins
## the trader's goods at full durability, except loot of kind
## 0 (trophies), which is destroyed; the prototype of a sold
## weapon, armour, wand, blueprint, spell, keystone or rune joins the record's
## lists, so restocks offer it too.
func _sold_to(rec: Dictionary, item: String) -> void:
	var plain := Items.unworn(item)
	if Items.kind(plain) == "loot":
		return
	var kept := Items.with_wear(item, 0.0)   # the charge stays
	rec.goods[kept] = int(rec.goods.get(kept, 0)) + 1
	var table := ""
	var key := ""
	if Items.is_spell_container(plain) or Items.is_keystone(plain):
		table = "spell_prototypes"
		key = String(Spells.parse(Items.spell_code(plain)).code)
	elif plain.begins_with("rune:"):
		table = "spell_modifiers"
		key = plain.substr(5)
	elif plain.begins_with("bp:"):
		var r := Items.info(plain.substr(3))
		table = String(r.table)
		key = String(r.base)
	elif Items.kind(plain) in ["weapon", "armor"] or Items.kind(plain) == "quick" and not Items.info(plain).mat.is_empty():
		var r := Items.info(plain)
		table = String(r.table)
		key = String(r.base)
	if table in ["weapons", "armors", "quick_items", "spell_prototypes", "spell_modifiers"] and key != "":
		var l: Array = rec.sold.get_or_add(table, [])
		if not key in l:
			l.append(key)


## Host: item constructor (Items.construct_price). Pieces come from the
## inventory first; missing ones are bought from the shop at their buy price
## (camphelp 102, mode 5).
func _construct(cmd: Dictionary, player: int = 0) -> void:
	var sid := shop_id(cmd)
	if sid == 0 or not Shops.sells_items(sid):
		return
	var bp := String(cmd.get("bp", "")).to_lower()
	var mat := String(cmd.get("mat", "")).to_lower()
	if not bp.begins_with("bp:") or not Items.materials_for(bp).any(func(m): return String(m.name).to_lower() == mat):
		return
	var need := {bp: 1, Items.material_unit(mat): Items.components(bp)}
	var cost := Items.construct_price(bp, mat)
	var take := {}
	for piece: String in need:
		var have := state.items.count(piece)
		take[piece] = mini(have, int(need[piece]))
		var missing := int(need[piece]) - int(take[piece])
		if missing > 0:
			if shop_count(piece, cmd) < missing:
				return
			cost += missing * Items.buy_price(piece)
	# Optional spell slot (: the spell lying in the pile
	# goes onto the item and is used up): "spell:<id>" from the
	# bag, or a known spell of hero "unit". It must fit the item (
	# mode 5, Items.can_enchant) and, as every pile piece, adds trunc(its price
	# × the constructor coefficient) to the deal (mode 5
	# (piece, 6)).
	var item := "%s.%s" % [bp.substr(3), mat]
	var spell := String(cmd.get("spell", "")).to_lower()
	var known: Array = []
	if spell != "":
		if not spell.begins_with("spell:"):
			var hu := _hero_unit(int(cmd.get("unit", -1)), player)
			if hu == null:
				return
			known = hu.get_meta("hero").get_or_add("spells", [])
			if not spell in known:
				return
		elif not spell in state.items:
			return
		if not Items.can_enchant(item, spell.trim_prefix("spell:")):
			return
		cost += Items.constr_piece_price("spell:" + spell.trim_prefix("spell:"))
	if state.money < cost:
		return
	state.money -= cost
	for piece: String in take:
		for k in int(take[piece]):
			state.items.erase(piece)
		if int(need[piece]) > int(take[piece]):
			_take_goods(shop_record(sid).goods, piece, int(need[piece]) - int(take[piece]))
	if spell.begins_with("spell:"):
		state.items.erase(spell)
	elif spell != "":
		known.erase(spell)
	if spell != "":
		item += "|" + spell.trim_prefix("spell:")
	state.items.append(item)
	sync_state()


## Host: take an inventory item apart into its blueprint and material units
## (and its spell, see below).
func _deconstruct(cmd: Dictionary) -> void:
	var sid := shop_id(cmd)
	if sid == 0 or not Shops.sells_items(sid):
		return
	var item := String(cmd.get("item", ""))
	var i := state.items.find(item)
	if i < 0 or not Items.can_deconstruct(item):
		return
	var cost := Items.deconstruct_price(item)
	if state.money < cost:
		return
	state.money -= cost
	state.items.remove_at(i)
	var inf := Items.info(item)
	var bp := "bp:" + String(inf.base)
	state.items.append(bp)
	for k in Items.components(bp):
		state.items.append(Items.material_unit(String(inf.material)))
	# an item with a spell also gives back a "spell
	# container" (0x3008) carrying that spell.
	if Items.spell_of(item) != "":
		state.items.append("spell:" + Items.spell_of(item))
	sync_state()


## The party whose best knowledge / stamina the spell constructor uses
## (walks the player's party): the
## heroes and mercenaries `player` controls.
func party_units(player: int) -> Array:
	var out := []
	if world:
		for u: GameUnit in world.units.values():
			if u.controller == player and u.has_meta("hero"):
				out.append(u)
	return out


## The spell group of trader `sid` with the camp's GS overrides (:
## record, i.offspellconstr / i.onspellconstr, i.noconstr hides the
## constructor).
func spell_constr_offered(sid: int) -> bool:
	if sid == 0 or is_equal_approx(state.get_var(0, "i.noconstr"), 1.0):
		return false
	if is_equal_approx(state.get_var(0, "i.onspellconstr"), 1.0):
		return true
	return Shops.sells_spells(sid) and not is_equal_approx(state.get_var(0, "i.offspellconstr"), 1.0)


## Host: the spell constructor's ✓ (mode 3, the deal
##  mode 3) as one transaction; the answer goes back to the
## player's camp screen ("constr_result": ok, op, the resulting items and
## where the built spell went). Nothing is changed unless everything passes.
## cmd.pile = [[id, from], ...]: first the spell ("spell:<id>"), then the
## runes ("rune:<code>"); from = "bag", "shop" (the trader's goods
## marks such a piece) or "known" (one of hero "unit"'s spells:
## the remake lists them in the bag row; in the original the hero puts the
## spell into the bag first).
## - A ready spell alone = take apart: costs trunc(price ×
##   0.1) (mode 3); it is replaced by its keystone ("Prototype", = the
##   spell's prototype) and one rune per modifier byte, in that order.
## - A keystone + runes = build: the builder takes the keystone
##    and each rune (per type), and
##   the built spell must fit the party's best knowledge (≥ its complexity
## ) and stamina (≥ __ftol of its cost). Costs
##   Σ trunc(piece price × 0.2) (mode 2). The pile is emptied and the new spell
##   container takes its place.
## Each piece from the trader also costs its buy price (mode 0) and leaves the
## goods. Money: party −= the total; ✓ is dimmed when it is short.
## The pile is the remake's camp screen; its pieces leave the pile for the bag
## (case 6: party pieces and the constructor's own results go to
## the party), so the host puts the results in the bag; a spell built from a
## hero's known spell goes back on that hero when he could learn it there
## (the learn check, Spells.usable_by), else into the bag.
## A "keystone:<code>" builds even without runes; "spell:<code>" is always
## a ready container, including old saves and zero-rune spells.
func _spell_constr(cmd: Dictionary, player: int) -> void:
	var res := _spell_constr_apply(cmd, player)
	broadcast({"t": "constr_result", "to": player, "req": int(cmd.get("req", 0)), "ok": not res.is_empty(),
		"op": String(res.get("op", "")), "items": res.get("items", []), "where": String(res.get("where", ""))})


func _spell_constr_apply(cmd: Dictionary, player: int) -> Dictionary:
	var sid := shop_id(cmd)
	if not spell_constr_offered(sid):
		return {}
	var pile: Array = cmd.get("pile", [])
	if pile.is_empty() or pile.size() > 1 + Spells.MAX_MODS:
		return {}
	var ids: Array[String] = []
	var froms: Array[String] = []
	for e in pile:
		if not (e is Array and e.size() == 2):
			return {}
		ids.append(String(e[0]).to_lower())
		froms.append(String(e[1]))
	if not (Items.is_spell_container(ids[0]) or Items.is_keystone(ids[0])) \
			or not froms[0] in ["bag", "shop", "known"]:
		return {}
	if froms[0] == "known" and not Items.is_spell_container(ids[0]):
		return {}
	for i in range(1, ids.size()):
		if not ids[i].begins_with("rune:") or not froms[i] in ["bag", "shop"]:
			return {}
	var spell := Items.spell_code(ids[0])
	if Spells.parse(spell).proto.is_empty():
		return {}
	var take_apart := Items.is_spell_container(ids[0])
	if not take_apart and not Spells.mods_of(spell).is_empty():
		return {}
	#  mode 3: a ready spell takes the pile alone; runes need a keystone.
	if take_apart and ids.size() > 1:
		return {}
	# The pieces must be there: bag / trader counts, or the hero's spell.
	var hu := _hero_unit(int(cmd.get("unit", -1)), player)
	var known: Array = hu.get_meta("hero").get_or_add("spells", []) if hu else []
	var need := {"bag": {}, "shop": {}}
	for i in ids.size():
		if froms[i] == "known":
			if hu == null or not spell in known:
				return {}
		else:
			need[froms[i]][ids[i]] = int(need[froms[i]].get(ids[i], 0)) + 1
	for id: String in need.bag:
		if _count_unworn(state.items, id) < int(need.bag[id]):
			return {}
	if not need.shop.is_empty() and not Shops.sells_spells(sid):
		return {}
	for id: String in need.shop:
		if shop_count(id, cmd) < int(need.shop[id]):
			return {}
	# The deal (mode 3, prices with the record's coef).
	var coef := Shops.coef(sid)
	var cost := 0
	if take_apart:
		cost = int(float(Items.price(ids[0])) * float(coef[Items.Deal.SPELL_DECONSTR]))
	else:
		for id in ids:
			cost += int(float(Items.price(id)) * float(coef[Items.Deal.SPELL_CONSTR]))
	for i in ids.size():
		if froms[i] == "shop":
			cost += int(float(Items.price(ids[i])) * float(coef[Items.Deal.SPELL_BUY]))
	var built := spell
	if not take_apart:
		for i in range(1, ids.size()):
			var code := ids[i].substr(5)
			if not Spells.constr_rune_fits(spell, i - 1, code):
				return {}
			built = Spells.with_mod(built, code)
		if not Spells.constr_buildable(party_units(player), built):
			return {}
	if state.money < cost:
		return {}
	# Settle money and pieces together.
	state.money -= cost
	for id: String in need.bag:
		for k in int(need.bag[id]):
			state.items.remove_at(find_item(state.items, id))
	for id: String in need.shop:
		_take_goods(shop_record(sid).goods, id, int(need.shop[id]))
	var ki := known.find(spell) if froms[0] == "known" else -1
	if ki >= 0:
		known.remove_at(ki)
	var out := {"op": "take_apart" if take_apart else "build", "items": [], "where": "bag"}
	if take_apart:
		out.items.append("keystone:" + String(Spells.parse(spell).code))
		for m in Spells.mods_of(spell):
			out.items.append("rune:" + m)
		state.items.append_array(out.items)
	else:
		out.items.append("spell:" + built)
		state.items.append("spell:" + built)
	sync_state()
	return out


## How many entries of `list` are `id` whatever their per-instance state.
static func _count_unworn(list: Array, id: String) -> int:
	var n := 0
	var base := Items.unworn(id)
	for x in list:
		if x is String and (x == id or Items.unworn(x) == base):
			n += 1
	return n


## Host: repair in a settlement (the original shop mode 8): the
## worn part of the price, back to full durability (tutorial it012).
func _repair(cmd: Dictionary, player: int) -> void:
	var sid := shop_id(cmd)
	if sid == 0 or not Shops.sells_items(sid):
		return
	var item := String(cmd.get("item", ""))
	var lists: Array = [state.items]
	var u := _hero_unit(int(cmd.get("unit", -1)), player)
	if u:
		lists = [u.get_meta("hero").weapons, u.get_meta("hero").armors, state.items]
	for l: Array in lists:
		var i := l.find(item)
		if i < 0:
			continue
		var p := Items.repair_price(item)
		if p > state.money:
			return
		state.money -= p
		l[i] = Items.with_wear(item, 0.0)   # only, the charge stays
		if u and l != state.items:
			_refresh_hero(u)
		else:
			sync_state()
		return


## Host: Use/Steal on a living unit, the original (sub-code 1).
## No random roll and no facing, light or awareness term: the theft works
## when the thief's value is above the target's (`steal_value`). Otherwise
## (thief, target): the thief's side goes into the target's own
## hostility mask (no hit hook, no line on screen) and nothing is taken. A
## unit of a player gives nothing. Success takes, one per theft, the
## first item of the target's bag (: unit, filled from the
## .mob UNIT_QUEST_ITEMS and GiveUnitQuestItem); with the bag
## empty it takes the rest at once like looting a body (
## the prototype's items, its loot and rare-loot money rolls, the
## belt), and the unit counts as looted (flag, WasLooted: a later
## theft and its corpse give nothing). Both go to the player's message window
## (message 6); nothing to take → the thief's ack 0x22 (StealEmp).
## Remake: the target's "pockets" are its rolled loot (Items.roll_loot).
func steal(u: GameUnit, t: GameUnit) -> void:
	if steal_value(u) <= steal_value(t):
		if t.faction != u.faction and world.relation(t.faction, u.faction) != 2:
			world.ai._hate(t, u.faction)
		return
	if t.controller >= 0:
		return
	if not t.has_meta("pockets"):
		t.set_meta("pockets", Items.roll_loot(t.proto, t.info, world.combat.rng))
	var pockets: Array = t.get_meta("pockets")
	var bag := Array(t.info.get("quest_items", [])).map(func(x): return String(x).to_lower())
	var take := []
	for i in pockets.size():
		if bag.has(String(pockets[i])):
			take.append(pockets.pop_at(i))
			break
	if take.is_empty() and not t.get_meta("looted", false):
		take = pockets.duplicate()
		pockets.clear()
		t.set_meta("looted", true)
	var got := []
	var money := 0
	for it: String in take:
		var st := Items.parse_stack(it)
		if st[0] == "money":
			state.money += st[1]
			money += st[1]
		else:
			add_item(st[0], st[1])
			got.append(st[0])
	if got.is_empty() and money <= 0:
		u.ack(EIAcks.STEAL_EMPTY)
		return
	notify_got(loot_player(u), got, money)
	SmileFaces.unit(self, u)   # remake option "smile_faces": a successful theft
	sync_state()


## The Use/Steal value (index 0, used by both Use and Steal):
## a character (unit id in [1e9, 2e9)) Dex − 25 + its Use/Steal skill (+ the
## best belt item modifier, all 0 in items.idb); any other unit its stats
## byte = round of the prototype's "steal skills" (
## an imported .mob record's s41 low byte, Combat.mob_import) — not its
## "general skills" (the combat skills..).
static func steal_value(u: GameUnit) -> float:
	if u.has_meta("hero"):
		return float(u.stats.get("dex", 25.0)) - 25.0 + Skills.level(u.get_meta("hero"), "science")
	if u.uid >= 1000000000 and u.uid < 2000000000:
		var npc := GameData.db.find("npcs", String(u.proto.get("name", "")))
		if not npc.is_empty():
			return float(npc.get("dex", 25.0)) - 25.0 + float(Skills.from_npc(npc).get("science", 0))
	return roundf(float(u.proto.get("steal_skills", 0.0)))


## A corpse the party may loot: every dead unit in the original. **Remake-only**
## exception: heroes and mercenaries (their bodies come back with respawn /
## the party; the original's own player corpses, flag
## carry a drop record instead, not ported).
## `conn`: the asking player's connection (peer id, 0 = not checked).
static func lootable(u: GameUnit, player := -1, conn := 0) -> bool:
	if u.has_meta("lmp_owner"):   # LMP hero body: its owner's connection only
		var owner_conn := int(u.get_meta("lmp_conn", 0))
		return u.dead and (player < 0 or (player == int(u.get_meta("lmp_owner")) \
			and (conn == 0 or owner_conn == 0 or conn == owner_conn)))
	return u.dead and not u.has_meta("hero")


## Host: a hero reached a corpse; the party takes everything it carried and
## the body is gone (the original, the loot action 6 /:
##  moves the corpse's items and money to the
## player and sets its looted flag +8 |= (WasLooted), then
##  = RemoveObjectFromServer removes it at once, whether or not
## it carried anything; no fade, the clients get net message 0x42 = the
## remake's "remove"), then the noise (× 1.5).
func take_loot(u: GameUnit, corpse: GameUnit) -> void:
	var loot: Array = corpse.get_meta("loot", []) if not corpse.get_meta("looted", false) else []
	corpse.remove_meta("loot")
	corpse.set_meta("looted", true)   # script builtin WasLooted
	broadcast({"t": "loot", "uid": corpse.uid, "has": false})
	world.remove_looted(corpse)
	broadcast({"t": "remove", "uid": corpse.uid})
	# after the body is gone: the looting is heard
	# (: the looter's hearing detectability × 1.5, 26 ticks).
	world.ai.noise_event(u, u.detect(3) * 1.5)
	var got := []
	var money := 0
	for it: String in loot:
		if it.begins_with("bag:"):   # an LMP body's bag item, whole (_lmp_respawn)
			state.items.append(it.substr(4))
			got.append(it.substr(4))
			continue
		var st := Items.parse_stack(it)
		if st[0] == "money":
			state.money += st[1]
			money += st[1]
		else:
			add_item(st[0], st[1])
			got.append(st[0])
	notify_got(loot_player(u), got, money)
	if not got.is_empty() or money > 0:
		SmileFaces.unit(self, u)   # remake option "smile_faces"
	sync_state()


## The player whose purse and bag a unit's loot and theft go to: the original
##  hands the body's money and items and a stolen
## item to the unit's owning player (unit), not to
## whoever gave the order. A co-op joiner's mercenary held by another player
## while its own is away (_spawn_merc "lent_of") still belongs to its player's
## party (its record keeps the owner), so its finds go to that player's own
## purse and bag (the joiner entry, CoopProgress.purse_entry), which it gets
## back when it rejoins; with shared loot the present players get copies.
static func loot_player(u: GameUnit) -> int:
	return int(u.get_meta("lent_of", u.controller))


## Host: items / money that reached a player's bag (the original
## client message 6): the receiving player's message window lists them, as
## "You picked up:" lines or, with `broken`, "Broken:" (game_hud._got_items).
func notify_got(player: int, items: Array, money := 0, broken := false) -> void:
	if not items.is_empty() or money > 0:
		broadcast({"t": "got", "to": player, "items": items, "money": money, "broken": broken})


# ------------------------------------------------------------------ replication

var _ic_t := 0.0
var snap_usec := 0   # host: time spent building and sending snapshots (tools report it)


## Item spells with the "ic" rune (flag) on the worn armour and the
## weapon in hand, the original from the unit tick (
## every 55 ms). The list (unit on every equipment
## change) holds such items, each with a countdown that starts at 0. Per tick
## an entry above 0 counts down; else, when the item's charge exceeds the
## spell's stamina, it fires: Healing (spell 24) only while the unit
## is hurt (HP ≠ max) and only once per tick, the others always
## the charge loses the cost, the spell is cast at the unit
##  and the countdown becomes duration − 3, or 8 when
## that is below 1. A charge short of the cost fires nothing.
func _ic_spells() -> void:
	var protos: Array = GameData.db.table("spell_prototypes")
	var spent := false
	for u: GameUnit in world.units.values():
		if u.dead or not u.has_meta("hero"):
			continue
		var h: Dictionary = u.get_meta("hero")
		var armors: Array = h.get("armors", [])
		var items: Array = armors.duplicate()
		var ws: Array = h.get("weapons", [])
		if not ws.is_empty():
			items.append(ws[0])
		var old: Dictionary = u.get_meta("ic_cd", {})
		var cd := {}
		var healed := false
		for i in items.size():
			var it: String = items[i]
			var sp := Items.spell_of(it)
			if sp.is_empty() or not int(Spells.parse(sp).flags) & 0x20000:
				continue
			# The entry is the item, whatever its wear / charge (both on the string).
			var key := "%d:%s" % [i, Items.unworn(it)]
			var n := int(old.get(key, 0))
			if n >= 1:
				cd[key] = n - 1
				continue
			cd[key] = n
			var p := Spells.parse(sp)
			if protos.find(p.proto) == 24 and (healed or u.hp == u.max_hp):
				continue
			if not (spend_charge(armors, i, float(p.mana), true) if i < armors.size()
					else spend_charge(ws, 0, float(p.mana), true)):
				continue
			if protos.find(p.proto) == 24:
				healed = true
			spent = true
			#  suppresses an automatic healing item's sound when
			# the resulting packed HP is full; the spell object still appears.
			Spells.cast_unit(world, u, sp, u, u.pos, true)
			cd[key] = 8 if int(p.duration) - 3 < 1 else int(p.duration) - 3
		u.set_meta("ic_cd", cd)
	if spent:
		_state_dirty = true


func _physics_process(dt: float) -> void:
	if get_tree().paused or loading_game or movie_active() or local_host.awaiting_view:
		return
	if is_host:
		_mp_tick(dt)
	if lmp_travel and is_host:
		lmp_travel.physics(dt)
		_sync_t -= dt
		if online and (_state_dirty and _sync_t <= 0.0 or _sync_t <= -5.0):
			_state_dirty = false
			_sync_t = 0.5
			sync_state()
		return
	_tick_world_session(dt)


func _tick_world_session(dt: float) -> void:
	if is_host and world and world.authority:
		_exit_t -= dt
		if _exit_t <= 0.0:
			_exit_t = 0.25
			_check_exits()
			SmileFaces.battle_tick(self)   # remake option "smile_faces": a won fight
		_ic_t += dt
		while _ic_t >= GameUnit.TICK:
			_ic_t -= GameUnit.TICK
			_ic_spells()
		# Campaign state (vars, quests, items) reaches clients in batches.
		if not lmp_travel:
			_sync_t -= dt
		if not lmp_travel and online and (_state_dirty and _sync_t <= 0.0 or _sync_t <= -5.0):
			_state_dirty = false
			_sync_t = 0.5
			sync_state()
	if not (online and is_host and world):
		return
	_snap_t -= dt
	if _snap_t > 0.0:
		return
	_snap_t = SNAP_RATE
	_snap_count += 1
	var t0 := Time.get_ticks_usec()
	var snaps := []
	var near := NetSmooth.near_points(world)
	for u: GameUnit in world.units.values():
		# Bandwidth (remake): the periodic full refresh is spread over 20
		# ticks, units far from every player's heroes go at a fifth of the rate.
		var full := (_snap_count + u.uid) % 20 == 0
		if not full and (_snap_count + u.uid) % 5 != 0 and NetSmooth.far(u.pos, near):
			continue
		var sn := u.snapshot()
		var prev = _last_snap.get(u.uid)
		if full or prev == null or prev != sn:
			snaps.append(sn)
			_last_snap[u.uid] = sn
	_send_snapshot_records(snaps, world.time)
	snap_usec += Time.get_ticks_usec() - t0


func _send_snapshot_records(snaps: Array, time: float, recipient := 0) -> void:
	# Stay under the ENet MTU: ~130 bytes per unit record, more for units
	# with magic effects (the chunk closes early then).
	var chunk := []
	var size := 0
	for sn: Array in snaps:
		var n := var_to_bytes(sn).size()   # includes optional native visibility history
		if not chunk.is_empty() and (chunk.size() >= SNAP_CHUNK or size + n > SNAP_BYTES):
			_send_snap(chunk, time, recipient)
			chunk = []
			size = 0
		chunk.append(sn)
		size += n
	if not chunk.is_empty():
		_send_snap(chunk, time, recipient)


func _send_snap(snaps: Array, time: float, recipient := 0) -> void:
	if recipient > 0:
		_rpc_snap.rpc_id(recipient, snaps, time, _load_serial)
	elif lmp_travel:
		lmp_travel.send_snap(snaps, time)
	else:
		_rpc_snap.rpc(snaps, time, _load_serial)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snap(snaps: Array, t: float, generation := -1) -> void:
	if not lmp.is_empty() or generation != _pool_epoch:
		return   # actual LMP requires the owner-scoped generation wrapper
	_apply_snap(snaps, t)


func _apply_snap(snaps: Array, t: float) -> void:
	if world == null or _zone_holding or _remote_loading:
		return
	world.time = t
	for s: Array in snaps:
		var u: GameUnit = world.units.get(int(s[0]))
		if u:
			u.apply_snapshot(s)


## Seconds before a co-op player's hero rises again (approx.; the original
## multiplayer respawns on the player's request).
const RESPAWN_DELAY := 5.0


func all_party_heroes_dead() -> bool:
	var found := false
	if world:
		for u: GameUnit in world.units.values():
			if u.controller >= 0 and u.has_meta("hero") and not u.get_meta("hero").has("merc"):
				found = true
				if not u.dead:
					return false
	return found


## Host: a player's own hero died. Single player: nothing yet — the original shows
## "Your main character is dead!" (texts.res game_over_msg) only when the
## player next changes zone (`sp_game_over`). Co-op: the original multiplayer
## ("LMP", the -lmp campaign maps) rules bring it back.
func hero_died(u: GameUnit) -> void:
	if not is_host:
		return
	# Single player: the death itself opens no box. (player
	# the only sender of client message 9 = game over) is called
	# only by the zone change, and that only from the leave box's
	# ✓ (message 3), the global map (message 6) and the script's LeaveToZone;
	# no timer, no death hook reaches it. The party plays on with
	# the companions; leaving the zone ends the game (`sp_game_over`).
	# Remake option "sp_death_notice": the game-over sound and a small notice
	# (GameHUD) at once, without pausing; the zone change rule is unchanged.
	if not multiplayer_game and lmp.is_empty():
		if GameData.option("sp_death_notice") == 1 and sp_main_hero_dead():
			# Remake option "revive": the notice says a companion can help.
			broadcast({"t": "death_notice", "revive": Revive.helper_present(self, u)})
		return
	var alive := false
	for o: GameUnit in world.units.values():
		if o.has_meta("hero") and not o.get_meta("hero").has("merc") and not o.dead and o.controller >= 0:
			alive = true
	# Remake co-op (not LMP): the game ends when every player's hero is dead.
	if not alive and lmp.is_empty():
		broadcast({"t": "game_over"})
		return
	if not lmp.is_empty():
		# The multiplayer game: runs only from the zone change
		#  (player; no other caller, no timer). Its
		# callers are the client's leave-zone request (message 3
		# from the leave box), a zone by name
		# (message 6,) and the
		# script's LeaveToZone (0x8a): the hero stays dead until its player
		# changes zone (enter_zone respawns it first).
		return
	if Revive.enabled(self):
		return   # remake option "revive": the hero waits for a companion (or the next zone, enter_zone)
	# Weak references: the zone (and the unit with it) may go before the timer.
	var ur: WeakRef = weakref(u)
	var wr: WeakRef = weakref(world)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(func():
		var du = ur.get_ref()
		if du and du.dead and world != null and world == wr.get_ref():
			coop.with_purse(du.controller, respawn.bind(du)))   # the death toll from its owner's purse


## money - round(money x [LMP] "Lost Money"), experience debt +=
## "Lost XP" x experience (paid off by later gains), all body parts
## restored. The hero rises next to a living party member. In the multiplayer
## game the experience is the original's (lmp_toll_base); the remake's co-op
## campaign (no original counterpart: single-player branch is the
## game-over message) keeps "Lost XP" x the total experience.
func respawn(u: GameUnit) -> void:
	var h: Dictionary = u.get_meta("hero")
	var lost := int(round(state.money * GameData.ai_value("LMP", "Lost Money", 0.05)))
	state.money -= lost
	var base := lmp_toll_base(h) if not lmp.is_empty() else float(h.get("exp_total", h.get("exp", 0.0)))
	h.exp_debt = float(h.get("exp_debt", 0.0)) + GameData.ai_value("LMP", "Lost XP", 0.05) * base
	if not lmp.is_empty():
		_lmp_respawn(u, lost)
		return
	for o: GameUnit in world.units.values():
		if o != u and o.has_meta("hero") and not o.dead and o.controller >= 0:
			u.pos = o.pos + Vector2(1.0, 0.0)
			break
	u.revive()
	broadcast({"t": "party"})
	sync_state()


##  (network branch,..): the experience the
## death toll is taken from — the hero's total experience (stats +4) plus its
## (negative) debt, less the starting experience of the hero's NPC row
## ((prototype) = exp_to_distribute, 500 for every network
## face; the same field gives a new character), floored at 0, so
## the starting experience is never lost. With no NPC row the sum is taken as
## it is (no floor).
static func lmp_toll_base(h: Dictionary) -> float:
	var x := float(h.get("exp_total", h.get("exp", 0.0))) - float(h.get("exp_debt", 0.0))
	var npc := GameData.db.find("npcs", String(h.get("prototype", ""))) if GameData.db else {}
	if not npc.is_empty():
		x = maxf(0.0, x - float(npc.get("exp_to_distribute", 0.0)))
	return x


## LMP (the original, network branch): the dead hero's body stays
## where it fell and the hero rises as a new unit (id + 1000000)
## through the party deployment (player, 0, 1), i.e. at the centre
## of the deploy rect of the entrance its player came into the zone by (player
## record zone / entrance, exit record +4..), facing as that
## entrance's "#view". The money lost goes with the body: adds a
## record {body id, owner connection, money, the player's item list
## } to the world's list, and lets only that
## connection (or −1 = anyone) loot the body. Remake: the body
## is a dead copy of the hero carrying the lost money, lootable by its player
## only ("lmp_owner"; "lmp_conn" its connection, so a player who has left
## and come back cannot, as in the original) and carrying the lost money and the
## whole bag: copies the player's item list into the record and
##  empties it (runs in the player's purse, CoopProgress.with_purse)
## the hero unit itself is moved and revived (same uid). Equipment and belt
## stay on the hero. It runs at the zone change (hero_died), so the body is
## left in the zone the player leaves (CampaignState.store_zone "bodies").
func _lmp_respawn(u: GameUnit, lost: int) -> void:
	var rec: Dictionary = u.info.duplicate(true)
	rec.nid = world.new_uid()
	rec.position = Vector3(u.pos.x, u.pos.y, 0)
	var body := world.spawn_unit(rec)
	if body:
		body.controller = -1
		body.facing = u.facing
		var snap := body.snapshot()
		snap[6] = int(snap[6]) | 1
		body.apply_snapshot(snap, true)
		body.set_meta("lmp_owner", u.controller)
		body.set_meta("lmp_conn", _pid_of(u.controller))
		var loot: Array = ["money[%d]" % lost] if lost > 0 else []
		for it in state.items:
			loot.append("bag:" + str(it))   # kept as they are (take_loot)
		body.set_meta("loot", loot)
		state.items.clear()
		announce_unit(body)
	var ex: Dictionary = world.zone.get("exits", {}).get(_lmp_entrance, {})
	var rect: Rect2 = ex.get("deploy", Rect2(u.pos, Vector2.ZERO))
	u.pos = world.nav.nearest_walkable(rect.get_center())
	u.facing = deg_to_rad(float(ex.get("view", 0.0))) if ex.has("view") else u.facing
	u.revive()
	broadcast({"t": "party"})
	sync_state()
	_mp_camp[u.controller] = 0.0   #  sends the party after the toll (sent outside the purse swap)


## An order failure shown to the player controlling `u`: texts.res "string
## failed_<n>" (0 Can't tame, 2 Can't attack, 4 Path not found, 7 Can't charm,
## 9 Can't cast spells, ...).
func failed(u: GameUnit, n: int) -> void:
	if u == null or u.controller < 0:
		return
	var text := GameData.text("string failed_%d" % n).strip_edges()
	if text:
		broadcast({"t": "msg", "text": text, "to": u.controller})


## Host -> all: UI-level events (messages, dialogs, sounds).
func broadcast(event: Dictionary) -> void:
	if is_host and String(event.get("t", "")) == "movie" and lmp.is_empty() and not event.has("serial"):
		var movie := String(event.get("name", ""))
		if movie.is_empty(): return
		if movie_active():
			_movie_queue.append(movie)
			return
		_movie_serial += 1
		event = event.duplicate()
		event.serial = _movie_serial
		_movie_ev = event
		_movie_wait = {} if local_host.worker else {1: true}
		if online:
			for pid in players:
				if int(pid) != 1 and CoopProgress.peer_alive(multiplayer, int(pid)):
					_movie_wait[int(pid)] = true
		_movie_deadline = Time.get_ticks_msec() + MOVIE_TIMEOUT_MS
		if game == null and not local_host.worker: _movie_ack.call_deferred(1, _movie_serial)
	if is_host and world and String(event.get("t", "")) == "lever" and event.has("state") and not event.has("motion"):
		var data: Dictionary = world.lever_sys.motion_payload(int(event.nid))
		if not data.is_empty():
			event["motion"] = data
	if lmp_travel and not bool(event.get("global", false)):
		_track(event)
		lmp_travel.broadcast(event)
		return
	if is_host:
		if online and String(event.get("t", "")) == "game_over":
			# The reliable notice must not race the last unreliable death
			# snapshot; its still-dead predicate applies immediately on clients.
			event["snaps"] = party_heroes().map(func(u: GameUnit): return u.snapshot())
		_track(event)
	_on_event(event)
	if online and is_host:
		_rpc_event.rpc(event)


@rpc("authority", "call_remote", "reliable")
func _rpc_event(event: Dictionary) -> void:
	if _zone_holding or _remote_loading:
		_zone_held.append(_on_event.bind(event))
		return
	_on_event(event)


func _on_event(event: Dictionary) -> void:
	var t := String(event.get("t", ""))
	if t == "local_host_view":
		local_host.restore_view(event.get("camera", {}))
		return
	if t == "local_save_failed" and local_host.frontend:
		message.emit(RemakeText.t("Could not save the game."))
		return
	if t == "movie" and event.has("serial"):
		_movie_ev = event
	elif t == "movie_release" and int(event.get("serial", -1)) == int(_movie_ev.get("serial", -2)):
		_movie_ev = {}
	if t == "travel":
		if not is_host:
			for id: String in event.get("zone_states", {}):
				state.set_var(0, "z." + id, float(event.zone_states[id]))
		map_open = true
		GameData.trace("travel map open from %s" % zone_id)
	elif t == "travel_close":
		map_open = false
		GameData.trace("travel map closed in %s" % zone_id)
	# World-state events only need applying on clients; the host already did it.
	if not is_host and world:
		match t:
			"game_over":
				for s: Array in event.get("snaps", []):
					var u: GameUnit = world.units.get(int(s[0]))
					if u:
						u.apply_snapshot(s)
			"remove":
				var u: GameUnit = world.units.get(int(event.uid))
				if u:
					world.remove_unit(u)
			"spawn":
				_spawn_record(event.rec)
			"merc_control":
				var u: GameUnit = world.units.get(int(event.get("uid", -1)))
				var m = event.get("character")
				if u and m is Dictionary and typeof(m.get("merc")) in [TYPE_INT, TYPE_FLOAT] \
						and String(u.info.get("name", "")).to_lower() == "merc%d" % int(m.merc):
					_set_merc_control(u, m.duplicate(true), bool(event.get("hired", false)))
					if event.get("snap") is Array:
						u.apply_snapshot(event.snap, true)
					if event.get("stats") is Dictionary:
						u.stats = event.stats.duplicate(true)
			"remove_obj":
				var o = world.objects.get(int(event.nid))
				world.objects.erase(int(event.nid))   # as the host (ScriptVM RemoveObjectFromServer)
				world.levers.erase(int(event.nid))
				world.nav.remove_object(int(event.nid))
				if o and is_instance_valid(o):
					o.queue_free()
			"move_obj":   # script SetCP on a map object
				var mp: Array = event.p
				world.move_object(int(event.nid), Vector3(mp[0], mp[1], mp[2]))
			"hide_obj":
				var o = world.objects.get(int(event.nid))
				if o and is_instance_valid(o):
					o.visible = not event.hide
			"add_mob":
				world.add_mob_objects(String(event.file))
			"lever":
				if world.levers.has(int(event.nid)) and event.has("enabled"):   # EnableLever
					world.levers[int(event.nid)].enabled = bool(event.enabled)
				elif world.levers.has(int(event.nid)):
					if event.has("motion"):
						world.lever_sys.receive(int(event.nid), int(event.state), event.motion)
					else:
						world.levers[int(event.nid)].state = event.state
						world.lever_sys.apply(int(event.nid), true, float(event.get("time", -1.0)))
			"diplo":
				world.set_relation(event.a, event.b, event.v)
			"water":   # script SetWaterLevel: the host's whole list
				var seq := int(event.get("seq", _water_received + 1))
				if String(event.get("zone", zone_id)) == zone_id and seq >= _water_received:
					_water_received = seq
					world.set_water_state(event.l)
			"direct_arrow":
				var a: GameUnit = world.units.get(int(event.a))
				if a: Projectile.launch_direct(world,a,event.direction,false,event.start)
			"arrow":
				var a: GameUnit = world.units.get(int(event.a))
				var b: GameUnit = world.units.get(int(event.b))
				if a and b:
					Projectile.launch(world, a, b, false)
			"state":
				set_meta("host_revive", int(event.get("revive", 0)))
				state.money = event.money
				state.quests = event.quests
				state.quest_items = event.quest_items
				state.items = event.items
				state.heroes = event.heroes
				state.current_party = String(event.get("current_party", state.current_party))
				state.parties = event.get("parties", state.parties)
				state.party_bags = event.get("party_bags", state.party_bags)
				state.mercs = event.get("mercs", state.mercs)
				state.side_quests = event.get("side_quests", {})
				state.shops = event.get("shops", state.shops)
				state.visited = event.get("visited", {})
				state.vars = event.get("vars", state.vars)
				state.gs_tables = event.get("gs_tables", {}).duplicate(true)
				state.gs_reconstructed = bool(event.get("gs_reconstructed", not event.has("gs_tables")))
				state.last_quest = String(event.get("last_quest", state.last_quest))
				state.world_time = float(event.get("world_time", state.world_time))
				state.day = int(event.get("day", state.day))
				lmp_locations = event.get("lmp_locations", lmp_locations)
				if event.get("lmp_settings") is Dictionary and not lmp.is_empty():
					lmp = event.lmp_settings.duplicate(true)
				_relink_heroes()
				_apply_unit_stats(event.get("unit_stats", {}))
				if game:
					game.on_event({"t": "inventory"})
			"equip":
				var u: GameUnit = world.units.get(int(event.uid))
				if u:
					u.set_equipment(PackedStringArray(event.armors), PackedStringArray(event.weapons))
					if event.get("stats") is Dictionary:
						u.stats = event.stats.duplicate(true)
			"reshape":
				var u: GameUnit = world.units.get(int(event.uid))
				if u and not is_host:
					u.info.complexion = event.complexion
					u.set_equipment(PackedStringArray(u.info.get("armors", [])), PackedStringArray(u.info.get("weapons", [])))
			"loot":
				var u: GameUnit = world.units.get(int(event.uid))
				if u:
					if event.has:
						u.set_meta("loot", [])
					elif u.has_meta("loot"):
						u.remove_meta("loot")
	if t == "spell_light" and world and world.presentation:
		SpellFx.teleport_result(world, event)
	if t == "spellfx" and world and world.presentation:
		SpellFx.spawn_event(world, event)
		if not event.get("replay", false):
			GameSound.spell(String(event.code), EISpace.pos(event.x, event.y, world.ground_at(event.x, event.y)), "end")
		ParticleFx.of(world).spell_cast(event)
	if world and world.presentation and t in ParticleFx.EVENTS:   # visual only, on every peer
		ParticleFx.of(world).on_event(event)
	if world and world.presentation and t == "blood":   # the hit's blood mark (visual only, every peer)
		GroundMarks.of(world).hit(event)
	if world and world.presentation and t == "blood_pool":
		if String(event.get("zone", "")) != String(world.zone.get("id", "")):
			return
		if lmp.is_empty() and event.get("pool_epoch") != (_load_serial if is_host else _pool_epoch):
			return
		var uid: Variant = event.get("uid")
		if not (uid is int or uid is float) or not is_finite(float(uid)) \
				or float(uid) <= 0.0 or float(uid) > 0xffffffff or float(uid) != float(int(uid)):
			return
		var u: Variant = world.units.get(int(uid))
		if typeof(u) == TYPE_OBJECT and is_instance_valid(u) and u is GameUnit and not u.is_queued_for_deletion():
			GroundMarks.of(world).pool(u)
	if t == "hitnum":   # floating hit / experience number (every peer)
		if world and event.get("xp_stats") is Dictionary:
			var xp_unit: GameUnit = world.units.get(int(event.get("uid", -1)))
			if xp_unit and is_instance_valid(xp_unit):
				xp_unit.set_meta("xp_stats", event.xp_stats.duplicate(true))
		if game and world and world.presentation:
			FlyingHP.of(game).add(event)
			if int(event.get("f", 0)) & 4:
				game.electrical_hit(event)
		return
	match t:
		"msg":
			if int(event.get("to", my_index)) == my_index:
				message.emit(String(event.text))
		"say": _say(event)
		"loot_copy":   # remake option coop_share_loot (CoopProgress.share_found)
			if int(event.get("to", -1)) == my_index:
				message.emit(CoopProgress.copy_text(event))
				SmileFaces.copy(game)   # remake option "smile_faces"
		"lobby":   # the host's choice of game, while in the lobby (remake)
			if not is_host:
				lobby_mode = event.get("mode", {}) if event.get("mode") is Dictionary else {}
				players_changed.emit()
		_:
			if game and not (local_host.worker and t in ["movie", "movie_release"]):
				game.on_event(event)


## Script "say" / "say_block" on this peer (the original with code
## 0x2a / 0x2b): the unit named by the script (its name id,
## no name = no unit = nothing; resolved by the host's ScriptVM) speaks the
## Scenario line, and only when the
## line exists does the text window get "<unit name>:" and the texts.res
## "say <line id>" text (empty in the editions at hand, so no line shows).
func _say(event: Dictionary) -> void:
	var u: GameUnit = world.units.get(int(event.get("uid", -1))) if world else null
	if u == null or not is_instance_valid(u):
		return
	var l := GameSound.say(u, String(event.get("id", "")), bool(event.get("block", false)))
	if l.is_empty():
		return
	var text := GameData.text("say " + String(l.id))
	if text:
		message.emit("%s:\n%s" % [u.display_name, text])


## Host: a unit created mid-zone (AddMob, summons) must also appear on clients.
func announce_unit(u: GameUnit, except_pid := 0) -> void:
	if online and is_host:
		var ev := {"t": "spawn", "rec": _unit_record(u)}
		if lmp_travel:
			for pid: int in lmp_travel.peers_here():
				if pid != except_pid:
					lmp_travel.send_event(pid, ev)
			return
		for pid in multiplayer.get_peers():
			if pid != except_pid:
				_rpc_event.rpc_id(pid, ev)


## Host: experience for a party (the original; who gets it: XpRules).
## `source`: "kill", "quest" (QuestComplete), "talk" (conversation reward) or
## "side" (quest map reward); `player`: whose party (killer / talker / 0).
func give_experience(amount: float, source := "quest", player := 0) -> void:
	XpRules.give(self, amount, source, player)


## Host -> clients: party-wide campaign data shown in the UI.
## Host: campaign state changed; clients get it with the next batch.
func mark_dirty() -> void:
	_state_dirty = true


func sync_state() -> void:
	if coop.purse_active():   # a joiner's purse stands in: sent once it is put back
		mark_dirty()
		return
	if online and is_host:
		var ev := {"t": "state", "money": state.money, "quests": state.quests, "quest_items": state.quest_items,
			"items": state.items, "heroes": state.heroes, "mercs": state.mercs, "side_quests": state.side_quests, "shops": state.shops, "visited": state.visited,
			# Expansion chapters replace the host's active party. The live
			# state must carry the same roster/bag identity as a zone snapshot.
			"current_party": state.current_party, "parties": state.parties, "party_bags": state.party_bags,
			"vars": state.vars, "gs_tables": state.gs_metadata(), "gs_reconstructed": state.gs_reconstructed,
			"last_quest": state.last_quest, "world_time": state.world_time, "day": state.day,
			"revive": GameData.option(Revive.OPTION), "unit_stats": _hero_stat_records(),
			"lmp_settings": lmp}   # host options / effective stats
		# Each peer sees its own purse and bag (CoopProgress.state_for).
		for pid in multiplayer.get_peers():
			if CoopProgress.peer_alive(multiplayer, pid):
				if lmp_travel and players.has(pid):
					var idx := int(players[pid].index)
					var w: GameWorld = lmp_travel.owner_world(idx)
					lmp_travel.with_world(w, func():
						var own := coop.state_for(pid, ev).duplicate()
						own.unit_stats = _hero_stat_records()
						own.world_time = state.world_time
						own.day = state.day
						own.lmp_locations = lmp_locations
						lmp_travel.send_event(pid, own))
				else:
					_rpc_event.rpc_id(pid, coop.state_for(pid, ev))
	if game and (lmp_travel == null or game.world == world):
		game.on_event({"t": "inventory"})


## Reliable, low-rate character data. Changing the inventory's hero record
## alone left clients showing the prototype's unarmed attack and damage.
## Do not recalculate HP here: snapshots own damaged parts and live pools.
func _hero_stat_records() -> Dictionary:
	var out := {}
	if world:
		for u: GameUnit in world.units.values():
			if u.has_meta("hero"):
				out[u.uid] = u.stats.duplicate(true)
	return out


func _apply_unit_stats(records: Dictionary) -> void:
	if world:
		for uid in records:
			var u: GameUnit = world.units.get(int(uid))
			if u and records[uid] is Dictionary:
				u.stats = records[uid].duplicate(true)


## Client: point hero units at the hero records received from the host.
func _relink_heroes() -> void:
	if world == null:
		return
	for u: GameUnit in world.units.values():
		if u.controller < 0:
			continue
		for h: Dictionary in state.heroes.get(u.controller, []):
			if String(h.get("guest_unit_name", h.get("unit_name", h.name))) == String(u.info.get("name", "")):
				u.set_meta("hero", h)
				u.display_name = h.name
				Combat.sync_natural_armor(u, h)   # as on the host (cleared when deployed)
		# Mercenaries (their units keep the map name "merc<N>", CampaignState.merc_record).
		for m: Dictionary in state.mercs.values():
			if not state.merc_party_active(m):
				continue
			if int(m.get("controller", -1)) == u.controller and String(state.merc_record(m).name) == String(u.info.get("name", "")):
				u.set_meta("hero", m)
				u.display_name = m.name
				Combat.sync_natural_armor(u, m)


## Text from the current quest map's .mq archive (random quest zones).
func quest_text(key: String) -> String:
	var mq := String(world.zone.get("mob", "")).get_basename() + ".mq" if world else ""
	if mq == ".mq" or not GameFiles.exists(GameData.root.path_join("maps/" + mq)):
		return SideQuests.text(key)
	var arc := EIResArchive.open_path(GameData.root.path_join("maps/" + mq))
	if arc and arc.has(key.to_lower()):
		return EIText.ansi(arc.read(key.to_lower()))
	return SideQuests.text(key)


# ------------------------------------------------------------------ players

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(player_name: String, hero_class: String, protocol := 0, maps_md5 := "", pw := "") -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if local_host.single_player:
		multiplayer.multiplayer_peer.disconnect_peer(pid)
		return
	if not CoopProgress.peer_alive(multiplayer, pid):
		return   # dropped again before its hello was handled (it will say hello anew)
	# A wrong password is refused before a stale connection of the same name
	# is dropped (it must not push the real player out).
	if password != "" and pw.left(PASSWORD_MAX) != password and net.refuse(pid, protocol, maps_md5, player_name, pw):
		return
	if (not lmp.is_empty() or String(lobby_mode.get("mode", "")) == "lmp") \
			and MpCharacter.accept(_lmp_character(pid)).is_empty():
		net.refuse_character(pid)
		return
	_drop_stale_peer(pid, player_name)
	if net.refuse(pid, protocol, maps_md5, player_name, pw):
		return
	var idx := _player_slot(player_name)
	var in_game := world != null
	players[pid] = {"index": idx, "name": player_name, "hero": hero_class, "colour": NetStatus.free_colour(players)}
	_rpc_players.rpc(players)
	_rpc_welcome.rpc_id(pid, idx)
	if not in_game and not lobby_mode.is_empty():
		_rpc_event.rpc_id(pid, {"t": "lobby", "mode": lobby_mode})
	broadcast({"t": "msg", "text": net.joined_text(player_name), "global": true})
	if not lmp.is_empty():
		# The multiplayer game: its database first, then a network hero (no
		# brought campaign hero, CoopProgress is the co-op campaign's).
		_rpc_lmp.rpc_id(pid, lmp)
		if in_game:
			coop.with_purse(idx, _ensure_lmp_hero.bind(idx, player_name))
			_spawn_late_joiner(idx, pid)
		players_changed.emit()
		return
	coop.on_hello(pid, idx, player_name)
	if in_game:
		state.ensure_hero(idx, _hero_proto(idx), player_name)
		if loading_game:
			_load_waiting[pid] = true
			net.loading_started(pid, _load_serial)
			_rpc_load_prepare.rpc_id(pid, _load_serial, _loading_zone_id)
		else:
			_spawn_late_joiner(idx, pid)
	players_changed.emit()


## Player index for a joining player: a player coming back (same name as a
## co-op hero whose player is gone) gets the old slot and so the old hero;
## anyone else the lowest free index. Remake-only.
func _player_slot(player_name: String) -> int:
	var used := players.values().map(func(p): return int(p.index))
	if not lmp.is_empty():
		var free := 1
		while free in used:
			free += 1
		return free
	var nm := player_name.strip_edges().to_lower()
	for i in state.heroes:
		if int(i) > 0 and not int(i) in used and not state.heroes[i].is_empty() \
				and String(state.heroes[i][0].get("name", "")).to_lower() == nm:
			return int(i)
	var idx := 1
	while idx in used or (state.heroes.has(idx) and _orphan_owner_named(idx)):
		idx += 1
	return idx


## True while slot `idx` keeps the hero of a named player who may come back.
func _orphan_owner_named(idx: int) -> bool:
	var h: Array = state.heroes.get(idx, [])
	return not h.is_empty() and String(h[0].get("name", "")) != GameUnit.unit_title(String(h[0].get("prototype", "")))


## A player reconnecting before the host noticed the old connection drop
## (ENet waits up to PEER_TIMEOUT_MS): same name from the same address ->
## the old peer is dropped first so its slot and hero are free again.
func _drop_stale_peer(pid: int, player_name: String) -> void:
	var enet := NetSim.enet_of(multiplayer)
	if enet == null or enet.get_peer(pid) == null:
		return
	var addr := enet.get_peer(pid).get_remote_address()
	for old in players.keys():
		if old == pid or int(players[old].index) == 0 or String(players[old].name) != player_name:
			continue
		var op := enet.get_peer(old)
		if op and op.get_remote_address() == addr:
			_on_peer_disconnected(old)
			op.peer_disconnect_now()


## Host: a player joined a running game. Units it left behind when it
## disconnected (still following the party under AI control) come back under
## its control; otherwise its heroes appear next to the leader. Only the new
## peer loads the zone; the others get the new units as spawns.
func _spawn_late_joiner(idx: int, pid: int) -> void:
	if lmp_travel:
		lmp_travel.join(idx, pid)
		return
	if coop.GuestRoles.ensure(self, idx):
		for u: GameUnit in world.units.values().duplicate():
			if (u.controller == idx or int(u.get_meta("orphan_of", -1)) == idx) and u.has_meta("hero") and not u.get_meta("hero").has("merc"):
				world.remove_unit(u)
				broadcast({"t":"remove", "uid":u.uid})
	var repaired := preload("res://src/game/script/camp_grants.gd").catch_up(state, idx) if lmp.is_empty() else false
	var leader: GameUnit = null
	for u: GameUnit in world.units.values():
		if u.controller == 0 and not u.dead:
			leader = u
			break
	var reclaimed := false
	for u: GameUnit in world.units.values():
		if int(u.get_meta("lent_of", -1)) == idx:   # its mercenary, held while it was away (_spawn_merc)
			u.remove_meta("lent_of")
			u.controller = idx
			u.command({"type": "wait", "t": 0.1})
		if int(u.get_meta("orphan_of", -1)) == idx and u.controller < 0:
			u.remove_meta("orphan_of")
			u.controller = idx
			u.mode = "player"
			u.mode_data = {}
			u.command({"type": "wait", "t": 0.1})
			if u.has_meta("hero") and not u.get_meta("hero").has("merc"):
				reclaimed = true
	var fresh: Array[GameUnit] = []
	var at := leader.pos if leader else world.terrain.size_ei() * 0.5
	for rec: Dictionary in ([] if reclaimed else state.party_records(idx)):
		var p := world.nav.nearest_walkable(at + Vector2(1.5, 1.5))
		rec.position = Vector3(p.x, p.y, 0)
		rec.nid = world.new_uid()
		var u := world.spawn_unit(rec)
		if u:
			u.controller = idx
			u.faction = 0
			u.mode = "player"
			state.apply_hero(u)
			fresh.append(u)
	# A hero not deployed when the save was loaded (its player was away)
	# takes up the follow order the save kept for it.
	if not fresh.is_empty():
		state.apply_follow(world, "follow_live", fresh)
	if repaired and reclaimed:
		for u: GameUnit in world.units.values():
			if u.controller == idx and u.has_meta("hero") and not u.get_meta("hero").has("merc"):
				Combat.set_complexion(u, u.get_meta("hero"), u.get_meta("hero").complexion)
				_refresh_hero(u)
	_relink_heroes()
	if world.vm: world.vm.resolve_script_ai_targets()
	_rpc_zone.rpc_id(pid, zone_id, _unit_records(), world.diplomacy, _extra_mobs(),
		String(world.zone.get("mpr", "")), _lever_states(), _load_serial)
	_send_world_state(pid)
	for u in fresh:
		announce_unit(u, pid)
	broadcast({"t": "party"})
	sync_state()
	_send_clock(pid)


@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(idx: int) -> void:
	my_index = idx


@rpc("authority", "call_remote", "reliable")
func _rpc_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()


## A zone build stalls the main loop for several seconds (no polling), longer
## than ENet's default 5 s minimum timeout; allow a peer up to a minute.
const PEER_TIMEOUT_MS := 60000

func _on_peer_connected(pid: int) -> void:
	_relax_timeout(pid)


func _relax_timeout(pid: int) -> void:
	var enet := NetSim.enet_of(multiplayer)
	if enet == null or (not is_host and pid != 1):
		return   # clients have a direct ENet transport only to their server
	var p := enet.get_peer(pid)
	if p:
		p.set_timeout(0, PEER_TIMEOUT_MS, PEER_TIMEOUT_MS)


func _on_peer_disconnected(pid: int) -> void:
	if _building:   # noticed by NetStatus.keep_alive inside a zone build
		_on_peer_disconnected.call_deferred(pid)
		return
	if local_host.authorized(pid):
		net.bye()
		get_tree().quit()
		return
	if not is_host or not players.has(pid):
		return
	var idx: int = players[pid].index
	broadcast({"t": "msg", "text": net.gone_text(pid, players[pid].name), "global": true})
	if lmp_travel:
		lmp_travel.disconnect_player(idx)
	net.forget(pid)
	players.erase(pid)
	if lmp_travel:
		# Native connection disposal removes its party record as well as the
		# quest registration. A new login uses its newly selected character.
		state.heroes.erase(idx)
		coop.lmp_purses.erase(idx)
		_mp_resend.erase(idx)
		_mp_camp.erase(idx)
		mark_dirty()
	# Their heroes stay with the party under AI control, following the leader.
	if world and lmp_travel == null:
		for u: GameUnit in world.units.values():
			if u.controller == idx:
				u.controller = -1
				u.direct_controlled = false
				u.mode = "follow"
				u.mode_data = {"target": _leader()}
				u.set_meta("orphan_of", idx)   # given back if the player returns
	_rpc_players.rpc(players)
	players_changed.emit()


func players_include(idx: int) -> bool:
	for p in players.values():
		if p.index == idx:
			return true
	return false


func _leader() -> GameUnit:
	for u: GameUnit in world.units.values():
		if u.controller == 0 and not u.dead:
			return u
	return null


# ------------------------------------------------------------------ saves

## `save_name`: the Save screen's name ("" = the default name); `frame`: the
## frame captured when the game switched to its menus, the save's shot
## without it (quick / auto saves) the frame
## screen shortly after.
func save_game(slot: String, save_name := "", frame: Image = null) -> Error:
	if local_host.frontend:
		local_host.save(slot, save_name, frame)
		return OK   # accepted; the worker reports completion or failure
	if not is_host:
		message.emit(RemakeText.t("Only the host can save."))
		return ERR_UNAUTHORIZED
	if not lmp.is_empty():
		return ERR_UNAVAILABLE   # LMP keeps its network heroes separately
	if loading_game:
		return ERR_UNAVAILABLE
	if coop.purse_active():   # mid-command of a joiner (its purse in state): right after
		save_game.call_deferred(slot, save_name, frame)
		return ERR_BUSY
	if movie_active():
		_movie_saves[slot] = [save_name, frame]
		return ERR_BUSY
	swap.cancel_all()   # return offered items before the authoritative save snapshot
	_capture_save_state()
	GameData.trace("save %s in %s" % [slot, zone_id])
	var err := state.save(SaveInfo.path(slot))
	GameData.trace("save %s done (%d)" % [slot, err])
	if err == OK:
		# The Load screen's entry (the original info.sav / shot.sav).
		SaveInfo.write(slot, state.get_var(0, "gtime"), _allod_id(), zone_id, save_name)
		if frame:
			SaveInfo.write_shot_image(slot, frame)
		elif not local_host.worker:
			SaveInfo.write_shot(slot, get_viewport())
		local_host.saved(slot, frame != null)
	# No log line: the original checks the free space first («no_disc_space» box
	# load_panel) and shows nothing after a save; while it saves it shows
	# «string notify_saving» (NotifyLine; after the shot, so the
	# picture stays clean). Not for the zone autosave.
	if err != OK:
		push_error("save %s failed (%d)" % [slot, err])
		if local_host.worker and local_host.owner_peer > 1:
			_rpc_event.rpc_id(local_host.owner_peer, {"t": "local_save_failed"})
	elif slot != "autosave" and game and game.hud:
		game.hud.notify("string notify_saving")
	if err == OK and online:
		for pid in players:
			if int(pid) != 1 and CoopProgress.peer_alive(multiplayer, int(pid)):
				_rpc_event.rpc_id(int(pid), {"t": "saved", "slot": slot})
	return err


## Snapshot the running world before measuring or writing it. Otherwise the
## Save screen measures the previous autosave / zone departure, missing new
## script frames, lasting effects and current party bodies.
func _capture_save_state() -> void:
	if not is_host or not lmp.is_empty() or loading_game or coop.purse_active() or state == null or world == null:
		return
	state.collect_pets(world)
	state.store_zone(zone_id, world)
	state.current_zone = zone_id
	state.store_party_positions(world)
	state.store_follow(world, "follow_live")
	state.camera = local_host.camera.duplicate(true) if local_host.worker else (game.rig.pose() if game and game.rig else {})   # scenario.sav camera record
	if not local_host.worker and game and game.hud and game.hud.minimap and not state.camera.is_empty():
		state.camera["minimap_zoom"] = game.hud.minimap.zoom   #  reads it back
	coop.before_save()


##  measures the current working save, plus a 1 MB reserve in the
## caller. This engine writes one Variant file; include store_var's 4-byte
## length prefix and capture the same live state as save_game first.
func save_bytes_needed() -> int:
	if local_host.frontend:
		return local_host.save_bytes
	if not is_host or not lmp.is_empty() or loading_game or coop.purse_active() or state == null or world == null:
		return 0
	_capture_save_state()
	return 4 + var_to_bytes(state.to_dict()).size()


func _allod_id() -> String:
	return String(campaign.zones.get(zone_id, {}).get("allod", "")).to_lower() if campaign else ""


## The Save screen's new entry (in Save mode): the next
## "save<n>" slot with the game's time ("gtime"), allod and zone.
func fresh_save_entry(frame: Image) -> SaveInfo:
	return SaveInfo.make_fresh(float(state.get_var(0, "gtime")) if state else 0.0, _allod_id(), zone_id, frame)


## The newer of the quick save and the zone autosave ("" if neither exists).
static func latest_save() -> String:
	var best := ""
	var t := 0
	for slot in ["quick", "autosave"]:
		var p := SaveInfo.path(slot)
		if GameFiles.exists(p) and FileAccess.get_modified_time(p) >= t and CampaignState.compatible_data(CampaignState.read_data(p)):
			t = FileAccess.get_modified_time(p)
			best = slot
	return best


func load_game(slot: String) -> bool:
	if not _may_load():
		return false
	var s := _read_save(slot)
	if s == null or not zone_exists(s.current_zone):
		return false
	_begin_host_load(s.current_zone)
	# Synchronous tools / engine callers keep their bool-returning API. The
	# UI uses load_game_shown and waits for every connected client's ack.
	_flush_load_notice()
	return _load_state(slot, s)


## The menus' load: load_game with the loading screen put on screen first on
## web / mobile (LoadingScreen.hold), before anything changes.
func load_game_shown(slot: String) -> bool:
	if await _start_single_if_needed() == ERR_SKIP:
		return false
	if local_host.frontend:
		var answer := await local_host.request("load", {"slot": slot})
		return bool(answer.get("ok", false))
	if not _may_load():
		return false
	var s := _read_save(slot)
	if s == null or not zone_exists(s.current_zone):
		return false
	_begin_host_load(s.current_zone)
	await _wait_load_clients()
	if LoadingScreen.deferred() and zone_exists(s.current_zone):
		await LoadingScreen.hold(get_tree(), campaign.zone(s.current_zone), LoadingScreen.SAVED_ZONE)
	return _load_state(slot, s)


func _may_load() -> bool:
	if not is_host:
		message.emit(RemakeText.t("Only the host can load"))
		return false
	return lmp.is_empty() and not loading_game


func _begin_host_load(id: String, cancel_movie := true) -> void:
	if cancel_movie:
		_cancel_movie()
	loading_game = true
	_loading_zone_id = id
	_load_serial += 1
	_load_waiting.clear()
	if world:
		_loading_world_mode = world.process_mode
		world.process_mode = Node.PROCESS_MODE_DISABLED
	if online:
		reset_coop_clock()
		for pid in players:
			if int(pid) != 1 and CoopProgress.peer_alive(multiplayer, int(pid)):
				_load_waiting[int(pid)] = true
				net.loading_started(int(pid), _load_serial)
				_rpc_load_prepare.rpc_id(int(pid), _load_serial, id, not cancel_movie)
	# Draw before closing the map/menu; there must be no exposed frozen-world
	# frame while the host waits for peers to acknowledge the transfer.
	LoadingScreen.prepare(get_tree(), campaign.zone(id), LoadingScreen.SAVED_ZONE if cancel_movie or state.zones.has(id) else LoadingScreen.NEW_ZONE)
	if game:
		game.on_event({"t": "load_begin", "travel": not cancel_movie})


func _flush_load_notice() -> void:
	if not online:
		return
	if multiplayer.multiplayer_peer is NetSim:
		(multiplayer.multiplayer_peer as NetSim).flush_now()
	var enet := NetSim.enet_of(multiplayer)
	if enet and enet.host:
		enet.host.flush()


func _wait_load_clients() -> void:
	_flush_load_notice()
	var deadline := Time.get_ticks_msec() + 8000
	while not _load_waiting.is_empty() and Time.get_ticks_msec() < deadline:
		for pid in _load_waiting.keys():
			if not players.has(pid) or not CoopProgress.peer_alive(multiplayer, int(pid)):
				_load_waiting.erase(pid)
		if not _load_waiting.is_empty():
			await get_tree().process_frame


@rpc("authority", "call_remote", "reliable")
func _rpc_load_prepare(serial: int, id: String, travel := false) -> void:
	_pool_epoch = maxi(_pool_epoch, serial)
	if serial <= _load_serial:
		return
	_load_serial = serial
	_remote_loading = true
	_remote_load_end_serial = -1
	loading_game = true
	_apply_clock(false, 0)
	if world:
		_loading_world_mode = world.process_mode
		world.process_mode = Node.PROCESS_MODE_DISABLED
	await LoadingScreen.wait_remote(get_tree(), campaign.zone(id))
	if game:
		game.on_event({"t": "load_begin", "travel": travel})
	# On a deferred surface the host must wait until the picture is actually
	# presented; otherwise receipt / input blocking is already synchronous.
	if _remote_loading and serial == _load_serial:
		_rpc_load_ready.rpc_id(1, serial)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_load_ready(serial: int) -> void:
	if is_host and loading_game and serial == _load_serial:
		_load_waiting.erase(multiplayer.get_remote_sender_id())


func _finish_host_load() -> void:
	loading_game = false
	_loading_zone_id = ""
	_load_waiting.clear()
	if online:
		for pid in players:
			if int(pid) != 1 and CoopProgress.peer_alive(multiplayer, int(pid)):
				_rpc_load_end.rpc_id(int(pid), _load_serial)
		_send_clock()
	if game:
		game.on_event({"t": "load_end"})


@rpc("authority", "call_remote", "reliable")
func _rpc_load_end(serial: int) -> void:
	if not _remote_loading or serial != _load_serial:
		return
	if _zone_holding:
		_remote_load_end_serial = serial
		return
	_remote_loading = false
	_remote_load_end_serial = -1
	loading_game = false
	if world:
		world.process_mode = Node.PROCESS_MODE_PAUSABLE
	var held := _zone_held
	_zone_held = []
	for c: Callable in held:
		c.call()
	LoadingScreen.end()
	net.zone_loaded()
	if game:
		game.on_event({"t": "load_end"})


func _cancel_remote_load() -> void:
	if not _remote_loading:
		return
	_remote_loading = false
	loading_game = false
	_zone_held.clear()
	if world:
		world.process_mode = _loading_world_mode
	LoadingScreen.end()
	if game:
		game.on_event({"t": "load_end"})


## Web / mobile, the menus: the loading screen for zone `id` on screen before
## a synchronous start (new_lmp_game).
func hold_loading(id: String) -> void:
	if LoadingScreen.deferred() and zone_exists(id):
		await LoadingScreen.hold(get_tree(), campaign.zone(id), LoadingScreen.NEW_ZONE)


func _read_save(slot: String) -> CampaignState:
	if not is_host:
		return null
	GameData.trace("load %s (from %s)" % [slot, zone_id])
	var s := CampaignState.load_from(SaveInfo.path(slot))
	if s == null:
		GameData.trace("load %s failed" % slot)
	return s


func _load_state(slot: String, s: CampaignState) -> bool:
	if not is_host or not lmp.is_empty() or s == null or not zone_exists(s.current_zone):
		return false
	swap.cancel_all()
	coop.before_load(slot, s)
	# Players connected now who joined after that save was made (co-op class
	# heroes; brought heroes come from before_load) still get a hero.
	for pid in players:
		var idx := int(players[pid].index)
		if idx > 0:
			s.ensure_hero(idx, _hero_proto(idx), String(players[pid].name))
	state = s
	if local_host.worker:
		local_host.camera = state.camera.duplicate(true)
	zone_id = ""
	_restoring = true
	_enter_zone(s.current_zone, 1, false)
	_restoring = false
	state.restore_party_positions(world)
	state.apply_follow(world, "follow_live")
	# Every unit drawn where it now stands: the zone state and the party's
	# saved spots moved them after they were made (at their map / deploy
	# spots), so each is placed at once with no interpolation from there.
	for u: GameUnit in world.units.values():
		u.resync_drawn()
	if game and game.hud:
		game.hud.notify("string notify_loading")
	# attach_world focused the zone's start point before the party was put
	# back where it was saved: look at the selected hero instead.
	# The original restores the saved camera record (
	# ) and never refocuses; the remake does that for both
	# camera styles on the saving machine's view (not for joiners).
	if game and game.hud and game.hud.minimap and is_host:
		game.hud.minimap.zoom = float(state.camera.get("minimap_zoom", 1.0))   # old saves: 1.0
	if game and game.rig and is_host and game.rig.set_pose(state.camera):
		pass
	elif game and not game.selected.is_empty():
		var p: Vector2 = game.selected[0].pos
		game.rig.focus(EISpace.pos(p.x, p.y, world.ground_at(p.x, p.y)))
	_publish_zone()
	state.replay_restored(world)
	sync_state()
	if local_host.worker and local_host.owner_peer > 1:
		_rpc_event.rpc_id(local_host.owner_peer, {"t": "local_host_view", "camera": state.camera})
	GameData.trace("load %s done in %s" % [slot, zone_id])
	_finish_host_load()
	return true

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

const PORT := 27015
## the original: the network screen's Max Players slider 0..5 + 1 (
## default 6; hosts with it); the host counts as one.
const MAX_PLAYERS := 6
const SNAP_RATE := 0.1
const SNAP_CHUNK := 8
const SNAP_BYTES := 1100    # payload budget of one snapshot packet (MTU 1392)
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
## peer id -> {index, name}
var players := {1: {"index": 0, "name": "Player"}}
var max_players := MAX_PLAYERS   # host: this game's Max Players (host itself included)
var zone_id := ""
var _snap_t := 0.0
var _snap_count := 0
var _last_snap := {}
var _exit_t := 0.0
var _sync_t := 0.0
var _state_dirty := false
var _leave_armed := -1      # exit a move click armed (leave-zone box, _arm_exit)
var _auto_exit := -1        # remake: exit the host party stands in (box shown / standing there on entry)
var _auto_world: GameWorld
var travel_options: Array = []   # host: destinations currently offered
var _travel_ev := {}        # host: the open global map event (for joiners)
var map_open := false       # every peer: the global map is up ("travel" until "travel_close" / a zone)
var _dialog_ev := {}        # host: the running conversation event (for joiners)
var coop: CoopProgress
var net: NetStatus
var upnp: UpnpPort
## the original's own multiplayer game (LmpMode): {"base": bz1mpg.., "quest": <q>
## "pk": 0|1}; empty in the campaign (single player or the remake's co-op).
var lmp := {}
## LMP: the entrance the party came into the current zone by (respawn spot).
var _lmp_entrance := 1


func _ready() -> void:
	name = "Session"
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
	multiplayer.connected_to_server.connect(func():
		_relax_timeout(1)   # the client's own zone builds stall as long as the host's
		coop.client_hello()
		_rpc_hello.rpc_id(1, GameData.player_name, GameData.hero_class, NetStatus.PROTOCOL, NetStatus.world_hash()))
	multiplayer.server_disconnected.connect(func():
		var t := net.server_lost_text()
		if t:
			message.emit(t))


# ------------------------------------------------------------------ setup

func host(port := PORT, limit := MAX_PLAYERS) -> Error:
	if OS.has_feature("web"):
		return ERR_UNAVAILABLE
	var socket_mode := GameData.option("net_websocket") != 0
	var peer: MultiplayerPeer = _websocket_peer() if socket_mode else ENetMultiplayerPeer.new()
	# Remake: "*" listens on IPv4 and IPv6 at once (a dual-stack socket), so
	# friends can join by "[IPv6 address]:port" too (often reachable without
	# any port forwarding).
	if peer is ENetMultiplayerPeer:
		peer.set_bind_ip("*")
	# ENet takes one connection more than the game has room for, so a joiner
	# beyond Max Players hears "server full" (NetStatus.refusal) instead of
	# a silent timeout.
	max_players = clampi(limit, 1, MAX_PLAYERS)
	var err: Error = peer.create_server(port) if socket_mode else peer.create_server(port, max_players)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer if socket_mode else NetSim.wrap(peer)   # (tools: --netsim)
	online = true
	is_host = true
	if not socket_mode and GameData.option("net_upnp") == 1 and not Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--tool=")):
		upnp.open(port)
	my_index = 0
	players = {1: {"index": 0, "name": GameData.player_name}}
	return OK


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
	return OK


static func _websocket_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 16777216
	peer.outbound_buffer_size = 16777216
	peer.max_queued_packets = 4096
	peer.handshake_timeout = 30.0
	return peer


## the original: "new game" (message) plays Movies\Intro.bik
## (modal) and then starts the game. The single
## player menu plays it before calling this with `intro` false; otherwise
## (co-op, **approx.**) every peer sees it once the first zone is built.
func new_campaign(intro := true) -> void:
	state = CampaignState.new()
	coop.campaign_started()
	for pid in players:
		state.ensure_hero(players[pid].index, _hero_proto(players[pid].index), String(players[pid].name))
	enter_zone("gz1g", 1)
	if intro:
		broadcast({"t": "movie", "name": "intro"})


## Host: starts the original's own multiplayer game (LmpMode) on `base`: every
## peer switches to res/databaseLMP.res, each player gets a network hero with
## its own purse and bag (CoopProgress.lmp_purses) and the party starts in the
## base at its entrance 1, where the quest giver offers the base's quests
## (SideQuests.lmp_offer, as a new server's). `quest` (tests)
## takes that quest straight away.
func new_lmp_game(base: String, quest := "", pk := 0) -> bool:
	base = base.to_lower()
	quest = quest.to_lower()
	if not base in LmpMode.BASES or (quest and not LmpMode.quests_of(campaign, base).has(quest)):
		message.emit(RemakeText.t("Unknown zone ") + base + "/" + quest)
		return false
	if not GameData.use_lmp_database(true):
		message.emit(RemakeText.t("Unknown zone ") + base)
		return false
	lmp = {"base": base, "quest": "", "last": "", "topics": [], "pk": pk}
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
	enter_zone(base, 1)
	if quest:
		SideQuests.take_lmp(self, quest)
	else:
		SideQuests.lmp_offer(self)
	return true


## The connection (peer id) of player slot `idx` now, 0 = none.
func _pid_of(idx: int) -> int:
	for pid in players:
		if int(players[pid].index) == idx:
			return int(pid)
	return 0


## LMP: a player's network hero. **Approx.** (the network character screens,
## are not ported): databaseLMP.res "Human Hero"
## (prototype kit, NPC row attributes / skills / experience) named after the
## player.
func _ensure_lmp_hero(idx: int, player_name: String) -> void:
	if state.heroes.has(idx):
		return
	state.ensure_hero(idx, "Human Hero", player_name)
	var h: Dictionary = state.heroes[idx][0]
	if player_name.strip_edges():
		h.name = player_name.strip_edges()


## Every peer: the multiplayer game's settings; a client switches to the
## multiplayer database before the first zone comes (same channel, in order)
## and sends its table digests again (CoopDb, NetStatus).
@rpc("authority", "call_remote", "reliable")
func _rpc_lmp(settings: Dictionary) -> void:
	lmp = settings
	GameData.use_lmp_database(not lmp.is_empty())
	Shops.network = not lmp.is_empty()
	net.send_db_digests()


## Leaving the multiplayer game (back to the menu): the campaign database again.
func _exit_tree() -> void:
	if not lmp.is_empty():
		lmp = {}
		GameData.use_lmp_database(false)
		Shops.network = false


func _hero_proto(index: int) -> String:
	if index == 0:
		return "Human Hero"
	for p in players.values():
		if int(p.index) == index and String(p.get("hero", "")) in COOP_CLASSES:
			return String(p.hero)
	return COOP_HEROES[(index - 1) % COOP_HEROES.size()]


# ------------------------------------------------------------------ zones

## Host: load a zone and deploy all players' parties at an entrance.
func enter_zone(id: String, entrance: int, autosave := true) -> void:
	var z := campaign.zone(id)
	if z.is_empty() or not z.has("mpr") or not zone_exists(id):
		message.emit(RemakeText.t("Unknown zone ") + id)
		return
	if world and zone_id and not lmp.is_empty():
		# a player whose hero is dead (or gone) when it is sent to
		# another zone is respawned first (player =).
		for u: GameUnit in world.units.values().duplicate():
			if u.dead and u.controller >= 0 and u.has_meta("hero") and not u.get_meta("hero").has("merc"):
				coop.with_purse(u.controller, respawn.bind(u))   # its own purse and bag
	if world and zone_id:
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
	LoadingScreen.begin(get_tree(), z)
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
	state.visited[id] = true
	_lmp_entrance = entrance
	if lmp.is_empty():
		coop.zone_entered(id)
	world.vm = ScriptVM.create(world, self)
	_start_pose(z, entrance)
	_replay_local()
	if online:
		_rpc_zone.rpc(id, _unit_records(), world.diplomacy, _extra_mobs(), z.mpr, _lever_states())
		_send_world_state(0)
	state.replay_restored(world)   # restored units' effect visuals, lasting ground spells
	sync_state()
	# the original runs the "autosave" command shortly after a zone has
	# loaded (10th frame); the Autosave option switches it off.
	if autosave and is_host and GameData.option("autosave") and lmp.is_empty():
		save_game.call_deferred("autosave")
	ShaderWarmup.run(game)
	LoadingScreen.end()
	GameData.trace("zone ready %s" % id)


## the original (party deployment) builds a WorldScript for the
## heroes; on map "zone1" with the deploy point within sqrt(300) m of
## (54, 138) (squared 3D distance < 300) and game state != 2 it appends
## PlayAnimation(GetObjectByName("hero"), "uspecial25"): Zak wakes up lying on
## the ruins' floor at the campaign start. Only the unit named "hero" (player
## 0's Zak), also in co-op. **Approx.**: == 2 is taken to be a loaded
## save (the remake skips the clip when a save is loaded).
var _restoring := false


func _start_pose(z: Dictionary, entrance: int) -> void:
	if _restoring or String(z.get("mpr", "")).to_lower() != "zone1":
		return
	var rect: Rect2 = z.exits.get(entrance, {}).get("deploy", Rect2())
	if rect.get_center().distance_squared_to(Vector2(54, 138)) >= 300.0:
		return
	for u: GameUnit in world.units.values():
		if u.controller == 0 and u.has_meta("hero") and not u.get_meta("hero").has("merc"):
			u.command({"type": "anim", "name": "uspecial25"})
			return


func _build_world(z: Dictionary, authority: bool) -> void:
	var w := GameWorld.new()
	w.name = "World"
	w.zone = z
	w.authority = authority
	w.session = self
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
	world = w
	game.attach_world(w)
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
	var exit: Dictionary = z.exits.get(entrance, {})
	var rect: Rect2 = exit.get("deploy", Rect2(world.terrain.size_ei() * 0.5, Vector2(4, 4)))
	var view := deg_to_rad(float(exit.get("view", 0.0)))
	var slot := 0
	for pid in players:
		var idx: int = players[pid].index
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
	for n in state.mercs:
		var m: Dictionary = state.mercs[n]
		if state.get_var(0, "adeadn%d" % n) >= 1.0 or not state.current_party.is_empty():
			continue   # dead, or waiting while the story uses another party
		var p := world.nav.nearest_walkable(rect.get_center() + Vector2(slot % 3 - 1, slot / 3) * 1.5)
		slot += 1
		_spawn_merc(m, p, view, true)
	for pet: Dictionary in state.pets:
		if not state.current_party.is_empty():
			break
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
		u.faction = 0
		u.mode = "player"
		u.facing = facing
		u.set_meta("tame_stage", 3)
		u.set_meta("pet", pet)
		if float(pet.get("hp", -1.0)) > 0.0:
			u.hp = minf(float(pet.hp), u.max_hp)
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
		if r.get("loot", false):
			u.set_meta("loot", [])
		if r.has("lmp_owner"):
			u.set_meta("lmp_owner", int(r.lmp_owner))
			u.set_meta("lmp_conn", int(r.get("lmp_conn", 0)))
	return u


@rpc("authority", "call_remote", "reliable")
func _rpc_zone(id: String, records: Array, diplo: PackedInt32Array, extra_mobs: Array, mpr := "", levers := {}) -> void:
	if game == null:
		zone_received.emit()
	zone_id = id
	var z := campaign.zone(id)
	if mpr != "":
		z = z.duplicate()
		z.mpr = mpr
	GameData.trace("zone load %s (from host)" % id)
	LoadingScreen.begin(get_tree(), z)
	_build_world(z, false)
	world.diplomacy = diplo
	for f: String in extra_mobs:
		world.add_mob_objects(f)
	for nid in levers:
		world.lever_sys.restore(int(nid), int(levers[nid][0]), float(levers[nid][1]))
		if levers[nid].size() > 2 and world.levers.has(int(nid)):
			world.levers[int(nid)].enabled = bool(levers[nid][2])
	for r: Dictionary in records:
		_spawn_record(r)
	_relink_heroes()
	game.attach_world(world)
	ShaderWarmup.run(game)
	LoadingScreen.end()
	GameData.trace("zone ready %s (from host)" % id)
	net.zone_loaded()


## nid -> [state, figure t, enabled] for the zone message (levers already
## switched, EnableLever).
func _lever_states() -> Dictionary:
	var out := {}
	for nid in world.levers:
		out[nid] = [world.levers[nid].state, world.lever_sys.figure_t(nid), bool(world.levers[nid].get("enabled", true))]
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
const LASTING_SPELLFX := ["firewall", "litnwall", "acid_fog", "fireworks"]

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
		"spellfx":
			var sp := Spells.parse(String(event.get("spell", event.get("code", ""))))
			if String(sp.code) in LASTING_SPELLFX:
				var ev := event.duplicate()
				var caster: GameUnit = world.units.get(int(event.get("a", -1)))
				if caster:   # the wall's direction as cast (the caster moves on)
					var d := Vector2(float(event.x), float(event.y)) - caster.pos
					d = d.normalized() if d.length() > 0.01 else Vector2.from_angle(caster.facing)
					ev.dx = d.x
					ev.dy = d.y
				elif event.has("fx"):   # cast without a caster: from its source point
					var d2 := Vector2(float(event.x) - float(event.fx), float(event.y) - float(event.fy))
					if d2.length() > 0.01:
						ev.dx = d2.normalized().x
						ev.dy = d2.normalized().y
				var spells: Array = _replay_state().spells
				# (A restored one, CampaignState.replay_restored, has only "left".)
				spells.append([ev, world.time + (float(event.left) if event.has("left")
					else maxf(float(sp.duration), 1.0) * GameUnit.TICK)])
				while spells.size() > 16:
					spells.pop_front()


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
		var gone := floorf((world.time - float(torn[id][1])) / GameUnit.TICK)
		if gone > float(ev.life):
			torn.erase(id)
			continue
		ev.x = float(ev.x) + float(ev.vx) * gone
		ev.y = float(ev.y) + float(ev.vy) * gone
		ev.life = float(ev.life) - gone
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
		if left > 0.5:
			var ev: Dictionary = e[0].duplicate()
			ev.left = left
			ev.replay = true
			out.append(ev)
	return out


## Host: what a client loading the current zone needs beyond the zone message
## (pid 0 = every client).
func _send_world_state(pid: int) -> void:
	var evs := _replay_events()
	if not world.water_levels.is_empty():   # SetWaterLevel, with the offsets reached so far
		evs.append({"t": "water", "l": world.water_levels.duplicate(true)})
	if not _dialog_ev.is_empty() and world.vm and world.vm.briefings.active == String(_dialog_ev.get("id", "")):
		evs.append(_dialog_ev)
	if not travel_options.is_empty() and not _travel_ev.is_empty():
		evs.append(_travel_ev)
	for ev: Dictionary in evs:
		if pid == 0:
			_rpc_event.rpc(ev)
		else:
			_rpc_event.rpc_id(pid, ev)


## Host: a stored zone's script particle sources and lights come back with it
## (the zone script that made them does not run again). Its PlayMusic does
## not: the original's zone load only sets the zone music mode.
func _replay_local() -> void:
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

## The player whose leave-zone box moves the party (co-op: the host, 0). The
## multiplayer game: in the original every player leaves by its own living units
## (counts only living ones, so a player whose hero is dead gets
## no box and cannot leave). **Approx.**: the remake moves the party together,
## so the box goes to the host while its hero lives, else to the lowest
## player slot with a living hero.
func leave_player() -> int:
	if lmp.is_empty() or world == null:
		return 0
	var best := -1
	for h: GameUnit in party_heroes():
		if h.controller >= 0 and not h.get_meta("hero").has("merc") and (best < 0 or h.controller < best):
			best = h.controller
	return maxi(best, 0)


## LMP, a player's hero died: when no player has a living hero left in a game
## zone, nobody could open the leave box (needs a living unit)
## and the original has no other way out for them. **Approx.** (remake rule): the
## host sends the party to the base, where a player leaving the game zone
## always goes (names the base); the zone change
## respawns every dead hero first.
func _lmp_all_dead_check() -> void:
	if world == null or String(world.zone.get("type", "")) == "brief":
		return
	for h: GameUnit in world.units.values():
		if h.controller >= 0 and h.has_meta("hero") and not h.get_meta("hero").has("merc") and not h.dead:
			return
	var base := String(lmp.get("base", ""))
	var entrance := 1
	for n in world.zone.get("exits", {}):
		if String(world.zone.exits[n].get("to", "")).to_lower() == base:
			entrance = int(world.zone.exits[n].get("to_exit", 1))
	GameData.trace("lmp: every hero is dead, the party goes to " + base)
	_lmp_leave(base, entrance)


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
func _arm_exit(player: int, at: Vector2, has_units: bool) -> void:
	if player != leave_player():
		return
	_leave_armed = -1
	if not has_units or world == null:
		return
	var n := _exit_at(at)
	if n >= 0:
		var to := String(world.zone.exits[n].get("to", "none"))
		if state.get_var(0, "z." + to.to_lower()) != 1.0:
			_leave_armed = n


func _exit_at(at: Vector2) -> int:
	var zone: Dictionary = world.zone
	for n in zone.get("exits", {}):
		var ex: Dictionary = zone.exits[n]
		if ex.has("remove") and String(ex.get("to", "none")).to_lower() != "none" and (ex.remove as Rect2).has_point(at):
			return n
	return -1


func _check_exits() -> void:
	if String(world.zone.get("type", "")) == "brief":
		_village_exit_check()
		return
	_auto_exit_check()
	if _leave_armed < 0 or not travel_options.is_empty() or (world.vm and world.vm.briefings.active):
		return
	var ex: Dictionary = world.zone.get("exits", {}).get(_leave_armed, {})
	if ex.is_empty():
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
## move click inside the exit): when every living
## hero of the host's party stands in one open exit's remove rect, the
## leave-zone box opens even without that click. Shown once per stay: it
## re-arms only after the party has left the rect (a ✗ leaves the party
## standing there); a party that starts the zone inside an exit is not asked
## until it has stepped out once.
func _auto_exit_check() -> void:
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


## A village leaves by its own rule (the village screen's update
## ..): armed from the screen's build (:
##  = 1, exit = 0), it puts only the party's FIRST record (party
## the leader) into the unit list and
## on exit 0; when that unit stands in it (target not "none", GS var
## "z.<target>" != 1) it leaves at once through — no leave-zone
## box and no check of the other members, so hired mercenaries (and other
## heroes) need not be in the exit. Remake: the host's leader (co-op: the host
## decides, as for field exits); fired once per stay in the rect, so "Stay here"
## on the global map does not reopen it at once.
func _village_exit_check() -> void:
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
		return
	if not inside:
		_auto_exit = -1
		return
	if n == _auto_exit or not travel_options.is_empty() or (world.vm and world.vm.briefings.active):
		return
	var to := String(exits[n].get("to", "none"))
	if state.get_var(0, "z." + to.to_lower()) == 1.0:
		return
	_auto_exit = n
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


## Host: go to `target` (a game/brief zone, or an edge = choice on the island map).
func leave_zone(target: String, entrance: int) -> void:
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
	else:
		# The global map's routes (CampaignMap.routes = the original)
		# from the edge; the older walk over open zones only as a fallback.
		travel_options = _route_options(target)
		if travel_options.is_empty():
			travel_options = _edge_options(target, {zone_id: true, target: true})
	if travel_options.is_empty():
		push_warning("leave_zone: no route from " + target)
		return
	broadcast({"t": "travel", "options": travel_options, "from": target})


## LMP: the base's exit names the pseudo-zone "MPGame1" — the zone of the
## quest taken (LmpMode.GAME_ZONE); a quest zone's exit names its base. The
## party goes there straight away (map-LMP.txt has no "#exit" to an edge and
## the bases' "#position" is "for single player only").
func _lmp_leave(target: String, entrance: int) -> void:
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
	for o: Dictionary in travel_options:
		if o.zone == zone and int(o.entrance) == entrance:
			travel_options = []
			broadcast({"t": "travel_close", "go": zone})   # the zone stays frozen (Game.on_event)
			state.advance_hours(float(o.get("hours", 0.0)))
			call_deferred("enter_zone", zone, entrance)
			return


# ------------------------------------------------------------------ commands

func submit(cmd: Dictionary) -> void:
	if is_host:
		coop.with_purse(my_index, apply_command.bind(cmd, my_index))
	else:
		_rpc_cmd.rpc_id(1, cmd)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_cmd(cmd: Dictionary) -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if players.has(pid):
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


## The spot of the i-th unit of a group move round the clicked point (remake).
static func group_offset(i: int) -> Vector2:
	return Vector2.ZERO if i == 0 else Vector2.from_angle(i * 2.1) * 1.2


func apply_command(cmd: Dictionary, player: int) -> void:
	if world == null:
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
			_arm_exit(player, c, not mine.is_empty())
			for i in mine.size():
				var off := group_offset(i)
				# The unit's own gait decides run / walk (the original unit)
				# "run" is the double-click flag (command).
				var mo := {"type": "move", "to": c + off, "gait": true, "run": bool(cmd.get("run", false))}
				if cmd.get("swarm", false):
					# Ctrl / aimed key on the ground: packet 0x3a, the Player
					# motivation's state 2 (UnitAI.swarm_tick), round the point.
					mo.swarm = c
				mine[i].command(mo)
		"leave_exit":   # the leave-zone box's ✓
			var lx: Dictionary = world.zone.get("exits", {}).get(int(cmd.get("exit", -1)), {})
			if player == leave_player() and not lx.is_empty():
				leave_zone(String(lx.to), int(lx.get("to_exit", 1)))
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
		"attack":
			if target:
				for u in mine:
					if u != target:   # Ctrl / aimed click may pick a party member
						# Double click: stand up and run unless in reach (case 3).
						_double_stand(u, cmd, target.pos, float(u.stats.reach) if u.stats.get("ranged", false) else u.melee_reach(target))
						u.attack(target, false, int(cmd.get("aim", -1)), bool(cmd.get("run", false)))
		"follow":
			# Follow order (HUD left strip, the original interaction mode 8): the
			# selected units keep following the clicked unit (Player motivation
			# state 6,; see GameUnit._follow_tick).
			if target and not target.dead:
				for u in mine:
					if u != target:
						u.command({"type": "follow", "target": target})
		"interact":
			if target and not mine.is_empty():
				_double_stand(mine[0], cmd, target.pos, TALK_REACH)
				mine[0].command({"type": "follow", "target": target, "dist": TALK_REACH, "once": true, "run": bool(cmd.get("run", false))})
				mine[0].set_meta("interact", [target, player])
				# The other selected units get no order: the server's handler of
				# the use / talk packet 0x36 orders one unit only
				# (the nearest one whose path reaches the target)
				# and leaves the rest where they are. **Approx.**: the remake's
				# talker is the first selected unit, not the nearest.
		"cast":
			var u := _hero_unit(int(cmd.get("unit", -1)), player)
			var spell := String(cmd.get("spell", "")).to_lower()
			if u and not u.dead and spell in u.get_meta("hero").get("spells", []):
				var tu: GameUnit = world.units.get(int(cmd.get("target", -1)))
				u.command({"type": "cast", "spell": spell, "target": tu,
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
		"equip", "unequip", "use", "give_quick", "take_quick", "select_weapon", "learn", "unlearn":
			_item_command(cmd, player)
		"buy", "sell":
			_trade(cmd, player)
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
				_double_stand(mine[0], cmd, Vector2(p3.x, p3.y), 3.0)
				mine[0].command({"type": "move", "to": world.nav.nearest_walkable(Vector2(p3.x, p3.y), 3), "gait": true,
					"run": bool(cmd.get("run", false))})
				mine[0].set_meta("interact", [obj, player])
		"steal":
			var thief: GameUnit = world.units.get(int(cmd.get("unit", -1)))
			if thief and thief.controller == player and thief.has_meta("hero") and not thief.blocked and target and not target.dead:
				# Approach to just inside the steal reach (ScriptVM._interact_reach).
				var sr := maxf(0.3, world.vm._interact_reach(thief, target, "steal") - 0.1)
				_double_stand(thief, cmd, target.pos, sr)
				thief.command({"type": "follow", "target": target, "dist": sr, "once": true, "run": bool(cmd.get("run", false))})
				thief.set_meta("interact", [target, player, "steal"])
		"loot":   # any dead unit (checks only = dead)
			if target and target.dead and lootable(target, player, _pid_of(player)) and not mine.is_empty():
				# Approach to just inside the loot reach (ScriptVM._interact_reach).
				var lr := maxf(0.3, world.vm._interact_reach(mine[0], target) - 0.1)
				_double_stand(mine[0], cmd, target.pos, lr)
				mine[0].command({"type": "follow", "target": target, "dist": lr, "once": true, "corpse": true, "run": bool(cmd.get("run", false))})
				mine[0].set_meta("interact", [target, player])
		"stop":
			for u in mine:
				u.command({"type": "wait", "t": 0.1})
		"travel":
			if player == 0 or not players_include(0):
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
	if not players_include(int(m.get("controller", 0))):
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
		u.controller = int(m.controller)
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
	for u: GameUnit in world.units.values():
		if u.controller == player and u.has_meta("hero") and not u.get_meta("hero").has("merc"):
			if at == Vector2.INF:
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
	broadcast({"t": "party"})
	sync_state()


## `player`: the one who hired it in a conversation (
##  on that player), -1 = scripts (the remake's choice: the
## player with the fewest units).
func merc_changed(n: int, hired: bool, player := -1) -> void:
	if world == null:
		return
	if hired and not state.mercs.has(n):
		var npc: GameUnit = null
		for u: GameUnit in world.units.values():
			if String(u.info.get("name", "")).to_lower() == "merc%d" % n and not u.has_meta("hero"):
				npc = u
		var rec: Dictionary = npc.info.duplicate() if npc else _find_merc_record(n)
		if rec.is_empty():
			return
		var m := state.make_merc(n, rec)
		m.controller = player if player >= 0 and players_include(player) else _merc_owner()
		var heroes := party_heroes()
		var at: Vector2 = npc.pos if npc else (heroes[0].pos if not heroes.is_empty() else Vector2.ZERO) + Vector2(1, 1)
		var facing: float = npc.facing if npc else 0.0
		if npc:
			# the original puts the village unit itself into the party:
			# it leaves its zone (stored as removed), so it cannot be hired
			# again there, nor stand in the village while it travels or after
			# it died.
			world.remove_unit(npc)
			broadcast({"t": "remove", "uid": npc.uid})
		var u := _spawn_merc(m, world.nav.nearest_walkable(at), facing)
		if u:
			announce_unit(u)
		broadcast({"t": "party"})
		sync_state()
	elif not hired and state.mercs.has(n):
		var m: Dictionary = state.mercs[n]
		state.mercs.erase(n)
		for u: GameUnit in world.units.values():
			if u.has_meta("hero") and u.get_meta("hero") == m:
				world.remove_unit(u)
				broadcast({"t": "remove", "uid": u.uid})
				# Dismissed in its village (n2), the same unit stays there as the
				# village NPC again (the scripts walk it back to its spot).
				var rec := {}
				for r: Dictionary in (world.map.unit_records if world.map else []):
					if String(r.get("name", "")).to_lower() == "merc%d" % n:
						rec = r.duplicate()
				if not rec.is_empty() and not u.dead and not world.units.has(int(rec.get("nid", 0))):
					rec.position = Vector3(u.pos.x, u.pos.y, 0)
					var npc := world.spawn_unit(rec)
					if npc:
						npc.facing = u.facing
						announce_unit(npc)
		broadcast({"t": "party"})
		sync_state()


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
## Search radius for a belt item's offensive spell target (the original takes the
## nearest hostile unit the player sees; approx.).
const BELT_TARGET_RANGE := 40.0


func _hero_unit(uid: int, player: int) -> GameUnit:
	var u: GameUnit = world.units.get(uid) if world else null
	return u if u and u.controller == player and u.has_meta("hero") else null


## Host: equipment and item use. The bag (state.items) is shared by the party.
func _item_command(cmd: Dictionary, player: int) -> void:
	var u := _hero_unit(int(cmd.get("unit", -1)), player)
	if u == null:
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
			state.items.remove_at(bag_i)
			if sl == "weapon":
				# Four weapon slots (the original unit); the new
				# one becomes the active weapon (weapons[0]), a fifth goes back
				# to the bag.
				h.weapons.insert(0, item)
				while h.weapons.size() > WEAPON_SLOTS:
					state.items.append(h.weapons.pop_back())
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
			h.weapons.remove_at(wi)
			h.weapons.insert(0, item)
			_refresh_hero(u)
		"unequip":
			var wi := find_item(h.weapons, item)
			var ai := find_item(h.armors, item) if wi < 0 else -1
			if wi >= 0:
				item = h.weapons[wi]
				h.weapons.remove_at(wi)
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
			if item.substr(6) in known:
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
				u.command({"type": "cast", "spell": sp, "target": tu, "item": item,
					"point": Vector2(float(cmd.get("x", tu.pos.x if tu else u.pos.x)), float(cmd.get("y", tu.pos.y if tu else u.pos.y)))})
				return
			var tgt := u
			if Spells.offensive(sp):
				tgt = world.ai.nearest_enemy(u, BELT_TARGET_RANGE)
				if tgt == null:
					return
			if Items.is_wand(item):
				if not use_charge(q, qi):
					return
			else:
				q.remove_at(qi)
			Spells.apply(world, u, sp, tgt, tgt.pos)
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
	var h: Dictionary = u.get_meta("hero")
	Combat.hero_stats(u, h)
	u.set_equipment(PackedStringArray(h.armors), PackedStringArray(h.weapons))
	broadcast({"t": "equip", "uid": u.uid, "armors": h.armors, "weapons": h.weapons})
	sync_state()


func shop_available() -> bool:
	return world != null and String(world.zone.get("type", "")) == "brief"


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
		party += state.mercs.values()
		for h: Dictionary in party:
			for st: String in Skills.SCHOOL:
				best[st] = maxf(float(best.get(st, -1e20)), Skills.knowledge(h, st))
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		rec.goods = Shops.generate(id, rec.get("sold", {}), best, rng)
		rec.restock = false
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


func _trade(cmd: Dictionary, _player: int) -> void:
	var sid := shop_id(cmd)
	if sid == 0:
		return
	var rec := shop_record(sid)
	var goods: Dictionary = rec.goods
	var item := String(cmd.get("item", "")).to_lower()
	var spellish := item.begins_with("spell:") or item.begins_with("rune:")
	if not (Shops.sells_spells(sid) if spellish else Shops.sells_items(sid)):
		return
	if cmd.t == "buy":
		# The goods are the trader's inventory (moves the buy pile
		# out of it): what is bought is gone until the next restock.
		if int(goods.get(item, 0)) <= 0:
			return
		var p := Items.buy_price(item)
		if state.money < p:
			return
		# Spells too go into the party's bag (moves the whole buy
		# pile, modes 2 and 4); a hero learns one from there ("learn").
		state.money -= p
		_take_goods(goods, item, 1)
		state.items.append(item)
	else:
		var i := state.items.find(item)
		if i < 0 or Items.kind(item) == "quest":
			return
		state.items.remove_at(i)
		var p := Items.deal_price(item, Items.Deal.SPELL_SELL if spellish else Items.Deal.SELL)
		state.money += p
		_sold_to(rec, item)
	sync_state()


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
	if plain.begins_with("spell:"):
		table = "spell_prototypes"
		key = String(Spells.parse(plain.substr(6)).code)
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
## - A spell with runes alone = take apart: costs trunc(price ×
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
## Approx.: a keystone and a rune-less spell are the same "spell:<code>" in
## the remake, so a build needs at least one rune and only a spell with runes
## is taken apart.
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
	if not ids[0].begins_with("spell:") or not froms[0] in ["bag", "shop", "known"]:
		return {}
	for i in range(1, ids.size()):
		if not ids[i].begins_with("rune:") or not froms[i] in ["bag", "shop"]:
			return {}
	var spell := ids[0].substr(6)
	if Spells.parse(spell).proto.is_empty():
		return {}
	var take_apart := Spells.mods_of(spell).size() > 0
	#  mode 3: a ready spell takes the pile alone; runes need a keystone.
	if take_apart and ids.size() > 1 or not take_apart and ids.size() < 2:
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
		out.items.append("spell:" + String(Spells.parse(spell).code))
		for m in Spells.mods_of(spell):
			out.items.append("rune:" + m)
		state.items.append_array(out.items)
	else:
		out.items.append("spell:" + built)
		if ki >= 0 and Spells.usable_by(hu.get_meta("hero"), hu.max_mana, built):
			known.insert(ki, built)
			out.where = "known"
		else:
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


## Host: Use/Steal on a living unit, the original. The thief's value
## (Dex - 25 + Use/Steal skill,; belt modifiers are 0 in items.idb)
## must beat the target's (characters the same, others the prototype's "general
## skills"); there is no random roll. Success takes the first thing in the
## target's pockets; failure alerts the target.
func steal(u: GameUnit, t: GameUnit) -> void:
	var h: Dictionary = u.get_meta("hero")
	var mine := float(u.stats.get("dex", 25.0)) - 25.0 + Skills.level(h, "science")
	var theirs := float(t.proto.get("general_skills", 0.0))
	if t.has_meta("hero"):
		theirs = float(t.stats.get("dex", 25.0)) - 25.0 + Skills.level(t.get_meta("hero"), "science")
	if mine <= theirs:
		world.ai.on_attacked(t, u)
		return
	if not t.has_meta("pockets"):
		t.set_meta("pockets", Items.roll_loot(t.proto, t.info, world.combat.rng))
	var pockets: Array = t.get_meta("pockets")
	if pockets.is_empty():
		return
	var st := Items.parse_stack(String(pockets.pop_front()))
	if st[0] == "money":
		state.money += st[1]
	else:
		state.add_item(st[0], st[1])
	notify_got(u.controller, [] if st[0] == "money" else [st[0]], st[1] if st[0] == "money" else 0)
	sync_state()


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
## remake's "remove").
func take_loot(u: GameUnit, corpse: GameUnit) -> void:
	var loot: Array = corpse.get_meta("loot", []) if not corpse.get_meta("looted", false) else []
	corpse.remove_meta("loot")
	corpse.set_meta("looted", true)   # script builtin WasLooted
	broadcast({"t": "loot", "uid": corpse.uid, "has": false})
	world.remove_looted(corpse)
	broadcast({"t": "remove", "uid": corpse.uid})
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
			state.add_item(st[0], st[1])
			got.append(st[0])
	notify_got(u.controller, got, money)
	sync_state()


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
			Spells.apply(world, u, sp, u, u.pos)
			cd[key] = 8 if int(p.duration) - 3 < 1 else int(p.duration) - 3
		u.set_meta("ic_cd", cd)
	if spent:
		_state_dirty = true


func _physics_process(dt: float) -> void:
	if is_host and world and world.authority:
		_exit_t -= dt
		if _exit_t <= 0.0:
			_exit_t = 0.25
			_check_exits()
		_ic_t += dt
		while _ic_t >= GameUnit.TICK:
			_ic_t -= GameUnit.TICK
			_ic_spells()
		# Campaign state (vars, quests, items) reaches clients in batches.
		_sync_t -= dt
		if online and (_state_dirty and _sync_t <= 0.0 or _sync_t <= -5.0):
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
	# Stay under the ENet MTU: ~130 bytes per unit record, more for units
	# with magic effects (the chunk closes early then).
	var chunk := []
	var size := 0
	for sn: Array in snaps:
		var n := 130 if (sn[11] as Array).is_empty() else var_to_bytes(sn).size()
		if not chunk.is_empty() and (chunk.size() >= SNAP_CHUNK or size + n > SNAP_BYTES):
			_rpc_snap.rpc(chunk, world.time)
			chunk = []
			size = 0
		chunk.append(sn)
		size += n
	if not chunk.is_empty():
		_rpc_snap.rpc(chunk, world.time)
	snap_usec += Time.get_ticks_usec() - t0


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snap(snaps: Array, t: float) -> void:
	if world == null:
		return
	world.time = t
	for s: Array in snaps:
		var u: GameUnit = world.units.get(int(s[0]))
		if u:
			u.apply_snapshot(s)


## Seconds before a co-op player's hero rises again (approx.; the original
## multiplayer respawns on the player's request).
const RESPAWN_DELAY := 5.0


## Host: a player's own hero died. Single player: "Your main character is dead!"
## (texts.res game_over_msg) -> load or leave. Co-op: the original multiplayer
## ("LMP", the -lmp campaign maps) rules bring it back.
func hero_died(u: GameUnit) -> void:
	if not is_host:
		return
	var alive := false
	for o: GameUnit in world.units.values():
		if o.has_meta("hero") and not o.get_meta("hero").has("merc") and not o.dead and o.controller >= 0:
			alive = true
	# only a single-player game ends (client message 9); in a
	# network game a dead hero always comes back, even with everyone dead.
	if (not online or not alive) and lmp.is_empty():
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
		_lmp_all_dead_check()
		return
	# Weak references: the zone (and the unit with it) may go before the timer.
	var ur: WeakRef = weakref(u)
	var wr: WeakRef = weakref(world)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(func():
		var du = ur.get_ref()
		if du and du.dead and world != null and world == wr.get_ref():
			coop.with_purse(du.controller, respawn.bind(du)))   # the death toll from its owner's purse


## money - round(money x [LMP] "Lost Money"), experience debt +=
## "Lost XP" x experience (paid off by later gains), all body parts
## restored. The hero rises next to a living party member.
func respawn(u: GameUnit) -> void:
	var h: Dictionary = u.get_meta("hero")
	var lost := int(round(state.money * GameData.ai_value("LMP", "Lost Money", 0.05)))
	state.money -= lost
	h.exp_debt = float(h.get("exp_debt", 0.0)) + GameData.ai_value("LMP", "Lost XP", 0.05) * float(h.get("exp_total", h.get("exp", 0.0)))
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


## LMP (the original, network branch): the dead hero's body stays
## where it fell and the hero rises as a new unit (id + 250000)
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
	if is_host:
		_track(event)
	_on_event(event)
	if online and is_host:
		_rpc_event.rpc(event)


@rpc("authority", "call_remote", "reliable")
func _rpc_event(event: Dictionary) -> void:
	_on_event(event)


func _on_event(event: Dictionary) -> void:
	var t := String(event.get("t", ""))
	if t == "travel":
		map_open = true
		GameData.trace("travel map open from %s" % zone_id)
	elif t == "travel_close":
		map_open = false
		GameData.trace("travel map closed in %s" % zone_id)
	# World-state events only need applying on clients; the host already did it.
	if not is_host and world:
		match t:
			"remove":
				var u: GameUnit = world.units.get(int(event.uid))
				if u:
					world.remove_unit(u)
			"spawn":
				_spawn_record(event.rec)
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
					world.levers[int(event.nid)].state = event.state
					world.lever_sys.apply(int(event.nid), true, float(event.get("time", -1.0)))
			"diplo":
				world.set_relation(event.a, event.b, event.v)
			"water":   # script SetWaterLevel: the host's whole list
				world.set_water_state(event.l)
			"arrow":
				var a: GameUnit = world.units.get(int(event.a))
				var b: GameUnit = world.units.get(int(event.b))
				if a and b:
					Projectile.launch(world, a, b, false)
			"state":
				state.money = event.money
				state.quests = event.quests
				state.quest_items = event.quest_items
				state.items = event.items
				state.heroes = event.heroes
				state.mercs = event.get("mercs", state.mercs)
				state.side_quests = event.get("side_quests", {})
				state.shops = event.get("shops", state.shops)
				state.visited = event.get("visited", {})
				state.vars = event.get("vars", state.vars)
				state.last_quest = String(event.get("last_quest", state.last_quest))
				state.world_time = float(event.get("world_time", state.world_time))
				state.day = int(event.get("day", state.day))
				_relink_heroes()
				if game:
					game.on_event({"t": "inventory"})
			"equip":
				var u: GameUnit = world.units.get(int(event.uid))
				if u:
					u.set_equipment(PackedStringArray(event.armors), PackedStringArray(event.weapons))
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
	if t == "spellfx" and world:
		var sp := Spells.parse(String(event.code))
		if not event.get("replay", false):   # a lasting spell seen by a joiner: no flash or sound
			SpellFx.spawn(world, Vector2(event.x, event.y), String(event.sub), sp.radius,
				float(event.get("hold", 0.0)), sp.proto)
			GameSound.spell(String(event.code), EISpace.pos(event.x, event.y, world.ground_at(event.x, event.y)), "end")
		ParticleFx.of(world).spell_cast(event)
	if world and t in ParticleFx.EVENTS:   # visual only, on every peer
		ParticleFx.of(world).on_event(event)
	if world and t == "blood":   # the hit's blood mark (visual only, every peer)
		GroundMarks.of(world).hit(event)
	if t == "hitnum":   # floating hit / experience number (every peer)
		if game:
			FlyingHP.of(game).add(event)
		return
	match t:
		"msg":
			if int(event.get("to", my_index)) == my_index:
				message.emit(String(event.text))
		"say": _say(event)
		_:
			if game:
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
			"vars": state.vars, "last_quest": state.last_quest, "world_time": state.world_time, "day": state.day}
		# Each peer sees its own purse and bag (CoopProgress.state_for).
		for pid in multiplayer.get_peers():
			if CoopProgress.peer_alive(multiplayer, pid):
				_rpc_event.rpc_id(pid, coop.state_for(pid, ev))
	if game:
		game.on_event({"t": "inventory"})


## Client: point hero units at the hero records received from the host.
func _relink_heroes() -> void:
	if world == null:
		return
	for u: GameUnit in world.units.values():
		if u.controller < 0:
			continue
		for h: Dictionary in state.heroes.get(u.controller, []):
			if String(h.get("unit_name", h.name)) == String(u.info.get("name", "")):
				u.set_meta("hero", h)
				u.display_name = h.name
				Combat.sync_natural_armor(u, h)   # as on the host (cleared when deployed)
		# Mercenaries (their units keep the map name "merc<N>", CampaignState.merc_record).
		for m: Dictionary in state.mercs.values():
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
func _rpc_hello(player_name: String, hero_class: String, protocol := 0, maps_md5 := "") -> void:
	if not is_host:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not CoopProgress.peer_alive(multiplayer, pid):
		return   # dropped again before its hello was handled (it will say hello anew)
	_drop_stale_peer(pid, player_name)
	if net.refuse(pid, protocol, maps_md5):
		return
	var idx := _player_slot(player_name)
	var in_game := world != null
	players[pid] = {"index": idx, "name": player_name, "hero": hero_class}
	_rpc_players.rpc(players)
	_rpc_welcome.rpc_id(pid, idx)
	broadcast({"t": "msg", "text": net.joined_text(player_name)})
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
		_spawn_late_joiner(idx, pid)
	players_changed.emit()


## Player index for a joining player: a player coming back (same name as a
## co-op hero whose player is gone) gets the old slot and so the old hero;
## anyone else the lowest free index. Remake-only.
func _player_slot(player_name: String) -> int:
	var used := players.values().map(func(p): return int(p.index))
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
		if old == pid or old == 1 or String(players[old].name) != player_name:
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
	var leader: GameUnit = null
	for u: GameUnit in world.units.values():
		if u.controller == 0 and not u.dead:
			leader = u
			break
	var reclaimed := false
	for u: GameUnit in world.units.values():
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
	_rpc_zone.rpc_id(pid, zone_id, _unit_records(), world.diplomacy, _extra_mobs(),
		String(world.zone.get("mpr", "")), _lever_states())
	_send_world_state(pid)
	for u in fresh:
		announce_unit(u, pid)
	broadcast({"t": "party"})
	sync_state()


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
	if enet == null:
		return
	var p := enet.get_peer(pid)
	if p:
		p.set_timeout(0, PEER_TIMEOUT_MS, PEER_TIMEOUT_MS)


func _on_peer_disconnected(pid: int) -> void:
	if _building:   # noticed by NetStatus.keep_alive inside a zone build
		_on_peer_disconnected.call_deferred(pid)
		return
	if not is_host or not players.has(pid):
		return
	var idx: int = players[pid].index
	broadcast({"t": "msg", "text": net.gone_text(pid, players[pid].name)})
	net.forget(pid)
	players.erase(pid)
	# Their heroes stay with the party under AI control, following the leader.
	if world:
		for u: GameUnit in world.units.values():
			if u.controller == idx:
				u.controller = -1
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
func save_game(slot: String, save_name := "", frame: Image = null) -> void:
	if not is_host:
		message.emit(RemakeText.t("Only the host can save."))
		return
	if not lmp.is_empty():
		return   # the multiplayer game has no saves (its network heroes keep themselves)
	if coop.purse_active():   # mid-command of a joiner (its purse in state): right after
		save_game.call_deferred(slot, save_name, frame)
		return
	state.collect_pets(world)
	state.store_zone(zone_id, world)
	state.current_zone = zone_id
	state.store_party_positions(world)
	state.camera = game.rig.pose() if game and game.rig else {}   # scenario.sav camera record
	if game and game.hud and game.hud.minimap and not state.camera.is_empty():
		state.camera["minimap_zoom"] = game.hud.minimap.zoom   #  reads it back
	coop.before_save()
	GameData.trace("save %s in %s" % [slot, zone_id])
	var err := state.save("user://saves/%s.sav" % slot)
	GameData.trace("save %s done (%d)" % [slot, err])
	if err == OK:
		# The Load screen's entry (the original info.sav / shot.sav).
		SaveInfo.write(slot, state.get_var(0, "gtime"), _allod_id(), zone_id, save_name)
		if frame:
			SaveInfo.write_shot_image(slot, frame)
		else:
			SaveInfo.write_shot(slot, get_viewport())
	# No log line: the original checks the free space first («no_disc_space» box
	# load_panel) and shows nothing after a save; while it saves it shows
	# «string notify_saving» (NotifyLine; after the shot, so the
	# picture stays clean). Not for the zone autosave.
	if err != OK:
		push_error("save %s failed (%d)" % [slot, err])
	elif slot != "autosave" and game and game.hud:
		game.hud.notify("string notify_saving")


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
		var p := "user://saves/%s.sav" % slot
		if GameFiles.exists(p) and FileAccess.get_modified_time(p) >= t:
			t = FileAccess.get_modified_time(p)
			best = slot
	return best


func load_game(slot: String) -> bool:
	GameData.trace("load %s (from %s)" % [slot, zone_id])
	var s := CampaignState.load_from("user://saves/%s.sav" % slot)
	if s == null:
		GameData.trace("load %s failed" % slot)
		return false
	coop.before_load(slot, s)
	# Players connected now who joined after that save was made (co-op class
	# heroes; brought heroes come from before_load) still get a hero.
	for pid in players:
		var idx := int(players[pid].index)
		if idx > 0:
			s.ensure_hero(idx, _hero_proto(idx), String(players[pid].name))
	state = s
	zone_id = ""
	_restoring = true
	enter_zone(s.current_zone, 1, false)
	_restoring = false
	state.restore_party_positions(world)
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
	GameData.trace("load %s done in %s" % [slot, zone_id])
	return true

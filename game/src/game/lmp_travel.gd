extends RefCounted
## The native LMP server keeps a base and one quest world. A connection can
## leave the quest while the remaining registered players keep playing.
## Session's temporary world scopes are synchronous, like its purse scopes;
## a deferred departure always carries the owner and its old generation.

const FIELDS := ["world", "zone_id", "_snap_t", "_snap_count", "_last_snap", "_exit_t",
	"_leave_armed", "_auto_exit", "_auto_world", "travel_options", "_travel_ev", "map_open",
	"_dialog_ev", "_alone_exit", "_alone_world", "_ic_t", "_lmp_entrance"]

var session: Session
var contexts := {}                 # zone id -> the world's Session fields
var owners := {}                   # player slot -> zone / entrance / generation / loading
var quest_zone := ""
var _depth := 0


func _init(s: Session) -> void:
	session = s


func adopt() -> void:
	var ctx := _capture()
	contexts[session.zone_id] = ctx
	if session.zone_id != String(session.lmp.base):
		quest_zone = session.zone_id
	for p: Dictionary in session.players.values():
		owners[int(p.index)] = {"zone": session.zone_id, "entrance": session._lmp_entrance,
			"generation": 1, "loading": int(p.index) != 0, "armed": -1, "auto": -2}
	session.lmp_generation = 1
	_publish_locations()


func _capture() -> Dictionary:
	var ctx := {}
	for key: String in FIELDS:
		ctx[key] = session.get(key)
	ctx.world_time = session.state.world_time
	ctx.day = session.state.day
	return ctx


func _install(ctx: Dictionary) -> void:
	for key: String in FIELDS:
		if ctx.has(key):
			session.set(key, ctx[key])
	session.state.world_time = float(ctx.get("world_time", session.state.world_time))
	session.state.day = int(ctx.get("day", session.state.day))


func _store(ctx: Dictionary) -> void:
	ctx.merge(_capture(), true)


## No await, timers or deferred callback may be inside this scope.
func with_world(w: GameWorld, f: Callable) -> Variant:
	if w == null:
		return null
	var id := String(w.zone.get("id", ""))
	if not contexts.has(id) or contexts[id].world != w:
		return null
	return _with_context(contexts[id], f)


func _with_context(ctx: Dictionary, f: Callable) -> Variant:
	if ctx.get("world") == session.world and String(ctx.get("zone_id", "")) == session.zone_id:
		_depth += 1
		var direct = f.call()
		_depth -= 1
		_store(ctx)
		return direct
	var previous := _capture()
	var old: Dictionary = contexts.get(session.zone_id, {})
	if not old.is_empty():
		old.merge(previous, true)
	_install(ctx)
	_depth += 1
	var result = f.call()
	_depth -= 1
	_store(ctx)
	_install(previous)
	return result


func owner_world(player: int) -> GameWorld:
	var id := zone_of(player)
	return contexts.get(id, {}).get("world")


func zone_of(player: int) -> String:
	return String(owners.get(player, {}).get("zone", ""))


func generation_of(player: int) -> int:
	return int(owners.get(player, {}).get("generation", 0))


func loading(player: int) -> bool:
	return bool(owners.get(player, {}).get("loading", true))


func registered(id: String) -> Array:
	var out := []
	for idx in owners:
		if zone_of(int(idx)) == id and session.players_include(int(idx)):
			out.append(int(idx))
	return out


func can_tick(w: GameWorld) -> bool:
	return w != null and not registered(String(w.zone.get("id", ""))).is_empty()


func contains(w: GameWorld) -> bool:
	return w != null and contexts.get(String(w.zone.get("id", "")), {}).get("world") == w


func same_place(a: int, b: int) -> bool:
	return not zone_of(a).is_empty() and zone_of(a) == zone_of(b) and not loading(a) and not loading(b)


## only the quest WorldServer's registered players count.
## State 3 departures cease registration in 58dff0 =66d230.
## A dead unit does not remove its connection; base/lobby players do not count.
func host_can_leave() -> bool:
	var id := zone_of(0)
	return id == String(session.lmp.base) or registered(id).size() <= 1


func accepts(player: int, zone: String, generation: int) -> bool:
	return session.players_include(player) and not loading(player) \
		and zone_of(player) == zone and generation_of(player) == generation


func command(cmd: Dictionary, player: int) -> void:
	if not accepts(player, String(cmd.get("_zone", "")), int(cmd.get("_generation", 0))):
		return
	var w := owner_world(player)
	with_world(w, func(): session.coop.with_purse(player, session.apply_command.bind(cmd, player)))


func peers_here() -> Array:
	var out := []
	for idx: int in registered(session.zone_id):
		var pid := session._pid_of(idx)
		if pid > 1 and CoopProgress.peer_alive(session.multiplayer, pid):
			out.append(pid)
	return out


func send_event(pid: int, ev: Dictionary) -> void:
	if not session.players.has(pid):
		return
	var idx := int(session.players[pid].index)
	if zone_of(idx) != session.zone_id:
		return
	session._rpc_lmp_event.rpc_id(pid, session.zone_id, generation_of(idx), ev)


func broadcast(ev: Dictionary) -> void:
	var target := int(ev.get("to", -1))
	if session.game and session.game.world == session.world and (target < 0 or target == session.my_index):
		session._on_event(ev)
	if not session.online:
		return
	for pid: int in peers_here():
		if target < 0 or int(session.players[pid].index) == target:
			send_event(pid, ev)


func send_snap(snaps: Array, time: float) -> void:
	for pid: int in peers_here():
		var idx := int(session.players[pid].index)
		session._rpc_lmp_snap.rpc_id(pid, session.zone_id, generation_of(idx), snaps, time)


func publish(pid := 0) -> void:
	if not session.online:
		return
	var destinations := peers_here() if pid == 0 else [pid]
	for peer: int in destinations:
		if not session.players.has(peer):
			continue
		var idx := int(session.players[peer].index)
		if zone_of(idx) != session.zone_id:
			continue
		session.net.loading_started(peer, generation_of(idx))
		session._rpc_lmp_zone.rpc_id(peer, session.zone_id, generation_of(idx), session._unit_records(),
			session.world.diplomacy, session._extra_mobs(), String(session.world.zone.get("mpr", "")), session._lever_states())
		session._send_world_state(peer)


func loaded(pid: int, zone: String, generation: int) -> bool:
	if not session.players.has(pid):
		return false
	var idx := int(session.players[pid].index)
	if zone_of(idx) != zone or generation_of(idx) != generation:
		return false
	owners[idx].loading = false
	_publish_locations()
	session.mark_dirty()
	return true


func physics(dt: float) -> void:
	for ctx: Dictionary in contexts.values():
		var w: GameWorld = ctx.get("world")
		if can_tick(w):
			with_world(w, session._tick_world_session.bind(dt))


func _new_context(id: String) -> Dictionary:
	return {"world": null, "zone_id": id, "_snap_t": 0.0, "_snap_count": 0,
		"_last_snap": {}, "_exit_t": 0.0, "_leave_armed": -1, "_auto_exit": -1,
		"_auto_world": null, "travel_options": [], "_travel_ev": {}, "map_open": false,
		"_dialog_ev": {}, "_alone_exit": {}, "_alone_world": null, "_ic_t": 0.0,
		"_lmp_entrance": 1, "world_time": session.state.world_time, "day": session.state.day}


func ensure_world(id: String) -> GameWorld:
	if contexts.has(id):
		return contexts[id].world
	if id != String(session.lmp.base):
		if not quest_zone.is_empty() and quest_zone != id:
			if not registered(quest_zone).is_empty():
				return null   # never replace a map under its registered players
			_drop_world(quest_zone)
		quest_zone = id
	var z := session._zone_variant(session.campaign.zone(id))
	var ctx := _new_context(id)
	contexts[id] = ctx
	_with_context(ctx, func():
		session._build_world(z, true, false)
		session.world.vm = ScriptVM.create(session.world, session)
		session.state.visited[id] = true)
	return ctx.world


func quest_taken(id: String) -> void:
	if not quest_zone.is_empty() and registered(quest_zone).is_empty():
		_drop_world(quest_zone, false)
		quest_zone = ""
	session.state.zones.erase(id)


func _drop_world(id: String, persist := true) -> void:
	var ctx: Dictionary = contexts.get(id, {})
	if ctx.is_empty():
		return
	if persist:
		with_world(ctx.world, func(): session.state.store_zone(id, session.world))
	ctx.world.queue_free()
	contexts.erase(id)


## Queued with the source generation. No asynchronous world scope is held.
func request(player: int, target: String, entrance: int) -> bool:
	if not session.players_include(player) or not owners.has(player) or loading(player):
		return false
	target = target.to_lower()
	if target == LmpMode.GAME_ZONE:
		target = String(session.lmp.get("quest", ""))
	if target.is_empty() or not session.zone_exists(target) or session.campaign.zone(target).is_empty():
		return false
	if target != String(session.lmp.base) and target != String(session.lmp.get("quest", "")):
		return false
	if target != String(session.lmp.base) and not quest_zone.is_empty() and quest_zone != target \
			and not registered(quest_zone).is_empty():
		return false
	if player == 0 and target == String(session.lmp.base) and not host_can_leave():
		var text := GameData.text("string no_way").strip_edges()
		if text:
			session.message.emit(text)
		return false
	var old := generation_of(player)
	owners[player].loading = true   # refuse all further old-map orders immediately
	_publish_locations()
	call_deferred("_perform", player, target, maxi(1, entrance), old)
	return true


func _perform(player: int, target: String, entrance: int, old_generation: int) -> void:
	if not owners.has(player) or not session.players_include(player) or generation_of(player) != old_generation:
		return
	var source := owner_world(player)
	if source == null:
		owners[player].loading = false
		return
	var destination := ensure_world(target)
	if destination == null:
		owners[player].loading = false
		_publish_locations()
		return
	session.swap.cancel_player(player)
	with_world(source, _detach_party.bind(player, true))
	owners[player] = {"zone": target, "entrance": entrance, "generation": old_generation + 1,
		"loading": player != 0, "armed": -1, "auto": -2}
	_publish_locations()
	with_world(destination, _deploy_party.bind(player, entrance))
	if player == 0:
		_activate(destination)
	else:
		with_world(destination, publish.bind(session._pid_of(player)))
	session._mp_send(player)
	session.mark_dirty()
	session.sync_state()


func _activate(w: GameWorld) -> void:
	var old: Dictionary = contexts.get(session.zone_id, {})
	if not old.is_empty():
		_store(old)
	_install(contexts[String(w.zone.id)])
	session.lmp_generation = generation_of(0)
	if session.game:
		session.game.attach_world(w)
		session.game.rig.village_start_view(w.zone)
		for ev: Dictionary in session._replay_events():
			if String(ev.get("t", "")) not in ["music"]:
				session._on_event(ev)
	_store(contexts[String(w.zone.id)])


func _detach_party(player: int, respawn_dead: bool) -> void:
	var w := session.world
	if respawn_dead:
		var hero_present := false
		for u: GameUnit in w.units.values().duplicate():
			if u.controller == player and u.has_meta("hero") and not u.get_meta("hero").has("merc"):
				hero_present = true
				if u.dead:
					session._lmp_entrance = int(owners[player].entrance)
					session.coop.with_purse(player, session.respawn.bind(u))
		if not hero_present:
			# 66f480 takes the toll even when 55fb00 cannot find the old unit.
			# Its body loot record then has no physical body to resolve.
			session.coop.with_purse(player, func():
				var lost := int(round(session.state.money * GameData.ai_value("LMP", "Lost Money", 0.05)))
				session.state.money -= lost
				session.state.items.clear()
				for h: Dictionary in session.state.heroes.get(player, []):
					h.exp_debt = float(h.get("exp_debt", 0.0)) + GameData.ai_value("LMP", "Lost XP", 0.05) * Session.lmp_toll_base(h)
					h.hp = -1.0
					h.erase("dead")
					h.erase("body"))
	# Capture only this owner's party: another quest player keeps its current
	# orders, live pools, follow targets and party records throughout the move.
	session.state.pets = session.state.pets.filter(func(p): return int(p.get("controller", -1)) != player)
	for u: GameUnit in w.units.values().duplicate():
		if u.controller != player:
			continue
		if u.has_meta("hero"):
			var h: Dictionary = u.get_meta("hero")
			h.hp = u.hp
			h.mana = u.mana
			h.pos = u.pos
			h.gait = u.gait()
			h.body = CampaignState.body_state(u)
			if u.dead:
				h.dead = true
			else:
				h.erase("dead")
			if String(w.zone.get("type", "")) != "brief":
				var ref := CampaignState.party_ref(CampaignState.follow_target(u))
				if ref.is_empty():
					h.erase("follow")
				else:
					h.follow = ref
		elif CampaignState.is_pet(u):
			var rec := u.info.duplicate()
			rec.erase("nid")
			session.state.pets.append({"rec": rec, "hp": u.hp, "controller": player,
				"pos": u.pos, "body": CampaignState.body_state(u)})
		session.broadcast({"t": "remove", "uid": u.uid})
		w.remove_unit(u)
	session.broadcast({"t": "party"})


func _deploy_party(player: int, entrance: int) -> void:
	var w := session.world
	var ex: Dictionary = w.zone.get("exits", {}).get(entrance, {})
	var center := w.terrain.size_ei() * 0.5 if w.terrain else Vector2.ZERO
	var rect: Rect2 = ex.get("deploy", Rect2(center, Vector2(4, 4)))
	var facing := deg_to_rad(float(ex.get("view", 0.0)))
	var fresh := []
	var slot := 0
	for h: Dictionary in session.state.heroes.get(player, []):
		var quick = h.get("quick", [])
		for i in quick.size():
			quick[i] = Items.with_charge(quick[i], Items.energy(quick[i]))
	for rec: Dictionary in session.state.party_records(player):
		var p := w.nav.nearest_walkable(rect.get_center() + Vector2(slot % 3 - 1, slot / 3) * 1.5)
		rec.position = Vector3(p.x, p.y, 0)
		rec.nid = w.new_uid()
		var u := w.spawn_unit(rec)
		if u:
			u.controller = player
			u.faction = 0
			u.mode = "player"
			u.facing = facing
			session.state.apply_hero(u)
			fresh.append(u)
			session.announce_unit(u, session._pid_of(player))
		slot += 1
	for pet: Dictionary in session.state.pets:
		if int(pet.get("controller", -1)) != player:
			continue
		var p := w.nav.nearest_walkable(rect.get_center() + Vector2(slot % 3 - 1, slot / 3) * 1.5)
		var u := session._spawn_pet(pet, p, facing)
		if u:
			fresh.append(u)
			session.announce_unit(u, session._pid_of(player))
		slot += 1
	if String(w.zone.get("type", "")) != "brief" and not fresh.is_empty():
		session.state.apply_follow(w, "follow", fresh)
	session.broadcast({"t": "party"})


func join(player: int, pid: int) -> void:
	var base := String(session.lmp.base)
	var w := ensure_world(base)
	if w == null:
		return
	owners[player] = {"zone": base, "entrance": 1, "generation": generation_of(player) + 1,
		"loading": true, "armed": -1, "auto": -2}
	_publish_locations()
	with_world(w, func():
		_deploy_party(player, 1)
		publish(pid))
	session.mark_dirty()
	session.sync_state()


func disconnect_player(player: int) -> void:
	var w := owner_world(player)
	session.swap.cancel_player(player)
	if w:
		with_world(w, _detach_party.bind(player, false))
	owners.erase(player)
	_publish_locations()


func _publish_locations() -> void:
	var public := {}
	for idx in owners:
		public[idx] = {"zone": zone_of(int(idx)), "generation": generation_of(int(idx)), "loading": loading(int(idx))}
	session.lmp_locations = public


func arm_exit(player: int, at: Vector2, has_units: bool, clicked_exit := -1) -> void:
	if not owners.has(player):
		return
	owners[player].armed = -1
	if not has_units:
		return
	var n := session._exit_at(at)
	if n >= 0 and _exit_open(player, n) \
			and (GameData.option("auto_exit") == 1 or clicked_exit == n):
		owners[player].armed = n


func _exit_open(player: int, n: int) -> bool:
	var ex: Dictionary = session.world.zone.get("exits", {}).get(n, {})
	var to := String(ex.get("to", "none")).to_lower()
	if to == "none" or session.state.get_var(0, LmpMode.exit_var(to)) == 1.0:
		return false
	return player != 0 or to != String(session.lmp.base) or host_can_leave()


func _party_exit(player: int) -> int:
	var n := -1
	var any := false
	for u: GameUnit in session.world.units.values():
		if u.controller != player or u.dead or not u.has_meta("hero"):
			continue
		var current := session._exit_at(u.pos)
		if current < 0 or (any and n != current):
			return -1
		n = current
		any = true
	return n if any and _exit_open(player, n) else -1


func check_exits() -> void:
	var automatic := GameData.option("auto_exit") == 1
	var w := session.world
	for player: int in registered(session.zone_id):
		if loading(player):
			continue
		var o: Dictionary = owners[player]
		var n := _party_exit(player)
		if int(o.auto) == -2:
			o.auto = n   # entering inside an exit does not automatically leave
			if automatic:
				continue
		if n < 0:
			o.auto = -1
			continue
		if w.vm and not w.vm.briefings.active.is_empty():
			continue
		if String(w.zone.get("type", "")) == "brief":
			# Native villages use only the first party record, without a box.
			if (automatic and n == int(o.auto)) or (not automatic and int(o.armed) != n):
				continue
			o.auto = n
			o.armed = -1
			var ex: Dictionary = w.zone.exits[n]
			request(player, String(ex.to), int(ex.get("to_exit", 1)))
		elif int(o.armed) == n or (automatic and n != int(o.auto)):
			o.armed = -1
			o.auto = n
			session.broadcast({"t": "leave_box", "to": player, "exit": n})

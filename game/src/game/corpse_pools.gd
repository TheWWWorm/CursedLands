extends RefCounted
## A death's pool uses the previous completed world's noticed/corpse union.
## The renderer's visible flag and the player's relevant-object list are
## separate. The authority persists each observer's perception history and
## NPC investigation, as well as pool recipes shared with clients.

var world: GameWorld
var _members := {}                 # uid -> WeakRef, current world only
var _restore := {}                 # saved references, resolved after deployment
var _pools: Array[Dictionary] = []  # visual recipes, independent of corpse lifetime
var _next_pool := 1


func _init(w: GameWorld) -> void:
	world = w


func _valid(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and is_instance_valid(value) \
		and value is GameUnit and not value.is_queued_for_deletion() \
		and world.units.get(value.uid) == value


func _owner_here(player: int) -> bool:
	var s := world.session
	return s != null and s.players_include(player) \
		and (s.lmp_travel == null or s.lmp_travel.owner_world(player) == world)


func _history(u: GameUnit, key: String) -> Dictionary:
	var out := {}
	var values: Variant = u.get_meta(key, {})
	if values is Dictionary:
		for value: Variant in values.values():
			if _valid(value):
				out[value.get_instance_id()] = value
	return out


func _remember(value: Variant) -> void:
	if _valid(value):
		_members[value.uid] = weakref(value)


## Run after every object, water and delayed-spell update. A newly controlled
## unit created by a callback participates too; do not refresh this at send.
func refresh() -> void:
	if not world.authority:
		return
	_members.clear()
	var owners := {}
	for value: Variant in world.units.values():
		if typeof(value) == TYPE_OBJECT and is_instance_valid(value) and value is GameUnit \
				and value.controller >= 0 and _owner_here(value.controller) and _valid(value):
			owners.get_or_add(value.controller, []).append(value)
	for party: Array in owners.values():
		var corpses := {}
		for u: GameUnit in party:
			_remember(u)   # owned units remain members while dead or hidden
			for value: Variant in _history(u, "noticed").values():
				_remember(value)
			corpses.merge(_history(u, "seen_corpses"), true)
		for value: Variant in corpses.values():
			_remember(value)
		for u: GameUnit in party:
			# Corpse retention is shared within this owner's controlled units.
			if corpses.is_empty():
				u.remove_meta("seen_corpses")
			else:
				u.set_meta("seen_corpses", corpses.duplicate())
	if world.vm:
		var heroes: Variant = world.vm.globals.get("Heroes", [])
		if heroes is Array:
			for value: Variant in heroes:
				_remember(value)


func emit_pool(u: GameUnit) -> void:
	var s := world.session
	if not world.authority or s == null or not s.is_host or not _valid(u):
		return
	var member: Variant = _members.get(u.uid)
	if not (member is WeakRef) or member.get_ref() != u:
		return
	var recipient := false
	for p: Dictionary in s.players.values():
		if _owner_here(int(p.index)):
			recipient = true
			break
	if not recipient:
		return
	var event := {"t": "blood_pool", "uid": u.uid, "zone": String(world.zone.get("id", ""))}
	var mark := GroundMarks.pool_record(u)
	if not mark.is_empty():
		_prune_pools()
		event.mark = mark
		event.pool_id = _next_pool
		_pools.append({"id":_next_pool, "mark":mark.duplicate(), "time":world.time})
		_next_pool += 1
		while _pools.size() > GroundMarks.MAX_BLOOD: _pools.pop_front()
	# LMP's existing event wrapper already supplies the owner's generation.
	if s.lmp_travel == null:
		event.pool_epoch = s._load_serial
	s.broadcast(event)


func _aged_pool(row: Dictionary) -> Dictionary:
	var mark: Dictionary = row.mark.duplicate()
	mark.age = int(mark.age) + maxi(floori((world.time - float(row.time)) / GameUnit.TICK + 0.000001), 0)
	return mark


func _prune_pools() -> void:
	_pools = _pools.filter(func(row): return GroundMarks.valid_pool(_aged_pool(row)))


## Load and late join replay only living pools, at their saved growth/fade
## age. Geometry survives looting/removal of the original corpse.
func pool_events() -> Array:
	_prune_pools()
	var out := []
	for row in _pools:
		out.append({"t":"blood_pool", "zone":String(world.zone.get("id", "")),
			"pool_epoch":world.session._load_serial if world.session else 0,
			"pool_id":int(row.id), "mark":_aged_pool(row)})
	return out


func _ref(u: GameUnit) -> Array:
	var party := CampaignState.party_ref(u)
	# Co-op projection can remove an absent player's roster reference. A
	# zero fallback prevents that empty reference from naming a recycled uid.
	return [u.uid if party.is_empty() else 0, party]


static func _uid(value: Variant) -> int:
	if (value is int or value is float) and is_finite(float(value)) \
			and float(value) > 0.0 and float(value) <= 0xffffffff and float(value) == float(int(value)):
		return int(value)
	return -1


func _resolve(row: Variant) -> GameUnit:
	if not (row is Array) or row.size() != 2 or not (row[1] is Array):
		return null
	var party: Array = row[1]
	var value: Variant
	if not party.is_empty():
		# Party ids change on deployment. Never fall back to an old uid if
		# its roster reference no longer exists; that uid may name a map NPC.
		if party.size() == 2 and party[0] == "merc" and (party[1] is int or party[1] is String):
			value = CampaignState.party_unit(world, party)
		elif party.size() == 3 and party[0] == "hero" and party[1] is String \
				and (party[2] is int or party[2] is float) and is_finite(float(party[2])) \
				and float(party[2]) >= 0.0 and float(party[2]) <= 0x7fffffff \
				and float(party[2]) == float(int(party[2])):
			value = CampaignState.party_unit(world, party)
		else:
			return null
	else:
		if _uid(row[0]) < 0: return null
		value = world.units.get(_uid(row[0]))
	return value if _valid(value) else null


func _restore_history(rows: Variant) -> Dictionary:
	var out := {}
	if rows is Array:
		for row: Variant in rows:
			var u := _resolve(row)
			if u:
				out[u.get_instance_id()] = u
	return out


## Zone state is read before party deployment. Resolve its uid/roster
## references immediately before the first logic update, not during load.
func restore_state(value: Variant) -> void:
	_members.clear()
	_restore = value.duplicate(true) if value is Dictionary else {}
	_pools.clear()
	_next_pool = 1
	var pools: Variant = _restore.get("pools", [])
	if pools is Array:
		for row: Variant in pools.slice(-GroundMarks.MAX_BLOOD):
			if not row is Dictionary or _uid(row.get("id")) < 0 or not GroundMarks.valid_pool(row.get("mark")): continue
			_pools.append({"id":int(row.id), "mark":row.mark.duplicate(), "time":world.time})
			_next_pool = maxi(_next_pool, int(row.id) + 1)


func prepare_restore() -> void:
	if _restore.is_empty():
		return
	var saved := _restore
	_restore = {}
	var rows: Variant = saved.get("controllers")
	if rows is Array:
		for row: Variant in rows:
			if not (row is Dictionary) or not (row.get("noticed") is Array) or not (row.get("corpses") is Array):
				continue
			var u := _resolve(row.get("unit"))
			if not u or (u.controller >= 0 and not _owner_here(u.controller)):
				continue
			for pair: Array in [["noticed", row.noticed], ["seen_corpses", row.corpses]]:
				var history := _restore_history(pair[1])
				if history.is_empty():
					u.remove_meta(pair[0])
				else:
					u.set_meta(pair[0], history)
			u.remove_meta("perceived")
			if u.controller < 0 and not u.dead:
				_restore_investigation(u, row)
	var members: Variant = saved.get("members")
	if members is Array:
		for row: Variant in members:
			_remember(_resolve(row))


func save_state() -> Dictionary:
	prepare_restore()
	_prune_pools()
	# Keep the legacy key for compatibility; it now contains all observers.
	var saved := {"members": [], "controllers": [], "pools": []}
	for row in _pools:
		saved.pools.append({"id":int(row.id), "mark":_aged_pool(row)})
	for member: WeakRef in _members.values():
		var value: Variant = member.get_ref()
		if _valid(value):
			saved.members.append(_ref(value))
	for value: Variant in world.units.values():
		if not _valid(value) or (value.controller >= 0 and not _owner_here(value.controller)):
			continue
		var row := {"unit": _ref(value), "noticed": [], "corpses": []}
		for pair: Array in [["noticed", "noticed"], ["seen_corpses", "corpses"]]:
			for u: GameUnit in _history(value, pair[0]).values():
				row[pair[1]].append(_ref(u))
		if value.controller < 0 and not value.dead:
			_save_investigation(value, row)
		saved.controllers.append(row)
	return saved


## CorpseWatcher consumes a discovery once, but can defer it while another
## motivation wins. Save both the queue and the current investigation so a
## checkpoint neither rediscovers a finished body nor drops an unfinished one.
func _save_investigation(u: GameUnit, row: Dictionary) -> void:
	row.pending = []
	for ref: WeakRef in u.get_meta("pending_corpses", {}).values():
		var body: Variant = ref.get_ref()
		if _valid(body) and body.dead: row.pending.append(_ref(body))
	if not u.has_meta("suspect"): return
	var s: Dictionary = u.get_meta("suspect").duplicate(true)
	# World time starts afresh on load and on a zone revisit.
	s.t0 = world.time - float(s.t0)
	s.last = world.time - float(s.last)
	if s.has("corpse"):
		var body: Variant = _history(u, "seen_corpses").get(s.corpse)
		s.corpse = _ref(body) if _valid(body) else []
	row.suspicion = s
	var order := u.order
	if order.is_empty() and not u.orders.is_empty(): order = u.orders[0]
	if order.get("susp", false) and order.get("type") in ["move", "wait"]:
		row.investigation_order = order.duplicate(true)
	row.order_failed = u.order_failed


func _restore_investigation(u: GameUnit, row: Dictionary) -> void:
	u.remove_meta("pending_corpses")
	var pending := {}
	for body: GameUnit in _restore_history(row.get("pending", [])).values():
		if body.dead: pending[body.get_instance_id()] = weakref(body)
	if not pending.is_empty(): u.set_meta("pending_corpses", pending)
	u.remove_meta("suspect")
	var raw: Variant = row.get("suspicion")
	if not raw is Dictionary or not raw.get("pos") is Vector2 or not raw.get("look") is Array: return
	for key: String in ["t0", "last", "l0", "d", "m"]:
		if not (raw.get(key) is float or raw.get(key) is int) or not is_finite(float(raw[key])): return
	var s: Dictionary = raw.duplicate(true)
	s.t0 = world.time - float(s.t0)
	s.last = world.time - float(s.last)
	if s.has("corpse"):
		var body := _resolve(s.corpse)
		if body and body.dead: s.corpse = body.get_instance_id()
		else: s.erase("corpse")
	u.set_meta("suspect", s)
	if s.get("active", false): u.alert = true
	var order: Variant = row.get("investigation_order")
	if order is Dictionary and order.get("susp", false) and order.get("type") in ["move", "wait"]:
		u.command(order.duplicate(true))
	u.order_failed = bool(row.get("order_failed", false))
	world.active_set.wake_unit(u)

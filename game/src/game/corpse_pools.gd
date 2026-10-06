extends RefCounted
## A death's pool uses the previous completed world's noticed/corpse union.
## The renderer's visible flag and the player's relevant-object list are
## separate. Only the authority keeps this cache and sends the UID event.

var world: GameWorld
var _members := {}                 # uid -> WeakRef, current world only
var _restore := {}                 # saved references, resolved after deployment


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
	# LMP's existing event wrapper already supplies the owner's generation.
	if s.lmp_travel == null:
		event.pool_epoch = s._load_serial
	s.broadcast(event)


func _ref(u: GameUnit) -> Array:
	return [u.uid, CampaignState.party_ref(u)]


static func _uid(value: Variant) -> int:
	if (value is int or value is float) and is_finite(float(value)) \
			and float(value) > 0.0 and float(value) <= 0xffffffff and float(value) == float(int(value)):
		return int(value)
	return -1


func _resolve(row: Variant) -> GameUnit:
	if not (row is Array) or row.size() != 2 or _uid(row[0]) < 0 or not (row[1] is Array):
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
			if not u or not _owner_here(u.controller):
				continue
			for pair: Array in [["noticed", row.noticed], ["seen_corpses", row.corpses]]:
				var history := _restore_history(pair[1])
				if history.is_empty():
					u.remove_meta(pair[0])
				else:
					u.set_meta(pair[0], history)
			u.remove_meta("perceived")
	var members: Variant = saved.get("members")
	if members is Array:
		for row: Variant in members:
			_remember(_resolve(row))


func save_state() -> Dictionary:
	prepare_restore()
	var saved := {"members": [], "controllers": []}
	for member: WeakRef in _members.values():
		var value: Variant = member.get_ref()
		if _valid(value):
			saved.members.append(_ref(value))
	for value: Variant in world.units.values():
		if not _valid(value) or not _owner_here(value.controller):
			continue
		var row := {"unit": _ref(value), "noticed": [], "corpses": []}
		for pair: Array in [["noticed", "noticed"], ["seen_corpses", "corpses"]]:
			for u: GameUnit in _history(value, pair[0]).values():
				row[pair[1]].append(_ref(u))
		saved.controllers.append(row)
	return saved

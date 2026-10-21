extends RefCounted
## Remake side of cases_ext_dialogue.py: production Briefings.interact,
## Briefings.tick and ScriptVM.recalc_merc_briefings over a CampaignState whose
## GS variables are written through CampaignState.set_var in input order.

class RecordingSession extends Session:
	var events: Array = []
	var experience: Array = []
	var merc_events: Array = []
	func broadcast(event: Dictionary) -> void:
		events.append(event)
	# Experience distribution, party membership changes and network state
	# sync are boundaries: recorded, never performed.
	func give_experience(amount: float, _source := "quest", _player := 0) -> void:
		experience.append(amount)
	func merc_changed(n: int, hired: bool, _player := -1, _leave_npc := true, _script_removal := false) -> void:
		merc_events.append([n, "hire" if hired else "remove"])
	func sync_state() -> void:
		pass

class RecordingVM extends ScriptVM:
	var fired: Array = []
	func fire_event(name: String, args: Array) -> void:
		fired.append([name, args.duplicate()])

class RecordingBriefings extends Briefings:
	var started: Array = []
	func play_named(id: String, var_name: String, player := 0, partner: GameUnit = null, instant := false, approached := false) -> void:
		started.append([id, var_name, player, partner, instant, approached])

func kinds() -> Array:
	return ["dialogue_topics", "dialogue_zone", "dialogue_merc", "dialogue_complete"]

func capture(kind: String, data: Dictionary, trace: Node) -> Array:
	var session := RecordingSession.new()
	session.coop = CoopProgress.new()
	session.coop.session = session
	session.add_child(session.coop)
	session.state = CampaignState.new()
	session.state.day = 1
	session.online = bool(data.get("multiplayer", false))
	var world := GameWorld.new()
	world.zone = {"id": String(data.get("zone", "parity")).to_lower(), "type": "game"}
	world.session = session
	var vm := RecordingVM.new()
	vm.world = world
	vm.session = session
	vm.ast = ScriptParser.new()
	for row: Array in data.variables:
		session.state.set_var(0, String(row[0]), trace.f32(float(row[1])))
	var states: Array
	match kind:
		"dialogue_topics": states = _topics(data, vm, session, world, trace)
		"dialogue_zone": states = _zone(vm)
		"dialogue_merc": states = _merc(data, vm, session, trace)
		"dialogue_complete": states = _complete(data, vm, session, trace)
	vm.world = null
	session.free()
	world.free()
	return states

func _topics(data: Dictionary, vm: ScriptVM, session: RecordingSession, world: GameWorld, _trace: Node) -> Array:
	# texts.res is a supplied boundary: every briefing text the list can ask
	# for is either the supplied entry or absent.
	var texts: Dictionary = data.get("texts", {})
	var keys := {"briefing constr": true}
	for row: Array in data.variables:
		keys["briefing " + String(row[0]).get_slice(".", String(row[0]).get_slice_count(".") - 1).to_lower()] = true
	for key: String in texts: keys[key] = true
	var saved := {}
	for key: String in keys:
		if GameData._text_cache.has(key): saved[key] = GameData._text_cache[key]
		GameData._text_cache[key] = String(texts.get(key, "")).replace("\r", "")
	var npc_row: Dictionary = data.npc
	var npc := GameUnit.new()
	npc.world = world
	npc.uid = ScriptVM.name_id(String(npc_row.get("id_name", npc_row.name)))
	npc.info = {"name": String(npc_row.name)}
	var hero := GameUnit.new()
	hero.world = world
	hero.uid = 1
	var briefings := Briefings.new(vm)
	briefings.interact(hero, npc, 0)
	var topics := []
	var titles := []
	var opened := false
	for event: Dictionary in session.events:
		if String(event.get("t", "")) != "topics": continue
		opened = true
		for option: Dictionary in event.options:
			var full := String(option["var"])
			topics.append(full.get_slice(".", full.get_slice_count(".") - 1))
			titles.append(String(option.title))
	for key: String in keys:
		if saved.has(key): GameData._text_cache[key] = saved[key]
		else: GameData._text_cache.erase(key)
	npc.free()
	hero.free()
	return [{"open": opened, "topics": topics, "titles": titles}]

func _zone(vm: ScriptVM) -> Array:
	var briefings := RecordingBriefings.new(vm)
	briefings.tick()
	if briefings.started.is_empty():
		return [{"started": false, "briefing": ""}]
	return [{"started": true, "briefing": String(briefings.started[0][0])}]

func _hire_party(data: Dictionary, st: CampaignState) -> void:
	for member: Dictionary in data.party:
		var name := String(member.name).to_lower()
		if not (name.begins_with("merc") and name.substr(4).is_valid_int()): continue
		var n := name.substr(4).to_int()
		st.mercs[n] = {"prototype": name, "name": name, "controller": 0, "party": st.current_party,
			"dead": bool(member.get("dead", false))}

func _variables(st: CampaignState, trace: Node, merc_only: bool, skip := "") -> Dictionary:
	var names := []
	for key: String in st.vars:
		if not key.begins_with("0:"): continue
		var name := key.substr(2)
		if name == skip or float(st.vars[key]) == 0.0: continue
		if merc_only and not (name.begins_with("b.merc") or name.begins_with("amerc_")): continue
		names.append(name)
	names.sort()
	var values := {}
	for name: String in names:
		values[name] = trace.f32(float(st.vars["0:" + name]))
	return values

func _merc(data: Dictionary, vm: ScriptVM, session: RecordingSession, trace: Node) -> Array:
	_hire_party(data, session.state)
	vm.recalc_merc_briefings()
	return [{"variables": _variables(session.state, trace, true)}]

func _complete(data: Dictionary, vm: RecordingVM, session: RecordingSession, trace: Node) -> Array:
	var st := session.state
	st.money = int(data.get("money", 0))
	_hire_party(data, st)
	var key := String(data.key)
	var id := key.get_slice(".", key.get_slice_count(".") - 1).to_lower()
	# database.res briefings row is a supplied boundary (absent when null).
	var index: Dictionary = GameData.db.tables.get_or_add("briefings#index", {})
	var had := index.has(id)
	var saved = index.get(id)
	index.erase(id)
	var record = data.get("record")
	if record != null:
		var row := {"name": id, "unknown": trace.f32(float(record.get("experience", 0.0))),
			"money": trace.f32(float(record.get("money", 0.0)))}
		for field in ["give_quests", "give_quests2", "open_zones", "unknown2"]:
			row[field] = Array(record.get(field, []))
		index[id] = row
	var briefings := Briefings.new(vm)
	briefings.active = key
	briefings.active_player = 0
	briefings.complete(0, key)
	if had: index[id] = saved
	else: index.erase(id)
	var completion := []
	for row: Array in vm.fired:
		if row[0] == "#OnBriefingComplete":
			completion = [0, key, trace.f32(st.get_pvar(0, key)), int(row[1][0]), String(row[1][1])]
	return [{"completion": completion, "money": st.money, "experience": session.experience,
		"merc_events": session.merc_events, "variables": _variables(st, trace, false, key)}]

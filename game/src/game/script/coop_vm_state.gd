extends RefCounted
## A copied co-op checkpoint becomes one player's solo campaign. Project only
## serialized VM state; never change the authority's live actors or threads.
const KEY := "coop_return"
const P := preload("res://src/game/script/script_parser.gd")

static func mark_zones(zones: Dictionary, player: int) -> Dictionary:
	var out: Dictionary = zones.duplicate()
	if player <= 0: return out
	for name in out:
		var zone: Variant = out[name]
		if zone is Dictionary and zone.get("vm") is Dictionary and not zone.vm.is_empty():
			out[name] = zone.duplicate()
			out[name].vm = zone.vm.duplicate()
			out[name].vm[KEY] = {"version":1,"player":player}
	return out


static func _hero(value: Variant) -> Array:
	if value is Dictionary and value.has("u") and value.get("h") is Array \
			and value.h.size() == 2 and value.h.all(func(n):return (n is int or n is float) and n >= 0 and n == int(n)):
		return value.h
	return []


static func _ref(value: Dictionary, index: int) -> Dictionary:
	var out := value.duplicate(true)
	out.h = [0,index]
	return out


## Shared narrative values still name the original protagonist (player 0).
## Other absent peers never resolve through their old recyclable unit IDs.
static func _value(value: Variant, player: int) -> Variant:
	var hero := _hero(value)
	if not hero.is_empty():
		return _ref(value,int(hero[1])) if int(hero[0]) in [0,player] else null
	if value is Array:
		var out := []
		for i in _indices(value,player,false): out.append(_value(value[i],player))
		return out
	return value


## Keep deliberate duplicates from one owner, but never collapse two players
## into two occurrences of the same solo character. Native NPC refs are intact.
static func _indices(items: Array, player: int, participants: bool, story: Array = []) -> Array:
	var preferred := {}
	for value in items:
		var h := _hero(value)
		if h.is_empty(): continue
		var owner := int(h[0]); var index := int(h[1])
		if owner == player: preferred[index] = player
		elif owner == 0 and (not participants or index in story) and not preferred.has(index): preferred[index] = 0
	var out := []
	for i in items.size():
		var h := _hero(items[i])
		if h.is_empty() or int(h[0]) == int(preferred.get(int(h[1]),-1)): out.append(i)
	return out


static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value:
			if key != "u" or _hero(value).is_empty(): out[key] = _canonical(value[key])
		return out
	if value is Array: return value.map(_canonical)
	return value


## Named party records belong to the shared authored story. Their identity
## survives return through PartyProgress; optional player heroes do not.
static func _story_roles(vm: ScriptVM) -> Array:
	var out := []
	if vm.session == null or vm.session.state == null: return out
	var state := vm.session.state
	if state.current_party.is_empty(): return out
	var party := preload("res://src/game/coop_party_progress.gd")
	var roster: Array = state.heroes.get(0,[])
	for index in roster.size():
		var record: Dictionary = roster[index]
		if not String(record.get("unit_name","")).is_empty() and not party.protagonist(state.current_party,index,record): out.append(index)
	return out


static func _body(vm: ScriptVM, row: Dictionary) -> Array:
	if row.get("s") == "WorldScript": return vm.world_bodies.get(String(row.get("src","")),[])
	var blocks: Array = vm.ast.scripts.get(row.get("s",""),{}).get("blocks",[])
	var index := int(row.get("b",-1))
	return blocks[index].body if index >= 0 and index < blocks.size() else []


## A saved For cursor denotes the current item, not the number of future
## iterations. If it belongs to another participant, discard only that body
## and its waits, then start the next retained item (or continue after For).
static func _frames(vm: ScriptVM, row: Dictionary, globals: Dictionary, player: int) -> void:
	if not row.get("f") is Array: return   # older b/i-only VM shape
	var body := _body(vm,row)
	var frames: Array = row.f
	for depth in frames.size():
		var frame: Dictionary = frames[depth]
		if depth == 0: continue
		var parent: Dictionary = frames[depth-1]
		var at := int(parent.get("i",0))-1
		if at < 0 or at >= body.size() or body[at][0] != P.S_FOR: return
		var statement: Array = body[at]
		body = statement[3]
		if not frame.get("it") is Array: continue
		var items: Array = frame.it
		var indices := _indices(items,player,vm._refs(statement[2],"Heroes"),_story_roles(vm))
		var old := int(frame.get("k",0))
		var retained := indices.find(old)
		if retained < 0:
			retained = 0
			while retained < indices.size() and int(indices[retained]) < old: retained += 1
			row.w = 0.0; row.p = 0.0; row.erase("wc"); row.erase("wu")
			row.f = frames.slice(0,depth+1) if retained < indices.size() else frames.slice(0,depth)
			if retained >= indices.size(): return
			frame.i = 0
		frame.it = indices.map(func(i):return _value(items[i],player))
		frame.k = retained
		var name := String(frame.get("v",""))
		if not name.is_empty() and retained < frame.it.size():
			if row.l.has(name): row.l[name] = frame.it[retained]
			else: globals[name] = frame.it[retained]
		if not indices.has(old): return   # nested frames belonged to the discarded actor


## Extra-participant traps reuse an inspected native role's unchanged body.
## On solo return the recipient becomes a native story role. Match the whole
## called family against that role, so saved instruction indexes remain valid
## and its original idle copy cannot execute the same action a second time.
static func _family_equal(a: Variant, b: Variant, names: Array, mapping: Dictionary) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		if a.size() == 3 and a[0] == P.S_CALL and a[1] in names:
			if b[0] != P.S_CALL or not b[1] is String: return false
			if mapping.has(a[1]) and mapping[a[1]] != b[1]: return false
			mapping[a[1]] = b[1]
			return _family_equal(a[2],b[2],names,mapping)
		for i in a.size():
			if not _family_equal(a[i],b[i],names,mapping): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _family_equal(a[key],b[key],names,mapping): return false
		return true
	return a == b


static func _family_map(vm: ScriptVM, definition: Dictionary, role: int) -> Dictionary:
	var effects := preload("res://src/game/script/story_coop_effects.gd")
	var names: Array = definition.family
	var root: String = definition.trap.root
	var results := []
	for candidate: String in vm.ast.scripts:
		if candidate.contains("#RemakeParticipant"): continue
		var mapping := {root:candidate}
		var checked := {}
		var valid := true
		while valid and checked.size() < mapping.size():
			for name: String in mapping.keys():
				if checked.has(name): continue
				checked[name] = true
				var source: Dictionary = vm.ast.scripts.get(name,{})
				var target: Dictionary = vm.ast.scripts.get(mapping[name],{})
				if source.is_empty() or target.is_empty() or source.params != target.params:
					valid = false; break
				var blocks: Array = source.blocks.duplicate(true)
				for block: Dictionary in blocks:
					block.conds = effects.replace(block.conds,effects.role(int(definition.trap.slot)),effects.role(role))
					block.body = effects.replace(block.body,effects.role(int(definition.trap.slot)),effects.role(role))
				if not _family_equal(blocks,target.blocks,names,mapping): valid = false; break
		var unique := {}
		for value in mapping.values(): unique[value] = true
		if valid and mapping.size() == names.size() and mapping.size() == unique.size(): results.append(mapping)
	return results[0] if results.size() == 1 else {}


static func _participant_rows(vm: ScriptVM, rows: Array, player: int) -> Array:
	var traps := preload("res://src/game/script/story_coop_traps.gd")
	var translated := {}
	var replaced := {}
	var watchers := {}
	for watcher: String in vm.ast.scripts:
		var definition: Dictionary = vm.ast.scripts[watcher]
		if not definition.has("trap"): continue
		var roles := {}
		for row: Dictionary in rows:
			var keys := []
			if row.get("s") == watcher:
				# A seen character with no remaining child has already spent
				# this activation. It must not inherit the host's idle copy.
				keys = row.get("l",{}).get(traps.SEEN,[])
			elif String(row.get("s","")).trim_suffix(traps.COPY) in definition.family:
				keys = [row.get("l",{}).get(traps.KEY,"")]
			for key in keys:
				var parts := String(key).split(":")
				if parts.size()==3 and parts[0]=="h" and int(parts[1])==player: roles[int(parts[2])] = true
		for role: int in roles:
			var mapping := _family_map(vm,definition,role)
			if mapping.is_empty(): continue   # changed/modded families are never guessed
			translated["h:%d:%d" % [player,role]] = Dictionary(translated.get("h:%d:%d" % [player,role],{})).merged(mapping)
			for name: String in mapping.values(): replaced[name] = true
			watchers[watcher] = true
	var out := []
	for original: Dictionary in rows:
		var name := String(original.get("s",""))
		if replaced.has(name) or watchers.has(name): continue
		var key := String(original.get("l",{}).get(traps.KEY,""))
		if name.ends_with(traps.COPY) and key.begins_with("h:"):
			var parts := key.split(":")
			if parts.size()==3 and int(parts[1])!=player: continue
			var base := name.trim_suffix(traps.COPY)
			if translated.get(key,{}).has(base):
				var row := original.duplicate(true)
				row.s = translated[key][base]; row.l.erase(traps.KEY)
				out.append(row); continue
		out.append(original)
	return out


static func _actor_calls(body: Array, param: String, scripts: Dictionary) -> Array:
	var out := []
	for statement: Array in body:
		if statement[0] == P.S_FOR: out.append_array(_actor_calls(statement[3],param,scripts))
		elif statement[0] == P.S_CALL and scripts.has(statement[1]) \
				and not statement[2].is_empty() and statement[2][0] == [P.N_VAR,param] \
				and not scripts[statement[1]].params.is_empty():
			out.append(statement[1])
	return out


## Native per-character chains pass their first actor parameter unchanged.
## Prefer the recipient's whole chain over a temporary story-role alias,
## including when one copy is idle and the other is already sleeping.
static func _actor_families(vm: ScriptVM) -> Dictionary:
	var graph := {}
	for name: String in vm.ast.scripts:
		var definition: Dictionary = vm.ast.scripts[name]
		if definition.params.is_empty(): continue
		for block: Dictionary in definition.blocks:
			for child: String in _actor_calls(block.body,String(definition.params[0]),vm.ast.scripts):
				graph.get_or_add(name,[]).append(child)
				graph.get_or_add(child,[]).append(name)
	var families := {}
	for name: String in vm.ast.scripts:
		if families.has(name): continue
		var pending := [name]
		while not pending.is_empty():
			var current: String = pending.pop_back()
			if families.has(current): continue
			families[current] = name
			pending.append_array(graph.get(current,[]))
	return families


static func restore(vm: ScriptVM, saved: Dictionary) -> Dictionary:
	var marker: Variant = saved.get(KEY)
	if not marker is Dictionary or marker.get("version") != 1 \
			or not marker.get("player") is int or int(marker.player) <= 0: return saved
	var player := int(marker.player)
	var out := saved.duplicate(true)
	out.erase(KEY)
	var globals: Dictionary = out.get("globals",{})
	for name in globals: globals[name] = _value(globals[name],player)
	var candidates := []
	var rows := _participant_rows(vm,saved.get("instances",[]),player)
	var families := _actor_families(vm)
	var own_chains := {}
	for row: Dictionary in rows:
		var params: Array = vm.ast.scripts.get(row.get("s",""),{}).get("params",[])
		var hero := _hero(row.get("l",{}).get(String(params[0]) if not params.is_empty() else ""))
		if not hero.is_empty() and int(hero[0]) == player:
			own_chains["%s:%d" % [families.get(row.s,row.s),int(hero[1])]] = true
	var story := _story_roles(vm)
	var preferred := {}
	for original: Dictionary in rows:
		var row := original.duplicate(true)
		var params: Array = vm.ast.scripts.get(row.get("s",""),{}).get("params",[])
		var param := String(params[0]) if not params.is_empty() else ""
		var hero := _hero(row.get("l",{}).get(param))
		var owner := int(hero[0]) if not hero.is_empty() else -1
		var shared := owner >= 0 and vm._world_event(String(row.s))
		if owner >= 0 and owner != player and not shared:
			if owner != 0 or int(hero[1]) not in story: continue
			if own_chains.has("%s:%d" % [families.get(row.s,row.s),int(hero[1])]): continue
		for name in row.get("l",{}): row.l[name] = _value(row.l[name],player)
		if shared: row.l[param] = _ref(original.l[param],int(hero[1]))
		if row.has("wu"): row.wu = _value(row.wu,player)
		_frames(vm,row,globals,player)
		var identity := ""
		if shared:
			var canonical := row.duplicate(true)
			canonical.erase("p")   # polling phase does not make another actor
			identity = var_to_bytes(_canonical(canonical)).hex_encode()
			if owner == player or not preferred.has(identity): preferred[identity] = owner
		candidates.append({"row":row,"owner":owner,"shared":shared,"identity":identity})
	out.instances = []
	for candidate in candidates:
		if not candidate.shared or candidate.owner == preferred[candidate.identity]: out.instances.append(candidate.row)
	# Original story orders are the fallback only when this character has no
	# personal pending order for the same roster role.
	var orders: Array = out.get("story_orders",[])
	var own := {}
	for row in orders:
		var hero := _hero(row.get("actor"))
		if not hero.is_empty() and int(hero[0]) == player: own[int(hero[1])] = true
	out.story_orders = []
	for row in orders:
		var hero := _hero(row.get("actor"))
		if not hero.is_empty() and (int(hero[0]) not in [0,player] or (int(hero[0]) == 0 and own.has(int(hero[1])))): continue
		row.actor = _value(row.get("actor"),player)
		out.story_orders.append(row)
	for row in out.get("script_ai",[]):
		row.actor = _value(row.get("actor"),player)
		for name in row.get("data",{}): row.data[name] = _value(row.data[name],player)
	if out.has("briefing_queue"): out.briefing_queue = _value(out.briefing_queue,player)
	for name in out.get("world_done",{}): out.world_done[name] = 0
	return out

extends Node
## Original QFinish output versus the remake's compact objective evaluator.
## Real parser/scheduler/quest accounting; controlled actors, sight and inputs.
## Native generation is captured separately, not a full original-game replay.
class QuietSession extends Session:
	var restocks := 0
	func broadcast(_event: Dictionary) -> void: pass
	func sync_state() -> void: pass
	func restock_shops() -> void: restocks += 1

class ControlledVM extends ScriptVM:
	var party: Array = []
	var visible_units: Array = []
	func _call(name: String, args: Array, inst: Instance):
		# Native compiler accepts this lowercase builtin in its generated
		# text; the archive-facing remake evaluator spells it Any.
		return super._call('Any' if name == 'any' else name,args,inst)
	func heroes() -> Array: return party
	func _refresh_heroes() -> void: globals.Heroes = party.duplicate()
	func _player_visible(_corpses := false) -> Array: return visible_units.duplicate()

var checks := 0
var failures: Array = []
var observations: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)

func command_source(row: Dictionary) -> String:
	var source := 'WorldScript(QStart("%s")\n' % row.id
	for o: Array in row.objectives:
		source += '%s(%s%s)\n' % [o[0],JSON.stringify(o[1]),',%s' % o[2] if o[0] == 'QObjUse' else '']
	return source + 'QFinish())'

func fixture(row: Dictionary, reference: bool) -> ControlledVM:
	var s := QuietSession.new(); add_child(s); s.set_physics_process(false)
	s.state = CampaignState.new(); s.state.side_quests[row.id] = 'active'
	s.state.set_var(0,'q.%s.%s' % [row.id,row.id],1)
	if not row.objectives.is_empty(): s.state.set_var(0,'q.%s.%s.1' % [row.id,row.id],1)
	var w := GameWorld.new(); w.session = s; w.presentation = false; s.world = w
	w.ai = UnitAI.new(w); add_child(w)
	var vm := ControlledVM.new(); vm.world = w; vm.session = s; w.vm = vm
	vm.ast = ScriptParser.parse(row.source if reference else command_source(row))
	check(vm.ast.errors.is_empty(),row.id + ': captured/generated source parses')
	vm.briefings = Briefings.new(vm); vm.time_fixed = true
	var h := GameUnit.new(); h.uid = 999; h.controller = 0; h.world = w; h.pos = Vector2(1000,1000)
	w.set_unit(h.uid,h); w.add_child(h); vm.party = [h]
	for o: Array in row.objectives:
		var arg := str(o[1])
		if o[0] == 'QObjArea': vm.areas[int(o[1])] = [PackedFloat32Array([0,0,1,1])]
		elif o[0] == 'QObjKillGroup':
			if vm.globals.has(arg): continue
			var member := GameUnit.new(); member.uid = 2000000 + w.units.size(); member.world = w
			w.set_unit(member.uid,member); w.add_child(member); vm.globals[arg] = [member]
		elif arg.begins_with('GetObject('):
			var id := arg.get_slice('(',1).get_slice(')',0).to_int()
			if w.units.has(id): continue
			var u := GameUnit.new(); u.uid = id; u.world = w; u.pos = Vector2.ZERO
			w.set_unit(id,u); w.add_child(u); w.levers[id] = {'state':0}
	vm.world_bodies[''] = vm.ast.world; vm._start_world(vm.ast.world)
	return vm

func satisfy(vm: ControlledVM, objective: Array, yes: bool) -> void:
	var target = vm._objective_target(str(objective[1]))
	match objective[0]:
		'QObjArea': vm.party[0].pos = Vector2.ZERO if yes else Vector2(1000,1000)
		'QObjSeeObject': vm.party[0].pos = target.pos if yes else Vector2(1000,1000)
		'QObjSeeUnit': vm.visible_units = [target] if yes else []
		'QObjKillUnit': target.dead = yes
		'QObjKillGroup':
			for u: GameUnit in vm.globals[objective[1]]: u.dead = yes
		'QObjUse': vm.world.levers[target.uid].state = int(objective[2]) if yes else 0
		'QObjGetItem':
			var key := vm._quest_item_name(objective[1])
			if yes: vm.session.state.quest_items[key] = true
			else: vm.session.state.quest_items.erase(key)

func state(vm: ControlledVM) -> Dictionary:
	return {'vars':vm.session.state.vars.duplicate(true),'side':vm.session.state.side_quests.duplicate(true),
		'quests':vm.session.state.quests.duplicate(true),'restocks':vm.session.restocks}

func reloaded(vm: ControlledVM) -> ControlledVM:
	var saved: Dictionary = bytes_to_var(var_to_bytes(vm.save_state()))
	var fresh := ControlledVM.new(); fresh.world = vm.world; fresh.session = vm.session
	fresh.ast = vm.ast; fresh.world_bodies = vm.world_bodies
	fresh.briefings = Briefings.new(fresh); fresh.party = vm.party; fresh.visible_units = vm.visible_units
	fresh.time = vm.time; fresh._restore(saved); fresh.world.vm = fresh
	vm.briefings = null; vm.instances.clear(); vm.globals.clear()
	return fresh

func release(vm: ControlledVM) -> void:
	vm.instances.clear(); vm.globals.clear(); vm.party.clear(); vm.visible_units.clear()
	vm.world.vm = null; vm.session.world = null; vm.world.free(); vm.session.free()
	vm.briefings = null

func run_chain(row: Dictionary, reload: bool) -> void:
	var expected := fixture(row,true)
	var actual := fixture(row,false)
	var trace := []
	for tick in row.objectives.size() + 6:
		if tick >= 3 and tick < 3 + row.objectives.size():
			for vm: ControlledVM in [expected,actual]: satisfy(vm,row.objectives[tick-3],true)
		for vm: ControlledVM in [expected,actual]: vm.tick(ScriptVM.POLL)
		var same := state(actual) == state(expected)
		check(same,'%s %s tick %d: exact objective/journal/completion/restock parity' % [row.id,'reload' if reload else 'continuous',tick])
		trace.append({'tick':tick,'same':same,'expected':state(expected),'actual':state(actual)})
		if reload:
			expected = reloaded(expected); actual = reloaded(actual)
	observations.append({'id':row.id,'reload':reload,'trace':trace})
	release(expected); release(actual)

func pulse(kind: String) -> void:
	# A fleeting sight/area contact lasting one native 55 ms tick must latch.
	var source_row: Dictionary = reference_rows.filter(func(r):return r.id == ('z6q1' if kind == 'QObjSeeUnit' else 'z13q1'))[0]
	var row := source_row.duplicate(true)
	var expected := fixture(row,true); var actual := fixture(row,false)
	for i in 3:
		for vm: ControlledVM in [expected,actual]: vm.tick(ScriptVM.POLL)
	if kind == 'QObjSeeUnit':
		for vm: ControlledVM in [expected,actual]: satisfy(vm,row.objectives[0],true)
		for i in 12:
			for vm: ControlledVM in [expected,actual]: vm.tick(ScriptVM.POLL)
	var index := 1 if kind == 'QObjSeeUnit' else 0
	for vm: ControlledVM in [expected,actual]: satisfy(vm,row.objectives[index],true); vm.tick(ScriptVM.POLL)
	for vm: ControlledVM in [expected,actual]: satisfy(vm,row.objectives[index],false)
	for i in 12:
		for vm: ControlledVM in [expected,actual]: vm.tick(ScriptVM.POLL)
	check(state(actual) == state(expected),'one-tick %s contact is retained after leaving/hiding' % kind)
	release(expected); release(actual)

var reference_rows: Array
func _ready() -> void:
	GameData.options.merge({'show_tutorial':0,'smile_faces':0},true)
	var path: String = get_script().resource_path.get_base_dir().path_join('fixtures/original_quest_objectives.json')
	reference_rows = JSON.parse_string(FileAccess.get_file_as_string(path)).rows
	for row: Dictionary in reference_rows:
		# Also exercise the empty and sixteen-objective native boundaries.
		run_chain(row,false); run_chain(row,true)
	pulse('QObjArea'); pulse('QObjSeeUnit')
	var report := {'checks':checks,'failures':failures,'observations':observations,
		'scope':'Native-generated chain source, executed by production parser/scheduler with controlled world conditions. Not a full original-game run.'}
	FileAccess.open('user://quest-objective-chains.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('QUEST_OBJECTIVE_CHAINS ',checks,' checks ',failures.size(),' failures')
	get_tree().quit(0 if failures.is_empty() else 1)

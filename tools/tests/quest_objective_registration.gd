extends "quest_objective_chains.gd"
## QStart/QFinish are separate commands. A mod may yield between them;
## loading then must not compile/complete a chain that is still being built.
func registration(empty: bool) -> void:
	var row := {'id':'pending','objectives':[] if empty else [['QObjUse','GetObject(100)',1]]}
	var vm := fixture(row,false)
	var source := 'WorldScript(QStart("pending") Sleep(3) '
	if not empty: source += 'QObjUse("GetObject(100)",1) '
	source += 'QFinish())'
	vm.instances.clear(); vm.ast = ScriptParser.parse(source)
	vm.world_bodies[''] = vm.ast.world; vm._start_world(vm.ast.world)
	vm.tick(ScriptVM.POLL)
	check(vm._q_recording == 'pending','registration pauses inside QStart/QFinish')
	vm = reloaded(vm)
	for i in 2:
		vm.tick(ScriptVM.POLL)
		check(vm.session.state.get_var(0,'q.pending.pending') == 1,'saved unfinished %s chain stays pending at wait tick %d' % ['empty' if empty else 'lever',i])
	vm.tick(ScriptVM.POLL)
	check(vm._q_recording.is_empty() and vm.qobjs.pending.objs.size() == (0 if empty else 1),'resumed registration retains the intended objective list')
	if not empty: satisfy(vm,row.objectives[0],true)
	for i in 2: vm.tick(ScriptVM.POLL)
	check(vm.session.state.get_var(0,'q.pending.pending') == 2 and vm.session.restocks == 1,'finished registration completes once through the normal path')
	release(vm)

func _ready() -> void:
	GameData.options.merge({'show_tutorial':0,'smile_faces':0},true)
	registration(false); registration(true)
	var vm := fixture({'id':'legacy','objectives':[]},false)
	vm.instances.clear()
	vm._restore({'qobjs':{'legacy':{'objs':[],'items':0}}})
	vm.tick(ScriptVM.POLL)
	check(vm.session.state.get_var(0,'q.legacy.legacy') == 1,'ambiguous old empty registry does not invent a completed quest')
	release(vm)
	print('QUEST_OBJECTIVE_REGISTRATION ',checks,' checks ',failures.size(),' failures')
	get_tree().quit(0 if failures.is_empty() else 1)

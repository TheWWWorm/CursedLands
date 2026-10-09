extends "./story_coop_traps_net.gd"
## Actual original startup and ENet arrival; prepared coordinates and explicit
## native ticks isolate shared route stages without claiming a full playthrough.
const PORT := 29955
const SAFE := Vector2(100,100)
const ROOTS := ["VTriger#0#13","VTriger#0#296","VTriger#0#333"]
const ROWS := [
	["VCheck#0#17",Vector2(405,430),{"q.gz19h.q71h":2,"q.gz19h.q71h.1":2}],
	["VCheck#0#295",Vector2(101,250),{"q.gz19h.q72h.2":2,"q.gz19h.q72h.3":1}],
	["VCheck#0#300",Vector2(240,46),{"q.gz19h.q72h.3":2,"q.gz19h.q72h.20":1,"q.gz19h.q72h.34":2}],
	["VCheck#0#338","MC3",{"q.gz19h.q72h.10":2,"q.gz19h.q72h.11":1,"q.gz19h.q72h.8":1}],
	["VCheck#0#344",Vector2(450,105),{"q.gz19h.q72h.22":2}],
	["VCheck#0#348",Vector2(410,170),{"q.gz19h.q72h.16":2}],
	["VCheck#0#355","TCP-B",{"q.gz19h.q72h.23":2,"q.gz19h.q72h.24":1}],
	["VCheck#0#357","TCP-A",{"q.gz19h.q72h.25":2,"q.gz19h.q72h.26":1}],
	["VCheck#0#364","MC1",{"q.gz19h.q72h.6":2,"q.gz19h.q72h.7":1,"q.gz19h.q72h.4":1}],
]
var arrival := "late"
var evidence := {"phases":[]}

func loaded() -> bool:
	return client != null and client.world != null and client.zone_id == "gz19h" \
		and client.my_index == 1 and not client._remote_loading and not client._zone_holding \
		and not client.loading_game and client._pool_epoch == host._load_serial

func connect_guest() -> bool:
	client = branch(true)
	GameData.player_name = "Progression Guest"
	check(client.join("127.0.0.1",PORT) == OK,"actual ENet guest connects")
	var ready := await until(func():return client.my_index == 1 and host.players.size() == 2)
	check(ready,"normal hello registers a separate guest")
	if ready:
		ready = await until(loaded)
		check(ready,"guest receives the actual original prison")
		if ready: freeze(client)
	return ready

func place_safe() -> void:
	for u: GameUnit in host.world.party_units():
		u.pos = SAFE+Vector2(0,3*u.controller)
		u.resync_drawn()

func satisfies(name: String, actor: GameUnit) -> bool:
	var probe := ScriptVM.Instance.new()
	probe.locals.this = actor
	return host.world.vm._all(host.world.vm.ast.scripts[name].blocks[0].conds,probe)

func capture(label: String) -> void:
	var vm := host.world.vm
	var waits := []
	var names := ROWS.map(func(row):return row[0])
	for inst: ScriptVM.Instance in vm.instances:
		if inst.sname not in names or inst.killed: continue
		var actor = inst.locals.get("this")
		waits.append({"script":inst.sname,"uid":actor.uid if is_instance_valid(actor) else -1,
			"controller":actor.controller if is_instance_valid(actor) else -1})
	var values := {}
	for row: Array in ROWS:
		for key: String in row[2]: values[key] = host.state.get_var(0,key)
	evidence.phases.append({"label":label,"time":vm.time,"waits":waits,"values":values,
		"world_done":vm._world_done.duplicate(),"heroes":vm.globals.get("Heroes",[]).map(func(u):return u.uid)})

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--progression-arrival="): arrival = arg.get_slice("=",1)
	check(arrival in ["early","late"],"arrival case is explicit")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"net_websocket":0,"auto_graphics":0,"control_mode":1,
		"confine_mouse":0,"scroll_border":0},true)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	CoopProgress.bring_slot = ""
	host = branch(false)
	host.state = CoopProgress.fresh_state()
	host.state.heroes[0][0].name = "Progression Host"
	host.set_physics_process(false)
	GameData.player_name = "Progression Host"
	check(host.host(PORT,2) == OK,"actual ENet host opens")
	await host.enter_zone("gz19h",1,false)
	freeze(host)
	if arrival == "early" and not await connect_guest(): await done(); return
	place_safe()
	var vm := host.world.vm
	var original := ScriptParser.parse(host.world.mob.script_text)
	evidence.original_script_sha256 = host.world.mob.script_text.sha256_text()
	check(vm.ast.errors.is_empty() and original.errors.is_empty(),"mounted original map source parses")
	check(vm.instances.any(func(inst):return inst.sname == "WorldScript"),"unmodified original startup remains pending")
	check(vm.ast.world == original.world,"startup body and instruction positions are unchanged")
	for name: String in ROOTS:
		check(original.world.count([ScriptParser.S_CALL,name,[[ScriptParser.N_VAR,"NULL"]]]) == 1,
			name+": native startup calls the original registration once")
	for row: Array in ROWS:
		var name: String = row[0]
		check(vm.ast.scripts[name].params == original.scripts[name].params \
			and vm.ast.scripts[name].blocks == original.scripts[name].blocks,
			name+": original predicate and body are unchanged")
	ticks(16)
	check(not vm.instances.any(func(inst):return inst.sname == "WorldScript" or inst.sname in ROOTS),
		"original startup and its one-time registration loops have finished")
	var names := ROWS.map(func(row):return row[0])
	check(vm.instances.filter(func(inst):return inst.sname in names \
		and inst.locals.get("this") == host.party_units(0)[0] and not inst.killed).size() == ROWS.size(),
		"native protagonist owns all nine pending original checks")
	capture("after_startup")
	if arrival == "late" and not await connect_guest(): await done(); return
	place_safe(); ticks(3)
	var guest := visitor()
	check(guest != null and guest.controller == 1 and guest.has_meta("hero"),"guest deploys through normal network registration")
	if guest == null: await done(); return
	check(vm.globals.Heroes.has(guest),"refreshed native Heroes includes the guest")
	check(ROWS.all(func(row):return row[2].keys().all(func(key):return host.state.get_var(0,key) == 0)),
		"none of the tested route stages was preseeded or completed")
	var lever_states := {}
	for id: int in [43968,43974,45622,45627]: lever_states[id] = host.world.levers.get(id,{}).get("state",-1)
	var definitions := {}
	for name: String in ROOTS+names:
		definitions[name] = original.scripts[name]
		for block: Dictionary in original.scripts[name].blocks:
			for statement: Array in block.body:
				if statement[0] == ScriptParser.S_CALL and original.scripts.has(statement[1]):
					definitions[statement[1]] = original.scripts[statement[1]]
	evidence.original_definitions = definitions
	evidence.points = {}
	capture("after_join")
	for row: Array in ROWS:
		var name: String = row[0]
		var point: Vector2
		if row[1] is String:
			var object = vm.globals.get(row[1])
			check(is_instance_valid(object),name+": original bound landmark exists")
			if not is_instance_valid(object): continue
			point = vm._xy(object)
		else: point = row[1]
		point = host.world.nav.nearest_walkable(point)
		guest.pos = point; guest.resync_drawn()
		evidence.points[name] = [point.x,point.y]
		check(satisfies(name,guest) and not satisfies(name,host.party_units(0)[0]),
			name+": only the guest occupies an actual walkable trigger point")
		ticks(5)
		check(row[2].keys().all(func(key):return host.state.get_var(0,key) >= row[2][key]),
			name+": guest advances every authored shared route stage")
		check(vm._world_done.get(name,-1) == 1,name+": native one-shot records the guest as its trigger owner")
		capture(name)
	check(host.state.get_var(0,"b.bz18h.s71") == 1 and host.state.quests.get("q71h",0) == 2,
		"q71h reaches the unchanged native completion continuation")
	check(host.state.get_var(0,"q.gz19h.q72h") == 0 and host.zone_id == "gz19h",
		"route discovery never completes q72h or bypasses its protagonist portal")
	check(lever_states.keys().all(func(id):return host.world.levers.get(id,{}).get("state",-1) == lever_states[id]),
		"approaching landmarks never operates their native levers")
	check(host.party_units(0)[0].pos == SAFE and not guest.dead,
		"native protagonist stays distant and guest survives the prepared route")
	host.sync_state()
	check(await until(func():return ROWS.all(func(row):return row[2].keys().all(
		func(key):return client.state.get_var(0,key) == host.state.get_var(0,key)))),
		"actual ENet delivers the resulting shared quest values to the guest")
	await done()

func done() -> void:
	evidence.merge({"checks":checks,"failures":failures,"arrival":arrival,
		"scope":"Original unmodified startup and actual ENet early/late arrival. Only actor positions and native VM ticks are controlled, with AI/combat paused. No manual check registration, seeded quest completion, lever activation, full navigation route, rendering or performance acceptance."})
	FileAccess.open("user://prison-progression-late-join.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t")+"\n")
	print("PRISON_PROGRESSION_LATE_JOIN ",checks," checks ",failures," failures")
	await finish()

extends "./story_coop_traps_net.gd"
## Original gz19h WorldScript and real ENet entry. Only actor positions and
## native VM ticks are controlled; AI/combat are paused, not a full route.
const PORT := 29953
const SAFE := Vector2(100,100)
var register := "VTriger#0#264"
var approach := ["VCheck#0#265","VCheck#0#269","VCheck#0#271"]
var chest_check := "VCheck#0#258"
var quest := "q.gz19h.qk16h"
const CHEST_ID := 736257
var arrival := "late"
var quest_case := "qk16h"
var triggers := ["VTriger#0#261","VTriger#0#273"]
var evidence := {"phases":[]}

func loaded() -> bool:
	return client != null and client.world != null and client.zone_id == "gz19h" \
		and client.my_index == 1 and not client._remote_loading and not client._zone_holding \
		and not client.loading_game and client._pool_epoch == host._load_serial

func connect_guest() -> bool:
	client = branch(true)
	GameData.player_name = "Discovery Guest"
	check(client.join("127.0.0.1",PORT) == OK,"real ENet guest connects")
	var ready := await until(func():return client.my_index == 1 and host.players.size() == 2)
	check(ready,"normal hello registers the actual guest")
	if ready:
		ready = await until(loaded)
		check(ready,"guest receives the original prison world")
		if ready: freeze(client)
	return ready

func place_safe() -> void:
	for u: GameUnit in host.world.party_units():
		u.pos = SAFE + Vector2(0,3*u.controller)
		u.resync_drawn()

func quest_values() -> Dictionary:
	var out := {}
	for suffix: String in ["",".1",".2",".3"]:
		out[quest+suffix] = host.state.get_var(0,quest+suffix)
	return out

func capture(label: String) -> void:
	var vm := host.world.vm
	var waits := []
	for inst: ScriptVM.Instance in vm.instances:
		if inst.sname not in approach+[chest_check] or inst.killed: continue
		var u = inst.locals.get("this")
		waits.append({"script":inst.sname,"uid":u.uid if is_instance_valid(u) else -1,
			"controller":u.controller if is_instance_valid(u) else -1})
	var row := {"label":label,"vm_time":vm.time,"quest":quest_values(),"waits":waits,
		"hero_ids":vm.globals.get("Heroes",[]).map(func(u):return u.uid),
		"guest_uid":visitor().uid if visitor() else -1,"money":host.state.money,
		"chest_state":host.world.levers.get(CHEST_ID,{}).get("state",-1),
		"g1":host.state.get_var(0,"g1"),"alarm2":host.state.get_var(0,"q.gz19h.q72h.34")}
	evidence.phases.append(row)
	print("DISCOVERY_PHASE ",JSON.stringify(row))

func satisfies(name: String, actor: GameUnit) -> bool:
	var probe := ScriptVM.Instance.new()
	probe.locals.this = actor
	return host.world.vm._all(host.world.vm.ast.scripts[name].blocks[0].conds,probe)

func approach_point(guest: GameUnit, chest: Vector2) -> Vector2:
	var candidates := [Vector2(98,476),Vector2(103,486),Vector2(109,476)] if quest_case == "qk16h" else [Vector2(79,318)]
	# Prefer an authored approach region outside the separate chest radius,
	# so the two native quest stages have distinct observed witnesses.
	for x in [-8,0,8]:
		for y in [-8,0,8]: candidates.append(Vector2(103+x,486+y) if quest_case == "qk16h" else Vector2(79+x,318+y))
	var before := guest.pos
	var chosen := Vector2.INF
	var clearance := 7.0
	for point: Vector2 in candidates:
		point = host.world.nav.nearest_walkable(point)
		guest.pos = point
		if point.distance_to(chest) > clearance and approach.any(func(name):return satisfies(name,guest)) \
				and not satisfies(chest_check,guest):
			chosen = point
			clearance = point.distance_to(chest)
	guest.pos = before
	return chosen

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--discovery-arrival="): arrival = arg.get_slice("=",1)
		if arg.begins_with("--discovery-quest="): quest_case = arg.get_slice("=",1)
	check(arrival in ["early","late"],"arrival case is explicit")
	check(quest_case in ["qk16h","qk17h"],"quest case is explicit")
	if quest_case == "qk17h":
		register = "VTriger#0#278"
		approach = ["VCheck#0#279"]
		chest_check = "VCheck#0#280"
		triggers = ["VTriger#0#284","VTriger#0#285"]
		quest = "q.gz19h.qk17h"
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"net_websocket":0,"auto_graphics":0,"control_mode":1,
		"confine_mouse":0,"scroll_border":0},true)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	CoopProgress.bring_slot = ""
	host = branch(false)
	host.state = CoopProgress.fresh_state()
	host.state.heroes[0][0].name = "Discovery Host"
	host.set_physics_process(false)
	GameData.player_name = "Discovery Host"
	check(host.host(PORT,2) == OK,"actual ENet host opens")
	await host.enter_zone("gz19h",1,false)
	freeze(host)
	if arrival == "early" and not await connect_guest(): await done(); return
	place_safe()
	var vm := host.world.vm
	check(vm != null and vm.ast.errors.is_empty(),"original map script parses")
	check(vm.instances.any(func(inst):return inst.sname == "WorldScript"),
		"original startup remains pending before explicit ticks")
	var original := ScriptParser.parse(host.world.mob.script_text)
	evidence.original_script_sha256 = host.world.mob.script_text.sha256_text()
	var definitions := [register,chest_check]+triggers+approach
	check(definitions.all(func(name):return vm.ast.scripts[name].params == original.scripts[name].params \
		and vm.ast.scripts[name].blocks == original.scripts[name].blocks),
		"native registration, conditions and shared quest bodies remain unchanged")
	check(["VCheck#0#286","VCheck#0#281","VTriger#0#288"].all(func(name):
		return vm.ast.scripts[name] == original.scripts[name]),
		"separate HChest2 reward and completion chain remains authored")
	check(original.world.has([ScriptParser.S_CALL,register,[[ScriptParser.N_VAR,"NULL"]]]),
		"shipped WorldScript directly calls this registration")
	ticks(16)
	check(not vm.instances.any(func(inst):return inst.sname in ["WorldScript",register]),
		"original startup and its one-time Heroes registration have finished")
	check(vm.instances.filter(func(inst):return inst.sname in approach+[chest_check] \
		and inst.locals.get("this") == host.party_units(0)[0] and not inst.killed).size() == approach.size()+1,
		"original startup owns one waiting check per predicate for the native protagonist")
	capture("after_startup")
	if arrival == "late" and not await connect_guest(): await done(); return
	place_safe()
	ticks(3)
	var guest := visitor()
	check(guest != null and guest.controller == 1 and guest.has_meta("hero"),
		"guest is normally deployed as a separate player character")
	if guest == null: await done(); return
	check(vm.globals.Heroes.has(guest),"refreshed native Heroes contains the guest")
	check(quest_values().values().all(func(value):return value == 0),
		"neither discovery nor completion has been seeded")
	var chest = vm.globals.get("HChest1")
	check(is_instance_valid(chest) and host.world.objects.get(CHEST_ID) == chest,
		"original HChest1 resolves to actual map object 736257")
	if not is_instance_valid(chest): await done(); return
	var chest_at: Vector2 = vm._xy(chest)
	var start_at := approach_point(guest,chest_at)
	check(start_at.is_finite(),"actual walkable authored approach point is outside the chest stage")
	if not start_at.is_finite(): await done(); return
	var chest_state = host.world.levers.get(CHEST_ID,{}).get("state",-1)
	var second_chest_state = host.world.levers.get(980428,{}).get("state",-1)
	var initial_money: int = host.state.money
	evidence.points = {"approach":[start_at.x,start_at.y],"chest":[chest_at.x,chest_at.y]}
	capture("after_join")
	guest.pos = start_at
	guest.resync_drawn()
	check(approach.any(func(name):return satisfies(name,guest)) and not satisfies(chest_check,guest),
		"only the guest satisfies the original approach stage before ticks")
	check(approach.all(func(name):return not satisfies(name,host.party_units(0)[0])),
		"native protagonist remains outside every original approach region")
	ticks(4)
	check(host.state.get_var(0,quest) == 1,"guest approach activates the original shared quest")
	check(host.state.get_var(0,quest+".1") == 2,"guest approach completes the original first discovery stage")
	check(host.state.get_var(0,quest+".2") == 1 and host.state.get_var(0,quest+".3") == 0,
		"guest approach activates only the authored chest search stage")
	capture("after_approach")
	var near_chest := host.world.nav.nearest_walkable(chest_at)
	guest.pos = near_chest
	guest.resync_drawn()
	evidence.points.near_chest = [near_chest.x,near_chest.y]
	check(satisfies(chest_check,guest) and not satisfies(chest_check,host.party_units(0)[0]),
		"only the guest reaches the actual native chest-discovery radius")
	ticks(4)
	check(host.state.get_var(0,quest+".2") == 2,"guest alone completes the original chest-discovery stage")
	check(host.state.get_var(0,quest+".3") == 1,"guest chest discovery activates the authored opening stage")
	check(host.world.levers.get(CHEST_ID,{}).get("state",-1) == chest_state \
		and host.world.levers.get(980428,{}).get("state",-1) == second_chest_state \
		and host.state.money == initial_money and host.state.get_var(0,quest) != 2,
		"inspection never opens either chest, awards money or completes the quest")
	check(host.state.get_var(0,"g1") == 0 and host.state.get_var(0,"q.gz19h.q72h.34") == 0,
		"independent prison alarm stages remain inactive")
	check(host.party_units(0)[0].pos == SAFE and not guest.dead,
		"position-controlled native protagonist stays distant and guest remains alive")
	capture("after_chest_discovery")
	await done()

func done() -> void:
	evidence.merge({"checks":checks,"failures":failures,"arrival":arrival,"quest_case":quest_case,
		"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),
		"scope":"Original unmodified startup plus actual ENet early/late arrival. Actor positions and native VM ticks are controlled with AI/combat paused; chosen points satisfy actual native predicates on walkable map coordinates. No manual native registration/child spawn, quest completion seeding, chest opening, full route, navigation traversal or rendered acceptance."})
	FileAccess.open("user://prison-discovery-late-join.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t")+"\n")
	print("PRISON_DISCOVERY_LATE_JOIN ",checks," checks ",failures," failures")
	await finish()

extends "./story_coop_traps_net.gd"
## Original gz19h startup plus real ENet party registration. The field route
## is prepared: actor positions and VM ticks are controlled, AI/combat paused.
## No quest success is seeded and no alarm child is manually spawned.
const PORT := 29952
const SAFE := Vector2(100,100)
const INTRUSION := Vector2(480,330)
const WATCH := "VCheck#0#417"
const REGISTRAR := "VTriger#0#416#RemakeParticipants"
const ALARM_MOB := "zone19alarm1.mob"
var arrival := "late"
var evidence := {"phases":[],"trace":[]}
var expected_guards := []

func alarm_added() -> bool:
	return host.world.get_meta("added_mobs",[]).any(func(file):return String(file).to_lower() == ALARM_MOB)

func loaded() -> bool:
	return client != null and client.world != null and client.zone_id == "gz19h" \
		and client.my_index == 1 and not client._remote_loading and not client._zone_holding \
		and not client.loading_game and client._pool_epoch == host._load_serial

func connect_guest() -> bool:
	client = branch(true)
	GameData.player_name = "Alarm Guest"
	check(client.join("127.0.0.1",PORT) == OK,"real ENet guest connects")
	var ready := await until(func(): return client.my_index == 1 and host.players.size() == 2)
	check(ready,"normal hello registers guest in slot 1")
	if ready and host.world != null:
		ready = await until(loaded)
		check(ready,"guest receives actual gz19h world")
		if ready: freeze(client)
	return ready

func place_safe() -> void:
	for u: GameUnit in host.world.party_units():
		u.pos = SAFE + Vector2(0,3*u.controller)
		u.resync_drawn()

func watcher_count(u: GameUnit) -> int:
	return host.world.vm.instances.filter(func(inst):
		return inst.sname == WATCH and not inst.killed and inst.locals.get("this") == u
	).size()

func registrar_count() -> int:
	return host.world.vm.instances.filter(func(inst):return inst.sname == REGISTRAR).size()

func saved_waits(key: Array) -> Array:
	return host.world.vm.save_state().instances.filter(func(row):
		var subject = row.get("l",{}).get("this")
		return row.get("s") == WATCH and subject is Dictionary and subject.get("h") == key
	)

func capture(label: String) -> void:
	var vm := host.world.vm
	var guest := visitor()
	var watched := []
	for inst: ScriptVM.Instance in vm.instances:
		if inst.sname != WATCH or inst.killed: continue
		var u = inst.locals.get("this")
		watched.append({"uid":u.uid if is_instance_valid(u) else -1,
			"controller":u.controller if is_instance_valid(u) else -1})
	var row := {"label":label,"vm_time":vm.time,"world_time":host.world.time,
		"hero_ids":vm.globals.get("Heroes",[]).map(func(u):return u.uid),
		"watchers":watched,"instance_count":vm.instances.size(),
		"registrar_count":registrar_count(),"saved_guest_waits":saved_waits([1,0]),
		"guest_uid":guest.uid if guest else -1,"guest_watchers":watcher_count(guest) if guest else 0,
		"g1":host.state.get_var(0,"g1"),"alarm2":host.state.get_var(0,"q.gz19h.q72h.34"),
		"alarm_mob_added":alarm_added(),"guard_ids":vm.globals.get("a1",[]).map(func(u):return u.uid)}
	evidence.phases.append(row)
	print("ALARM_PHASE ",JSON.stringify(row))

func check_wait(label: String) -> void:
	var guest := visitor()
	check(guest != null and guest.controller == 1 and guest.has_meta("hero"),label+": guest is normally deployed")
	if guest == null: return
	check(host.world.vm.globals.Heroes.has(guest),label+": refreshed Heroes contains guest")
	check(watcher_count(guest) == 1,label+": guest has one native area-1 wait")
	check(watcher_count(host.party_units(0)[0]) == 1,label+": native protagonist retains one wait")
	check(host.state.get_var(0,"g1") == 0,label+": no area-1 success or alarm has been seeded")
	capture(label)

func disconnect_guest() -> bool:
	var peer := client.multiplayer.multiplayer_peer
	client.online = false
	client.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer.close()
	var old: Node = branches.back()
	branches.erase(old)
	old.queue_free()
	client = null
	var absent := await until(func():return host.players.size() == 1)
	check(absent,"authority observes actual guest disconnect")
	return absent

func reconnect_guest() -> bool:
	if not await disconnect_guest(): return false
	return await connect_guest()

func check_absent(label: String, key: Array) -> void:
	var vm := host.world.vm
	check(client == null and host.players.size() == 1 and not host.players_include(1),
		label+": no guest transport or registered player is present")
	check(visitor() == null and vm.heroes().all(func(u):return u.controller != 1),
		label+": guest was not deployed during host-only load")
	var rows := saved_waits(key)
	check(rows.size() == 1 and not rows[0].k and rows[0].f.is_empty(),
		label+": one unspent native wait retains the same serialized hero identity")
	check(watcher_count(null) == 1,label+": the absent actor's native wait stays dormant")
	check(registrar_count() == 1,label+": one persistent registrar survives")
	check(watcher_count(host.party_units(0)[0]) == 1,label+": native protagonist wait is not duplicated")
	check(host.state.get_var(0,"g1") == 0 and not alarm_added() and vm.globals.get("a1",[]).is_empty(),
		label+": absence does not activate or seed the original alarm")
	capture(label)

func absent_reload_sequence(slot: String, guest: GameUnit) -> bool:
	var key: Array = host.world.vm._hero_key(guest).duplicate()
	var hero_name := String(guest.get_meta("hero").get("name",""))
	evidence.rejoin_identity = {"hero_key":key,"name":hero_name,"before_uid":guest.uid}
	check(key == [1,0] and saved_waits(key).size() == 1,
		"before absence: the normally joined character owns one serialized native wait")
	if not await disconnect_guest(): return false
	var first_load := await host.load_game_shown(slot)
	check(first_load,"pending original map loads through Session with guest absent")
	if not first_load: return false
	freeze(host)
	ticks(25)
	check_absent("first_absent_reload",key)
	var absent_slot := slot+"_absent"
	check(host.save_game(absent_slot) == OK,"host saves the pending native wait while guest remains absent")
	var second_load := await host.load_game_shown(absent_slot)
	check(second_load,"host-only save reloads again before any guest rejoin")
	if not second_load: return false
	freeze(host)
	ticks(25)
	check_absent("second_absent_reload",key)
	# Retain the actual restored thread object. A replacement registration
	# after reconnect must not masquerade as resuming this pending wait.
	var dormant: ScriptVM.Instance = null
	for inst: ScriptVM.Instance in host.world.vm.instances:
		if inst.sname == WATCH and not inst.killed and inst.locals.get("this") == null:
			if dormant != null: dormant = null; break
			dormant = inst
	if not await connect_guest(): return false
	ticks(3)
	check_wait("after_absent_rejoin")
	guest = visitor()
	if guest == null: return false
	var vm := host.world.vm
	check(dormant != null and vm.instances.has(dormant) and not dormant.killed \
		and dormant.locals.get("this") == guest,
		"normal rejoin rebinds the same restored native wait rather than spawning a replacement")
	check(vm._hero_key(guest) == key and is_same(guest.get_meta("hero"),host.state.heroes[1][0]) \
		and String(guest.get_meta("hero").get("name","")) == hero_name,
		"rejoined actor retains its original player/roster identity and character name")
	check(saved_waits(key).size() == 1 and registrar_count() == 1 \
		and vm.instances.filter(func(inst):return inst.sname == WATCH and not inst.killed).size() == 2,
		"rejoin has exactly one registrar and one native wait per actual character")
	evidence.rejoin_identity.after_uid = guest.uid
	evidence.rejoin_identity.after_hero_key = vm._hero_key(guest)
	return true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--alarm-arrival="): arrival = arg.get_slice("=",1)
	check(arrival in ["early","late"],"arrival case is explicit")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"net_websocket":0,"auto_graphics":0,"control_mode":1,
		"confine_mouse":0,"scroll_border":0},true)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	CoopProgress.bring_slot = ""
	host = branch(false)
	host.state = CoopProgress.fresh_state()
	host.state.heroes[0][0].name = "Alarm Host"
	host.set_physics_process(false)
	GameData.player_name = "Alarm Host"
	check(host.host(PORT,2) == OK,"actual ENet host opens")
	await host.enter_zone("gz19h",1,false)
	freeze(host)
	# Both cases use the normal in-game hello/hero creation path. "Early"
	# means before the original WorldScript's one-time registration executes.
	if arrival == "early" and not await connect_guest(): await done(); return
	place_safe()
	var vm := host.world.vm
	var alarm := EIMob.load_bytes(GameData.read_file("maps/"+ALARM_MOB))
	for object: Dictionary in alarm.objects:
		if object.kind == "UNIT": expected_guards.append(int(object.nid))
	expected_guards.sort()
	check(expected_guards.size() == 8,"original alarm MOB contains its eight reinforcement guards")
	check(vm != null and vm.ast.errors.is_empty(),"original map script loads without parse errors")
	check(vm.instances.any(func(inst):return inst.sname == "WorldScript"),"original startup is still pending before explicit ticks")
	ticks(16)
	check(not vm.instances.any(func(inst):return inst.sname == "WorldScript"),"original WorldScript completes its own registration")
	check(not vm.instances.any(func(inst):return inst.sname == "VTriger#0#416"),"one-time authored registration has finished")
	check(vm.areas.has(1) and vm._call("IsInArea",[[ScriptParser.N_NUM,1.0],
		[ScriptParser.N_NUM,INTRUSION.x],[ScriptParser.N_NUM,INTRUSION.y]],ScriptVM.Instance.new()) == 1.0,
		"test point is inside original area 1")
	check(vm.globals.get("a1",[]).is_empty() and not alarm_added(),
		"original a1 group stays empty until the alarm loads its reinforcement MOB")
	var original := ScriptParser.parse(host.world.mob.script_text)
	check(vm.ast.scripts["VTriger#0#416"] == original.scripts["VTriger#0#416"]
		and vm.ast.scripts[WATCH] == original.scripts[WATCH],"registration and entry predicate remain authored")
	check(vm.ast.scripts["VCheck#0#428"] == original.scripts["VCheck#0#428"],"independent alarm-2 live-group predicate is unchanged")
	capture("after_startup")
	if arrival == "late" and not await connect_guest(): await done(); return
	place_safe()
	ticks(3)
	check_wait("after_join")
	var guest := visitor()
	if guest == null: await done(); return
	var slot := "prison_alarm_"+arrival
	check(host.save_game(slot) == OK,"pending original map and guest state save")
	check(await host.load_game_shown(slot),"saved pending map reloads through Session")
	freeze(host)
	check(await until(loaded),"guest receives restored original map")
	if not loaded(): await done(); return
	freeze(client)
	ticks(3)
	check_wait("after_reload")
	var before_reconnect := visitor().uid
	if not await reconnect_guest(): await done(); return
	ticks(3)
	check_wait("after_reconnect")
	guest = visitor()
	check(guest != null and guest.uid == before_reconnect,"reconnect reclaims the same deployed actor")
	if guest == null: await done(); return
	if not await absent_reload_sequence(slot,guest): await done(); return
	guest = visitor()
	guest.pos = INTRUSION
	guest.resync_drawn()
	vm = host.world.vm
	# Allow the native 20-tick pursuit loop to run after AddMob's own startup.
	# Do not populate a1 or invoke the registration/alarm children directly.
	for i in 85:
		ticks(1)
		var guards: Array = vm.globals.get("a1",[])
		var assigned := []
		for guard: GameUnit in guards:
			if guard.mode == "sentry" and guard.mode_data.get("point",Vector2.INF) == INTRUSION:
				assigned.append(guard.uid)
		assigned.sort()
		var target = vm.globals.get("Try1")
		evidence.trace.append({"tick":i+1,"vm_time":vm.time,"g1":host.state.get_var(0,"g1"),
			"intruder_uid":target.uid if is_instance_valid(target) else -1,"assigned_guards":assigned,
			"guard_count":guards.size(),"alarm_mob_added":alarm_added()})
	check(host.state.get_var(0,"g1") >= 2,"guest entry activates the authored area-1 alarm")
	check(vm.globals.get("Try1") == guest,"authored alarm selects the entering guest")
	check(alarm_added(),"original alarm loads its own reinforcement MOB")
	var actual_guards: Array = vm.globals.get("a1",[]).map(func(u):return u.uid)
	actual_guards.sort()
	check(actual_guards == expected_guards,"original reinforcement startup populates exactly its real a1 guards")
	check(evidence.trace.any(func(row):return row.assigned_guards == expected_guards),
		"all real a1 guards receive the original sentry target")
	check(host.state.get_var(0,"q.gz19h.q72h.34") == 0,"unrelated alarm-2 remains inactive")
	check(host.party_units(0)[0].pos == SAFE,"protagonist remains outside the alarm area")
	check(guest.pos == INTRUSION and not guest.dead,"position-controlled guest stays alive for predicate inspection")
	capture("after_intrusion")
	await done()

func done() -> void:
	evidence.merge({"checks":checks,"failures":failures,"arrival":arrival,"expected_guard_ids":expected_guards,
		"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),
		"scope":"Actual original startup, real ENet registration and Session save/reload/reconnect, then disconnect, host-only reload, 25 native ticks, absent save, second host-only reload, 25 native ticks and normal rejoin before real alarm entry. Controlled positions and manual VM ticks, paused AI/combat. No full prison route, physical guard navigation or rendered acceptance."})
	FileAccess.open("user://prison-alarm-late-join.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t")+"\n")
	print("PRISON_ALARM_LATE_JOIN ",checks," checks ",failures," failures")
	await finish()

extends "./story_coop_traps_net.gd"
## Original startup and real ENet arrival. Prepared map positions and native
## ticks isolate individual traps; this is not a physical prison playthrough.
const PORT := 29956
const SAFE := Vector2(100,100)
const REGISTER := "VTriger#0#76"
const ROWS := [
	["VCheck#0#86","VTriger#0#150",Vector2(380,255)],
	["VCheck#0#87","VTriger#0#90",Vector2(339,94)],
	["VCheck#0#88","VTriger#0#95",Vector2(450,185)],
	["VCheck#0#115","VTriger#0#153",Vector2(353.5,128.5)],
	["VCheck#0#116","VTriger#0#154",Vector2(380.5,122)],
	["VCheck#0#117","VTriger#0#155",Vector2(372,135.5)],
	["VCheck#0#118","VTriger#0#156",Vector2(400,135.5)],
	["VCheck#0#119","VTriger#0#157",Vector2(365.5,147.5)],
	["VCheck#0#120","VTriger#0#158",Vector2(395,147)],
	["VCheck#0#121","VTriger#0#159",Vector2(380.5,160)],
	["VCheck#0#122","VTriger#0#160",Vector2(403,151)],
]
var arrival := "late"
var with_reload := false
var evidence := {"phases":[]}

func loaded() -> bool:
	return client != null and client.world != null and client.zone_id == "gz19h" \
		and client.my_index == 1 and not client._remote_loading and not client._zone_holding \
		and not client.loading_game and client._pool_epoch == host._load_serial

func connect_guest() -> bool:
	client = branch(true); GameData.player_name = "Damage Guest"
	check(client.join("127.0.0.1",PORT) == OK,"actual ENet guest connects")
	var ready := await until(func():return client.my_index == 1 and host.players.size() == 2)
	check(ready,"normal hello registers a separate guest")
	if ready:
		ready = await until(loaded)
		check(ready,"guest receives original gz19h")
		if ready: freeze(client)
	return ready

func place_safe() -> void:
	for u: GameUnit in host.world.party_units():
		u.pos = SAFE+Vector2(0,3*u.controller); u.resync_drawn()

func pending(name: String, who: GameUnit) -> Array:
	return host.world.vm.instances.filter(func(inst):return inst.sname == name \
		and inst.locals.get("this") == who and (not inst.killed or not inst.frames.is_empty()))

func satisfies(name: String, who: GameUnit) -> bool:
	var probe := ScriptVM.Instance.new(); probe.locals.this = who
	return host.world.vm._all(host.world.vm.ast.scripts[name].blocks[0].conds,probe)

func capture(label: String) -> void:
	var vm := host.world.vm
	var guest := visitor()
	var names := [REGISTER,"VTriger#0#113",REGISTER+"#RemakeParticipants"]
	for row: Array in ROWS: names.append_array(row.slice(0,2))
	evidence.phases.append({"label":label,"time":vm.time,"guest_uid":guest.uid if guest else -1,
		"guest_dead":guest.dead if guest else false,"guest_hp":guest.hp if guest else -1,
		"rows":vm.save_state().instances.filter(func(row):return row.s in names)})

func independent_cooldowns(guest: GameUnit) -> void:
	var vm := host.world.vm
	var corpse_wait := pending("VTriger#0#160",guest)
	var corpse_deadline: float = corpse_wait[0].wait_until if not corpse_wait.is_empty() else vm.time
	ticks(63)
	var next_corpse_wait := pending("VTriger#0#160",guest)
	check(guest.dead and next_corpse_wait.size() == 1 and next_corpse_wait[0].wait_until > corpse_deadline,
		"original dead-actor trap continues its native Sleep/rearm cadence without a second life")
	capture("native_dead_cadence")
	guest.pos = SAFE+Vector2(0,3)
	if guest.dead: Revive.finish(host,guest)
	# Let every preceding independent trap return to its own idle predicate.
	ticks(65)
	var leader: GameUnit = host.party_units(0)[0]
	var point: Vector2 = host.world.nav.nearest_walkable(Vector2(339,94))
	leader.pos = point; leader.resync_drawn(); ticks(2)
	var first := pending("VTriger#0#90",leader)
	check(leader.dead and first.size() == 1,"native protagonist independently enters the same individual trap")
	var first_deadline: float = first[0].wait_until if not first.is_empty() else vm.time
	if leader.dead: Revive.finish(host,leader)
	leader.pos = point; leader.resync_drawn()
	ticks(17)
	check(not leader.dead and pending("VTriger#0#90",leader).size() == 1,
		"revival does not erase protagonist's pending native cooldown")
	guest.pos = point; guest.resync_drawn(); ticks(2)
	var second := pending("VTriger#0#90",guest)
	var second_deadline: float = second[0].wait_until if not second.is_empty() else vm.time
	check(guest.dead and second.size() == 1,"guest independently starts its own damage/Sleep cycle")
	check(first.size() == 1 and is_equal_approx(first[0].wait_until,first_deadline) and not leader.dead,
		"guest entry neither resets nor consumes protagonist's existing Sleep")
	check(second.size() == 1 and second_deadline-first_deadline > 15*ScriptVM.POLL,
		"staggered actors keep different native cooldown deadlines")
	if guest.dead: Revive.finish(host,guest)
	guest.pos = point; guest.resync_drawn()
	ticks(maxi(0,int(ceil((first_deadline-vm.time)/ScriptVM.POLL)))+3)
	check(leader.dead and not guest.dead,"first actor rearms while second actor still waits")
	check(second.size() == 1 and pending("VTriger#0#90",guest).has(second[0]) \
		and is_equal_approx(second[0].wait_until,second_deadline),
		"first actor's second hit preserves the exact second actor's sleeping instance")
	leader.pos = SAFE
	if leader.dead: Revive.finish(host,leader)
	leader.pos = SAFE; leader.resync_drawn()
	ticks(maxi(0,int(ceil((second_deadline-vm.time)/ScriptVM.POLL)))+3)
	check(guest.dead and pending("VTriger#0#90",guest).size() == 1 and not leader.dead,
		"second actor rearms on its own original deadline without sharing damage")
	evidence.cooldown_deadlines = {"first":first_deadline,"second":second_deadline}
	capture("independent_cooldowns")

func disconnect_guest() -> bool:
	var peer := client.multiplayer.multiplayer_peer
	client.online = false; client.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer.close()
	var old: Node = branches.back(); branches.erase(old); old.queue_free(); client = null
	var absent := await until(func():return host.players.size() == 1)
	check(absent,"authority observes actual guest disconnect")
	return absent

func disconnected_cycle(guest: GameUnit) -> void:
	var vm := host.world.vm
	var sleeping := pending("VTriger#0#90",guest)
	var deadline: float = sleeping[0].wait_until if not sleeping.is_empty() else vm.time
	if guest.dead: Revive.finish(host,guest)
	guest.pos = host.world.nav.nearest_walkable(Vector2(339,94)); guest.resync_drawn()
	if not await disconnect_guest(): return
	check(guest.controller == -1 and int(guest.get_meta("orphan_of",-1)) == 1 \
		and host.world.units.get(guest.uid) == guest and not guest.dead,
		"normal disconnect retains the same living native AI follower")
	ticks(5)
	check(sleeping.size() == 1 and pending("VTriger#0#90",guest).has(sleeping[0]) \
		and is_equal_approx(sleeping[0].wait_until,deadline) and not guest.dead,
		"present disconnected actor keeps its original running cooldown")
	ticks(maxi(0,int(ceil((deadline-vm.time)/ScriptVM.POLL)))+3)
	check(guest.dead and pending("VTriger#0#90",guest).size() == 1,
		"present disconnected follower receives the next native trap hit on schedule")
	evidence.disconnected_follower = {"uid":guest.uid,"controller":guest.controller,
		"orphan_of":guest.get_meta("orphan_of",-1),"deadline":deadline,"dead_after_rearm":guest.dead,
		"native_rows":vm.save_state().instances.filter(func(row):return row.s == "VTriger#0#90")}

func saved_sleep() -> Dictionary:
	for row: Dictionary in host.world.vm.save_state().instances:
		if row.s == "VTriger#0#90" and row.l.get("this") is Dictionary and row.l.this.get("h") == [1,0]: return row
	return {}

func same_sleep(first: Dictionary, second: Dictionary) -> bool:
	return not first.is_empty() and not second.is_empty() and first.s == second.s \
		and first.l.this == second.l.this and first.k == second.k and first.f == second.f \
		and first.b == second.b and first.i == second.i \
		and is_equal_approx(first.w,second.w) and is_equal_approx(first.p,second.p)

func absent_reload_sequence() -> void:
	if not await connect_guest(): return
	var guest := visitor()
	check(guest != null and guest.uid == int(evidence.disconnected_follower.uid),
		"normal reconnect reclaims the previously disconnected native actor")
	if guest == null: return
	if guest.dead: Revive.finish(host,guest)
	guest.pos = host.world.nav.nearest_walkable(Vector2(339,94)); guest.resync_drawn()
	ticks(2)
	var initial := saved_sleep()
	check(not initial.is_empty() and initial.w > ScriptVM.POLL*40 and initial.f == [{"i":4}],
		"normal reconnect retains a pending native Sleep before saving")
	if initial.is_empty(): return
	var slot := "prison_damage_"+arrival
	check(host.save_game(slot) == OK,"Session saves the independently sleeping guest and original map")
	if not await disconnect_guest(): return
	var first_load := await host.load_game_shown(slot)
	check(first_load,"Session loads the sleeping guest's map while that player is absent")
	if not first_load: return
	freeze(host); ticks(90)
	check(visitor() == null and host.players.size() == 1,"host-only load does not deploy the absent guest")
	var first := saved_sleep()
	check(same_sleep(initial,first),"first real absent load preserves exact native frame and remaining Sleep")
	check(host.world.vm.save_state().instances.filter(func(row):return row.s in ROWS.map(func(r):return r[0])+ROWS.map(func(r):return r[1]) \
		and row.l.get("this") is Dictionary and row.l.this.get("h") == [1,0]).size() == 11,
		"first absent map retains all eleven distinct actor continuations")
	check(host.save_game(slot+"_absent") == OK,"Session resaves all dormant native guest traps")
	var second_load := await host.load_game_shown(slot+"_absent")
	check(second_load,"Session loads the host-only checkpoint again before the guest returns")
	if not second_load: return
	freeze(host); ticks(95)
	var second := saved_sleep()
	check(same_sleep(initial,second),"second real absent load retains the original pending cooldown")
	var dormant: ScriptVM.Instance = null
	for inst: ScriptVM.Instance in host.world.vm.instances:
		if inst.sname == "VTriger#0#90" and inst.locals.get("this") == null:
			if dormant != null: dormant = null; break
			dormant = inst
	if not await connect_guest(): return
	guest = visitor(); ticks(1)
	var vm := host.world.vm
	check(guest != null and dormant != null and vm.instances.has(dormant) and dormant.locals.get("this") == guest,
		"real rejoin binds the same restored sleeping instance to its original character")
	if guest == null: return
	check(dormant != null and is_equal_approx(dormant.wait_until-vm.time,float(initial.w)-ScriptVM.POLL),
		"actual rejoin resumes remaining time without resetting or spending the native Sleep")
	guest.pos = host.world.nav.nearest_walkable(Vector2(339,94)); guest.resync_drawn()
	ticks(int(ceil(float(initial.w)/ScriptVM.POLL))+3)
	check(guest.dead and pending("VTriger#0#90",guest).size() == 1 and pending("VCheck#0#87",guest).is_empty(),
		"returned guest completes exactly one native damage cycle after the preserved Sleep")
	check(not host.party_units(0)[0].dead and host.party_units(0)[0].pos == SAFE,
		"guest's return and damage leave the safe protagonist's independent state intact")
	check(await sync_visitor(guest),"real ENet delivers the returned guest's final damage and position")
	# SpellSounds queues the native fireball impact sound for a later audio
	# frame. Let both peers finish that real callback before fixture teardown.
	await frames(3)
	check(await until(func():return [host,client].all(func(peer):
		return peer.game.sound == null or peer.game.sound.spells == null or peer.game.sound.spells._later.is_empty()),5),
		"both peers finish native delayed spell audio before teardown")
	evidence.absent_reload = {"initial":initial,"first":first,"second":second,"returned_uid":guest.uid}
	capture("after_absent_reload_rejoin")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--damage-arrival="): arrival = arg.get_slice("=",1)
		if arg == "--damage-reload": with_reload = true
	check(arrival in ["early","late"],"arrival case is explicit")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"net_websocket":0,"auto_graphics":0,"control_mode":1,
		"confine_mouse":0,"scroll_border":0},true)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	CoopProgress.bring_slot = ""
	host = branch(false); host.state = CoopProgress.fresh_state()
	host.state.heroes[0][0].name = "Damage Host"; host.set_physics_process(false)
	GameData.player_name = "Damage Host"
	check(host.host(PORT,2) == OK,"actual ENet host opens")
	await host.enter_zone("gz19h",1,false); freeze(host)
	if arrival == "early" and not await connect_guest(): await done(); return
	place_safe()
	var vm := host.world.vm
	var original := ScriptParser.parse(host.world.mob.script_text)
	evidence.original_script_sha256 = host.world.mob.script_text.sha256_text()
	check(original.errors.is_empty() and vm.ast.errors.is_empty(),"mounted original source parses")
	check(vm.instances.any(func(inst):return inst.sname == "WorldScript"),"native startup remains pending before controlled ticks")
	check(vm.ast.world == original.world and original.world.count([ScriptParser.S_CALL,REGISTER,[[ScriptParser.N_VAR,"NULL"]]]) == 1,
		"native startup still calls the unmodified trap registration exactly once")
	var names := [REGISTER,"VTriger#0#113"]
	for row: Array in ROWS: names.append_array(row.slice(0,2))
	evidence.native_definitions = names.map(func(name):return [name,original.scripts[name]])
	evidence.native_signature = JSON.stringify(evidence.native_definitions,"",true,true).sha256_text()
	check(names.all(func(name):return vm.ast.scripts[name] == original.scripts[name]),
		"all 24 native trap definitions retain exact bodies, conditions, timers and eligibility")
	ticks(16)
	check(not vm.instances.any(func(inst):return inst.sname in ["WorldScript",REGISTER]),
		"native startup and its one-time Heroes loop have finished")
	check(ROWS.all(func(row):return pending(row[0],host.party_units(0)[0]).size() == 1),
		"native protagonist owns all eleven distinct pending traps")
	capture("after_startup")
	if arrival == "late" and not await connect_guest(): await done(); return
	place_safe(); ticks(3)
	var guest := visitor()
	check(guest != null and guest.controller == 1 and guest.has_meta("hero"),"guest deploys through normal network registration")
	if guest == null: await done(); return
	check(vm.globals.Heroes.has(guest),"refreshed Heroes includes the guest")
	check(ROWS.all(func(row):return pending(row[0],guest).size() == 1),
		"guest has one native waiting instance of every individual trap")
	capture("after_join")
	evidence.points = {}
	for row: Array in ROWS:
		if guest.dead: Revive.finish(host,guest)
		check(not guest.dead,"fixture uses a living guest before "+row[0])
		var point: Vector2 = host.world.nav.nearest_walkable(row[2])
		guest.pos = point; guest.resync_drawn()
		evidence.points[row[0]] = [point.x,point.y]
		check(satisfies(row[0],guest) and not satisfies(row[0],host.party_units(0)[0]),
			row[0]+": only guest occupies an actual walkable authored trigger")
		ticks(5)
		check(guest.dead and guest.hp <= 0,row[0]+": original InflictDamage kills the entering guest")
		var sleeping := pending(row[1],guest)
		check(sleeping.size() == 1 and not sleeping[0].frames.is_empty() and sleeping[0].killed \
			and sleeping[0].wait_until > vm.time and sleeping[0].wait_until-vm.time <= 60*ScriptVM.SLEEP_UNIT,
			row[0]+": that guest keeps exactly one original Sleep(60) continuation")
		check(not host.party_units(0)[0].dead and pending(row[0],host.party_units(0)[0]).size() == 1,
			row[0]+": guest's hit neither damages nor consumes protagonist's own wait")
		capture(row[0])
	check(await sync_visitor(guest),"real ENet delivers the final actor life state and position")
	check(host.party_units(0)[0].pos == SAFE,"protagonist stays outside the prepared trap route")
	independent_cooldowns(guest)
	await disconnected_cycle(guest)
	if with_reload: await absent_reload_sequence()
	await done()

func done() -> void:
	evidence.merge({"checks":checks,"failures":failures,"arrival":arrival,"with_reload":with_reload,
		"scope":"Original unmodified WorldScript and real ENet early/late guest registration. All eleven traps use native InflictDamage and Sleep, actual walkable map points, and real Revival between independent prepared cases. Native dead-actor rearm, staggered host/guest cooldowns, and present disconnected follower behavior are checked. Optional --damage-reload executes two real host-only Session save/reloads and rejoin during Sleep. Actor positions and VM ticks are controlled with unrelated AI/combat paused. No full navigation route, rendered or timing/performance acceptance."})
	FileAccess.open("user://prison-damage-late-join.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t")+"\n")
	print("PRISON_DAMAGE_LATE_JOIN ",checks," checks ",failures," failures")
	await finish()

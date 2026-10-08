extends "story_coop_traps_net.gd"
## Resume an ordinary-play pre-escape save, add an actual ENet guest, then let
## all original AI, attacks, spells, movement and zone scripts run normally.
## Supply --save=<ordinary FPrison night save just after Kel's escape dialogue>.
## The source is copied into a disposable profile; it is never overwritten.
## --reactive waits for Terror before host input. --idle-guest checks automatic
## guest escape without a client move command. Enemy AI and spells stay active.
var reactive := OS.get_cmdline_user_args().has("--reactive")
var idle_guest := OS.get_cmdline_user_args().has("--idle-guest")
var automate := false
var ui_frame := 0
var saw_guest_run := false
var saw_barrier_dead := false
var saw_party_clear := false
var saw_terror := false
var early_terror := false
var travel_sent := false
var last_trace := 0
var initial_uids: Array = []
var deaths: Array = []
var run_sent := false
var escape_unknown_calls := {}
var client_boundary_released := false
var client_camera_released := false

func freeze(s:Session)->void:
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false)
	s.game.rig.set_process(false);s.game.hud._tutorial.close()

func loaded() -> bool:
	return client.world != null and client.zone_id == host.zone_id and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	var source := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): source=arg.trim_prefix("--save=")
	check(FileAccess.file_exists(source),"ordinary-play checkpoint supplied")
	if failures: await finish(); return
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	check(DirAccess.copy_absolute(source,SaveInfo.path("escape_source"))==OK,"copy ordinary-play checkpoint into isolated profile")
	if failures: await finish(); return
	host=branch(false);check(host.host(29937,2)==OK,"open real escape host")
	check(await host.load_game_shown("escape_source"),"load ordinary pre-escape checkpoint")
	if failures: await finish(); return
	freeze(host)
	check(host.zone_id=="bz1h" and host.state.current_party=="FPrison","checkpoint is the original captive camp")
	check(host.state.get_var(0,"b.merc2.n1_2")==2.,"explicit load preserves completed conversation for the pending escape thread")
	print("ESCAPE_STAGE ",host.state.get_var(0,"b.merc2.n1_2")," night=",host.state.get_var(0,"bz1h_night")," scripts=",host.world.vm.instances.map(func(i):return i.sname))
	client=branch(true);GameData.player_name="Escape Guest"
	check(client.join("127.0.0.1",29937)==OK,"join camp as actual client")
	check(await until(loaded),"client receives pre-escape camp")
	if failures:await finish();return
	var guest:=visitor();check(guest!=null and not guest.dead,"guest has a living controllable captive")
	if guest==null:await finish();return
	check(client.village_move_limit().z>0.,"client movement remains bounded before the escape")
	initial_uids=host.world.party_units().map(func(u):return u.uid)
	print("ESCAPE_START ",host.world.party_units().map(func(u):return [u.uid,u.pos,u.hp,u.blocked,u.order]))
	host.world.unit_died.connect(func(u,k):
		deaths.append([u.uid,u.display_name,k.uid if is_instance_valid(k) else -1]);print("ESCAPE_DEATH ",deaths.back()))
	host.world.combat_event.connect(func(kind,a,b,amount):
		if kind=="damage" and b and b.uid in initial_uids:print("ESCAPE_DAMAGE ",host.world.time," uid=",b.uid," hp=",b.hp," amount=",amount," pos=",b.pos," cause=",a.uid if is_instance_valid(a) else -1," order=",b.order," speed=",b.speed()," mana=",b.mana))
	host.set_physics_process(true);host.world.set_physics_process(true);host.world.set_process(true)
	client.set_physics_process(true);client.world.set_physics_process(true);client.world.set_process(true)
	automate=true
	var arrived:=await until(func():return host.zone_id=="gz1h" and loaded(),180.0)
	automate=false
	check(saw_barrier_dead,"ordinary scripted attacks destroy the barrier")
	check(saw_guest_run,"real guest receives automatic escape movement")
	check(saw_party_clear,"Kir Kel and guest physically clear the barrier")
	check(saw_terror and not early_terror,"Terror arrives only after the living party clears")
	check(client_boundary_released,"client receives the released escape boundary")
	check(client_camera_released,"client camera can follow outside the opened camp")
	check(run_sent,"ordinary run-away input submitted after the escape cue")
	check(not deaths.any(func(row):return row[0] in initial_uids),"no party member dies during the escape")
	check(arrived,"original escape transfers host and client to the next area")
	if arrived:
		check(host.world.party_units().all(func(u):return not u.dead),"whole deployed party survives the escape")
		check(not client.party_units(1).is_empty() and not client.party_units(1)[0].dead,"client receives a living escaped character")
		check(escape_unknown_calls.is_empty() and host.world.vm.unknown_calls.is_empty(),"escape reaches field without unsupported original script calls")
	else:print("ESCAPE_FAILED zone=",host.zone_id," options=",host.travel_options," guest=",visitor().pos if visitor() else Vector2.INF," deaths=",deaths)
	await finish()

func _process(_dt:float)->void:
	if not automate:return
	ui_frame+=1
	for s:Session in [host,client]:
		if s.game and s.game.hud and ui_frame%5==0:
			var hud:=s.game.hud
			if hud._tutorial.visible:hud._tutorial.close()
			if hud._movie.visible:hud._movie.stop()
			if hud._dialog.visible and hud._dialog._topics.is_empty():hud._dialog._skip();hud._dialog._next()
	if host.world==null or host.loading_game:return
	if host.zone_id=="bz1h":
		escape_unknown_calls.merge(host.world.vm.unknown_calls,true)
		if client.zone_id=="bz1h" and loaded() and client.village_move_limit()==Vector3.ZERO:
			client_boundary_released=true
			var escape_view:=Vector3(400,0,-77)
			client_camera_released=client.game.rig.terrain!=null \
				and client.game.rig.clamp_look_at(escape_view,true)==escape_view
		var barrier:GameUnit=host.world.units.get(1001009)
		saw_barrier_dead=saw_barrier_dead or barrier==null or barrier.dead
		var guest:=visitor()
		if guest:saw_guest_run=saw_guest_run or guest.order.get("story_move",false) or guest.orders.any(func(o):return o.get("story_move",false))
		var party:=host.world.party_units()
		var clear:=party.all(func(u):return not u.dead and u.pos.y<84.)
		saw_party_clear=saw_party_clear or clear
		if host.world.units.has(666666):
			if not saw_terror:early_terror=not clear or (guest!=null and guest.pos.y>=80.)
			saw_terror=true
		if (saw_terror if reactive else saw_party_clear) and not run_sent:
			# The original scene fires at Kir after staging. Issue the same
			# ordinary run-away input as the earlier single-player playthrough.
			for s:Session in ([host] if idle_guest else [host,client]):
				var us:=s.party_units(s.my_index)
				s.submit({"t":"move","units":us.map(func(u):return u.uid),"x":400.0,"y":77.0-s.my_index*2,"run":true})
			run_sent=true
			print("ESCAPE_RUN ",host.world.time," ",party.map(func(u):return [u.uid,u.pos,u.hp,u.speed(),u.order,u.orders]))
		if Time.get_ticks_msec()>last_trace+10000:
			last_trace=Time.get_ticks_msec();print("ESCAPE_TRACE ",party.map(func(u):return [u.uid,u.pos,u.hp,u.order])," barrier=",barrier.hp if barrier else -1," brief=",host.world.vm.briefings.active)
	if not travel_sent and host.travel_options.any(func(o):return o.zone=="gz1h"):
		var option:Dictionary=host.travel_options.filter(func(o):return o.zone=="gz1h")[0]
		travel_sent=true;print("ESCAPE_TRAVEL ",option)
		host.submit({"t":"travel","zone":"gz1h","entrance":option.entrance})

func finish()->void:
	automate=false
	for s:Session in [client,host]:
		if is_instance_valid(s):
			s.online=false
			if s.multiplayer.multiplayer_peer:s.multiplayer.multiplayer_peer.close()
	for root:Node in branches:
		if is_instance_valid(root):root.queue_free()
	await frames(8)
	print("SLAVE_ESCAPE_PLAY_NET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

extends "coop_story.gd"
## A real ENet client issues direct-control commands to another session. No
## client supplied target/damage is trusted; generation and ownership apply.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(n := 12) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":1},true)
	var h := branch("Host",true);host=h.s;hg=h.g
	var c := branch("Guest",false);client=c.s;cg=c.g
	require(host.host(29917,2)==OK)
	GameData.player_name="Direct Guest"
	require(client.join("127.0.0.1",29917)==OK)
	require(await until(func():return host.players.size()==2 and client.my_index==1))
	host.set_physics_process(false);client.set_physics_process(false)
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Direct Guest")
	await host.enter_zone("bz1g",1,false)
	host.world.set_physics_process(false);host.world.set_process(false);host.world.vm.instances.clear()
	require(await until(func():return client.zone_id=="bz1g" and not client.loading_game and not host.loading_game))
	client.world.set_physics_process(false)
	var own: GameUnit=host.party_units(0)[0]
	var guest: GameUnit=host.party_units(1)[0]
	guest.blocked=false;guest.order={};guest.orders.clear();guest._anim_lock=0;guest._attack_cd=0
	client.submit({"t":"direct_control","leader":guest.uid});await frames()
	check(guest.direct_controlled and not own.direct_controlled,"client enables manual control only for its hero")
	client.submit({"t":"direct_look","units":[guest.uid],"heading":1.2});await frames()
	check(is_equal_approx(guest.direct_heading,1.2),"guest look rotation reaches the authority")
	client.submit({"t":"direct_look","units":[own.uid],"heading":2.4});await frames()
	check(is_nan(own.direct_heading),"network look cannot rotate another player's body")
	client.submit({"t":"direct_move","units":[guest.uid],"direction":Vector2(0.4,0.2)});await frames()
	check(not guest.direct_steering.is_empty() and guest.direct_steering.direction==Vector2(0.4,0.2),"network steering preserves analog input at authority")
	check(not guest.direct_steering.is_empty() and guest.direct_steering.village_limit==host.village_move_limit(),"network steering retains village boundary")
	var kept:=own.orders.duplicate(true)
	client.submit({"t":"direct_move","units":[own.uid],"direction":Vector2.RIGHT});await frames()
	check(own.orders==kept,"network steering cannot take over the host hero")
	client.submit({"t":"direct_move","units":[guest.uid],"direction":Vector2.ZERO});await frames()
	check(guest.orders.is_empty() and guest.direct_steering.is_empty(),"network release clears pending steering")
	guest.command({"type":"wait","t":2.0})
	client.submit({"t":"direct_move","units":[guest.uid],"direction":Vector2.ZERO});await frames()
	check(guest.orders.size()==1 and guest.orders[0].type=="wait","late network release preserves an unrelated new order")
	guest.orders.clear()
	client._rpc_cmd.rpc_id(1,{"t":"direct_move","units":[guest.uid],"direction":Vector2.RIGHT,
		"_zone":"bz1g","_generation":host._load_serial-1});await frames()
	check(guest.orders.is_empty(),"old load generation cannot steer current hero")
	client.submit({"t":"direct_control","leader":own.uid});await frames()
	check(not own.direct_controlled and not guest.direct_controlled,"client cannot seize the host hero")
	client.submit({"t":"direct_attack","units":[guest.uid],"direction":Vector3.RIGHT});await frames()
	check(guest.orders.is_empty(),"authority rejects guest direct attack in the real village")
	guest.orders.clear()
	# Send a valid known spell through the direct-cast alias too, so the
	# safe-zone check, not the spell/ownership validator, must refuse it.
	var spell := "healing{}"
	guest.get_meta("hero").spells.append(spell)
	client.submit({"t":"direct_cast","unit":guest.uid,"spell":spell,"target":guest.uid});await frames()
	check(guest.orders.is_empty(),"authority rejects guest third-person spell in the real village")
	guest.orders.clear()
	client.submit({"t":"attack","units":[guest.uid],"target":own.uid});await frames()
	check(guest.orders.is_empty(),"classic attack stays blocked in the same village")
	await host.enter_zone("gz1g",1,false)
	host.world.set_physics_process(false);host.world.set_process(false);host.world.vm.instances.clear()
	require(await until(func():return client.zone_id=="gz1g" and not client.loading_game and not host.loading_game \
		and not client._remote_loading and not client._zone_holding and client._pool_epoch==host._load_serial))
	client.world.set_physics_process(false)
	own=host.party_units(0)[0];guest=host.party_units(1)[0]
	guest.blocked=false;guest.order={};guest.orders.clear();guest._anim_lock=0;guest._attack_cd=0
	client.submit({"t":"direct_attack","units":[guest.uid],"direction":Vector3.RIGHT});await frames()
	check(guest.orders.size()==1 and guest.orders[0].type=="direct_attack","guest direction attack reaches authority in the field")
	check(not guest.orders.is_empty() and guest.orders[0].get("direction")==Vector3.RIGHT,"authority preserves normalized aim")
	guest.orders.clear()
	var own_orders := own.orders.duplicate(true)
	client.submit({"t":"direct_attack","units":[own.uid],"direction":Vector3.RIGHT});await frames()
	check(own.orders == own_orders,"foreign-unit direct attack cannot replace the host's arrival orders")
	client._rpc_cmd.rpc_id(1,{"t":"direct_attack","units":[guest.uid],"direction":Vector3.RIGHT,
		"_zone":"gz1g","_generation":host._load_serial-1});await frames()
	check(guest.orders.is_empty(),"previous load generation cannot attack in current area")
	guest.blocked=true
	client.submit({"t":"direct_attack","units":[guest.uid],"direction":Vector3.RIGHT});await frames()
	check(guest.orders.is_empty(),"script trap/blocked actor refuses network attack")
	guest.blocked=false
	client.submit({"t":"direct_attack","units":[guest.uid],"direction":Vector3(NAN,0,0)});await frames()
	check(guest.orders.is_empty(),"non-finite aim is rejected over network")
	# The guest's distant ground cast must not turn into an approach on the
	# authority. A nearby cast still executes and spends native stamina.
	var caster: Dictionary = guest.get_meta("hero")
	caster.spells=["fireworks{}"];caster.skills={"sense":100};caster.int=25.0
	Combat.hero_stats(guest,caster)
	for distance: float in [10.0,35.0]:
		guest.order={};guest.orders.clear();guest.path=PackedVector2Array()
		guest._anim_lock=0;guest._pending_hit={};guest._attack_cd=0;guest.action="idle"
		guest.stop_steering();guest.mana=guest.max_mana
		var start:=guest.pos;var mana:=guest.mana;var at:=start+Vector2(distance,0)
		client.submit({"t":"direct_cast","unit":guest.uid,"spell":"fireworks{}","x":at.x,"y":at.y});await frames()
		check(guest.orders.size()==1 and guest.orders[0].get("in_place",false),"network ground spell preserves in-place casting")
		for tick in 60:
			guest._tick(GameUnit.TICK)
			if guest.action.begins_with("cast") or (guest.order.is_empty() and guest.orders.is_empty()):break
		check(guest.pos==start and guest.path.is_empty(),"network ground cast never issues a move")
		check(guest.mana<mana if distance<30 else guest.mana==mana,"network cast spends stamina only within native range")
	guest.order={};guest.orders.clear();guest._anim_lock=0;guest._pending_hit={};guest.action="idle"
	client.submit({"t":"gait","units":[guest.uid],"gait":0});await frames()
	host._send_snapshot_records([guest.snapshot()],host.world.time);await frames()
	check(guest.gait()==0 and client.world.units[guest.uid].gait()==0,"prone posture reaches host and client")
	guest.restore_gait(2);guest._anim_lock=0
	# New projectile event is presentation-only on the client.
	var delivered := {}
	client.world.child_entered_tree.connect(func(n: Node):
		if n is Projectile and n._direct: delivered["hit"] = n.apply_hit)
	host.broadcast({"t":"direct_arrow","a":guest.uid,"direction":Vector3.RIGHT,"start":DirectCombat.origin(guest)})
	check(await until(func():return delivered.has("hit")),"free arrow event reaches the client")
	check(not delivered.get("hit",true),"client arrow cannot deal duplicate damage")
	client.submit({"t":"direct_control","leader":guest.uid});await frames()
	client.submit({"t":"direct_attack","units":[guest.uid],"direction":Vector3.RIGHT});await frames()
	client.submit({"t":"direct_move","units":[guest.uid],"direction":Vector2.UP});await frames()
	check(not guest.direct_steering.is_empty() and guest.orders.any(func(o):return o.type=="direct_attack"),"network movement preserves a buffered attack")
	guest.direct_motion=Vector2(0.05,-0.025);guest._attack_cd=0.75;guest._anim_lock=0.4;guest.direct_hit_serial=9;guest.running=true
	host._send_snapshot_records([guest.snapshot()],host.world.time);await frames()
	var copy:GameUnit=client.world.units[guest.uid]
	check(copy.direct_controlled and copy.direct_motion.distance_to(guest.direct_motion)<0.001 and copy.running,"host replicates moving pose state")
	check(is_equal_approx(copy.direct_recovery,0.75) and copy.direct_hit_serial==9,"host replicates readiness and confirmed hit sequence")
	# A spell can be queued before movement, then keep travelling through
	# the committed cast. The peer receives the same cast and walking pose.
	guest.order={};guest.orders.clear();guest._pending_hit={};guest._anim_lock=0.4
	guest.action="attack";guest.stop_steering();guest.mana=guest.max_mana
	guest.get_meta("hero").spells.append("healing{}")
	guest.get_meta("hero").skills.astral=100
	client.submit({"t":"direct_cast","unit":guest.uid,"spell":"healing{}","target":guest.uid});await frames()
	var direction:=Vector2.RIGHT
	for candidate: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		if host.world.nav.direct_line(guest,guest.pos+candidate): direction=candidate;break
	client.submit({"t":"direct_move","units":[guest.uid],"direction":direction});await frames()
	check(guest.orders.size()==1 and guest.orders[0].type=="cast" and not guest.direct_steering.is_empty(),"network movement preserves a buffered spell")
	for tick in 30:
		guest.tick(GameUnit.TICK)
		if guest.action.begins_with("cast"):break
	check(guest.action.begins_with("cast"),"network spell starts after the previous recovery")
	var cast_position:=guest.pos
	guest.tick(GameUnit.TICK)
	check(guest.pos.distance_to(cast_position)>0.001 and guest._anim_lock>0,"authority moves the guest during a committed cast")
	host._send_snapshot_records([guest.snapshot()],host.world.time);await frames()
	check(copy.action.begins_with("cast") and copy.direct_motion.length()>0 and copy._move_speed>0,"peer receives both casting and movement state")
	if copy._direct_pose: copy._direct_pose.apply_pose(0.2)
	check(copy._direct_pose!=null and copy._direct_pose.weight>0,"peer composes walking legs beneath the casting animation")
	client.submit({"t":"direct_control","leader":-1});await frames()
	host._send_snapshot_records([guest.snapshot()],host.world.time);await frames()
	check(not copy.direct_controlled and copy.direct_motion==Vector2.ZERO,"tactical switch clears replicated direct pose")
	host.online=false;client.online=false
	host.multiplayer.multiplayer_peer.close();client.multiplayer.multiplayer_peer.close()
	for node in branches:node.queue_free()
	await frames()
	print("DIRECT_COOP ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

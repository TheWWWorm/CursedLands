extends Node
## Original barrier-destruction handler with multiple deployed guest heroes.
## Enemy AI is paused to isolate orders, routes and the Terror staging gate.
const P := preload("res://src/game/script/script_parser.gd")
class LocalSession extends Session:
	# The client posture prediction check uses the UI without an ENet peer.
	# Capture its submission; authority behavior is tested separately below.
	var sent: Array = []
	func submit(cmd: Dictionary) -> void:
		if not is_host: sent.append(cmd); return
		super.submit(cmd)
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_directory":0,"net_lan":0},true)
	var s := LocalSession.new(); add_child(s)
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.set_physics_process(false)
	s.players[42] = {"index":1,"name":"Guest One"}; s.players[43] = {"index":2,"name":"Guest Two"}
	s.state = CampaignState.new()
	s.state.create_party("FPrison"); s.state.add_party_unit("FPrison","Hero","Hero1")
	s.state.add_party_unit("FPrison","merc2","merc2")
	s.state.set_current_party("FPrison")
	for i in [1,2]: s.state.ensure_hero(i,"Human Hero","Guest "+str(i))
	s.state.set_var(0,"bz1h_night",2)
	await s.enter_zone("bz1h",1,false)
	var w := s.world; w.set_process(false); w.set_physics_process(false)
	var vm := w.vm; vm.instances.clear()
	var hero: GameUnit = vm._by_name("Hero")
	var kel: GameUnit = vm._by_name("merc2")
	check(hero != null and kel != null,"authored Kir and Kel deployed")
	var guests: Array[GameUnit] = [s.party_units(1)[0],s.party_units(2)[0]]
	for i in guests.size():
		guests[i].pos = Vector2(413.0+i,92.0); guests[i].blocked = false
		guests[i].orders.clear(); guests[i].order = {}
	# A normal first world tick registers every actor's standing footprint.
	# Do the same before pausing NPC AI, or route search sees an empty crowd
	# while the movement collision check still sees the live actors.
	for u: GameUnit in w.unit_rows(): w.nav.track_unit(u)
	var guest := guests[0]
	guest.set_gait(2)
	s.apply_command({"t":"gait","units":[guest.uid],"gait":0},1)
	check(guest.stance == GameUnit.STANCE_NONE,"authority rejects crouch in a safe zone")
	g.selected = [guest]; s.is_host = false
	g.hud.set_move_mode("crawl")
	check(guest.stance == GameUnit.STANCE_NONE,"client does not predict a refused crouch")
	s.is_host = true
	for kind in ["attack","cast","steal","use"]:
		guest.order = {}; guest.orders.clear()
		var spells: Array = guest.get_meta("hero").get("spells",[])
		s.apply_command({"t":kind,"units":[guest.uid],"unit":guest.uid,"target":1001009,
			"spell":spells[0] if not spells.is_empty() else "healing{}"},1)
		check(guest.orders.is_empty(),"authority rejects safe-zone "+kind)
	var limit: Vector3 = w.zone.restrict
	s.apply_command({"t":"move","units":[guest.uid],"x":limit.x+100,"y":limit.y,"line":true},1)
	check(not guest.orders.is_empty() and guest.orders[0].get("village_limit",Vector3.ZERO)==limit \
		and guest.orders[0].to.distance_to(Vector2(limit.x,limit.y))<=limit.z+0.001,"safe-zone move is bounded by the authored village circle")
	if guest.has_method("_outside_village_move"):
		guest.order = guest.orders[0]
		check(guest._outside_village_move(Vector2(limit.x+30,limit.y)),"movement step cannot detour outside the scene boundary")
		var saved_pos := guest.pos; guest.pos = Vector2(limit.x+20,limit.y)
		check(not guest._outside_village_move(Vector2(limit.x+19,limit.y)),"an older outside save can walk back into the village")
		guest.pos = saved_pos
	guest.order = {}; guest.orders.clear()
	var barrier: GameUnit = w.units.get(1001009)
	check(barrier != null,"original camp barrier exists")
	barrier.dead = true
	vm.spawn("VCheck#1#1",[null])
	for i in 20: w.time += GameUnit.TICK; vm.tick(GameUnit.TICK)
	check(not w.units.has(1001009),"original handler removes the destroyed barrier")
	for u in guests:
		check(not u.orders.is_empty() and u.orders[0].get("type","")=="move" and u.orders[0].get("run",false) \
			and u.orders[0].get("story_move",false) and u.orders[0].to.y<84.0,"guest receives the scripted escape run: "+str(u.controller))
	# Old saves waiting here need the missing escape orders restored.
	for u in guests: u.order = {}; u.orders.clear()
	preload("res://src/game/script/story_compat.gd").recover(vm)
	check(guests.all(func(u: GameUnit):return not u.orders.is_empty()),"loading an escape wait restores guest run orders")
	# Host and Kel reaching safety cannot release Terror while guests are
	# still inside. Check the actual parsed predicate, not a duplicate rule.
	hero.pos = Vector2(407,82); kel.pos = Vector2(407,81)
	for u: GameUnit in [hero,kel]:
		u.order = {}; u.orders.clear(); u.path = PackedVector2Array(); w.nav.track_unit(u)
	var conditions: Array = vm.ast.scripts["VCheck#1#1a"].blocks[0].conds
	check(not vm._all(conditions,ScriptVM.Instance.new()),"Terror waits until the guest party clears the barrier")
	for tick in 1000:
		w.time += GameUnit.TICK; w._logic_step += 1
		w.ai.activity.begin_tick(GameUnit.TICK)
		for u in guests: u.tick(GameUnit.TICK)
		w.ai.activity.end_tick()
		if guests.all(func(u: GameUnit):return u.pos.y<84.0): break
	for u in guests:
		if u._motion:
			var next: Dictionary = u._motion.sample(u._motion_tick+1)
			var res := {}
			var blocker := w.nav.step_blocker(u,next.p,res,next.cell)
			print("ESCAPE_BLOCKER ",u.controller," radius=",u.body_radius()," tick=",u._motion_tick," q=",next.p," blocker=",blocker.info.get("name","") if blocker else "none"," ",blocker.pos if blocker else Vector2.ZERO," order=",blocker.order if blocker else {}," ",res)
		print("ESCAPE_ARRIVAL ",u.controller," ",u.pos," ",u.order," pending=",u.orders," avoid=",u._avoid," path=",u.path," waiting=",u._waiting_for())
	check(guests.all(func(u: GameUnit):return u.pos.y<84.0),"both guests actually route through the opened camp barrier")
	check(vm._all(conditions,ScriptVM.Instance.new()),"arrival releases the original Terror sequence")
	guests[0].pos.y = 92; guests[0].dead = true
	check(vm._all(conditions,ScriptVM.Instance.new()),"optional dead guest does not deadlock the story")
	guests[0].dead = false; guests[0].controller = -1
	check(vm._all(conditions,ScriptVM.Instance.new()),"disconnected guest does not deadlock the story")
	g.queue_free(); s.queue_free()
	for i in 8: await get_tree().process_frame
	print("SLAVE_CAMP_ESCAPE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

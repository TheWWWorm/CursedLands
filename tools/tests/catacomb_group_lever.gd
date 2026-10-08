extends Node
## Actual Catacombs geometry, original mover script, ordinary walk/use orders.
## Synthetic party ownership; unrelated actors are held still. This covers a
## blocked selected operator, not large-party platform capacity or an ENet trip.
## Recreate the authored narrow layout even when production widens this lift;
## catacomb_capacity and catacomb_capacity_net cover the new layout separately.
const LIFT := 2240358
const UP := 338779
const DOWN := 1357456
const CALL := 1369841
var s: Session
var g: Game
var riders: Array[GameUnit] = []
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func ticks(n: int) -> void:
	for i in n:
		s.world.vm.tick(GameUnit.TICK)
		s.world.lever_sys.tick()
		s.world.time += GameUnit.TICK
		for u: GameUnit in riders: u.tick(GameUnit.TICK)

func height() -> float:
	return s.world.objects[LIFT].get_meta("ei").position.z

func use(ids: Array, lever: int) -> void:
	s.apply_command({"t":"use_lever", "units":ids, "target":lever}, 0)

func original_layout() -> void:
	var w := s.world
	w.map._relocated_objects.clear()
	var original := EIMob.load_bytes(GameData.read_file("maps/zone1dun2.mob"))
	for info: Dictionary in original.objects:
		var nid := int(info.get("nid",0))
		var old: Node3D = w.objects.get(nid)
		if old == null: continue
		var current: Dictionary = old.get_meta("ei")
		if current.position==info.position and current.complexion==info.complexion: continue
		var saved: Dictionary = w.levers.get(nid,{}).duplicate(true)
		w.nav.remove_object(nid)
		var node := w.map.place_object(info,old.get_parent())
		w.map.object_nodes.erase(old);w.map.object_nodes.append(node)
		old.get_parent().remove_child(old);old.free()
		w._register_object(node)
		if not saved.is_empty():w.levers[nid]=saved
		w.nav.add_object(node)
		if not saved.is_empty():w.lever_sys.add(nid)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	s = Session.new(); add_child(s)
	g = Game.new(); g.session = s; s.game = g; add_child(g)
	s.set_physics_process(false)
	s.state = CampaignState.new(); s.state.ensure_hero(0,"Human Hero")
	s.state.set_var(0,"q.gz1d2.q03h",1)
	await s.enter_zone("gz1d2",1,false)
	var w := s.world
	w.set_process(false); w.set_physics_process(false)
	original_layout()
	ticks(30)
	var lead: GameUnit = s.party_units(0)[0]
	w.vm._use_lever(lead,CALL); ticks(900)
	check(is_equal_approx(height(),28.654),"original call brings platform to the upper landing")
	for n in 3:
		var u := lead
		if n:
			s.state.ensure_hero(n,"Human Hero")
			var r: Dictionary = s.state.party_records(n)[0]
			r.nid = w.new_uid(); r.position = Vector3(30,54,0)
			u = w.spawn_unit(r); u.faction = 0; u.mode = "player"; s.state.apply_hero(u)
		u.controller = 0
		u.pos = Vector2(30+n*1.6,54); u.ai_next = INF; u._perceive_next = INF
		w.nav.track_unit(u); riders.append(u)
	for i in riders.size():
		var dest := Vector2(30.7,63.5-i*1.35)
		riders[i].move_to(dest); ticks(400)
		check(riders[i].pos.distance_to(dest)<0.6,"ordinary movement reaches deck/landing mark "+str(i))
	use([lead.uid],DOWN); ticks(950)
	check(is_equal_approx(height(),-0.3),"single selected actor operates down switch")
	var near := riders[1]
	var waiting := riders[2]
	check(w.ground_at(lead.pos.x,lead.pos.y)<5.0 and w.ground_at(near.pos.x,near.pos.y)<5.0,"two actual riders reach the lower floor")
	check(w.ground_at(waiting.pos.x,waiting.pos.y)>30.0,"character on overlapping fixed landing stays upstairs")
	var ids := [lead.uid,near.uid]
	var lead_at := lead.pos
	var near_at := near.pos
	var waiting_at := waiting.pos
	use([lead.uid],UP); ticks(300)
	check(lead.order_failed and is_equal_approx(height(),-0.3),"lead actor alone cannot pass the other rider to the up switch")
	near.controller = 1
	use(ids,UP); ticks(300)
	check(lead.order_failed and is_equal_approx(height(),-0.3),"host command cannot use another owner's rider")
	check(near.is_idle() and near.pos==near_at,"other owner's rider receives no fallback order")
	near.controller = 0; near.blocked = true
	use(ids,UP); ticks(300)
	check(lead.order_failed and is_equal_approx(height(),-0.3),"blocked selected rider cannot operate the switch")
	near.blocked = false
	var science: Array = w.levers[UP].science.duplicate()
	var dex: float = near.stats.dex
	w.levers[UP].science = [1,0,10]; near.stats.dex = 25.0
	check(Session.steal_value(near)<10.0,"nearby rider lacks the test lock's required skill")
	use(ids,UP)
	check(not near.has_meta("interact") and near.is_idle(),"fallback does not choose an unqualified rider")
	ticks(300)
	check(is_equal_approx(height(),-0.3),"skill gate remains enforced")
	w.levers[UP].science = science; near.stats.dex = dex
	w.levers[UP].enabled = false
	use(ids,UP); ticks(30)
	check(is_equal_approx(height(),-0.3) and near.is_idle(),"disabled switch ignores the group command")
	w.levers[UP].enabled = true
	use(ids,UP)
	check(near.has_meta("interact") and not lead.has_meta("interact"),"reachable qualified rider gets the group interaction")
	ticks(950)
	check(is_equal_approx(height(),28.654),"same group command raises the formerly stuck lift")
	check(lead.pos==lead_at,"fallback leaves the blocked lead rider in place")
	check(waiting.pos==waiting_at and waiting.is_idle(),"unselected character keeps its position and orders")
	check(w.ground_at(lead.pos.x,lead.pos.y)>30.0 and w.ground_at(near.pos.x,near.pos.y)>30.0,"both riders arrive at the upper floor")
	# Return with real commands, then unload in the physical aisle order.
	use(ids,DOWN); ticks(950)
	check(is_equal_approx(height(),-0.3),"group can descend again after the fallback trip")
	for i in 2:
		var dest := Vector2(31+i*1.6,67)
		riders[i].move_to(dest); ticks(400)
		check(riders[i].pos.distance_to(dest)<0.1 and not riders[i].order_failed,"rider walks off the lower platform "+str(i))
	check(w.objects.has(UP) and w.nav._fp.has(UP) and w.lever_sys.usable(UP),"planning preserves the original switch and its navigation footprint")
	g.queue_free(); s.queue_free()
	for i in 8: await get_tree().process_frame
	print("CATACOMB_GROUP_LEVER ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

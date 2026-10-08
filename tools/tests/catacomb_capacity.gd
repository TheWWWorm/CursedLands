extends Node
## Actual production geometry and original mover. Five staged human riders walk
## aboard, use switches and walk off through ordinary orders. Unrelated AI is
## held still. This is a capacity/old-save check, not a full quest playthrough.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
var s: Session
var g: Game
var riders:Array[GameUnit]=[]
func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	g.rig.set_process(false)
	g.rig.set_pose({"at":[30.722,33.5 if label=="top" else 5.0,-62.0],"yaw":PI*.6,"distance":18.,"tilt":0.,"free":true})
	for u:GameUnit in riders:u.resync_drawn()
	for frame in 12:await get_tree().process_frame
	var file:="user://catacomb-boarding-"+label+".png"
	get_viewport().get_texture().get_image().save_png(file)
	print("VIEW ",ProjectSettings.globalize_path(file))
func tick(n: int) -> void:
	for i in n:
		s.world.time += GameUnit.TICK
		s.world.vm.tick(GameUnit.TICK)
		s.world.lever_sys.tick()
		for u:GameUnit in riders:u.tick(GameUnit.TICK)
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	s=Session.new(); add_child(s)
	g=Game.new(); g.session=s; s.game=g; add_child(g)
	s.set_physics_process(false)
	s.state=CampaignState.new(); s.state.ensure_hero(0,"Human Hero")
	s.state.set_var(0,"q.gz1d2.q03h",1)
	await s.enter_zone("gz1d2",1,false)
	var w:=s.world
	w.set_process(false); w.set_physics_process(false)
	tick(30)
	var hero: GameUnit=s.party_units(0)[0]
	hero.ai_next=INF;hero._perceive_next=INF
	print("HERO_SIZE ",hero.body_radius()," use=",hero.use_radius()," pos=",hero.pos)
	w.vm._use_lever(hero,1369841); tick(900)
	check(is_equal_approx(w.objects[2240358].get_meta("ei").position.z,28.654),"original call reaches upper stop")
	check(w.nav._fp[2240358].faces[0].length_b>5.0,"moving floor has usable extra width")
	var slots:Array[Vector2]=[Vector2(32.25,63.25),Vector2(30.75,63.25),Vector2(29.25,63.25),Vector2(32.25,61.75),Vector2(30.75,61.75)]
	for n in mini(5,slots.size()):
		var u:GameUnit=hero
		if n:
			s.state.ensure_hero(n,"Human Hero")
			var r:Dictionary=s.state.party_records(n)[0]
			r.nid=w.new_uid();r.position=Vector3(30,54,0)
			u=w.spawn_unit(r);u.controller=n;u.faction=0;u.mode="player";s.state.apply_hero(u)
		u.controller=0
		u.pos=Vector2(30.+1.5*(n%2),54.-1.5*floori(n/2.));u.ai_next=INF;u._perceive_next=INF
		w.nav.track_unit(u);riders.append(u)
	for i in riders.size():
		var u:=riders[i]
		var dest:=slots[i]
		u.move_to(dest);tick(400)
		print("BOARD ",i," to=",dest," got=",u.pos," floor=",w.ground_at(u.pos.x,u.pos.y)," failed=",u.order_failed," order=",u.order," path=",u.path)
		check(w.ground_at(u.pos.x,u.pos.y)>33.0 and w.ground_at(u.pos.x,u.pos.y)<33.3 and not u.order_failed,"rider walks onto moving deck "+str(i))
	await capture("top")
	var operator:=riders[0]
	s.apply_command({"t":"use_lever","units":riders.map(func(u):return u.uid),"target":1357456},operator.controller)
	tick(950)
	print("DESCEND_REAL ",w.objects[2240358].get_meta("ei").position," lever=",w.levers[1357456]," operator=",operator.pos," failed=",operator.order_failed)
	check(is_equal_approx(w.objects[2240358].get_meta("ei").position.z,-0.3),"selected group operates down switch")
	for i in riders.size():check(w.ground_at(riders[i].pos.x,riders[i].pos.y)<5.0,"rider descends with platform "+str(i))
	await capture("bottom")
	var ids:Array=riders.map(func(u:GameUnit):return u.uid)
	s.apply_command({"t":"use_lever","units":ids,"target":338779},0)
	tick(950)
	print("ASCEND_GROUP ",w.objects[2240358].get_meta("ei").position," lever=",w.levers[338779]," operator=",operator.pos," failed=",operator.order_failed," order=",operator.order," path=",operator.path)
	check(is_equal_approx(w.objects[2240358].get_meta("ei").position.z,28.654),"group raises platform again")
	for i in riders.size():check(w.ground_at(riders[i].pos.x,riders[i].pos.y)>33.0,"rider returns to upper stop "+str(i))
	s.apply_command({"t":"use_lever","units":ids,"target":1357456},0);tick(950)
	s.apply_command({"t":"move","units":ids,"x":31.0,"y":68.0},0);tick(600)
	for i in riders.size():
		var u:=riders[i]
		print("EXIT ",i," got=",u.pos," floor=",w.ground_at(u.pos.x,u.pos.y)," failed=",u.order_failed," order=",u.order," path=",u.path)
	for i in riders.size():
		check(riders[i].pos.distance_to(Vector2(31,68)+Session.group_offset(i))<0.1 and not riders[i].order_failed,"one group click unloads rider "+str(i))
	# Walk back aboard from below, then unload onto the upper landing.
	for i in [4,3,2,0,1]:
		riders[i].move_to(slots[i]);tick(400)
		print("BOARD_BELOW ",i," pos=",riders[i].pos," failed=",riders[i].order_failed)
		check(w.ground_at(riders[i].pos.x,riders[i].pos.y)>4.1,"rider boards again from below "+str(i))
	s.apply_command({"t":"use_lever","units":ids,"target":338779},0);tick(950)
	s.apply_command({"t":"move","units":ids,"x":31.0,"y":50.0},0);tick(600)
	for i in riders.size():
		print("EXIT_TOP ",i," pos=",riders[i].pos," failed=",riders[i].order_failed)
		check(riders[i].pos.y<58.0 and w.ground_at(riders[i].pos.x,riders[i].pos.y)>30.0 and not riders[i].order_failed,"group walks onto upper landing "+str(i))
	# Saved script positions from before the layout change must migrate once.
	check(s.save_game("catacomb_new")==OK,"save actual stopped lift")
	var old:=CampaignState.load_from(SaveInfo.path("catacomb_new"))
	for nid:int in [338779,1357456]:old.zones["gz1d2"].moved[nid][0]+=0.9
	check(old.save(SaveInfo.path("catacomb_old"))==OK,"prepare old-coordinate save")
	check(await s.load_game_shown("catacomb_old"),"reload old-coordinate checkpoint")
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false)
	riders.clear();w=s.world
	for nid:int in [338779,1357456]:
		var now:Vector3=w.objects[nid].get_meta("ei").position
		check(absf(now.x-(28.72972 if nid==338779 else 28.76708))<.001,"old switch coordinates migrate once "+str(nid))
	check(is_equal_approx(w.objects[2240358].get_meta("ei").complexion.y,2.1),"save reload preserves widened figure")
	check(s.save_game("catacomb_migrated")==OK,"resave migrated checkpoint")
	check(await s.load_game_shown("catacomb_migrated"),"reload migrated checkpoint")
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false)
	w=s.world;hero=s.party_units(0)[0];riders.assign([hero]);hero.ai_next=INF;hero._perceive_next=INF
	check(absf(w.objects[338779].get_meta("ei").position.x-28.72972)<.001,"second load does not shift switch again")
	w.vm._use_lever(hero,1357456);tick(950)
	check(is_equal_approx(w.objects[2240358].get_meta("ei").position.z,-0.3),"restored original script still descends")
	w.vm._use_lever(hero,1369841);tick(950)
	check(is_equal_approx(w.objects[2240358].get_meta("ei").position.z,28.654),"fixed upper control still recalls descended lift")
	g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	print("CATACOMB_CAPACITY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

extends Node
## Diagnostic of authored LiA mine routes. No claim of native parity.
var s: Session
var g: Game
var party: Array[GameUnit] = []

func run_route(from: Vector2, to: Vector2, count: int) -> Dictionary:
	var w := s.world
	for i in party.size():
		var u := party[i]
		u.command({"type":"wait","t":0.0}); u.dead=false; u.hp=u.max_hp; u.mana=u.max_mana
		u.ai_next=INF; u._perceive_next=INF
		u.pos=w.nav.nearest_walkable_for(u,from+Vector2(i*1.5,0)) if i<count else Vector2(1+i*3,1)
		u.facing=(to-u.pos).angle(); u._sync_transform(); w.nav.track_unit(u); u.set_gait(3)
	var units := party.slice(0,count)
	var origins := units.map(func(u):return u.pos)
	var start := Time.get_ticks_usec()
	s.apply_command({"t":"move","units":units.map(func(u):return u.uid),"x":to.x,"y":to.y,"run":true},0)
	var command_us := Time.get_ticks_usec()-start
	var trace := []
	for tick in 600:
		w.time+=GameUnit.TICK; w._logic_step+=1
		for u: GameUnit in units: u.tick(GameUnit.TICK)
		if tick%18==0:
			trace.append({"t":tick*GameUnit.TICK,"units":units.map(func(u):return {
				"id":u.uid,"p":[u.pos.x,u.pos.y],"path":u.path.size(),"action":u.action,
				"order":u.order.get("type",""),"failed":u.order_failed,"speed":u._move_speed,
				"motion_tick":u._motion_tick,"motion_duration":u._motion.duration if u._motion else 0.0,
				"waiting":u._waiting_for().uid if u._waiting_for() else 0,"moving":u._moving,
				"mana":u.mana,"hp":u.hp})})
			await get_tree().process_frame
		if units.all(func(u):return u.is_idle()):break
	var row := {"from":str(from),"to":str(to),"party_size":count,"origins":str(origins),
		"command_us":command_us,"wall_us":Time.get_ticks_usec()-start,"trace":trace,
		"end":units.map(func(u):return {"p":[u.pos.x,u.pos.y],"remaining":u.pos.distance_to(to),"failed":u.order_failed})}
	row.stuck=[]
	for u: GameUnit in units:
		if u._motion==null:continue
		var next:Dictionary=u._motion.sample(u._motion_tick+1)
		var result:Dictionary={}
		var blocker:=w.nav.step_blocker(u,next.p,result,next.cell)
		row.stuck.append({"id":u.uid,"pos":str(u.pos),"next":str(next),"result":result,
			"blocker":blocker.uid if blocker else 0,"radius":u.body_radius(),"path":str(u.path),
			"neighbors":w.nav.units_around(u.pos,4).map(func(v):return {"id":v.uid,"p":str(v.pos),"moving":v._moving,
				"occ_cell":str(v._occ_cell),"occ_radius":v._occ_r,"radius":v.body_radius(),"mode":v.mode,"action":v.action,
				"name":v.proto.get("name",""),"order":v.order.get("type","")})})
	print("MINE_ROUTE ",str(from)," -> ",str(to)," count=",count," ",row.end)
	return row

func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"free_run":1,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"net_upnp":0,"net_lan":0,"net_directory":0},true)
	s=Session.new();add_child(s);s.set_physics_process(false)
	g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz24k",1,false)
	var w := s.world
	w.set_process(false); w.set_physics_process(false)
	# This direct-step probe freezes the world before its first housekeeping
	# tick. Initialize every authored actor's occupancy, as that tick does.
	for u:GameUnit in w.unit_rows():w.nav.track_unit(u)
	var hero: GameUnit=s.party_units(0)[0]
	party.append(hero)
	for n in [1,2]:
		s.state.ensure_hero(n,"Human Hero")
		var r: Dictionary=s.state.party_records(n)[0]
		r.nid=w.new_uid();r.position=Vector3(15+n*2,35,0)
		var u:=w.spawn_unit(r);u.faction=0;u.mode="player";u.controller=n;s.state.apply_hero(u);u.controller=0
		party.append(u)
	var rows := []
	var routes := [[Vector2(114,20),Vector2(90,60)],[Vector2(40,151),Vector2(72,164)],
		[Vector2(72,164),Vector2(40,151)],[Vector2(30,102),Vector2(88,120)],
		[Vector2(85,75),Vector2(85,115)]]
	if OS.get_cmdline_user_args().has("--last-route"):routes=routes.slice(4)
	for route in routes:
		for count in [1,3]:rows.append(await run_route(route[0],route[1],count))
	FileAccess.open("user://mine-party-probe.json",FileAccess.WRITE).store_string(JSON.stringify({"zone":s.zone_id,"population":w.units.size(),"rows":rows},"\t"))
	g.queue_free();s.queue_free()
	for i in 6:await get_tree().process_frame
	TexUpscale.shutdown();get_tree().quit()

extends Node
## Actual separate LocalHost authority and slot-zero ENet frontend.
## Original selected MP character -> authored Ingos -> Royal Deer -> Ingos.
var checks := 0
var failures := 0
var session: ObservedSession
var game: Game
var worker_pid := -1
var report := {}
const SEATS := [420812,137765,506671]

class ObservedSession extends Session:
	var record := false
	var snapshots := []
	func _apply_snap(snaps: Array,t: float,serial := -1) -> void:
		if record and world and not _zone_holding and not _remote_loading:
			for sn: Array in snaps:
				if int(sn[0]) in [420812,137765,506671]:
					snapshots.append([Time.get_ticks_msec(),t,serial,int(sn[0]),String(sn[4]),int(sn[14])])
		super._apply_snap(snaps,t,serial)

func check(ok: bool,label: String) -> bool:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
	return ok

func until(predicate: Callable,seconds := 45.0) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func ready_zone(id: String) -> bool:
	return session.zone_id==id and session.world!=null and not session._remote_loading and not session._zone_holding and not session.loading_game

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("user://"+label+".png")==OK,"capture "+label)

func pose_run() -> void:
	var seats:={}
	for id: int in SEATS:
		var u: GameUnit=session.world.units.get(id)
		if not check(u!=null and u.model!=null,"replica has original seated NPC "+str(id)): continue
		seats[str(id)]={"started":false,"idle_frames":0,"frames":0,"serials":{},"events":[],"last_action":"", "last_clip":"", "last_serial":-1,
			"position":str(u.pos),"initial_position":u.pos}
	check(not UnitFog.sight_active(session),"original village remains fully visible")
	game.rig.focus((session.world.units[420812] as GameUnit).global_position)
	game.rig.distance=14.0
	session.record=true
	var start:=Time.get_ticks_msec()
	while Time.get_ticks_msec()<start+14500:
		for id: int in SEATS:
			var u: GameUnit=session.world.units[id];var row: Dictionary=seats[str(id)]
			if u.action.begins_with("anim:"): row.started=true; row.serials[str(u._remote_action_serial)]=true
			if row.started and u.action=="idle": row.idle_frames+=1
			row.frames+=1
			if u.action!=row.last_action or u.model._current!=row.last_clip or u._remote_action_serial!=row.last_serial:
				row.events.append({"elapsed_ms":Time.get_ticks_msec()-start,"authority_time":session.world.time,
					"action":u.action,"clip":u.model._current,"serial":u._remote_action_serial,
					"playing":u.model.player.is_playing(),"animation_position":u.model.player.current_animation_position})
				row.last_action=u.action;row.last_clip=u.model._current;row.last_serial=u._remote_action_serial
		await get_tree().process_frame
	session.record=false
	for id: int in SEATS:
		var u: GameUnit=session.world.units[id];var row: Dictionary=seats[str(id)]
		check(row.serials.size()>=2,"real ENet conveys new seated events "+str(id))
		check(row.idle_frames==0,"host frontend has no standing frame between seated repeats "+str(id))
		check(u.pos==row.initial_position,"host frontend retains authored seat "+str(id))
		row.erase("initial_position")
	report.seats=seats;report.snapshots=session.snapshots
	await capture("ingos-seated-host")

func visibility() -> void:
	check(UnitFog.sight_active(session),"original multiplayer quest sight is active")
	var hero: GameUnit=game.my_units()[0]
	game.rig.focus(hero.global_position); game.rig.distance=CameraRig.M_DEFAULT_DISTANCE
	var fog: UnitFog=game.get_node("UnitFog")
	fog._t=0.0;fog._process(0.0)
	var noticed:={}
	for u: GameUnit in UnitFog.noticed_for(session,0,true): noticed[u.uid]=true
	var far:=[];var near:=[];var bad:=[];var labels:=[]
	var r:=UnitFog.range_of(hero)
	var always:=UnitFog.always_for(session,0)
	var count:=session.world.units.size()
	for u: GameUnit in session.world.unit_rows():
		if u.controller>=0 or u.hidden or u.dead: continue
		var distance:=u.pos.distance_to(hero.pos)
		var data:={"uid":u.uid,"name":u.info.get("name",""),"prototype":u.info.get("prototype",""),
			"position":str(u.pos),"distance":distance,"visible":u.visible,"fogged":u.fogged,
			"minimap_listed":UnitFog.listed(game,u),"noticed":noticed.has(u.uid),"authority_retained":always.has(u.uid)}
		if distance>r*2.0 and not noticed.has(u.uid):
			far.append(data)
			if u.visible or UnitFog.listed(game,u): bad.append(u.uid)
			if not always.has(u.uid): labels.append(u.uid)
		elif distance<r*0.9:
			near.append(data)
	check(far.size()>20,"Royal Deer has non-vacuous far authored NPC witnesses")
	check(bad.is_empty(),"far unnoticed NPCs are absent from world and minimap")
	check(labels.is_empty(),"named NPC authority/relevance registration remains available")
	check(not near.is_empty(),"Royal Deer has nearby non-party NPC witnesses")
	check(near.all(func(x):return x.visible and x.minimap_listed),"nearby NPCs remain visible in world and minimap")
	check(hero.visible and UnitFog.listed(game,hero),"local party remains visible")
	check(session.world.units.size()==count,"visibility leaves replicated unit population intact")
	report.visibility={"zone":session.world.zone,"party_position":str(hero.pos),"range":r,"population":count,"far":far,"near":near,"bad_uids":bad}
	await capture("royal-deer-host")

func finish() -> void:
	if session and session.local_host.frontend: await session.local_host.stop()
	if session: check(not session.local_host._process_alive(),"separate native multiplayer authority exits")
	report.merge({"checks":checks,"failures":failures,"worker_pid":worker_pid,
		"scope":"Linux actual LocalHost authority and slot-zero ENet frontend using original native multiplayer. Authored Ingos ambient timeline and Royal Deer entrance visibility; no Windows/WAN claim.",
		"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method()},true)
	FileAccess.open("user://lmp-host-view.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("LMP_HOST_VIEW ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,
		"auto_graphics":0,"unit_fog":1,"show_tutorial":0,"scroll_border":0,"confine_mouse":0,"q_aa":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	Engine.max_fps=60
	if not check(GameData.use_lmp_database(true),"original multiplayer database loads"): await finish();return
	var character:=MpCharacter.create(String(MpCharacter.faces()[1][0]))
	character.heroes[0].name="Owner view probe";MpCharacter.finish(character,"","","")
	check(MpCharacter.save_file("1.mp",character),"disposable native character saved")
	MpCharacter.select("1.mp");GameData.use_lmp_database(false)
	session=ObservedSession.new();get_parent().add_child(session);get_parent().session=session
	game=Game.new();game.session=session;session.game=game;get_parent().add_child(game);get_parent().game=game
	if not check(await session.local_host.start(31062,2,false)==OK,"start real native host worker"): await finish();return
	worker_pid=session.local_host.process_id;print("LMP_VIEW_WORKER ",worker_pid)
	var answer:=await session.local_host.request("lmp",{"base":"bz2mpg","quest":"z13q3"})
	if not check(answer.get("ok",false),"worker accepts native Ingos Royal Deer session"): await finish();return
	if not check(await until(func():return ready_zone("bz2mpg")),"host frontend receives original Ingos"):await finish();return
	check(session.local_host.frontend and not session.world.authority and session.my_index==0,"hosting owner is a slot-zero replicated frontend")
	await pose_run()
	session.submit({"t":"travel","zone":"z13q3","entrance":1})
	if not check(await until(func():return ready_zone("z13q3")),"native travel delivers Royal Deer"):await finish();return
	await get_tree().create_timer(0.4).timeout
	await visibility()
	session.submit({"t":"travel","zone":"bz2mpg","entrance":1})
	check(await until(func():return ready_zone("bz2mpg")),"native owner returns to Ingos")
	await finish()

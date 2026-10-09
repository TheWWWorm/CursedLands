extends Node
## Live authored Portal simulation in the ordinary separate LocalHost service,
## with protocol-matched owner/guest ENet frontends. Observation only: no AI,
## health, script, population, snapshot cadence or interpolation substitutions.
## --seconds=120 --speeds=1,2 --route-save=/absolute/disposable/source.sav
## Both views remain active; rendered runs explicitly draw the guest viewport.
const ROUTE := [Vector2(255.67,58.75),Vector2(255.69,66.75),Vector2(255.67,58.75),Vector2(255.65,50.75)]
const MOVING := ["walk","run","crawl"]
var checks := 0
var failures := 0
var seconds := 120.0
var speeds := [1,2]
var source := ""
var host: ObservedSession
var guest: ObservedSession
var hg: Game
var gg: Game
var viewport: SubViewport
var runs := []
var work := {}
var worker_pid := -1


class ObservedSession extends Session:
	var recording := false
	var started := 0
	var watched := {}
	var packets := []
	var actors := []
	var observed_us := 0
	func begin(at: int, ids: Array) -> void:
		started=at; packets.clear(); actors.clear(); watched.clear(); observed_us=0
		for uid in ids: watched[int(uid)]=true
		recording=true
	func _apply_snap(snaps: Array,t: float,serial := -1) -> void:
		if recording and world!=null and not _zone_holding and not _remote_loading:
			var start := Time.get_ticks_usec()
			var now := Time.get_ticks_msec()-started
			packets.append([now,t,serial,var_to_bytes(snaps).size(),snaps.size()])
			for sn: Array in snaps:
				if watched.has(int(sn[0])):
					actors.append([now,int(sn[0]),serial,t,float(sn[1]),float(sn[2]),String(sn[4])])
			observed_us+=Time.get_ticks_usec()-start
		super._apply_snap(snaps,t,serial)


func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS ",label)
	else: failures+=1; printerr("FAIL ",label)


func until(predicate: Callable,limit := 120.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(limit*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())


func wait_real(t: float) -> void:
	await get_tree().create_timer(t,true,false,true).timeout


func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0,"p50":0,"p95":0,"p99":0,"max":0,"sum":0}
	var sorted := values.duplicate(); sorted.sort()
	return {"count":values.size(),"p50":sorted[values.size()/2],"p95":sorted[mini(values.size()-1,int(values.size()*0.95))],
		"p99":sorted[mini(values.size()-1,int(values.size()*0.99))],"max":sorted[-1],
		"sum":values.reduce(func(total,n):return total+n,0)}


func actor_state(u: GameUnit) -> Dictionary:
	return {"uid":u.uid,"owner":u.controller,"hp":u.hp,"dead":u.dead,"action":u.action,
		"pos":[u.pos.x,u.pos.y],"drawn":[u._drawn.x,u._drawn.y],"visible":u.is_visible_in_tree(),
		"model":u.model!=null,"sleeping":u._presentation_sleeping}


func peer_stats(s: Session) -> Dictionary:
	var enet := NetSim.enet_of(s.multiplayer)
	if enet==null or not 1 in s.multiplayer.get_peers(): return {}
	var peer := enet.get_peer(1)
	return {"rtt_ms":peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
		"rtt_variance_ms":peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE),
		"outbound_loss_scaled":peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS),
		"loss_scale":ENetPacketPeer.PACKET_LOSS_SCALE}


func census(ms: int) -> Dictionary:
	var moving := 0; var fighting := 0; var dead := 0; var visible := 0
	for u: GameUnit in guest.world.unit_rows():
		if u.action in MOVING: moving+=1
		if u.action.begins_with("attack") or u.action.begins_with("cast") or u.action=="hit": fighting+=1
		if u.dead: dead+=1
		if u.is_visible_in_tree() and u.model and u.model.is_visible_in_tree(): visible+=1
	var party := []
	for u: GameUnit in guest.world.party_units(): party.append(actor_state(u))
	return {"wall_ms":ms,"replicated_authority_time":guest.world.time,"units":guest.world.units.size(),
		"moving":moving,"fighting":fighting,"dead":dead,"visible_models":visible,"party":party,
		"host_peer":peer_stats(host),"guest_peer":peer_stats(guest)}


func follow() -> void:
	for row: Array in [[host,hg,0],[guest,gg,1]]:
		var units: Array=row[0].party_units(row[2])
		if not units.is_empty(): row[1].rig.focus((units[0] as GameUnit).global_position)


func move_party(s: Session,owner: int,target: Vector2,ms: int) -> void:
	var i := 0
	for u: GameUnit in s.party_units(owner):
		if u.dead: continue
		var at := target+Vector2(float(owner)*1.5+float(i)*1.2,0)
		s.submit({"t":"move","units":[u.uid],"x":at.x,"y":at.y,"run":true})
		work.commands.append({"wall_ms":ms,"owner":owner,"uid":u.uid,"from":[u.pos.x,u.pos.y],"to":[at.x,at.y]})
		i+=1


func move_guest(target: Vector2,ms: int) -> void:
	# A newly joined guest occupies the map's own entrance, not the saved
	# owner's checkpoint. Exercise its local authored ground with the normal
	# controller path helper; never teleport it across the populated map.
	var pad := gg.get_node("PadField") as PadField
	for u: GameUnit in guest.party_units(1):
		if u.dead: continue
		var at := u.pos
		if u.pos.distance_to(target)>0.35: at=pad._walk_goal(u,(target-u.pos).normalized())
		guest.submit({"t":"move","units":[u.uid],"x":at.x,"y":at.y,"line":true,"run":false})
		work.commands.append({"wall_ms":ms,"owner":1,"uid":u.uid,"from":[u.pos.x,u.pos.y],"to":[at.x,at.y],"route":"guest entrance controller loop"})


func sample_actor(u: GameUnit,reference: GameUnit,dt_ms: int,view: String) -> void:
	var key := "%s:%d"%[view,u.uid]
	if not work.motion.has(key):
		work.motion[key]={"uid":u.uid,"view":view,"owner":u.controller,"distance":0.0,"draw_distance":0.0,
			"max_draw_step":0.0,"max_pending":0.0,"pending_freeze_ms":0,"max_pending_freeze_ms":0,
			"walk_stationary_ms":0,"max_walk_stationary_ms":0,"stop_mismatch_ms":0,"max_stop_mismatch_ms":0,
			"dead_frames":0,"visible_model_frames":0,"frames":0,"last_pos":u.pos,"last_draw":u._drawn}
	var m: Dictionary=work.motion[key]
	var move := u.pos.distance_to(m.last_pos); var drawn := u._drawn.distance_to(m.last_draw)
	m.distance+=move; m.draw_distance+=drawn; m.max_draw_step=maxf(m.max_draw_step,drawn)
	var pending := u.pos.distance_to(u._drawn); m.max_pending=maxf(m.max_pending,pending)
	m.pending_freeze_ms=int(m.pending_freeze_ms)+dt_ms if pending>0.10 and drawn<0.00001 else 0
	m.max_pending_freeze_ms=maxi(m.max_pending_freeze_ms,m.pending_freeze_ms)
	m.walk_stationary_ms=int(m.walk_stationary_ms)+dt_ms if u.action in MOVING and drawn<0.00001 else 0
	m.max_walk_stationary_ms=maxi(m.max_walk_stationary_ms,m.walk_stationary_ms)
	var stale_stop := reference!=null and u.action in MOVING and not reference.action in MOVING and u.pos.distance_to(reference.pos)<0.20
	m.stop_mismatch_ms=int(m.stop_mismatch_ms)+dt_ms if stale_stop else 0
	m.max_stop_mismatch_ms=maxi(m.max_stop_mismatch_ms,m.stop_mismatch_ms)
	if u.dead: m.dead_frames+=1
	if u.model and u.is_visible_in_tree() and u.model.is_visible_in_tree(): m.visible_model_frames+=1
	m.frames+=1; m.last_pos=u.pos; m.last_draw=u._drawn


func stream_summary(s: ObservedSession,uid: int) -> Dictionary:
	var packets := s.actors.filter(func(r):return int(r[1])==uid)
	var gaps := []; var serials := {}; var duplicate := 0; var reordered := 0; var last_serial := -1
	for i in packets.size():
		var r: Array=packets[i]
		if i>0: gaps.append(int(r[0])-int(packets[i-1][0]))
		if serials.has(int(r[2])): duplicate+=1
		elif int(r[2])<last_serial: reordered+=1
		serials[int(r[2])]=true; last_serial=maxi(last_serial,int(r[2]))
	var payloads := s.packets.map(func(r):return int(r[3]))
	var progress := float(packets[-1][3])-float(packets[0][3]) if packets.size()>1 else 0.0
	return {"party_uid":uid,"party_updates":packets.size(),"party_arrival_gap_ms":stats(gaps),
		"initial_silence_ms":packets[0][0] if not packets.is_empty() else int(seconds*1000),
		"trailing_silence_ms":maxi(0,int(seconds*1000)-int(packets[-1][0])) if not packets.is_empty() else int(seconds*1000),
		"gaps_over_250ms":gaps.filter(func(n):return n>250).size(),"gaps_over_500ms":gaps.filter(func(n):return n>500).size(),
		"gaps_over_1000ms":gaps.filter(func(n):return n>1000).size(),"duplicates":duplicate,"reordered":reordered,
		"authority_snapshot_seconds":progress,"authority_completed_55ms_ticks":roundi(progress/GameUnit.TICK),
		"received_snapshot_payload_bytes":stats(payloads),"observer_usec":s.observed_us}


func paired_loss(uid: int) -> Dictionary:
	# The owner-only fast stream contains only slot-zero actors. The selected
	# guest actor identifies ordinary broadcasts received by both frontends;
	# raw global-serial gaps cannot measure loss because streams interleave.
	var a := {}; var b := {}
	for r: Array in host.actors:
		if int(r[1])==uid and int(r[0])>=1000 and int(r[0])<=int(seconds*1000)-1000: a[int(r[2])]=true
	for r: Array in guest.actors:
		if int(r[1])==uid and int(r[0])>=1000 and int(r[0])<=int(seconds*1000)-1000: b[int(r[2])]=true
	var all_ids := a.keys()+b.keys(); all_ids.sort()
	if all_ids.is_empty(): return {}
	var low := maxi(int(a.keys().min()) if not a.is_empty() else 0,int(b.keys().min()) if not b.is_empty() else 0)
	var high := mini(int(a.keys().max()) if not a.is_empty() else 0,int(b.keys().max()) if not b.is_empty() else 0)
	var missing_guest := []; var missing_host := []; var common := 0
	for id: int in a:
		if id<low or id>high: continue
		if b.has(id): common+=1
		else: missing_guest.append(id)
	for id: int in b:
		if id>=low and id<=high and not a.has(id): missing_host.append(id)
	return {"common_guest_actor_broadcasts":common,"absent_at_guest_seen_by_owner":missing_guest,
		"absent_at_owner_seen_by_guest":missing_host,"serial_range":[low,high],
		"limit":"Paired observed broadcasts only; loss to both receivers is unobservable. ENet loss statistic is outbound, not snapshot loss."}


func captures(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	for pair: Array in [[get_viewport(),"owner"],[viewport,"guest"]]:
		check(pair[0].get_texture().get_image().save_png("user://transport-"+label+"-"+pair[1]+".png")==OK,"capture "+label+" "+pair[1])


func phase(sector: int) -> void:
	check(await host.load_game_shown("transport_source"),"load untouched authored Portal save at %dx"%sector)
	check(await until(func():return guest.zone_id=="gz1h" and host.zone_id=="gz1h" and not guest._remote_loading and not guest.loading_game and not host._remote_loading and not host.loading_game and not guest.party_units(1).is_empty()),"both peers reach Portal at %dx"%sector)
	if failures: return
	check(host.world.units.size()>=400 and guest.world.units.size()>=400,"authored busy population retained at %dx"%sector)
	check(host.local_host.frontend and not host.local_host.single_player and not host.world.authority and not guest.world.authority,"real worker owns simulation and both views are co-op replicas")
	check(host.my_index==0 and guest.my_index==1 and host.players.size()==2 and guest.players.size()==2,"protocol13 owner and guest have distinct live slots")
	await host.local_host.request("clock",{"sector":sector})
	hg.rig.distance=CameraRig.M_DEFAULT_DISTANCE; gg.rig.distance=CameraRig.M_DEFAULT_DISTANCE
	work={"commands":[],"motion":{},"census":[],"frame_ms":[]}
	follow(); await wait_real(2.0); follow()
	Engine.max_fps=60
	await captures("%dx-start"%sector)
	var ids := []
	for u: GameUnit in guest.world.party_units(): ids.append(u.uid)
	var target_uid: int=guest.party_units(1)[0].uid
	var guest_anchor: Vector2=guest.party_units(1)[0].pos
	var started := Time.get_ticks_msec(); var previous := started; var next_census := started
	var next_move := started; var next_guest_move := started; var next_notice := started+10000; var route_index := 0
	host.begin(started,ids); guest.begin(started,ids)
	print("SUSTAINED_BEGIN ",JSON.stringify({"speed":sector,"seconds":seconds,"zone":guest.zone_id,"population":guest.world.units.size(),"guest_uid":target_uid,"party":census(0).party}))
	while Time.get_ticks_msec()<started+int(seconds*1000):
		var now := Time.get_ticks_msec(); var elapsed := now-started; var dt := now-previous
		if dt>0: work.frame_ms.append(dt)
		previous=now
		if now>=next_move:
			# Fixed ordinary entrance loop used by existing long-play fixtures.
			# Speed-adjusted cadence keeps both speeds actively issuing routes.
			next_move=now+int(6000.0/sector)
			move_party(host,0,ROUTE[route_index],elapsed)
			route_index=(route_index+1)%ROUTE.size()
		if now>=next_guest_move:
			next_guest_move=now+400
			var leg := int(elapsed*sector/6000)%4
			var offset: float=[8.0,0.0,-8.0,0.0][leg]
			move_guest(guest_anchor+Vector2(offset,0),elapsed)
		for u: GameUnit in guest.world.party_units(): sample_actor(u,host.world.units.get(u.uid),dt,"guest")
		for u: GameUnit in host.world.party_units(): sample_actor(u,guest.world.units.get(u.uid),dt,"owner")
		follow()
		if now>=next_census:
			next_census=now+1000; work.census.append(census(elapsed))
		if now>=next_notice:
			next_notice=now+10000
			print("SUSTAINED_PROGRESS ",JSON.stringify({"speed":sector,"wall_ms":elapsed,"authority_time":guest.world.time,"party":work.census[-1].party}))
		await get_tree().process_frame
	host.recording=false; guest.recording=false
	var duration := (Time.get_ticks_msec()-started)/1000.0
	var owner_summary := stream_summary(host,target_uid); var guest_summary := stream_summary(guest,target_uid)
	var loss := paired_loss(target_uid)
	var row := {"speed":sector,"wall_seconds":duration,"owner_observer":owner_summary,"guest":guest_summary,
		"paired_delivery":loss,"motion":work.motion,"census":work.census,"commands":work.commands,
		"frontend_frame_gap_ms":stats(work.frame_ms),"population":guest.world.units.size(),
		"guest_anchor":[guest_anchor.x,guest_anchor.y]}
	for m: Dictionary in work.motion.values(): m.erase("last_pos"); m.erase("last_draw")
	check(guest_summary.party_updates>seconds*4,"sustained guest snapshots at %dx"%sector)
	check(guest_summary.party_arrival_gap_ms.max<1000 and guest_summary.initial_silence_ms<1000 and guest_summary.trailing_silence_ms<1000,"no multi-second guest snapshot gap at %dx"%sector)
	check(guest_summary.authority_snapshot_seconds>seconds*sector*0.9 and guest_summary.authority_snapshot_seconds<seconds*sector*1.1,"authority advances requested game time at %dx"%sector)
	check(guest_summary.received_snapshot_payload_bytes.max<=Session.SNAP_BYTES+8,"ordinary snapshot payloads retain packet budget at %dx"%sector)
	check(loss.get("absent_at_guest_seen_by_owner",[]).is_empty(),"guest misses no jointly observed loopback party broadcast at %dx"%sector)
	check(row.frontend_frame_gap_ms.max<1000,"no multi-second frontend frame stall at %dx"%sector)
	for m: Dictionary in work.motion.values():
		var label := "%s view actor %d"%[m.view,m.uid]
		check(m.distance>seconds*0.20 and m.draw_distance>seconds*0.20,label+" traverses the authored route")
		check(m.dead_frames==0 and m.visible_model_frames>0,label+" remains alive with a presentable original model")
		check(m.max_pending_freeze_ms<1000,label+" has no long pending presentation freeze")
		check(m.max_stop_mismatch_ms<1000,label+" has no long stale walking pose against the other delivery")
		check(m.max_draw_step<NetSmooth.TELEPORT,label+" has no presentation teleport")
	runs.append(row)
	FileAccess.open("user://transport-%dx-packets.json"%sector,FileAccess.WRITE).store_string(JSON.stringify({"owner":host.packets,"guest":guest.packets,"owner_party":host.actors,"guest_party":guest.actors}))
	await captures("%dx-end"%sector)
	print("SUSTAINED_PHASE ",JSON.stringify({"speed":sector,"guest":guest_summary,"paired_delivery":loss,"motion":work.motion,"frontend_frame_gap_ms":row.frontend_frame_gap_ms}))


func finish() -> void:
	if is_instance_valid(guest):
		var peer := guest.multiplayer.multiplayer_peer
		guest.online=false; guest.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
		if peer: peer.close()
	if is_instance_valid(host):
		await host.local_host.stop()
		check(not host.local_host._process_alive() and (worker_pid<=0 or not OS.is_process_running(worker_pid)),"actual simulation service stops cleanly")
	if viewport: viewport.queue_free()
	if hg: hg.queue_free()
	if host: host.queue_free()
	await wait_real(0.2)
	var report := {"checks":checks,"failures":failures,"network_protocol":NetStatus.PROTOCOL,
		"seconds_per_speed":seconds,"worker_pid":worker_pid,"runs":runs,"options":GameData.options,"renderer":RenderingServer.get_current_rendering_method(),
		"display":DisplayServer.get_name(),"scope":"Linux loopback live simulation service; two frontends share one process. No Windows, WAN or full-playthrough claim."}
	FileAccess.open("user://sustained-coop-delivery.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SUSTAINED_COOP_DELIVERY %d checks %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)


func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds=clampf(float(arg.trim_prefix("--seconds=")),4.0,600.0)
		elif arg.begins_with("--speeds="):
			speeds=[]
			for value in arg.trim_prefix("--speeds=").split(","):
				if int(value) in [1,2]: speeds.append(int(value))
		elif arg.begins_with("--route-save="): source=arg.trim_prefix("--route-save=")
	check(NetStatus.PROTOCOL==13,"all frontend scripts require protocol13")
	check(not source.is_empty() and FileAccess.file_exists(source),"explicit disposable source save exists")
	if failures: await finish(); return
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0,
		"auto_graphics":0,"control_mode":1,"coop_clock":1,"auto_exit":0,"scroll_border":0,"confine_mouse":0,
		"vsync":0,"fps_limit":0,"q_aa":0,"q_shadows":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	Engine.max_fps=60
	host=ObservedSession.new(); get_parent().add_child(host); get_parent().session=host
	hg=Game.new(); hg.session=host; host.game=hg; get_parent().add_child(hg); get_parent().game=hg
	check(await host.local_host.start(29942,2,false)==OK,"start unchanged co-op simulation service")
	worker_pid=host.local_host.process_id
	if failures: await finish(); return
	viewport=SubViewport.new(); viewport.size=Vector2i(1280,720); viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(viewport)
	var api := SceneMultiplayer.new(); api.root_path=viewport.get_path(); get_tree().set_multiplayer(api,viewport.get_path())
	var main := Node.new(); main.name="Main"; viewport.add_child(main)
	guest=ObservedSession.new(); main.add_child(guest)
	gg=Game.new(); gg.session=guest; guest.game=gg; main.add_child(gg)
	GameData.player_name="Sustained Guest"
	check(guest.join("127.0.0.1",29942)==OK,"guest joins actual service by ENet")
	check(await until(func():return guest.my_index==1 and host.players.size()==2),"ordinary authenticated owner/guest connection")
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var f := FileAccess.open(SaveInfo.path("transport_source"),FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(source)); f.close()
	if not failures:
		for sector: int in speeds:
			await phase(sector)
			if failures: break
	await finish()

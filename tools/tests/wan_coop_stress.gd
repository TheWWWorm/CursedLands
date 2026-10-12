extends Node
## Synthetic simultaneous-movement / real UDP impairment qualification.
## Existing NPC orders are replaced, but population, health, AI and native
## navigation remain active. Network impairment is outside Godot/ENet.
## Uses LocalHost owner authentication and lifecycle in a separate service,
## with protocol-matched owner/guest ENet frontends. No health, population,
## simulation cadence, snapshot cadence or interpolation substitutions.
## --seconds=120 --speeds=1,2 --route-save=/absolute/disposable/source.sav
## Both views remain active; rendered runs explicitly draw the guest viewport.
const MOVING := ["walk","run","crawl"]
var checks := 0
var failures := 0
var seconds := 120.0
var speeds := [1,2]
var source := ""
var required_adapter := ""
var renderer_info := {}
var host: ObservedSession
var guest: ObservedSession
var hg: Game
var gg: Game
var viewport: SubViewport
var runs := []
var work := {}
var worker_pid := -1
var stress_plan := {}
var stress_path := ""
var authority_session: Session
var stress_actors := []
var authority_frames := []
var authority_census := []
var command_times := []
var combat_events := 0
var long_routes := {}
var video_frames := []
var video_times := []


class AuthoritySession extends Session:
	var command_receipts := []
	func apply_command(cmd: Dictionary, player: int) -> void:
		if cmd.has("trace_sent_unix"):
			command_receipts.append({"player":player,"delay_ms":(Time.get_unix_time_from_system()-float(cmd.trace_sent_unix))*1000.0})
		super.apply_command(cmd,player)


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
		"host_peer":peer_stats(host),"guest_peer":peer_stats(guest),"game_ping":guest.net.status}


func follow() -> void:
	for row: Array in [[host,hg,0],[guest,gg,1]]:
		var units: Array=row[0].party_units(row[2])
		if not units.is_empty(): row[1].rig.focus((units[0] as GameUnit).global_position)


func trace_submit(s: Session, cmd: Dictionary) -> void:
	cmd.trace_sent_unix=Time.get_unix_time_from_system()
	s.submit(cmd)


func move_party(s: Session,owner: int,target: Vector2,ms: int) -> void:
	var i := 0
	for u: GameUnit in s.party_units(owner):
		if u.dead: continue
		var at := target+Vector2(float(owner)*1.5+float(i)*1.2,0)
		trace_submit(s,{"t":"move","units":[u.uid],"x":at.x,"y":at.y,"run":true})
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
		trace_submit(guest,{"t":"move","units":[u.uid],"x":at.x,"y":at.y,"line":true,"run":false})
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
		var started := Time.get_ticks_msec()
		check(pair[0].get_texture().get_image().save_png("user://transport-"+label+"-"+pair[1]+".png")==OK,"capture "+label+" "+pair[1])
		print("CAPTURE_COST ",pair[1]," ms=",Time.get_ticks_msec()-started)


func phase(sector: int) -> void:
	check(await host.load_game_shown("transport_source"),"load untouched authored Portal save at %dx"%sector)
	check(await until(func():return guest.zone_id==String(stress_plan.get("zone","gz1h")) and host.zone_id==guest.zone_id and not guest._remote_loading and not guest.loading_game and not host._remote_loading and not host.loading_game and not guest.party_units(1).is_empty() and LoadingScreen._current==null),"both peers reach playable Portal at %dx"%sector)
	if failures: return
	check(host.world.units.size()==guest.world.units.size() and guest.world.units.size()>=int(stress_plan.get("minimum_population",350)),"authored busy population retained at %dx"%sector)
	check(host.local_host.frontend and not host.local_host.single_player and not host.world.authority and not guest.world.authority,"real worker owns simulation and both views are co-op replicas")
	check(host.my_index==0 and guest.my_index==1 and host.players.size()==int(stress_plan.get("players",2)) and guest.players.size()==int(stress_plan.get("players",2)),"owner and guest have distinct live slots")
	hg.rig.distance=CameraRig.M_DEFAULT_DISTANCE; gg.rig.distance=CameraRig.M_DEFAULT_DISTANCE
	work={"commands":[],"motion":{},"census":[],"frame_ms":[],"slow_frames":[]}
	follow()
	if bool(stress_plan.get("long_routes",false)):
		for pair: Array in [[host,0],[guest,1]]:
			var leader: GameUnit=pair[0].party_units(pair[1])[0]
			var points := plan_route(leader,24.0,true)
			check(points.size()>=2,"normal player path supports a route at least 20 metres long")
			long_routes[pair[1]]={"points":points,"index":1}
	Engine.max_fps=60
	# Capture only after timing stops. A 5K PNG can block this frontend for
	# several seconds while the authority continues, leaving a synthetic
	# snapshot backlog immediately before the first measured frame.
	var ids := []
	for u: GameUnit in guest.world.party_units(): ids.append(u.uid)
	if int(stress_plan.get("players",2))==3:
		check(await until(func():return FileAccess.file_exists(String(stress_plan.directory).path_join("third-ready")),90),"standalone client is ready before shared timing starts")
	# A newly joined independent renderer can finish loading after the other
	# clients. The authority intentionally rejects clock changes until then.
	var clock_deadline := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<clock_deadline:
		await host.local_host.request("clock",{"sector":sector})
		await wait_real(0.2)
		if host.clock_speed==sector-1 and Engine.time_scale==float(sector): break
	print("STRESS_CLOCK ",JSON.stringify({"owner":host.clock_speed,"guest":guest.clock_speed,"engine":Engine.time_scale,"owner_enabled":host.host_clock,"guest_enabled":guest.host_clock}))
	check(host.clock_speed==sector-1 and Engine.time_scale==float(sector),"owner receives the requested shared simulation rate")
	var go := FileAccess.open(String(stress_plan.directory).path_join("go"),FileAccess.WRITE)
	go.store_string("go"); go.close()
	check(await until(func():return FileAccess.file_exists(String(stress_plan.directory).path_join("actors.json")),30),"authority selects authored actors for simultaneous movement")
	var selected: Array=JSON.parse_string(FileAccess.get_file_as_string(String(stress_plan.directory).path_join("actors.json")))
	check(selected.size()>=int(stress_plan.actors),"requested number of movable NPCs retained")
	for row: Dictionary in selected: ids.append(int(row.uid))
	await wait_real(2.0)
	var target_uid: int=guest.party_units(1)[0].uid
	var guest_anchor: Vector2=guest.party_units(1)[0].pos
	var started := Time.get_ticks_msec(); var previous := started; var next_census := started
	var host_anchor: Vector2=host.party_units(0)[0].pos
	var merge_before := guest.coop.merged_count
	var next_capture := started+10000
	var next_move := started; var next_guest_move := started; var next_notice := started+10000; var route_index := 0
	host.begin(started,ids); guest.begin(started,ids)
	print("SUSTAINED_BEGIN ",JSON.stringify({"speed":sector,"seconds":seconds,"zone":guest.zone_id,"population":guest.world.units.size(),"guest_uid":target_uid,"party":census(0).party}))
	while Time.get_ticks_msec()<started+int(seconds*1000):
		var now := Time.get_ticks_msec(); var elapsed := now-started; var dt := now-previous
		if dt>0: work.frame_ms.append(dt)
		if dt>100:
			var slow := {"wall_ms":elapsed,"frame_ms":dt,"progress_saves":guest.coop.merged_count,
				"process_seconds":Performance.get_monitor(Performance.TIME_PROCESS),
				"physics_seconds":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
				"draw_compilations":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)}
			work.slow_frames.append(slow)
			print("LAG_FRAME ",JSON.stringify(slow))
		previous=now
		if now>=next_move:
			if bool(stress_plan.get("long_routes",false)):
				next_move=now+int(stress_plan.command_ms)
				long_move(host,0,elapsed)
				long_move(guest,1,elapsed)
			else:
				next_move=now+int(6000.0/sector)
				move_party(host,0,host_anchor+Vector2([0.0,2.0,0.0,-2.0][route_index],0),elapsed)
				route_index=(route_index+1)%4
		if now>=next_guest_move and not bool(stress_plan.get("long_routes",false)):
			next_guest_move=now+400
			var leg := int(elapsed*sector/6000)%4
			var offset: float=[2.0,0.0,-2.0,0.0][leg]
			move_guest(guest_anchor+Vector2(offset,0),elapsed)
		if bool(stress_plan.get("capture",false)) and now>=next_capture and elapsed<30000:
			next_capture=now+200
			video_frames.append(viewport.get_texture().get_image())
			video_times.append(elapsed)
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
		"frontend_frame_gap_ms":stats(work.frame_ms),"slow_frames":work.slow_frames,"population":guest.world.units.size(),
		"guest_anchor":[guest_anchor.x,guest_anchor.y]}
	for m: Dictionary in work.motion.values(): m.erase("last_pos"); m.erase("last_draw")
	check(guest_summary.party_updates>seconds*4,"sustained guest snapshots at %dx"%sector)
	check(guest_summary.party_arrival_gap_ms.max<int(stress_plan.max_gap_ms) and guest_summary.initial_silence_ms<int(stress_plan.max_gap_ms) and guest_summary.trailing_silence_ms<int(stress_plan.max_gap_ms),"guest snapshot gaps stay within declared link budget at %dx"%sector)
	check(guest_summary.authority_snapshot_seconds>seconds*sector*0.9 and guest_summary.authority_snapshot_seconds<seconds*sector*1.1,"authority advances requested game time at %dx"%sector)
	check(guest_summary.received_snapshot_payload_bytes.max<=Session.SNAP_BYTES+8,"ordinary snapshot payloads retain packet budget at %dx"%sector)
	if String(stress_plan.profile)=="loopback":
		check(loss.get("absent_at_guest_seen_by_owner",[]).is_empty(),"guest misses no jointly observed loopback party broadcast at %dx"%sector)
	check(row.frontend_frame_gap_ms.max<1000,"no multi-second frontend frame stall at %dx"%sector)
	for m: Dictionary in work.motion.values():
		var label := "%s view actor %d"%[m.view,m.uid]
		check(m.distance>seconds*0.20 and m.draw_distance>seconds*0.20,label+" traverses the authored route")
		check(m.dead_frames==0 and (DisplayServer.get_name()=="headless" or m.visible_model_frames>0),label+" remains alive with a presentable original model")
		check(m.max_pending_freeze_ms<1000,label+" has no long pending presentation freeze")
		check(m.max_stop_mismatch_ms<1000,label+" has no long stale walking pose against the other delivery")
		check(m.max_draw_step<NetSmooth.TELEPORT,label+" has no presentation teleport")
	row.progress_saves=guest.coop.merged_count-merge_before
	row.authority_network=await host.local_host.request("network_stats")
	row.actor_streams={}
	for actor: Dictionary in selected: row.actor_streams[actor.uid]=stream_summary(guest,int(actor.uid))
	if int(stress_plan.get("players",2))==3:
		var independent_done := await until(func():return FileAccess.file_exists(String(stress_plan.directory).path_join("independent-guest.json")),60)
		check(independent_done,"standalone client finishes its own view and control checks")
		if not independent_done: return
		row.independent_guest=JSON.parse_string(FileAccess.get_file_as_string(String(stress_plan.directory).path_join("independent-guest.json")))
		check(int(row.independent_guest.failures)==0,"independent client perspective passes")
	var stop := FileAccess.open(String(stress_plan.directory).path_join("stop"),FileAccess.WRITE)
	stop.store_string("stop"); stop.close()
	check(await until(func():return FileAccess.file_exists(String(stress_plan.directory).path_join("authority.json")),20),"authority records real simulation timing and concurrent movement")
	row.authority=JSON.parse_string(FileAccess.get_file_as_string(String(stress_plan.directory).path_join("authority.json")))
	check(int(row.authority.concurrent_moving.max)>=int(stress_plan.actors)*0.5,"at least half the requested crowd really moves concurrently")
	check(row.authority.frame_ms.max<1000,"authority has no multi-second simulation frame stall")
	check(row.authority.world_seconds>float(row.authority.wall_seconds)*sector*0.9,"crowded authority maintains requested game speed")
	row.stress_plan=stress_plan
	row.routes=long_routes
	row.video_times_ms=video_times
	var guest_commands: Array=row.authority.command_receipts.filter(func(c):return int(c.player)==1).map(func(c):return float(c.delay_ms))
	row.guest_command_delay_ms=stats(guest_commands)
	check(row.guest_command_delay_ms.p95<1000,"guest command delivery p95 stays under one second")
	check(row.guest_command_delay_ms.max<3000,"guest commands avoid multi-second reliable backlog")
	if int(stress_plan.get("players",2))==3:
		var independent_commands: Array=row.authority.command_receipts.filter(func(c):return int(c.player)==2).map(func(c):return float(c.delay_ms))
		row.independent_command_delay_ms=stats(independent_commands)
		check(independent_commands.size()>=int(seconds*1000/float(stress_plan.command_ms))-3,"standalone guest commands reach authority throughout the run")
		check(row.independent_command_delay_ms.p95<1000 and row.independent_command_delay_ms.max<3000,"standalone guest avoids a growing reliable command backlog")
	check(row.progress_saves>=2,"real imported-save checkpoints are exercised")
	runs.append(row)
	FileAccess.open("user://transport-%dx-packets.json"%sector,FileAccess.WRITE).store_string(JSON.stringify({"owner":host.packets,"guest":guest.packets,"owner_party":host.actors,"guest_party":guest.actors}))
	await captures("%dx-end"%sector)
	if not video_frames.is_empty():
		var directory := String(stress_plan.directory).path_join("guest-frames")
		DirAccess.make_dir_recursive_absolute(directory)
		for i in video_frames.size(): video_frames[i].save_png(directory.path_join("%04d.png"%i))
		video_frames.clear()
	print("SUSTAINED_PHASE ",JSON.stringify({"speed":sector,"guest":guest_summary,"paired_delivery":loss,"motion":work.motion,"frontend_frame_gap_ms":row.frontend_frame_gap_ms}))


func finish() -> void:
	var progress := guest.coop.transfer_stats.duplicate() if is_instance_valid(guest) else {}
	var saves := guest.coop.merged_count if is_instance_valid(guest) else 0
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
		"seconds_per_speed":seconds,"worker_pid":worker_pid,"runs":runs,"progress_transfer":progress,"progress_saves":saves,"options":GameData.options,"renderer":RenderingServer.get_current_rendering_method(),
		"display":DisplayServer.get_name(),"renderer_info":renderer_info,
		"scope":"Linux real ENet with an external UDP impairment proxy and existing NPC move orders. Separate authority; two rendered frontends share a process. Emulated WAN, not an actual ZeroTier path or full playthrough."}
	FileAccess.open("user://sustained-coop-delivery.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WAN_COOP_STRESS %d checks %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)


func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stress-plan="): stress_path=arg.trim_prefix("--stress-plan=")
	stress_plan=JSON.parse_string(FileAccess.get_file_as_string(stress_path))
	if OS.get_cmdline_user_args().has("--stress-authority"):
		await authority_run()
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds=clampf(float(arg.trim_prefix("--seconds=")),4.0,600.0)
		elif arg.begins_with("--speeds="):
			speeds=[]
			for value in arg.trim_prefix("--speeds=").split(","):
				if int(value) in [1,2]: speeds.append(int(value))
		elif arg.begins_with("--route-save="): source=arg.trim_prefix("--route-save=")
		elif arg.begins_with("--require-adapter="): required_adapter=arg.trim_prefix("--require-adapter=")
	renderer_info={"method":RenderingServer.get_current_rendering_method(),
		"driver":RenderingServer.get_current_rendering_driver_name(),"display":DisplayServer.get_name(),
		"adapter":RenderingServer.get_video_adapter_name(),"vendor":RenderingServer.get_video_adapter_vendor(),
		"api":RenderingServer.get_video_adapter_api_version()}
	print("SUSTAINED_RENDERER ",JSON.stringify(renderer_info))
	if not required_adapter.is_empty():
		check(renderer_info.display!="headless" and renderer_info.method=="forward_plus" \
			and required_adapter.to_lower() in String(renderer_info.adapter).to_lower(),
			"actual Forward+ renderer uses required hardware adapter "+required_adapter)
	check(NetStatus.PROTOCOL==20,"all frontend scripts require protocol20")
	check(not source.is_empty() and FileAccess.file_exists(source),"explicit disposable source save exists")
	if failures: await finish(); return
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0,
		"auto_graphics":0,"control_mode":1,"coop_clock":1,"auto_exit":0,"scroll_border":0,"confine_mouse":0,
		"vsync":0,"fps_limit":0,"q_aa":0,"q_shadows":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH),true)
	# Match menu startup: deferred window/AA configuration must finish before
	# warming the loaded worlds. Report the actual output, not CLI dimensions.
	for i in 4: await get_tree().process_frame
	GameData._apply_window()
	await get_tree().process_frame
	renderer_info.window_size=DisplayServer.window_get_size()
	renderer_info.viewport_size=get_viewport().get_visible_rect().size
	renderer_info.msaa=get_viewport().msaa_3d
	renderer_info.render_scale=get_viewport().scaling_3d_scale
	print("SUSTAINED_DISPLAY ",JSON.stringify(renderer_info))
	Engine.max_fps=60
	host=ObservedSession.new(); get_parent().add_child(host); get_parent().session=host
	hg=Game.new(); hg.session=host; host.game=hg; get_parent().add_child(hg); get_parent().game=hg
	check(await start_stress_worker()==OK,"start same authority service with a test-only NPC order driver")
	worker_pid=host.local_host.process_id
	print("SUSTAINED_SERVICE ",worker_pid)
	if failures: await finish(); return
	viewport=SubViewport.new(); viewport.size=Vector2i(1280,720); viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(viewport)
	var api := SceneMultiplayer.new(); api.root_path=viewport.get_path(); get_tree().set_multiplayer(api,viewport.get_path())
	var main := Node.new(); main.name="Main"; viewport.add_child(main)
	guest=ObservedSession.new(); main.add_child(guest)
	gg=Game.new(); gg.session=guest; guest.game=gg; main.add_child(gg)
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var origin := FileAccess.open(SaveInfo.path("lag_origin"),FileAccess.WRITE)
	origin.store_buffer(FileAccess.get_file_as_bytes(source)); origin.close()
	CoopProgress.bring_slot="lag_origin"
	GameData.player_name="Sustained Guest"
	check(guest.join("127.0.0.1",int(stress_plan.proxy_port))==OK,"guest joins actual service by ENet")
	check(await until(func():return guest.my_index==1 and host.players.size()==2),"ordinary authenticated owner/guest connection")
	if int(stress_plan.get("players",2))==3:
		var request := FileAccess.open(String(stress_plan.directory).path_join("launch-third"),FileAccess.WRITE); request.store_string("launch"); request.close()
		check(await until(func():return host.players.size()==3,60),"additional independent client authenticates in its own process")
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var f := FileAccess.open(SaveInfo.path("transport_source"),FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(source)); f.close()
	if not failures:
		for sector: int in speeds:
			await phase(sector)
			if failures: break
	await finish()


func start_stress_worker() -> Error:
	# Replicate the LocalHost launch/authentication boundary, using the same
	# configure/listening/owner APIs. Only the tool entry adds scripted orders.
	var local := host.local_host
	local._token=Crypto.new().generate_random_bytes(32).hex_encode()
	local._config=String(stress_plan.directory).path_join("worker.cfg")
	var config := {"token":local._token,"parent":OS.get_process_id(),"port":int(stress_plan.server_port),
		"single_player":false,"limit":int(stress_plan.get("players",2)),"password":"","name":GameData.player_name,
		"hero":GameData.hero_class,"options":GameData.options.duplicate(true),"mods":host.mod_config.duplicate(true)}
	var file := FileAccess.open(local._config,FileAccess.WRITE)
	file.store_var(config); file.close(); FileAccess.set_unix_permissions(local._config,0x180)
	local.frontend=true; host.upnp.remote=true; host.host_port=int(stress_plan.server_port)
	var arguments := PackedStringArray(["--headless","--render-thread","safe","--audio-driver","Dummy","--max-fps","30",
		"--log-file",local._config+".log","--","--ei-path="+GameData.root,"--tool="+get_script().resource_path,
		"--stress-authority","--stress-plan="+stress_path])
	local.process_id=OS.create_process(OS.get_executable_path(),arguments)
	if not await until(func():return FileAccess.file_exists(local._config+".ready"),30): return ERR_TIMEOUT
	var result := host.join("127.0.0.1",int(stress_plan.server_port))
	if result==OK and not await until(func():return local._ready_owner,30): result=ERR_TIMEOUT
	return result as Error


func authority_run() -> void:
	seed(621012)
	authority_session=AuthoritySession.new(); get_parent().add_child(authority_session); get_parent().session=authority_session
	var config := authority_session.local_host.configure(String(stress_plan.directory).path_join("worker.cfg"))
	var result := authority_session.host(int(config.port),int(config.limit))
	authority_session.local_host.listening(result)
	if result!=OK: get_tree().quit(1); return
	var game := Game.new(); game.session=authority_session; authority_session.game=game
	get_parent().add_child(game); get_parent().game=game
	if not await until(func():return FileAccess.file_exists(String(stress_plan.directory).path_join("go")),180): get_tree().quit(2); return
	var w := authority_session.world
	var near := w.party_units()[0].pos
	var candidates := w.unit_rows().filter(func(u: GameUnit):return u.controller<0 and not u.dead and not u.hidden and not u.blocked and u._move_base()>0.1)
	candidates.sort_custom(func(a: GameUnit,b: GameUnit):return a.pos.distance_squared_to(near)<b.pos.distance_squared_to(near))
	var chosen := []
	for u: GameUnit in candidates:
		if stress_actors.size()>=int(stress_plan.actors): break
		var route := plan_route(u,20.0,false) if bool(stress_plan.get("long_routes",false)) else PackedVector2Array()
		if bool(stress_plan.get("long_routes",false)) and route.size()<2: continue
		stress_actors.append({"unit":u,"anchor":u.pos,"distance":0.0,"previous":u.pos,"route":route,"index":1})
		chosen.append({"uid":u.uid,"prototype":u.info.get("prototype",""),"position":[u.pos.x,u.pos.y],"distance_to_party":u.pos.distance_to(near),"route":route})
	FileAccess.open(String(stress_plan.directory).path_join("actors.json"),FileAccess.WRITE).store_string(JSON.stringify(chosen))
	w.profile_simulation=bool(stress_plan.get("profile_simulation",false)) or not bool(stress_plan.get("long_routes",false))
	w.combat_event.connect(func(_kind,_a,_b,_amount):combat_events+=1)
	var start := Time.get_ticks_msec(); var last := start; var next_order := start; var next_census := start
	var initial := w.time; var leg := 0
	var route_helper := PadField.new(); route_helper.game=game
	while not FileAccess.file_exists(String(stress_plan.directory).path_join("stop")) and Time.get_ticks_msec()<start+int(stress_plan.seconds)*1000+80000:
		var now := Time.get_ticks_msec()
		authority_frames.append(now-last); last=now
		if now>=next_order:
			next_order=now+int(1800.0/float(stress_plan.speed))
			var began := Time.get_ticks_usec()
			for row: Dictionary in stress_actors:
				var u: GameUnit=row.unit
				if u.dead: continue
				var target: Vector2
				if bool(stress_plan.get("long_routes",false)):
					target=row.route[row.index]
					if u.pos.distance_to(target)<1.25:
						row.index=1-int(row.index); target=row.route[row.index]
				else:
					var goal: Vector2=row.anchor+Vector2.from_angle(float(leg%4)*PI*0.5)*4.0
					target=route_helper._walk_goal(u,(goal-u.pos).normalized())
				u.move_to(target,false)
			command_times.append(Time.get_ticks_usec()-began); leg+=1
		var moving := 0; var fighting := 0
		for row: Dictionary in stress_actors:
			var u: GameUnit=row.unit
			row.distance+=u.pos.distance_to(row.previous); row.previous=u.pos
			if u.action in MOVING: moving+=1
			if u.action.begins_with("attack") or u.action.begins_with("cast"): fighting+=1
		if now>=next_census:
			next_census=now+250
			authority_census.append({"wall_ms":now-start,"moving":moving,"fighting":fighting,"simulation_seconds":w.time-initial})
		await get_tree().process_frame
	route_helper.free()
	var travel := []
	for row: Dictionary in stress_actors: travel.append({"uid":row.unit.uid,"distance":row.distance,"dead":row.unit.dead})
	var report := {"world_seconds":w.time-initial,"wall_seconds":(Time.get_ticks_msec()-start)/1000.0,
		"population":w.units.size(),"concurrent_moving":stats(authority_census.map(func(r):return r.moving)),
		"frame_ms":stats(authority_frames),"order_batch_us":stats(command_times),"census":authority_census,
		"actors":travel,"combat_events":combat_events,"command_receipts":(authority_session as AuthoritySession).command_receipts,"profile_us":w.profile_us,"profile_counts":w.profile_counts,"profile_slow":w.profile_slow}
	FileAccess.open(String(stress_plan.directory).path_join("authority.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("WAN_AUTHORITY ",JSON.stringify({"world_seconds":report.world_seconds,"frame_ms":report.frame_ms,"concurrent_moving":report.concurrent_moving}))


func plan_route(u: GameUnit, length: float, clear_of_enemies: bool) -> PackedVector2Array:
	var nav := u.world.nav
	for a in [0.0, PI, PI*0.5, -PI*0.5, PI*0.25, -PI*0.25, PI*0.75, -PI*0.75]:
		var goal := u.pos+Vector2.from_angle(a)*length
		if not nav.is_walkable(goal,u.move_class()): continue
		var path := nav.find_path(u.pos,goal,[u],[],0.0,u.move_class())
		if path.is_empty() or path[-1].distance_to(goal)>1.0: continue
		var safe := true
		if clear_of_enemies:
			for other: GameUnit in u.world.unit_rows():
				if other.dead or other.hidden or not u.world.is_enemy(u,other): continue
				for point: Vector2 in path:
					if point.distance_to(other.pos)<8.0: safe=false; break
				if not safe: break
		if safe: return PackedVector2Array([u.pos,goal])
	return PackedVector2Array()


func long_move(s: Session, owner: int, ms: int) -> void:
	var units := s.party_units(owner).filter(func(u: GameUnit):return not u.dead)
	if units.is_empty() or not long_routes.has(owner): return
	var route: Dictionary=long_routes[owner]
	if route.points.size()<2: return
	var goal: Vector2=route.points[route.index]
	if units[0].pos.distance_to(goal)<1.25:
		route.index=1-int(route.index); goal=route.points[route.index]
	trace_submit(s,{"t":"move","units":units.map(func(u):return u.uid),"x":goal.x,"y":goal.y,"run":false})
	work.commands.append({"wall_ms":ms,"owner":owner,"uids":units.map(func(u):return u.uid),
		"from":[units[0].pos.x,units[0].pos.y],"to":[goal.x,goal.y],"distance":units[0].pos.distance_to(goal),"route":"24m normal group move", "command_interval_ms":int(stress_plan.command_ms)})

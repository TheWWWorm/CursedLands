extends "res://tools/tests/path_trace_resolution.gd"
## Production recenter handoff and recovery. Failure notifications are injected;
## the scene collection, device replacement and native renders remain real.
var controller_rows := []

func await_active(owner: Node,previous_id := 0,seconds := 90.0) -> bool:
	var until:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<until:
		await frames(1)
		if owner.stats.get("active",false) and owner.device!=null and owner.device.output_ready() \
			and owner.device.get_instance_id()!=previous_id:return true
	return false

func wait_replacement(owner: Node,previous_id: int,label: String) -> void:
	var dropped:=0;var rebuilt:=0;var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<90000:
		await frames(1)
		if not owner.stats.get("active",false) or not Gfx.path_trace_active:dropped+=1
		if owner.stats.get("rebuilding",false):rebuilt+=1
		if owner.device!=null and owner.device.get_instance_id()!=previous_id and owner.device.output_ready():break
	check(owner.device!=null and owner.device.get_instance_id()!=previous_id and owner.device.output_ready(),label+": replacement produces valid native output")
	check(dropped==0,label+": current PT stays active throughout recenter preparation")
	check(rebuilt>0,label+": asynchronous replacement was observed")
	controller_rows.append({"case":label,"milliseconds":Time.get_ticks_msec()-started,"inactive_frames":dropped,
		"rebuilding_frames":rebuilt,"stats":owner.stats.duplicate(true)})

func await_pending(owner: Node) -> Object:
	var until:=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<until:
		await frames(1)
		if owner._pending_device!=null:return owner._pending_device
	return null

func inject_budget(owner: Node,game: Game) -> void:
	owner.set_process(false);owner._release()
	owner._begin_snapshot(game.world.terrain,camera)
	owner._gather.failed=true
	owner._queue_candidate(game.world.terrain,camera)
	check(owner._failed and owner.stats.get("fallback","")=="snapshot_budget","injected over-budget snapshot enters conventional fallback")
	check(owner.device==null and owner._failure_watch!=null and not owner._failure_watch._nodes.is_empty(),"failed snapshot retains a source-membership watch")
	check(owner._failure_watch.vertices.is_empty() and owner._failure_watch.images.is_empty() \
		and owner._failure_watch.pending.is_empty(),"failed snapshot releases packed CPU data")
	owner.set_process(true)

func run() -> void:
	var context:=await configure_resolution_game();var game: Game=context[1]
	var owner: Node=game.get_node("SceneRaytrace")
	if not owner.stats.get("active",false):get_tree().quit(1);return
	var original:=camera.global_transform
	var first: Object=owner.device;var first_id:=first.get_instance_id()
	camera.global_position+=Vector3(20,0,0)
	await wait_replacement(owner,first_id,"camera recenter")
	check(owner._center.distance_to(camera.global_position)<0.001,"replacement center matches its traced scene")
	await frames(4)
	check(first._closed and not first.output_ready(),"superseded device is retired after handoff")
	var current: Object=owner.device
	var emitter_count: int=owner.stats.get("emissive_triangles",0)
	owner._prepared(false,first_id);owner._prepared(true,first_id);owner._emitter_stats(9999,9999,first_id)
	check(owner.device==current and not owner._failed and owner.stats.get("emissive_triangles",0)==emitter_count,
		"late retired-generation notifications cannot corrupt current state")
	first=null;current=null

	# Reject a real prepared replacement before it can be published. Its queued
	# build notification must be harmless and the active scene remains usable.
	camera.global_position+=Vector3(20,0,0)
	var active_id: int=owner.device.get_instance_id()
	var found_pending:=false
	for i in 1800:
		await frames(1)
		if owner._pending_device!=null:
			var pending_id: int=owner._pending_device.get_instance_id()
			owner._prepared(false,pending_id);found_pending=true;break
	check(found_pending,"replacement failure injection reaches an actual pending device")
	check(owner.device!=null and owner.device.get_instance_id()==active_id and not owner._failed \
		and owner.stats.get("replacement_failure","")=="pipeline_failed","failed replacement preserves usable active output")
	await wait_replacement(owner,active_id,"replacement retry")

	# A rapid camera move invalidates an in-flight center, and disabling PT
	# during a build must drain that owner without allowing its deferred ready
	# notification to resurrect the renderer.
	camera.global_position+=Vector3(20,0,0)
	active_id=owner.device.get_instance_id()
	var cancelled: Object=await await_pending(owner)
	check(cancelled!=null,"rapid-movement case reaches a real pending device")
	if cancelled!=null:
		var cancelled_id: int=cancelled.get_instance_id()
		camera.global_position+=Vector3(40,0,0)
		await frames(4)
		check(owner._pending_device!=cancelled and cancelled._closed,"camera movement beyond the candidate region cancels and disposes it")
		owner._prepared(true,cancelled_id)
		check(owner.device!=cancelled,"cancelled candidate cannot publish through a late ready notification")
		await wait_replacement(owner,active_id,"rapid camera recenter")
		check(owner._center.distance_to(camera.global_position)<0.001,"rapid recenter uses the newest camera location")
		cancelled=null
	camera.global_position+=Vector3(20,0,0)
	cancelled=await await_pending(owner)
	check(cancelled!=null,"disable-during-build case reaches a real pending device")
	if cancelled!=null:
		var cancelled_id: int=cancelled.get_instance_id()
		GameData.options.merge({"pt_mode":0,"rt_shadows":0,"rt_gi":0},true);game._apply_options()
		await frames(4)
		check(owner.device==null and owner._pending_device==null and not Gfx.path_trace_active and cancelled._closed,
			"disabling PT drains active and pending device owners")
		owner._prepared(true,cancelled_id)
		check(owner.device==null and not owner._ready_gpu,"late readiness cannot reactivate a disabled renderer")
		cancelled=null
		GameData.options["pt_mode"]=1;game._apply_options()
		check(await await_active(owner),"PT can be re-enabled after cancelling a pending build")

	# A budget failure at the current location cannot retry its unchanged heavy
	# packing every frame, but movement or changed sources must recover it.
	inject_budget(owner,game)
	owner.set_process(false)
	var quiet:=true
	for i in 6:quiet=quiet and not owner._allow_retry(camera.global_position,1.0)
	check(quiet and owner._retry_attempt==1,"unchanged over-budget content does not repeatedly rebuild")
	owner.set_process(true);camera.global_position+=Vector3(18,0,0)
	check(await await_active(owner),"camera movement automatically recovers a snapshot failure")
	check(not owner._failed and owner._failure_watch==null and not owner.stats.has("fallback"),"successful retry clears failure state and watch")
	inject_budget(owner,game)
	var root:=Node3D.new();root.name="PathControllerRecovery";game.world.add_child(root)
	root.global_position=camera.global_position+Vector3(0,-2,-5)
	var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.material_override=StandardMaterial3D.new();root.add_child(mesh)
	game.world.objects["path-controller-recovery"]=root
	check(await await_active(owner),"source-membership change recovers a failure without moving the camera")
	check(owner._scene!=null and owner._scene._nodes.has(mesh.get_instance_id()),"recovered scene contains the newly admitted source")
	game.world.objects.erase("path-controller-recovery");root.queue_free();await frames(4)
	# Let the intentional topology invalidation finish before the active failure.
	check(await ready_snapshot(owner),"normal topology replacement settles after source cleanup")
	active_id=owner.device.get_instance_id();owner._prepared(false,active_id)
	check(owner._failed and not Gfx.path_trace_active and owner.device==null,"active-device failure restores conventional lighting immediately")
	check(await await_active(owner,active_id),"active pipeline failure retries automatically and restores real PT")

	owner.set_process(false)
	owner._clear_failure();var delays:=[]
	for i in 8:
		owner._remember_failure("pipeline_failed",camera.global_position)
		delays.append(owner._retry_delay)
		check(not owner._allow_retry(camera.global_position,0.1),"pipeline retry %d respects its delay"%i)
	var increasing:=true
	for i in range(1,delays.size()):increasing=increasing and delays[i]>=delays[i-1] and delays[i]<=30.0
	check(delays[0]==1.0 and delays[-1]==30.0 and increasing,
		"persistent pipeline failures use bounded increasing backoff")
	owner._clear_failure();owner.set_process(true)
	camera.global_transform=original
	check(await await_active(owner),"controller remains usable after failure/retry cycles")
	await frames(4)
	FileAccess.open(out.path_join("path-controller.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,
		"failures":failures,"runs":controller_rows,"retry_delays":delays,"stats":owner.stats.duplicate(true),
		"note":"Injected failure notifications and budget flag, actual campaign snapshots, native device builds and output. Physical OOM/device loss is not provoked."},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_TRACE_CONTROLLER ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)

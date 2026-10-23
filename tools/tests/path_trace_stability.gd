extends Node
## Live campaign stress probe, including the APIs present in the v1.24.0 export.
## Does not freeze simulation, hide actors, or seek animation. Ordinary saves
## retain their normal asynchronous thumbnail capture; no diagnostic readbacks.
## The regular camera is held only to make turns and snapshot jumps repeatable.
var out := "user://path-trace-stability"
var start_zone := "gz1g"
var next_zone := "bz8k"
var path_mode := 2
var quality := 1
var resolution := Vector2i(1280,720)
var topology_diagnostics := false
var phase_seconds := 6.0
var timeout_seconds := 175.0
var resolution_reapplications := 0
var generated_save := {}
var session: Session
var game: Game
var hero: GameUnit
var camera: Camera3D
var rt: Node
var phase := "startup"
var checks := 0
var failures: Array[String] = []
var checkpoints: Array = []
var scene_ids := {}
var device_ids := {}
var active_zones := {}
var instance_update_frames := 0
var pose_update_frames := 0
var live_update_frames := 0
var active_frames := 0
var started_usec := 0
var heartbeat_usec := 0
var running := false
var observe_live_updates := false
var last_row := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 102 # Read the controller's completed main-thread tick.
	run.call_deferred()

func _id(value: Object) -> int:
	return value.get_instance_id() if is_instance_valid(value) else 0

func _xyz(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _available(value: float) -> Variant:
	return value if value>0.0 else null

func _elapsed() -> float:
	return (Time.get_ticks_usec()-started_usec)/1000000.0

func _resolution_settings() -> void:
	GameData.resolution_size="%dx%d"%[resolution.x,resolution.y]
	GameData.options.display_mode=0
	GameData.options.resolution=maxi(0,GameData.resolutions().find(resolution))

func _enforce_resolution() -> void:
	var window := get_window()
	if window.mode!=Window.MODE_WINDOWED or not window.borderless or window.size!=resolution:
		resolution_reapplications+=1
	if window.mode!=Window.MODE_WINDOWED: window.mode=Window.MODE_WINDOWED
	if not window.borderless: window.borderless=true
	if window.size!=resolution: window.size=resolution

func _process(_dt: float) -> void:
	if not running: return
	# Startup's deferred window placement can run several frames after setup.
	_enforce_resolution()
	if is_instance_valid(rt):
		var stats: Dictionary = rt.stats
		if stats.get("active",false):
			active_frames += 1
			var scene_id := _id(rt._scene)
			if scene_id!=0: scene_ids[scene_id]=true
			var device_id := _id(rt.device)
			if device_id!=0: device_ids[device_id]=true
			if is_instance_valid(session): active_zones[session.zone_id]=true
			if observe_live_updates:
				var instances := int(stats.get("updated_instances",0))
				var poses := int(stats.get("updated_poses",0))
				if instances>0: instance_update_frames+=1
				if poses>0: pose_update_frames+=1
				if instances>0 or poses>0: live_update_frames+=1
	if Time.get_ticks_usec()>=heartbeat_usec:
		heartbeat_usec=Time.get_ticks_usec()+1000000
		_record("heartbeat")
	if _elapsed()>timeout_seconds:
		check(false,"live stability run exceeded its wall-time limit")
		_record("timeout")
		_persist("timeout")
		running=false
		get_tree().quit(1)

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)

func _topology_mesh(mesh: MeshInstance3D,scene: RefCounted,roots: Dictionary) -> Dictionary:
	if not is_instance_valid(mesh): return {"alive":false}
	var root: Node = mesh
	while is_instance_valid(root) and not roots.has(root.get_instance_id()): root=root.get_parent()
	var bounds := mesh.global_transform*mesh.get_aabb()
	var nearest: Vector3 = scene.center.clamp(bounds.position,bounds.end)
	return {"alive":true,"node":str(mesh.get_path()),"mesh_id":_id(mesh.mesh),
		"visible":mesh.is_visible_in_tree(),"position":_xyz(mesh.global_position),
		"nearest_bounds_metres":nearest.distance_to(scene.center),
		"root":str(root.get_path()) if is_instance_valid(root) else "",
		"root_metres":root.global_position.distance_to(scene.center) if root is Node3D else -1.0}

func _topology_snapshot() -> Dictionary:
	# Read-only replica of the shipped predicate. Calling _scene_meshes() here
	# would mutate its _mesh_roots table, so collect into local dictionaries.
	if not is_instance_valid(rt): return {}
	var scene: RefCounted = rt._scene if rt._scene!=null else rt._gather
	if scene==null or not is_instance_valid(session.world): return {}
	var began := Time.get_ticks_usec()
	var roots := {};var current := {};var meshes := {};var materials := {}
	var constants: Dictionary = scene.get_script().get_script_constant_map()
	var whole_units := constants.has("UNIT_HYSTERESIS")
	for root: Node3D in session.world.objects.values()+session.world.units.values():
		if not is_instance_valid(root): continue
		roots[root.get_instance_id()]=root
		var radius: float = scene.RADIUS+24.0
		if whole_units and root is GameUnit and scene._unit_roots.has(root.get_instance_id()): radius+=float(constants.UNIT_HYSTERESIS)
		if root.global_position.distance_squared_to(scene.center)>radius*radius: continue
		for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh==null or mesh is EIObjectWater: continue
			if (not whole_units or not root is GameUnit) and not scene._near(mesh.global_transform*mesh.get_aabb(),false): continue
			var supported := false
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface)
				if material is BaseMaterial3D or (material is ShaderMaterial and material.get_shader_parameter("albedo_tex") is Texture2D):
					supported=true;break
			if supported:
				current[mesh.get_instance_id()]=scene._mesh_version(mesh,materials)
				meshes[mesh.get_instance_id()]=mesh
	var added := 0;var removed := 0;var changed := 0;var examples := []
	for id: int in current:
		var kind := ""
		if not scene._nodes.has(id): added+=1;kind="added"
		elif current[id]!=scene._nodes[id]: changed+=1;kind="mesh_or_material_changed"
		if not kind.is_empty() and examples.size()<8:
			var detail := _topology_mesh(meshes[id],scene,roots)
			detail["kind"]=kind;detail["node_id"]=id
			if kind=="mesh_or_material_changed":
				detail["before"]=str(scene._nodes[id]);detail["after"]=str(current[id])
			examples.append(detail)
	for id: int in scene._nodes:
		if current.has(id): continue
		removed+=1
		if examples.size()<8:
			var detail := _topology_mesh(instance_from_id(id) as MeshInstance3D,scene,roots)
			detail["kind"]="removed";detail["node_id"]=id;examples.append(detail)
	var detail_changed: bool = scene.lighting_camera_mask>=0 and scene._detail_options!=Vector4i(
		GameData.option("gfx_terrain"),GameData.option("gfx_materials"),GameData.option("gfx_foliage_light"),GameData.option("gfx_terrain_cliffs"))
	var terrain_changed: bool = scene.path_materials and scene._terrain_version!=preload("res://src/game/fx/path_trace_terrain.gd").version(scene._terrain)
	return {"scene_id":_id(scene),"gathering":rt._scene==null,"baseline_nodes":scene._nodes.size(),
		"admission_policy":"whole-unit-hysteresis" if whole_units else "legacy-per-mesh",
		"current_nodes":current.size(),"added":added,"removed":removed,"changed":changed,
		"detail_options_changed":detail_changed,"terrain_version_changed":terrain_changed,
		"would_invalidate":detail_changed or terrain_changed or current!=scene._nodes,
		"examples":examples,"probe_usec":Time.get_ticks_usec()-began}

func _snapshot(reason: String,details: Dictionary = {}) -> Dictionary:
	var stats: Dictionary = rt.stats.duplicate(true) if is_instance_valid(rt) else {}
	var world: GameWorld = session.world if is_instance_valid(session) else null
	var controller := {}
	if is_instance_valid(rt):
		controller={"requested":Gfx.SceneRaytraceShader.requested(),"failed":rt._failed,
			"ready_gpu":rt._ready_gpu,"processing":rt.is_processing(),"mode":rt._mode,
			"pt_mode":GameData.option("pt_mode"),"quality":GameData.option("q_rt_lighting"),
			"terrain_visible":is_instance_valid(world) and is_instance_valid(world.terrain) and world.terrain.is_visible_in_tree(),
			"camera_current":is_instance_valid(camera) and camera.is_current(),
			"gather_instance":_id(rt._gather),"gather_cursor":rt._gather._cursor if rt._gather!=null else 0,
			"gather_pending":rt._gather.pending.size() if rt._gather!=null else 0}
	var visible_units := 0
	if is_instance_valid(world):
		for unit: GameUnit in world.units.values():
			if is_instance_valid(unit) and unit.is_visible_in_tree(): visible_units+=1
	var row := {"reason":reason,"phase":phase,"elapsed_seconds":_elapsed(),
		"unix":Time.get_unix_time_from_system(),"process_frame":Engine.get_process_frames(),
		"drawn_frames":Engine.get_frames_drawn(),"fps":Engine.get_frames_per_second(),
		"zone":session.zone_id if is_instance_valid(session) else "",
		"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"window_size":[get_window().size.x,get_window().size.y],
		"viewport_size":[get_viewport().get_visible_rect().size.x,get_viewport().get_visible_rect().size.y],
		"resolution_reapplications":resolution_reapplications,
		"active":stats.get("active",false),"fallback":stats.get("fallback",""),
		"scene_instance":_id(rt._scene) if is_instance_valid(rt) else 0,
		"device_instance":_id(rt.device) if is_instance_valid(rt) else 0,
		"world_instance":_id(world),"visible_units":visible_units,
		"camera":_xyz(camera.global_position) if is_instance_valid(camera) else [],
		"hero":_xyz(hero.global_position) if is_instance_valid(hero) else [],
		"updated_instances":stats.get("updated_instances",0),"updated_poses":stats.get("updated_poses",0),
		"paused":get_tree().paused,"stats":stats,"controller":controller,"details":details,
		"static_bytes":_available(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"video_allocated_bytes":_available(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
		"texture_bytes":_available(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)),
		"buffer_bytes":_available(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED))}
	if topology_diagnostics: row["topology_probe"]=_topology_snapshot()
	return row

func _record(reason: String,details: Dictionary = {}) -> void:
	last_row=_snapshot(reason,details)
	var encoded := JSON.stringify(last_row)
	print("PT_STABILITY ",encoded)
	var path := out.path_join("path-stability-progress.jsonl")
	var file := FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file!=null:
		file.seek_end();file.store_line(encoded);file.flush();file.close()
	if reason!="heartbeat": checkpoints.append(last_row)
	_persist("running")

func _persist(status: String) -> void:
	var file := FileAccess.open(out.path_join("path-stability-results.json"),FileAccess.WRITE)
	if file==null: return
	file.store_string(JSON.stringify({"status":status,"checks":checks,"failures":failures,
		"config":{"start_zone":start_zone,"next_zone":next_zone,"path_mode":path_mode,"quality":quality,
			"resolution":[resolution.x,resolution.y],
			"topology_diagnostics":topology_diagnostics,
			"phase_seconds":phase_seconds,"timeout_seconds":timeout_seconds},
		"profile":{"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0},
		"active_frames":active_frames,"instance_update_frames":instance_update_frames,
		"pose_update_frames":pose_update_frames,"live_update_frames":live_update_frames,
		"resolution_reapplications":resolution_reapplications,"generated_save":generated_save,
		"scene_instances":scene_ids.keys(),"device_instances":device_ids.keys(),"active_zones":active_zones.keys(),
		"last":last_row,"checkpoints":checkpoints,
		"note":"Live visible campaign actors and ordinary simulation. Camera turns/recenters and hero-relative movement. The destination save is generated by this fixture in its isolated profile, not supplied by a player; saving retains normal thumbnail capture. Memory counters are engine allocations, not total driver VRAM residency; unavailable values are null."},"\t"))
	file.flush();file.close()

func _phase(label: String,details: Dictionary = {}) -> void:
	phase=label
	_record("phase",details) # Flush before an operation that may crash.

func _frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func _hold(seconds: float) -> void:
	var until := Time.get_ticks_usec()+int(seconds*1000000.0)
	while running and Time.get_ticks_usec()<until: await get_tree().process_frame

func _wait_active(previous_scene := 0,seconds := 90.0) -> bool:
	await _frames(2) # The controller must observe the changed camera/world first.
	# Cold raster/RT pipeline compilation can consume several initial frames.
	# Initial activation gets extra time, while the overall wall cap stays strict.
	var until := Time.get_ticks_usec()+int(seconds*1000000.0)
	while running and Time.get_ticks_usec()<until:
		if is_instance_valid(rt):
			if rt._failed: return false
			if rt.stats.get("active",false) and rt.stats.get("path_tracing",false) \
				and _id(rt._scene)!=0 and _id(rt._scene)!=previous_scene: return true
		await get_tree().process_frame
	return false

func _enter(id: String) -> bool:
	observe_live_updates=false
	_phase("before-zone-load",{"destination":id})
	session._enter_zone(id,1,false)
	get_tree().paused=false
	check(session.zone_id==id and is_instance_valid(session.world),"entered campaign zone "+id)
	if session.zone_id!=id or not is_instance_valid(session.world): return false
	if not _prepare_zone_view(id): return false
	_phase("zone-ready",{"destination":id})
	var ready := await _wait_active()
	check(ready,"live PT becomes active in "+id)
	if ready:
		await _frames(4)
		observe_live_updates=true
		_record("active-zone")
	return ready

func _prepare_zone_view(id: String) -> bool:
	var party := session.party_units(0)
	check(not party.is_empty(),"campaign supplies a live party in "+id)
	if party.is_empty(): return false
	hero=party[0];camera=game.rig.camera
	GameData.options.merge({"rt_shadows":0,"rt_gi":0,"pt_mode":path_mode,
		"pt_accumulation":0,"q_rt_lighting":quality},true)
	_resolution_settings()
	game._apply_options()
	_enforce_resolution()
	check(get_window().size==resolution,"actual game window matches requested resolution in "+id)
	check(GameData.option("pt_mode")==path_mode and Gfx.SceneRaytraceShader.requested(),"selected PT settings remain effective in "+id)
	var focus := hero.global_position+Vector3.UP
	game.rig.hold_view(focus+Vector3(6,5,8),focus)
	camera.current=true
	return true

func _turn() -> void:
	_phase("turn-360")
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var began := Time.get_ticks_usec()
	var halfway := false
	while running:
		var amount := clampf((Time.get_ticks_usec()-began)/(phase_seconds*1000000.0),0.0,1.0)
		game.rig.hold_view(eye,eye+forward.rotated(Vector3.UP,TAU*amount)*12.0)
		if amount>=0.5 and not halfway:
			halfway=true;_record("turned-180")
		if amount>=1.0: break
		await get_tree().process_frame
	_record("turned-360")

func _move() -> void:
	var origin := hero.pos
	var camera_origin := camera.global_position
	var camera_offset := camera_origin-(hero.global_position+Vector3.UP)
	var destination := Vector2.INF
	for distance: float in [8.0,5.0,3.0,1.5]:
		for i in 24:
			var candidate := origin+Vector2.from_angle(TAU*float(i)/24.0)*distance
			if session.world.nav.direct_line(hero,candidate): destination=candidate;break
		if destination!=Vector2.INF: break
	_phase("hero-move",{"from":[origin.x,origin.y],"destination":str(destination)})
	check(destination!=Vector2.INF,"find a reachable route for ordinary hero movement")
	if destination==Vector2.INF: return
	hero.move_to(destination,true)
	var until := Time.get_ticks_usec()+int(phase_seconds*2.0*1000000.0)
	var travelled := 0.0
	var camera_travelled := 0.0
	while running and Time.get_ticks_usec()<until:
		if not is_instance_valid(hero): break
		var focus := hero.global_position+Vector3.UP
		game.rig.hold_view(focus+camera_offset,focus)
		travelled=maxf(travelled,hero.pos.distance_to(origin))
		camera_travelled=maxf(camera_travelled,camera.global_position.distance_to(camera_origin))
		await get_tree().process_frame
	check(travelled>0.25,"ordinary movement changes hero position by more than 0.25 metres")
	check(camera_travelled>0.25,"camera follows ordinary hero movement by more than 0.25 metres")
	_record("hero-moved",{"maximum_displacement_metres":travelled,"camera_maximum_displacement_metres":camera_travelled})

func _recenter() -> void:
	var focus := hero.global_position+Vector3.UP
	for offset: Vector3 in [Vector3(24,6,12),Vector3(-24,6,-12),Vector3(0,6,10)]:
		if not running: return
		var before := _id(rt._scene)
		var center: Vector3 = rt._center
		var eye := focus+offset
		if eye.distance_to(center)<=18.0: eye=center+offset.normalized()*26.0
		eye.y=maxf(eye.y,session.world.ground_at(eye.x,-eye.z)+3.0)
		_phase("before-recenter",{"old_scene":before,"target":_xyz(eye),"distance_metres":camera.global_position.distance_to(eye),
			"distance_from_snapshot_metres":center.distance_to(eye)})
		game.rig.hold_view(eye,focus)
		var ready := await _wait_active(before,45.0)
		check(ready,"camera recenter replaces the snapshot and restores active PT")
		_record("after-recenter",{"old_scene":before,"ready":ready})
		if not ready: return
		await _hold(1.0)

func _wait_save_thumbnail(_slot: String) -> bool:
	# Keep the short stability probe's original cadence. Sustained probes can
	# override this hook to require the production asynchronous image on disk.
	await _frames(4)
	return true

func _save_reload_destination() -> void:
	if not running: return
	var destination := session.zone_id
	var slot := "pt-stability-%s-%d-%d"%[destination,int(Time.get_unix_time_from_system()),OS.get_process_id()]
	var path := SaveInfo.path(slot)
	generated_save={"source":"generated-by-live-fixture","slot":slot,"zone":destination,
		"path":ProjectSettings.globalize_path(path),"saved":false,"loaded":false,"pt_active_after_load":false}
	_phase("before-generated-save",generated_save.duplicate())
	check(not FileAccess.file_exists(path),"generated test save uses a fresh isolated slot")
	if FileAccess.file_exists(path): return
	var error := session.save_game(slot)
	check(error in [OK,ERR_BUSY],"real Session.save_game accepts the generated destination checkpoint")
	if error not in [OK,ERR_BUSY]:
		_record("generated-save-failed",{"error":error});return
	# Inline save is synchronous; a movie/purse can defer the real operation.
	var until := Time.get_ticks_usec()+10000000
	while running and not FileAccess.file_exists(path) and Time.get_ticks_usec()<until:
		await get_tree().process_frame
	generated_save.saved=FileAccess.file_exists(path) and SaveInfo.read(slot).zone==destination
	check(generated_save.saved,"generated destination save and metadata reach disk")
	if not generated_save.saved or not running: return
	# Give the ordinary asynchronous save thumbnail its normal drawn frames
	# before loading. Its readback is part of the real save path under test.
	if not await _wait_save_thumbnail(slot): return
	generated_save["thumbnail_written"]=FileAccess.file_exists(SaveInfo.path(slot,"shot.png"))
	_record("generated-save-written",generated_save.duplicate())
	if not running: return
	var old_world := _id(session.world)
	var old_scene := _id(rt._scene)
	observe_live_updates=false
	_phase("before-generated-load",{"save":generated_save.duplicate(),"old_world":old_world,"old_scene":old_scene})
	# load_game is the shipped synchronous bool-returning API for tools;
	# load_game_shown is the separate asynchronous UI entry point.
	generated_save.loaded=session.load_game(slot)
	check(generated_save.loaded,"real Session.load_game restores the generated destination checkpoint")
	_record("generated-load-returned",generated_save.duplicate())
	if not generated_save.loaded or not running: return
	get_tree().paused=false
	check(session.zone_id==destination and is_instance_valid(session.world),"generated save restores its destination zone")
	check(_id(session.world)!=old_world,"save loading replaces the live world instance")
	if session.zone_id!=destination or not is_instance_valid(session.world): return
	if not _prepare_zone_view(destination): return
	_phase("generated-load-wait-pt",generated_save.duplicate())
	generated_save.pt_active_after_load=await _wait_active(old_scene)
	check(generated_save.pt_active_after_load,"replacement PT snapshot becomes active after generated save load")
	if generated_save.pt_active_after_load:
		observe_live_updates=true
		_phase("generated-load-live",generated_save.duplicate())
		await _hold(phase_seconds)
	_record("generated-save-roundtrip",generated_save.duplicate())

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out=arg.trim_prefix("--audit-out=")
		elif arg.begins_with("--pt-stability-start-zone="): start_zone=arg.trim_prefix("--pt-stability-start-zone=")
		elif arg.begins_with("--pt-stability-next-zone="): next_zone=arg.trim_prefix("--pt-stability-next-zone=")
		elif arg.begins_with("--pt-stability-mode="): path_mode=clampi(arg.trim_prefix("--pt-stability-mode=").to_int(),1,2)
		elif arg.begins_with("--pt-stability-quality="): quality=clampi(arg.trim_prefix("--pt-stability-quality=").to_int(),0,2)
		elif arg=="--pt-stability-topology": topology_diagnostics=true
		elif arg.begins_with("--pt-stability-resolution="):
			var parts := arg.trim_prefix("--pt-stability-resolution=").to_lower().split("x")
			if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() \
				or parts[0].to_int()<1 or parts[1].to_int()<1:
				push_error("PT stability resolution must be positive WIDTHxHEIGHT")
				get_tree().quit(1);return
			resolution=Vector2i(parts[0].to_int(),parts[1].to_int())
		elif arg.begins_with("--pt-stability-seconds="): phase_seconds=clampf(arg.trim_prefix("--pt-stability-seconds=").to_float(),3.0,12.0)
		elif arg.begins_with("--pt-stability-timeout="): timeout_seconds=clampf(arg.trim_prefix("--pt-stability-timeout=").to_float(),30.0,300.0)
	DirAccess.make_dir_recursive_absolute(out)
	started_usec=Time.get_ticks_usec();running=true
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"auto_graphics":0,"autosave":0,"show_tutorial":0,"vsync":0,"fps_limit":0,"scroll_border":0,
		"net_lan":0,"net_upnp":0,"net_directory":0,"control_mode":1,"gfx_water_reflections":0,
		"rt_shadows":0,"rt_gi":0,"pt_mode":path_mode,"pt_accumulation":0,"q_rt_lighting":quality},true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_resolution_settings()
	get_window().min_size=Vector2i(1,1);_enforce_resolution()
	_phase("create-session")
	session=Session.new();add_child(session)
	game=Game.new();game.session=session;session.game=game;add_child(game)
	rt=game.get_node("SceneRaytrace")
	session.state.ensure_hero(0,"Human Hero")
	if await _enter(start_zone):
		_phase("live-warmup");await _hold(phase_seconds)
		await _turn()
		await _move()
		await _recenter()
		if running and await _enter(next_zone):
			await _turn()
			_phase("destination-live");await _hold(phase_seconds)
			await _save_reload_destination()
	check(active_zones.has(start_zone) and active_zones.has(next_zone),"both campaign zones rendered active PT")
	check(generated_save.get("pt_active_after_load",false),"generated destination save completes a live PT load roundtrip")
	check(instance_update_frames>2,"visible live actors submit instance changes across multiple frames")
	check(live_update_frames>2,"ordinary animation or movement submits live pose/instance updates")
	check(scene_ids.size()>1 and device_ids.size()>1,"live test observes replaced scene and device snapshots")
	_phase("before-cleanup")
	running=false
	game.queue_free();session.queue_free()
	await _frames(12)
	TexUpscale.shutdown()
	_persist("passed" if failures.is_empty() else "failed")
	print("PT_STABILITY_DONE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)

extends Node
## Optional scene lighting. The conventional path remains live while scene
## snapshots build, outside the bounded RT region, or on unsupported devices.
const Device = preload("res://src/game/fx/scene_raytrace_device.gd")
const PathDevice = preload("res://src/game/fx/path_trace_device.gd")
const RayReconstruction = preload("res://src/game/fx/path_trace_rr.gd")
const PathSky = preload("res://src/game/fx/path_trace_sky.gd")
const Budget = preload("res://src/game/fx/path_trace_budget.gd")
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
const SCALES := [0.5,0.75,1.0]
const GI_SAMPLES := [1,2,4]
const SHADOW_SAMPLES := [1,2,4]
const RECEIVER_RADIUS := 72.0
const PATH_LIGHT_LIMIT := 64
const REASON := "Scene ray tracing needs a ray-tracing GPU and the qualified DX12 or Vulkan Forward+ renderer. Conventional lighting remains available."

var game: Game
var stats := {}
var device: Device
var _gather: Scene
var _scene: Scene
# A recenter replacement remains private until it has rendered valid output.
# The current scene keeps lighting the view while CPU/GPU preparation runs.
var _pending_device: Device
var _pending_scene: Scene
var _pending_ready := false
var _pending_stats := {}
var _pending_stage := -1
var _pending_geometries := []
var _pending_placements := []
var _snapshot_generation := 0
var _topology_pending := false
var _failure_reason := ""
var _failure_position := Vector3.INF
var _failure_watch: Scene
var _retry_delay := 0.0
var _failure_age := 0.0
var _failure_poll := 0.0
var _retry_attempt := 0
var _terrain: EITerrain
var _center := Vector3.INF
var _ready_gpu := false
var _failed := false
var _bound := false
var _poll := 0.0
var _lights: Array[WeakRef] = []
var _frame_number := 0
var _previous_view := Projection()
var _previous_view_projection := Projection()
var _previous_camera := Transform3D.IDENTITY
var _history_key := ""
var _mode := ""
var _path_mode := false
var _path_signature := PackedByteArray()
var _path_cloud_signature := PackedByteArray()
var _accumulation_frames := 0.0
# A visible settings request owns one cover. Ordinary recenter/topology work
# keeps this key, so cancellation and automatic recovery never reopen it.
var _preparation_seen := ""
var _preparation_owner: StringName = &""
var _preparation_token := 0
var _preparation_waiting_id := 0
var _preparation_completed_id := 0
var _preparation_size := Vector2i.ZERO
var _preparation_visible_frame := -1
# Diagnostic control for matched flicker comparisons; never freezes a light.
var _strict_light_history := OS.get_cmdline_user_args().has("--ei-strict-light-history")
# Diagnostic comparison against the old display-resolution PT workload.
var _window_resolution_reference := OS.get_cmdline_user_args().has("--ei-pt-window-resolution")
var _profile_cpu := OS.get_cmdline_user_args().has("--ei-profile-rt")
var _ground_cache := Scene.Ground.new()
var _source_cache := Scene.SourceCache.new()
var _programs := Device.Programs.new()
var _handoff_updates := false
var _budget := Budget.new()
var _budget_clock := 0
var _rr_effect: CompositorEffect
var _rr_camera: Camera3D
var _rr_original: Compositor
var _rr_compositor: Compositor
var _rr_active := false
var _rr_failed := false

func _init(owner_game: Game) -> void:
	game = owner_game; name = "SceneRaytrace"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 101
	Gfx.ensure_globals()

static func internal_render_size(viewport: Vector2,render_scale: float) -> Vector2i:
	# Godot truncates the scaled 3D dimensions before allocating its buffers.
	# Use the viewport's applied scale, including FSR, rather than saved options.
	return Vector2i(viewport*render_scale).max(Vector2i.ONE)

static func target_size(viewport: Vector2,quality: int,render_scale := 1.0) -> Vector2i:
	var scale: float = SCALES[clampi(quality,0,2)]
	var internal := internal_render_size(viewport,render_scale)
	return Vector2i(maxi(2,roundi(internal.x*scale)),maxi(2,roundi(internal.y*scale)))

func _process(dt: float) -> void:
	var cpu_start := Time.get_ticks_usec() if _profile_cpu else 0
	var cpu_stage := cpu_start
	var wanted := Gfx.SceneRaytraceShader.requested()
	var terrain: EITerrain = game.world.terrain if game.world != null else null
	var path_mode := GameData.option("pt_mode")>0
	var mode := "%s:%s:%s:%s:%s:%s:%s:%s"%[GameData.option("rt_shadows"),GameData.option("rt_gi"),GameData.option("q_rt_lighting"),GameData.option("pt_mode"),GameData.option("pt_accumulation"),GameData.option("pt_sharc"),GameData.option("pt_denoiser"),GameData.option("pt_ray_reconstruction")]
	if mode != _mode or terrain != _terrain:
		if terrain != _terrain or path_mode!=_path_mode: _release()
		_path_mode=path_mode
		_mode = mode; _terrain = terrain; _clear_failure(); _history_key=""
	if not wanted or not is_instance_valid(terrain) or not terrain.is_visible_in_tree() or game.simulation_only:
		_preparation_seen="";_end_preparation()
		if device != null or _gather != null or _pending_device!=null or _failure_watch!=null: _release()
		return
	if not Device.supported():
		_preparation_seen="";_end_preparation()
		_failed = true; stats = {"active":false,"supported":false,"fallback":"unsupported"}; return
	var camera := terrain.get_viewport().get_camera_3d()
	if camera == null:
		_preparation_seen="";_release();return
	if _rr_effect!=null and _rr_effect.failed:_rr_failed=true
	_set_ray_reconstruction(camera,RtxGraphics.rr_active() and not _rr_failed and camera.get_viewport()==get_tree().root)
	var visible_request := game.is_visible_in_tree() and game.is_ancestor_of(camera)
	var request := "%s:%s:%s"%[terrain.get_instance_id(),_mode,GameData.graphics_revision]
	var prepare := visible_request and request!=_preparation_seen
	var terrain_preparing := ShaderCompilationScreen.terrain_pending(terrain)
	if prepare:
		_clear_failure();_history_key="";_poll=0.0
	elif not visible_request:
		_preparation_seen="";_end_preparation()
	var may_retry := _allow_retry(camera.global_position,dt)
	# Spell flashes can live for less than the geometry polling interval.
	# Refresh the bounded light list before this frame, without rebuilding meshes.
	if _path_mode:_collect_lights(camera.global_position)
	_poll -= dt
	if _scene != null and (_poll<=0.0 or _scene.topology_pending) and not terrain_preparing:
		_poll = 1.0
		if not _path_mode:_collect_lights(camera.global_position)
		# Keep the working region lit while changed membership/equipment is
		# gathered. Instance updates immediately mask removed/replaced meshes;
		# a new scene is published only after its first complete frame.
		if _scene.topology_changed(500):
			_topology_pending=true
	if _profile_cpu:
		stats["cpu_topology_ms"]=(Time.get_ticks_usec()-cpu_stage)/1000.0;cpu_stage=Time.get_ticks_usec()
	var building := _gather if _gather!=null else _pending_scene
	if building!=null and (camera.global_position.distance_to(building.center)>32.0 or (prepare and terrain_preparing)):
		_cancel_candidate()
	# Only explicit settings requests own a preparation cover. Live geometry
	# replacement continues rendering through the same atomic handoff as travel.
	if prepare:
		_preparation_seen=request
		_begin_preparation()
	# Explicit terrain workers continue under the shared pause. Do not gather
	# their old geometry or acknowledge its shaders before their bounded work.
	if terrain_preparing: return
	if _gather==null and _pending_device==null and may_retry \
		and (device==null or _topology_pending or camera.global_position.distance_to(_center)>16.0):
		_begin_snapshot(terrain,camera)
	if _profile_cpu:
		stats["cpu_snapshot_ms"]=(Time.get_ticks_usec()-cpu_stage)/1000.0;cpu_stage=Time.get_ticks_usec()
	# Loading can use the larger preparation budget. Live travel shares the
	# frame with rendering and simulation, while the previous scene stays lit.
	if _gather!=null and _gather.step(1500 if device!=null else 6000): _queue_candidate()
	if _pending_stage>=0:
		_prepare_candidate(terrain,camera)
	elif _pending_device!=null and not _pending_ready:Device.dispatch(_pending_device,&"build_step")
	if _profile_cpu:stats["cpu_gather_ms"]=(Time.get_ticks_usec()-cpu_stage)/1000.0
	var quality := clampi(GameData.option("q_rt_lighting"),0,2)
	var viewport := camera.get_viewport()
	var display_size := viewport.get_visible_rect().size
	var render_scale := viewport.scaling_3d_scale
	var trace_scale := render_scale if _path_mode and not _window_resolution_reference else 1.0
	# Rays and receiver lookup share the unjittered camera projection. Raster
	# receivers project world positions into this lattice beside FSR jitter.
	var size := internal_render_size(display_size,render_scale) if _rr_active else target_size(display_size,quality,trace_scale)
	_budget.configure(GameData.option("pt_target_fps") if _path_mode and GameData.option("pt_accumulation")==0 and not _rr_active else 0)
	var now := Time.get_ticks_usec()
	var seconds := (now-_budget_clock)/1000000.0 if _budget_clock>0 else 0.0
	_budget_clock=now
	if _budget.target>0:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
		if device!=null:
			device.measure_budget=true
			var raster_ms := RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
			_budget.observe(device.gpu_frame,seconds,raster_ms+device.gpu_ms,device.gpu_ms,
				get_tree().paused or _gather!=null or _pending_device!=null or not _preparation_owner.is_empty() or not device.output_ready())
		size=_budget.size(size)
	elif device!=null:device.measure_budget=false
	if _pending_ready and _pending_device.output_ready() and _pending_device.output.get_size()==Vector2(size):
		if _pending_scene.topology_changed():
			var keep_cover := not _preparation_owner.is_empty()
			_cancel_candidate()
			if keep_cover: _begin_preparation()
		else: _activate_candidate()
	var frame := PackedByteArray()
	if _ready_gpu and device!=null:
		_scene.lighting_camera_mask = camera.cull_mask
		var update_started := Time.get_ticks_usec()
		var changes := _scene.updates(_handoff_updates)
		_handoff_updates=false
		stats["cpu_update_ms"]=(Time.get_ticks_usec()-update_started)/1000.0
		frame = _frame(camera,size,quality,not changes.instances.is_empty() or not changes.poses.is_empty(),dt)
		_render(device,size,frame,changes)
		if device.output_ready():
			_set_gi_active(_path_mode or GameData.option("rt_gi")>0)
			_bind_outputs()
			var view_projection := camera.get_camera_projection()*Projection(camera.get_camera_transform().affine_inverse())
			RenderingServer.global_shader_parameter_set(&"ei_rt_view_projection",view_projection)
			RenderingServer.global_shader_parameter_set(&"ei_rt_inverse_view_projection",view_projection.inverse())
			RenderingServer.global_shader_parameter_set(&"ei_rt_view",Projection(camera.get_camera_transform().affine_inverse()))
			RenderingServer.global_shader_parameter_set(&"ei_rt_eye",camera.get_camera_transform().origin)
			RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(_center.x,_center.y,_center.z,0))
			RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(1,GameData.option("rt_shadows"),GameData.option("rt_gi"),RECEIVER_RADIUS))
			RenderingServer.global_shader_parameter_set(&"ei_pt_active",float(_path_mode))
			stats["active"]=true
		stats["updated_instances"]=changes.instances.size();stats["updated_poses"]=changes.poses.size()
	if _pending_ready:
		_pending_scene.lighting_camera_mask=camera.cull_mask
		var changes := _pending_scene.updates()
		if frame.is_empty(): frame=_frame(camera,size,quality,true,dt)
		else: frame=frame.duplicate()
		# First output is private and never borrows the active scene's history.
		frame.encode_float(82*4,0.0)
		for axis in 3: frame.encode_float((84+axis)*4,_pending_scene.center[axis])
		_render(_pending_device,size,frame,changes)
	stats["rebuilding"]=_gather!=null or _pending_device!=null
	stats["snapshot_generation"]=_snapshot_generation
	stats["size"]=[size.x,size.y]; stats["quality"]=quality
	var render_size := internal_render_size(display_size,render_scale)
	stats["display_size"]=[int(display_size.x),int(display_size.y)]
	stats["render_size"]=[render_size.x,render_size.y];stats["render_scale"]=render_scale
	stats["trace_render_scale"]=trace_scale
	stats["window_resolution_reference"]=_path_mode and _window_resolution_reference
	stats["adaptive_target_fps"]=_budget.target;stats["adaptive_scale"]=_budget.scale
	stats["adaptive_changes"]=_budget.changes;stats["adaptive_gpu_ms"]=_budget.gpu_ms
	stats["gi_samples"]=GI_SAMPLES[quality] if GameData.option("rt_gi")>0 else 0
	stats["shadow_samples"]=SHADOW_SAMPLES[quality] if GameData.option("rt_shadows")>0 else 0
	stats["lights"]=_lights.size()
	stats["path_tracing"]=_path_mode;stats["path_bounces"]=GameData.option("pt_mode")*2 if _path_mode else 0
	stats["path_samples"]=1 if _rr_active else (GI_SAMPLES[quality] if _path_mode else 0)
	stats["accumulation_frames"]=_accumulation_frames if _path_mode else 0
	stats["program_compilations"]=_programs.compilations
	stats["program_cache_hits"]=_programs.hits
	if device!=null:stats["build_timings"]=device.build_timings.duplicate()
	if device is PathDevice:
		stats["ray_reconstruction"]=device.ray_reconstruction
		stats["rr_raw_frames"]=device.raw_reconstruction_frames
		stats["nrd_directional"]=device.nrd_active and device.nrd.directional
		stats["sharc_active"]=device.sharc.active
		stats["sharc_failed"]=device.sharc_failed
		stats["sharc_frames"]=device.sharc.frames
		stats["sharc_resets"]=device.sharc.resets
		stats["history_handoffs"]=device.history_handoffs
		stats["history_matched_surfaces"]=device.history_matched_surfaces
	_settle_preparation(size)
	if _profile_cpu:stats["cpu_total_ms"]=(Time.get_ticks_usec()-cpu_start)/1000.0

func _begin_preparation() -> void:
	_end_preparation()
	_preparation_token+=1
	_preparation_owner=StringName("pipeline:scene:%d:%d"%[get_instance_id(),_preparation_token])
	var phase := ShaderCompilationScreen.GEOMETRY if device==null else _pipeline_phase()
	var screen := ShaderCompilationScreen.begin(get_tree(),_preparation_owner,phase)
	if screen==null: _end_preparation();return
	# Show the cover before synchronous geometry/material packing can begin.
	screen.present()

func _pipeline_phase() -> String:
	return ShaderCompilationScreen.PATH_TRACE if _path_mode else ShaderCompilationScreen.RAYTRACE

func _end_preparation() -> void:
	if not _preparation_owner.is_empty(): ShaderCompilationScreen.end(_preparation_owner)
	_preparation_owner=&"";_preparation_waiting_id=0;_preparation_completed_id=0
	_preparation_size=Vector2i.ZERO;_preparation_visible_frame=-1

func _render(target: Device,size: Vector2i,frame: PackedByteArray,changes: Dictionary) -> void:
	if target is PathDevice:changes["nrd_directional"]=GameData.option("pt_denoiser")>0 and not OS.get_cmdline_user_args().has("--ei-pt-nrd-radiance")
	if target is PathDevice:
		changes["ray_reconstruction"]=_rr_active and target==device
		Device.dispatch(target,&"set_cloud_texture",[_path_cloud_texture()])
	# An active device is the visible target even while a recenter replacement
	# builds. With no active scene, the candidate must finish privately first.
	if _preparation_owner.is_empty() or (target!=device and device!=null):
		_dispatch_render(target,size,frame,changes);return
	var id := target.get_instance_id()
	if id!=_preparation_waiting_id or size!=_preparation_size:
		_preparation_token+=1
		_preparation_waiting_id=id;_preparation_completed_id=0
		_preparation_size=size;_preparation_visible_frame=-1
		ShaderCompilationScreen.update(_preparation_owner,_pipeline_phase())
		_dispatch_render(target,size,frame,changes,_preparation_token)
	else:
		_dispatch_render(target,size,frame,changes)

func _dispatch_render(target: Device,size: Vector2i,frame: PackedByteArray,changes: Dictionary,token := -1) -> void:
	if _rr_active and target==device and _rr_effect!=null:
		Device.dispatch(_rr_effect,&"queue_frame",[target,size,frame,changes,GameData.option("q_aniso"),token])
	elif token>=0:Device.dispatch(target,&"render_preparation",[token,size,frame,changes,GameData.option("q_aniso")])
	else:Device.dispatch(target,&"render",[size,frame,changes,GameData.option("q_aniso")])

func _set_ray_reconstruction(camera: Camera3D,active: bool) -> void:
	if _rr_active==active and (not active or camera==_rr_camera):return
	if is_instance_valid(_rr_camera) and _rr_camera.compositor==_rr_compositor:_rr_camera.compositor=_rr_original
	if _rr_effect!=null:Device.dispatch(_rr_effect,&"dispose")
	_rr_effect=null;_rr_camera=null;_rr_original=null;_rr_compositor=null
	_rr_active=active;_history_key=""
	RenderingServer.global_shader_parameter_set(&"ei_pt_rr_active",float(active))
	if not active:return
	_rr_camera=camera;_rr_original=camera.compositor
	_rr_compositor=Compositor.new()
	var effects: Array[CompositorEffect]=[]
	if _rr_original!=null:effects.assign(_rr_original.compositor_effects)
	_rr_effect=RayReconstruction.new();effects.push_front(_rr_effect)
	_rr_compositor.compositor_effects=effects;camera.compositor=_rr_compositor

func _rendered(token: int,ok: bool,id: int) -> void:
	# A prior settings request, resize or canceled device cannot complete the
	# current request. The acknowledgment follows an actual successful render;
	# output_ready alone may still describe the previous PT depth variant.
	if _preparation_owner.is_empty() or token!=_preparation_token or id!=_preparation_waiting_id: return
	if not ok: _end_preparation();return
	_preparation_completed_id=id
	ShaderCompilationScreen.update(_preparation_owner,ShaderCompilationScreen.FIRST_FRAME)

func _settle_preparation(size: Vector2i) -> void:
	if _preparation_owner.is_empty(): return
	if device==null or device.get_instance_id()!=_preparation_completed_id \
		or not stats.get("active",false) or not device.output_ready() \
		or size!=_preparation_size or device.output.get_size()!=Vector2(size):
		_preparation_visible_frame=-1;return
	# Candidate acknowledgment can arrive before promotion. Wait for a draw
	# after its output is bound, then let the shared screen settle its frames.
	if _preparation_visible_frame<0: _preparation_visible_frame=Engine.get_frames_drawn()
	elif Engine.get_frames_drawn()>_preparation_visible_frame: _end_preparation()

func _begin_snapshot(terrain: EITerrain,camera: Camera3D) -> void:
	_failed=false
	_gather=Scene.new();_gather.lighting_camera_mask=camera.cull_mask
	_gather._ground=_ground_cache
	_gather._sources=_source_cache
	_gather.path_materials=_path_mode
	# No water-plane clipping: ceilings and underground rooms participate.
	_gather.begin(terrain,camera.global_position,-1.0e20)
	if device==null: _center=camera.global_position

func _queue_candidate() -> void:
	_pending_scene=_gather;_gather=null
	_pending_stats={"active":false,"supported":true,"triangles":_pending_scene.triangles,
		"geometries":_pending_scene.geometries.size(),"instances":_pending_scene.instances.size()}
	if _pending_scene.failed or _pending_scene.triangles==0:
		_reject_candidate("snapshot_budget" if _pending_scene.failed else "snapshot_empty");return
	_pending_device=PathDevice.new() if _path_mode else Device.new()
	_pending_device.programs=_programs
	_pending_device.incremental_build=device!=null
	if _path_mode:
		_pending_device.defer_nrd=device is PathDevice and device.nrd_active
		_pending_device.sharc_enabled=GameData.option("pt_sharc")>0
		_pending_device.nrd.directional=GameData.option("pt_denoiser")>0 and not OS.get_cmdline_user_args().has("--ei-pt-nrd-radiance")
	var id := _pending_device.get_instance_id()
	_pending_device.prepared.connect(_prepared.bind(id))
	_pending_device.rendered.connect(_rendered.bind(id))
	if _path_mode: _pending_device.emitter_stats.connect(_emitter_stats.bind(id))
	if not _preparation_owner.is_empty(): ShaderCompilationScreen.update(_preparation_owner,_pipeline_phase())
	_pending_stage=0

## Packing placements, terrain material metadata and native resource creation
## used to land in the same 50–60 ms frame after the bounded gather completed.
## Keep the old scene visible while these independent stages take separate
## frames. The candidate is still revalidated before its atomic promotion.
func _prepare_candidate(terrain: EITerrain,camera: Camera3D) -> void:
	match _pending_stage:
		0:
			var initial := _pending_scene.updates(true)
			_pending_device.initial_poses=initial.poses
			for geometry: Dictionary in _pending_scene.geometries:
				_pending_geometries.append({"offset":geometry.offset,"count":geometry.count,"opaque":geometry.opaque,"cutoff":geometry.cutoff,"standard":geometry.standard,"surface":geometry.surface,"relief":geometry.relief,"terrain":geometry.terrain,"foliage_layer":geometry.foliage_layer,
					"leaf_light":geometry.leaf_light,"bark_relief":geometry.bark_relief,"emissive":geometry.emissive,"surface_layer":geometry.surface_layer,"detail_layer":geometry.detail_layer})
			for entry: Dictionary in _pending_scene.instances:
				_pending_placements.append({"geometry":entry.geometry,"transform":entry.transform,"mask":entry.mask,
					"lighting_offset":entry.get("lighting_offset",Vector3.ZERO)})
			_pending_stage=1
		1:
			if _path_mode:
				_pending_device.terrain.collect(_pending_scene,terrain)
				if _pending_scene.failed: _reject_candidate("snapshot_budget");return
				_pending_stats["terrain_material_bytes"]=_pending_device.terrain.data.size()
				_pending_stats["terrain_material_build_us"]=_pending_device.terrain.build_us
				_pending_stats["terrain_material_triangles"]=_pending_device.terrain.terrain_triangles
			_pending_stage=2
		2:
			Device.dispatch(_pending_device,&"build",[_pending_scene.vertices.to_byte_array(),_pending_scene.images,_pending_geometries,_pending_placements])
			_pending_geometries=[];_pending_placements=[];_pending_stage=-1
			_collect_lights(camera.global_position)

func _bind_outputs() -> void:
	if _bound: return
	RenderingServer.global_shader_parameter_set(&"ei_rt_gi",device.output)
	RenderingServer.global_shader_parameter_set(&"ei_rt_guide",device.guide)
	RenderingServer.global_shader_parameter_set(&"ei_rt_shadow0",device.shadow0)
	RenderingServer.global_shader_parameter_set(&"ei_rt_shadow1",device.shadow1)
	RenderingServer.global_shader_parameter_set(&"ei_pt_direct_sun",device.direct_sun if device is PathDevice else null)
	_bound=true

func _activate_candidate() -> void:
	var previous := device
	var preserve := previous is PathDevice and _pending_device is PathDevice and GameData.option("pt_accumulation")==0
	if preserve:
		Device.dispatch(_pending_device,&"adopt_history",[previous,_pending_scene.history_matches(_scene)])
		_handoff_updates=true
	elif _pending_device is PathDevice:_pending_device.defer_nrd=false
	device=_pending_device;_scene=_pending_scene;_center=_scene.center;stats=_pending_stats
	_pending_device=null;_pending_scene=null;_pending_ready=false;_pending_stats={}
	_ready_gpu=true;_bound=false
	if not preserve:_history_key="";_path_signature=PackedByteArray();_accumulation_frames=0
	_snapshot_generation+=1;_clear_failure()
	_topology_pending=false
	# Replace global bindings before retiring their previous GPU owners.
	_bind_outputs()
	_retire_device(previous)

func _clear_failure() -> void:
	_failed=false;_failure_reason="";_failure_watch=null;_retry_delay=0.0
	_failure_position=Vector3.INF;_failure_age=0.0;_failure_poll=0.0;_retry_attempt=0
	for key in ["fallback","replacement_failure","retry_attempt","retry_delay_seconds"]: stats.erase(key)

func _remember_failure(reason: String,position: Vector3,watch: Scene = null) -> void:
	_failure_reason=reason;_failure_position=position;_failure_watch=watch
	if _failure_watch!=null: _failure_watch.discard_geometry()
	_retry_attempt=mini(_retry_attempt+1,6);_retry_delay=minf(pow(2.0,_retry_attempt-1),30.0)
	_failure_age=0.0;_failure_poll=0.0;_failed=device==null
	stats["fallback" if _failed else "replacement_failure"]=reason
	stats["retry_attempt"]=_retry_attempt;stats["retry_delay_seconds"]=_retry_delay

func _allow_retry(position: Vector3,dt: float) -> bool:
	if _failure_reason.is_empty(): return true
	_failure_age+=maxf(dt,0.0);_retry_delay=maxf(0.0,_retry_delay-dt)
	stats["retry_delay_seconds"]=_retry_delay
	# Moving away from an over-budget region must not require toggling options.
	if _failure_age>=0.5 and position.distance_to(_failure_position)>16.0: return true
	if _retry_delay>0.0: return false
	if _failure_reason in ["pipeline_failed","snapshot_empty"]: return true
	_failure_poll-=dt
	if _failure_watch!=null and (_failure_poll<=0.0 or _failure_watch.topology_pending):
		_failure_poll=1.0
		return _failure_watch.topology_changed(500)
	return false

func _reject_candidate(reason: String) -> void:
	var failed_scene := _pending_scene
	var position := failed_scene.center if failed_scene!=null else _center
	if device==null: stats=_pending_stats
	_cancel_candidate()
	_remember_failure(reason,position,failed_scene if reason.begins_with("snapshot_") else null)

func _cancel_candidate() -> void:
	_end_preparation()
	_retire_device(_pending_device)
	_pending_device=null;_pending_scene=null;_pending_ready=false;_pending_stats={};_gather=null
	_pending_stage=-1;_pending_geometries=[];_pending_placements=[]

func _retire_device(retired: Device) -> void:
	if retired==null: return
	var ready_callback := _prepared.bind(retired.get_instance_id())
	if retired.prepared.is_connected(ready_callback): retired.prepared.disconnect(ready_callback)
	var rendered_callback := _rendered.bind(retired.get_instance_id())
	if retired.rendered.is_connected(rendered_callback): retired.rendered.disconnect(rendered_callback)
	if retired is PathDevice:
		var emitter_callback := _emitter_stats.bind(retired.get_instance_id())
		if retired.emitter_stats.is_connected(emitter_callback): retired.emitter_stats.disconnect(emitter_callback)
	Device.dispatch(retired,&"dispose")

func _path_cloud_texture() -> Texture2D:
	if _terrain==null or game._sky_cave or not Gfx.Clouds.shadows_enabled() or Gfx._cloud_owner!=_terrain.get_instance_id():return null
	if Gfx.Clouds.mode()==1:return Gfx._cloud_sheet_noise
	var field := Gfx._cloud_shadow_field
	return field.view.get_texture() if field!=null and is_instance_valid(field.view) and field._published and field.domain.w>0.0 else null

func _path_cloud_frame() -> PackedFloat32Array:
	var data:=PackedFloat32Array();data.resize(12)
	if _terrain==null or _path_cloud_texture()==null:return data
	var state: Vector4=Gfx._cloud_frame.state
	var phases: Vector4=Gfx._cloud_frame.phases
	var domain:=Vector4.ZERO
	if Gfx.Clouds.mode()>1:
		domain=Gfx._cloud_shadow_field.domain
		state.w=2.0
	for i in 4:data[i]=state[i];data[4+i]=phases[i];data[8+i]=domain[i]
	return data

func _frame(camera: Camera3D,size: Vector2i,quality: int,scene_changed := false,delta_seconds := 1.0/60.0,publish_points := true) -> PackedByteArray:
	var transform := camera.get_camera_transform()
	var view := Projection(transform.affine_inverse())
	var projection := camera.get_camera_projection()
	var key := "%s:%s:%s:%s"%[_mode,size,camera.get_instance_id(),camera.cull_mask]
	var history := key==_history_key and transform.origin.distance_to(_previous_camera.origin)<2.0 \
		and transform.basis.z.dot(_previous_camera.basis.z)>0.95
	var data := PackedFloat32Array()
	for matrix: Projection in [projection.inverse(),Projection(transform),_previous_view_projection,_previous_view]:
		for axis in 4:
			var v: Vector4=matrix[axis];data.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
	var sun := Gfx.sun.srgb_to_linear()
	var direction := Gfx._cloud_sun_direction
	# A cave has no outdoor sky transport. Its authored ambient floor travels
	# separately in PathSky's reserved channels, alongside local illumination.
	var sky := Color.BLACK if game._sky_cave else Gfx.ambient.srgb_to_linear()
	data.append_array(PackedFloat32Array([sun.r,sun.g,sun.b,GameData.option("rt_shadows"),direction.x,direction.y,direction.z,0.00465,
		sky.r,sky.g,sky.b,GameData.option("rt_gi"),_frame_number,GI_SAMPLES[quality],SHADOW_SAMPLES[quality],camera.near,
		float(camera.projection==Camera3D.PROJECTION_ORTHOGONAL),camera.far,float(history),Scene.RADIUS*2.0,
		_center.x,_center.y,_center.z,Scene.RADIUS]))
	var colours := PackedFloat32Array()
	var local_positions := PackedFloat32Array()
	var local_colours := PackedFloat32Array()
	var extra_signature := PackedFloat32Array()
	for i in (PATH_LIGHT_LIMIT if _path_mode else 7):
		var light: OmniLight3D = _lights[i].get_ref() if i<_lights.size() else null
		var position := Vector4.ZERO; var colour := Color(0,0,0,0)
		if light != null and light.is_visible_in_tree() and light.light_energy>0.0:
			var p := light.global_position; position = Vector4(p.x,p.y,p.z,light.omni_range)
			colour = light.light_color.srgb_to_linear()*light.light_energy
			colour.a = maxf(light.light_size,0.04)
			if _path_mode:
				colour.a = maxf(colour.a,float(light.get_meta(LocalLighting.PATH_SOURCE_RADIUS,0.0)))
				# Readability lights explicitly disable glossy highlights.
				if light.light_specular<=0.0:colour.a=-colour.a
		var pos := PackedFloat32Array([position.x,position.y,position.z,position.w])
		var rgb := PackedFloat32Array([colour.r,colour.g,colour.b,colour.a])
		local_positions.append_array(pos);local_colours.append_array(rgb)
		if i<7:
			data.append_array(pos);colours.append_array(rgb)
			if publish_points:RenderingServer.global_shader_parameter_set(StringName("ei_rt_point%d"%i),position)
		else:extra_signature.append_array(pos);extra_signature.append_array(rgb)
	data.append_array(colours)
	if _path_mode:
		# Cloud attenuation changes illumination, not the authored time of day.
		var daylight := Gfx.sun_day(Gfx.sun)
		if game._lights!=null and game.session!=null and game.session.state!=null:
			daylight=Gfx.sun_day(game._lights.sample("sunlight",game.session.state.world_time))
		var environment := PathSky.palette(Gfx.ambient,Gfx.sun,Gfx.fog_sky,game._sky_cave,daylight)
		# Progressive accumulation is valid only for an exactly unchanged
		# camera, projection, lighting and scene. Never retain moving shadows.
		var signature := data.slice(0,32)
		signature.append_array(data.slice(64,76));signature.append_array(data.slice(84,144))
		# The bounded trace region is an acceleration detail, not a light.
		# NRD rejects newly visible geometry by depth/normal and confidence.
		if GameData.option("pt_accumulation")==0:
			for i in range(44,48):signature[i]=0.0
		signature.append_array(environment)
		signature.append_array(extra_signature)
		var bytes := signature.to_byte_array()
		var clouds := _path_cloud_frame()
		var cloud_bytes := clouds.to_byte_array()
		var same_cloud_mode := _path_cloud_signature.size()==cloud_bytes.size() \
			and _path_cloud_signature.decode_float(3*4)==clouds[3]
		var stationary := history and not scene_changed and bytes==_path_signature and cloud_bytes==_path_cloud_signature
		var progressive := GameData.option("pt_accumulation")>0
		var limit := 256.0 if progressive else 8.0
		# Fire/lava flutter and the advancing daylight change every frame.
		# Keep a short responsive history for gradual lighting changes, while
		# moving/recoloured local sources and larger daylight changes reset.
		# Still-scene accumulation always requires exact lighting and geometry.
		var same_lighting := bytes.slice(32*4)==_path_signature.slice(32*4)
		var same_projection := bytes.slice(0,16*4)==_path_signature.slice(0,16*4)
		var weather_fading := _weather_fading()
		# Rain's cosine fade spans twenty world ticks (1.1 seconds), not
		# twenty seconds. Give it the same short response as fluttering fire.
		var outdoor_tolerance := clampf(0.1*delta_seconds*60.0,0.1,0.25) if weather_fading else 0.002
		var gentle_change := not progressive and not _strict_light_history and not same_lighting \
			and _small_lighting_change(bytes,_path_signature,outdoor_tolerance)
		if gentle_change:
			# At 60 Hz retain at most 2/3 of the previous estimate. Shorten
			# the history in slower frames so torch response does not acquire
			# a longer time constant when the game is under GPU pressure.
			# Daylight drift alone is tiny (bounded to 0.2% per channel).
			# It must not give the whole outdoor image the torch's short history
			# every frame. A changing local light still uses the fast response.
			var local_changed := bytes.slice(76*4,104*4)!=_path_signature.slice(76*4,104*4) or bytes.slice(116*4)!=_path_signature.slice(116*4)
			if local_changed or weather_fading:limit=minf(3.0,1.0/(1.0-pow(2.0/3.0,maxf(delta_seconds,0.001)*60.0)))
		var reuse := history and same_projection and same_cloud_mode and (stationary if progressive else same_lighting or gentle_change)
		if not reuse: data[82]=0.0
		_accumulation_frames=minf(_accumulation_frames+1,limit) if reuse else 1.0
		stats["history_reused"]=reuse;stats["history_limit"]=limit
		stats["light_history_limited"]=gentle_change and reuse and limit<8.0
		_path_signature=bytes
		_path_cloud_signature=cloud_bytes
		data.append_array(PackedFloat32Array([GameData.option("pt_mode")*2,limit,float(stationary),1]))
		var inverse_previous := _previous_view_projection.inverse()
		for axis in 4:
			var v: Vector4=inverse_previous[axis];data.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
		data.append_array(environment)
		data.append_array(clouds)
		# Weather changes every receiver; local flutter only needs a fast
		# response where those lights contribute to the visible surface.
		data.append_array(PackedFloat32Array([mini(_lights.size(),PATH_LIGHT_LIMIT),float(gentle_change and weather_fading),GameData.option("pt_sharc"),1]))
		data.append_array(local_positions);data.append_array(local_colours)
	_previous_view=view;_previous_view_projection=projection*view;_previous_camera=transform;_history_key=key
	_frame_number=(_frame_number+1)%1000000
	return data.to_byte_array()

func _weather_fading() -> bool:
	return not game._sky_cave and is_instance_valid(game.sound) and game.sound.weather!=null \
		and game.sound.weather.world==game.world and game.sound.weather._fade>0.0

static func _small_lighting_change(current: PackedByteArray, previous: PackedByteArray, outdoor_tolerance := 0.002) -> bool:
	# Signature floats 76..103 are the seven linear RGB/source-size records.
	# Projection is checked by the caller; ordinary camera motion reprojects.
	# Region and local-light positions/ranges stay exact. The campaign clock
	# advances sunlight and sky every frame, even with a stationary camera.
	if current.size()!=previous.size() or current.size()<116*4 or (current.size()-116*4)%32!=0: return false
	if current.slice(44*4,76*4)!=previous.slice(44*4,76*4): return false
	for offset in [32,40,104,108,112]:
		if current.decode_float((offset+3)*4)!=previous.decode_float((offset+3)*4): return false
		var old := Vector3(previous.decode_float(offset*4),previous.decode_float((offset+1)*4),previous.decode_float((offset+2)*4))
		var now := Vector3(current.decode_float(offset*4),current.decode_float((offset+1)*4),current.decode_float((offset+2)*4))
		if old==now: continue
		if not old.is_finite() or not now.is_finite(): return false
		# Do not blend newly enabled or extinguished illumination. A 0.2%
		# per-channel bound admits gradual daylight, not a weather/time jump.
		if minf(old.x,minf(old.y,old.z))<0.0 or minf(now.x,minf(now.y,now.z))<0.0: return false
		if old==Vector3.ZERO or now==Vector3.ZERO: return false
		for channel in 3:
			if absf(now[channel]-old[channel])>maxf(maxf(now[channel],old[channel]),0.0001)*outdoor_tolerance: return false
	if current.decode_float(39*4)!=previous.decode_float(39*4): return false
	var old_direction := Vector3(previous.decode_float(36*4),previous.decode_float(37*4),previous.decode_float(38*4))
	var direction := Vector3(current.decode_float(36*4),current.decode_float(37*4),current.decode_float(38*4))
	# At most 0.057 degrees per frame; responsive history remains bounded to
	# eight frames. Abrupt weather/time changes still reject it immediately.
	if not direction.is_finite() or not old_direction.is_finite() or direction.distance_squared_to(old_direction)>0.000001: return false
	var colour_offsets: Array[int]=[]
	for i in 7:colour_offsets.append((76+i*4)*4)
	for offset in range(116*4,current.size(),32):
		if current.slice(offset,offset+16)!=previous.slice(offset,offset+16):return false
		colour_offsets.append(offset+16)
	for offset: int in colour_offsets:
		if current.slice(offset,offset+16)==previous.slice(offset,offset+16): continue
		if current.decode_float(offset+12)!=previous.decode_float(offset+12): return false
		var old := Vector3(previous.decode_float(offset),previous.decode_float(offset+4),previous.decode_float(offset+8))
		var now := Vector3(current.decode_float(offset),current.decode_float(offset+4),current.decode_float(offset+8))
		if not old.is_finite() or not now.is_finite(): return false
		var old_peak := maxf(old.x,maxf(old.y,old.z));var new_peak := maxf(now.x,maxf(now.y,now.z))
		if minf(old_peak,new_peak)<=0.0: return false
		var ratio := new_peak/old_peak
		if ratio<0.9 or ratio>1.1: return false
		# Energy changes scale all three channels. A changed hue, even when
		# equally bright, is a new source and must not leave a colour trail.
		if (old/old_peak-now/new_peak).length_squared()>1.0e-10: return false
	return true

func _collect_lights(focus: Vector3) -> void:
	var found := []
	for node in get_tree().get_nodes_in_group(Gfx.POINT_LIGHT_GROUP):
		var light := node as OmniLight3D
		if light==null or not light.is_visible_in_tree() or light.light_energy<=0.0 or light.light_negative: continue
		var distance := maxf(light.global_position.distance_to(focus)-light.omni_range,0.0)
		if distance<Scene.RADIUS: found.append([distance,light])
	if _path_mode:
		# Only over-budget regions need camera-based pruning. Otherwise stable
		# identity order avoids changing the sampling distribution as we walk.
		if found.size()>PATH_LIGHT_LIMIT:
			found.sort_custom(func(a: Array,b: Array) -> bool:
				return _light_priority(a[1],focus)>_light_priority(b[1],focus))
			found.resize(PATH_LIGHT_LIMIT)
		found.sort_custom(func(a: Array,b: Array) -> bool:return a[1].get_instance_id()<b[1].get_instance_id())
	else:found.sort_custom(func(a: Array,b: Array) -> bool:
		return a[1].get_instance_id()<b[1].get_instance_id() if is_equal_approx(a[0],b[0]) else a[0]<b[0])
	var previous := _lights.map(func(w: WeakRef): return w.get_ref())
	_lights.clear()
	for i in mini(found.size(),PATH_LIGHT_LIMIT if _path_mode else 7): _lights.append(weakref(found[i][1]))
	stats["lights"]=_lights.size()
	stats["local_light_shadow_samples"]=4 if _path_mode and _lights.size()>7 else _lights.size()
	if previous!=_lights.map(func(w: WeakRef): return w.get_ref()): _history_key=""

static func _light_priority(light: OmniLight3D,focus: Vector3) -> float:
	var c:=light.light_color.srgb_to_linear()*light.light_energy
	var power:=maxf(c.r,maxf(c.g,c.b))
	return power/(1.0+light.global_position.distance_squared_to(focus)/maxf(light.omni_range*light.omni_range,0.01))

func _prepared(ok: bool,id: int) -> void:
	if _pending_device!=null and _pending_device.get_instance_id()==id:
		if ok: _pending_ready=true
		else: _reject_candidate("pipeline_failed")
	elif device!=null and device.get_instance_id()==id and not ok:
		var position := _center
		_release();_remember_failure("pipeline_failed",position)
	# Deferred notifications from retired generations cannot affect a successor.

func _emitter_stats(count: int,candidates: int,id: int) -> void:
	var target: Dictionary
	if device!=null and device.get_instance_id()==id: target=stats
	elif _pending_device!=null and _pending_device.get_instance_id()==id: target=_pending_stats
	else: return
	target["emissive_triangles"]=count;target["emissive_candidates"]=candidates

func _release() -> void:
	_set_ray_reconstruction(null,false)
	_set_gi_active(false)
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",0.0)
	stats["active"]=false;stats["rebuilding"]=false
	_bound=false;_ready_gpu=false;_center=Vector3.INF;_history_key=""
	_cancel_candidate();_clear_failure()
	_scene=null;_lights.clear();_path_signature=PackedByteArray();_path_cloud_signature=PackedByteArray();_accumulation_frames=0
	_ground_cache=Scene.Ground.new()
	_source_cache.clear();_source_cache=Scene.SourceCache.new()
	_topology_pending=false
	if device!=null:
		for key in [&"ei_rt_gi",&"ei_rt_guide",&"ei_rt_shadow0",&"ei_rt_shadow1",&"ei_pt_direct_sun"]:
			RenderingServer.global_shader_parameter_set(key,null)
		_retire_device(device);device=null
	Device.dispatch(_programs,&"dispose");_programs=Device.Programs.new()
	_handoff_updates=false
	_budget=Budget.new();_budget_clock=0
	stats.erase("emissive_triangles");stats.erase("emissive_candidates")

func _set_gi_active(active: bool) -> void:
	var path_active := active and _path_mode
	if Gfx.scene_rt_gi_active==active and Gfx.path_trace_active==path_active: return
	Gfx.scene_rt_gi_active=active
	Gfx.path_trace_active=path_active
	if is_instance_valid(game) and game._env!=null: Gfx.apply_env(game._env)

func _exit_tree() -> void: _release()

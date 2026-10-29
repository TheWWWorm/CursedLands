extends Node
## One bounded reflected scene view for Mirror water, optionally replaced by
## the experimental hardware RT texture. Natural retains SSR.
## Water has its own draw layer so the viewport never samples itself.
const WATER_LAYER := 1 << 16
## Camera masks have 32 bits; bit 20 is outside the default 20 scene layers.
## No geometry uses this marker. Test it only outside shadow passes: Godot
## 4.7's shadow RenderSceneDataRD does not initialize camera_visible_layers.
const CAMERA_MARKER := 1 << 20
## Screen-copy effects and projected gameplay markers belong to the main
## view. They have no physical reflected surface and can expose their quads.
const OMIT_SCREEN_EFFECT := """
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
 if (!IN_SHADOW_PASS && (CAMERA_VISIBLE_LAYERS & 1048576u) != 0u) { discard; }
#endif
"""
const REACH := 64.0
const MAX_SIZE := 2048.0
const RT_RESOLUTION_SCALES := [0.5, 0.75, 1.0]
const RT_SAMPLE_GRID := 2
const RayDevice = preload("res://src/game/fx/water_raytrace_device.gd")
const RayScene = preload("res://src/game/fx/water_raytrace_scene.gd")
const PathWater = preload("res://src/game/fx/path_trace_water_device.gd")
const Lighting = preload("res://src/game/fx/scene_raytrace.gd")
const CLIP := """
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
 if (!IN_SHADOW_PASS && (CAMERA_VISIBLE_LAYERS & 1048576u) != 0u &&
     (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < ei_water_mirror.x - 0.02) { discard; }
#endif
"""

var terrain: EITerrain
var viewport: SubViewport
var camera: Camera3D
var plane := -INF
var _poll := 0.0
var _source: Camera3D
var _plane_key := []   # camera frustum, position and plane of the last _select_plane
var _rows: Array[PackedInt32Array] = []   # even x of liquid cells per even y (_index)
var _rows_terrain: EITerrain
var _rt: RayDevice
var _rt_scene: RayScene
var _rt_live: RayScene
var _rt_pending: RayDevice
var _rt_pending_scene: RayScene
var _rt_pending_ready := false
var _rt_pending_plane := INF
var _rt_path_mode := false
# Off-tree frame producers share the main view's sky, cloud, local-light and
# history contracts. They never process, build a scene or publish main-view
# globals. Each reflected generation owns its own reprojection state.
var _rt_frame: Lighting
var _rt_pending_frame: Lighting
var _frame_delta := 1.0/60.0
var _rt_build_stage := -1
var _rt_geometries := []
var _rt_placements := []
var _rt_programs := RayDevice.Programs.new()
# Recenter snapshots use the same immutable mesh/texture sources. Reading
# them back from the GPU again stalls city walking even with staged builds.
var _rt_sources := RayScene.SourceCache.new()
var _rt_ground := RayScene.Ground.new()
var _rt_topology_poll := 0.0
var _rt_lights: Array[WeakRef] = []
var _rt_ready := false
var _rt_failed := false
var _rt_center := Vector3.INF
var _rt_plane := INF
var rt_stats := {}
var _settings_key := ""
var _needs_preparation := false
var _preparing := false
var _preparation_submitted := false
var _preparation_serial := 0
var _preparation_owner: StringName
var _mirror_draw_callback := Callable()


static func supported() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "forward_plus"


static func clip_source(code: String) -> String:
	return code.replace("void fragment() {", "void fragment() {" + CLIP)


static func screen_effect_source(code: String) -> String:
	return code.replace("void fragment() {", "void fragment() {" + OMIT_SCREEN_EFFECT)


static func reflected_transform(source: Transform3D, height: float) -> Transform3D:
	var flip := Vector3(1, -1, 1)
	# Reflecting a basis changes handedness. Reverse its right vector too;
	# the projective texture lookup accounts for that horizontal reversal.
	return Transform3D(Basis(-source.basis.x * flip, source.basis.y * flip, source.basis.z * flip),
		Vector3(source.origin.x, 2.0 * height - source.origin.y, source.origin.z))


static func target_size(size: Vector2) -> Vector2i:
	var scale := minf(1.0, MAX_SIZE / maxf(size.x, size.y))
	return Vector2i(maxi(2, roundi(size.x * scale)), maxi(2, roundi(size.y * scale)))


static func raytrace_target_size(size: Vector2, quality := 2) -> Vector2i:
	# Scale both viewport dimensions. High stays native at 1440p/4K too;
	# keep the sample grid independent so every tier retains smooth edges.
	var scale: float = RT_RESOLUTION_SCALES[clampi(quality, 0, RT_RESOLUTION_SCALES.size() - 1)]
	return Vector2i(maxi(2, roundi(size.x * scale)), maxi(2, roundi(size.y * scale)))


func request_refresh() -> void:
	_poll = 0.0
	_plane_key = []
	_rows_terrain = null


func _ready() -> void:
	process_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preparation_owner = StringName("pipeline:water:%d" % get_instance_id())


func _active() -> bool:
	if not is_instance_valid(terrain) or not terrain.is_visible_in_tree(): return false
	var world := terrain.game_world()
	if world == null: return false
	var game := world.get_parent() as Game
	return game != null and not game.simulation_only and game.world == world \
		and Gfx.on("gfx_water") and GameData.option("gfx_water_reflections") >= 2


func _sync_settings() -> void:
	var settings_key := "%s:%s:%s:%s:%s:%s:%s" % [GameData.option("gfx_water"), GameData.option("gfx_water_reflections"), GameData.option("q_water_rt_quality"), GameData.graphics_revision,GameData.option("pt_mode"),GameData.option("pt_accumulation"),GameData.option("pt_denoiser")]
	if settings_key != _settings_key:
		_finish_preparation()
		_settings_key = settings_key
		_rt_topology_poll = 0.0
		_rt_failed = false
		# A settings request cannot acknowledge geometry gathered under the
		# previous materials, nor wait for the ordinary topology poll interval.
		if _rt_scene != null or _rt_pending != null: _cancel_raytrace_candidate()
		var path_mode := GameData.option("pt_mode")>0
		if path_mode!=_rt_path_mode:
			_rt_path_mode=path_mode
		_needs_preparation = Gfx.on("gfx_water") and GameData.option("gfx_water_reflections") >= 2


func _process(dt: float) -> void:
	_frame_delta=dt
	_sync_settings()
	_rt_topology_poll -= dt
	if not _active():
		_disable()
		return
	var source := terrain.get_viewport().get_camera_3d()
	if source == null:
		_disable()
		return
	_poll -= dt
	if source != _source or _poll <= 0.0:
		# The scan (~1.5 ms in Rindale's mansion) depends only on the view and
		# the current plane while the water stays as it is (request_refresh).
		var key := [source.get_frustum(), source.global_position, plane, terrain]
		if source != _source or key != _plane_key:
			plane = _select_plane(source, true)
			_plane_key = [key[0], key[1], plane, terrain]
		_source = source
		_poll = 0.125
	if not is_finite(plane) or source.global_position.y < plane + 0.15:
		_disable()
		return
	if _needs_preparation and not _preparing: _begin_preparation()
	_configure_mirror(source, plane, source.get_camera_transform())
	var material := terrain._water_mat
	if GameData.option("gfx_water_reflections") == 3:
		_update_raytrace(source)
	else:
		if _rt != null or _rt_scene != null or _rt_pending != null:
			_release_raytrace()
			material.set_shader_parameter("planar_texture",viewport.get_texture())
		_rt_failed = false
		if _preparing and not _preparation_submitted:
			_preparation_submitted = true
			_mirror_draw_callback = _mirror_drawing.bind(_preparation_serial)
			RenderingServer.frame_pre_draw.connect(_mirror_draw_callback)


func _configure_mirror(source: Camera3D, height: float, pose: Transform3D) -> void:
	if viewport == null: _create_view()
	viewport.size = target_size(source.get_viewport().get_visible_rect().size)
	camera.keep_aspect = source.keep_aspect
	camera.projection = source.projection
	camera.fov = source.fov
	camera.size = source.size
	camera.frustum_offset = source.frustum_offset
	camera.near = source.near
	# The reflected bank has the same view depth as its virtual image. A
	# shorter far plane cuts distant banks off at eye level, then reveals
	# them as pitching down reduces their depth. REACH only bounds the water
	# surface search; geometry must use the main view's draw distance.
	camera.far = source.far
	camera.global_transform = reflected_transform(pose, height)
	camera.cull_mask = reflection_mask(source.cull_mask)
	RenderingServer.global_shader_parameter_set(&"ei_water_mirror", Vector3(height, 0, 0))
	var material := terrain._water_mat
	material.set_shader_parameter("planar_height", height)
	material.set_shader_parameter("planar_projection", camera.get_camera_projection())
	material.set_shader_parameter("planar_view", camera.global_transform.affine_inverse())
	material.set_shader_parameter("planar_enabled", true)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


## ShaderWarmup calls this only while a desktop loading cover allows forced
## draws. Its small material viewport cannot prepare the real scene target.
## Use the nearest authored water even when the loading camera faces away;
## the normal first gameplay update still selects its own visible plane.
func prepare_loading(source: Camera3D) -> bool:
	if not supported() or not _active() or GameData.option("gfx_water_reflections") != 2 \
			or LoadingScreen._current == null or OS.has_feature("web") or LoadingScreen.force_deferred:
		return false
	_sync_settings()
	if not _needs_preparation or source == null or not source.is_inside_tree(): return false
	if viewport != null and viewport.disable_3d: return false
	var width := terrain.sectors_x * EITerrain.SECTOR
	var height := terrain.sectors_y * EITerrain.SECTOR
	_index(width, height)
	var nearest := Vector3.INF
	var best := INF
	for row in _rows.size():
		var y := row * 2
		for x in _rows[row]:
			var i := y * width + x
			var level := terrain.water[i]
			if not is_finite(level) or terrain.liquid_ground[i] in [EITerrain.LAVA, 255]: continue
			var point := Vector3(x + 0.5, level, -y - 0.5)
			var distance := point.distance_squared_to(source.global_position)
			if distance >= best: continue
			if level < terrain.height_at(point.x, -point.z) + 0.08: continue
			nearest = point
			best = distance
	if not nearest.is_finite(): return false
	_begin_preparation()
	var eye := nearest + Vector3(0, clampf(absf(source.global_position.y - nearest.y), 2.0, 20.0), 8.0)
	var pose := Transform3D(Basis.IDENTITY, eye).looking_at(nearest)
	_configure_mirror(source, nearest.y, pose)
	if _rt != null or _rt_scene != null or _rt_pending != null:
		_release_raytrace()
		terrain._water_mat.set_shader_parameter("planar_texture", viewport.get_texture())
	# Finish both newly placed and stationary geometry passes, exactly as the
	# material warmup does. Only completed draws acknowledge this request.
	for settle in 4:
		RenderingServer.force_draw(true, 0.0)
		RenderingServer.force_sync()
	_finish_preparation()
	_disable()
	return true


func _begin_preparation() -> void:
	_preparing = true
	_preparation_submitted = false
	_preparation_serial += 1
	var screen := ShaderCompilationScreen.begin(get_tree(), _preparation_owner, ShaderCompilationScreen.WATER)
	if screen:
		# This independent viewport must also stay out of the canvas-only draw.
		var disabled := viewport.disable_3d if viewport else false
		if viewport: viewport.disable_3d = true
		screen.present()
		if viewport: viewport.disable_3d = disabled


func _mirror_drawing(serial: int) -> void:
	if not _preparing or serial != _preparation_serial or viewport == null: return
	# Another preparation owner can force a canvas-only draw. Its deferred
	# post-draw signal is not evidence that this reflection has rendered.
	if viewport.disable_3d or viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED: return
	RenderingServer.frame_pre_draw.disconnect(_mirror_draw_callback)
	_mirror_draw_callback = Callable()
	# frame_pre_draw fires before the engine queues the draw. Defer the fence
	# until afterward, then acknowledge only when that render command ends.
	_mirror_draw_submitted.call_deferred(serial)


func _mirror_draw_submitted(serial: int) -> void:
	if _preparing and serial == _preparation_serial:
		RenderingServer.call_on_render_thread(_mirror_draw_recorded.bind(weakref(self), serial))


static func _mirror_draw_recorded(owner: WeakRef, serial: int) -> void:
	_mirror_draw_finished.call_deferred(owner, serial)


static func _mirror_draw_finished(owner: WeakRef, serial: int) -> void:
	var target: Node = owner.get_ref()
	if is_instance_valid(target) and target.is_inside_tree() and target._preparing and serial == target._preparation_serial:
		target._finish_preparation()


func _preparation_rendered(serial: int, _ok: bool, device_id: int) -> void:
	var pending := _rt_pending != null and _rt_pending.get_instance_id() == device_id
	var active := _rt != null and _rt.get_instance_id() == device_id
	if _preparing and serial == _preparation_serial and (pending or active):
		# Failure also releases the cover; the existing planar fallback remains.
		_finish_preparation()


func _finish_preparation(clear_intent := true) -> void:
	if _mirror_draw_callback.is_valid() and RenderingServer.frame_pre_draw.is_connected(_mirror_draw_callback):
		RenderingServer.frame_pre_draw.disconnect(_mirror_draw_callback)
	_mirror_draw_callback = Callable()
	ShaderCompilationScreen.end(_preparation_owner)
	_preparing = false
	_preparation_submitted = false
	if clear_intent: _needs_preparation = false


func _update_raytrace(source: Camera3D) -> void:
	if not RayDevice.supported():
		_rt_failed = true
		rt_stats = {"supported":false,"fallback":"planar"}
		_finish_preparation()
		return
	if ShaderCompilationScreen.terrain_pending(terrain): return
	var changed := false
	if _rt_ready and _rt_live != null and (_rt_topology_poll <= 0.0 or _rt_live.topology_pending):
		_rt_topology_poll = 1.0
		_collect_raytrace_lights(source.global_position)
		changed = _rt_live.topology_changed(500)
	# Keep the complete reflection while gathering and building a replacement.
	# Recompiling pipelines and revealing every initially masked BLAS on its
	# first render used to turn each recenter into an unbounded frame spike.
	if not _rt_failed and _rt_scene == null and _rt_pending == null and (changed \
			or source.global_position.distance_to(_rt_center) > 16.0 or absf(plane-_rt_plane) > 0.25 or (_rt is PathWater)!=_rt_path_mode):
		_rt_pending_plane = plane
		_rt_scene = RayScene.new()
		_rt_scene._sources = _rt_sources
		_rt_scene._ground = _rt_ground
		_rt_scene.path_materials=_rt_path_mode
		if _rt_path_mode:_rt_scene.lighting_camera_mask=reflection_mask(source.cull_mask)
		# The water plane clips only the primary reflected ray. Underwater
		# geometry remains available to secondary paths and shadow rays.
		_rt_scene.begin(terrain,source.global_position,-INF if _rt_path_mode else plane)
	if _rt_scene != null and _rt_scene.step(1500 if _rt != null else 6000):
		_queue_raytrace_candidate()
	elif _rt_pending != null and _rt_build_stage >= 0:
		_prepare_raytrace_candidate()
	elif _rt_pending != null and not _rt_pending_ready:
		RayDevice.dispatch(_rt_pending,&"build_step")
	if _rt_pending_ready and _rt_pending.output_ready():
		if absf(plane-_rt_pending_plane)>0.25 or _rt_pending_scene.topology_changed():
			_cancel_raytrace_candidate()
		else:
			_promote_raytrace_candidate()
	if _rt_ready:
		_render_raytrace(source,_rt,_rt_live,_rt_center)
		terrain._water_mat.set_shader_parameter("planar_texture",_rt.reflection_output())
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		rt_stats["active"] = true
	if _rt_pending_ready:
		_render_raytrace(source,_rt_pending,_rt_pending_scene,_rt_pending_scene.center)
	if _rt_failed: _finish_preparation()
	rt_stats["rebuilding"] = _rt_scene != null or _rt_pending != null


func _queue_raytrace_candidate() -> void:
	_rt_pending_scene = _rt_scene
	_rt_scene = null
	if _rt_pending_scene.failed or _rt_pending_scene.triangles == 0:
		_rt_failed = true
		rt_stats["replacement_failure"] = "snapshot_budget"
		_cancel_raytrace_candidate()
		return
	_rt_pending = PathWater.new() if _rt_path_mode else RayDevice.new()
	if _rt_path_mode:
		_rt_pending.nrd.directional=GameData.option("pt_denoiser")>0
		_rt_pending_frame=Lighting.new(terrain.game_world().get_parent() as Game)
		_rt_pending_frame._path_mode=true;_rt_pending_frame._terrain=terrain
	_rt_pending.programs = _rt_programs
	_rt_pending.incremental_build = true
	_rt_pending.prepared.connect(_raytrace_prepared.bind(_rt_pending.get_instance_id()))
	_rt_pending.rendered.connect(_preparation_rendered.bind(_rt_pending.get_instance_id()))
	_rt_build_stage = 0


func _prepare_raytrace_candidate() -> void:
	if _rt_build_stage == 0:
		var initial := _rt_pending_scene.updates(true)
		_rt_pending.initial_poses = initial.poses
		for geometry: Dictionary in _rt_pending_scene.geometries:
			_rt_geometries.append({"offset":geometry.offset,"count":geometry.count,"opaque":geometry.opaque,
				"cutoff":geometry.cutoff,"standard":geometry.standard,"surface":geometry.surface,"relief":geometry.relief,"terrain":geometry.terrain,"foliage_layer":geometry.foliage_layer,
				"leaf_light":geometry.leaf_light,"bark_relief":geometry.bark_relief,"emissive":geometry.emissive,"surface_layer":geometry.surface_layer,"detail_layer":geometry.detail_layer})
		for entry: Dictionary in _rt_pending_scene.instances:
			_rt_placements.append({"geometry":entry.geometry,"transform":entry.transform,"mask":entry.mask})
		_rt_build_stage = 1
	elif _rt_build_stage==1 and _rt_pending is PathWater:
		_rt_pending.terrain.collect(_rt_pending_scene,terrain)
		if _rt_pending_scene.failed:
			_rt_failed=true;rt_stats["replacement_failure"]="terrain_budget";_cancel_raytrace_candidate();return
		_rt_build_stage=2
	else:
		RayDevice.dispatch(_rt_pending,&"build",[_rt_pending_scene.vertices.to_byte_array(),_rt_pending_scene.images,_rt_geometries,_rt_placements])
		_rt_geometries = []; _rt_placements = []; _rt_build_stage = -1
		_collect_raytrace_lights(_rt_pending_scene.center)


func _promote_raytrace_candidate() -> void:
	var previous := _rt
	if _rt_frame!=null:_rt_frame.free()
	_rt_frame=_rt_pending_frame;_rt_pending_frame=null
	_rt = _rt_pending; _rt_live = _rt_pending_scene
	_rt_center = _rt_live.center; _rt_plane = _rt_pending_plane; _rt_ready = true
	_rt_pending = null; _rt_pending_scene = null; _rt_pending_ready = false
	rt_stats.merge({"supported":true,"triangles":_rt_live.triangles,"textures":_rt_live.images.size(),
		"radius":RayScene.RADIUS,"geometries":_rt_live.geometries.size(),"instances":_rt_live.instances.size(),
		"native_scene":_rt_live._kernel != null,"build":_rt.build_timings},true)
	# Rebind before retiring the device that owns the sampled output.
	terrain._water_mat.set_shader_parameter("planar_texture",_rt.reflection_output())
	if previous != null: RayDevice.dispatch(previous,&"dispose")


func _render_raytrace(source: Camera3D, target_device: RayDevice, scene: RayScene, center: Vector3) -> void:
	var size := source.get_viewport().get_visible_rect().size
	var quality := clampi(GameData.option("q_water_rt_quality"), 0, RT_RESOLUTION_SCALES.size() - 1)
	var target := raytrace_target_size(size, quality)
	if target_device is PathWater:
		_render_path_water(target_device,scene,center,target,quality)
		return
	var frame := PackedFloat32Array()
	var inverse := camera.get_camera_projection().inverse()
	var transform := Projection(camera.global_transform)
	for matrix: Projection in [inverse,transform]:
		for axis in 4:
			var v: Vector4 = matrix[axis]
			frame.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
	var sun_direction := Gfx._cloud_sun_direction
	frame.append_array(PackedFloat32Array([Gfx.ambient.r,Gfx.ambient.g,Gfx.ambient.b,RT_SAMPLE_GRID,
		Gfx.sun.r,Gfx.sun.g,Gfx.sun.b,1,sun_direction.x,sun_direction.y,sun_direction.z,plane,
		Gfx.fog_depth.x,Gfx.fog_depth.y,source.far,1.0 if source.projection == Camera3D.PROJECTION_ORTHOGONAL else 0.0,Gfx.fog_sky.r,Gfx.fog_sky.g,Gfx.fog_sky.b,
		2.0/absf(camera.get_camera_projection().y.y)/target.y,
		center.x,center.y,center.z,RayScene.RADIUS]))
	var colours := PackedFloat32Array()
	for i in 4:
		var light: OmniLight3D = _rt_lights[i].get_ref() if i < _rt_lights.size() else null
		if light != null and light.is_visible_in_tree() and light.light_energy > 0.0:
			var p := light.global_position
			var c := (light.light_color.srgb_to_linear()*light.light_energy).linear_to_srgb()
			var local := is_equal_approx(light.light_specular,Gfx.LOCAL_SPECULAR) or is_equal_approx(light.light_specular,Gfx.LOCAL_SPECULAR_PASS)
			frame.append_array(PackedFloat32Array([p.x,p.y,p.z,light.omni_range]))
			colours.append_array(PackedFloat32Array([c.r,c.g,c.b,2.0 if local else 1.0 if is_equal_approx(light.light_specular,Gfx.ADDITIVE_SPECULAR) else 0.0]))
		else:
			frame.append_array(PackedFloat32Array([0,0,0,0])); colours.append_array(PackedFloat32Array([0,0,0,0]))
	frame.append_array(colours)
	var changes := scene.updates()
	_submit_frame(target_device,target,frame.to_byte_array(),changes)
	rt_stats["path_traced"] = false
	_update_render_stats(changes,target,quality)


func _render_path_water(target_device: PathWater,scene: RayScene,center: Vector3,target: Vector2i,quality: int) -> void:
	var producer := _rt_frame if target_device==_rt else _rt_pending_frame
	if producer==null:return
	producer._center=center;producer._lights=_rt_lights
	producer._mode="water:%s:%s:%s:%s"%[plane,GameData.option("pt_mode"),GameData.option("pt_accumulation"),GameData.option("pt_denoiser")]
	var changes := scene.updates()
	changes["nrd_directional"]=GameData.option("pt_denoiser")>0 and not OS.get_cmdline_user_args().has("--ei-pt-nrd-radiance")
	# Four fixed primary samples each trace a continuation path. Water quality
	# changes resolution; it does not silently multiply four into sixteen paths.
	var bytes := producer._frame(camera,target,0,not changes.instances.is_empty() or not changes.poses.is_empty(),_frame_delta,false)
	bytes.encode_float(67*4,1.0);bytes.encode_float(75*4,1.0)
	var fog := Gfx.fog_sky.srgb_to_linear()
	bytes.append_array(PackedFloat32Array([plane,Gfx.fog_depth.x,Gfx.fog_depth.y,0,fog.r,fog.g,fog.b,0]).to_byte_array())
	RayDevice.dispatch(target_device,&"set_cloud_texture",[producer._path_cloud_texture()])
	_submit_frame(target_device,target,bytes,changes)
	rt_stats["path_traced"]=true;rt_stats["bounces"]=GameData.PathTraceSettings.bounces(GameData.option("pt_mode"))
	rt_stats["nrd_directional"]=target_device.nrd_active and target_device.nrd.directional
	_update_render_stats(changes,target,quality)


func _submit_frame(target_device: RayDevice,target: Vector2i,frame: PackedByteArray,changes: Dictionary) -> void:
	var filtering := clampi(GameData.option("q_aniso"),0,4)
	if _preparing and not _preparation_submitted and (target_device == _rt_pending \
			or (target_device == _rt and _rt_scene == null and _rt_pending == null)):
		_preparation_submitted = true
		ShaderCompilationScreen.update(_preparation_owner, ShaderCompilationScreen.FIRST_FRAME)
		RayDevice.dispatch(target_device,&"render_preparation",[_preparation_serial,target,frame,changes,filtering])
	else:
		RayDevice.dispatch(target_device,&"render",[target,frame,changes,filtering])


func _update_render_stats(changes: Dictionary,target: Vector2i,quality: int) -> void:
	rt_stats["updated_instances"] = changes.instances.size()
	rt_stats["updated_morphs"] = changes.poses.size()
	rt_stats["lights"] = _rt_lights.size()
	rt_stats["size"] = [target.x,target.y]
	rt_stats["quality"] = quality
	rt_stats["samples_per_pixel"] = RT_SAMPLE_GRID * RT_SAMPLE_GRID
	rt_stats["texture_anisotropy"] = 1 << clampi(GameData.option("q_aniso"),0,4)


func _collect_raytrace_lights(focus: Vector3) -> void:
	var found := []
	for node in get_tree().get_nodes_in_group(Gfx.POINT_LIGHT_GROUP):
		var light := node as OmniLight3D
		if light == null or not light.is_visible_in_tree() or light.light_energy <= 0.0 or light.light_negative: continue
		var distance := maxf(light.global_position.distance_to(focus)-light.omni_range,0.0)
		if distance < RayScene.RADIUS: found.append([distance,light])
	found.sort_custom(func(a: Array,b: Array) -> bool: return a[0] < b[0])
	if _rt_path_mode:
		if found.size()>Lighting.PATH_LIGHT_LIMIT:
			found.sort_custom(func(a: Array,b: Array) -> bool:return Lighting._light_priority(a[1],focus)>Lighting._light_priority(b[1],focus))
			found.resize(Lighting.PATH_LIGHT_LIMIT)
		found.sort_custom(func(a: Array,b: Array) -> bool:return a[1].get_instance_id()<b[1].get_instance_id())
	_rt_lights.clear()
	for i in mini(found.size(),Lighting.PATH_LIGHT_LIMIT if _rt_path_mode else 4): _rt_lights.append(weakref(found[i][1]))


func _raytrace_prepared(ok: bool, id: int) -> void:
	# The device also reports a later dispatch failure through this signal.
	# Its old candidate callback remains connected after promotion.
	if not ok and _rt != null and id == _rt.get_instance_id():
		_rt_failed = true
		rt_stats["fallback"] = "pipeline_failed"
		_finish_preparation()
		if is_instance_valid(terrain) and terrain._water_mat and viewport:
			terrain._water_mat.set_shader_parameter("planar_texture",viewport.get_texture())
		_release_raytrace()
		return
	if _rt_pending == null or id != _rt_pending.get_instance_id(): return
	_rt_pending_ready = ok
	if not ok:
		_rt_failed = true
		rt_stats["replacement_failure"] = "pipeline_failed"
		_finish_preparation()
		_cancel_raytrace_candidate()


func _cancel_raytrace_candidate() -> void:
	if _rt_pending_frame!=null:_rt_pending_frame.free();_rt_pending_frame=null
	_rt_scene = null; _rt_pending_scene = null; _rt_pending_ready = false
	_rt_geometries = []; _rt_placements = []; _rt_build_stage = -1
	if _rt_pending != null:
		RayDevice.dispatch(_rt_pending,&"dispose")
		_rt_pending = null
	_preparation_submitted = false


func _release_raytrace() -> void:
	if _rt_frame!=null:_rt_frame.free();_rt_frame=null
	_rt_sources.clear();_rt_ground=RayScene.Ground.new()
	_cancel_raytrace_candidate()
	_rt_ready = false
	rt_stats["active"] = false
	_rt_live = null
	_rt_lights.clear()
	_rt_center = Vector3.INF
	_rt_plane = INF
	if _rt != null:
		RayDevice.dispatch(_rt,&"dispose")
		_rt = null


static func reflection_mask(source_mask: int) -> int:
	return (source_mask & ~(WATER_LAYER | EIUnitModel.CLOSE_VIEW_LAYER)) | CAMERA_MARKER | EIUnitModel.REFLECTION_LAYER


func _create_view() -> void:
	viewport = SubViewport.new()
	viewport.name = "WaterReflectionView"
	configure_viewport(viewport,terrain.get_world_3d())
	add_child(viewport)
	camera = Camera3D.new()
	camera.environment = reflection_environment()
	viewport.add_child(camera)
	camera.current = true
	terrain._water_mat.set_shader_parameter("planar_texture", viewport.get_texture())


## Shader preparation uses these exact framebuffer/environment settings;
## the main viewport's DLSS, MSAA and fog pipelines cannot stand in for them.
static func configure_viewport(view: SubViewport, world: World3D) -> void:
	# SubViewports default to interpolation ON even when the main viewport
	# is OFF. This camera follows the render-frame pose; interpolating it
	# again makes the rendered bank lag behind planar_view during fast turns.
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.world_3d = world
	view.transparent_bg = true
	view.gui_disable_input = true
	view.positional_shadow_atlas_size = 0
	view.msaa_3d = Viewport.MSAA_2X


static func reflection_environment() -> Environment:
	# The water shader already supplies sky/cloud colour. Avoid a second sky,
	# post-process stack and depth-of-field pass in this small geometry view.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	return environment


func _disable() -> void:
	# Defer initial/settings work until water is visible, without showing a
	# modal screen for ordinary camera-driven reflection replacement.
	_finish_preparation(false)
	rt_stats["active"] = false
	if is_instance_valid(terrain) and terrain._water_mat:
		terrain._water_mat.set_shader_parameter("planar_enabled", false)
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _exit_tree() -> void:
	_finish_preparation()
	_disable()
	if is_instance_valid(terrain) and terrain._water_mat:
		terrain._water_mat.set_shader_parameter("planar_texture", null)
	_release_raytrace()
	RayDevice.dispatch(_rt_programs,&"dispose")


## The liquid cells of the even rows and columns _select_plane probes. Level
## changes (EITerrain.set_water_offset) keep a cell finite or not; a new
## terrain or request_refresh rebuilds the list.
func _index(width: int, height: int) -> void:
	if _rows_terrain == terrain and _rows.size() == (height + 1) >> 1:
		return
	_rows_terrain = terrain
	_rows.clear()
	_rows.resize((height + 1) >> 1)
	for y in range(0, height, 2):
		var row := PackedInt32Array()
		for x in range(0, width, 2):
			var i := y * width + x
			if is_finite(terrain.water[i]) and not terrain.liquid_ground[i] in [EITerrain.LAVA, 255]:
				row.append(x)
		_rows[y >> 1] = row


## `indexed` scans only the liquid cells found when the water was last
## refreshed (_index); direct callers that edit the water arrays scan all.
func _select_plane(source: Camera3D, indexed := false) -> float:
	var position := source.global_position
	# Camera3D.is_position_in_frustum rebuilds all six projection planes on
	# every call. A water scan can test thousands of cells with one camera.
	var frustum := source.get_frustum()
	var width := terrain.sectors_x * EITerrain.SECTOR
	var height := terrain.sectors_y * EITerrain.SECTOR
	var groups := {}
	if indexed: _index(width, height)
	var x0 := maxi(0, int(position.x - REACH)) & ~1
	var x1 := mini(width, int(position.x + REACH))
	# Probe original liquid cells, not walkable bridge heights. Bucket nearby
	# surface levels so tiny authored river slopes share a stable plane.
	for y in range(maxi(0, int(-position.z - REACH)) & ~1, mini(height, int(-position.z + REACH)), 2):
		var row := _rows[y >> 1] if indexed else PackedInt32Array()
		if indexed and row.is_empty(): continue
		var k := row.bsearch(x0) if indexed else 0
		var x := x0 - 2
		while true:
			if indexed:
				if k >= row.size(): break
				x = row[k]
				k += 1
			else:
				x += 2
			if x >= x1: break
			var i := y * width + x
			var water_height := terrain.water[i]
			if not is_finite(water_height) or terrain.liquid_ground[i] in [EITerrain.LAVA, 255]: continue
			# A higher upstream pool may be inside the frustum while hidden by
			# its bank. It cannot reflect toward an eye below its surface. Do
			# not let its votes replace the visible lower river and disable the
			# entire mirror when the camera pitches up (Karansul's Lands).
			if water_height >= position.y - 0.15: continue
			var point := Vector3(x + 0.5, water_height, -y - 0.5)
			var distance := point.distance_squared_to(position)
			# REACH bounds the map cells searched, not the camera's altitude.
			# A tactical eye above 64 m can still look straight into this lake.
			# Keep actual 3D distance for level ranking and the frustum for range.
			if Vector2(point.x-position.x,point.z-position.z).length_squared() > REACH * REACH: continue
			var visible := true
			var cell := Vector3(x + 1.0, water_height, -y - 1.0)
			for boundary: Plane in frustum:
				# This probe represents a 2 m water tile. Its centre can leave
				# the screen while the foreground surface still fills its edge.
				# Test the tile bounds so a slight tilt does not select a remote
				# level simply because that one point fell outside the frustum.
				var radius := absf(boundary.normal.x) + absf(boundary.normal.z) + 0.125 * absf(boundary.normal.y)
				if boundary.distance_to(cell) > radius:
					visible = false
					break
			if not visible: continue
			if water_height < terrain.height_at(point.x, -point.z) + 0.08: continue
			var weight := 1.0 / maxf(4.0, distance)
			var key := roundi(water_height * 4.0)
			var group: Vector3 = groups.get(key, Vector3(0, 0, INF))
			groups[key] = Vector3(group.x + weight, group.y + water_height * weight, minf(group.z, distance))
	var best := -INF
	var score := 0.0
	for key in groups:
		var group: Vector3 = groups[key]
		var candidate := group.y / group.x
		# A broad pool beyond a waterfall must not outvote a narrow foreground
		# stream merely because tilting the camera exposes more of its cells.
		# Choose the nearest visible level, retaining the same small hysteresis.
		var weight := 1.0 / maxf(4.0, group.z) * (1.25 if is_finite(plane) and absf(candidate - plane) < 0.25 else 1.0)
		if weight > score:
			score = weight
			best = candidate
	return best

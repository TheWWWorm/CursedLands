extends Node
## Optional scene lighting. The conventional path remains live while scene
## snapshots build, outside the bounded RT region, or on unsupported devices.
const Device = preload("res://src/game/fx/scene_raytrace_device.gd")
const PathDevice = preload("res://src/game/fx/path_trace_device.gd")
const PathSky = preload("res://src/game/fx/path_trace_sky.gd")
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
const SCALES := [0.5,0.75,1.0]
const GI_SAMPLES := [1,2,4]
const SHADOW_SAMPLES := [1,2,4]
const RECEIVER_RADIUS := 72.0
const REASON := "Scene ray tracing needs a ray-tracing GPU and the qualified DX12 or Vulkan Forward+ renderer. Conventional lighting remains available."

var game: Game
var stats := {}
var device: Device
var _gather: Scene
var _scene: Scene
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
var _accumulation_frames := 0

func _init(owner_game: Game) -> void:
	game = owner_game; name = "SceneRaytrace"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 101
	Gfx.ensure_globals()

static func target_size(viewport: Vector2,quality: int) -> Vector2i:
	var scale: float = SCALES[clampi(quality,0,2)]
	return Vector2i(maxi(2,roundi(viewport.x*scale)),maxi(2,roundi(viewport.y*scale)))

func _process(dt: float) -> void:
	var wanted := Gfx.SceneRaytraceShader.requested()
	var terrain: EITerrain = game.world.terrain if game.world != null else null
	var path_mode := GameData.option("pt_mode")>0
	var mode := "%s:%s:%s:%s:%s"%[GameData.option("rt_shadows"),GameData.option("rt_gi"),GameData.option("q_rt_lighting"),GameData.option("pt_mode"),GameData.option("pt_accumulation")]
	if mode != _mode or terrain != _terrain:
		if terrain != _terrain or path_mode!=_path_mode: _release()
		_path_mode=path_mode
		_mode = mode; _terrain = terrain; _failed = false; _history_key=""
	if not wanted or not is_instance_valid(terrain) or not terrain.is_visible_in_tree() or game.simulation_only:
		if device != null or _gather != null: _release()
		return
	if _failed: return
	if not Device.supported():
		_failed = true; stats = {"active":false,"supported":false,"fallback":"unsupported"}; return
	var camera := terrain.get_viewport().get_camera_3d()
	if camera == null: _release(); return
	_poll -= dt
	if _scene != null and _poll<=0.0:
		_poll = 1.0
		_collect_lights(camera.global_position)
		if _scene.topology_changed(): _release()
	if camera.global_position.distance_to(_center)>16.0:
		_release(); _center = camera.global_position
		_gather = Scene.new(); _gather.lighting_camera_mask = camera.cull_mask
		_gather.path_materials = _path_mode
		# No water-plane clipping: ceilings, underground rooms and banks all
		# participate in the lighting acceleration structure.
		_gather.begin(terrain,_center,-1.0e20)
	if _gather != null:
		if not _gather.step(): return
		stats = {"active":false,"supported":true,"triangles":_gather.triangles,"geometries":_gather.geometries.size(),"instances":_gather.instances.size()}
		if _gather.failed or _gather.triangles==0:
			_failed = true; stats["fallback"]="snapshot_budget"; _gather=null; return
		var geometries := []; var placements := []
		for geometry: Dictionary in _gather.geometries:
			geometries.append({"offset":geometry.offset,"count":geometry.count,"opaque":geometry.opaque,"cutoff":geometry.cutoff,"standard":geometry.standard,"surface":geometry.surface,"relief":geometry.relief,"terrain":geometry.terrain,"foliage_layer":geometry.foliage_layer,
				"leaf_light":geometry.leaf_light,"bark_relief":geometry.bark_relief,"emissive":geometry.emissive,"surface_layer":geometry.surface_layer,"detail_layer":geometry.detail_layer})
		for entry: Dictionary in _gather.instances:
			placements.append({"geometry":entry.geometry,"transform":entry.transform,"mask":0})
		device = PathDevice.new() if _path_mode else Device.new()
		if _path_mode:
			device.terrain.collect(_gather,terrain)
			if _gather.failed:
				_failed=true;stats["fallback"]="snapshot_budget";device=null;_gather=null;return
			stats["terrain_material_bytes"]=device.terrain.data.size()
			stats["terrain_material_build_us"]=device.terrain.build_us
			stats["terrain_material_triangles"]=device.terrain.terrain_triangles
		device.prepared.connect(_prepared)
		if _path_mode: device.emitter_stats.connect(_emitter_stats)
		RenderingServer.call_on_render_thread(device.build.bind(_gather.vertices.to_byte_array(),_gather.images,geometries,placements))
		_scene = _gather; _gather = null
		_collect_lights(camera.global_position)
	if not _ready_gpu: return
	_scene.lighting_camera_mask = camera.cull_mask
	var quality := clampi(GameData.option("q_rt_lighting"),0,2)
	var size := target_size(camera.get_viewport().get_visible_rect().size,quality)
	var changes := _scene.updates()
	var frame := _frame(camera,size,quality,not changes.instances.is_empty() or not changes.poses.is_empty())
	RenderingServer.call_on_render_thread(device.render.bind(size,frame,changes,GameData.option("q_aniso")))
	if device.output.get_width()>0:
		_set_gi_active(_path_mode or GameData.option("rt_gi")>0)
		if not _bound:
			RenderingServer.global_shader_parameter_set(&"ei_rt_gi",device.output)
			RenderingServer.global_shader_parameter_set(&"ei_rt_guide",device.guide)
			RenderingServer.global_shader_parameter_set(&"ei_rt_shadow0",device.shadow0)
			RenderingServer.global_shader_parameter_set(&"ei_rt_shadow1",device.shadow1)
			_bound = true
		var view_projection := camera.get_camera_projection()*Projection(camera.get_camera_transform().affine_inverse())
		RenderingServer.global_shader_parameter_set(&"ei_rt_view_projection",view_projection)
		RenderingServer.global_shader_parameter_set(&"ei_rt_inverse_view_projection",view_projection.inverse())
		RenderingServer.global_shader_parameter_set(&"ei_rt_view",Projection(camera.get_camera_transform().affine_inverse()))
		RenderingServer.global_shader_parameter_set(&"ei_rt_eye",camera.get_camera_transform().origin)
		RenderingServer.global_shader_parameter_set(&"ei_rt_center",Vector4(_center.x,_center.y,_center.z,0))
		RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4(1,GameData.option("rt_shadows"),GameData.option("rt_gi"),RECEIVER_RADIUS))
		RenderingServer.global_shader_parameter_set(&"ei_pt_active",float(_path_mode))
		stats["active"]=true
	stats["size"]=[size.x,size.y]; stats["quality"]=quality
	stats["gi_samples"]=GI_SAMPLES[quality] if GameData.option("rt_gi")>0 else 0
	stats["shadow_samples"]=SHADOW_SAMPLES[quality] if GameData.option("rt_shadows")>0 else 0
	stats["lights"]=_lights.size();stats["updated_instances"]=changes.instances.size();stats["updated_poses"]=changes.poses.size()
	stats["path_tracing"]=_path_mode;stats["path_bounces"]=GameData.option("pt_mode")*2 if _path_mode else 0
	stats["path_samples"]=GI_SAMPLES[quality] if _path_mode else 0
	stats["accumulation_frames"]=_accumulation_frames if _path_mode else 0

func _frame(camera: Camera3D,size: Vector2i,quality: int,scene_changed := false) -> PackedByteArray:
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
	# A cave has no unoccluded outdoor sky. Its authored lights and emissive
	# surfaces supply indirect illumination instead of an ambient floor.
	var sky := Color.BLACK if game._sky_cave else Gfx.ambient.srgb_to_linear()
	data.append_array(PackedFloat32Array([sun.r,sun.g,sun.b,GameData.option("rt_shadows"),direction.x,direction.y,direction.z,0.00465,
		sky.r,sky.g,sky.b,GameData.option("rt_gi"),_frame_number,GI_SAMPLES[quality],SHADOW_SAMPLES[quality],camera.near,
		float(camera.projection==Camera3D.PROJECTION_ORTHOGONAL),camera.far,float(history),Scene.RADIUS*2.0,
		_center.x,_center.y,_center.z,Scene.RADIUS]))
	var colours := PackedFloat32Array()
	for i in 7:
		var light: OmniLight3D = _lights[i].get_ref() if i<_lights.size() else null
		var position := Vector4.ZERO; var colour := Color(0,0,0,0)
		if light != null and light.is_visible_in_tree() and light.light_energy>0.0:
			var p := light.global_position; position = Vector4(p.x,p.y,p.z,light.omni_range)
			colour = light.light_color.srgb_to_linear()*light.light_energy
			colour.a = maxf(light.light_size,0.04)
		data.append_array(PackedFloat32Array([position.x,position.y,position.z,position.w]))
		colours.append_array(PackedFloat32Array([colour.r,colour.g,colour.b,colour.a]))
		RenderingServer.global_shader_parameter_set(StringName("ei_rt_point%d"%i),position)
	data.append_array(colours)
	if _path_mode:
		var environment := PathSky.palette(Gfx.ambient,Gfx.sun,Gfx.fog_sky,game._sky_cave)
		# Progressive accumulation is valid only for an exactly unchanged
		# camera, projection, lighting and scene. Never retain moving shadows.
		var signature := data.slice(0,32)
		signature.append_array(data.slice(64,76));signature.append_array(data.slice(84,144))
		signature.append_array(environment)
		var bytes := signature.to_byte_array()
		var stationary := history and not scene_changed and bytes==_path_signature
		var limit := 256 if GameData.option("pt_accumulation")>0 else 8
		_accumulation_frames=mini(_accumulation_frames+1,limit) if stationary else 1
		# Responsive history reprojects through ordinary camera motion. Light
		# changes invalidate both modes; still-scene history also requires an
		# identical camera and geometry on every contributing frame.
		var same_lighting := bytes.slice(32*4)==_path_signature.slice(32*4)
		var same_projection := bytes.slice(0,16*4)==_path_signature.slice(0,16*4)
		if not same_lighting or not same_projection or (limit>8 and not stationary): data[82]=0.0
		_path_signature=bytes
		data.append_array(PackedFloat32Array([GameData.option("pt_mode")*2,limit,float(stationary),1]))
		var inverse_previous := _previous_view_projection.inverse()
		for axis in 4:
			var v: Vector4=inverse_previous[axis];data.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
		data.append_array(environment)
	_previous_view=view;_previous_view_projection=projection*view;_previous_camera=transform;_history_key=key
	_frame_number=(_frame_number+1)%1000000
	return data.to_byte_array()

func _collect_lights(focus: Vector3) -> void:
	var found := []
	for node in get_tree().get_nodes_in_group(Gfx.POINT_LIGHT_GROUP):
		var light := node as OmniLight3D
		if light==null or not light.is_visible_in_tree() or light.light_energy<=0.0 or light.light_negative: continue
		var distance := maxf(light.global_position.distance_to(focus)-light.omni_range,0.0)
		if distance<Scene.RADIUS: found.append([distance,light])
	found.sort_custom(func(a: Array,b: Array) -> bool:
		return a[1].get_instance_id()<b[1].get_instance_id() if is_equal_approx(a[0],b[0]) else a[0]<b[0])
	var previous := _lights.map(func(w: WeakRef): return w.get_ref())
	_lights.clear()
	for i in mini(found.size(),7): _lights.append(weakref(found[i][1]))
	if previous!=_lights.map(func(w: WeakRef): return w.get_ref()): _history_key=""

func _prepared(ok: bool) -> void:
	_ready_gpu=ok
	if not ok:
		_release();_failed=true;stats["fallback"]="pipeline_failed"

func _emitter_stats(count: int, candidates: int) -> void:
	stats["emissive_triangles"]=count;stats["emissive_candidates"]=candidates

func _release() -> void:
	_set_gi_active(false)
	RenderingServer.global_shader_parameter_set(&"ei_rt_state",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_pt_active",0.0)
	stats["active"]=false;_bound=false;_ready_gpu=false;_center=Vector3.INF;_history_key=""
	_gather=null;_scene=null;_lights.clear()
	_path_signature=PackedByteArray();_accumulation_frames=0
	if device!=null:
		for key in [&"ei_rt_gi",&"ei_rt_guide",&"ei_rt_shadow0",&"ei_rt_shadow1"]:
			RenderingServer.global_shader_parameter_set(key,null)
		device.prepared.disconnect(_prepared)
		if device is PathDevice: device.emitter_stats.disconnect(_emitter_stats)
		RenderingServer.call_on_render_thread(device.dispose);device=null
	stats.erase("emissive_triangles");stats.erase("emissive_candidates")

func _set_gi_active(active: bool) -> void:
	if Gfx.scene_rt_gi_active==active: return
	Gfx.scene_rt_gi_active=active
	if is_instance_valid(game) and game._env!=null: Gfx.apply_env(game._env)

func _exit_tree() -> void: _release()

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
const RayDevice = preload("res://src/game/fx/water_raytrace_device.gd")
const RayScene = preload("res://src/game/fx/water_raytrace_scene.gd")
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
var _rt: RayDevice
var _rt_scene: RayScene
var _rt_live: RayScene
var _rt_topology_poll := 0.0
var _rt_lights: Array[WeakRef] = []
var _rt_ready := false
var _rt_failed := false
var _rt_center := Vector3.INF
var _rt_plane := INF
var rt_stats := {}


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


func request_refresh() -> void:
	_poll = 0.0


func _ready() -> void:
	process_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _active() -> bool:
	if not is_instance_valid(terrain) or not terrain.is_visible_in_tree(): return false
	var world := terrain.game_world()
	if world == null: return false
	var game := world.get_parent() as Game
	return game != null and not game.simulation_only and game.world == world \
		and Gfx.on("gfx_water") and GameData.option("gfx_water_reflections") >= 2


func _process(dt: float) -> void:
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
		plane = _select_plane(source)
		_source = source
		_poll = 0.125
	if not is_finite(plane) or source.global_position.y < plane + 0.15:
		_disable()
		return
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
	camera.global_transform = reflected_transform(source.get_camera_transform(), plane)
	camera.cull_mask = (source.cull_mask & ~WATER_LAYER) | CAMERA_MARKER
	RenderingServer.global_shader_parameter_set(&"ei_water_mirror", Vector3(plane, 0, 0))
	var material := terrain._water_mat
	material.set_shader_parameter("planar_height", plane)
	material.set_shader_parameter("planar_projection", camera.get_camera_projection())
	material.set_shader_parameter("planar_view", camera.global_transform.affine_inverse())
	material.set_shader_parameter("planar_enabled", true)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if GameData.option("gfx_water_reflections") == 3:
		_update_raytrace(source)
	else:
		if _rt != null or _rt_scene != null:
			_release_raytrace()
			material.set_shader_parameter("planar_texture",viewport.get_texture())
		_rt_failed = false


func _update_raytrace(source: Camera3D) -> void:
	if _rt_failed: return
	if not RayDevice.supported():
		_rt_failed = true
		rt_stats = {"supported":false,"fallback":"planar"}
		return
	if _rt_ready and _rt_live != null and _rt_topology_poll <= 0.0:
		_rt_topology_poll = 1.0
		_collect_raytrace_lights(source.global_position)
		if _rt_live.topology_changed():
			_release_raytrace()
			terrain._water_mat.set_shader_parameter("planar_texture",viewport.get_texture())
	# Recenter when travelling or changing pools. While gathering a new
	# snapshot the normal planar view remains complete and current.
	if source.global_position.distance_to(_rt_center) > 16.0 or absf(plane-_rt_plane) > 0.25:
		_release_raytrace()
		terrain._water_mat.set_shader_parameter("planar_texture",viewport.get_texture())
		_rt_center = source.global_position
		_rt_plane = plane
		_rt_scene = RayScene.new()
		_rt_scene.begin(terrain,_rt_center,plane)
	if _rt_scene != null:
		if not _rt_scene.step(): return
		rt_stats = {"supported":true,"triangles":_rt_scene.triangles,"textures":_rt_scene.images.size(),"radius":RayScene.RADIUS,"geometries":_rt_scene.geometries.size(),"instances":_rt_scene.instances.size(),"native_scene":_rt_scene._kernel != null}
		if _rt_scene.failed or _rt_scene.triangles == 0:
			_rt_failed = true
			rt_stats["fallback"] = "snapshot_budget"
			_rt_scene = null
			return
		_rt = RayDevice.new()
		_rt.prepared.connect(_raytrace_prepared)
		var geometries := []; var placements := []
		for geometry: Dictionary in _rt_scene.geometries:
			geometries.append({"offset":geometry.offset,"count":geometry.count})
		for entry: Dictionary in _rt_scene.instances:
			placements.append({"geometry":entry.geometry,"transform":entry.transform,"mask":0})
		RenderingServer.call_on_render_thread(_rt.build.bind(_rt_scene.vertices.to_byte_array(),_rt_scene.images,geometries,placements))
		_rt_live = _rt_scene
		_rt_scene = null
		_collect_raytrace_lights(source.global_position)
	if not _rt_ready: return
	var size := source.get_viewport().get_visible_rect().size
	var scale := minf(0.5,960.0/maxf(size.x,size.y))
	var target := Vector2i(maxi(2,roundi(size.x*scale)),maxi(2,roundi(size.y*scale)))
	var frame := PackedFloat32Array()
	var inverse := camera.get_camera_projection().inverse()
	var transform := Projection(camera.global_transform)
	for matrix: Projection in [inverse,transform]:
		for axis in 4:
			var v: Vector4 = matrix[axis]
			frame.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
	var sun_direction := Gfx._cloud_sun_direction
	frame.append_array(PackedFloat32Array([Gfx.ambient.r,Gfx.ambient.g,Gfx.ambient.b,0,
		Gfx.sun.r,Gfx.sun.g,Gfx.sun.b,1,sun_direction.x,sun_direction.y,sun_direction.z,plane,
		Gfx.fog_depth.x,Gfx.fog_depth.y,source.far,1.0 if source.projection == Camera3D.PROJECTION_ORTHOGONAL else 0.0,Gfx.fog_sky.r,Gfx.fog_sky.g,Gfx.fog_sky.b,
		2.0/absf(camera.get_camera_projection().y.y)/target.y,
		_rt_center.x,_rt_center.y,_rt_center.z,RayScene.RADIUS]))
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
	var changes := _rt_live.updates()
	RenderingServer.call_on_render_thread(_rt.render.bind(target,frame.to_byte_array(),changes))
	rt_stats["updated_instances"] = changes.instances.size()
	rt_stats["updated_morphs"] = changes.poses.size()
	rt_stats["lights"] = _rt_lights.size()
	terrain._water_mat.set_shader_parameter("planar_texture",_rt.output)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	rt_stats["active"] = true
	rt_stats["size"] = [target.x,target.y]


func _collect_raytrace_lights(focus: Vector3) -> void:
	var found := []
	for node in get_tree().get_nodes_in_group(Gfx.POINT_LIGHT_GROUP):
		var light := node as OmniLight3D
		if light == null or not light.is_visible_in_tree() or light.light_energy <= 0.0: continue
		var distance := maxf(light.global_position.distance_to(focus)-light.omni_range,0.0)
		if distance < RayScene.RADIUS: found.append([distance,light])
	found.sort_custom(func(a: Array,b: Array) -> bool: return a[0] < b[0])
	_rt_lights.clear()
	for i in mini(found.size(),4): _rt_lights.append(weakref(found[i][1]))


func _raytrace_prepared(ok: bool) -> void:
	_rt_ready = ok
	_rt_failed = not ok
	if not ok:
		rt_stats["fallback"] = "pipeline_failed"
		_release_raytrace()
		if is_instance_valid(terrain) and terrain._water_mat and viewport:
			terrain._water_mat.set_shader_parameter("planar_texture",viewport.get_texture())


func _release_raytrace() -> void:
	_rt_ready = false
	rt_stats["active"] = false
	_rt_scene = null
	_rt_live = null
	_rt_lights.clear()
	_rt_center = Vector3.INF
	_rt_plane = INF
	if _rt != null:
		_rt.prepared.disconnect(_raytrace_prepared)
		RenderingServer.call_on_render_thread(_rt.dispose)
		_rt = null


func _create_view() -> void:
	viewport = SubViewport.new()
	viewport.name = "WaterReflectionView"
	# SubViewports default to interpolation ON even when the main viewport
	# is OFF. This camera follows the render-frame pose; interpolating it
	# again makes the rendered bank lag behind planar_view during fast turns.
	viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.world_3d = terrain.get_world_3d()
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.positional_shadow_atlas_size = 0
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	camera = Camera3D.new()
	# The water shader already supplies sky/cloud colour. Avoid a second sky,
	# post-process stack and depth-of-field pass in this small geometry view.
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0, 0, 0, 0)
	camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	camera.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	viewport.add_child(camera)
	camera.current = true
	terrain._water_mat.set_shader_parameter("planar_texture", viewport.get_texture())


func _disable() -> void:
	rt_stats["active"] = false
	if is_instance_valid(terrain) and terrain._water_mat:
		terrain._water_mat.set_shader_parameter("planar_enabled", false)
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _exit_tree() -> void:
	_disable()
	if is_instance_valid(terrain) and terrain._water_mat:
		terrain._water_mat.set_shader_parameter("planar_texture", null)
	_release_raytrace()


func _select_plane(source: Camera3D) -> float:
	var position := source.global_position
	# Camera3D.is_position_in_frustum rebuilds all six projection planes on
	# every call. A water scan can test thousands of cells with one camera.
	var frustum := source.get_frustum()
	var width := terrain.sectors_x * EITerrain.SECTOR
	var height := terrain.sectors_y * EITerrain.SECTOR
	var groups := {}
	# Probe original liquid cells, not walkable bridge heights. Bucket nearby
	# surface levels so tiny authored river slopes share a stable plane.
	for y in range(maxi(0, int(-position.z - REACH)) & ~1, mini(height, int(-position.z + REACH)), 2):
		for x in range(maxi(0, int(position.x - REACH)) & ~1, mini(width, int(position.x + REACH)), 2):
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
			if distance > REACH * REACH: continue
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

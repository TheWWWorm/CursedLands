extends Node
## Render the shared sky once at a bounded size, then sample it along each
## water normal. No scenery, shadows, depth copy or temporal history here.
const Reflection = preload("res://src/game/fx/water_reflection.gd")
const Clouds = preload("res://src/game/fx/clouds.gd")
const MAX_SIZE := 256.0
var terrain: EITerrain
var viewport: SubViewport
var camera: Camera3D
var _scanner: Reflection
var _source: Camera3D
var _poll := 0
var _plane := -INF
var _key: Array = []

static func supported() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "forward_plus"

func _ready() -> void:
	process_priority = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scanner = Reflection.new()
	_scanner.terrain = terrain

func _process(_dt: float) -> void:
	if not is_instance_valid(terrain) or not terrain.is_visible_in_tree() or Gfx._cloud_owner != terrain.get_instance_id() or not Clouds.reflections_enabled() or Clouds.mode() < 2:
		_disable(); return
	var source := terrain.get_viewport().get_camera_3d()
	if source == null: _disable(); return
	var environment := source.environment
	if environment == null: environment = source.get_world_3d().environment
	if environment == null or environment.background_mode != Environment.BG_SKY or environment.sky == null:
		_disable(); return
	var now := Time.get_ticks_msec()
	if source != _source or now >= _poll:
		_plane = _scanner._select_plane(source)
		_source = source; _poll = now + 125
	if not is_finite(_plane) or source.global_position.y < _plane + 0.15:
		_disable(); return
	if viewport == null: _create_view()
	var size := source.get_viewport().get_visible_rect().size
	var scale := minf(0.25, MAX_SIZE / maxf(size.x,size.y))
	viewport.size = Vector2i(maxi(2,roundi(size.x*scale)),maxi(2,roundi(size.y*scale)))
	camera.environment.sky = environment.sky
	camera.keep_aspect = source.keep_aspect
	camera.fov = minf(150.0,source.fov+16.0)
	camera.near = 0.1; camera.far = 4000.0
	camera.global_transform = Reflection.reflected_transform(source.get_camera_transform(),_plane)
	var material := terrain._water_mat
	material.set_shader_parameter("cloud_reflection_projection",camera.get_camera_projection())
	material.set_shader_parameter("cloud_reflection_view",camera.global_transform.affine_inverse())
	material.set_shader_parameter("cloud_reflection_ready",true)
	var sky_material := environment.sky.sky_material as ShaderMaterial
	var key: Array = [camera.global_transform,camera.get_camera_projection(),viewport.size,environment.sky,Clouds.mode(),
		Gfx._cloud_frame,Gfx._cloud_sun_direction,Gfx._sky_flash,Gfx._border_size,Gfx._border_menu]
	if sky_material:
		for parameter: StringName in [&"ambient",&"sun_col",&"sky_col",&"light_dir",&"night",&"fancy",&"spin"]:
			key.append(sky_material.get_shader_parameter(parameter))
	if key != _key:
		_key = key.duplicate(true)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _create_view() -> void:
	viewport = SubViewport.new(); viewport.name = "CloudReflectionView"
	viewport.own_world_3d = true; viewport.gui_disable_input = true
	viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.positional_shadow_atlas_size = 0
	add_child(viewport)
	camera = Camera3D.new(); camera.cull_mask = 0
	camera.environment = Environment.new()
	Gfx.setup_original_env(camera.environment)
	camera.environment.background_mode = Environment.BG_SKY
	camera.environment.fog_enabled = false
	camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	camera.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	viewport.add_child(camera); camera.current = true
	terrain._water_mat.set_shader_parameter("cloud_reflection_texture",viewport.get_texture())

func _disable() -> void:
	if is_instance_valid(terrain) and terrain._water_mat:
		terrain._water_mat.set_shader_parameter("cloud_reflection_ready",false)
	if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_key.clear()

func _exit_tree() -> void:
	_disable()
	if is_instance_valid(terrain) and terrain._water_mat:
		terrain._water_mat.set_shader_parameter("cloud_reflection_texture",null)
	if is_instance_valid(_scanner): _scanner.free()

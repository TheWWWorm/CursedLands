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
var _plane := -INF
var _key: Array = []
var _sky_source: Sky
var _sky_material: Material
var _sky_parameters := {}

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
	_plane = _scanner.visible_plane(source)
	if not is_finite(_plane) or source.global_position.y < _plane + 0.15:
		_disable(); return
	if viewport == null: _create_view()
	var size := source.get_viewport().get_visible_rect().size
	var scale := minf(0.25, MAX_SIZE / maxf(size.x,size.y))
	viewport.size = Vector2i(maxi(2,roundi(size.x*scale)),maxi(2,roundi(size.y*scale)))
	_sync_sky(environment.sky)
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
		key.append(sky_material)
		key.append(sky_material.shader)
		for parameter: StringName in [&"tex",&"ambient",&"sun_col",&"sky_col",&"light_dir",&"night",&"fancy",&"spin"]:
			key.append(sky_material.get_shader_parameter(parameter))
	if key != _key:
		_key = key.duplicate(true)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _sync_sky(source: Sky) -> void:
	# A Sky owns its radiance history, including the last camera position.
	# Sharing it with the reflected camera invalidates the main view's history
	# twice per frame. This view needs only background colour, never radiance.
	if source != _sky_source or source.sky_material != _sky_material:
		_sky_source = source
		_sky_material = source.sky_material
		_sky_parameters.clear()
		var sky := Sky.new()
		# Godot still allocates/filters a cubemap for background-only skies.
		# Its contents are unused here; keep that bookkeeping at minimum size.
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		sky.sky_material = source.sky_material.duplicate() if source.sky_material else null
		camera.environment.sky = sky
	var original := source.sky_material as ShaderMaterial
	var material := camera.environment.sky.sky_material as ShaderMaterial
	if original and material:
		if material.shader != original.shader:
			material.shader = original.shader
			_sky_parameters.clear()
		for parameter: StringName in [&"tex",&"ambient",&"sun_col",&"sky_col",&"light_dir",&"night",&"fancy",&"spin"]:
			var value: Variant = original.get_shader_parameter(parameter)
			if not _sky_parameters.has(parameter) or _sky_parameters[parameter] != value:
				material.set_shader_parameter(parameter,value)
				_sky_parameters[parameter] = value
		if not _sky_parameters.has(&"sky_radiance"):
			material.set_shader_parameter(&"sky_radiance", false)
			material.set_shader_parameter(&"cloud_radiance", false)
			_sky_parameters[&"sky_radiance"] = false

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

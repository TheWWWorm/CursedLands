class_name ArenaPveField
extends ArenaField

var show_markers := true
var _old_ambient := Color.WHITE
var _old_sun := Color.WHITE
var _old_direction := Vector3.ZERO
var _old_fog := []
var _shadow_poll := 0.0


func _build_stage() -> void:
	_old_ambient = Gfx.ambient
	_old_sun = Gfx.sun
	_old_direction = Gfx._cloud_sun_direction
	_old_fog = [Gfx.fog_sky, Gfx.fog_color, Gfx.fog_depth]
	select_occupied = true
	show_team_rings = false
	resized.connect(_update_camera)
	zoom = 14.5
	yaw = -PI / 2
	_update_camera()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment.ssao_enabled = Gfx.on("gfx_ssao")
	environment.environment.ssao_radius = 1.1
	environment.environment.ssao_intensity = 0.8
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -35, 0)
	sun.light_angular_distance = 1.5
	sun.directional_shadow_max_distance = 85.0
	sun.shadow_enabled = true
	stage.add_child(sun)
	# Original figure/terrain materials use native light uniforms, not just
	# Godot's environment. A fixed afternoon keeps every run equally readable.
	Gfx.update_original(environment.environment, sun, EILights.load_for("Gipat", false), 14.0, false)
	# A warm clearing against cool shade. Apply the same palette to native
	# figures and the Godot paving, after the original-light defaults above.
	var shade := Color(0.46, 0.49, 0.48)
	var daylight := Color(1.0, 0.94, 0.84)
	Gfx.set_light(shade, daylight)
	environment.environment.ambient_light_color = shade
	sun.light_color = daylight
	# The overhead spectator camera has no visible sky. A black, softly
	# feathered perimeter also hides the physical map edge at maximum zoom.
	Gfx.set_fog_palette(Color.BLACK, Color.BLACK, Gfx.fog_depth)
	environment.environment.fog_light_color = Color.BLACK


func reset_camera() -> void:
	yaw = -PI / 2
	zoom = 14.5
	_update_camera()


func _process(delta: float) -> void:
	super._process(delta)
	_shadow_poll -= delta
	if _shadow_poll > 0 or match_state == null or not is_instance_valid(match_state.world): return
	_shadow_poll = ContactShadows.SCAN
	var enabled := Gfx.on("gfx_contact_shadows") and not Portability.compatibility()
	for unit: GameUnit in match_state.world.unit_rows():
		var shadow := unit.get_meta("contact_shadow") as Decal if unit.has_meta("contact_shadow") else null
		if not is_instance_valid(shadow) and enabled:
			shadow = Decal.new()
			shadow.name = "ContactShadow"
			var diameter := maxf(ContactShadows.MIN_SIZE, unit.figure_radius * ContactShadows.SIZE_K)
			shadow.size = Vector3(diameter, 2.0, diameter)
			shadow.texture_albedo = ContactShadows._texture()
			shadow.modulate = Color(0, 0, 0, ContactShadows.ALPHA)
			shadow.albedo_mix = 1.0
			shadow.upper_fade = 0.35
			shadow.lower_fade = 0.35
			shadow.cull_mask = EITerrain.DECAL_LAYER
			unit.add_child(shadow)
			shadow.position.y = 0.2
			unit.set_meta("contact_shadow", shadow)
		if is_instance_valid(shadow): shadow.visible = enabled


func _draw_overlay() -> void:
	if not show_markers: return
	if not ghost_id.is_empty() and match_state and is_instance_valid(match_state.world) and match_state.phase == ArenaMatch.Phase.DEPLOY:
		var rect := ArenaRun.DEPLOY
		var corners := PackedVector2Array([screen_point(rect.position), screen_point(rect.position + Vector2(rect.size.x, 0)),
			screen_point(rect.end), screen_point(rect.position + Vector2(0, rect.size.y))])
		overlay.draw_colored_polygon(corners, Color(BLUE, 0.025))
		corners.append(corners[0])
		overlay.draw_polyline(corners, Color(BLUE, 0.32), 1, true)
	super._draw_overlay()


func _update_camera() -> void:
	super._update_camera()
	if camera and size.x > 0 and size.y > 0:
		var point := match_state.bounds().get_center() if match_state else Vector2(32, 32)
		var center := Vector3(point.x - 1.75, 0, -point.y)
		var fitted_size := maxf(14.5, 29.0 * size.y / size.x)
		# Keep both starting rows, including their health bars, between the
		# recruitment shelf and reserves at 16:9 and 4:3 desktop sizes.
		var pixels_per_meter := size.y / fitted_size
		var depth_sine := clampf((size.y - 360.0) / (21.0 * pixels_per_meter), 0.25, 0.55)
		var height := 36.0 * depth_sine / sqrt(1.0 - depth_sine * depth_sine)
		camera.position = center + Vector3(sin(yaw) * 36, height, cos(yaw) * 36)
		camera.look_at(center)
		camera.size = fitted_size * zoom / 14.5
		camera.position += camera.basis.y * camera.size * 70.0 / size.y


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 8, 35)
		_update_camera()
		accept_event()
		return
	super._gui_input(event)


func _exit_tree() -> void:
	Gfx.set_light(_old_ambient, _old_sun)
	Gfx.set_sun_direction(_old_direction)
	if _old_fog.size() == 3: Gfx.set_fog_palette(_old_fog[0], _old_fog[1], _old_fog[2])

class_name ArenaPveField
extends ArenaField

var show_markers := true
var _old_ambient := Color.WHITE
var _old_sun := Color.WHITE
var _old_direction := Vector3.ZERO


func _build_stage() -> void:
	_old_ambient = Gfx.ambient
	_old_sun = Gfx.sun
	_old_direction = Gfx._cloud_sun_direction
	select_occupied = true
	show_team_rings = false
	resized.connect(_update_camera)
	zoom = 14.5
	yaw = -PI / 2
	_update_camera()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("252e29")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c6d1c4")
	environment.environment.ambient_light_energy = 0.7
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-57, -32, 0)
	sun.light_color = Color("ffe2af")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	stage.add_child(sun)
	# Original figure/terrain materials use native light uniforms, not just
	# Godot's environment. A fixed afternoon keeps every run equally readable.
	Gfx.update_original(environment.environment, sun, EILights.load_for("Gipat", false), 14.0, false)


func reset_camera() -> void:
	yaw = -PI / 2
	zoom = 14.5
	_update_camera()


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

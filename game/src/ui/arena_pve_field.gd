class_name ArenaPveField
extends ArenaField
signal board_chosen(player: int)
var evolution_pulses := {}
var tournament: ArenaTournamentBattles
var _arena_fog := Vector2(90, 100)


func showing_boards() -> bool:
	return is_instance_valid(tournament) and tournament.overview

var show_markers := true
var _old_ambient := Color.WHITE
var _old_sun := Color.WHITE
var _old_direction := Vector3.ZERO
var _old_fog := []
var _shadow_poll := 0.0
var _environment: Environment
var _sun_light: DirectionalLight3D


func _build_stage() -> void:
	_old_ambient = Gfx.ambient
	_old_sun = Gfx.sun
	_old_direction = Gfx._cloud_sun_direction
	_old_fog = [Gfx.fog_sky, Gfx.fog_color, Gfx.fog_depth]
	select_occupied = true
	show_team_rings = false
	numeric_health = true
	resized.connect(_update_camera)
	zoom = 14.5
	yaw = -PI / 2
	# Orthographic shadows use the camera's full depth, ignoring the light's
	# max distance. The inherited 180 m range wasted most of the shadow map
	# and put the opposing rows in different cascades. The whole 64 m island
	# fits this range, including the rotating and widest spectator views.
	camera.near = 0.5
	camera.far = 90.0
	_update_camera()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment = environment.environment
	environment.environment.ssao_radius = 1.1
	environment.environment.ssao_intensity = 0.8
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	_sun_light = sun
	sun.rotation_degrees = Vector3(-52, -35, 0)
	# One map gives this orthographic board a consistent texel scale. A
	# filtered silhouette keeps feet anchored without PCSS cascade changes.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_fade_start = 1.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.6
	sun.shadow_opacity = 0.85
	sun.shadow_enabled = true
	stage.add_child(sun)
	# Original figure/terrain materials use native light uniforms, not just
	# Godot's environment. A fixed afternoon keeps every run equally readable.
	Gfx.update_original(environment.environment, sun, EILights.load_for("Ingos", false), 14.0, false)
	# Cold daylight over the snowy courtyard. Apply the same palette to native
	# figures and the Godot paving, after the original-light defaults above.
	var shade := Color(0.45, 0.50, 0.59)
	var daylight := Color(0.88, 0.94, 1.0)
	Gfx.set_light(shade, daylight)
	environment.environment.ambient_light_color = shade
	sun.light_color = daylight
	# The overhead spectator camera has no visible sky. A black, softly
	# feathered perimeter also hides the physical map edge at maximum zoom.
	Gfx.set_fog_palette(Color.BLACK, Color.BLACK, Gfx.fog_depth)
	_arena_fog = Gfx.fog_depth
	environment.environment.fog_light_color = Color.BLACK
	GameData.options_changed.connect(_apply_presentation)
	_apply_presentation()


func _apply_presentation() -> void:
	# SubViewports do not inherit the root's AA / filtering settings.
	Gfx.apply_quality(view)
	_environment.ssao_enabled = Gfx.on("gfx_ssao")
	# A wider PCF footprint is clean at High/Ultra; keep the sparse Low and
	# Medium filters tighter instead of spreading their samples into grain.
	_sun_light.shadow_blur = 1.8 if GameData.option("q_shadows") >= 2 else 1.0


func reset_camera() -> void:
	yaw = -PI / 2
	zoom = 14.5
	_update_camera()


func _process(delta: float) -> void:
	if showing_boards():
		hovered = null
		if ghost: ghost.hide()
		overlay.queue_redraw()
		return
	super._process(delta)
	for uid in evolution_pulses.keys():
		evolution_pulses[uid] -= delta
		if evolution_pulses[uid] <= 0: evolution_pulses.erase(uid)
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
			shadow.modulate = Color(0, 0, 0, 0.38)
			shadow.albedo_mix = 1.0
			shadow.upper_fade = 0.35
			shadow.lower_fade = 0.35
			shadow.cull_mask = EITerrain.DECAL_LAYER
			unit.add_child(shadow)
			shadow.position.y = 0.2
			unit.set_meta("contact_shadow", shadow)
		if is_instance_valid(shadow): shadow.visible = enabled


func _draw_overlay() -> void:
	if showing_boards():
		_draw_boards()
		return
	if not show_markers: return
	if not ghost_id.is_empty() and match_state and is_instance_valid(match_state.world) and match_state.phase == ArenaMatch.Phase.DEPLOY:
		var rect := ArenaRun.DEPLOY
		var corners := PackedVector2Array([screen_point(rect.position), screen_point(rect.position + Vector2(rect.size.x, 0)),
			screen_point(rect.end), screen_point(rect.position + Vector2(0, rect.size.y))])
		overlay.draw_colored_polygon(corners, Color(BLUE, 0.025))
		corners.append(corners[0])
		overlay.draw_polyline(corners, Color(BLUE, 0.32), 1, true)
	super._draw_overlay()
	if match_state == null or not is_instance_valid(match_state.world): return
	for unit: GameUnit in match_state.world.unit_rows():
		var placement: Dictionary = unit.get_meta("arena_placement", {})
		var uid := int(placement.get("run_uid", 0))
		if uid == 0: continue
		if not evolution_pulses.has(uid): continue
		var remaining: float = evolution_pulses[uid]
		var color := Color(ArenaCreatureCard.GOLD, minf(1, remaining))
		var rects := unit_rects(unit)
		if not rects.is_empty(): _selection_corners(Rect2(rects[0]).grow((6 + (1.6 - remaining) * 4) * ui_scale), color)
		var center := health_anchor(unit) - Vector2(0, 32) * ui_scale
		var radius := (13 + (1.6 - remaining) * 10) * ui_scale
		for i in 8:
			var direction := Vector2.from_angle(TAU * i / 8)
			overlay.draw_line(center + direction * radius, center + direction * (radius + 5 * ui_scale), color, ui_scale, true)


func _update_camera() -> void:
	if camera and showing_boards():
		camera.far = 300
		camera.position = Vector3(96, 160, -96)
		camera.look_at(Vector3(96, 0, -96), Vector3(0, 0, -1))
		camera.size = maxf(208.0, 192.0 * size.y / maxf(100, minf(size.x - 48 * ui_scale, size.y - 128 * ui_scale)))
		Gfx.set_fog_palette(Color.BLACK, Color.BLACK, Vector2(250, 300))
		return
	super._update_camera()
	if camera and size.x > 0 and size.y > 0:
		camera.far = 90
		Gfx.set_fog_palette(Color.BLACK, Color.BLACK, _arena_fog)
		var point := match_state.bounds().get_center() if match_state else Vector2(32, 32)
		var center := Vector3(point.x - 1.75, 0, -point.y)
		var fitted_size := maxf(14.5, 29.0 * size.y / size.x)
		# Keep both starting rows, including their health bars, between the
		# recruitment shelf and reserves at 16:9 and 4:3 desktop sizes.
		var pixels_per_meter := size.y / fitted_size
		var depth_sine := clampf((size.y - 430.0 * ui_scale) / (21.0 * pixels_per_meter), 0.25, 0.55)
		var height := 36.0 * depth_sine / sqrt(1.0 - depth_sine * depth_sine)
		camera.position = center + Vector3(sin(yaw) * 36, height, cos(yaw) * 36)
		camera.look_at(center)
		camera.size = fitted_size * zoom / 14.5


func _gui_input(event: InputEvent) -> void:
	if showing_boards():
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var player := _map_player(event.position)
			if player >= 0: board_chosen.emit(player)
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 8, 35)
		_update_camera()
		accept_event()
		return
	super._gui_input(event)


func _map_player(at: Vector2) -> int:
	var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(at), camera.project_ray_normal(at))
	if point == null or point.x < 0 or point.x >= 192 or -point.z < 0 or -point.z >= 192: return -1
	return ArenaTournamentBattles.MAP_SEATS[int(-point.z / 64) * 3 + int(point.x / 64)]


func _draw_boards() -> void:
	var font := ThemeDB.fallback_font
	var pixels := roundi(14 * ui_scale)
	var hovered_player := _map_player(get_local_mouse_position())
	for player in ArenaTournamentBattles.MAP_SEATS:
		var origin := ArenaTournamentBattles.board_offset(player)
		var start := camera.unproject_position(origin)
		var end := camera.unproject_position(origin + Vector3(64, 0, -64))
		var rect := Rect2(start, end - start).abs().grow(-4 * ui_scale)
		var alive := tournament.run.health(player) > 0
		var board: ArenaPveMatch = tournament.home if player == 0 else tournament.boards.get(player)
		if board and is_instance_valid(board.world):
			for unit: GameUnit in board.world.unit_rows():
				if unit.dead or unit.hidden: continue
				var at := camera.unproject_position(unit.global_position)
				overlay.draw_circle(at, 3.4 * ui_scale, Color("17262d"), true, -1, true)
				overlay.draw_circle(at, 2.2 * ui_scale, BLUE if unit.faction == 1 else RED, true, -1, true)
		var colour := BLUE if player == hovered_player and alive else Color(0.8, 0.87, 0.91, 0.35)
		overlay.draw_rect(rect, colour, false, ui_scale, true)
		var text_colour := ArenaCreatureCard.SNOW_INK if alive else Color("454545")
		var title := tournament.run.player_title(player)
		var hp := str(tournament.run.health(player)) if alive else RemakeText.t("Eliminated")
		for line in 2:
			var text := title if line == 0 else hp
			var at := Vector2(rect.position.x, rect.end.y - (24 if line == 0 else 7) * ui_scale)
			overlay.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, pixels, 1, Color("eeeeee"))
			overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, pixels, text_colour)


func _exit_tree() -> void:
	Gfx.set_light(_old_ambient, _old_sun)
	Gfx.set_sun_direction(_old_direction)
	if _old_fog.size() == 3: Gfx.set_fog_palette(_old_fog[0], _old_fog[1], _old_fog[2])

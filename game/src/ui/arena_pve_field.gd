class_name ArenaPveField
extends ArenaField
signal board_chosen(player: int)
const OVERVIEW_FRIEND := preload("res://assets/arena/overview_friend.svg")
const OVERVIEW_ENEMY := preload("res://assets/arena/overview_enemy.svg")
const DEFAULT_YAW := -PI / 6
var evolution_pulses := {}
var tournament: ArenaTournamentBattles
var _board_headers := {}


class BoardHeader extends Control:
	var state: Array = []
	func update_header(at: Vector2, values: Array) -> void:
		position = at
		if values == state: return
		state = values; queue_redraw()
	func _draw() -> void:
		if state.is_empty(): return
		var extent: Vector2 = state[0]
		var k: float = state[5]
		var font: Font = state[6]
		var pixels := roundi(14 * k)
		draw_rect(Rect2(Vector2.ZERO,extent),state[3],false,k,true)
		for line in 2:
			var text: String = state[1+line]
			var at := Vector2(0,extent.y-(24 if line == 0 else 7)*k)
			draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_CENTER,extent.x,pixels,1,Color("eeeeee"))
			draw_string(font,at,text,HORIZONTAL_ALIGNMENT_CENTER,extent.x,pixels,state[4])


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
var pitch_offset := 0.0
var pan_offset := Vector2.ZERO
var _yaw_velocity := 0.0
var _pan_velocity := Vector2.ZERO
var _right_orbit := false
var _right_dragged := false
var _right_distance := Vector2.ZERO
var _guide_ground: ArenaWinterTerrain
var _snow_surround: ArenaSnowSurround


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
	yaw = DEFAULT_YAW
	# Keep the board inside the depth range even at the highest orbit tilt.
	camera.near = 0.5
	camera.far = 90.0
	_update_camera()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("aebcc9")
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
	sun.shadow_opacity = 0.85
	sun.shadow_enabled = true
	stage.add_child(sun)
	# Original figure/terrain materials use native light uniforms, not just
	# Godot's environment. A fixed afternoon keeps every run equally readable.
	Gfx.update_original(environment.environment, sun, EILights.load_for("Ingos", false), 14.0, false)
	# Cold daylight over the snowy courtyard. Apply the same palette to native
	# figures and the Godot paving, after the original-light defaults above.
	var shade := Color(0.60, 0.64, 0.70)
	var daylight := Color(0.88, 0.94, 1.0)
	Gfx.set_light(shade, daylight)
	environment.environment.ambient_light_color = shade
	sun.light_color = daylight
	# Snow-colored fog hides the map edge without a black frame around play.
	Gfx.set_fog_palette(Color("aebcc9"), Color("aebcc9"), Gfx.fog_depth)
	environment.environment.fog_light_color = Color("aebcc9")
	GameData.options_changed.connect(_apply_presentation)
	_apply_presentation()
	_snow_surround = ArenaSnowSurround.new()
	_snow_surround.name = "SnowSurround"
	_snow_surround.hide()
	stage.add_child(_snow_surround)
	_snow_surround.set_overview(false)


func _apply_presentation() -> void:
	# SubViewports do not inherit the root's AA / filtering settings.
	Gfx.apply_quality(view)
	_environment.ssao_enabled = Gfx.on("gfx_ssao")
	# A wider PCF footprint is clean at High/Ultra; keep the sparse Low and
	# Medium filters tighter instead of spreading their samples into grain.
	_sun_light.shadow_blur = 1.8 if GameData.option("q_shadows") >= 2 else 1.0
	# GLES3 and the sparse Low-quality RD filter need a larger texel offset
	# to keep flat snow out of its own shadow. Reapply when quality changes.
	_sun_light.shadow_normal_bias = 2.0 if Portability.compatibility() or GameData.option("q_shadows") == 0 else 0.6


func reset_camera() -> void:
	stop_camera_motion()
	yaw = DEFAULT_YAW
	pitch_offset = 0.0
	pan_offset = Vector2.ZERO
	zoom = 14.5
	_update_camera()


func stop_camera_motion() -> void:
	_yaw_velocity = 0.0
	_pan_velocity = Vector2.ZERO
	_orbit = false
	_right_orbit = false
	_right_dragged = false
	_right_distance = Vector2.ZERO


## Match the main game's continuous turn acceleration and short release tail.
## The camera uses wall time, so 2x combat does not double the turn speed.
func advance_camera(dt: float, turn: float, movement := Vector2.ZERO) -> void:
	var direction := -1.0 if GameData.option("camera_reverse_x") else 1.0
	var target := -turn * 2.0 * CameraRig.speed_factor("cam_rotate_speed") * direction
	_yaw_velocity = lerpf(_yaw_velocity, target, 1.0 - exp(-(18.0 if turn else 32.0) * dt))
	if absf(_yaw_velocity) < 0.001:
		_yaw_velocity = 0.0
	yaw += _yaw_velocity * dt
	var right := Vector2(camera.basis.x.x,-camera.basis.x.z).normalized()
	var back := Vector2(camera.basis.z.x,-camera.basis.z.z).normalized()
	var pan_target := (right*movement.x+back*movement.y).limit_length() * 14.0 * zoom/14.5 * CameraRig.speed_factor("cam_pan_speed")
	_pan_velocity = _pan_velocity.lerp(pan_target,1.0-exp(-(18.0 if movement else 32.0)*dt))
	if _pan_velocity.length_squared()<0.000001: _pan_velocity=Vector2.ZERO
	if _yaw_velocity==0.0 and _pan_velocity==Vector2.ZERO: return
	pan_offset=(pan_offset+_pan_velocity*dt).clamp(Vector2(-16,-16),Vector2(16,16))
	_update_camera()


func _drag_camera(delta: Vector2, tilt := false) -> void:
	var direction := -1.0 if GameData.option("camera_reverse_x") else 1.0
	_yaw_velocity = 0.0
	yaw -= delta.x * 0.006 * CameraRig.speed_factor("cam_rotate_speed") * direction
	if tilt:
		var vertical := -1.0 if GameData.option("camera_reverse_y") else 1.0
		pitch_offset = clampf(pitch_offset + delta.y * 0.004 * vertical * CameraRig.speed_factor("cam_rotate_speed"), deg_to_rad(-35.0), deg_to_rad(35.0))
	_update_camera()


func _process(delta: float) -> void:
	_update_deployment_guide()
	if showing_boards():
		_update_board_headers()
		_clear_unit_markers()
		hovered = null
		if ghost: ghost.hide()
		overlay.queue_redraw()
		return
	for header: BoardHeader in _board_headers.values():
		if header.visible: header.hide()
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


func _unit_markers_visible() -> bool:
	return show_markers and not showing_boards()


func _update_deployment_guide() -> void:
	var ground: ArenaWinterTerrain
	if match_state and is_instance_valid(match_state.world):
		ground = match_state.world.terrain as ArenaWinterTerrain
	if ground != _guide_ground:
		if is_instance_valid(_guide_ground): _guide_ground.set_deployment_guide(0.0)
		_guide_ground = ground
		if is_instance_valid(ground): _snow_surround.bind(ground)
	if not is_instance_valid(_guide_ground): return
	var preparing := show_markers and not showing_boards() and match_state.phase == ArenaMatch.Phase.DEPLOY
	_guide_ground.set_deployment_guide((0.8 if ghost_id.is_empty() else 1.0) if preparing else 0.0)


func _draw_overlay() -> void:
	if showing_boards():
		_draw_boards()
		return
	if not show_markers: return
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
	if is_instance_valid(_snow_surround): _snow_surround.set_overview(showing_boards())
	if camera and showing_boards():
		camera.far = 300
		camera.position = Vector3(96, 160, -96)
		camera.look_at(Vector3(96, 0, -96), Vector3(0, 0, -1))
		camera.size = maxf(208.0, 192.0 * size.y / maxf(100, minf(size.x - 48 * ui_scale, size.y - 128 * ui_scale)))
		Gfx.set_fog_palette(Color("aebcc9"), Color("aebcc9"), Vector2(250, 300))
		return
	if not camera or size.x <= 0 or size.y <= 0: return
	var board := match_state.bounds() if match_state else ArenaTerrain.PLAY_AREA
	var point := board.get_center()
	var center := Vector3(point.x + pan_offset.x, 0, -point.y - pan_offset.y)
	# Look diagonally across the approach so front and rear ranks separate.
	# The starting tilt and height are retained; only the horizontal orbit changes.
	var angle := clampf(deg_to_rad(34.0) + pitch_offset, deg_to_rad(18.0), deg_to_rad(75.0))
	var direction := Vector3(sin(yaw) * cos(angle), sin(angle), cos(yaw) * cos(angle))
	var distance := 72.0 * maxf(1.0, zoom / 14.5)
	camera.position = center + direction * distance
	camera.look_at(center)
	# Fit the complete playable board and tall figures into the space between
	# shelf, reserves and side panels. The frame is stable as units move; zoom,
	# pan and orbit remain player-controlled and survive every round.
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for x: float in [board.position.x, board.end.x]:
		for y: float in [board.position.y, board.end.y]:
			for height: float in [0.0, 4.5]:
				var delta := Vector3(x-point.x, height, point.y-y)
				var projected := Vector2(camera.basis.x.dot(delta), -camera.basis.y.dot(delta))
				low = low.min(projected); high = high.max(projected)
	var safe := battle_screen_rect()
	var span := high - low
	var fitted := maxf(span.x * size.y / safe.size.x, span.y * size.y / safe.size.y)
	camera.size = fitted * zoom / 14.5
	var pixel_scale := size.y / camera.size
	var shift := (size * 0.5 - safe.get_center()) / pixel_scale + (low + high) * 0.5
	camera.position += camera.basis.x * shift.x - camera.basis.y * shift.y
	# HUD centering used to alter height when yaw changed the fitted width.
	# Slide along the orthographic view ray to retain the old starting height
	# exactly, without moving the board in the image or changing its zoom.
	var reference_span := Vector2(board.size.y, board.size.x * sin(angle) + 4.5 * cos(angle))
	var reference_size := maxf(reference_span.x * size.y / safe.size.x, reference_span.y * size.y / safe.size.y) * zoom / 14.5
	var reference_shift := (size.y * 0.5 - safe.get_center().y) * reference_size / size.y - 2.25 * cos(angle)
	var height := distance * sin(angle) - cos(angle) * reference_shift
	camera.position += direction * ((height - camera.position.y) / direction.y)
	camera.far = maxf(150.0, distance + camera.size / tan(angle) + 32.0)
	Gfx.set_fog_palette(Color("aebcc9"), Color("aebcc9"), Vector2(300, 420))


func battle_screen_rect() -> Rect2:
	var left := minf(252.0 * ui_scale, size.x * 0.22)
	var right := minf(188.0 * ui_scale, size.x * 0.17)
	# The shop closes for combat; reserve portraits occupy the bottom edge.
	# Use the intervening height rather than framing excess empty ground.
	var top := minf(80.0 * ui_scale, size.y * 0.22)
	var bottom := minf(58.0 * ui_scale, size.y * 0.12)
	return Rect2(left, top, maxf(100, size.x-left-right), maxf(100, size.y-top-bottom))


func _gui_input(event: InputEvent) -> void:
	if showing_boards():
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var player := _map_player(event.position)
			if player >= 0: board_chosen.emit(player)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_right_orbit = true
			_right_dragged = false
			_right_distance = Vector2.ZERO
			_yaw_velocity = 0.0
			grab_focus()
		else:
			# A stationary right click retains preparation's cancel action.
			if _right_orbit and not _right_dragged: cancel_requested.emit()
			_right_orbit = false
			_right_dragged = false
		accept_event()
		return
	if event is InputEventMouseMotion:
		if _right_orbit and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_right_distance += event.relative
			if _right_dragged: _drag_camera(event.relative, true)
			elif _right_distance.length() >= 3.0:
				_right_dragged = true
				_drag_camera(_right_distance, true)
			accept_event()
			return
		if _orbit and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			if event.shift_pressed:
				var plane := Plane(Vector3.UP, 0)
				var before = plane.intersects_ray(camera.project_ray_origin(event.position-event.relative),camera.project_ray_normal(event.position-event.relative))
				var after = plane.intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
				if before is Vector3 and after is Vector3:
					pan_offset += Vector2(before.x-after.x,after.z-before.z)
					pan_offset = pan_offset.clamp(Vector2(-16,-16),Vector2(16,16))
					_update_camera()
			else: _drag_camera(event.relative, event.alt_pressed)
			accept_event()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom = clampf(zoom * pow(0.85 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/0.85, CameraRig.speed_factor("cam_zoom_speed") * (event.factor if event.factor>0.0 else 1.0)), 8, 35)
		_update_camera()
		accept_event()
		return
	super._gui_input(event)


func _map_player(at: Vector2) -> int:
	var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(at), camera.project_ray_normal(at))
	if point == null or point.x < 0 or point.x >= 192 or -point.z < 0 or -point.z >= 192: return -1
	return ArenaTournamentBattles.MAP_SEATS[int(-point.z / 64) * 3 + int(point.x / 64)]


func _update_board_headers() -> void:
	var hovered_player := _map_player(pointer_position())
	for player in ArenaTournamentBattles.MAP_SEATS:
		var origin := ArenaTournamentBattles.board_offset(player)
		var start := camera.unproject_position(origin)
		var end := camera.unproject_position(origin + Vector3(64, 0, -64))
		var rect := Rect2(start, end - start).abs().grow(-4 * ui_scale)
		var alive := tournament.run.health(player) > 0
		var header: BoardHeader = _board_headers.get(player)
		if header == null:
			header = BoardHeader.new(); header.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.add_child(header); _board_headers[player] = header
		header.show()
		var colour := BLUE if player == hovered_player and alive else Color(0.8, 0.87, 0.91, 0.35)
		var text_colour := ArenaCreatureCard.SNOW_INK if alive else Color("454545")
		header.update_header(rect.position,[rect.size,tournament.run.player_title(player),
			str(tournament.run.health(player)) if alive else RemakeText.t("Eliminated"),
			colour,text_colour,ui_scale,ThemeDB.fallback_font])


func _draw_boards() -> void:
	# Only moving unit dots need new canvas commands every frame. Names,
	# health totals and board borders retain their commands until changed.
	for player in ArenaTournamentBattles.MAP_SEATS:
		var board: ArenaPveMatch = tournament.home if player == 0 else tournament.boards.get(player)
		if board and is_instance_valid(board.world):
			for unit: GameUnit in board.world.unit_rows():
				if unit.dead or unit.hidden: continue
				var at := camera.unproject_position(unit.global_position)
				# The same two circles in one cached quad. Retessellating 252
				# antialiased circles each frame costs several milliseconds.
				var marker := OVERVIEW_FRIEND if unit.faction == 1 else OVERVIEW_ENEMY
				overlay.draw_texture_rect(marker, Rect2(at-Vector2.ONE*4.0*ui_scale,Vector2.ONE*8.0*ui_scale),false)


func _exit_tree() -> void:
	if is_instance_valid(_guide_ground): _guide_ground.set_deployment_guide(0.0)
	Gfx.set_light(_old_ambient, _old_sun)
	Gfx.set_sun_direction(_old_direction)
	if _old_fog.size() == 3: Gfx.set_fog_palette(_old_fog[0], _old_fog[1], _old_fog[2])


var _warm_round := ""
var _warming := false
func prepare_battle_presentation() -> bool:
	var key := str([(match_state as ArenaPveMatch).run.run_seed,(match_state as ArenaPveMatch).run.wave,GameData.options])
	if _warm_round != key:
		if _warming: return false
		_warm_round=key;_warming=true;_warm_battle.call_deferred()
	return not _warming and ArenaAnimationWarmup.picking_ready()

func _warm_battle() -> void:
	await ShaderWarmup.arena(self)
	_warming=false

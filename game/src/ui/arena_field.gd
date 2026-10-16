class_name ArenaField
extends Control
## A contained 3D spectator view. Pointer coordinates stay local to the field,
## so clicking the roster can never also deploy a creature underneath it.

signal ground_clicked(point: Vector2)
signal creature_clicked(unit: GameUnit)
signal cancel_requested

const BLUE := Color("69c9ed")
const RED := Color("f18d7e")
var match_state: ArenaMatch
var view: SubViewport
var stage: Node3D
var camera: Camera3D
var overlay: Control
var ghost: EIUnitModel
var ghost_id := ""
var team := 0
var erase := false
var hover_point := Vector2.INF
var hovered: GameUnit
var yaw := 0.0
var zoom := 30.0
var _orbit := false
var _ground_material: ShaderMaterial
var select_occupied := false
var show_team_rings := true
var highlighted_run_uid := 0
var ui_scale := 1.0
var numeric_health := false
var _bounds_frame := -1
var _screen_bounds := {}


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	view = SubViewport.new()
	view.own_world_3d = true
	view.handle_input_locally = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_2X
	container.add_child(view)
	stage = Node3D.new()
	view.add_child(stage)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 180
	stage.add_child(camera)
	camera.current = true
	_update_camera()
	_build_stage()
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	mouse_exited.connect(func():
		hover_point = Vector2.INF
		hovered = null
		if ghost: ghost.hide())


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("10191f")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b5c6d2")
	env.environment.ambient_light_energy = 0.65
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54, -28, 0)
	sun.light_color = Color("ffe4be")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 145, 0)
	fill.light_color = Color("83c4e0")
	fill.light_energy = 0.45
	stage.add_child(fill)
	_box(Vector3(16, -0.8, -16), Vector3(34, 1.5, 34), Color("202c32"))
	_box(Vector3(16, -0.25, -16), Vector3(32.8, 0.45, 32.8), Color("55564f"))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(32, 32)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(16, 0.005, -16)
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = preload("res://src/ui/arena_floor.gdshader")
	floor_mesh.material_override = _ground_material
	stage.add_child(floor_mesh)
	for x in [0.5, 31.5]:
		for z in [0.5, 8.0, 16.0, 24.0, 31.5]:
			_box(Vector3(x, 0.2, -z), Vector3(1, 0.4, 1.4), Color("66665d"))
	for z in [0.5, 31.5]:
		for x in [8.0, 16.0, 24.0]:
			_box(Vector3(x, 0.2, -z), Vector3(1.4, 0.4, 1), Color("66665d"))
	for x in [5.0, 27.0]:
		_box(Vector3(x, 2.1, -32), Vector3(0.18, 4.2, 0.18), Color("a3997f"))
		_box(Vector3(x + 0.8, 3.2, -32), Vector3(1.5, 1.8, 0.08), BLUE.darkened(0.35) if x < 16 else RED.darkened(0.35))
		_box(Vector3(x, 0.2, -32), Vector3(1, 0.4, 1), Color("737269"))


func _box(at: Vector3, dimensions: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material = material
	node.mesh = mesh
	node.position = at
	stage.add_child(node)


func select_creature(id: String) -> void:
	ghost_id = id
	if is_instance_valid(ghost):
		stage.remove_child(ghost)
		ghost.queue_free()
	ghost = null
	if id.is_empty(): return
	ghost = EIUnitModel.create({"prototype": id}, true)
	if ghost:
		stage.add_child(ghost)
		for mesh: MeshInstance3D in ghost.find_children("*", "MeshInstance3D", true, false):
			mesh.transparency = 0.55
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.hide()


func reset_camera() -> void:
	yaw = 0.0
	zoom = 30.0
	_update_camera()


func _update_camera() -> void:
	if camera == null: return
	var point := match_state.bounds().get_center() if match_state else Vector2(16, 16)
	var center := Vector3(point.x, 0, -point.y)
	camera.position = center + Vector3(sin(yaw) * 30, 29, cos(yaw) * 30)
	camera.size = zoom
	camera.look_at(center)


func ground_point(at: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(at)
	var direction := camera.project_ray_normal(at)
	var p: Variant = Plane(Vector3.UP, 0).intersects_ray(origin, direction)
	if p != null and match_state and is_instance_valid(match_state.world):
		for i in 5:
			var height := match_state.world.terrain.height_at(p.x, -p.z)
			p = Plane(Vector3.UP, height).intersects_ray(origin, direction)
			if p == null: break
	return Vector2(p.x, -p.z) if p != null else Vector2.INF


func screen_point(point: Vector2) -> Vector2:
	var height := match_state.world.terrain.height_at(point.x, point.y) if match_state and is_instance_valid(match_state.world) else 0.0
	return camera.unproject_position(Vector3(point.x, height + 0.04, -point.y))


func unit_rects(unit: GameUnit) -> Array:
	var frame := Engine.get_process_frames()
	if frame != _bounds_frame:
		_bounds_frame = frame
		_screen_bounds.clear()
	var key := unit.get_instance_id()
	if not _screen_bounds.has(key): _screen_bounds[key] = unit.screen_rects(camera)
	return _screen_bounds[key]


func _pick(at: Vector2) -> GameUnit:
	if match_state == null or not is_instance_valid(match_state.world): return null
	var exact: Array = []
	var nearby: Array = []
	var headers: Array = []
	var to_view := camera.global_transform.affine_inverse()
	for unit: GameUnit in match_state.world.unit_rows():
		if unit.dead or unit.hidden or not unit.visible or camera.is_position_behind(unit.global_position): continue
		if numeric_health:
			var head := health_anchor(unit)
			if Rect2(head - Vector2(29, 40) * ui_scale, Vector2(58, 44) * ui_scale).has_point(at):
				headers.append([at.distance_to(head - Vector2(0, 15) * ui_scale), unit])
		if not unit.may_cover(camera, at, 10 * ui_scale): continue
		var rects := unit_rects(unit)
		if rects.is_empty(): continue
		var rect := Rect2(rects[0])
		var distance := at.distance_to(at.clamp(rect.position, rect.end))
		if distance > 10 * ui_scale: continue
		var depth := -(to_view * unit.global_position).z
		var part_hit := false
		for part in rects.slice(1):
			if Rect2(part).has_point(at): part_hit = true; break
		(exact if part_hit else nearby).append([distance, depth, unit])
	# The visible HP marker remains a reliable target when bodies overlap.
	if not headers.is_empty():
		headers.sort_custom(func(a,b): return a[0] < b[0])
		return headers[0][1]
	var hits := exact if not exact.is_empty() else nearby
	if hits.is_empty(): return null
	hits.sort_custom(func(a, b): return a[0] < b[0] if not is_equal_approx(a[0], b[0]) else a[1] < b[1])
	return hits[0][2]


func _gui_input(event: InputEvent) -> void:
	if match_state == null: return
	if event is InputEventMouseMotion:
		if _orbit and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			yaw -= event.relative.x * 0.008
			_update_camera()
		hover_point = ground_point(event.position)
		hovered = _pick(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_orbit = event.pressed
		elif event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
					zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 12, 46)
					_update_camera()
				MOUSE_BUTTON_LEFT:
					grab_focus()
					var u := _pick(event.position)
					if u and (select_occupied or erase or ghost_id.is_empty() or match_state.phase != ArenaMatch.Phase.DEPLOY):
						creature_clicked.emit(u)
					else:
						ground_clicked.emit(ground_point(event.position))
				MOUSE_BUTTON_RIGHT:
					cancel_requested.emit()
		accept_event()


func _process(_dt: float) -> void:
	if match_state == null or not is_instance_valid(match_state.world): return
	if get_viewport().gui_get_hovered_control() == self:
		hovered = _pick(get_local_mouse_position())
	else:
		hovered = null
	if ghost:
		ghost.visible = hover_point != Vector2.INF and match_state.bounds().has_point(hover_point) \
			and match_state.phase == ArenaMatch.Phase.DEPLOY and not erase and hovered == null \
			and get_viewport().gui_get_hovered_control() == self
		if ghost.visible:
			ghost.position = Vector3(hover_point.x, match_state.world.terrain.height_at(hover_point.x, hover_point.y), -hover_point.y)
			ghost.rotation.y = GameUnit.MODEL_YAW_OFFSET if team == 0 else GameUnit.MODEL_YAW_OFFSET + PI
	if _ground_material: _ground_material.set_shader_parameter("deploying", match_state.phase == ArenaMatch.Phase.DEPLOY)
	overlay.queue_redraw()


func _ring(point: Vector2, radius: float, color: Color, width := 2.0) -> void:
	var line := PackedVector2Array()
	for i in 49:
		var angle := TAU * float(i) / 48
		line.append(screen_point(point + Vector2(cos(angle), sin(angle)) * radius))
	overlay.draw_polyline(line, color, width, true)


func health_anchor(unit: GameUnit) -> Vector2:
	return camera.unproject_position(unit.global_position + Vector3.UP * EnemyBars.head_top(unit)) - Vector2(0, 10 * ui_scale)


func _draw_overlay() -> void:
	if match_state == null or not is_instance_valid(match_state.world): return
	var font := ThemeDB.fallback_font
	var k := ui_scale
	for u: GameUnit in match_state.world.unit_rows():
		if u.dead or not u.visible or camera.is_position_behind(u.global_position): continue
		var color := BLUE if u.faction == 1 else RED
		var selected := highlighted_run_uid > 0 and int(u.get_meta("arena_placement", {}).get("run_uid", 0)) == highlighted_run_uid
		if show_team_rings:
			_ring(u.pos, maxf(0.55, u.body_radius() + 0.15), Color(color, 0.65), k)
		elif u == hovered or selected:
			var rects := unit_rects(u)
			if not rects.is_empty(): _selection_corners(Rect2(rects[0]).grow(5 * k), ArenaCreatureCard.GOLD if selected else color)
		var p := health_anchor(u)
		overlay.draw_style_box(_bar_style(), Rect2(p - Vector2(27, 3) * k, Vector2(54, 6) * k))
		overlay.draw_rect(Rect2(p - Vector2(25, 1) * k, Vector2(50 * clampf(u.hp / maxf(1, u.max_hp), 0, 1), 2) * k), color)
		if numeric_health:
			var placement: Dictionary = u.get_meta("arena_placement", {})
			var rank := int(placement.get("rank", ArenaUnitInfo.rank_of(String(u.info.get("prototype", "")))))
			if rank >= 0: ArenaStars.draw_rank(overlay, p - Vector2(((rank + 1) * 14 - 2) / 2.0, 38) * k, rank + 1, k)
		if numeric_health or u == hovered:
			var text := "%d/%d" % [maxi(0, ceili(u.hp)), ceili(u.max_hp)] if numeric_health else u.display_name
			var pixels := roundi(14 * k)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
			var at := p - Vector2(width / 2, 8 * k)
			overlay.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, maxi(3, roundi(3 * k)), Color("10151b"))
			overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, ArenaCreatureCard.PAPER)

	if ghost and ghost.visible:
		var valid := match_state.placement_error(hover_point).is_empty()
		_ring(hover_point, 0.9, (BLUE if team == 0 else RED) if valid else Color("ffcf75"), 3)


func _selection_corners(rect: Rect2, color: Color) -> void:
	var length := minf(12 * ui_scale, minf(rect.size.x, rect.size.y) * 0.35)
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var at: Vector2 = rect.position + rect.size * corner
		var inward: Vector2 = Vector2.ONE - corner * 2
		overlay.draw_polyline(PackedVector2Array([at + Vector2(inward.x * length, 0), at, at + Vector2(0, inward.y * length)]), color, 1.5 * ui_scale, true)


var _bar: StyleBoxFlat
func _bar_style() -> StyleBoxFlat:
	if _bar == null:
		_bar = StyleBoxFlat.new()
		_bar.bg_color = Color("10151b")
		_bar.set_corner_radius_all(2)
	return _bar

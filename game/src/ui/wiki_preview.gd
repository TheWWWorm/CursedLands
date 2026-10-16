class_name WikiPreview
extends Control
## Exactly one live model, using the inventory's real texture composition and
## creature appearance paths. Never constructs a GameUnit or changes the world.

var item: ItemView
var creature: Paperdoll
var _drag := false
var _turn := 0.0
var _zoom := 1.0
var _descriptor := {}
var _creature_fitted := false
var fit_slot := false
var _fit_distance := 0.0
var _fit_center := Vector3.ZERO


func _ready() -> void:
	# Fit after the paperdoll's pose/frame pass, before that frame is drawn.
	process_priority = 10
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(_resize_preview)


func show_model(descriptor: Dictionary) -> bool:
	clear()
	_descriptor = descriptor
	_turn = 0.0
	_zoom = 1.0
	_creature_fitted = false
	_fit_distance = 0.0
	if descriptor.is_empty(): return false
	if descriptor.kind == "creature":
		creature = Paperdoll.new()
		creature.view_size = Vector2i(180, 220)
		creature.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(creature)
		creature.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if fit_slot else Control.PRESET_FULL_RECT)
		_sync_resolution()
		creature.mouse_filter = Control.MOUSE_FILTER_IGNORE
		creature.custom_minimum_size = Vector2.ZERO
		creature.show_info({"prototype": descriptor.value})
		creature._cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		return creature._model != null
	item = ItemView.new()
	item.camp = true
	item.fit_slot = true
	add_child(item)
	item.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	item.show_item(descriptor.value)
	# Wiki rotation is controlled by the reader rather than the inventory's
	# hover spring. ItemView still owns all material and framing behavior.
	item.set_process(false)
	return item._model != null


func clear() -> void:
	_drag = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	item = null
	creature = null
	_descriptor = {}


func turn_by(radians: float) -> void:
	_turn += radians
	if is_instance_valid(creature): creature.turn_by(radians)
	if is_instance_valid(item) and is_instance_valid(item._model):
		var axis := item._axis if item._axis != Vector3.ZERO else Vector3(0, 1, 0)
		var q := Quaternion(axis, _turn) * item._base
		item._model.quaternion = EISpace.quat(q.w, q.x, q.y, q.z)
		item._model.position = -(item._model.basis * item._fit_center)


func zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, 0.55, 1.8)
	_resize_preview()


func reset_view() -> void:
	turn_by(-_turn)
	_zoom = 1.0
	_resize_preview()


func _resize_preview() -> void:
	if is_instance_valid(item) and is_instance_valid(item._fit_camera):
		item._fit_slot()
		item._fit_camera.size *= _zoom
	_creature_fitted = false
	_fit_distance = 0.0
	_fit_creature()


func _process(_dt: float) -> void:
	if fit_slot: _sync_resolution()
	if fit_slot or not _creature_fitted: _fit_creature()


## SubViewportContainer normally allocates logical pixels, even under a scaled
## HUD. Render at the displayed pixel density, then scale the container back.
func _sync_resolution() -> void:
	if not fit_slot or not is_instance_valid(creature): return
	var canvas_scale := get_global_transform_with_canvas().get_scale().abs()
	var density := clampf(maxf(canvas_scale.x, canvas_scale.y), 1.0, 4.0)
	var pixels := Vector2i((size * density).ceil()).max(Vector2i(1, 1))
	var inverse := Vector2.ONE / density
	if creature.scale != inverse: creature.scale = inverse
	if Vector2i(creature.size) != pixels: creature.size = Vector2(pixels)


func _fit_creature() -> void:
	if not is_instance_valid(creature) or creature._framed < 3 or creature._model == null: return
	# Paperdoll's hero framing uses height. The encyclopedia also shows wide
	# flying creatures: fit their complete horizontal orbit as well, so wings,
	# tails and weapons stay in view when turning the model.
	var box := AABB()
	var first := true
	var inverse := creature._pivot.global_transform.affine_inverse()
	for mesh: MeshInstance3D in creature._model.find_children("*", "MeshInstance3D", true, false):
		if not creature._shown_part(mesh): continue
		var bounds: AABB = (mesh.global_transform if fit_slot else inverse * mesh.global_transform) * mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	if first: return
	var width := Vector2(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z))).length() * 2.0
	var aspect := size.x / maxf(size.y, 1.0)
	var distance := maxf(box.size.y, width / maxf(aspect, 0.1)) * 0.5 / tan(deg_to_rad(30.0) * 0.5)
	distance = (distance * 1.15 + width * 0.5) * _zoom
	var center := Vector3(0, box.get_center().y, 0)
	if fit_slot:
		# Frame all visible meshes including held weapons and wings. Camera
		# KEEP_HEIGHT matches this calculation at both wide and narrow slots.
		creature._cam.keep_aspect = Camera3D.KEEP_HEIGHT
		if _fit_distance == 0: _fit_center = box.get_center()
		var radius_y := maxf(absf(box.position.y - _fit_center.y), absf(box.end.y - _fit_center.y))
		var radius_x := maxf(absf(box.position.x - _fit_center.x), absf(box.end.x - _fit_center.x))
		var fit := maxf(radius_y, radius_x / maxf(aspect, 0.1)) / tan(deg_to_rad(15.0))
		_fit_distance = maxf(_fit_distance, fit * 1.12 + maxf(0, box.end.z - _fit_center.z))
		distance = _fit_distance
		center = _fit_center
	creature.fov = 30.0
	creature._cam.fov = 30.0
	creature._cam.position = center + Vector3(0, 0, distance)
	creature._cam.far = maxf(100.0, distance + width * 2.0 + box.size.y)
	creature._cam.look_at(center)
	creature._cam.force_update_transform()
	_creature_fitted = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1)
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			turn_by(event.relative.x * 0.012)
		else:
			_drag = false
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_by(1.0 / maxf(event.factor, 0.01))
		accept_event()

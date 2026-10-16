class_name WikiPreview
extends Control
## Exactly one live model, using the inventory's real texture composition and
## creature appearance paths. Never constructs a GameUnit or changes the world.

var item: ItemView
var creature: Paperdoll
var map_view: TextureRect
var _map_pan := Vector2.ZERO
var _drag := false
var _turn := 0.0
var _zoom := 1.0
var _descriptor := {}
var _creature_fitted := false
var _item_fit_size := 0.0
var _item_fit_key := []


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
	_item_fit_size = 0.0
	if descriptor.is_empty(): return false
	if descriptor.kind == "map":
		var image := map_image(descriptor)
		if image == null: return false
		map_view = TextureRect.new()
		map_view.texture = ImageTexture.create_from_image(image)
		map_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		map_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(map_view)
		_map_pan = Vector2.ZERO
		_resize_preview()
		return true
	if descriptor.kind == "creature":
		creature = Paperdoll.new()
		creature.view_size = Vector2i(180, 220)
		creature.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(creature)
		creature.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	if descriptor.has("layer") and item._model != null:
		var texture := EIUnitModel._compose(descriptor.mask, [String(descriptor.layer)] as Array[String])
		if texture == null: clear(); return false
		for mesh: MeshInstance3D in item._model.find_children("*", "MeshInstance3D", true, false):
			var source := mesh.get_active_material(0) as StandardMaterial3D
			if source == null: continue
			var material := source.duplicate() as StandardMaterial3D
			material.albedo_texture = texture
			var scale := 256.0 / float(texture.get_width())
			material.uv1_scale = Vector3(scale, scale, 1)
			material.uv1_offset = Vector3(0, 1.0 - scale, 0)
			mesh.material_override = material
	# Wiki rotation is controlled by the reader rather than the inventory's
	# hover spring. ItemView still owns all material and framing behavior.
	item.set_process(false)
	_fit_item()
	return item._model != null


func clear() -> void:
	_drag = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	item = null
	creature = null
	map_view = null
	_descriptor = {}
	_item_fit_key.clear()


func turn_by(radians: float) -> void:
	_turn += radians
	if is_instance_valid(creature): creature.turn_by(radians)
	if is_instance_valid(item) and is_instance_valid(item._model):
		var axis := item._axis if item._axis != Vector3.ZERO else Vector3(0, 1, 0)
		var q := Quaternion(axis, _turn) * item._base
		item._model.quaternion = EISpace.quat(q.w, q.x, q.y, q.z)
		item._model.position = -(item._model.basis * item._fit_center)
		_fit_item()
	_creature_fitted = false
	_fit_creature()


func zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, 0.55, 1.8)
	_resize_preview()


func reset_view() -> void:
	turn_by(-_turn)
	_zoom = 1.0
	_map_pan = Vector2.ZERO
	_resize_preview()


func _resize_preview() -> void:
	if is_instance_valid(map_view):
		map_view.size = size / _zoom
		map_view.position = (size - map_view.size) * .5 + _map_pan
	if is_instance_valid(item) and is_instance_valid(item._fit_camera):
		item._fit_slot()
		_item_fit_size = 0.0
		_item_fit_key.clear()
		_fit_item()
	_creature_fitted = false
	_fit_creature()


func _process(_dt: float) -> void:
	if not _creature_fitted: _fit_creature()
	# Child container layout can resize ItemView after our resize callback.
	if is_instance_valid(item): _fit_item()


func _fit_item() -> void:
	if item._fit_camera == null or item._fit_points.is_empty(): return
	var key := [item.size, item._model.basis, _zoom]
	if key == _item_fit_key: return
	if not _item_fit_key.is_empty() and _item_fit_key[0] != item.size: _item_fit_size = 0.0
	_item_fit_key = key
	var box := AABB(item._model.transform * item._fit_points[0], Vector3.ZERO)
	for point: Vector3 in item._fit_points: box = box.expand(item._model.transform * point)
	var aspect := item.size.x / maxf(item.size.y, 1.0)
	var fitted := maxf(.05, maxf(box.size.z, box.size.x / maxf(aspect,.1)) * 1.15)
	if _item_fit_size == 0.0: _item_fit_size = fitted
	item._fit_camera.size = maxf(_item_fit_size, fitted) * _zoom
	item._fit_camera.position = Vector3(box.get_center().x, box.position.y - 2.0, box.get_center().z)
	item._fit_camera.far = box.size.y + 4.0


func _fit_creature() -> void:
	if not is_instance_valid(creature) or creature._framed < 3 or creature._model == null: return
	# Paperdoll's hero framing uses height. The encyclopedia also shows wide
	# flying creatures: include wings, tails and weapons in the shown pose.
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in creature._model.find_children("*", "MeshInstance3D", true, false):
		if not creature._shown_part(mesh): continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	if first: return
	# Fit the presented pose, rather than leaving empty room for the entire
	# 360-degree orbit. Explicit rotation refits the newly presented pose.
	var width := box.size.x
	var aspect := size.x / maxf(size.y, 1.0)
	var distance := maxf(box.size.y, width / maxf(aspect, 0.1)) * 0.5 / tan(deg_to_rad(30.0) * 0.5)
	distance = (distance * 1.15 + box.size.z * 0.5) * _zoom
	var center := box.get_center()
	creature.fov = 30.0
	creature._cam.fov = 30.0
	creature._cam.position = center + Vector3(0, 0, distance)
	creature._cam.far = maxf(100.0, distance + width * 2.0 + box.size.y)
	creature._cam.look_at(center)
	creature._cam.force_update_transform()
	_creature_fitted = true


## The same north-up crop as the original objectives screen. This reads a
## single authored picture; opening a map creates no world or gameplay state.
static func map_image(descriptor: Dictionary) -> Image:
	var image := GameData.load_image(descriptor.value)
	if image == null: return null
	image.flip_y()
	var dimensions: Array = descriptor.get("dimensions", [1,1])
	var extent := maxf(float(dimensions[0]), float(dimensions[1]))
	var width := clampi(roundi(image.get_width()*float(dimensions[0])/extent),1,image.get_width())
	var height := clampi(roundi(image.get_height()*float(dimensions[1])/extent),1,image.get_height())
	return image.get_region(Rect2i(0,image.get_height()-height,width,height))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1)
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if map_view != null:
				_map_pan += event.relative
				_resize_preview()
			else: turn_by(event.relative.x * 0.012)
		else:
			_drag = false
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_by(1.0 / maxf(event.factor, 0.01))
		accept_event()

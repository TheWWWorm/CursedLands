class_name WikiPreview
extends Control
## Exactly one live model, using the inventory's real texture composition and
## creature appearance paths. Never constructs a GameUnit or changes the world.

signal article_requested(key: String)
var _pins: Array = []
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
var _pin_popup: PopupPanel
var _popup_points: Array = []

class MapPin extends Button:
	var count := 1
	var tint := Color("3d6558")
	var exit := false
	var angle := 0.0
	func _draw() -> void:
		var centre := size*.5
		var radius := 14.0 if count>1 else 6.0
		if exit:
			var points := PackedVector2Array()
			for v: Vector2 in [Vector2(0,-14),Vector2(13,9),Vector2(0,4),Vector2(-13,9),Vector2(0,-14)]:points.append(centre+v.rotated(angle))
			draw_colored_polygon(points,Color("75b548"));draw_polyline(points,Color("284421"),2,true)
		else:
			draw_circle(centre,radius+2,Color("f4ead2"))
			draw_circle(centre,radius,tint)
		if has_focus():draw_arc(centre,radius+5,0,TAU,32,Color("d5ae57"),2,true)
		if count>1:
			var font := get_theme_font("font")
			var label := str(count)
			draw_string(font,centre+Vector2(-font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x*.5,4),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)


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
	_pins.clear()
	_pin_popup=null
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
	_zoom = clampf(_zoom * factor, 0.2 if map_view else 0.55, 1.0 if map_view else 1.8)
	_resize_preview()


func reset_view() -> void:
	turn_by(-_turn)
	_zoom = 1.0
	_map_pan = Vector2.ZERO
	_resize_preview()


func _resize_preview() -> void:
	if is_instance_valid(map_view):
		map_view.size = size / _zoom
		var bounds := (map_view.size-size)*.5
		_map_pan=_map_pan.clamp(-bounds,bounds)
		map_view.position = (size - map_view.size) * .5 + _map_pan
		_place_pins()
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


func set_pins(pins: Array) -> void:
	_pins=pins
	_place_pins()

func _place_pins() -> void:
	if not is_instance_valid(map_view) or map_view.texture==null: return
	var image_size := map_view.texture.get_size()
	var factor := minf(map_view.size.x/image_size.x,map_view.size.y/image_size.y)
	var drawn := image_size*factor
	var origin := (map_view.size-drawn)*.5
	for child in map_view.get_children():map_view.remove_child(child);child.queue_free()
	# Group positions in screen space, so zooming progressively reveals detail.
	# Exit and quest markers retain their identity; creature groups are quieter.
	var groups := {}
	for pin: Dictionary in _pins:
		var point := origin+Vector2(pin.x,pin.y)*drawn
		if not Rect2(-map_view.position-Vector2(16,16),size+Vector2(32,32)).has_point(point):continue
		var cell := 82.0 if pin.kind=="inhabitant" else 42.0
		var grid := Vector2i(floori(point.x/cell),floori(point.y/cell))
		var id := String(pin.kind)+str(grid)
		var group: Dictionary=groups.get_or_add(id,{"point":Vector2.ZERO,"pins":[]})
		group.point+=point;group.pins.append(pin)
	for group: Dictionary in groups.values():
		var button := MapPin.new();button.count=group.pins.size();button.size=Vector2(36,36);button.custom_minimum_size=button.size;button.set_meta("map_pin",true)
		button.exit=group.pins[0].kind=="exit"
		var location := Vector2(group.pins[0].x,group.pins[0].y)-Vector2(.5,.5)
		button.angle=(PI if location.y<0 else 0.0) if absf(location.y)>=absf(location.x) else (-PI*.5 if location.x>0 else PI*.5)
		button.tint=Color("90602d") if group.pins[0].kind=="quest" else Color("315a83") if group.pins[0].kind=="exit" else Color("3d6558")
		for state: String in ["normal","hover","pressed","focus"]:button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var names := PackedStringArray()
		for pin: Dictionary in group.pins:
			if not names.has(pin.title):names.append(pin.title)
		button.tooltip_text="\n".join(names)
		button.pressed.connect(func():_select_pins(group.pins))
		button.focus_entered.connect(button.queue_redraw);button.focus_exited.connect(button.queue_redraw)
		map_view.add_child(button);button.position=group.point/group.pins.size()-button.size*.5

	_position_pin_popup()

func _position_pin_popup() -> void:
	if not is_instance_valid(_pin_popup) or not _pin_popup.visible or _popup_points.is_empty():return
	var image_size := map_view.texture.get_size()
	var drawn := image_size*minf(map_view.size.x/image_size.x,map_view.size.y/image_size.y)
	var point := Vector2.ZERO
	for pin: Dictionary in _popup_points:point+=Vector2(pin.x,pin.y)
	point/=float(_popup_points.size())
	var at := get_global_rect().position+map_view.position+(map_view.size-drawn)*.5+point*drawn
	var area := get_global_rect()
	var origin := at+Vector2(24,-_pin_popup.size.y*.5)
	if origin.x+_pin_popup.size.x>area.end.x-8:origin.x=at.x-24-_pin_popup.size.x
	origin=origin.clamp(area.position+Vector2(8,8),area.end-Vector2(_pin_popup.size)-Vector2(8,8))
	_pin_popup.position=Vector2i(origin)

func _select_pins(points: Array) -> void:
	if is_instance_valid(_pin_popup):_pin_popup.queue_free()
	_popup_points=points
	_pin_popup=PopupPanel.new();_pin_popup.theme=theme;add_child(_pin_popup)
	var style := StyleBoxFlat.new();style.bg_color=Color("f6f1e6");style.set_corner_radius_all(10);style.set_content_margin_all(14);style.shadow_color=Color(0,0,0,.25);style.shadow_size=12;style.shadow_offset=Vector2(0,5);_pin_popup.add_theme_stylebox_override("panel",style)
	var body := VBoxContainer.new();body.add_theme_constant_override("separation",10);_pin_popup.add_child(body)
	var close := Button.new();close.text=RemakeText.t("Close");close.pressed.connect(_pin_popup.hide);body.add_child(close)
	var scroll := ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(scroll)
	var list := VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",8);scroll.add_child(list)
	var grouped := {}
	for point: Dictionary in points:
		var row: Dictionary=grouped.get_or_add(point.key,{"title":point.title,"count":0});row.count+=1
	for key: String in grouped:
		var row: Dictionary=grouped[key]
		var button := Button.new();button.text=row.title+(" ×"+str(row.count) if row.count>1 else "");button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;button.custom_minimum_size.y=48;button.add_theme_color_override("font_color",Color("2d392b"))
		button.pressed.connect(func():_pin_popup.hide();article_requested.emit(key));list.add_child(button)
	var width := minf(320,size.x-44)
	scroll.custom_minimum_size=Vector2(width,minf(260,grouped.size()*56))
	_pin_popup.popup(Rect2i(Vector2i.ZERO,Vector2i(width+28,mini(340,grouped.size()*56+78))))
	_position_pin_popup()
	close.grab_focus()

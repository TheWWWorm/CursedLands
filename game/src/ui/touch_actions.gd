class_name TouchActions
extends Control
## Two small additions beside the existing HUD. Menus, shops and dials keep
## their original controls; the overflow makes keyboard entry points reachable.
var game: Game
var _menu: Button
var _aim: Button
var _popup: PanelContainer
var _grid: GridContainer
var _aim_open := false
var _icons: Array[Texture2D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu = _button("≡", func(): _show_menu())
	_aim = _button("", func(): _show_aim())
	for cursor in Game.AIM_CURSORS:
		var frames := GameCursor.frames(cursor)
		_icons.append(ImageTexture.create_from_image(frames[0]) if not frames.is_empty() else null)
	_aim.icon = _icons[1]
	_aim.tooltip_text = RemakeText.t("Aim at a body part")
	add_child(_menu)
	add_child(_aim)
	_popup = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.045, 0.025, 0.94)
	style.border_color = Color(0.47, 0.38, 0.23)
	style.set_border_width_all(1)
	style.set_content_margin_all(3)
	_popup.add_theme_stylebox_override("panel", style)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	_popup.add_child(_grid)
	add_child(_popup)
	_popup.hide()

func _button(title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = RemakeText.t(title)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	button.add_theme_font_override("font", Interface800.font())
	button.add_theme_color_override("font_color", Interface800.TEXT)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.13, 0.08, 0.9) if state == "normal" else Color(0.30, 0.24, 0.13)
		style.border_color = Color(0.47, 0.38, 0.23)
		style.set_border_width_all(1)
		style.set_content_margin_all(5)
		button.add_theme_stylebox_override(state, style)
	return button

func _process(_dt: float) -> void:
	visible = TouchInput.enabled and is_instance_valid(game) and not game.hud._movie.visible
	if not visible:
		return
	var safe := Rect2(Vector2.ZERO, size)
	var cell := TouchInput.target_pixels() / get_global_transform_with_canvas().get_scale().x
	# The aim button belongs beside the party faces, as in the touch sketch.
	# Keep the small menu access beside the original top-left unit panel.
	var x := minf(size.y * 195.0 / 600.0, safe.end.x - cell - 12)
	_menu.position = Vector2(x, safe.position.y + 6)
	_menu.size = Vector2(cell, cell)
	var party_width := maxf(56.0, game.hud._faces._cells.size() * 56.0) * size.y / 600.0
	_aim.position = Vector2(size.x * 0.5 - party_width * 0.5 - cell - 8, size.y - cell - 8)
	_aim.size = Vector2(cell, cell)
	_aim.icon = _icons[game.touch_aim] if game.touch_aim >= 0 else _icons[1]
	_aim.modulate = Color(1.3, 1.15, 0.7) if game.touch_aim >= 0 else Color.WHITE
	_aim.visible = not game.hud.blocks_camera() and not game.session.shop_available()
	_menu.visible = not game.hud.blocks_camera()
	if not _menu.visible:
		_popup.hide()
	for child: Button in _grid.get_children():
		child.custom_minimum_size = Vector2(cell * (1.25 if _aim_open else 1.8), cell)
		child.add_theme_font_size_override("font_size", maxi(12, int(cell * 0.29)))
	_popup.position = Vector2(clampf(_aim.position.x + cell * 0.5 - _popup.size.x * 0.5, 0, size.x - _popup.size.x), _aim.position.y - _popup.size.y - 6) if _aim_open else Vector2(x, cell + 12)
	_menu.add_theme_font_size_override("font_size", int(cell * 0.40))
	_aim.add_theme_font_size_override("font_size", int(cell * 0.30))

func _clear_popup() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_popup.size = Vector2.ZERO

func _entry(title: String, action: Callable) -> void:
	_grid.add_child(_button(title, func():
		_popup.hide()
		# Original menus capture the current frame as their backdrop. Let the
		# overflow disappear before that capture, so it cannot leave a ghost.
		if not _aim_open and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		action.call()))

func _show_aim() -> void:
	if _popup.visible and _aim_open:
		_popup.hide()
		game.cancel_touch_target()
		return
	_clear_popup()
	_aim_open = true
	_grid.columns = 3
	for i in 6:
		_entry(["Head", "Body", "L arm", "R arm", "L leg", "R leg"][i], func():
			game.pending_spell = ""
			game.touch_force = ""
			game.touch_aim = i
			game.hud.set_targeting(""))
	_popup.show()

func _show_menu() -> void:
	if _popup.visible and not _aim_open:
		_popup.hide()
		return
	_clear_popup()
	_aim_open = false
	_grid.columns = 2
	_entry("Inventory", game.hud.toggle_inventory)
	_entry("Journal", game.hud.toggle_journal)
	_entry("Menu", game.hud.toggle_menu)
	_entry("Select all", func(): game.selected.assign(game.my_units()))
	_entry("Centre", func():
		if not game.selected.is_empty(): game.rig.center_on(game.selected[0].global_position))
	_entry("Cancel action", game.cancel_touch_target)
	_entry("Force move", func(): game.cancel_touch_target(); game.touch_force = "alt")
	_entry("Force attack", func(): game.cancel_touch_target(); game.touch_force = "ctrl")
	if game.session.shop_available():
		_entry("Side quests", game.hud.toggle_side_quests)
	if game.session.online:
		_entry("Chat", game.hud.chat_line.open)
	if OS.has_feature("web"):
		_entry("Fullscreen", func(): JavaScriptBridge.get_interface("CursedFiles").fullscreen())
	_popup.show()

func _input(event: InputEvent) -> void:
	if not visible or not _popup.visible or not event is InputEventMouseButton or not event.pressed:
		return
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * (event as InputEventMouseButton).position
	if not _popup.get_rect().has_point(point) and not _aim.get_rect().has_point(point) and not _menu.get_rect().has_point(point):
		_popup.hide()
		get_viewport().set_input_as_handled()

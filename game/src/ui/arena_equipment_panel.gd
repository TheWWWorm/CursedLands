class_name ArenaEquipmentPanel
extends VBoxContainer
## Reward choices only. Owned equipment lives on the persistent board tray.

signal choose_requested(index: int)
var run: ArenaRun
var focus_scope: Control
var busy := false:
	set(value):
		busy = value
		synchronize()
var _offer_row: HBoxContainer
var _message: Label
var _state_key := ""

func _ready() -> void:
	name = "EquipmentRewards"
	add_theme_constant_override("separation", 16)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offer_row = HBoxContainer.new()
	_offer_row.name = "ItemRewards"
	_offer_row.add_theme_constant_override("separation", 18)
	add_child(_offer_row)
	var fallback := _label(self, RemakeText.t("If you do not choose, the first reward goes to your inventory when battle starts."), 13, ArenaCreatureCard.MUTED)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message = _label(self, "", 14, Color("efbf87"))
	_message.hide()
	synchronize()

func synchronize() -> void:
	if not is_node_ready() or run == null: return
	var key := JSON.stringify([run.item_offers, run.stage, run.preparing_battle, busy])
	if key == _state_key: return
	_state_key = key
	for child in _offer_row.get_children():
		_offer_row.remove_child(child)
		child.queue_free()
	for index in run.item_offers.size():
		var kind := String(run.item_offers[index])
		var card := Button.new()
		card.name = "Reward%d" % index
		card.set_meta("reward_index", index)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(250, 350)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.accessibility_name = RemakeText.t("Choose %s") % ArenaItems.title(kind)
		card.disabled = busy or run.stage != "prepare" or run.preparing_battle or not run.can_shop()
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var border := ArenaCreatureCard.GOLD if state in ["hover", "focus"] else Color("44514f")
			card.add_theme_stylebox_override(state, ArenaCreatureCard.style(Color.TRANSPARENT, border, Vector2.ZERO))
		_offer_row.add_child(card)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 0)
		card.add_child(column)
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 2; column.offset_right = -2
		column.offset_top = 2; column.offset_bottom = -2
		var header := PanelContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var accent := ArenaItemEmblem.color_for(kind)
		header.add_theme_stylebox_override("panel", ArenaCreatureCard.style(accent.darkened(0.76), Color.TRANSPARENT, Vector2(14, 14)))
		column.add_child(header)
		var heading := VBoxContainer.new()
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heading.add_theme_constant_override("separation", 10)
		header.add_child(heading)
		var art := ArenaItemEmblem.new()
		art.kind = kind
		art.custom_minimum_size = Vector2(96, 96)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		heading.add_child(art)
		var title := _label(heading, ArenaItems.title(kind), 21, accent.lightened(0.45))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.custom_minimum_size.y = 48
		var body := PanelContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_theme_stylebox_override("panel", ArenaCreatureCard.style(Color("101718"), Color.TRANSPARENT, Vector2(16, 16)))
		column.add_child(body)
		var description := _label(body, ArenaItems.description(kind), 14, ArenaCreatureCard.PAPER)
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		column.minimum_size_changed.connect(func(): card.custom_minimum_size.y = maxf(350, column.get_combined_minimum_size().y + 4))
		card.pressed.connect(func():
			if not busy: choose_requested.emit(index))
	_link_focus.call_deferred()

func focus_first() -> void:
	if _offer_row.get_child_count() > 0: _offer_row.get_child(0).grab_focus()

func _link_focus() -> void:
	var controls: Array[Control] = []
	var scope := focus_scope if is_instance_valid(focus_scope) else self
	for node in scope.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and not node.disabled: controls.append(node)
	for i in controls.size():
		controls[i].focus_next = controls[i].get_path_to(controls[(i + 1) % controls.size()])
		controls[i].focus_previous = controls[i].get_path_to(controls[(i - 1 + controls.size()) % controls.size()])

func show_message(message: String) -> void:
	_message.text = message
	_message.visible = not message.is_empty()

func _label(parent: Node, text: String, pixels: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

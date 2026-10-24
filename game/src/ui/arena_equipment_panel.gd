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
	var tiers := _label(self, RemakeText.t("Item tiers 1–5 unlock after rounds 3, 5, 10, 15 and 20. Each reward offers three items of the same tier."), 12, ArenaCreatureCard.MUTED)
	tiers.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		var card := preload("res://src/ui/arena_equipment_reward.gd").new()
		card.kind = kind
		card.name = "Reward%d" % index
		card.set_meta("reward_index", index)
		card.disabled = busy or run.stage != "prepare" or run.preparing_battle or not run.can_shop()
		_offer_row.add_child(card)
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

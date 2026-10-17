class_name ArenaRewardCard
extends Button
## The complete reward is one target, using items from the original archives.

const ART := {"experience": "dcbook", "scout": "map00", "merchant": "rangersign00",
	"reserve": "thiefsack", "purse": "sackofgold", "supplies": "govenorchest00", "life": "driadidol01"}
var reward := {}
var preview: WikiPreview


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var fill := Color("1d2422")
		var edge := Color("746b4e")
		if state in ["hover", "hover_pressed"]: fill = Color("343c32"); edge = ArenaCreatureCard.GOLD
		elif state == "pressed": fill = Color("494936"); edge = ArenaCreatureCard.GOLD
		elif state == "focus": fill = Color.TRANSPARENT; edge = ArenaCreatureCard.PAPER
		elif state == "disabled": fill = Color("151b19"); edge = Color("45483d")
		add_theme_stylebox_override(state, ArenaCreatureCard.style(fill, edge, Vector2(12, 12)))
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var words: Array = ArenaRules.BOONS[reward.kind]
	var title := _label(box, RemakeText.t(words[0]), 20, ArenaCreatureCard.GOLD)
	title.add_theme_font_override("font", preload("res://fonts/LiberationSerif-Regular.ttf"))
	preview = WikiPreview.new()
	preview.fit_slot = true
	preview.custom_minimum_size = Vector2(80, 110)
	box.add_child(preview)
	var companion: bool = reward.kind == "companion"
	preview.show_model({"kind": "creature" if companion else "item", "value": reward.prototype if companion else ART[reward.kind]})
	if companion:
		preview.turn_by(-0.35)
		_label(box, ArenaRules.title(reward.prototype), 14, ArenaCreatureCard.GOLD)
	_label(box, RemakeText.t(words[1]), 14, ArenaCreatureCard.PAPER)
	# Button does not measure children. Track the wrapped content's real height
	# once its equal-width column has been allocated by the reward row.
	margin.minimum_size_changed.connect(func(): custom_minimum_size.y = margin.get_combined_minimum_size().y)
	resized.connect(func(): custom_minimum_size.y = margin.get_combined_minimum_size().y)
	custom_minimum_size.y = margin.get_combined_minimum_size().y
	if disabled: box.modulate.a = 0.5
	for child: Control in find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accessibility_name = RemakeText.t(words[0])


func _label(parent: Node, value: String, pixels: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

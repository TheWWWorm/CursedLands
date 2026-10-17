class_name BuildVersion
extends Interface800
## Shared menu footer, sourced from the same version as crash reports.
var _margin: MarginContainer
var _label: Label
var above_pad_hints := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = MarginContainer.new()
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	_label = Label.new()
	_label.text = RemakeText.t("Version %s") % String(ProjectSettings.get_setting("application/config/version", "?"))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", Interface800.font())
	_label.add_theme_color_override("font_color", Interface800.TEXT)
	_label.add_theme_color_override("font_shadow_color", Interface800.SHADOW)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_margin.add_child(_label)
	resized.connect(_layout)
	PadInput.mode_changed.connect(_layout)
	_layout()

func footer_height() -> float:
	return _label.get_combined_minimum_size().y + 8.0

func _layout() -> void:
	var safe := _safe()
	_margin.position = safe.position
	_margin.size = safe.size
	for edge in ["left", "top", "right"]:
		_margin.add_theme_constant_override("margin_" + edge, 16)
	var bottom := 16
	if above_pad_hints and PadInput.active == "pad":
		bottom += ceili(40.0 * safe.size.y / 600.0)
	_margin.add_theme_constant_override("margin_bottom", bottom)
	# Use the existing interface typography scale, with a readable small-window floor.
	_label.add_theme_font_size_override("font_size", maxi(16, font_px(0)))

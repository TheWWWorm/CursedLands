class_name ScrollOptionButton
extends OptionButton
## Keep long lists scrollable instead of letting their minimum height push
## entries off-screen. PopupMenu handles wheel, touch and keyboard navigation.
const MAX_HEIGHT := 900.0

var _display_font: Font
var _popup_font: Font

func _ready() -> void:
	_display_font = get_theme_font("font").duplicate()
	_popup_font = get_popup().get_theme_font("font").duplicate()
	add_theme_font_override("font", _display_font)
	get_popup().add_theme_font_override("font", _popup_font)
	set_notify_transform(true)
	_update_font_sampling()
	get_popup().about_to_popup.connect(_limit_popup)
	get_popup().visibility_changed.connect(_finish_popup.call_deferred)
	get_viewport().size_changed.connect(get_popup().hide)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		_update_font_sampling()

func _update_font_sampling() -> void:
	# These menus use logical UI units. Rasterize at their actual display
	# scale instead of enlarging a 14/16 px glyph atlas (also after resize).
	var pixels := get_global_transform_with_canvas().get_scale().abs() \
		* get_viewport().get_screen_transform().get_scale().abs()
	var sampling := maxf(1.0, maxf(pixels.x, pixels.y))
	for font: Font in [_display_font, _popup_font]:
		if font is SystemFont or font is FontFile:
			font.oversampling = sampling

func _popup_bounds() -> Rect2:
	var bounds := Portability.safe_rect(get_viewport_rect().size).grow(-8)
	if not get_popup().is_embedded():
		bounds = get_viewport().get_screen_transform() * bounds
	return bounds

func _limit_popup() -> void:
	_update_font_sampling()
	var bounds := _popup_bounds()
	var popup_scale := get_global_transform_with_canvas().get_scale().abs()
	if not get_popup().is_embedded():
		popup_scale *= get_viewport().get_screen_transform().get_scale().abs()
	# Window limits are display pixels, not the popup's scaled content units.
	get_popup().max_size = Vector2i(bounds.size.x,
		minf(bounds.size.y, MAX_HEIGHT * minf(popup_scale.x, popup_scale.y)))

func _finish_popup() -> void:
	var popup := get_popup()
	if not popup.visible: return
	var bounds := _popup_bounds()
	popup.position = Vector2i(Vector2(popup.position).clamp(bounds.position, bounds.end - Vector2(popup.size)))
	# PopupMenu calculates item offsets on its first draw, after the container
	# layout. A previously unseen list must also reveal a selection at its end.
	await get_tree().process_frame
	if is_instance_valid(popup) and popup.visible and selected >= 0:
		popup.scroll_to_item(selected)

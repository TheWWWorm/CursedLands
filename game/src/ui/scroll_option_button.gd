class_name ScrollOptionButton
extends OptionButton
## Keep long lists scrollable instead of letting their minimum height push
## entries off-screen. PopupMenu handles wheel, touch and keyboard navigation.
const MAX_HEIGHT := 360.0

func _ready() -> void:
	get_popup().about_to_popup.connect(_limit_popup)
	get_popup().visibility_changed.connect(_finish_popup.call_deferred)
	get_viewport().size_changed.connect(get_popup().hide)

func _popup_bounds() -> Rect2:
	var bounds := Portability.safe_rect(get_viewport_rect().size).grow(-8)
	if not get_popup().is_embedded():
		bounds = get_viewport().get_screen_transform() * bounds
	return bounds

func _limit_popup() -> void:
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

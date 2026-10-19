class_name SideQuestPanel
extends PanelContainer
## Village quest offers from the quest maps (see SideQuests). Accepting sends
## a command to the host, which plays the offer briefing for the whole party.

var hud: GameHUD
var _list: VBoxContainer
var _scroll: ScrollContainer
var _close: Button
var _layout_queued := false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var title := Label.new()
	title.text = RemakeText.t("Village quests")
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	_close = Button.new()
	_close.text = RemakeText.t("Close")
	_close.pressed.connect(hide)
	root.add_child(_close)
	_list.minimum_size_changed.connect(_queue_layout)
	visibility_changed.connect(_queue_layout)
	get_parent_control().resized.connect(_queue_layout)
	_queue_layout()


func _queue_layout() -> void:
	if _layout_queued: return
	_layout_queued = true
	_layout.call_deferred()


func _layout() -> void:
	_layout_queued = false
	if not is_instance_valid(_scroll): return
	# Stay inside the HUD's safe area when a long offer list becomes the short
	# "current task" message, and after a phone rotates or its browser resizes.
	var available := get_parent_control().size - Vector2(24, 24)
	var width := minf(560, available.x)
	var button_height := maxf(44.0, TouchInput.target_pixels() / get_global_transform_with_canvas().get_scale().y) if TouchInput.enabled else 32.0
	_close.custom_minimum_size.y = button_height
	for child in _list.get_children():
		if child is Button: child.custom_minimum_size.y = button_height
	var chrome := get_combined_minimum_size().y
	var height := minf(available.y, minf(540, chrome + _list.get_combined_minimum_size().y))
	size = Vector2(maxf(1, width), maxf(chrome, height))
	position = (get_parent_control().size - size) * 0.5


func open() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var s := hud.game.session
	var offers := SideQuests.offers(s)
	var busy := s.state.side_quests.values().any(func(v): return v == "active" or v == "done")
	if offers.is_empty():
		var l := Label.new()
		l.text = RemakeText.t("Finish your current task first." if busy else "Nobody here needs help right now.")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
	for q: Dictionary in offers:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.set_meta("wiki_context", {"key": "quest/" + String(q.id).uri_encode()})
		l.text = RemakeText.t("%s  (%s, %d experience)\n%s") % [q.title, s.zone_title(SideQuests.zone_of(s, q)), int(q.exp), q.desc]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		var b := Button.new()
		b.text = RemakeText.t("Accept")
		b.set_meta("wiki_context", {"key": "quest/" + String(q.id).uri_encode()})
		b.pressed.connect(func():
			visible = false
			hud.game.issue({"t": "side_quest", "q": q.id}))
		_list.add_child(b)
	visible = true
	_scroll.scroll_vertical = 0
	_queue_layout()

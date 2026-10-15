class_name WikiPanel
extends PanelContainer
## Searchable, linked HTML encyclopedia with one lazily loaded model preview.
## Opened through the normal menu modal, so single-player pause and co-op
## input routing follow the existing menu lifecycle.

signal closed

const PAGE_SIZE := 80
var catalog: WikiCatalog
var current := "home"
var html := ""
var _query: LineEdit
var _category: OptionButton
var _results: ItemList
var _status: Label
var _back: Button
var _forward: Button
var _previous: Button
var _next: Button
var _article: RichTextLabel
var _preview: WikiPreview
var _preview_box: VBoxContainer
var _unavailable: Label
var _builder: VBoxContainer
var _runes: OptionButton
var _add_rune: Button
var _reset_spell: Button
var _body: BoxContainer
var _sidebar: VBoxContainer
var _content: BoxContainer
var _matches: Array[String] = []
var _offset := 0
var _history: Array[Dictionary] = []
var _history_at := -1
var _page_revision := 0
var _ui_scale := -1.0
var _title: Label
var _versions: HFlowContainer
var _version_block: VBoxContainer
var _selected_versions := {}


func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = Theme.new()
	theme.default_font = Interface800.font()
	add_to_group("pad_panel")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 12
	offset_top = 12
	offset_right = -12
	offset_bottom = -12
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171b20")
	style.border_color = Color("80704e")
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var toolbar := HBoxContainer.new()
	box.add_child(toolbar)
	_back = _button(toolbar, "←", func(): history(-1), RemakeText.t("Back"))
	_forward = _button(toolbar, "→", func(): history(1), RemakeText.t("Forward"))
	_button(toolbar, RemakeText.t("Contents"), func(): navigate("home"))
	var title := Label.new()
	_title = title
	title.text = RemakeText.t("Game wiki")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	toolbar.add_child(title)
	_button(toolbar, RemakeText.t("Close"), close)
	var search_row := HBoxContainer.new()
	box.add_child(search_row)
	_category = ScrollOptionButton.new()
	for category: String in WikiCatalog.CATEGORIES: _category.add_item(RemakeText.t(category))
	_category.tooltip_text = RemakeText.t("Choose which kind of pages to search.")
	_category.item_selected.connect(func(_i): _filter())
	search_row.add_child(_category)
	_query = LineEdit.new()
	_query.placeholder_text = RemakeText.t("Search the wiki…")
	_query.tooltip_text = RemakeText.t("Search localized page names. Every word must match.")
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.text_changed.connect(func(_value): _filter())
	search_row.add_child(_query)
	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16)
	box.add_child(_body)
	_sidebar = VBoxContainer.new()
	_body.add_child(_sidebar)
	_results = ItemList.new()
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results.allow_reselect = true
	_results.auto_height = false
	_results.add_theme_font_size_override("font_size", 16)
	_results.item_selected.connect(func(index: int): navigate(String(_results.get_item_metadata(index))))
	_sidebar.add_child(_results)
	var pages := HBoxContainer.new()
	_sidebar.add_child(pages)
	_previous = _button(pages, "←", func(): _offset = maxi(0, _offset - PAGE_SIZE); _fill_results(), RemakeText.t("Previous results"))
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	pages.add_child(_status)
	_next = _button(pages, "→", func(): _offset += PAGE_SIZE; _fill_results(), RemakeText.t("Next results"))
	_content = BoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 16)
	_body.add_child(_content)
	var article_column := VBoxContainer.new()
	article_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	article_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(article_column)
	_version_block = VBoxContainer.new()
	article_column.add_child(_version_block)
	var version_title := Label.new()
	version_title.text = RemakeText.t("Material / version")
	_version_block.add_child(version_title)
	_versions = HFlowContainer.new()
	_version_block.add_child(_versions)
	_article = RichTextLabel.new()
	_article.bbcode_enabled = true
	_article.selection_enabled = true
	_article.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_article.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_article.custom_minimum_size = Vector2(100, 70)
	_article.add_theme_font_override("normal_font", Interface800.font())
	_article.add_theme_font_size_override("normal_font_size", 18)
	_article.add_theme_font_size_override("bold_font_size", 18)
	_article.add_theme_color_override("default_color", Color("e4ddcf"))
	_article.add_theme_color_override("font_selected_color", Color.WHITE)
	_article.meta_clicked.connect(func(meta): follow_link(str(meta)))
	article_column.add_child(_article)
	_preview_box = VBoxContainer.new()
	_content.add_child(_preview_box)
	var model_title := Label.new()
	model_title.text = RemakeText.t("3D preview")
	model_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_box.add_child(model_title)
	_preview = WikiPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.tooltip_text = RemakeText.t("Drag to rotate. Scroll to zoom. The buttons also work with touch and a controller.")
	_preview_box.add_child(_preview)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	_preview_box.add_child(controls)
	_button(controls, "↶", func(): _preview.turn_by(-PI / 6.0), RemakeText.t("Rotate left"))
	_button(controls, "↷", func(): _preview.turn_by(PI / 6.0), RemakeText.t("Rotate right"))
	_button(controls, "+", func(): _preview.zoom_by(0.9), RemakeText.t("Zoom in"))
	_button(controls, "−", func(): _preview.zoom_by(1.1), RemakeText.t("Zoom out"))
	_button(controls, "↺", _preview.reset_view, RemakeText.t("Reset view"))
	_unavailable = Label.new()
	_unavailable.text = RemakeText.t("This game data has no model for this entry.")
	_unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_box.add_child(_unavailable)
	_builder = VBoxContainer.new()
	_preview_box.add_child(_builder)
	_runes = ScrollOptionButton.new()
	_runes.fit_to_longest_item = false
	_runes.clip_text = true
	_runes.tooltip_text = RemakeText.t("Choose a compatible rune to calculate a spell variant.")
	_runes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_builder.add_child(_runes)
	_add_rune = _button(_builder, RemakeText.t("Add rune"), _with_rune)
	_reset_spell = _button(_builder, RemakeText.t("Reset spell"), _without_runes)
	resized.connect(_layout)
	_layout()


func open(rules: Dictionary = {}) -> void:
	# Rebuild even when a mod patches the database in place. Indexing has no
	# model loads, and takes only a few frames for the original campaigns.
	catalog = WikiCatalog.new()
	catalog.rebuild()
	_history.clear()
	_history_at = -1
	if not catalog.entries.has(current): current = "home"
	catalog.rules = rules.duplicate(true)
	show()
	move_to_front()
	_filter()
	navigate(current, _history_at < 0)
	_query.grab_focus()


func close() -> void:
	if not visible: return
	dismiss()
	closed.emit()


## Closing an owning menu / host load is not another user close event.
func dismiss() -> void:
	hide()
	_page_revision += 1
	_preview.clear()


func _filter() -> void:
	if catalog == null: return
	_offset = 0
	_matches = catalog.search(_query.text, WikiCatalog.CATEGORIES[_category.selected])
	_fill_results()


func _fill_results() -> void:
	_results.clear()
	_offset = clampi(_offset, 0, maxi(0, (_matches.size() - 1) / PAGE_SIZE * PAGE_SIZE))
	for index in range(_offset, mini(_offset + PAGE_SIZE, _matches.size())):
		var key := _matches[index]
		var entry: Dictionary = catalog.entries[key]
		_results.add_item(entry.title)
		_results.set_item_metadata(_results.item_count - 1, key)
		_results.set_item_tooltip(_results.item_count - 1, entry.title + " · " + RemakeText.t(entry.category))
		if key == current: _results.select(_results.item_count - 1)
	_previous.disabled = _offset <= 0
	_next.disabled = _offset + PAGE_SIZE >= _matches.size()
	_status.text = RemakeText.t("%d pages") % _matches.size()
	if _matches.is_empty(): _status.text = RemakeText.t("No matching pages")
	else: _status.tooltip_text = "%d–%d / %d" % [_offset + 1, mini(_offset + PAGE_SIZE, _matches.size()), _matches.size()]


func navigate(key: String, remember := true, variant := "") -> void:
	if catalog == null or not catalog.entries.has(key): return
	if remember:
		if _history_at >= 0:
			_history[_history_at].scroll = _article.get_v_scroll_bar().value
		if _history_at < 0 or key != _history[_history_at].key:
			_history.resize(_history_at + 1)
			_history.append({"key": key, "scroll": 0.0, "variant": variant})
			if _history.size() > 100: _history.pop_front()
			_history_at = _history.size() - 1
	current = key
	if variant.is_empty(): variant = String(_selected_versions.get(key, ""))
	var page := catalog.page(key, variant)
	_selected_versions[key] = page.get("variant", "")
	if _history_at >= 0 and _history[_history_at].key == key:
		_history[_history_at].variant = page.get("variant", "")
	_fill_versions(key, page.get("variant", ""))
	html = page.html
	_article.text = WikiHtml.to_bbcode(html, _ui_scale)
	_article.scroll_to_line(0)
	_page_revision += 1
	_preview_box.visible = not page.preview.is_empty()
	var available := _preview.show_model(page.preview)
	_unavailable.visible = not available
	_builder.visible = catalog.entries[key].kind == "spell"
	if _builder.visible: _fill_runes(catalog.entries[key].value)
	_back.disabled = _history_at <= 0
	_forward.disabled = _history_at >= _history.size() - 1
	for index in _results.item_count:
		if _results.get_item_metadata(index) == key: _results.select(index)
	_layout()


func history(direction: int) -> void:
	var index := _history_at + direction
	if index < 0 or index >= _history.size(): return
	_history[_history_at].scroll = _article.get_v_scroll_bar().value
	_history_at = index
	navigate(_history[index].key, false, _history[index].get("variant", ""))
	var revision := _page_revision
	# RichTextLabel updates the scroll range on the next layout.
	await get_tree().process_frame
	if revision == _page_revision: _article.get_v_scroll_bar().value = _history[index].scroll


func follow_link(url: String) -> void:
	var destination := WikiHtml.key_from_url(url)
	var key := destination.get_slice("?", 0)
	if key.begins_with("category/"):
		var category := key.trim_prefix("category/").uri_decode()
		var index := WikiCatalog.CATEGORIES.find(category)
		if index < 0: return
		_category.select(index)
		_query.text = ""
		_filter()
	elif not key.is_empty():
		var variant := destination.get_slice("?version=", 1).uri_decode() if "?version=" in destination else ""
		navigate(key, true, variant)


func _fill_versions(key: String, selected: String) -> void:
	for child in _versions.get_children():
		_versions.remove_child(child)
		child.queue_free()
	var choices := catalog.variants_for(key)
	_version_block.visible = choices.size() > 1
	if choices.size() <= 1: return
	for id: String in choices:
		var label := RemakeText.t("Blueprint") if id.begins_with("bp:") else WikiCatalog.item_title(id)
		var info := Items.info(id)
		if not id.begins_with("bp:") and not info.mat.is_empty():
			label = WikiCatalog.item_title(Items.material_unit(info.material))
		var button := _button(_versions, label, func(): navigate(key, false, id), WikiCatalog.item_title(id))
		button.toggle_mode = true
		button.set_pressed_no_signal(id == selected)
		button.set_meta("version", id)


func _fill_runes(spell: String) -> void:
	_runes.clear()
	var allowed := []
	for row: Dictionary in GameData.db.table("spell_modifiers"):
		var code := String(row.get("code", "")).to_lower()
		if WikiCatalog.rune_fits(spell, code): allowed.append(code)
	allowed.sort_custom(func(a, b): return WikiCatalog.rune_title(a).naturalnocasecmp_to(WikiCatalog.rune_title(b)) < 0)
	for code: String in allowed:
		_runes.add_item(WikiCatalog.rune_title(code))
		_runes.set_item_metadata(_runes.item_count - 1, code)
	_runes.disabled = allowed.is_empty()
	_add_rune.disabled = allowed.is_empty()
	_reset_spell.disabled = Spells.mods_of(spell).is_empty()
	if allowed.is_empty(): _runes.add_item(RemakeText.t("No compatible runes"))


func _with_rune() -> void:
	if _runes.disabled or _runes.selected < 0: return
	var spell := String(catalog.entries[current].value)
	var code := String(_runes.get_item_metadata(_runes.selected))
	if not WikiCatalog.rune_fits(spell, code): return
	var key := catalog.add_variant(Spells.with_mod(spell, code))
	if key: navigate(key)


func _without_runes() -> void:
	var spell := String(catalog.entries[current].value).get_slice("{", 0)
	navigate("spell/" + spell.uri_encode())


func _layout() -> void:
	if _body == null: return
	var scale := clampf(size.y / 900.0, 0.85, 3.0)
	if not is_equal_approx(scale, _ui_scale):
		_ui_scale = scale
		theme.default_font_size = roundi(18 * scale)
		_title.add_theme_font_size_override("font_size", roundi(24 * scale))
		_results.add_theme_font_size_override("font_size", roundi(17 * scale))
		_status.add_theme_font_size_override("font_size", roundi(14 * scale))
		_article.add_theme_font_size_override("normal_font_size", roundi(20 * scale))
		_article.add_theme_font_size_override("bold_font_size", roundi(20 * scale))
		for button: Node in find_children("*", "Button", true, false): button.custom_minimum_size.y = roundi(36 * scale)
		if not html.is_empty(): _article.text = WikiHtml.to_bbcode(html, scale)
	var narrow := size.x / scale < 850
	var short := size.y / scale < 600
	_body.vertical = narrow
	_sidebar.custom_minimum_size = Vector2(0, (95 if short else 150) * scale) if narrow else Vector2(clampf(size.x * 0.23, 190 * scale, 290 * scale), 0)
	_sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	_sidebar.size_flags_vertical = Control.SIZE_FILL if narrow else Control.SIZE_EXPAND_FILL
	_content.vertical = size.x / scale < 650
	_preview_box.custom_minimum_size = Vector2(0, (145 if short else 210) * scale) if _content.vertical else Vector2(clampf(size.x * 0.22, 170 * scale, 320 * scale), 0)
	_preview.custom_minimum_size = Vector2(100, (70 if short else 120) * scale)


func _input(event: InputEvent) -> void:
	# LineEdit consumes Escape during GUI dispatch. Handle the modal's close
	# before that dispatch, while letting an open choice popup close first.
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode != KEY_ESCAPE: return
	if _category.get_popup().visible or _runes.get_popup().visible: return
	close()
	get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		close()
	elif event.alt_pressed and event.keycode == KEY_LEFT:
		history(-1)
	elif event.alt_pressed and event.keycode == KEY_RIGHT:
		history(1)
	else:
		return
	get_viewport().set_input_as_handled()


func pad_press(action: String, phase: String) -> bool:
	if phase != "down": return false
	match action:
		"cancel": close()
		"actions": history(-1)
		"items": history(1)
		"mod", "system":
			_article.get_v_scroll_bar().value += -120 if action == "mod" else 120
		_: return false
	return true


func pad_targets() -> Array:
	var targets := [{"rect": _query.get_global_rect(), "id": "wiki_search"}]
	for control: Node in find_children("*", "Button", true, false):
		if control.is_visible_in_tree() and not control.disabled:
			targets.append({"rect": control.get_global_rect(), "id": control.get_instance_id()})
	var view := _results.get_global_rect()
	for index in _results.item_count:
		var rect := _results.get_item_rect(index)
		rect.position += view.position - Vector2(0, _results.get_v_scroll_bar().value)
		rect = rect.intersection(view)
		if rect.has_area(): targets.append({"rect": rect, "id": "wiki_page_%d" % index})
	return targets


func _button(parent: Control, text: String, callback: Callable, tip := "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size.y = roundi(36 * maxf(_ui_scale, 0.85))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

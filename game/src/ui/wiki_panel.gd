class_name WikiPanel
extends PanelContainer
## Searchable, linked HTML encyclopedia with one lazily loaded model preview.
## Opened through the normal menu modal, so single-player pause and co-op
## input routing follow the existing menu lifecycle.

signal closed

var catalog: WikiCatalog
var current := "home"
var html := ""
var _query: LineEdit
var _category: OptionButton
var _subcategory: OptionButton
var _results: ItemList
var _status: Label
var _back: Button
var _forward: Button
var _article: RichTextLabel
var _preview: WikiPreview
var _preview_box: VBoxContainer
var _unavailable: Label
var _representative: Label
var _builder: VBoxContainer
var _builder_scroll: ScrollContainer
var _item_spells: OptionButton
var _apply_item_button: Button
var _builder_status: Label
var _rune_preview: WikiPreview
var _draft_item_spell := ""
var _draft_item_key := ""
var _runes: OptionButton
var _add_rune: Button
var _reset_spell: Button
var _remove_rune: Button
var _body: BoxContainer
var _sidebar: VBoxContainer
var _content: BoxContainer
var _matches: Array[String] = []
var _history: Array[Dictionary] = []
var _history_at := -1
var _page_revision := 0
var _ui_scale := -1.0
var _title: Label
var _versions: HFlowContainer
var _version_block: VBoxContainer
var _selected_versions := {}
var _model_title: Label
var _rotate_buttons: Array[Button] = []
var _campaign_buttons: Array[Button] = []
var _sources := {}
var _catalogs := {}
var _source: WikiSource
var _rules := {}


func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = Theme.new()
	theme.default_font = Interface800.font()
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = Color("353b40") if state == "hover" else Color("454b3c") if state == "pressed" else Color("242a30")
		button_style.border_color = Color("b19b69") if state in ["hover","focus"] else Color("635d4c")
		button_style.set_border_width_all(1)
		button_style.set_corner_radius_all(3)
		button_style.content_margin_left = 9
		button_style.content_margin_right = 9
		button_style.content_margin_top = 5
		button_style.content_margin_bottom = 5
		theme.set_stylebox(state,"Button",button_style)
		theme.set_stylebox(state,"OptionButton",button_style)
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
	var campaigns := HFlowContainer.new()
	box.add_child(campaigns)
	for id: String in [CampaignProfile.ORIGINAL, CampaignProfile.ASTRAL]:
		var text := RemakeText.t("Base game") if id == CampaignProfile.ORIGINAL else RemakeText.t("Expansion — Lost in Astral")
		var button := _button(campaigns, text, func(): _select_campaign(id))
		button.toggle_mode = true
		button.set_meta("campaign",id)
		_campaign_buttons.append(button)
	var search_row := HBoxContainer.new()
	box.add_child(search_row)
	_category = ScrollOptionButton.new()
	for category: String in WikiCatalog.CATEGORIES: _category.add_item(RemakeText.t(category))
	_category.tooltip_text = RemakeText.t("Choose which kind of pages to search.")
	_category.item_selected.connect(func(_i): _subcategory.select(0); _filter())
	search_row.add_child(_category)
	_subcategory = ScrollOptionButton.new()
	_subcategory.add_item(RemakeText.t("All items"))
	_subcategory.set_item_metadata(0, "")
	for type: String in WikiCatalog.ITEM_TYPES:
		_subcategory.add_item(RemakeText.t(WikiCatalog.ITEM_TYPES[type]))
		_subcategory.set_item_metadata(_subcategory.item_count - 1, type)
	_subcategory.tooltip_text = RemakeText.t("Filter by armour slot, weapon type or item purpose.")
	_subcategory.item_selected.connect(func(_i): _filter())
	search_row.add_child(_subcategory)
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
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	_sidebar.add_child(_status)
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
	_model_title = model_title
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
	_rotate_buttons.append(_button(controls, "↶", func(): _preview.turn_by(-PI / 6.0), RemakeText.t("Rotate left")))
	_rotate_buttons.append(_button(controls, "↷", func(): _preview.turn_by(PI / 6.0), RemakeText.t("Rotate right")))
	_button(controls, "+", func(): _preview.zoom_by(0.9), RemakeText.t("Zoom in"))
	_button(controls, "−", func(): _preview.zoom_by(1.1), RemakeText.t("Zoom out"))
	_button(controls, "↺", _preview.reset_view, RemakeText.t("Reset view"))
	_unavailable = Label.new()
	_unavailable.text = RemakeText.t("This game data has no model for this entry.")
	_unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_box.add_child(_unavailable)
	_representative = Label.new()
	_representative.text = RemakeText.t("Authored appearance; this material has no separate texture.")
	_representative.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_box.add_child(_representative)
	_builder_scroll = ScrollContainer.new()
	_builder_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_builder_scroll.custom_minimum_size.y = 200
	_preview_box.add_child(_builder_scroll)
	_builder = VBoxContainer.new()
	_builder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_builder_scroll.add_child(_builder)
	_item_spells = ScrollOptionButton.new()
	_item_spells.fit_to_longest_item = false
	_item_spells.clip_text = true
	_item_spells.tooltip_text = RemakeText.t("Choose a spell to preview on this item.")
	_item_spells.item_selected.connect(func(_index): _source.read(_choose_item_spell))
	_builder.add_child(_item_spells)
	_runes = ScrollOptionButton.new()
	_runes.fit_to_longest_item = false
	_runes.clip_text = true
	_runes.tooltip_text = RemakeText.t("Choose a compatible rune to calculate a spell variant.")
	_runes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_runes.item_selected.connect(func(_index): _source.read(_show_rune_art))
	_builder.add_child(_runes)
	_rune_preview = WikiPreview.new()
	_rune_preview.custom_minimum_size = Vector2(60,72)
	_builder.add_child(_rune_preview)
	_add_rune = _button(_builder, RemakeText.t("Add rune"), _with_rune)
	_remove_rune = _button(_builder,RemakeText.t("Remove last rune"),func(): _source.read(_remove_last_rune))
	_reset_spell = _button(_builder, RemakeText.t("Reset spell"), _without_runes)
	_apply_item_button = _button(_builder, RemakeText.t("Preview enchanted item"), func(): _source.read(_apply_item_spell))
	_builder_status = Label.new()
	_builder_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_builder.add_child(_builder_status)
	resized.connect(_layout)
	_layout()


func open(rules: Dictionary = {}) -> void:
	# Rebuild even when a mod patches the database in place. Indexing has no
	# model loads, and takes only a few frames for the original campaigns.
	_rules = rules.duplicate(true)
	_sources.clear()
	_catalogs.clear()
	show()
	move_to_front()
	for button: Button in _campaign_buttons:
		var id := String(button.get_meta("campaign"))
		button.disabled = id != GameData.campaign_id and not GameData.campaign_roots.has(id)
		button.tooltip_text = RemakeText.t("Install this campaign through Game files to browse its wiki.") if button.disabled else RemakeText.t("Browse this campaign without changing the current game.")
	_select_campaign(GameData.campaign_id)
	_query.grab_focus()


func _select_campaign(id: String) -> void:
	if not _sources.has(id):
		var source := WikiSource.new()
		var error := source.load_installed(id)
		if error:
			_status.text = error
			for button: Button in _campaign_buttons: button.set_pressed_no_signal(button.get_meta("campaign") == _source.campaign)
			return
		_sources[id] = source
	_source = _sources[id]
	if not _catalogs.has(id):
		_catalogs[id] = _source.read(func():
			var result := WikiCatalog.new()
			result.rules = _rules.duplicate(true)
			result.rebuild()
			return result)
	catalog = _catalogs[id]
	_history.clear()
	_history_at = -1
	current = "home"
	_query.text = ""
	for button: Button in _campaign_buttons: button.set_pressed_no_signal(button.get_meta("campaign") == id)
	_filter()
	navigate("home")


func close() -> void:
	if not visible: return
	dismiss()
	closed.emit()


## Closing an owning menu / host load is not another user close event.
func dismiss() -> void:
	hide()
	_page_revision += 1
	_preview.clear()
	_rune_preview.clear()
	_sources.clear()
	_catalogs.clear()
	_source = null


func _filter() -> void:
	if catalog == null: return
	_subcategory.visible = WikiCatalog.CATEGORIES[_category.selected] == "Items"
	var subtype := String(_subcategory.get_item_metadata(_subcategory.selected)) if _subcategory.visible else ""
	_matches = _source.read(func(): return catalog.search(_query.text, WikiCatalog.CATEGORIES[_category.selected], subtype))
	_fill_results()


func _fill_results() -> void:
	_results.clear()
	for key: String in _matches:
		var entry: Dictionary = catalog.entries[key]
		_results.add_item(entry.title)
		_results.set_item_metadata(_results.item_count - 1, key)
		_results.set_item_tooltip(_results.item_count - 1, entry.title + " · " + RemakeText.t(entry.category))
		if key == current: _results.select(_results.item_count - 1)
	_status.text = RemakeText.t("%d pages") % _matches.size()
	if _matches.is_empty(): _status.text = RemakeText.t("No matching pages")
	_status.tooltip_text = _status.text


func navigate(key: String, remember := true, variant := "") -> void:
	if _source == null: return
	_source.read(func(): _navigate(key,remember,variant))


func _navigate(key: String, remember: bool, variant: String) -> void:
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
	var is_map: bool = page.preview.get("kind", "") == "map"
	_model_title.text = RemakeText.t("Map overview") if is_map else RemakeText.t("3D preview")
	_preview.tooltip_text = RemakeText.t("Drag to pan. Scroll to zoom.") if is_map else RemakeText.t("Drag to rotate. Scroll to zoom. The buttons also work with touch and a controller.")
	for button: Button in _rotate_buttons: button.visible = not is_map
	_unavailable.visible = not available
	_representative.visible = available and page.preview.get("representative", false)
	var is_spell: bool = catalog.entries[key].kind == "spell"
	var is_item := catalog.craftable(key) and not String(page.get("variant", "")).begins_with("bp:")
	_builder.visible = is_spell or is_item
	_builder_scroll.visible = _builder.visible
	_item_spells.visible = is_item
	_apply_item_button.visible = is_item
	_builder_status.text = ""
	if is_spell:
		_fill_runes(catalog.entries[key].value)
	elif is_item:
		if key != _draft_item_key:
			_draft_item_key = key
			_draft_item_spell = Items.spell_of(page.variant)
		_fill_item_spells()
	else: _rune_preview.clear()
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
		_subcategory.select(0)
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
		var label := RemakeText.t("Blueprint") if id.begins_with("bp:") else catalog.display_item_title(id)
		var info := Items.info(id)
		if not id.begins_with("bp:") and not info.mat.is_empty():
			label = WikiCatalog.item_title(Items.material_unit(info.material))
		var button := _button(_versions, label, func(): navigate(key, false, id), catalog.display_item_title(id))
		button.toggle_mode = true
		button.set_pressed_no_signal(id == selected)
		button.set_meta("version", id)


func _fill_runes(spell: String) -> void:
	var selected := String(_runes.get_item_metadata(_runes.selected)) if _runes.selected >= 0 and not _runes.disabled else ""
	_runes.clear()
	var allowed := []
	for row: Dictionary in GameData.db.table("spell_modifiers"):
		var code := String(row.get("code", "")).to_lower()
		if WikiCatalog.rune_listed(code) and WikiCatalog.rune_fits(spell, code): allowed.append(code)
	allowed.sort_custom(func(a, b): return WikiCatalog.rune_title(a).naturalnocasecmp_to(WikiCatalog.rune_title(b)) < 0)
	for code: String in allowed:
		_runes.add_item(WikiCatalog.rune_title(code))
		_runes.set_item_metadata(_runes.item_count - 1, code)
		if code == selected: _runes.select(_runes.item_count - 1)
	_runes.disabled = allowed.is_empty()
	_add_rune.disabled = allowed.is_empty()
	_reset_spell.disabled = Spells.mods_of(spell).is_empty()
	_remove_rune.disabled = _reset_spell.disabled
	if allowed.is_empty(): _runes.add_item(RemakeText.t("No compatible runes"))
	_show_rune_art()


func _show_rune_art() -> void:
	_rune_preview.clear()
	if _runes.disabled or _runes.selected < 0: return
	var code := String(_runes.get_item_metadata(_runes.selected))
	_rune_preview.show_model({"kind":"item","value":"rune:"+code})
	_rune_preview.tooltip_text = WikiCatalog.rune_title(code)


func _fill_item_spells() -> void:
	_item_spells.clear()
	for key: String in catalog.search("", "Spells"):
		var spell := String(catalog.entries[key].value)
		_item_spells.add_item(WikiCatalog.spell_title(spell))
		_item_spells.set_item_metadata(_item_spells.item_count - 1,spell)
		if spell == _draft_item_spell.get_slice("{",0): _item_spells.select(_item_spells.item_count - 1)
	if _draft_item_spell.is_empty() and _item_spells.item_count: _draft_item_spell = _item_spells.get_item_metadata(_item_spells.selected)
	_fill_runes(_draft_item_spell)
	_item_draft_status()


func _choose_item_spell() -> void:
	_draft_item_spell = String(_item_spells.get_item_metadata(_item_spells.selected))
	_fill_runes(_draft_item_spell)
	_item_draft_status()


func _item_draft_status() -> void:
	var item := Items.plain(String(_selected_versions.get(current,"")))
	_apply_item_button.disabled = not Items.can_enchant(item,_draft_item_spell)
	_builder_status.text = WikiCatalog.spell_title(_draft_item_spell) + "\n" + RemakeText.t("Complexity %s / %s · Energy %s / %s") % [WikiCatalog.num(Spells.complexity(_draft_item_spell)),WikiCatalog.num(Items.slots(item)),WikiCatalog.num(Spells.parse(_draft_item_spell).mana),WikiCatalog.num(Items.energy(item))]
	if _apply_item_button.disabled: _builder_status.text += "\n" + RemakeText.t("The spell must fit the item's complexity and energy limits. Weapons and armour also need a triggered or continuous item rune.")


func _apply_item_spell() -> void:
	var item := Items.plain(String(_selected_versions.get(current,"")))
	var built := catalog.construct_item(current,item,_draft_item_spell)
	if not built.is_empty(): _navigate(current,false,built)


func _with_rune() -> void:
	_source.read(_add_selected_rune)


func _add_selected_rune() -> void:
	if _runes.disabled or _runes.selected < 0: return
	var is_item: bool = catalog.entries[current].kind == "item"
	var spell := _draft_item_spell if is_item else String(catalog.entries[current].value)
	var code := String(_runes.get_item_metadata(_runes.selected))
	if not WikiCatalog.rune_fits(spell, code): return
	if is_item:
		_draft_item_spell = Spells.with_mod(spell,code)
		_fill_runes(_draft_item_spell)
		_item_draft_status()
		return
	var key := catalog.add_variant(Spells.with_mod(spell, code))
	if key: _navigate(key,true,"")


func _without_runes() -> void:
	if catalog.entries[current].kind == "item":
		_draft_item_spell = _draft_item_spell.get_slice("{",0)
		navigate(current,false,String(_selected_versions[current]).get_slice("|",0))
		return
	var spell := String(catalog.entries[current].value).get_slice("{", 0)
	navigate("spell/" + spell.uri_encode())


func _remove_last_rune() -> void:
	var is_item: bool = catalog.entries[current].kind == "item"
	var spell := _draft_item_spell if is_item else String(catalog.entries[current].value)
	var runes := Spells.mods_of(spell)
	if runes.is_empty(): return
	runes.remove_at(runes.size()-1)
	var built := spell.get_slice("{",0) + ("{" + ";".join(runes) + "}" if not runes.is_empty() else "")
	if is_item:
		_draft_item_spell = built
		_fill_runes(built)
		_item_draft_status()
	else:
		var key := catalog.add_variant(built)
		if key: _navigate(key,true,"")


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
	_builder_scroll.custom_minimum_size.y = (115 if short or _content.vertical else 200) * scale
	_rune_preview.custom_minimum_size = Vector2(60,72) * scale


func _input(event: InputEvent) -> void:
	# LineEdit consumes Escape during GUI dispatch. Handle the modal's close
	# before that dispatch, while letting an open choice popup close first.
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode != KEY_ESCAPE: return
	if _category.get_popup().visible or _subcategory.get_popup().visible or _runes.get_popup().visible: return
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

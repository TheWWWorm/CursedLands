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
var _results: WikiResults
var _status: Label
var _back: Button
var _forward: Button
var _article: RichTextLabel
var _preview: WikiPreview
var _preview_box: VBoxContainer
var _unavailable: Label
var _representative: Label
var _workbench: WikiWorkbench
var _camp_constructor: WikiCampConstructor
var _workbench_open := false
var _workbench_toggle: Button
var _rune_families: HFlowContainer
var _rune_group := "e"
var _rune_palette: HFlowContainer
var _assembly: BoxContainer
var _assembly_values: RichTextLabel
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
var _versions: ScrollOptionButton
var _version_block: VBoxContainer
var _selected_versions := {}
var _model_title: Label
var _rotate_buttons: Array[Button] = []
var _campaign_buttons: Array[Button] = []
var _sources := {}
var _catalogs := {}
var _source: WikiSource
var _reading_surface: PanelContainer
var _home_view: WikiHome
var _page_title: Label
var _page_subtitle: Label
var _actions: HFlowContainer
var _rules := {}
var _plan_by_campaign := {}
var _planner: WikiPlanner
var _add_plan: Button
var _save_creation: Button
var _library_view: WikiLibraryView
var _craft_slot := ""
var _craft_key := ""
var _share: Button
var _guide_button: Button
var _guide := ""
var _base_html := ""
var _map_filters: HFlowContainer
var _map_pins: Array = []
var _map_kinds := {"exit":true,"quest":true,"inhabitant":false}
var _import_text: LineEdit
var _import_toggle: Button
var _action_status: Label
var _compact_controls: HFlowContainer
var _browse_toggle: Button
var _preview_toggle: Button
var _narrow_browsing := false
var _narrow_preview := false
var _has_preview := false
var _article_column: VBoxContainer


func _ready() -> void:
	hide()
	process_mode=Node.PROCESS_MODE_ALWAYS
	theme=Theme.new();theme.default_font=load("res://fonts/LiberationSans-Regular.ttf");theme.default_font_size=16
	for type: String in ["Label","Button","OptionButton","CheckButton","LineEdit"]:theme.set_color("font_color",type,Color("eee8d8"))
	theme.set_color("font_placeholder_color","LineEdit",Color("b7c4ad"))
	theme.set_constant("arrow_margin","OptionButton",14)
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new();style.bg_color=Color("41513b") if state in ["hover","pressed"] else Color("26372d");style.border_color=Color("8d986e") if state=="focus" else Color("52614b");style.set_border_width_all(1);style.set_corner_radius_all(4);style.set_content_margin_all(8)
		for type: String in ["Button","OptionButton","LineEdit"]:theme.set_stylebox(state,type,style)
	add_to_group("pad_panel")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);offset_left=14;offset_top=14;offset_right=-14;offset_bottom=-14
	mouse_filter=Control.MOUSE_FILTER_STOP
	var frame := StyleBoxFlat.new();frame.bg_color=Color("1d2b23");frame.border_color=Color("7a7958");frame.set_border_width_all(1);frame.set_corner_radius_all(8);frame.set_content_margin_all(18);add_theme_stylebox_override("panel",frame)
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",18);add_child(box)
	var toolbar := HBoxContainer.new();toolbar.add_theme_constant_override("separation",8);box.add_child(toolbar)
	_title=Label.new();_title.text="Cursed Lands · "+RemakeText.t("Game wiki");_title.add_theme_font_override("font",Interface800.font());_title.add_theme_font_size_override("font_size",28);_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(_title)
	_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_back=_button(toolbar,RemakeText.t("Back"),func():history(-1))
	_forward=_button(toolbar,RemakeText.t("Forward"),func():history(1))
	_button(toolbar,RemakeText.t("Close"),close)
	_compact_controls=HFlowContainer.new();box.add_child(_compact_controls)
	_browse_toggle=_button(_compact_controls,RemakeText.t("Browse and search"),func():
		_narrow_browsing=not _narrow_browsing;_layout()
		if _narrow_browsing:_query.grab_focus())
	_preview_toggle=_button(_compact_controls,RemakeText.t("Show illustration"),func():_narrow_preview=not _narrow_preview;_layout(),RemakeText.t("Show or hide the model, map and construction controls."))
	_body=BoxContainer.new();_body.size_flags_vertical=Control.SIZE_EXPAND_FILL;_body.add_theme_constant_override("separation",20);box.add_child(_body)
	_sidebar=VBoxContainer.new();_sidebar.add_theme_constant_override("separation",10);_body.add_child(_sidebar)
	var campaigns := HFlowContainer.new();_sidebar.add_child(campaigns)
	for id: String in [CampaignProfile.ORIGINAL,CampaignProfile.ASTRAL]:
		var text := RemakeText.t("Base game") if id==CampaignProfile.ORIGINAL else RemakeText.t("Lost in Astral")
		var button := _button(campaigns,text,func():_select_campaign(id));button.toggle_mode=true;button.set_meta("campaign",id);_campaign_buttons.append(button)
	var navigation := HBoxContainer.new();_sidebar.add_child(navigation)
	_button(navigation,RemakeText.t("Contents"),func():navigate("home"))
	_button(navigation,RemakeText.t("Build planner"),func():navigate("mechanics/planning"))
	_button(_sidebar,RemakeText.t("Saved creations"),_open_library)
	_query=LineEdit.new();_query.placeholder_text=RemakeText.t("Search the wiki…");_query.clear_button_enabled=true;_query.tooltip_text=RemakeText.t("Search names, materials and locations. Small spelling mistakes are tolerated.");_query.text_changed.connect(func(_value):_filter());_sidebar.add_child(_query)
	_category=ScrollOptionButton.new();_category.fit_to_longest_item=false
	for category: String in WikiCatalog.CATEGORIES:_category.add_item(RemakeText.t(category))
	_category.item_selected.connect(func(_i):_subcategory.select(0);_filter());_category.tooltip_text=RemakeText.t("Choose which kind of pages to search.");_sidebar.add_child(_category)
	_subcategory=ScrollOptionButton.new();_subcategory.fit_to_longest_item=false;_subcategory.add_item(RemakeText.t("All items"));_subcategory.set_item_metadata(0,"")
	for type: String in WikiCatalog.ITEM_TYPES:_subcategory.add_item(RemakeText.t(WikiCatalog.ITEM_TYPES[type]));_subcategory.set_item_metadata(_subcategory.item_count-1,type)
	_subcategory.item_selected.connect(func(_i):_filter());_subcategory.tooltip_text=RemakeText.t("Filter by armour slot, weapon type or item purpose.");_sidebar.add_child(_subcategory)
	_results=WikiResults.new();_results.size_flags_vertical=Control.SIZE_EXPAND_FILL;_sidebar.add_child(_results);_results.item_selected.connect(func(index):navigate(String(_results.get_item_metadata(index))))
	_status=Label.new();_status.add_theme_font_size_override("font_size",12);_status.add_theme_color_override("font_color",Color("b7c4ad"));_sidebar.add_child(_status)
	_reading_surface=PanelContainer.new();_reading_surface.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_reading_surface.size_flags_vertical=Control.SIZE_EXPAND_FILL;_reading_surface.theme=_paper_theme();_body.add_child(_reading_surface)
	var paper := StyleBoxFlat.new();paper.bg_color=Color("f1ebdc");paper.set_corner_radius_all(6);paper.set_content_margin_all(26);_reading_surface.add_theme_stylebox_override("panel",paper)
	_content=BoxContainer.new();_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_content.size_flags_vertical=Control.SIZE_EXPAND_FILL;_content.add_theme_constant_override("separation",24);_reading_surface.add_child(_content)
	_article_column=VBoxContainer.new()
	var article_column := _article_column;article_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;article_column.size_flags_vertical=Control.SIZE_EXPAND_FILL;article_column.add_theme_constant_override("separation",12);_content.add_child(article_column)
	_home_view=WikiHome.new();_home_view.size_flags_vertical=Control.SIZE_EXPAND_FILL;_home_view.article_requested.connect(func(key):navigate(key));_home_view.category_requested.connect(func(category):follow_link("wiki://category/"+String(category).uri_encode()));article_column.add_child(_home_view)
	_page_title=Label.new();_page_title.add_theme_font_override("font",Interface800.font());_page_title.add_theme_font_size_override("font_size",36);_page_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;article_column.add_child(_page_title)
	_page_subtitle=Label.new();_page_subtitle.add_theme_color_override("font_color",Color("637057"));_page_subtitle.add_theme_font_size_override("font_size",13);_page_subtitle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;article_column.add_child(_page_subtitle)
	_actions=HFlowContainer.new();article_column.add_child(_actions)
	_add_plan=_button(_actions,RemakeText.t("Add to plan"),func():_source.read(_add_current_to_plan));_share=_button(_actions,RemakeText.t("Copy link"),_copy_link);_guide_button=_button(_actions,RemakeText.t("Quest hints"),_toggle_guide);_guide_button.toggle_mode=true
	_save_creation=_button(_actions,RemakeText.t("Save locally"),func():_source.read(_save_current_creation))
	_button(_actions,RemakeText.t("Saved creations"),_open_library)
	_workbench_toggle=_button(_actions,RemakeText.t("Open constructor"),func():_workbench_open=not _workbench_open;_layout())
	_action_status=Label.new();_action_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_action_status.add_theme_font_size_override("font_size",13);article_column.add_child(_action_status)
	_import_toggle=_button(_actions,RemakeText.t("Import build"),func():_import_text.visible=not _import_text.visible;_import_text.grab_focus())
	_import_text=LineEdit.new();_import_text.placeholder_text=RemakeText.t("Paste a build link and press Enter");_import_text.max_length=26000;_import_text.text_submitted.connect(_import_plan);article_column.add_child(_import_text)
	_planner=WikiPlanner.new();_planner.size_flags_vertical=Control.SIZE_EXPAND_FILL;_planner.article_requested.connect(func(key,variant):navigate(key,true,variant));_planner.craft_requested.connect(_craft_equipment);article_column.add_child(_planner)
	_version_block=VBoxContainer.new();article_column.add_child(_version_block)
	var version_title := Label.new();version_title.text=RemakeText.t("Material / version");version_title.add_theme_font_size_override("font_size",13);_version_block.add_child(version_title)
	_versions=ScrollOptionButton.new();_versions.fit_to_longest_item=false;_versions.item_selected.connect(func(i):navigate(current,false,String(_versions.get_item_metadata(i))));_version_block.add_child(_versions)
	_article=RichTextLabel.new();_article.bbcode_enabled=true;_article.selection_enabled=true;_article.size_flags_vertical=Control.SIZE_EXPAND_FILL;_article.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_article.custom_minimum_size=Vector2(100,70);_article.add_theme_constant_override("line_separation",5);_article.meta_clicked.connect(func(meta):follow_link(str(meta)));article_column.add_child(_article)
	_preview_box=VBoxContainer.new();_preview_box.add_theme_constant_override("separation",10);_content.add_child(_preview_box)
	_model_title=Label.new();_model_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_model_title.add_theme_color_override("font_color",Color("637057"));_model_title.add_theme_font_size_override("font_size",13);_preview_box.add_child(_model_title)
	_preview=WikiPreview.new();_preview.size_flags_vertical=Control.SIZE_EXPAND_FILL;_preview.article_requested.connect(func(key):navigate(key));_preview_box.add_child(_preview)
	_map_filters=HFlowContainer.new();_preview_box.add_child(_map_filters)
	for pair: Array in [["exit","Exits"],["quest","Quest areas"],["inhabitant","Creatures"]]:
		var check := CheckButton.new();check.text=RemakeText.t(pair[1]);check.button_pressed=_map_kinds[pair[0]];check.tooltip_text=RemakeText.t("Show authored map markers. Quest and creature positions may reveal spoilers.");check.toggled.connect(func(on):_map_kinds[pair[0]]=on;_preview.set_pins(_map_pins.filter(func(pin):return _map_kinds.get(pin.kind,false))));_map_filters.add_child(check)
	var controls := HBoxContainer.new();controls.alignment=BoxContainer.ALIGNMENT_CENTER;_preview_box.add_child(controls)
	_rotate_buttons.append(_button(controls,"",func():_preview.turn_by(-PI/6),RemakeText.t("Rotate left")));_rotate_buttons.append(_button(controls,"",func():_preview.turn_by(PI/6),RemakeText.t("Rotate right")))
	_rotate_buttons[0].icon=load("res://icons/wiki/turn-left.svg");_rotate_buttons[1].icon=load("res://icons/wiki/turn-right.svg")
	_button(controls,"+",func():_preview.zoom_by(.9),RemakeText.t("Zoom in"));_button(controls,"−",func():_preview.zoom_by(1.1),RemakeText.t("Zoom out"));_button(controls,RemakeText.t("Reset view"),_preview.reset_view)
	_unavailable=Label.new();_unavailable.text=RemakeText.t("This game data has no model for this entry.");_unavailable.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_preview_box.add_child(_unavailable)
	_representative=Label.new();_representative.text=RemakeText.t("Authored appearance; this material has no separate texture.");_representative.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_preview_box.add_child(_representative)
	_builder_scroll=ScrollContainer.new();_builder_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_builder_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;article_column.add_child(_builder_scroll)
	var workshop := PanelContainer.new();workshop.size_flags_horizontal=Control.SIZE_EXPAND_FILL;workshop.theme=WikiWorkbench.workshop_theme(_paper_theme());workshop.add_theme_stylebox_override("panel",StyleBoxEmpty.new());_builder_scroll.add_child(workshop)
	_builder=VBoxContainer.new();_builder.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_builder.add_theme_constant_override("separation",12);workshop.add_child(_builder)
	_item_spells=ScrollOptionButton.new();_item_spells.fit_to_longest_item=false;_item_spells.clip_text=true;_item_spells.tooltip_text=RemakeText.t("Choose a spell to preview on this item.");_item_spells.item_selected.connect(func(_index):_source.read(_choose_item_spell));_builder.add_child(_item_spells)
	_runes=ScrollOptionButton.new();_runes.fit_to_longest_item=false;_runes.clip_text=true;_runes.tooltip_text=RemakeText.t("Choose a compatible rune to calculate a spell variant.");_runes.item_selected.connect(func(_index):_source.read(_show_rune_art));_builder.add_child(_runes)
	_runes.hide()
	_rune_families=HFlowContainer.new();_rune_families.add_theme_constant_override("h_separation",4);_builder.add_child(_rune_families)
	_rune_palette=HFlowContainer.new();_rune_palette.add_theme_constant_override("h_separation",8);_rune_palette.add_theme_constant_override("v_separation",8);_builder.add_child(_rune_palette)
	_assembly=BoxContainer.new();_assembly.add_theme_constant_override("separation",24);_builder.add_child(_assembly)
	_workbench=WikiWorkbench.new();_workbench.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_workbench.rune_removed.connect(func(index):_source.read(func():_remove_rune_at(index)));_assembly.add_child(_workbench)
	_assembly_values=RichTextLabel.new();_assembly_values.bbcode_enabled=true;_assembly_values.fit_content=true;_assembly_values.scroll_active=false;_assembly_values.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_assembly_values.custom_minimum_size.x=180;_assembly.add_child(_assembly_values)
	_camp_constructor=WikiCampConstructor.new();_camp_constructor.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_builder.add_child(_camp_constructor)
	_camp_constructor.rune_chosen.connect(func(code):_source.read(func():
		for i in _runes.item_count:
			if _runes.get_item_metadata(i)==code:_runes.select(i);_add_selected_rune();break))
	_camp_constructor.item_chosen.connect(func(id):navigate(current,false,id))
	_camp_constructor.spell_chosen.connect(func(code):
		if catalog.entries[current].kind=="spell":navigate(_source.read(func():return catalog.add_variant(code)))
		else:_source.read(func():_draft_item_spell=code;_fill_runes(code);_item_draft_status()))
	_rune_preview=WikiPreview.new();_rune_preview.custom_minimum_size=Vector2(60,64);_builder.add_child(_rune_preview);_rune_preview.hide()
	var rune_actions := HFlowContainer.new();_builder.add_child(rune_actions)
	_add_rune=_button(rune_actions,RemakeText.t("Add rune"),_with_rune);_remove_rune=_button(rune_actions,RemakeText.t("Remove last rune"),func():_source.read(_remove_last_rune));_reset_spell=_button(rune_actions,RemakeText.t("Reset spell"),_without_runes);_add_rune.hide();_remove_rune.hide()
	_apply_item_button=_button(_builder,RemakeText.t("Preview enchanted item"),func():_source.read(_apply_item_spell))
	_builder_status=Label.new();_builder_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_builder_status.add_theme_font_size_override("font_size",13);_builder.add_child(_builder_status)
	resized.connect(_layout);get_viewport().size_changed.connect(_layout);_layout()


func _paper_theme() -> Theme:
	var result := theme.duplicate() as Theme
	for type: String in ["Label","Button","OptionButton","CheckButton","LineEdit","SpinBox"]:
		result.set_color("font_color",type,Color("2d392b"));result.set_color("font_hover_color",type,Color("1b301f"));result.set_color("font_pressed_color",type,Color("1b301f"));result.set_color("font_focus_color",type,Color("1b301f"));result.set_color("font_disabled_color",type,Color("75806a"))
	result.set_constant("modulate_arrow","OptionButton",1)
	result.set_constant("arrow_margin","OptionButton",14)
	result.set_color("font_placeholder_color","LineEdit",Color("65715a"))
	for prefix: String in ["up","down"]:
		for state: String in ["","_hover","_pressed","_disabled"]:result.set_color(prefix+state+"_icon_modulate","SpinBox",Color("5c6c4d"))
	result.set_color("default_color","RichTextLabel",Color("2d392b"));result.set_color("table_odd_row_bg","RichTextLabel",Color("e7e6d7"));result.set_color("table_even_row_bg","RichTextLabel",Color("eeecdf"));result.set_color("font_selected_color","RichTextLabel",Color("203522"));result.set_color("selection_color","RichTextLabel",Color("cdd9b7"));result.set_font("bold_font","RichTextLabel",load("res://fonts/LiberationSans-Bold.ttf"))
	result.set_constant("table_h_separation","RichTextLabel",12);result.set_constant("table_v_separation","RichTextLabel",3)
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new();style.bg_color=Color("d6dfc4") if state in ["pressed","hover"] else Color("f6f1e6");style.border_color=Color("7b886a") if state in ["focus","pressed"] else Color("bac2a8");style.set_border_width_all(1);style.set_corner_radius_all(4);style.set_content_margin_all(8)
		for type: String in ["Button","OptionButton","LineEdit"]:result.set_stylebox(state,type,style)
	return result

func _dialog_theme() -> Theme:
	var result := _paper_theme()
	result.default_font_size=16
	for type: String in ["Label","Button","OptionButton","LineEdit","PopupMenu"]:result.set_font_size("font_size",type,16)
	result.set_font_size("title_font_size","Window",22)
	result.set_color("title_color","Window",Color("eee5c9"))
	var panel := StyleBoxFlat.new();panel.bg_color=Color("f1ebdc");panel.set_content_margin_all(18);result.set_stylebox("panel","AcceptDialog",panel)
	var border := StyleBoxFlat.new();border.bg_color=Color("24382b");border.set_border_width_all(1);border.border_color=Color("828568");border.expand_margin_top=30;result.set_stylebox("embedded_border","Window",border)
	return result


func open(rules: Dictionary = {}) -> void:
	# Rebuild even when a mod patches the database in place. Indexing has no
	# model loads, and takes only a few frames for the original campaigns.
	WikiCampArt._cache.clear();_workbench._current="";_camp_constructor._identity=""
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
	if _sidebar.visible:_query.grab_focus()
	else:_browse_toggle.grab_focus()


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
		_results.add_item(entry.title+"\n"+String(catalog.knowledge.subtitles.get(key,RemakeText.t(entry.category))),entry.kind)
		_results.set_item_metadata(_results.item_count - 1, key)
		_results.set_item_tooltip(_results.item_count - 1, entry.title + " · " + RemakeText.t(entry.category))
		if key == current: _results.select(_results.item_count - 1)
	_status.text = RemakeText.t("%d pages") % _matches.size()
	if _matches.is_empty(): _status.text = RemakeText.t("No matching pages")
	_status.tooltip_text = _status.text


func navigate(key: String, remember := true, variant := "") -> void:
	_narrow_browsing=false
	_narrow_preview=false
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
	if key.uri_decode().get_slice("{",0)!=_craft_key:_craft_slot=""
	_add_plan.text=RemakeText.t("Craft and equip") if _craft_slot else RemakeText.t("Add to plan")
	if variant.is_empty(): variant = String(_selected_versions.get(key, ""))
	var page := catalog.page(key, variant)
	_selected_versions[key] = page.get("variant", "")
	if _history_at >= 0 and _history[_history_at].key == key:
		_history[_history_at].variant = page.get("variant", "")
	_fill_versions(key, page.get("variant", ""))
	_base_html = page.html
	_guide = page.guide
	_guide_button.visible = not _guide.is_empty()
	_guide_button.set_pressed_no_signal(true)
	html = _base_html.replace("</article>",WikiCatalog.heading(RemakeText.t("Quest hints"))+_guide+"</article>") if _guide else _base_html
	_action_status.text="";_action_status.hide()
	_planner.visible=key=="mechanics/planning"
	_import_text.hide()
	_import_toggle.visible=_planner.visible
	_home_view.visible=key=="home"
	_article.visible=not _planner.visible and not _home_view.visible
	_page_title.visible=not _home_view.visible
	_page_subtitle.visible=not _home_view.visible and not _planner.visible
	_actions.visible=not _home_view.visible
	_page_title.text=catalog.display_item_title(page.variant) if catalog.entries[key].kind=="item" else String(catalog.entries[key].title)
	_page_subtitle.text=page.subtitle
	if _home_view.visible:_home_view.setup(catalog)
	_add_plan.visible=catalog.entries[key].kind in ["item","spell"] and not String(page.variant).begins_with("bp:")
	_save_creation.visible=_add_plan.visible or _planner.visible
	if _planner.visible:
		var plan: Dictionary=_plan_by_campaign.get_or_add(_source.campaign,WikiPlan.blank(_source.campaign))
		_planner.setup(plan,catalog,_source)
	_render_article()
	_article.scroll_to_line(0)
	_page_revision += 1
	_has_preview = not page.preview.is_empty()
	_preview_box.visible = _has_preview
	var available := _preview.show_model(page.preview)
	var is_map: bool = page.preview.get("kind", "") == "map"
	_map_filters.visible=is_map
	_map_pins=page.pins
	_preview.set_pins(_map_pins.filter(func(pin): return _map_kinds.get(pin.kind,false)))
	_model_title.text = RemakeText.t("Map overview") if is_map else RemakeText.t("3D preview")
	_preview.tooltip_text = RemakeText.t("Drag to pan. Scroll to zoom.") if is_map else RemakeText.t("Drag to rotate. Scroll to zoom. The buttons also work with touch and a controller.")
	for button: Button in _rotate_buttons: button.visible = not is_map
	_unavailable.visible = not available
	_representative.visible = available and page.preview.get("representative", false)
	var is_spell: bool = catalog.entries[key].kind == "spell"
	var is_item := catalog.craftable(key) and not String(page.get("variant", "")).begins_with("bp:")
	_builder.visible = is_spell or is_item
	_workbench_toggle.visible=_builder.visible
	if not _builder.visible:_workbench_open=false
	_builder_scroll.visible = _builder.visible and _workbench_open
	_item_spells.visible = is_item
	_apply_item_button.visible = is_item
	_builder_status.text = ""
	if is_spell:
		_fill_runes(catalog.entries[key].value)
	elif is_item:
		if key != _draft_item_key or not Items.spell_of(page.variant).is_empty():
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
		_narrow_browsing=true
		_layout()
	elif not key.is_empty():
		var variant := destination.get_slice("?version=", 1).uri_decode() if "?version=" in destination else ""
		navigate(key, true, variant)


func _fill_versions(key: String, selected: String) -> void:
	_versions.clear()
	var choices := catalog.variants_for(key)
	_version_block.visible = choices.size() > 1
	if choices.size() <= 1: return
	for id: String in choices:
		var label := RemakeText.t("Blueprint") if id.begins_with("bp:") else catalog.display_item_title(id)
		var info := Items.info(id)
		if not id.begins_with("bp:") and not info.mat.is_empty():label=WikiCatalog.item_title(Items.material_unit(info.material))
		_versions.add_item(label);_versions.set_item_metadata(_versions.item_count-1,id)
		if id == Items.plain(selected):_versions.select(_versions.item_count-1)


func _fill_runes(spell: String) -> void:
	var selected := String(_runes.get_item_metadata(_runes.selected)) if _runes.selected >= 0 and not _runes.disabled else ""
	_runes.clear()
	var allowed := []
	for row: Dictionary in GameData.db.table("spell_modifiers"):
		var code := String(row.get("code", "")).to_lower()
		if not spell.is_empty() and WikiCatalog.rune_listed(code) and WikiCatalog.rune_fits(spell, code): allowed.append(code)
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
	_refresh_workbench(spell)


func _show_rune_art() -> void:
	_rune_preview.clear()
	if _runes.disabled or _runes.selected < 0: return
	var code := String(_runes.get_item_metadata(_runes.selected))
	_rune_preview.show_model({"kind":"item","value":"rune:"+code})
	_rune_preview.tooltip_text = WikiCatalog.rune_title(code)


func _fill_item_spells() -> void:
	_item_spells.clear();_item_spells.add_item(RemakeText.t("No enchantment"));_item_spells.set_item_metadata(0,"")
	for key: String in catalog.search("", "Spells"):
		var spell := String(catalog.entries[key].value)
		_item_spells.add_item(WikiCatalog.spell_title(spell))
		_item_spells.set_item_metadata(_item_spells.item_count - 1,spell)
		if spell == _draft_item_spell.get_slice("{",0): _item_spells.select(_item_spells.item_count - 1)
	_fill_runes(_draft_item_spell)
	_item_draft_status()


func _choose_item_spell() -> void:
	_draft_item_spell = String(_item_spells.get_item_metadata(_item_spells.selected))
	_fill_runes(_draft_item_spell)
	_item_draft_status()


func _item_draft_status() -> void:
	var item := Items.plain(String(_selected_versions.get(current,"")))
	_apply_item_button.visible=not _draft_item_spell.is_empty()
	_apply_item_button.disabled = _draft_item_spell.is_empty() or not Items.can_enchant(item,_draft_item_spell)
	_refresh_workbench(_draft_item_spell)
	if _draft_item_spell.is_empty():_builder_status.text="";return
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
	_remove_rune_at(Spells.mods_of(spell).size()-1)


func _remove_rune_at(index: int) -> void:
	var is_item: bool = catalog.entries[current].kind == "item"
	var spell := _draft_item_spell if is_item else String(catalog.entries[current].value)
	var runes := Spells.mods_of(spell)
	if index<0 or index>=runes.size():return
	runes.remove_at(index)
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
	# Base breakpoints on the available viewport, not a container minimum that
	# can still carry the previous wide layout after the window is resized.
	var available := get_viewport_rect().size-Vector2(28,28)
	var scale := clampf(available.y / 900.0, 0.85, 3.0)
	if not is_equal_approx(scale, _ui_scale):
		_ui_scale = scale
		theme.default_font_size = roundi(18 * scale)
		_title.add_theme_font_size_override("font_size", roundi(28 * scale))
		_page_title.add_theme_font_size_override("font_size",roundi(36*scale))
		_results.add_theme_font_size_override("font_size", roundi(17 * scale))
		_status.add_theme_font_size_override("font_size", roundi(14 * scale))
		_article.add_theme_font_size_override("normal_font_size", roundi(20 * scale))
		_article.add_theme_font_size_override("bold_font_size", roundi(20 * scale))
		for button: Node in find_children("*", "Button", true, false):
			if not button.get_meta("map_pin",false) and not button.get_meta("equipment_slot",false) and not button.get_meta("workbench_slot",false):button.custom_minimum_size.y = roundi((65 if button.get_meta("wiki_result",false) else 34)*scale)
		if not html.is_empty(): _render_article()
	var narrow := available.x / scale < 850
	_compact_controls.visible=narrow
	var crafting := _workbench_open or _planner.visible
	_sidebar.visible=(not narrow or _narrow_browsing) and not (crafting and not narrow)
	var paper := _reading_surface.get_theme_stylebox("panel") as StyleBoxFlat
	paper.bg_color=Color("090d09") if crafting else Color("f1ebdc")
	paper.set_content_margin_all(12 if crafting else 26)
	_reading_surface.theme=WikiCampArt.theme(_paper_theme()) if crafting else _paper_theme()
	_page_title.visible=not _home_view.visible and not crafting
	_title.text=RemakeText.t("Build planner") if _planner.visible else _page_title.text if _workbench_open else "Cursed Lands · "+RemakeText.t("Game wiki")
	_reading_surface.visible=not narrow or not _narrow_browsing
	_browse_toggle.text=RemakeText.t("Return to article") if _narrow_browsing else RemakeText.t("Browse and search")
	_preview_toggle.visible=narrow and _has_preview and not _narrow_browsing and not _workbench_open
	_preview_toggle.text=RemakeText.t("Hide illustration") if _narrow_preview else RemakeText.t("Show illustration")
	_preview_box.visible=_has_preview and (not narrow or _narrow_preview) and not _workbench_open
	_article_column.visible=_workbench_open or not (narrow and _narrow_preview and _has_preview)
	_builder_scroll.visible=_builder.visible and _workbench_open
	_version_block.visible=_versions.item_count>1 and not _workbench_open
	_article.visible=not _planner.visible and not _home_view.visible and not _workbench_open
	_page_subtitle.visible=not _home_view.visible and not _planner.visible and not _workbench_open
	_workbench_toggle.text=RemakeText.t("Return to article") if _workbench_open else RemakeText.t("Open constructor")
	_assembly.vertical=available.x<1080
	_workbench.custom_minimum_size.x=0
	_workbench.size_flags_horizontal=Control.SIZE_EXPAND_FILL if _assembly.vertical else Control.SIZE_FILL
	_model_title.text=_page_title.text if narrow and _narrow_preview else RemakeText.t("Map overview") if _map_filters.visible else RemakeText.t("3D preview")
	if not crafting:_title.text=RemakeText.t("Game wiki") if narrow else "Cursed Lands · "+RemakeText.t("Game wiki")
	var short := available.y / scale < 600
	_body.vertical = narrow
	_sidebar.custom_minimum_size = Vector2(0, (95 if short else 150) * scale) if narrow else Vector2(clampf(size.x * 0.23, 190 * scale, 290 * scale), 0)
	_sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	_sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.vertical = narrow
	_preview_box.custom_minimum_size = Vector2(0, (145 if short else 210) * scale) if _content.vertical else Vector2(clampf(size.x * (0.36 if _map_filters.visible else 0.22), 170 * scale, (490 if _map_filters.visible else 290) * scale), 0)
	_preview.custom_minimum_size = Vector2(100, (70 if short else 120) * scale)
	_builder_scroll.custom_minimum_size.y = 100 * scale
	_rune_preview.custom_minimum_size = Vector2(60,72) * scale


func _input(event: InputEvent) -> void:
	# LineEdit consumes Escape during GUI dispatch. Handle the modal's close
	# before that dispatch, while letting an open choice popup close first.
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode != KEY_ESCAPE: return
	for child in get_children():
		if child is Window and child.visible:return
	if _category.get_popup().visible or _subcategory.get_popup().visible or _runes.get_popup().visible or _versions.get_popup().visible: return
	if is_instance_valid(_preview._pin_popup) and _preview._pin_popup.visible: return
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
		if control.is_visible_in_tree() and not control.disabled and not control.get_meta("wiki_result",false):
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


func _toggle_guide() -> void:
	html=_base_html
	if _guide_button.button_pressed: html=html.replace("</article>",WikiCatalog.heading(RemakeText.t("Quest hints"))+_guide+"</article>")
	_render_article()

func _craft_equipment(key: String,variant: String,slot: String) -> void:
	_draft_item_key=""
	navigate(key,true,variant)
	_craft_slot=slot;_craft_key=key.uri_decode().get_slice("{",0)
	_workbench_open=true;_add_plan.text=RemakeText.t("Craft and equip");_layout()

func _add_current_to_plan() -> void:
	_action_status.show()
	var plan: Dictionary=_plan_by_campaign.get_or_add(_source.campaign,WikiPlan.blank(_source.campaign))
	if plan.entries.size()>=WikiPlan.LIMIT: _action_status.text=RemakeText.t("A plan can contain up to 32 entries."); return
	var entry: Dictionary=catalog.entries[current]
	var variant := String(_selected_versions.get(current,""))
	if entry.kind=="item" and _workbench_open and _draft_item_spell:
		variant=catalog.construct_item(current,Items.plain(variant),_draft_item_spell)
		if variant.is_empty():_action_status.text=RemakeText.t("The spell must fit the item's complexity and energy limits. Weapons and armour also need a triggered or continuous item rune.");return
	var magic := String(entry.value) if entry.kind=="spell" else Items.spell_of(variant)
	var key := "spell/"+magic.get_slice("{",0).uri_encode() if entry.kind=="spell" else current
	var row := {"key":key,"variant":Items.plain(variant),"spell":magic.get_slice("{",0),"runes":Array(Spells.mods_of(magic)),"count":1}
	WikiPlan.auto_slot(plan,row,catalog);plan.entries.append(row)
	if _craft_slot:
		WikiPlan.assign_slot(plan,plan.entries.size()-1,_craft_slot,catalog)
		_navigate("mechanics/planning",true,"")
	_action_status.text=RemakeText.t("Added to your build plan.")

func _copy_link() -> void:
	_action_status.show()
	var url := ""
	if current=="mechanics/planning": url=WikiPlan.url(_plan_by_campaign[_source.campaign],RemakeText.lang)
	else:
		var entry: Dictionary=catalog.entries[current]
		var key := "spell/"+String(entry.value).get_slice("{",0).uri_encode() if entry.kind=="spell" else current
		url="https://cursedlands.wwworm.com/wiki/?lang="+RemakeText.lang+"&campaign="+_source.campaign+"&page="+key.uri_encode()
		var variant := String(_selected_versions.get(current,""))
		if variant: url+="&version="+Items.plain(variant).uri_encode()
		var magic := String(entry.value) if entry.kind=="spell" else (_draft_item_spell if _workbench_open else Items.spell_of(variant))
		if magic: url+="&spell="+magic.get_slice("{",0).uri_encode()+"&runes="+";".join(Spells.mods_of(magic)).uri_encode()
		if _workbench_open:url+="&craft=1"
	DisplayServer.clipboard_set(url)
	_action_status.text=RemakeText.t("Link copied. Website values use the published game data.")

func _creation_snapshot() -> Dictionary:
	if current=="mechanics/planning":return {"type":"character","name":RemakeText.t("Character build"),"plan":_plan_by_campaign[_source.campaign].duplicate(true)}
	var entry: Dictionary=catalog.entries[current]
	if not entry.kind in ["item","spell"]:return {}
	var variant := String(_selected_versions.get(current,""))
	var magic := String(entry.value) if entry.kind=="spell" else (_draft_item_spell if _workbench_open else Items.spell_of(variant))
	var row := {"key":"spell/"+magic.get_slice("{",0).uri_encode() if entry.kind=="spell" else current,"variant":Items.plain(variant),"spell":magic.get_slice("{",0),"runes":Array(Spells.mods_of(magic)),"count":1,"slot":""}
	var plan := WikiPlan.blank(_source.campaign);plan.entries.append(row)
	var result := WikiPlan.totals(plan,catalog)
	if not result.rows[0].valid:return {}
	return {"type":entry.kind,"name":result.rows[0].title,"plan":plan}

func _save_current_creation() -> void:
	var snapshot := _creation_snapshot()
	if snapshot.is_empty():_action_status.show();_action_status.text=RemakeText.t("This creation is invalid and cannot be saved.");return
	var dialog := ConfirmationDialog.new();dialog.name="WikiSaveCreation";dialog.title=RemakeText.t("Save locally");dialog.dialog_hide_on_ok=false;dialog.theme=_dialog_theme();add_child(dialog)
	dialog.get_ok_button().text=RemakeText.t("Save locally");dialog.get_cancel_button().text=RemakeText.t("Cancel")
	var body := VBoxContainer.new();body.add_theme_constant_override("separation",12);dialog.add_child(body)
	var label := Label.new();label.text=RemakeText.t("Name");body.add_child(label)
	var name_input := LineEdit.new();name_input.max_length=120;name_input.text=String(snapshot.name).left(120);body.add_child(name_input)
	var help := Label.new();help.text=RemakeText.t("Saved on this device, separately from your game saves. Copy a link to keep a backup.");help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(help)
	var status := Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(status)
	dialog.confirmed.connect(func():
		if name_input.text.strip_edges().is_empty():status.text=RemakeText.t("Enter a name for this creation.");return
		var result := WikiLibrary.save(name_input.text.strip_edges(),snapshot.type,snapshot.plan)
		if result.error:status.text=RemakeText.t(result.error);return
		_action_status.show();_action_status.text=RemakeText.t("Saved on this device. Find it in Saved creations.");dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_clamped(Vector2i(480,260));name_input.grab_focus();name_input.select_all()

func _open_library() -> void:
	if not is_instance_valid(_library_view):
		_library_view=WikiLibraryView.new();_library_view.theme=_dialog_theme();add_child(_library_view)
		_library_view.creation_opened.connect(func(record):_load_creation(record,false))
		_library_view.creation_added.connect(func(record):_load_creation(record,true))
	_library_view.refresh();_library_view.popup_centered_clamped(Vector2i(760,600))

func _load_creation(record: Dictionary,add_to_plan: bool) -> void:
	var plan: Dictionary=record.plan.duplicate(true)
	if plan.campaign!=_source.campaign:
		if plan.campaign!=GameData.campaign_id and not GameData.campaign_roots.has(plan.campaign):
			_library_view._status.text=RemakeText.t("Install this campaign through Game files to browse its wiki.");return
		_select_campaign(plan.campaign)
	if record.type=="character":_plan_by_campaign[plan.campaign]=plan;navigate("mechanics/planning")
	elif add_to_plan:
		var current_plan: Dictionary=_plan_by_campaign.get_or_add(plan.campaign,WikiPlan.blank(plan.campaign))
		if current_plan.entries.size()>=WikiPlan.LIMIT:_library_view._status.text=RemakeText.t("A plan can contain up to 32 entries.");return
		current_plan.entries.append(plan.entries[0]);navigate("mechanics/planning")
	else:
		var row: Dictionary=plan.entries[0]
		var valid: bool=_source.read(func():return WikiPlan.totals(plan,catalog).rows[0].valid)
		if not valid:_library_view._status.text=RemakeText.t("Unavailable in this campaign or incompatible combination.");return
		var magic := WikiPlan.spell(row)
		var key: String=_source.read(func():return catalog.add_variant(magic)) if record.type=="spell" else row.key
		var variant: String=row.variant+("|"+magic if record.type=="item" and magic else "")
		_draft_item_key="";navigate(key,true,variant);_workbench_open=true;_layout()
	_library_view.hide()

func _import_plan(text: String) -> void:
	_action_status.show()
	var plan := WikiPlan.decode(text)
	if plan.is_empty(): _action_status.text=RemakeText.t("This build link is invalid or uses an unsupported version."); return
	if plan.campaign!=_source.campaign:
		if plan.campaign!=GameData.campaign_id and not GameData.campaign_roots.has(plan.campaign):
			_action_status.text=RemakeText.t("Install this campaign through Game files to browse its wiki."); return
		_select_campaign(plan.campaign)
	_plan_by_campaign[plan.campaign]=plan
	navigate("mechanics/planning")
	_import_text.clear()


func _render_article() -> void:
	var body := RegEx.create_from_string("<h1>.*?</h1>").sub(html,"",true)
	_article.text=WikiHtml.to_bbcode(body,_ui_scale)


func _refresh_workbench(spell: String) -> void:
	if not is_instance_valid(_workbench):return
	var is_item: bool=catalog.entries[current].kind=="item"
	var item := Items.plain(String(_selected_versions.get(current,""))) if is_item else ""
	_camp_constructor.setup(spell,item,catalog,_workbench)
	_assembly.hide();_rune_families.hide();_rune_palette.hide();_item_spells.hide()
	for child in _rune_families.get_children():_rune_families.remove_child(child);child.queue_free()
	for family: Array in [["e","Power"],["m","Stamina cost"],["d","Duration"],["r","Range"],["a","Area"],["t","Targets"],["f","Target filter"],["i","Special"]]:
		var tab := Button.new();tab.text=RemakeText.t(family[1]);tab.add_theme_font_size_override("font_size",14);tab.toggle_mode=true;tab.button_pressed=_rune_group==family[0]
		tab.pressed.connect(func():_rune_group=family[0];_source.read(func():_refresh_workbench(spell)))
		_rune_families.add_child(tab)
	for child in _rune_palette.get_children():_rune_palette.remove_child(child);child.queue_free()
	for i in _runes.item_count:
		if _runes.disabled:break
		var code := String(_runes.get_item_metadata(i))
		if not code.begins_with(_rune_group):continue
		var button := Button.new();button.text=WikiCatalog.rune_title(code);button.icon=WikiWorkbench.piece_icon("rune:"+code);button.expand_icon=true;button.custom_minimum_size=Vector2(44,44);button.add_theme_font_size_override("font_size",14);button.add_theme_constant_override("icon_max_width",32);button.tooltip_text=RemakeText.t("Add rune")+": "+WikiCatalog.rune_title(code)
		button.pressed.connect(func():_runes.select(i);_with_rune());_rune_palette.add_child(button)
	var parsed := Spells.parse(spell)
	var rows := []
	for field: Array in [["effect","Power"],["mana","Stamina cost"],["complex","Complexity"],["range","Range"],["duration","Duration (ticks)"],["targets","Targets"]]:rows.append([WikiCatalog.esc(RemakeText.t(field[1])),WikiCatalog.num(parsed.get(field[0],0))])
	if item:
		for value_row: Array in [["Weight",Items.weight(item)],["Rune slots",Items.slots(item)],["Charge capacity",Items.energy(item)],["Components",Items.components("bp:"+String(Items.info(item).base))]]:rows.append([WikiCatalog.esc(RemakeText.t(value_row[0])),WikiCatalog.num(value_row[1])])
	_assembly_values.text=WikiHtml.to_bbcode("<article>"+WikiCatalog.heading(catalog.display_item_title(item) if item else WikiCatalog.spell_title(spell))+WikiCatalog.paragraph(RemakeText.t("Runes: %s / 8") % Spells.mods_of(spell).size())+WikiCatalog.table_html([RemakeText.t("Property"),RemakeText.t("Value")],rows)+"</article>")

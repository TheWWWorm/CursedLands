class_name WikiHome
extends ScrollContainer
signal article_requested(key: String)
signal category_requested(category: String)
var _body: VBoxContainer
var _spread: BoxContainer
var _routes: VBoxContainer
var _guide_rows: Array[BoxContainer] = []

func setup(catalog: WikiCatalog) -> void:
	_guide_rows.clear()
	for child in get_children():remove_child(child);child.queue_free()
	horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_body=VBoxContainer.new();_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_body.add_theme_constant_override("separation",18);add_child(_body)
	var heading := Label.new();heading.text=RemakeText.t("Your field guide");heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;heading.add_theme_font_override("font",Interface800.font());heading.add_theme_font_size_override("font_size",46);_body.add_child(heading)
	var intro := Label.new();intro.text=RemakeText.t("Find the right equipment, understand the rules and prepare for what lies ahead.");intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;intro.add_theme_font_size_override("font_size",19);intro.add_theme_color_override("font_color",Color("5c6852"));_body.add_child(intro)
	_spread=BoxContainer.new();_spread.add_theme_constant_override("separation",28);_body.add_child(_spread)
	_routes=VBoxContainer.new();_routes.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_routes.add_theme_constant_override("separation",20);_spread.add_child(_routes)
	var sword := ""
	for key: String in catalog.search("","Items","weapon_sword"):
		if catalog.craftable(key):sword=key;break
	var magic: String=catalog.search("","Spells")[0]
	_route(catalog,_routes,sword,"Items","Find equipment","Compare materials, find possible sources and plan a craft.")
	_route(catalog,_routes,magic,"Spells","Build a spell","Combine runes and check the finished spell requirements.")
	var map_key := "map/gz1g"
	if not catalog.entries.has(map_key):map_key=catalog.search("","Maps")[0]
	var map_box := VBoxContainer.new();map_box.custom_minimum_size.x=240;map_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_spread.add_child(map_box)
	var page := catalog.page(map_key)
	if not page.preview.is_empty():
		var preview := WikiPreview.new();preview.custom_minimum_size=Vector2(200,235);map_box.add_child(preview);preview.show_model(page.preview)
	var map_button := Button.new();map_button.text=RemakeText.t("Explore the maps");map_button.pressed.connect(func():category_requested.emit("Maps"));map_box.add_child(map_button)
	var map_note := Label.new();map_note.text=RemakeText.t("Find exits, creatures and quest areas on the original maps.");map_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;map_note.add_theme_font_size_override("font_size",14);map_box.add_child(map_note)
	var separator := HSeparator.new();_body.add_child(separator)
	for row: Array in [["category/Getting started","Getting started","Short lessons, controls and the full tutorial reference."],["guide/recent","Recent hints","Revisit hints encountered in this campaign."],["category/Characters","Meet the characters","Read biographies and follow the events that connect the cast."],["category/Allods","Discover the allods","Explore the islands, their settlements and their place in the story."],["mechanics/planning","Build planner","Plan equipment, training and materials. Keep the entire build in a shareable link."],["category/Quests","Follow a quest","Read objectives, hints, locations and authored rewards."],["mechanics/armor","Understand combat","Practical answers about damage, protection and accuracy."],["cut/overview","Cut content","Models, colours, creatures and equipment that exist in the data but not in the campaign."]]:
		var line := BoxContainer.new();line.add_theme_constant_override("separation",24);_body.add_child(line);_guide_rows.append(line)
		var button := Button.new();button.text=RemakeText.t(row[1]);button.icon=load("res://icons/wiki/quest.svg") if row[0]=="category/Quests" else null;button.expand_icon=true;button.add_theme_constant_override("icon_max_width",32);button.custom_minimum_size.x=210;line.add_child(button)
		button.pressed.connect(func():
			if row[0].begins_with("category/"):category_requested.emit(row[0].trim_prefix("category/"))
			else:article_requested.emit(row[0]))
		var note := Label.new();note.text=RemakeText.t(row[2]);note.size_flags_horizontal=Control.SIZE_EXPAND_FILL;note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.add_theme_font_size_override("font_size",14);line.add_child(note)
	_layout()
	if not resized.is_connected(_layout):resized.connect(_layout)

func _route(catalog: WikiCatalog, parent: Control, key: String, category: String, title: String, description: String) -> void:
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",18);parent.add_child(row)
	if key:
		var preview := WikiPreview.new();preview.custom_minimum_size=Vector2(112,133);row.add_child(preview);preview.show_model(catalog.page(key).preview)
	var text := VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;text.add_theme_constant_override("separation",10);row.add_child(text)
	var button := Button.new();button.text=RemakeText.t(title);button.add_theme_font_override("font",Interface800.font());button.add_theme_font_size_override("font_size",25);button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func():category_requested.emit(category));text.add_child(button)
	var note := Label.new();note.text=RemakeText.t(description);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.add_theme_font_size_override("font_size",14);text.add_child(note)

func _layout() -> void:
	if _spread:_spread.vertical=size.x<650
	for row: BoxContainer in _guide_rows:row.vertical=size.x<650

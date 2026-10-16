class_name WikiPlanner
extends ScrollContainer
signal changed
signal article_requested(key: String, variant: String)
signal craft_requested(key: String, variant: String, slot: String)
var plan := {}
var catalog: WikiCatalog
var source: WikiSource
var _body: VBoxContainer
var _summary: RichTextLabel
var _grid: GridContainer
var _training: VBoxContainer
var _rows: VBoxContainer
var _columns: BoxContainer
var _equipment: WikiEquipment
var _picker: VBoxContainer
var _picker_query: LineEdit
var _picker_items: ScrollOptionButton
var _picker_versions: ScrollOptionButton
var _picker_apply: Button
var _picker_craft: Button
var _picker_saved_index := -1
var _picker_record := {}
var _selector_frame: PanelContainer
var _picker_placeholder: Label
var _pools: Label
var _training_cost: Label
var _picked_slot := ""
var _picker_key := ""

func setup(value: Dictionary, reference: WikiCatalog, context: WikiSource) -> void:
	plan=value; catalog=reference; source=context
	for child in get_children(): remove_child(child); child.queue_free()
	horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_body=VBoxContainer.new(); _body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation",14); add_child(_body)
	var help := Label.new();help.text=RemakeText.t("Choose an equipment slot to build your loadout. Adjust attributes and skills beside it.");help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.add_theme_font_size_override("font_size",14);_body.add_child(help)
	var workshop := PanelContainer.new();workshop.size_flags_horizontal=Control.SIZE_EXPAND_FILL;workshop.theme=WikiCampArt.theme(_inherited_theme());workshop.add_theme_stylebox_override("panel",StyleBoxEmpty.new());_body.add_child(workshop)
	_columns=BoxContainer.new();_columns.add_theme_constant_override("separation",0);workshop.add_child(_columns)
	_training=VBoxContainer.new();_training.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_training.size_flags_stretch_ratio=0.8;_training.add_theme_constant_override("separation",12);_columns.add_child(_training)
	_section(_training,"Character")
	var grid := GridContainer.new();_grid=grid;grid.columns=2;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);_training.add_child(grid)
	for field: Array in [["strength","Strength"],["dexterity","Dexterity"],["intelligence","Intelligence"],["experience","Earned experience"]]:
		_number(grid,field[0],RemakeText.t(field[1]),plan,1000000000 if field[0]=="experience" else 100,0 if field[0]=="experience" else 1)
	var skill_box := VBoxContainer.new();skill_box.add_theme_constant_override("separation",12);_section(skill_box,"Skills")
	var skill_grid := GridContainer.new();skill_grid.columns=2;skill_grid.add_theme_constant_override("h_separation",8);skill_grid.add_theme_constant_override("v_separation",8);skill_box.add_child(skill_grid)
	for skill: String in Skills.LIST:_number(skill_grid,skill,source.read(func():return Skills.title(skill)),plan.skills,100,0)
	_equipment=WikiEquipment.new();_equipment.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_equipment.size_flags_stretch_ratio=1.2;_equipment.slot_requested.connect(_choose_slot);_columns.add_child(_equipment)
	source.read(func():_equipment.setup(plan,catalog))
	_columns.remove_child(_training);_equipment.left_panel.add_child(_training);_equipment.right_panel.add_child(skill_box)
	_pools=Label.new();_pools.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_pools.add_theme_font_size_override("font_size",15);_equipment.left_panel.add_child(_pools)
	_training_cost=Label.new();_training_cost.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_training_cost.add_theme_font_size_override("font_size",15);skill_box.add_child(_training_cost)
	_selector_frame=PanelContainer.new();_selector_frame.add_theme_stylebox_override("panel",WikiCampArt.panel_style());_columns.add_child(_selector_frame)
	var selector_body := VBoxContainer.new();_selector_frame.add_child(selector_body)
	_picker_placeholder=Label.new();_picker_placeholder.text=RemakeText.t("Choose an equipment slot to see items, spells and saved recipes here.");_picker_placeholder.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;selector_body.add_child(_picker_placeholder)
	_picker=VBoxContainer.new();_picker.hide();_picker.add_theme_constant_override("separation",14);selector_body.add_child(_picker)
	var note := Label.new();note.text=RemakeText.t("Base values exclude equipment bonuses, perks and temporary effects. Training cost starts from zero skills; crafting totals exclude fixed items and spell purchases.");note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_body.add_child(note)
	_summary=RichTextLabel.new();_summary.bbcode_enabled=true;_summary.fit_content=true;_summary.scroll_active=false;_summary.custom_minimum_size.y=100;_body.add_child(_summary)
	_rows=VBoxContainer.new();_rows.add_theme_constant_override("separation",12);_body.add_child(_rows)
	if not resized.is_connected(_layout):resized.connect(_layout)
	_layout()
	_refresh()

func _layout() -> void:
	if is_instance_valid(_columns):
		_columns.vertical=size.x<1140
		_columns.add_theme_constant_override("separation",20)
		_selector_frame.custom_minimum_size.x=0 if _columns.vertical else 320
		_selector_frame.visible=not _columns.vertical or _picker.visible
		_equipment.custom_minimum_size.x=0

func _number(parent: Control,key: String,label: String,object: Dictionary,maximum: int,minimum: int) -> void:
	var name_label := Label.new();name_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;name_label.custom_minimum_size.x=76;name_label.text=label;name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(name_label)
	name_label.add_theme_font_size_override("font_size",14)
	var input := SpinBox.new();input.add_theme_font_size_override("font_size",14);input.min_value=minimum;input.max_value=maximum;input.value=object.get(key,minimum);input.custom_minimum_size.x=76 if key=="experience" else 58;input.allow_greater=false;parent.add_child(input)
	input.value_changed.connect(func(v): object[key]=int(v);changed.emit();_refresh())

func _refresh() -> void:
	var result: Dictionary=source.read(func(): return WikiPlan.totals(plan,catalog))
	source.read(func():_equipment.setup(plan,catalog))
	_pools.text=RemakeText.t("Health")+": "+WikiCatalog.num(result.health)+"\n"+RemakeText.t("Stamina")+": "+WikiCatalog.num(result.stamina)+"\n"+RemakeText.t("Weight")+": "+WikiCatalog.num(result.weight)+" / "+WikiCatalog.num(result.capacity)
	_training_cost.text=RemakeText.t("Training cost")+": "+WikiCatalog.num(result.training)
	var rows := []
	for field: Array in [["health","Health"],["stamina","Stamina"],["capacity","Maximum equipment load"],["weight","Weight"],["training","Training cost"],["value","Base value"],["construction","Construction cost"]]: rows.append([WikiCatalog.esc(RemakeText.t(field[1])),WikiCatalog.num(result[field[0]])])
	var html := WikiCatalog.heading(RemakeText.t("Character and costs"))+WikiCatalog.table_html([RemakeText.t("Property"),RemakeText.t("Value")],rows)
	if result.weight>result.capacity:html+=WikiCatalog.paragraph(RemakeText.t("The planned load exceeds this character's capacity."))
	html+=WikiCatalog.heading(RemakeText.t("Crafting materials"))
	for key: String in result.materials:
		var mat: Dictionary=result.materials[key];html+=WikiCatalog.paragraph(mat.title+" × "+str(mat.count))
	_summary.text=WikiHtml.to_bbcode("<article>"+html+"</article>")
	for child in _rows.get_children(): _rows.remove_child(child);child.queue_free()
	if result.rows.is_empty():
		var label := Label.new();label.text=RemakeText.t("Your plan is empty. Open an item or spell and choose Add to plan.");label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_rows.add_child(label)
	for i in result.rows.size():
		var row: Dictionary=result.rows[i]
		var box := VBoxContainer.new();_rows.add_child(box)
		var link := Button.new();link.text=row.title;link.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;link.disabled=not catalog.entries.has(row.key)
		link.pressed.connect(func():
			var entry: Dictionary=plan.entries[i]
			var magic := WikiPlan.spell(entry)
			var key: String=source.read(func():return catalog.add_variant(magic)) if row.key.begins_with("spell/") and row.valid else row.key
			var variant: String=entry.variant+("|"+magic if row.key.begins_with("item/") and magic and row.valid else "")
			article_requested.emit(key,variant))
		box.add_child(link)
		var status := Label.new();status.text=RemakeText.t("Unavailable in this campaign or incompatible combination.") if not row.valid else RemakeText.t("Requirements met") if row.ready else RemakeText.t("Needs more knowledge or stamina");status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status)
		var placement := ScrollOptionButton.new();placement.fit_to_longest_item=false;placement.add_item(RemakeText.t("Inventory"));placement.set_item_metadata(0,"")
		var kind: String=source.read(func():return WikiPlan.entry_type(plan.entries[i],catalog))
		for slot: String in WikiPlan.SLOTS:
			if WikiPlan.slot_type(slot)!=kind:continue
			placement.add_item(WikiEquipment.slot_label(slot));placement.set_item_metadata(placement.item_count-1,slot)
			if plan.entries[i].get("slot","")==slot:placement.select(placement.item_count-1)
		placement.item_selected.connect(func(index):source.read(func():WikiPlan.assign_slot(plan,i,placement.get_item_metadata(index),catalog));changed.emit();_refresh());box.add_child(placement)
		var controls := HBoxContainer.new();box.add_child(controls)
		_number(controls,"count",RemakeText.t("Count"),plan.entries[i],99,1)
		var remove := Button.new();remove.text=RemakeText.t("Remove");remove.pressed.connect(func(): plan.entries.remove_at(i);changed.emit();_refresh());controls.add_child(remove)


func _choose_slot(slot: String) -> void:
	_picked_slot=slot
	_picker_placeholder.hide()
	for child in _picker.get_children():_picker.remove_child(child);child.queue_free()
	_picker.show()
	_layout()
	var title := Label.new();title.text=RemakeText.t("Choose equipment")+" · "+WikiEquipment.slot_label(slot);title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_picker.add_child(title)
	_picker_query=LineEdit.new();_picker_query.placeholder_text=RemakeText.t("Search the wiki…");_picker_query.text_changed.connect(func(_text):source.read(_filter_picker));_picker.add_child(_picker_query)
	_picker_items=ScrollOptionButton.new();_picker_items.fit_to_longest_item=false;_picker_items.item_selected.connect(func(_index):source.read(_picker_select));_picker.add_child(_picker_items)
	_picker_versions=ScrollOptionButton.new();_picker_versions.fit_to_longest_item=false;_picker.add_child(_picker_versions)
	var actions := HFlowContainer.new();_picker.add_child(actions)
	_picker_apply=Button.new();_picker_apply.text=RemakeText.t("Equip");_picker_apply.pressed.connect(func():source.read(_equip_selected));actions.add_child(_picker_apply)
	_picker_craft=Button.new();_picker_craft.text=RemakeText.t("Craft / enchant");_picker_craft.pressed.connect(func():
		if _picker_saved_index>=0:return
		var variant := String(_picker_versions.get_item_metadata(_picker_versions.selected)) if _picker_versions.item_count else ""
		craft_requested.emit(_picker_key,variant,_picked_slot));actions.add_child(_picker_craft)
	var empty := Button.new();empty.text=RemakeText.t("Move to inventory");empty.pressed.connect(func():
		for row: Dictionary in plan.entries:
			if row.get("slot","")==_picked_slot:row.slot=""
		changed.emit();_refresh();_close_picker());actions.add_child(empty)
	var close := Button.new();close.text=RemakeText.t("Close");close.pressed.connect(_close_picker);actions.add_child(close)
	source.read(_filter_picker)
	ensure_control_visible(_picker)
	_picker_query.grab_focus()

func _filter_picker() -> void:
	_picker_items.clear()
	var rows: Array=WikiPlan.totals(plan,catalog).rows
	for i in rows.size():
		if not rows[i].valid or WikiPlan.entry_type(plan.entries[i],catalog)!=WikiPlan.slot_type(_picked_slot):continue
		if WikiSearch.score(_picker_query.text,rows[i].title,"")<0:continue
		_picker_items.add_item(RemakeText.t("From this build")+" · "+rows[i].title);_picker_items.set_item_metadata(_picker_items.item_count-1,i)
	for record: Dictionary in WikiLibrary.read().records:
		if record.type=="character" or record.plan.campaign!=source.campaign:continue
		if WikiPlan.entry_type(record.plan.entries[0],catalog)!=WikiPlan.slot_type(_picked_slot) or WikiSearch.score(_picker_query.text,record.name,"")<0:continue
		if not WikiPlan.totals(record.plan,catalog).rows[0].valid:continue
		_picker_items.add_item(RemakeText.t("Saved creations")+" · "+record.name);_picker_items.set_item_metadata(_picker_items.item_count-1,record)
	for key: String in catalog.search(_picker_query.text,"Spells" if WikiPlan.slot_type(_picked_slot)=="spell" else "Items"):
		var entry: Dictionary=catalog.entries[key]
		var probe := {"key":key,"variant":String(entry.value)}
		if WikiPlan.entry_type(probe,catalog)!=WikiPlan.slot_type(_picked_slot):continue
		_picker_items.add_item(entry.title);_picker_items.set_item_metadata(_picker_items.item_count-1,key)
	_picker_items.disabled=_picker_items.item_count==0
	_picker_apply.disabled=_picker_items.disabled
	_picker_craft.disabled=_picker_items.disabled
	if _picker_items.disabled:_picker_items.add_item(RemakeText.t("No matching pages"));_picker_versions.hide()
	else:_picker_select()

func _picker_select() -> void:
	var selected: Variant=_picker_items.get_item_metadata(_picker_items.selected)
	_picker_record=selected if selected is Dictionary else {}
	_picker_saved_index=int(selected) if selected is int else -1
	_picker_craft.visible=_picker_saved_index<0 and _picker_record.is_empty()
	_picker_apply.disabled=_picker_saved_index<0 and plan.entries.size()>=WikiPlan.LIMIT
	_picker_apply.tooltip_text=RemakeText.t("A plan can contain up to 32 entries.") if _picker_apply.disabled else ""
	if _picker_saved_index>=0 or not _picker_record.is_empty():
		_picker_versions.hide()
		return
	_picker_key=String(selected)
	_picker_craft.visible=_picker_key.begins_with("spell/") or catalog.craftable(_picker_key)
	_picker_versions.clear()
	for variant: String in catalog.variants_for(_picker_key):
		if variant.begins_with("bp:"):continue
		_picker_versions.add_item(catalog.display_item_title(variant));_picker_versions.set_item_metadata(_picker_versions.item_count-1,variant)
	_picker_versions.visible=_picker_versions.item_count>1

func _equip_selected() -> void:
	if _picker_items.disabled:return
	if _picker_saved_index>=0:
		WikiPlan.assign_slot(plan,_picker_saved_index,_picked_slot,catalog)
		changed.emit();_refresh();_close_picker();return
	if plan.entries.size()>=WikiPlan.LIMIT:return
	if not _picker_record.is_empty():
		plan.entries.append(_picker_record.plan.entries[0].duplicate(true));WikiPlan.assign_slot(plan,plan.entries.size()-1,_picked_slot,catalog)
		changed.emit();_refresh();_close_picker();return
	var entry: Dictionary=catalog.entries[_picker_key]
	var magic: String=entry.value if entry.kind=="spell" else ""
	var variant := String(_picker_versions.get_item_metadata(_picker_versions.selected)) if _picker_versions.item_count else ""
	plan.entries.append({"key":_picker_key,"variant":variant,"spell":magic,"runes":[],"count":1,"slot":""})
	WikiPlan.assign_slot(plan,plan.entries.size()-1,_picked_slot,catalog)
	changed.emit();_refresh();_close_picker()

func _inherited_theme() -> Theme:
	var node: Node=self
	while node:
		if node is Control and node.theme:return node.theme
		node=node.get_parent()
	return Theme.new()

func _section(parent: Control,key: String) -> void:
	var label := Label.new();label.text=RemakeText.t(key);label.add_theme_font_override("font",Interface800.font());label.add_theme_font_size_override("font_size",20);parent.add_child(label)

func _close_picker() -> void:
	_picker.hide()
	_picker_placeholder.show();_layout()
	if _equipment._buttons.has(_picked_slot):_equipment._buttons[_picked_slot].grab_focus()

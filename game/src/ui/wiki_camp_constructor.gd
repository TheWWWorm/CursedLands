class_name WikiCampConstructor
extends Control
signal rune_chosen(code: String)
signal spell_chosen(code: String)
signal item_chosen(id: String)
var _focus_id := ""
var _canvas: Control
var _board: WikiWorkbench
var _result: PanelContainer
var _details: PanelContainer
var _top: HBoxContainer
var _bottom: HBoxContainer
var _detail_text: RichTextLabel
var _spell_choices: ScrollOptionButton
var _selector: PanelContainer
var _identity := ""

func setup(magic: String,item: String,catalog: WikiCatalog,board: WikiWorkbench) -> void:
	var identity := GameData.campaign_id+"|"+magic+"|"+item
	if identity==_identity:return
	_identity=identity
	if board.get_parent():board.get_parent().remove_child(board)
	for child in get_children():remove_child(child);child.queue_free()
	theme=WikiCampArt.theme(_inherited_theme())
	_canvas=Control.new();add_child(_canvas)
	_board=board;_board.board_size=400;_board.custom_minimum_size=Vector2.ZERO;_canvas.add_child(_board);_board.setup(magic,item)
	_result=PanelContainer.new();_result.add_theme_stylebox_override("panel",WikiCampArt.panel_style());_canvas.add_child(_result)
	var info := RichTextLabel.new();info.bbcode_enabled=true;info.scroll_active=true;info.fit_content=false;_result.add_child(info)
	var title := catalog.display_item_title(item) if item else WikiCatalog.spell_title(magic)
	var parsed := Spells.parse(magic)
	var text := "[center][font_size=21]"+title+"[/font_size][/center]\n\n"
	for field: Array in [["effect","Power"],["mana","Stamina cost"],["complex","Complexity"],["range","Range"],["duration","Duration (ticks)"],["targets","Targets"]]:
		if magic:text+=RemakeText.t(field[1])+": "+WikiCatalog.num(parsed.get(field[0],0))+"\n"
	if item:
		var details := Items.info(item)
		var built := item+("|"+magic if magic else "")
		var valid := magic.is_empty() or Items.can_enchant(item,magic)
		if details.table=="weapons":
			var damage := Items.damage(item)
			text+=RemakeText.t("Damage")+": "+WikiCatalog.num(damage.x)+"–"+WikiCatalog.num(damage.y)+"\n"
		if details.table=="armors":
			text+="\n"+RemakeText.t("Armor: primary coverage")+"\n"
			var armor := Items.armor_layer(item)
			for i in armor.size():
				if not is_zero_approx(armor[i]):text+=RemakeText.t(WikiCatalog.DAMAGE_TYPES[i])+": "+WikiCatalog.num(armor[i])+"\n"
		for row: Array in [["Weight",Items.weight(item)],["Durability",Items.max_durability(item)],["Rune slots",Items.slots(item)],["Charge capacity",Items.energy(item)]]:text+=RemakeText.t(row[0])+": "+WikiCatalog.num(row[1])+"\n"
		if valid:
			text+="\n"+RemakeText.t("Base value")+": "+WikiCatalog.num(Items.price(built))+"\n"+RemakeText.t("Construction cost")+": "+WikiCatalog.num(int(Items.price(built)*Items.COEF[Items.Deal.CONSTR]))+"\n"
		if magic:text+="\n"+RemakeText.t("This combination fits the item." if valid else "The spell must fit the item's complexity and energy limits. Weapons and armour also need a triggered or continuous item rune.")+"\n"
	text+="\n"+RemakeText.t("Runes: %s / 8") % Spells.mods_of(magic).size()
	info.text=text
	_details=PanelContainer.new();_details.add_theme_stylebox_override("panel",WikiCampArt.panel_style());_canvas.add_child(_details)
	var side := VBoxContainer.new();side.add_theme_constant_override("separation",16);_details.add_child(side)
	var label := Label.new();label.text=RemakeText.t("Spell constructor") if item.is_empty() else RemakeText.t("Item constructor");label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",21);side.add_child(label)
	_detail_text=RichTextLabel.new();_detail_text.bbcode_enabled=true;_detail_text.size_flags_vertical=Control.SIZE_EXPAND_FILL;side.add_child(_detail_text)
	_detail_text.text=RemakeText.t("Choose a material above. Optionally select an enchantment and add compatible runes below.") if item else RemakeText.t("Choose a spell from the top tray. Add runes from the lower tray; select an installed rune to remove it.")
	if item:
		var choices := ScrollOptionButton.new();_spell_choices=choices;choices.fit_to_longest_item=false;choices.add_item(RemakeText.t("No enchantment"));choices.set_item_metadata(0,"")
		for key: String in catalog.search("","Spells"):
			var code := String(catalog.entries[key].value);choices.add_item(WikiCatalog.spell_title(code));choices.set_item_metadata(choices.item_count-1,code)
			if code==magic.get_slice("{",0):choices.select(choices.item_count-1)
		choices.item_selected.connect(func(i):spell_chosen.emit(choices.get_item_metadata(i)));side.add_child(choices);side.move_child(choices,1)
	_selector=PanelContainer.new();_selector.add_theme_stylebox_override("panel",WikiCampArt.panel_style());add_child(_selector)
	var selector_body := VBoxContainer.new();selector_body.add_theme_constant_override("separation",12);_selector.add_child(selector_body)
	var selector_title := Label.new();selector_title.text=RemakeText.t("Spells");selector_title.add_theme_font_size_override("font_size",24);selector_body.add_child(selector_title)
	var search := LineEdit.new();search.placeholder_text=RemakeText.t("Search spells");selector_body.add_child(search)
	var list_scroll := ScrollContainer.new();list_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;list_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;selector_body.add_child(list_scroll)
	var spell_list := VBoxContainer.new();spell_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;spell_list.add_theme_constant_override("separation",8);list_scroll.add_child(spell_list)
	var spell_rows := []
	if item:spell_rows.append({"name":RemakeText.t("No enchantment"),"magic":""})
	for record: Dictionary in WikiLibrary.read().records:
		if record.type=="spell" and record.plan.campaign==GameData.campaign_id:
			if not WikiPlan.totals(record.plan,catalog).rows[0].valid:continue
			var saved_magic := WikiPlan.spell(record.plan.entries[0]);spell_rows.append({"name":RemakeText.t("Saved creations")+" · "+record.name,"magic":saved_magic})
	for key: String in catalog.search("","Spells"):
		var code := String(catalog.entries[key].value);spell_rows.append({"name":WikiCatalog.spell_title(code),"magic":code})
	var filter_list := func():
		for child in spell_list.get_children():spell_list.remove_child(child);child.queue_free()
		for row: Dictionary in spell_rows:
			if WikiSearch.score(search.text,row.name,"")<0:continue
			var choice := Button.new();choice.text=row.name;choice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;choice.alignment=HORIZONTAL_ALIGNMENT_LEFT;choice.custom_minimum_size.y=44;choice.add_theme_font_size_override("font_size",16);choice.add_theme_constant_override("icon_max_width",32);choice.expand_icon=true
			if row.magic:choice.icon=WikiWorkbench.piece_icon("spell:"+row.magic)
			choice.pressed.connect(func():spell_chosen.emit(row.magic));spell_list.add_child(choice)
	search.text_changed.connect(func(_text):filter_list.call());filter_list.call()
	var selected := Label.new();selected.text=WikiCatalog.spell_title(magic) if magic else RemakeText.t("No enchantment");selected.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;selector_body.add_child(selected)
	var count := Label.new();count.text=RemakeText.t("Runes: %s / 8") % Spells.mods_of(magic).size();selector_body.add_child(count)
	if item and magic and not Spells.mods_of(magic).is_empty():
		var installed := GridContainer.new();installed.columns=4;side.add_child(installed);side.move_child(installed,2)
		var runes := Spells.mods_of(magic)
		for index in runes.size():
			var remove := Button.new();remove.icon=WikiWorkbench.piece_icon("rune:"+runes[index]);remove.expand_icon=true;remove.custom_minimum_size=Vector2(36,36);remove.add_theme_constant_override("icon_max_width",28);remove.tooltip_text=RemakeText.t("Remove")+": "+WikiCatalog.rune_title(runes[index]);remove.pressed.connect(func():_board.rune_removed.emit(index));installed.add_child(remove)
	_top=_tray();_bottom=_tray()
	if item:
		var key := "item/"+String(Items.info(item).base).uri_encode()
		for variant: String in catalog.variants_for(key):
			if variant.begins_with("bp:"):continue
			var b := _piece(_top,variant,catalog.display_item_title(variant),"stock");b.pressed.connect(func():item_chosen.emit(variant))
	else:
		for row: Dictionary in GameData.db.table("spell_prototypes"):
			var code := String(row.code).to_lower()
			if not catalog.entries.has("spell/"+code.uri_encode()):continue
			var b := _piece(_top,"spell:"+code,WikiCatalog.spell_title(code),"stock")
			b.pressed.connect(func():spell_chosen.emit(code))
			b.mouse_entered.connect(func():_detail_text.text=WikiCatalog.spell_title(code));b.focus_entered.connect(func():_detail_text.text=WikiCatalog.spell_title(code))
			if code==magic.get_slice("{",0):b.set_pressed_no_signal(true)
	for row: Dictionary in GameData.db.table("spell_modifiers"):
		var code := String(row.code).to_lower()
		if not WikiCatalog.rune_listed(code):continue
		var b := _piece(_bottom,"rune:"+code,WikiCatalog.rune_title(code),"bag")
		b.disabled=magic.is_empty() or not WikiCatalog.rune_fits(magic,code)
		if b.disabled:b.modulate=Color(0.45,0.45,0.45)
		if _focus_id=="rune:"+code and not b.disabled:b.grab_focus.call_deferred()
		b.tooltip_text=RemakeText.t("Add rune")+": "+WikiCatalog.rune_title(code)
		b.pressed.connect(func():_focus_id="rune:"+code;rune_chosen.emit(code))
		var description := WikiCatalog.rune_title(code)+"\n\n"+RemakeText.t("Stamina cost")+": "+WikiCatalog.num(row.get("mana",0))+"\n"+RemakeText.t("Complexity")+": "+WikiCatalog.num(row.get("complex",0))
		b.mouse_entered.connect(func():_detail_text.text=description);b.focus_entered.connect(func():_detail_text.text=description)
	if not resized.is_connected(_layout):resized.connect(_layout)
	_layout()

func _inherited_theme() -> Theme:
	var node := get_parent()
	while node:
		if node is Control and node.theme:return node.theme
		node=node.get_parent()
	return Theme.new()

func _tray() -> HBoxContainer:
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",0);_canvas.add_child(row)
	var previous := Button.new();previous.text="‹";previous.tooltip_text=RemakeText.t("Previous components");previous.custom_minimum_size.x=50;row.add_child(previous)
	var scroll := ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(scroll)
	var cells := HBoxContainer.new();cells.add_theme_constant_override("separation",0);scroll.add_child(cells)
	var next := Button.new();next.text="›";next.tooltip_text=RemakeText.t("Next components");next.custom_minimum_size.x=50;row.add_child(next)
	previous.pressed.connect(func():scroll.scroll_horizontal=maxi(0,scroll.scroll_horizontal-100*7));next.pressed.connect(func():scroll.scroll_horizontal+=100*7)
	row.set_meta("cells",cells)
	return row

func _piece(tray: HBoxContainer,id: String,title: String,frame_name: String) -> Button:
	var button := Button.new();button.toggle_mode=true;button.set_meta("workbench_slot",true);button.tooltip_text=title;button.custom_minimum_size=Vector2(100,100)
	(tray.get_meta("cells") as HBoxContainer).add_child(button)
	for state: String in ["normal","hover","pressed","disabled"]:
		var style := StyleBoxTexture.new();style.texture=WikiCampArt.texture(frame_name);style.modulate_color=Color(1.2,1.15,0.9) if state in ["hover","pressed"] else Color.WHITE;button.add_theme_stylebox_override(state,style)
	var icon := TextureRect.new();icon.texture=WikiWorkbench.piece_icon(id) if Items.is_spell_piece(id) else null;icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(icon);icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);icon.offset_left=12;icon.offset_top=12;icon.offset_right=-12;icon.offset_bottom=-12
	if not Items.is_spell_piece(id):
		icon.hide();var model := WikiPreview.new();model.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(model);model.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);model.offset_left=12;model.offset_top=12;model.offset_right=-12;model.offset_bottom=-12;model.show_model({"kind":"item","value":id})
	elif not icon.texture:icon.texture=load("res://icons/wiki/rune.svg")
	return button

func _layout() -> void:
	if not _canvas:return
	var compact := size.x<760
	var side_by_side := size.x>=1140
	_selector.visible=side_by_side
	if is_instance_valid(_spell_choices):_spell_choices.visible=not side_by_side
	var extent := size.x-(340 if side_by_side else 0)
	var factor := extent/800.0
	if not compact:factor=minf(factor,maxf(1.0,(get_viewport_rect().size.y-185.0)/600.0))
	custom_minimum_size.y=(1120 if compact else 600)*factor
	_canvas.position.x=(extent-800*factor)/2;_canvas.scale=Vector2.ONE*factor;_canvas.size=Vector2(800,1120 if compact else 600)
	_selector.position=Vector2(size.x-320,0);_selector.size=Vector2(320,600*factor)
	_top.position=Vector2.ZERO;_top.size=Vector2(800,100)
	_bottom.position=Vector2(0,500);_bottom.size=Vector2(800,100)
	_board.position=Vector2(200,100);_board.size=Vector2(400,400)
	_result.position=Vector2(0,100);_result.size=Vector2(200,400)
	_details.position=Vector2(600,100);_details.size=Vector2(200,400)
	if compact:
		_canvas.scale=Vector2.ONE;_canvas.position.x=0;_canvas.size=Vector2(size.x,size.x+820)
		_top.size=Vector2(size.x,100)
		_board.position=Vector2(0,100);_board.scale=Vector2.ONE*size.x/400
		_bottom.position=Vector2(0,100+size.x);_bottom.size=Vector2(size.x,100)
		_result.position=Vector2(0,200+size.x);_result.size=Vector2(size.x,310)
		_details.position=Vector2(0,510+size.x);_details.size=Vector2(size.x,260)
		custom_minimum_size.y=size.x+770
	else:_board.scale=Vector2.ONE

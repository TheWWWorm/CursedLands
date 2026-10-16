extends Node
var failures := []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label);printerr("FAIL ",label)
func frames(n:=6) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void:
	GameData.options.confine_mouse=0
	var before := hash(GameData.db.tables)
	var time := Time.get_ticks_msec()
	var c := WikiCatalog.new();c.rebuild()
	var build_ms := Time.get_ticks_msec()-time
	# Compare the reference against combat itself, including integer truncation,
	# ranged defense and the named/party exceptions. Never alter a player save.
	var previous_difficulty := GameData.difficulty
	var world := GameWorld.new()
	var combat := Combat.new(world)
	var unit := GameUnit.new();unit.uid=1
	for key: String in c.search("","Creatures"):
		unit.proto=GameData.db.find("monster_prototypes",c.entries[key].value)
		unit.stats={"to_hit":unit.proto.get("to_hit",0),"parry":unit.proto.get("parry",0)}
		var comparison := c.creature_difficulty(c.entries[key].value)
		for level in [0,1]:
			GameData.difficulty=level
			var expected: Dictionary=comparison.hard if level==0 else comparison.easy
			check(expected.attack==combat.attack_value(unit),"difficulty attack matches combat "+key)
			check(expected.defense==combat.defence_value(unit),"difficulty defense matches combat "+key)
			check(is_equal_approx(expected.armor,float(unit.proto.get("absorption",0))*combat.difficulty(unit,"Absorption")),"difficulty armor matches combat "+key)
	GameData.difficulty=1;unit.uid=1000000001
	check(combat.difficulty(unit,"Attack")==1 and combat.difficulty(unit,"Defence")==1,"named character exception")
	unit.controller=0;check(combat.difficulty(unit,"Absorption")==1,"party armor exception")
	GameData.difficulty=previous_difficulty
	unit.free();world.free()
	check(c.search("swrod","Items").size()>0 if RemakeText.lang=="en" else true,"transposed spelling finds swords")
	check(WikiSearch.score("Schwert","Schwert","")>WikiSearch.score("Schwert","Bronzeschwert",""),"exact title ranks first")
	check(WikiSearch.score("  feuer   pfeil ","Feuer Pfeil","")>=0,"multiword whitespace")
	var relations := 0;var pins := 0
	for key: String in c.entries:
		for group: Dictionary in c.knowledge.groups(key):
			for row: Dictionary in group.rows: check(c.entries.has(row.key),"relationship target "+row.key);relations+=1
		for pin: Dictionary in c.knowledge.pins.get(key,[]):
			check(pin.x>=0 and pin.x<=1 and pin.y>=0 and pin.y<=1 and c.entries.has(pin.key),"bounded map point");pins+=1
	check(relations>1000 and pins>100,"authored relationships and map markers populated")
	var plan := WikiPlan.blank(GameData.campaign_id)
	var item_key := "";var item := ""
	for key: String in c.search("","Items"):
		if c.craftable(key):
			for variant: String in c.variants_for(key):
				if not variant.begins_with("bp:"):item_key=key;item=variant;break
		if item:break
	check(not item.is_empty(),"craftable item for fixture")
	plan.entries.append({"key":item_key,"variant":item,"spell":"","runes":[],"count":2})
	var magic_key: String=c.search("","Spells")[0]
	var magic: String=c.entries[magic_key].value
	plan.entries.append({"key":magic_key,"variant":"","spell":magic,"runes":[],"count":1})
	plan=WikiPlan.validate(plan)
	plan.skills={"melee":20,"archery":12,"science":7,"elemental":31,"sense":42,"astral":53}
	var totals := WikiPlan.totals(plan,c)
	check(is_equal_approx(totals.weight,Items.weight(item)*2),"planned equipment weight uses inventory calculation")
	check(totals.construction==Items.constr_piece_price(item)*2,"construction price uses inventory calculation")
	check(totals.stamina==Skills.base_pool(plan.experience,plan.dexterity,"MP"),"stamina uses original curve")
	check(totals.rows.all(func(row):return row.valid),"valid selected items and spells")
	check(WikiPlan.decode(WikiPlan.url(plan,"de"))==plan,"portable build round trip")
	check(WikiPlan.decode("not a build").is_empty(),"invalid link rejected")
	var invalid := plan.duplicate(true);invalid.v=2;check(WikiPlan.validate(invalid).is_empty(),"future build version rejected")
	invalid=plan.duplicate(true);invalid.entries[0].count=-1;check(WikiPlan.validate(invalid).is_empty(),"negative quantity rejected")
	invalid=plan.duplicate(true);invalid.entries[1].runes=["unknown"];check(not WikiPlan.totals(invalid,c).rows[1].valid,"unknown rune rejected")
	FileAccess.open("user://wiki-plan-oracle.json",FileAccess.WRITE).store_string(JSON.stringify({"plan":plan,"encoded":WikiPlan.encode(plan),"totals":totals,"constructors":c.constructor_data()}))
	var enchanted := WikiPlan.blank(GameData.campaign_id)
	enchanted.entries=[{"key":"item/long%20sword","variant":"long sword.steel","spell":"arrow","runes":["it"],"count":1,"slot":"weapon1"}]
	var enchanted_totals := WikiPlan.totals(enchanted,c)
	check(enchanted_totals.rows[0].valid,"triggered spell can be crafted into a weapon")
	check(enchanted_totals.value==Items.price("long sword.steel|arrow{it}"),"enchanted plan uses complete crafted item value")
	check(WikiPlan.decode(WikiPlan.url(enchanted,"en")).entries[0].runes==["it"],"shared equipped item retains spell runes")
	local_library_test(plan,enchanted)
	FileAccess.open("user://wiki-enchanted-oracle.json",FileAccess.WRITE).store_string(JSON.stringify({"plan":enchanted,"totals":enchanted_totals}))
	var panel := WikiPanel.new();add_child(panel);panel.open();await frames()
	panel.navigate(item_key,true,item);await frames();panel._source.read(panel._add_current_to_plan)
	check(panel._plan_by_campaign[GameData.campaign_id].entries.size()==1,"native add-to-plan action")
	panel._import_plan(WikiPlan.url(plan,RemakeText.lang));await frames()
	check(panel.current=="mechanics/planning" and panel._planner.visible,"native imported plan opens planner")
	check(panel._planner.plan==plan,"native import retains fields and runes")
	panel._planner._choose_slot("helm");await frames()
	check(panel._planner._picker.is_visible_in_tree() and not panel._planner._picker_apply.disabled,"equipment picker offers compatible helmets")
	panel._source.read(panel._planner._equip_selected);await frames()
	check(panel._planner.plan.entries.any(func(row):return row.get("slot","")=="helm"),"equipment picker equips a helmet")
	check(not panel._planner._picker.visible,"equipment picker returns to skills after equipping")
	panel._craft_equipment("item/long%20sword","long sword.steel","weapon1");await frames()
	var before_craft: int=panel._plan_by_campaign[GameData.campaign_id].entries.size()
	panel._draft_item_spell="arrow";panel._source.read(panel._item_draft_status);panel._source.read(panel._add_current_to_plan)
	check(panel._plan_by_campaign[GameData.campaign_id].entries.size()==before_craft,"item without required trigger rune cannot be crafted")
	panel._draft_item_spell="arrow{it}";panel._source.read(panel._item_draft_status);panel._source.read(panel._add_current_to_plan);await frames()
	check(panel.current=="mechanics/planning","craft and equip returns to character")
	var crafted: Dictionary=panel._planner.plan.entries.back()
	check(crafted.slot=="weapon1" and crafted.spell=="arrow" and crafted.runes==["it"],"craft and equip preserves weapon enchantment")
	panel._planner._choose_slot("weapon2");await frames()
	for i in panel._planner._picker_items.item_count:
		if panel._planner._picker_items.get_item_metadata(i) is int and int(panel._planner._picker_items.get_item_metadata(i))==panel._planner.plan.entries.size()-1:
			panel._planner._picker_items.select(i);panel._source.read(panel._planner._picker_select);break
	panel._source.read(panel._planner._equip_selected);await frames()
	check(crafted.slot=="weapon2" and crafted.runes==["it"],"saved enchanted item equips in another slot without losing runes")
	check(panel._planner.plan.entries.size()==before_craft+1,"equipping crafted inventory does not duplicate it")
	# Exercise the actual save dialog and library controls in the isolated profile.
	if FileAccess.file_exists(WikiLibrary.PATH):DirAccess.remove_absolute(WikiLibrary.PATH)
	panel._source.read(panel._save_current_creation);await frames()
	var save_dialog: ConfirmationDialog=panel.get_node("WikiSaveCreation")
	check(save_dialog.visible,"native save opens a naming dialog")
	save_dialog.confirmed.emit();await frames()
	var saved_library := WikiLibrary.read()
	check(saved_library.records.size()==1 and saved_library.records[0].type=="character","native save dialog persists a character")
	var saved_item := WikiLibrary.save("Enchanted steel","item",enchanted)
	panel._open_library();await frames()
	panel._load_creation(saved_item.record,false);await frames()
	check(panel._workbench_open and panel._draft_item_spell=="arrow{it}","native library reopens an item's complete enchantment")
	panel._open_library();await frames();panel._load_creation(saved_library.records[0],false);await frames()
	check(panel._planner.plan.entries.any(func(row):return row.get("slot","")=="weapon2" and row.runes==["it"]),"native saved character restores enchanted equipment and slots")
	panel._planner._choose_slot("weapon4");await frames()
	var found_local := false
	for i in panel._planner._picker_items.item_count:
		if panel._planner._picker_items.get_item_metadata(i) is Dictionary:panel._planner._picker_items.select(i);panel._source.read(panel._planner._picker_select);found_local=true;break
	check(found_local,"native selector includes locally saved recipes")
	panel._source.read(panel._planner._equip_selected);await frames()
	check(panel._planner.plan.entries.any(func(row):return row.get("slot","")=="weapon4" and row.spell=="arrow" and row.runes==["it"]),"native selector equips saved recipe without losing runes")
	panel._workbench_open=false
	var map_key := ""
	for key: String in panel.catalog.search("","Maps"):
		if panel.catalog.knowledge.pins.get(key,[]).size()>0 and not panel.catalog.page(key).preview.is_empty():map_key=key;break
	panel.navigate(map_key);await frames()
	check(panel._map_filters.visible and panel._preview.map_view.get_child_count()>0,"native map has interactive markers")
	var quest := ""
	for key: String in panel.catalog.search("","Quests"):
		if panel.catalog.page(key).guide:quest=key;break
	panel.navigate(quest);await frames()
	check(panel._guide_button.visible and panel._guide_button.button_pressed,"quest hints visible by default")
	panel._guide_button.button_pressed=false;panel._toggle_guide();check(panel.html==panel._base_html,"quest hints can collapse")
	var slot_plan := WikiPlan.blank(GameData.campaign_id)
	slot_plan.entries.append({"key":item_key,"variant":item,"spell":"","runes":[],"count":1})
	catalog_slot_test(slot_plan,c)
	panel.navigate(magic_key);await frames()
	panel._workbench_open=true;panel._layout();await frames()
	check(panel._builder_scroll.visible and not panel._article.visible,"constructor gets a dedicated reading pane")
	panel._source.read(panel._add_selected_rune);await frames()
	check(panel._workbench._slots.size()==10,"camp spell assembly has result, keystone and eight rune slots")
	panel._source.read(func():panel._remove_rune_at(0));await frames()
	check(Spells.mods_of(panel.catalog.entries[panel.current].value).is_empty(),"clicking a filled rune slot removes that rune")
	panel._workbench_open=false;panel._layout()
	if DisplayServer.get_name()!="headless":
		GameData._window_gen+=1;get_tree().root.mode=Window.MODE_WINDOWED;get_tree().root.size=Vector2i(1440,900);await frames(18)
		for pair: Array in [["home","home"],[item_key,"item"],[map_key,"map"],[quest,"quest"],["mechanics/planning","plan"],[c.search("","Creatures")[0],"difficulty"]]:
			panel.navigate(pair[0]);await frames(25);get_viewport().get_texture().get_image().save_png("user://wiki-"+RemakeText.lang+"-"+pair[1]+".png")
		panel.navigate("mechanics/planning");panel._planner._choose_slot("weapon3");await frames(15)
		check(panel._planner._picker.get_global_rect().position.x>=panel._planner._equipment.get_global_rect().end.x,"native picker uses separate side space")
		get_viewport().get_texture().get_image().save_png("user://wiki-"+RemakeText.lang+"-selector.png")
		panel._open_library();await frames(15);get_viewport().get_texture().get_image().save_png("user://wiki-"+RemakeText.lang+"-library.png");panel._library_view.hide()
		panel.navigate(magic_key);panel._workbench_open=true;panel._layout();await frames(25)
		get_viewport().get_texture().get_image().save_png("user://wiki-"+RemakeText.lang+"-workbench.png")
		panel._workbench_open=false
		panel.navigate(item_key,true,item);panel._workbench_open=true;panel._layout();await frames(25)
		check(panel._draft_item_spell.is_empty(),"item constructor starts without an implicit enchantment")
		check(panel._camp_constructor._spell_choices.is_visible_in_tree() or panel._camp_constructor._selector.is_visible_in_tree(),"camp item enchantment picker is visible")
		panel._camp_constructor._spell_choices.select(1);panel._camp_constructor._spell_choices.item_selected.emit(1);await frames()
		check(not panel._draft_item_spell.is_empty(),"camp item enchantment picker changes the draft")
		panel._camp_constructor._spell_choices.select(0);panel._camp_constructor._spell_choices.item_selected.emit(0);await frames()
		get_viewport().get_texture().get_image().save_png("user://wiki-"+RemakeText.lang+"-item-workbench.png")
		panel._workbench_open=false
		panel.navigate(map_key);await frames(15)
		panel._preview._select_pins([panel._map_pins[0]]);await frames(10)
		check(panel._preview._pin_popup.position.x>=panel._preview.get_global_rect().position.x,"map popup remains near the map")
		get_viewport().get_texture().get_image().save_png("user://wiki-"+RemakeText.lang+"-map-popup.png")
		panel._preview._pin_popup.hide()
		get_tree().root.size=Vector2i(480,800);await frames(18)
		panel.navigate(c.search("","Creatures")[0]);await frames(18)
		check(panel._article.size.y>300 and not panel._sidebar.visible,"compact article gets the reading space")
		get_viewport().get_texture().get_image().save_png("user://wiki-"+RemakeText.lang+"-phone.png")
		panel._browse_toggle.pressed.emit();await frames()
		check(panel._sidebar.visible and panel._results.size.y>200,"compact browse exposes useful results")
		panel._results.item_selected.emit(0);await frames()
		check(not panel._sidebar.visible and panel._reading_surface.visible,"result returns to compact article")
		panel.navigate(map_key);await frames();panel._preview_toggle.pressed.emit();await frames()
		check(panel._preview_box.visible and not panel._article_column.visible,"compact illustration has its own space")
		check(panel.get_rect().end.x<=480 and panel.get_rect().end.y<=800,"localized compact controls fit")
		panel.navigate(magic_key);panel._workbench_open=true;panel._layout();await frames(18)
		check(panel._camp_constructor.get_global_rect().end.x<=480,"compact constructor fits viewport")
		get_viewport().get_texture().get_image().save_png("user://wiki-"+RemakeText.lang+"-phone-workbench.png")
		panel._workbench_open=false;panel.navigate("mechanics/planning");await frames()
		check(panel._planner._grid.columns==2 and panel.get_rect().end.x<=480,"planner adapts when resized")
	panel.close();panel.queue_free();await frames()
	DirAccess.remove_absolute(WikiLibrary.PATH)
	check(hash(GameData.db.tables)==before,"wiki leaves game database unchanged")
	TexUpscale.shutdown()
	print("WIKI_REWORK ",JSON.stringify({"checks":checks,"failures":failures,"build_ms":build_ms,"relations":relations,"pins":pins}))
	get_tree().quit(0 if failures.is_empty() else 1)

func catalog_slot_test(plan: Dictionary,c: WikiCatalog) -> void:
	WikiPlan.auto_slot(plan,plan.entries[0],c)
	var slot: String=plan.entries[0].slot
	check(WikiPlan.decode(WikiPlan.url(plan,"en")).entries[0].slot==slot,"equipped slot survives shared link")
	if not slot:return
	plan.entries.append(plan.entries[0].duplicate(true));plan.entries[1].slot=""
	check(WikiPlan.assign_slot(plan,1,slot,c),"compatible equipment can replace a slot")
	check(plan.entries[0].slot=="" and plan.entries[1].slot==slot,"displaced equipment returns to inventory")
	plan.entries[0].slot=slot
	check(WikiPlan.validate(plan).is_empty(),"duplicate equipped slots rejected")

func local_library_test(plan: Dictionary,enchanted: Dictionary) -> void:
	# Isolated test path, never the player's saved library.
	var path := "user://wiki-library-test.json"
	if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	var character := WikiLibrary.save("Персонаж · Charakter","character",plan,path)
	var item := WikiLibrary.save("Enchanted steel","item",enchanted,path)
	var spell_plan := WikiPlan.blank(GameData.campaign_id);spell_plan.entries=[{"key":"spell/acid_ray","variant":"","spell":"acid_ray","runes":["e1","r1"],"count":1}]
	var magic := WikiLibrary.save("Acid reach","spell",spell_plan,path)
	check(not character.error and not item.error and not magic.error,"native library saves all three creation types")
	var restored := WikiLibrary.read(path)
	check(restored.records.size()==3 and not restored.error,"native library reads snapshots from disk")
	var restored_item: Dictionary=restored.records.filter(func(r):return r.type=="item")[0]
	check(restored_item.plan.entries[0].spell=="arrow" and restored_item.plan.entries[0].runes==["it"],"native local item preserves enchantment")
	check(restored_item.plan.entries[0].slot=="","native saved recipe can be reused in any compatible slot")
	var restored_character: Dictionary=restored.records.filter(func(r):return r.type=="character")[0]
	check(restored_character.plan==WikiPlan.validate(plan),"native local character preserves attributes, skills and loadout")
	check(not WikiLibrary.save("wrong","item",spell_plan,path).error.is_empty(),"native library rejects mismatched record kinds")
	check(WikiLibrary.remove(item.record.id,path).is_empty() and WikiLibrary.read(path).records.size()==2,"native library removes the selected snapshot only")
	FileAccess.open(path,FileAccess.WRITE).store_string("broken")
	check(not WikiLibrary.read(path).error.is_empty() and not WikiLibrary.save("new","character",plan,path).error.is_empty(),"native corrupt library is not overwritten")
	check(FileAccess.get_file_as_string(path)=="broken","native failed save preserves unreadable data")
	DirAccess.remove_absolute(path)

extends Node
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame
func spell_values(spell: String) -> Dictionary:
	var parsed := Spells.parse(spell); var out := {}
	for field: String in ["effect","mana","complex","range","area","radius","duration","targets","price","flags","filter"]: out[field] = parsed[field]
	return out
func _ready() -> void:
	GameData.options.confine_mouse = 0
	var other := "/home/llm2x/Documents/EI/inspection/lost-in-astral/game"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--wiki-other="): other = arg.trim_prefix("--wiki-other=")
	var original := WikiSource._capture()
	var hash_before := hash(GameData.db.tables)
	var settings_before := FileAccess.get_file_as_bytes(GameData.CONFIG_PATH)
	var source := WikiSource.new()
	GameData.campaign_roots[CampaignProfile.ASTRAL] = other
	check(source.load_installed(CampaignProfile.ASTRAL).is_empty(),"alternate installed campaign opens read-only")
	check(GameData.db == original.data.db and GameData.root == original.data.root,"loading alternate source restores live database and root")
	var catalog: WikiCatalog = source.read(func(): var c := WikiCatalog.new(); c.rebuild(); return c)
	check(catalog.search("","Maps").size()>10 and catalog.search("","Quests").size()>30,"expansion maps and quests indexed")
	for path: String in WikiSource.CACHES:
		var script: GDScript = load(path)
		for key: String in WikiSource.CACHES[path]: check(is_same(script.get(key),original.caches[path][key]),"restore exact cache "+path+":"+key)
	var panel := WikiPanel.new(); add_child(panel); panel.open(); await frames()
	panel._select_campaign(CampaignProfile.ASTRAL); await frames()
	check(panel.catalog == panel._catalogs[CampaignProfile.ASTRAL],"expansion campaign tab owns its catalogue")
	var map: String = panel.catalog.search("","Maps")[0]
	for key: String in panel.catalog.search("","Maps"):
		if source.read(func(): return not panel.catalog.page(key).preview.is_empty()): map = key; break
	panel.navigate(map); await frames()
	check(panel._preview.map_view != null and panel._preview.map_view.texture != null,"map tab shows original map artwork")
	check(GameData.db == original.data.db and hash(GameData.db.tables)==hash_before,"alternate article and artwork leave gameplay data unchanged")
	panel._select_campaign(CampaignProfile.ORIGINAL); await frames()
	var c := panel.catalog
	check(c.search("","Spells").all(func(k): return not "{" in c.entries[k].value),"spell browsing has only base spells")
	check(c.search("","Runes").all(func(k): return WikiCatalog.rune_listed(c.entries[k].value)),"rune browsing excludes editor records")
	for key: String in c.search("","Items"):
		if c._fixed.has(c.entries[key].value): check(c.variants_for(key).size()==1,"fixed item has no material or blueprint choices")
	for type: String in WikiCatalog.ITEM_TYPES:
		check(c.search("","Items",type).all(func(k): return WikiCatalog.item_subcategory(c.entries[k].value)==type),"item subcategory "+type)
	var spell := "fire_arrow"
	if not c.entries.has("spell/"+spell): spell = c.entries[c.search("","Spells")[0]].value
	panel.navigate("spell/"+spell); await frames()
	var rune := ""
	for i in panel._runes.item_count:
		if String(panel._runes.get_item_metadata(i)).begins_with("e"):
			panel._runes.select(i); rune = panel._runes.get_item_metadata(i); break
	check(not rune.is_empty(),"power rune available")
	panel._with_rune(); await frames()
	check(panel._runes.get_item_metadata(panel._runes.selected)==rune,"adding a rune preserves selected rune")
	check(panel._rune_preview.item != null and panel._rune_preview.item.item == "rune:"+rune,"selected rune shows original artwork")
	var built := String(c.entries[panel.current].value)
	check(Spells.mods_of(built).size()==1,"one rune added")
	panel._with_rune(); await frames()
	check(Spells.mods_of(c.entries[panel.current].value).size()==2,"same rune can be added repeatedly")
	var key := ""; var version := ""; var enchant := ""
	for candidate: String in c.search("","Items"):
		if not c.craftable(candidate): continue
		for id: String in c.variants_for(candidate):
			if id.begins_with("bp:"): continue
			for s: String in c.search("","Spells"):
				var magic := Spells.with_mod(c.entries[s].value,"it")
				if Items.can_enchant(id,magic): key=candidate;version=id;enchant=magic;break
			if key: break
		if key: break
	check(not key.is_empty(),"real enchantable material/item found")
	if key:
		var result := c.construct_item(key,version,enchant)
		check(result==version+"|"+enchant,"item constructor uses native enchantment admission")
		panel.navigate(key,true,result); await frames()
		check(panel._selected_versions[key]==result and panel._preview.item.item==result,"constructed item updates actual preview")
		check(WikiCatalog.num(Items.price(result)) in panel.html,"constructed item value is native calculated value")
		check(c.construct_item(key,version,"invalid_spell").is_empty(),"invalid enchantment rejected")
	var oracle := c.constructor_data(); var cases := []
	for code: String in oracle.spells:
		for rune_code: String in oracle.runes:
			var candidate := Spells.with_mod(code,rune_code)
			if not c.add_variant(candidate).is_empty(): cases.append({"code":code,"runes":[rune_code],"expected":spell_values(candidate)})
		# Repeated and mixed runes exercise cumulative clamps, whole-tick
		# duration changes and the eight-rune limit, not just a single fold.
		var mixed := code
		for i in Spells.MAX_MODS:
			for rune_code: String in oracle.runes:
				if c.rune_fits(mixed,rune_code):
					mixed = Spells.with_mod(mixed,rune_code)
					break
			cases.append({"code":code,"runes":Array(Spells.mods_of(mixed)),"expected":spell_values(mixed)})
	var item_cases := []; var tested_types := {}
	for item_key: String in c.search("","Items"):
		if not c.craftable(item_key): continue
		var subtype := WikiCatalog.item_subcategory(c.entries[item_key].value)
		if tested_types.has(subtype): continue
		tested_types[subtype] = true
		var choices := c.variants_for(item_key).filter(func(id): return not id.begins_with("bp:"))
		for item: String in [choices[0],choices[-1]]:
			var inputs := c.item_builder_data(item)
			item_cases.append({"item":inputs,"code":"","runes":[],"valid":true,"price":Items.price(item),"construction":Items.constr_piece_price(item)})
			for code: String in oracle.spells:
				for mods: Array in [[],["it"],["ic"]]:
					var magic := code + "{" + ";".join(mods) + "}"
					var valid := Items.can_enchant(item,magic)
					item_cases.append({"item":inputs,"code":code,"runes":mods,"valid":valid,"price":Items.price(item+"|"+magic),"construction":Items.constr_piece_price(item+"|"+magic)})
	FileAccess.open("user://constructor-oracles.json",FileAccess.WRITE).store_string(JSON.stringify({"data":oracle,"cases":cases,"items":item_cases}))
	if DisplayServer.get_name()!="headless":
		GameData._window_gen += 1
		get_tree().root.mode=Window.MODE_WINDOWED
		get_tree().root.size=Vector2i(1280,720); await frames(20)
		get_viewport().get_texture().get_image().save_png("user://wiki-features-item.png")
		panel.navigate("map/"+c._campaign.zone_by_map("zone1").id); await frames(20)
		get_viewport().get_texture().get_image().save_png("user://wiki-features-map.png")
	panel.close(); panel.queue_free(); await frames()
	var language := RemakeText.lang
	for locale: String in ["en","ru","de"]:
		RemakeText.lang = locale
		source.read(func():
			var translated := WikiCatalog.new(); translated.rebuild()
			var cyrillic := RegEx.create_from_string("[А-Яа-яЁё]")
			for id: String in translated.ordered:
				if locale != "ru": check(cyrillic.search(translated.page(id).html)==null,"localized expansion article "+locale+":"+id)
			for id: String in translated.search("","Maps"):
				check(not translated.entries[id].title.begins_with("Location "),"only authored named maps listed")
			GameData._text_cache["quest q1g"] = "Edited quest\nCustom summary"
			check(WikiWorldText.text("quest q1g")=="Edited quest\nCustom summary","world translation preserves edited source")
			GameData._text_cache["spell arrow"] = "Edited spell"
			WikiReferenceText.apply()
			check(GameData.text("spell arrow")=="Edited spell","reference translation preserves edited source"))
	RemakeText.lang = language
	check(FileAccess.get_file_as_bytes(GameData.CONFIG_PATH)==settings_before,"wiki browsing does not write settings")
	check(GameData.db==original.data.db and hash(GameData.db.tables)==hash_before,"constructors leave live database unchanged")
	TexUpscale.shutdown()
	print("WIKI_FEATURES ",JSON.stringify({"checks":checks,"failures":failures,"oracle_cases":cases.size(),"item_cases":item_cases.size()}))
	get_tree().quit(1 if failures else 0)

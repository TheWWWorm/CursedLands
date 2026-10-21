extends "../export_wiki.gd"
## Native acceptance followed by the real standalone exporter, one locale per run.
func _ready() -> void:
	var language := "ru"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wiki-language="): language = arg.trim_prefix("--wiki-language=")
	RemakeText.lang = language
	GameData.options.confine_mouse = 0
	for i in 30: await get_tree().process_frame
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280,800)
	var panel := WikiPanel.new(); add_child(panel); panel.open()
	var key := WikiCatalog.item_key("spiked mace")
	panel.navigate(key)
	for i in 20: await get_tree().process_frame
	var expected: String = panel._source.read(func(): return WikiCatalog.authored_name("spiked mace.bronze"))
	assert(not expected.is_empty())
	assert(panel.catalog.entries[key].title == expected)
	assert(panel._page_title.text == expected)
	assert(get_viewport().get_texture().get_image().save_png("user://wiki-club-"+language+".png")==OK)
	FileAccess.open("user://wiki-club-"+language+".json",FileAccess.WRITE).store_string(JSON.stringify({"language":language,"key":key,"expected":expected,"native_article":panel._article.get_parsed_text()}))
	print("WIKI_NAMES_VISUAL ",language," 4 checks 0 failures ",expected)
	panel.close(); panel.queue_free()
	for i in 6: await get_tree().process_frame
	await super._ready()

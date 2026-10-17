extends Node
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
func frames() -> void:
	for i in 4: await get_tree().process_frame
func _ready() -> void:
	var original := hash(GameData.db.tables)
	var panel := WikiPanel.new(); add_child(panel)
	var start := Time.get_ticks_msec(); panel.open()
	var cold := Time.get_ticks_msec() - start
	await frames()
	var catalog := panel.catalog
	check(panel._results.item_count > 1000 and panel._results._buttons.size() < 40, "full search index uses only visible row Controls")
	for name: String in catalog._map_records:
		var reference := EIMob.load_bytes(GameData.read_file("maps/" + name + ".mob"))
		var cached: EIMob = catalog.map_records(name)
		check(cached.script_text == reference.script_text, "map script preserved " + name)
		var units := reference.objects.filter(func(o): return o.kind == "UNIT")
		check(units.size() == cached.objects.size(), "all unit records preserved " + name)
		for i in mini(units.size(), cached.objects.size()):
			for key: String in ["prototype", "name", "position", "quest_items", "quick_items"]:
				check(units[i].get(key) == cached.objects[i].get(key), "map unit field preserved " + name + ":" + str(i) + ":" + key)
	panel.dismiss()
	start = Time.get_ticks_msec(); panel.open()
	var warm := Time.get_ticks_msec() - start
	check(panel.catalog == catalog, "reopening retains unchanged catalog")
	check(warm < cold, "warm opening avoids catalog work")
	panel._results.get_v_scroll_bar().value = panel._results.get_v_scroll_bar().max_value
	await frames()
	check(panel._results._buttons.any(func(b): return b.visible and b.get_meta("index") == panel._results.item_count - 1), "last virtual result remains accessible")
	panel._query.text = "toad" if RemakeText.lang == "en" else "жаба" if RemakeText.lang == "ru" else "Kröte"
	panel._filter(); await frames()
	check(panel._matches.size() > 0 and panel._results.item_count == panel._matches.size(), "search filters full catalog")
	panel.navigate("creature/toadm2")
	check(not panel.html.contains(RemakeText.t("Pairs show Easy / Hard. A single value is the same on both difficulties.")), "redundant difficulty explanation removed")
	var revision := ModStore.data_revision
	ModStore.data_revision += 1
	panel.dismiss(); panel.open()
	check(panel.catalog != catalog, "in-place mod revision invalidates cache")
	ModStore.data_revision = revision
	check(hash(GameData.db.tables) == original, "reference never modifies native stats")
	FileAccess.open("user://wiki-performance.json", FileAccess.WRITE).store_string(JSON.stringify({"cold_ms": cold, "warm_ms": warm, "checks": checks, "failures": failures}))
	print("WIKI_PERFORMANCE cold=", cold, "ms warm=", warm, "ms ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

extends Node
## --tool=/absolute/path/tools/tests/wiki.gd with any supported installation.
## Real archives, every HTML article/link, calculated variants, model widgets,
## search/history, hostile text, and the owning menu's pause/load lifecycle.

var checks := 0
var failures: Array[String] = []
var counts := {}
var catalog: WikiCatalog
var panel: WikiPanel
var rendered := false


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)


func frames() -> void:
	for i in 6: await get_tree().process_frame


func _ready() -> void:
	rendered = DisplayServer.get_name() != "headless"
	if rendered:
		# Let GameData's three-frame startup placement finish, then resize the
		# root Window (DisplayServer alone leaves the old X11 viewport size).
		for i in 20: await get_tree().process_frame
		GameData._window_gen += 1
		get_tree().root.mode = Window.MODE_WINDOWED
		get_tree().root.borderless = false
		get_tree().root.size = Vector2i(1280, 720)
		await frames()
	var before := hash(GameData.db.tables)
	var started := Time.get_ticks_msec()
	catalog = WikiCatalog.new()
	catalog.rebuild()
	print("WIKI index ", catalog.ordered.size(), " pages in ", Time.get_ticks_msec() - started, " ms language=", RemakeText.lang)
	check(catalog.ordered.size() > 100, "real game catalogue")
	for category: String in WikiCatalog.CATEGORIES.slice(1):
		counts[category] = catalog.search("", category).size()
		check(counts[category] > 0, "category populated: " + category)
	for key: String in catalog.ordered:
		var page := catalog.page(key)
		check(not page.html.is_empty() and "<h1>" in page.html, "HTML article: " + key)
		var parser := XMLParser.new()
		var error := parser.open_buffer(String(page.html).to_utf8_buffer())
		if error == OK:
			error = parser.read()
			while error == OK:
				if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "a":
					var url := parser.get_named_attribute_value_safe("href")
					var destination := WikiHtml.key_from_url(url).get_slice("?", 0)
					check(destination.begins_with("category/") or catalog.entries.has(destination), "resolved link: " + url)
				error = parser.read()
		check(error == ERR_FILE_EOF, "well-formed HTML: " + key)
		check(not WikiHtml.to_bbcode(page.html).is_empty(), "HTML renders: " + key)
		if checks % 200 < 5: await get_tree().process_frame
	check(hash(GameData.db.tables) == before, "catalogue leaves gameplay databases unchanged")
	var safe := WikiHtml.to_bbcode('<article><h1>&lt;unsafe&gt; [url=https://example.invalid]bad[/url]</h1><script>bad-script</script><a href="file:///tmp/test">plain</a></article>')
	check(not "[url=https" in safe and not "bad-script" in safe and not "[url=file" in safe, "HTML and BBCode cannot execute or navigate externally")
	check("<unsafe>" in safe, "HTML entities decoded as readable text")
	check(WikiHtml.key_from_url("https://example.invalid").is_empty(), "external navigation blocked")
	check(WikiHtml.key_from_url("wiki://../bad").is_empty(), "path traversal blocked")
	var sample: Dictionary = catalog.entries[catalog.search("", "Items")[0]]
	check(catalog.search(sample.title).has(sample.key), "search finds localized item name")
	check(catalog.search("__no_such_wiki_title__").is_empty(), "empty search results")
	check(catalog.search("", "Spells").all(func(key): return catalog.entries[key].kind == "spell"), "category filter")
	data_change_checks()
	await ui_checks()
	await lifecycle_checks()
	if not OS.get_cmdline_user_args().has("--wiki-skip-menu"): await main_menu_checks()
	var result := {"checks": checks, "failures": failures, "language": RemakeText.lang, "campaign": GameData.campaign_id, "counts": counts, "rendered": rendered, "seconds": (Time.get_ticks_msec() - started) / 1000.0}
	var output := FileAccess.open("user://wiki-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("WIKI_RESULT ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)


func data_change_checks() -> void:
	var row: Dictionary = GameData.db.table("weapons")[0]
	var base := String(row.name).to_lower()
	var variant: String = catalog._families[base][0]
	var key := WikiCatalog.item_key(variant)
	var before: String = catalog.page(key).html
	var minimum: float = row.get("min_damage", 0.0)
	row.min_damage = minimum + 19.0
	var updated: String = catalog.page(key).html
	check(before != updated, "page reflects a live data-mod change")
	var bounds := Items.damage(variant)
	check(("%s–%s" % [WikiCatalog.num(bounds.x), WikiCatalog.num(bounds.y)]) in updated, "modified values use the actual gameplay builder")
	row.min_damage = minimum
	check(catalog.page(key).html == before, "data-mod fixture restores original data")
	var added := row.duplicate(true)
	added.name = "__wiki_custom_weapon"
	GameData.db.table("weapons").append(added)
	GameData.db.tables["weapons#index"][added.name] = added
	catalog.rebuild()
	var added_variant: String = catalog._families[added.name][0]
	check(catalog.entries.has(WikiCatalog.item_key(added_variant)), "new mod item is indexed without a wiki definition")
	check(not "__wiki_custom_weapon" in WikiCatalog.item_title(added_variant), "unnamed mod item never exposes its internal specification")
	GameData.db.table("weapons").pop_back()
	GameData.db.tables["weapons#index"].erase(added.name)
	Items._cache.clear()
	catalog.rebuild()


func ui_checks() -> void:
	panel = WikiPanel.new()
	add_child(panel)
	panel.open()
	await frames()
	check(panel.visible and panel.current == "home", "wiki opens at contents")
	check(panel._results.item_count <= WikiPanel.PAGE_SIZE, "search list is paginated")
	var samples := {}
	for key: String in catalog.ordered:
		var entry: Dictionary = catalog.entries[key]
		if entry.kind == "item":
			var value := catalog.variants_for(key)[0]
			var table := String(Items.info(value).table)
			if not samples.has(table):
				var look := Items.look(value)
				if not look.is_empty() and (not look.has("texture") or GameData.get_texture(look.texture) != null): samples[table] = key
	for table: String in ["weapons", "armors", "quick_items", "quest_items", "loot_items"]:
		if not samples.has(table): continue
		panel.navigate(samples[table])
		await frames()
		check(panel._preview.item != null and panel._preview.item._model != null, "real item model: " + table)
		if table == "weapons":
			var id := catalog.variants_for(samples[table])[0]
			var damage := Items.damage(id)
			check(("%s–%s" % [WikiCatalog.num(damage.x), WikiCatalog.num(damage.y)]) in panel.html, "weapon bounds use gameplay item builder")
			var orientation := panel._preview.item._model.quaternion
			panel._preview.turn_by(0.6)
			check(orientation.angle_to(panel._preview.item._model.quaternion) > 0.4, "item rotation")
			panel._preview.zoom_by(0.8)
			check(is_equal_approx(panel._preview._zoom, 0.8), "item zoom")
			panel._preview.reset_view()
			check(panel._preview._turn == 0.0 and panel._preview._zoom == 1.0, "model reset")
			var family := String(samples[table])
			var choices := panel.catalog.variants_for(family)
			check(catalog.search("", "Items").count(family) == 1, "one searchable page per weapon family")
			if choices.size() > 1:
				var history_size := panel._history.size()
				var version := choices[1]
				for button: Node in panel._versions.get_children():
					if button.get_meta("version") == version: button.pressed.emit()
				await frames()
				check(panel.current == family and panel._history.size() == history_size, "version button stays on the same page")
				check(panel._preview.item.item == version, "version button changes the live model")
				var changed_damage := Items.damage(version)
				check(("%s–%s" % [WikiCatalog.num(changed_damage.x), WikiCatalog.num(changed_damage.y)]) in panel.html, "version button recalculates weapon statistics")
			await capture("item")
	for category: String in ["Materials", "Items"]:
		for key: String in catalog.search("", category):
			var value := String(catalog.entries[key].value)
			if category == "Items":
				var choices := catalog.variants_for(key)
				if choices.is_empty() or not choices[-1].begins_with("bp:"): continue
				value = choices[-1]
			var look := Items.look(value)
			if look.is_empty() or (look.has("texture") and GameData.get_texture(look.texture) == null): continue
			panel.navigate(key, true, value)
			await frames()
			check(panel._preview.item != null and panel._preview.item._model != null, "real material/blueprint model: " + category)
			break
	var creature_key := ""
	for key: String in catalog.search("", "Creatures"):
		var row := GameData.db.find("monster_prototypes", catalog.entries[key].value)
		var race := GameData.db.find("race_models", String(row.get("base_race", "")))
		if not EIFigure.get_model(String(race.get("mask", "")).to_lower()).is_empty():
			creature_key = key
			break
	check(not creature_key.is_empty(), "creature model fixture from database")
	if creature_key:
		panel.navigate(creature_key)
		await frames()
		check(panel._preview.creature != null and panel._preview.creature._model != null, "real animated creature preview")
		check(panel._preview.item == null, "old item preview released")
		var q := panel._preview.creature._pivot.quaternion
		panel._preview.turn_by(0.6)
		check(q.angle_to(panel._preview.creature._pivot.quaternion) > 0.4, "creature rotation")
		check(panel._preview._creature_fitted, "creature framed before its first presented model")
		check(creature_in_frame(panel._preview.creature), "wide creature fits the model viewport after rotation")
		await capture("creature")
	var spell := ""
	var rune := ""
	for key: String in catalog.search("", "Spells"):
		var value := String(catalog.entries[key].value)
		if not Spells.mods_of(value).is_empty(): continue
		for row: Dictionary in GameData.db.table("spell_modifiers"):
			if Spells.can_add(value, row.code) and String(row.code).begins_with("e"):
				spell = value
				rune = row.code
				break
		if spell: break
	check(not spell.is_empty(), "real compatible spell/rune")
	if spell:
		panel.navigate("spell/" + spell.uri_encode())
		await frames()
		check(panel._builder.visible and not panel._add_rune.disabled, "spell builder controls visible")
		for index in panel._runes.item_count:
			if panel._runes.get_item_metadata(index) == rune: panel._runes.select(index)
		panel._add_rune.pressed.emit()
		await frames()
		var built := Spells.with_mod(spell, rune)
		check(panel.catalog.entries[panel.current].value == built, "rune button builds actual variant")
		check(WikiCatalog.num(Spells.parse(built).effect) in panel.html, "spell variant power from gameplay parser")
		check(Spells.parse(built).effect != Spells.parse(spell).effect, "effect rune changes power")
		await capture("spell")
		panel._reset_spell.pressed.emit()
		check(panel.catalog.entries[panel.current].value == spell, "reset spell button")
		await panel.history(-1)
		check(panel.catalog.entries[panel.current].value == built, "back navigation")
		await panel.history(1)
		check(panel.catalog.entries[panel.current].value == spell, "forward navigation")
	panel.follow_link("wiki://category/Materials")
	check(panel._category.selected == WikiCatalog.CATEGORIES.find("Materials") and panel._matches.size() == counts.Materials, "contents category link")
	check(panel.pad_targets().size() > 5, "controller search, navigation and page targets")
	panel._query.text = "__no_such_wiki_title__"
	panel._query.text_changed.emit(panel._query.text)
	check(panel._results.item_count == 0 and panel._status.text == RemakeText.t("No matching pages"), "visible empty search state")
	panel.catalog.rules = {"armor_formula": 1}
	panel.navigate("mechanics/armor")
	check(RemakeText.t("At least 20% of each incoming damage type passes through armor.") in panel._article.get_parsed_text(), "active mod armor rule explained")
	await capture("armor")
	panel.catalog.rules = {"armor_formula": 0}
	panel.navigate("mechanics/armor")
	check(RemakeText.t("Armor can absorb damage completely.") in panel._article.get_parsed_text(), "original armor rule explained")
	panel._query.text = ""
	panel._category.select(0)
	panel._filter()
	for size in [Vector2i(1280, 720), Vector2i(800, 600), Vector2i(480, 800)]:
		get_tree().root.size = size
		await frames()
		check(panel.get_global_rect().end.x <= size.x + 1 and panel.get_global_rect().end.y <= size.y + 1, "panel fits viewport: " + str(size))
		check(panel._article.size.x > 80 and panel._article.size.y >= 65, "readable article: " + str(size))
		await capture("layout-%dx%d" % [size.x, size.y])
		if samples.has("weapons"):
			panel.navigate(samples.weapons)
			await frames()
			check(panel._preview.get_global_rect().end.x <= size.x + 1 and panel._preview.get_global_rect().end.y <= size.y + 1, "model fits viewport: " + str(size))
			await capture("model-%dx%d" % [size.x, size.y])
		panel.navigate("mechanics/armor")
	get_tree().root.size = Vector2i(1280, 720)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape)
	await frames()
	check(not panel.visible and panel._preview.get_child_count() == 0, "close releases live preview")
	panel.queue_free()
	await frames()


func creature_in_frame(doll: Paperdoll) -> bool:
	var rect := Rect2(Vector2.ZERO, Vector2(doll._vp.size)).grow(2.0)
	for mesh: MeshInstance3D in doll._model.find_children("*", "MeshInstance3D", true, false):
		if not doll._shown_part(mesh): continue
		for i in 8:
			var point: Vector3 = mesh.global_transform * mesh.get_aabb().get_endpoint(i)
			if not rect.has_point(doll._cam.unproject_position(point)):
				print("WIKI_FRAME ", doll._info, " viewport=", doll._vp.size, " control=", doll.size, " camera=", doll._cam.position, " point=", point, " screen=", doll._cam.unproject_position(point))
				return false
	return true


func lifecycle_checks() -> void:
	# Owning HUD with no map: verifies the real modal/pause path without
	# changing player settings, loading a save or starting a local worker.
	var session := Session.new()
	add_child(session)
	var game := Game.new()
	game.session = session
	session.game = game
	add_child(game)
	await frames()
	var hud := game.hud
	check(hud != null, "actual HUD exists")
	if hud:
		get_tree().paused = false
		hud.open_wiki()
		check(hud._wiki.visible and get_tree().paused, "wiki pauses single player through menu")
		hud._wiki.close()
		check(not hud._esc_open and not get_tree().paused, "wiki close restores unpaused state")
		get_tree().paused = true
		hud.open_wiki()
		hud._wiki.close()
		check(get_tree().paused, "wiki preserves an existing pause")
		get_tree().paused = false
		hud.open_wiki()
		hud._close_for_host_load()
		check(not hud._wiki.visible and not hud._esc_open and not get_tree().paused, "host load dismisses wiki and restores pause")
		session.online = true
		hud.open_wiki()
		check(hud._wiki.visible and not get_tree().paused and hud.blocks_input(), "co-op wiki blocks local gameplay input without pausing the world")
		hud._wiki.close()
		session.online = false
	game.queue_free()
	session.queue_free()
	await frames()


func main_menu_checks() -> void:
	var menu: Control = load("res://src/ui/main_menu.gd").new()
	menu.detect_graphics = false
	add_child(menu)
	await frames()
	check(menu._wiki_button.is_visible_in_tree(), "main menu wiki entry visible")
	menu._wiki_button.pressed.emit()
	await frames()
	check(menu._wiki.visible and not menu.pad_menu_free(), "main menu opens wiki as a modal")
	menu._wiki.close()
	await frames()
	check(not menu._wiki.visible and menu.pad_menu_free(), "main menu wiki closes")
	menu.queue_free()
	await frames()


func capture(label: String) -> void:
	if not rendered: return
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://wiki-%s-%s.png" % [RemakeText.lang, label])

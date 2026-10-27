extends Node
## Rendered wiki pages for an unused face and an unused item model in
## EN/RU/DE at 720p, 1440p and 4K: localized title, a built preview model,
## and native-resolution captures (user://wiki-cut-<lang>-<h>-<page>.png).
var checks := 0
var failures := 0
const SIZES := [Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const PAGES := {"face": "cut/face/unhufe_13", "item": "cut/item/initqi36item"}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func frames(count := 8) -> void:
	for i in count: await get_tree().process_frame

func dimensions(value: Vector2i) -> void:
	GameData._window_gen += 1
	get_window().wrap_controls = false
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size = value
	get_window().size = value
	await frames(8)

func _ready() -> void:
	GameData.options.merge({"auto_graphics": 0, "display_mode": 0, "confine_mouse": 0}, true)
	get_window().mode = Window.MODE_WINDOWED
	get_window().borderless = true
	await frames(20)
	for lang: String in ["en", "ru", "de"]:
		RemakeText.lang = lang
		var panel := WikiPanel.new()
		add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.open()
		for size: Vector2i in SIZES:
			await dimensions(size)
			for page: String in PAGES:
				var key: String = PAGES[page]
				var tag := "%s %dx%d %s" % [lang, size.x, size.y, page]
				panel.navigate(key)
				await frames(20)
				var title: String = panel.catalog.entries.get(key, {}).get("title", "")
				var english := "Unused female face 4" if page == "face" else "Crowbar (variant 1)"
				check(not title.is_empty() and (lang == "en") == (title == english), tag + ": localized title " + title)
				check(panel._page_title.text == title, tag + ": the page heading shows the title")
				var preview := panel._preview
				var built: Node = preview.creature._model if page == "face" and is_instance_valid(preview.creature) \
					else (preview.item._model if is_instance_valid(preview.item) else null)
				check(built != null and not built.find_children("*", "MeshInstance3D", true, false).is_empty(), tag + ": preview model built")
				check(preview.is_visible_in_tree() and preview.size.x >= 120 * size.y / 720.0, tag + ": preview is visible and scaled: " + str(preview.size))
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					var shot := get_viewport().get_texture().get_image()
					check(shot.get_size() == size, tag + ": native-resolution capture")
					shot.save_png("user://wiki-cut-%s-%d-%s.png" % [lang, size.y, page])
		panel.close()
		panel.queue_free()
		await frames(4)
	RemakeText.lang = "en"
	TexUpscale.shutdown()
	print("WIKI_CUT_FACES_ITEMS_UI ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)

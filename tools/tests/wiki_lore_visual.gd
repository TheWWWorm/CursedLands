extends Node
## Rendered acceptance captures of the shared lore presentation in EN/RU/DE.
func frames(count := 8) -> void:
	for i in count: await get_tree().process_frame

func _ready() -> void:
	var directory := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wiki-capture="): directory = arg.trim_prefix("--wiki-capture=")
		if arg.begins_with("--wiki-language="): RemakeText.lang = arg.trim_prefix("--wiki-language=")
	assert(not directory.is_empty() and DisplayServer.get_name() != "headless")
	DirAccess.make_dir_recursive_absolute(directory)
	GameData.options.confine_mouse = 0
	await frames(30)
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	var language := RemakeText.lang
	var panel := WikiPanel.new()
	add_child(panel)
	panel.open()
	get_tree().root.size = Vector2i(1440,900)
	await frames(18)
	for key: String in ["character/hero", "character/witch", "allod/gipat", "home"]:
		panel.navigate(key)
		await frames(20)
		assert(panel._article.size.x > 300)
		get_viewport().get_texture().get_image().save_png(directory.path_join(language + "-" + key.replace("/", "-") + ".png"))
	var map_key := "map/bz1g" if GameData.campaign_id == CampaignProfile.ORIGINAL else "map/bz2h"
	panel.navigate(map_key)
	await frames()
	assert(panel._preview.scene_view == null) # No terrain load just to read prose.
	assert(panel._preview._descriptor.kind == "scene")
	get_viewport().get_texture().get_image().save_png(directory.path_join(language + "-location.png"))
	var data_root := GameData.root
	var database := hash(GameData.db.tables)
	panel._preview.scene_requested.emit()
	await frames(15)
	assert(panel._preview.scene_view != null and panel._preview.scene_view.model != null)
	assert(GameData.root == data_root and hash(GameData.db.tables) == database)
	get_viewport().get_texture().get_image().save_png(directory.path_join(language + "-location-loaded.png"))
	get_tree().root.size = Vector2i(480,800)
	panel.navigate("character/hero")
	await frames(18)
	get_viewport().get_texture().get_image().save_png(directory.path_join(language + "-phone.png"))
	if panel._sidebar.visible or panel._article.size.y <= 300 or panel.get_rect().end.x > 480 or panel.get_rect().end.y > 800:
		printerr("FAIL compact lore layout ", get_tree().root.size, " ", panel._article.size)
		get_tree().quit(1)
		return
	panel._preview_toggle.pressed.emit()
	await frames(12)
	assert(panel._preview_box.visible and not panel._article_column.visible)
	get_viewport().get_texture().get_image().save_png(directory.path_join(language + "-phone-portrait.png"))
	panel.close()
	panel.queue_free()
	await frames()
	TexUpscale.shutdown()
	print("WIKI_LORE_VISUAL ", GameData.campaign_id, " ", language)
	get_tree().quit()

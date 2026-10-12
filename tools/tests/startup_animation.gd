extends Node
var frames := {}
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func presented() -> void:
	for child in get_parent().get_children():
		if child is StartupScreen and not frames.has(child._decoded):
			frames[child._decoded] = hash(child._y.get_image().get_data())
			if child._decoded in [0,6,11]:get_viewport().get_texture().get_image().save_png("user://startup-%d.png"%child._decoded)
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"display_mode":0},true)
	RenderingServer.set_render_loop_enabled(true)
	RenderingServer.frame_post_draw.connect(presented)
	var menu:Control = await get_parent().open_menu()
	RenderingServer.frame_post_draw.disconnect(presented)
	check(frames.size()==12,"real launch path presents all twelve stages")
	check(frames.size()>1 and frames.values()[0]!=frames.values()[-1],"letters change between first and last image")
	await get_tree().process_frame
	check(not get_parent().get_children().any(func(c):return c is StartupScreen),"startup relinquishes menu and input")
	check(menu._mods_button.is_visible_in_tree(),"main menu exposes Mods directly")
	await menu._on_board("mods")
	check(menu._mods.visible and menu._mods._page=="mods" and not menu.pad_menu_free(),"main menu action opens Mods and blocks signpost input")
	menu._mods.close()
	check(menu.pad_menu_free(),"closing Mods restores main menu")
	for i in 5:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://main-menu-mods.png")
	menu.queue_free();await get_tree().process_frame
	print("STARTUP_ANIMATION ",JSON.stringify({"checks":checks,"failures":failures,"stages":frames}));TexUpscale.shutdown();get_tree().quit(1 if failures else 0)

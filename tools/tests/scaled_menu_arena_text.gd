extends "arena_expansion_ui.gd"
const MainMenu = preload("res://src/ui/main_menu.gd")

func _ready() -> void:
	await frames(24)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"vsync":0,"pad_enabled":0},true)
	GameData._window_gen += 1
	get_window().mode=Window.MODE_WINDOWED
	var lang := "ru"
	var dimensions := Vector2i(2560,1440)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--text-ui="):
			var spec := arg.get_slice("=",1).split(",")
			lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	get_window().size=dimensions; RemakeText.lang=lang; await frames(6)
	var menu := MainMenu.new();menu.detect_graphics=false;add_child(menu);await frames(16)
	check(menu.oversampling_with_scale==CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED,"menu scales glyph rasterization with controls")
	for button: Button in menu._campaigns.buttons.values()+[menu._mods_button,menu._arena_pve_button]:
		bounded(button,"menu choice")
		for line in button.text.split("\n"):
			check(button.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x < button.size.x-20,"localized choice fits")
	await shot("text-menu-"+lang)
	# Same live layout, with only glyph sampling changed, for a reviewable A/B.
	menu.oversampling_with_scale=CanvasItem.OVERSAMPLING_WITH_SCALE_DISABLED
	await shot("text-menu-legacy-"+lang)
	menu.queue_free();await frames(8)
	GameData.arena_mode=0
	screen=ArenaPveScreen.new();add_child(screen);await frames(8)
	screen._seed_input.text="7191";screen._begin();screen.run.auto_save=false
	screen.run.gold=3;screen._refresh();await frames(8)
	check(screen.oversampling_with_scale==CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED,"arena scales glyph rasterization with controls")
	check(screen.theme.default_font.oversampling==0,"arena font allows per-control sampling")
	check(screen.theme.default_font.multichannel_signed_distance_field and screen._heading_font.multichannel_signed_distance_field,"scaled arena text uses stable distance-field glyphs")
	for label: Label in [screen._gold,screen._income,screen._lives]:
		bounded(label,"arena status")
		check(label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x<=label.size.x+1,"localized status fits")
	await shot("text-arena-"+lang)
	screen._show_menu();await frames()
	for button: Button in screen._modal_box.find_children("*","Button",true,false):
		bounded(button,"arena menu button")
		check(button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x<button.size.x-16,"translated modal button fits")
	await shot("text-arena-modal-"+lang)
	screen._close_modal()
	screen.oversampling_with_scale=CanvasItem.OVERSAMPLING_WITH_SCALE_DISABLED
	screen.theme.default_font.oversampling=maxf(1,screen._ui_scale)
	screen._heading_font.oversampling=maxf(1,screen._ui_scale)
	await shot("text-arena-legacy-"+lang)
	screen.queue_free();screen=null;await frames(8)
	print("SCALED_TEXT ",JSON.stringify({"language":lang,"checks":checks,"failures":failures}))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)

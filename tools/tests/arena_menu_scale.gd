extends "arena_expansion_ui.gd"
const MainMenu=preload("res://src/ui/main_menu.gd")
func _ready()->void:
	OS.add_logger(errors);await frames(24)
	GameData._window_gen+=1;GameData.options.confine_mouse=0
	var dimensions:=Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec:=arg.get_slice("=",1).split(",");RemakeText.lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	get_window().mode=Window.MODE_WINDOWED;get_window().size=dimensions;get_window().position=Vector2i.ZERO
	await frames(8)
	var menu:=MainMenu.new();menu.detect_graphics=false;add_child(menu);await frames(24)
	var top:Button=menu._campaigns.buttons[CampaignProfile.ORIGINAL]
	for button in [menu._mods_button,menu._wiki_button,menu._arena_pve_button]:
		bounded(button,"footer action")
		check(button.get_global_rect().size.y>=top.get_global_rect().size.y-1,"footer action is as tall as campaign actions")
		check(button.get_global_rect().position.y>dimensions.y*0.8,"footer action stays at bottom")
		check(button.get_global_rect().size.y>=64*minf(dimensions.x/1280.0,dimensions.y/800.0)-1,"footer action scales with display")
	await shot("menu-scale-%s-%d"%[RemakeText.lang,dimensions.x])
	check(errors.messages.is_empty(),"menu has no runtime errors: "+JSON.stringify(errors.messages.slice(0,3)))
	print("ARENA_MENU_SCALE checks=",checks," failures=",JSON.stringify(failures));OS.remove_logger(errors);get_tree().quit(0 if failures.is_empty() else 1)

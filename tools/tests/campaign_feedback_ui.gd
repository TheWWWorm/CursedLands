extends "arena_expansion_ui.gd"
func _ready()->void:
	await frames(24)
	var lang:="en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-lang="):lang=arg.get_slice("=",1)
	RemakeText.lang=lang
	GameData.options.merge({"show_tutorial":0,"auto_graphics":0,"confine_mouse":0,"net_lan":0,"net_upnp":0,"net_directory":0,"gfx_hd_textures":0},true)
	GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,800);get_window().position=Vector2i.ZERO
	var session:=Session.new();add_child(session);session.set_physics_process(false)
	var quests:=ZoneObjectives.new();quests.setup(session,"gz17h",[],true,"field");add_child(quests)
	await frames(12)
	check(quests._pic!=null and not quests._title.is_empty() and not quests._zone_desc.get_parsed_text().is_empty(),"native map and description are populated")
	check(quests.find_children("*","LinkButton",true,false).is_empty(),"no low-resolution standalone journal links")
	await move(quests.get_global_transform_with_canvas()*quests._r(Rect2(420,30,320,485)).get_center())
	check(quests.wiki_context().get("key","")=="map/gz17h","map exposes the context wiki shortcut")
	await shot("campaign-journal-"+lang)
	quests.queue_free();await frames(2)
	if GameData.REMAKE_OPTIONS.has("selection_glow"):
		var panel:=OptionsPanel.new();add_child(panel);panel.open();panel._show_group(24);panel._sel=8;await frames(8)
		check(panel._rows[8].name=="selection_glow" and panel._rows[8].label==RemakeText.t("Selection glow"),"localized selection glow setting")
		check(panel._rows[8].get("choices",[])==RemakeText.tl(["Auto","Off","On"]),"localized glow choices")
		check(panel._rows[8].tip.contains(RemakeText.t(GameData.REMAKE_OPTIONS.selection_glow[1])),"localized glow help")
		await shot("selection-glow-"+lang)
		panel._restore();panel._close();panel.queue_free()
	session.queue_free();await frames(3)
	print("CAMPAIGN_FEEDBACK_UI ",lang," ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

extends "arena_expansion_ui.gd"
func _ready()->void:
	await frames(12)
	for lang in ["en","ru","de"]:
		RemakeText.lang=lang
		var parent_cursor:=GameCursor.new();add_child(parent_cursor);parent_cursor.set_kind("cursor_default")
		var cursor:=GameCursor.new();cursor.control_shapes=[Input.CURSOR_ARROW,Input.CURSOR_POINTING_HAND];add_child(cursor);cursor.set_kind("cursor_default")
		check(GameCursor._owner==cursor,"new screen owns game cursor")
		cursor.queue_free();await frames(2)
		check(GameCursor._owner==parent_cursor,"closing screen restores parent's game cursor")
		var dialog:=PlayerProfileDialog.new();add_child(dialog);dialog.open();await frames(4)
		if DisplayServer.get_name()!="headless":bounded(dialog._surface,"localized profile surface")
		dialog.name_edit.text="Wanderer_Игрок_Ä"
		dialog._save();await frames(2)
		var settings:=ConfigFile.new();settings.load("user://settings.cfg")
		check(settings.get_value("player","name","")=="Wanderer_Игрок_Ä","global name persists in settings")
		check(GameData.player_name=="Wanderer_Игрок_Ä","global name updates")
		var panel:=NetworkPanel.new();add_child(panel);panel.open()
		check(panel.player_name==GameData.player_name,"campaign multiplayer prefills global name")
		var arena:=ArenaOnlinePanel.new();add_child(arena);arena.open()
		check(arena.player_name==GameData.player_name,"autochess lobby prefills global name")
		var run:=ArenaTournamentRun.new();run.auto_save=false;run.begin(19)
		check(run.player_title(0)==GameData.player_name,"solo standings use global name")
		panel.queue_free();arena.queue_free();parent_cursor.queue_free();await frames(2)
	print("PLAYER_PROFILE ",checks," checks; failures=",JSON.stringify(failures))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)

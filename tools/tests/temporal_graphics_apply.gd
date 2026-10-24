extends "startup_graphics_recovery.gd"
## Apply through the real Screen panel and verify persistence/restart prompts.
var restarts := 0

func _run() -> void:
	var facts := RtxGraphics.facts()
	if not facts.engine or not facts.api:
		get_tree().quit(2)
		return
	RendererChoice.on_restart = func(): restarts += 1
	for language: String in ["en", "ru", "de"]:
		RemakeText.lang = language
		GameData.options.merge({"rtx_upscaling":2 if facts.launch else 0,"rtx_frame_generation":0,
			"fsr_upscaling":0,"fsr_frame_generation":0,"auto_graphics":0},true)
		GameData.save_settings()
		var panel := OptionsPanel.new()
		panel.game_files = true
		get_parent().add_child(panel)
		panel.open()
		panel._show_group(OptionsPanel.SCREEN_GROUP)
		await settle()
		var before := FileAccess.get_file_as_bytes(GameData.CONFIG_PATH)
		panel._screen_pickers["q_aa"].item_selected.emit(0 if facts.launch else 8)
		if not facts.launch:
			panel._screen_pickers[FsrGraphics.QUALITY].item_selected.emit(2)
		check(FileAccess.get_file_as_bytes(GameData.CONFIG_PATH) == before,"selection waits for Apply")
		panel._apply()
		await settle()
		var saved := ConfigFile.new()
		check(saved.load(GameData.CONFIG_PATH) == OK,"Apply saves settings")
		check(int(saved.get_value("options","rtx_upscaling",-1)) == (0 if facts.launch else 3),"Apply persists the chosen NVIDIA owner and quality")
		check(int(saved.get_value("options","fsr_upscaling",-1)) == 0 and int(saved.get_value("options","fsr_frame_generation",-1)) == 0,"saved SDK requests remain exclusive")
		var boxes := get_parent().find_children("*","MessageBox",true,false)
		check(boxes.size() == 1,"owner switch asks for restart exactly once")
		if boxes.size() == 1:
			var box: MessageBox = boxes[0]
			check(box.message == RemakeText.t("The graphics technology changes after restarting. Restart the game now?"),"restart prompt names the graphics technology")
			get_viewport().get_texture().get_image().save_png("user://temporal-restart-"+language+".png")
			var count := restarts
			answer(box,false)
			await settle()
			check(restarts == count,"Later keeps the game running")
			check(int(GameData.option(RtxGraphics.UPSCALING)) == (0 if facts.launch else 3),"Later retains the saved choice for next startup")
		panel._apply()
		await settle()
		boxes = get_parent().find_children("*","MessageBox",true,false)
		if boxes.size() == 1:
			var count := restarts
			answer(boxes[0],true)
			await settle()
			check(restarts == count + 1,"Restart invokes the existing restart action")
		else:
			check(false,"restart remains available after postponing")
		panel.queue_free()
		await settle()
	check(not RendererChoice.restart_args().has("--experimental-rtx"),"normal restart needs no NVIDIA launcher switch")
	RendererChoice.on_restart = Callable()
	var result := {"checks":checks,"failures":failures,"nvidia_session":facts.launch,"restart_actions":restarts}
	FileAccess.open("user://temporal-apply.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("TEMPORAL_APPLY ",JSON.stringify(result))
	get_tree().quit(1 if failures else 0)

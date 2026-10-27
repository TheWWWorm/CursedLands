extends Node
## The name typed on the multiplayer screens (co-op and autochess) is the
## device's player name as soon as the field is left, the screen goes Back or
## hides, or the window closes. It used to be saved only when a game was hosted
## or joined: a name typed before Back still showed for the rest of the session
## but settings.cfg kept "Player", so the next start (typically a new version)
## showed "Player" again.
var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)


func saved_name() -> String:
	var cfg := ConfigFile.new()
	return String(cfg.get_value("player", "name", "")) if cfg.load(GameData.CONFIG_PATH) == OK else ""


func type(panel: NetworkPanel, text: String, clear := true) -> void:
	panel._focus = "name"
	if clear:
		for i in panel.player_name.length(): panel._type("", true)
	for c in text: panel._type(c)


## Every way off the field, on each multiplayer screen.
func screen(label: String, panel: NetworkPanel, page: int) -> void:
	GameData.player_name = "Saved"; GameData.save_settings()
	add_child(panel)
	panel.visible = false   # created hidden: nothing typed yet, nothing to save
	check(GameData.player_name == "Saved" and saved_name() == "Saved", label + ": a hidden, unopened screen keeps the saved name")
	panel.open(); panel.show_page(page)
	check(panel._row_on("name"), label + ": the name row can be edited")
	check(panel.player_name == "Saved", label + ": the screen opens with the saved name")
	panel.go_back()
	check(saved_name() == "Saved", label + ": Back without typing keeps the name")

	panel.open(); panel.show_page(page)
	type(panel, "Атм Тест")
	panel.go_back()   # leaves the field, then the page
	check(GameData.player_name == "Атм Тест", label + ": Back keeps the typed name for this session")
	check(saved_name() == "Атм Тест", label + ": Back saves the typed name for the next start")

	panel.open(); panel.show_page(page)
	check(panel.player_name == "Атм Тест", label + ": reopening shows the saved name")
	type(panel, "Atm2")
	panel._focus = "addr"   # click into another field
	check(saved_name() == "Atm2", label + ": leaving the field saves the name")

	panel.open(); panel.show_page(page)
	type(panel, "Atm3")
	panel.visible = false   # the screen closes without Back
	check(saved_name() == "Atm3", label + ": hiding the screen saves the name")

	panel.visible = true; panel.open(); panel.show_page(page)
	type(panel, "Atm4")
	panel.notification(NOTIFICATION_WM_CLOSE_REQUEST)   # the window is closed while typing
	check(saved_name() == "Atm4", label + ": closing the window saves the name")

	panel.open(); panel.show_page(page)
	type(panel, "")
	panel.go_back()
	check(GameData.player_name == "Atm4" and saved_name() == "Atm4", label + ": an emptied field keeps the last name")

	panel.open(); panel.show_page(page)
	type(panel, "  Spaced\u0007 ")
	panel.go_back()
	check(saved_name() == ArenaOnlineSession.clean_name("  Spaced\u0007 ") and saved_name() == "Spaced", label + ": the saved name is cleaned as hosting and joining clean it")
	panel.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	var keep := GameData.player_name
	await screen("co-op join", NetworkPanel.new(), NetworkPanel.JOIN_COOP)
	await screen("co-op host", NetworkPanel.new(), NetworkPanel.HOST_COOP)
	await screen("autochess", ArenaOnlinePanel.new(), NetworkPanel.JOIN_COOP)
	# The stored name is what a fresh start reads (GameData._ready).
	var cfg := ConfigFile.new(); cfg.load(GameData.CONFIG_PATH)
	check(cfg.get_value("player", "name", "Player") == "Spaced", "a new start reads the last saved name")
	GameData.player_name = keep; GameData.save_settings()
	print("NETWORK_NAME_PERSISTS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)

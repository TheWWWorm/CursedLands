extends Node
## Navigate the real settings screen, choose third person, accept and reopen.
var checks := 0
var failures := 0
var panel: OptionsPanel

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame

func click(at: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		event.position = panel._origin() + at * panel.kv()
		panel._gui_input(event)

func camera_page() -> void:
	click(Vector2(175, 168 + 24 * OptionsPanel.TAB_ORDER.find(OptionsPanel.REMAKE_GROUP)))
	click(Vector2(340, 168 + 24 * OptionsPanel.SECTIONS.find(OptionsPanel.CAMERA_GROUP)))
	check(panel._group == OptionsPanel.CAMERA_GROUP, "mouse navigation opens Remake / Camera")

func mode_row() -> int:
	for row: int in panel._rows:
		if panel._rows[row].name == "control_mode": return row
	return -1

func _ready() -> void:
	GameData.options.merge({"show_tutorial":0, "auto_graphics":0, "control_mode":0}, true)
	panel = OptionsPanel.new(); add_child(panel)
	panel.open(); await frames(); camera_page()
	var row := mode_row()
	check(row >= 0, "control-mode selector is visible alongside camera key bindings")
	for name: String in ["camera_rotate_left", "camera_rotate_right"]:
		check(panel._rows.values().any(func(r): return r.name == name and r.kind == "keys"), name + " remains rebindable")
	if row >= 0:
		click(Vector2(590, 168 + 24 * row)); click(Vector2(590, 168 + 24 * row))
		check(panel._values.control_mode == 2, "mouse selects the third-person choice")
	if DisplayServer.get_name() != "headless":
		await frames(); await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://control-mode-options.png")
		print("OPTIONS_IMAGE ", ProjectSettings.globalize_path("user://control-mode-options.png"))
	click(Vector2(250, 550))
	check(not panel.visible and GameData.option("control_mode") == 2, "accept applies third-person controls")
	var cfg := ConfigFile.new()
	check(cfg.load(GameData.CONFIG_PATH) == OK and cfg.get_value("options", "control_mode", -1) == 2, "choice persists in settings file")
	check(DirectControl.wants(GameData.option("control_mode"), false), "saved choice enables keyboard/mouse third person")
	panel.open(); camera_page(); row = mode_row()
	check(row >= 0 and panel._switch_text(panel._rows[row]) == RemakeText.t("Third person"), "reopened settings show the selected mode")
	click(Vector2(590, 168 + 24 * row))
	check(panel._values.control_mode == 3 and panel._switch_text(panel._rows[row]) == RemakeText.t("First person"), "first-person choice is available and readable")
	var light_row := -1
	for at: int in panel._rows:
		if panel._rows[at].name == "character_light": light_row = at
	check(light_row >= 0 and panel._values.character_light == 0, "character light defaults to camera-dependent Auto")
	if light_row >= 0: click(Vector2(590, 168 + 24 * light_row))
	click(Vector2(250, 550))
	cfg.load(GameData.CONFIG_PATH)
	check(GameData.option("control_mode") == 3 and cfg.get_value("options", "control_mode", -1) == 3, "first-person choice persists")
	check(GameData.option("character_light") == 1 and cfg.get_value("options", "character_light", -1) == 1, "character light override persists")
	panel.queue_free(); await frames()
	print("CONTROL_MODE_OPTIONS ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)

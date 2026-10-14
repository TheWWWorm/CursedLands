extends Node
## Actual menu draw submissions with closed and open UI screens. Run rendered.
var rows := []
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func sample(label: String) -> float:
	for i in 5:
		await RenderingServer.frame_post_draw
	var draws := 0.0
	for i in 30:
		await RenderingServer.frame_post_draw
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var mean := draws / 30.0
	rows.append({"label":label, "draw_calls":mean})
	print("MENU_HIDDEN_VIEWPORTS ", label, " draw_calls=", mean)
	return mean

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	GameData.options.auto_graphics = 0
	GameData.options.confine_mouse = 0
	GameData.options.display_mode = 0
	TutorialPanel.auto_show = false
	var menu := preload("res://src/ui/main_menu.gd").new()
	get_parent().add_child(menu)
	await RenderingServer.frame_post_draw
	menu.process_mode = Node.PROCESS_MODE_DISABLED
	var boards: Array = menu.find_children("*", "InterfaceBoard", true, false)
	for b in boards: b.process_mode = Node.PROCESS_MODE_ALWAYS
	check(boards.size() > 0, "menu has real interface boards")
	check(boards.all(func(b): return not b.is_visible_in_tree()), "all closed-menu boards are hidden")
	var shipped := await sample("as-built hidden")
	check(boards.all(func(b): return b._vp.size == Vector2i(800,600)), "hidden boards retain their initial size")
	for b in boards: b._vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var disabled := await sample("disabled control")
	check(is_equal_approx(shipped, disabled), "closed UI does not submit hidden 3D board draws")
	for b in boards: b._vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var always := await sample("always control")
	check(always > disabled, "control detects redundant hidden board draws")
	for b in boards: b._vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	var gated := await sample("visible-only hidden")
	check(is_equal_approx(gated, disabled), "visible-only mode removes hidden board draws")
	menu._options.open()
	var shown := await sample("visible-only options open")
	var visible_boards := boards.filter(func(b): return b.is_visible_in_tree())
	check(visible_boards.size() > 0 and visible_boards.all(func(b): return b._vp.size.y == maxi(60,int(b.size.y))), "opened boards resize to their visible screen")
	for b in boards: b._vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var shown_disabled := await sample("disabled options control")
	check(shown > shown_disabled, "visible options board draws with visible-only mode")
	for b in boards: b._vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	menu._options._close()
	var closed := await sample("visible-only options closed")
	check(is_equal_approx(closed, disabled), "closing options stops its board draws")
	var result := {"checks":checks, "failures":failures, "boards":boards.size(), "rows":rows,
		"renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open("user://menu-hidden-viewports.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("MENU_HIDDEN_VIEWPORTS_RESULT ",JSON.stringify(result))
	get_tree().quit(1 if failures else 0)

extends Node
## Exercise the actual menu / expedition / sandbox teardown paths.

var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func frames() -> void:
	for i in 12: await get_tree().process_frame

func _ready() -> void:
	await frames()
	var main := get_parent()
	reparent(get_tree().root)
	var menu: Control = load("res://src/ui/main_menu.gd").new()
	menu.detect_graphics = false
	main.add_child(menu)
	await frames()
	check(menu._arena_pve_button.is_visible_in_tree(), "main menu exposes expedition")
	check(not menu._campaign_bar.get_children().any(func(n):return n is Button and n.text == RemakeText.t("Arena")), "arena button absent from menu")
	check(not menu.campaign_pad_targets().any(func(t):return t.id == "campaign_arena"), "arena removed from controller navigation")
	menu._arena_pve_button.pressed.emit()
	await frames()
	var expedition := main.get_node_or_null("ArenaExpedition") as ArenaPveScreen
	check(expedition != null and expedition.landing, "menu opens expedition team selection")
	check(main.session == null and main.game == null, "expedition creates no campaign session")
	if expedition:
		main.open_arena()
		await frames()
		check(not is_instance_valid(expedition), "developer-only sandbox releases expedition")
	var sandbox := main.get_node_or_null("Arena") as ArenaScreen
	check(sandbox != null and sandbox.match_state.phase == ArenaMatch.Phase.DEPLOY, "sandbox opens ready to deploy")
	main.open_arena_pve()
	await frames()
	check(not is_instance_valid(sandbox), "return to expedition releases sandbox")
	expedition = main.get_node_or_null("ArenaExpedition") as ArenaPveScreen
	check(expedition != null, "expedition can reopen after sandbox")
	if expedition:
		expedition.battle.set_speed(2)
		expedition.exit_requested.emit()
		await frames()
		check(not is_instance_valid(expedition), "exit releases expedition world")
	check(Engine.time_scale == 1, "main menu restores normal clock")
	check(main.get_children().any(func(n): return n.get_script() == load("res://src/ui/main_menu.gd")), "main menu returns")
	print("ARENA_PVE_LIFECYCLE ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

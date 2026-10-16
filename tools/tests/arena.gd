extends Node
## Real database, real widgets, real monster AI/combat. Run with --tool= this
## absolute path; private XDG directories protect player files and settings.

var checks := 0
var failures: Array[String] = []
var screen: ArenaScreen
var arena: ArenaMatch
var rendered := false
var events := {}

class Errors extends Logger:
	var messages: Array[String] = []
	var mutex := Mutex.new()
	func _log_error(fn: String, file: String, line: int, code: String,
		why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == ERROR_TYPE_WARNING: return
		mutex.lock()
		messages.append("%s %s (%s:%d %s)" % [code, why, file, line, fn])
		mutex.unlock()
	func snapshot() -> Array[String]:
		mutex.lock()
		var copy := messages.duplicate()
		mutex.unlock()
		return copy

var errors := Errors.new()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)


func frames(count := 5) -> void:
	for i in count: await get_tree().process_frame


func click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await frames(2)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)


func shot(label: String) -> void:
	if not rendered: return
	await frames(8)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://arena-" + label + ".png")


func prototype(fragment: String, caster := false) -> String:
	for entry: Dictionary in arena.catalog.entries:
		if not fragment.is_empty() and not fragment.to_lower() in String(entry.id): continue
		if caster and Array(entry.row.get("spells", [])).is_empty(): continue
		return entry.id
	return ""


func _ready() -> void:
	OS.add_logger(errors)
	rendered = DisplayServer.get_name() != "headless"
	await frames(20)
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280, 800)
	await frames()
	var data_hash := hash(GameData.db.tables)
	var initial_speed := Engine.time_scale
	screen = ArenaScreen.new()
	add_child(screen)
	arena = screen.match_state
	arena.visual_event.connect(func(e): events[e.t] = int(events.get(e.t, 0)) + 1)
	await frames()
	check(arena.catalog.entries.size() == GameData.db.table("monster_prototypes").size(), "all authored creature prototypes are available")
	check(arena.catalog.entries.size() > 100, "real installed creature roster")
	check(arena.state.heroes.is_empty() and not arena.online and arena.local_host == null and arena.net == null, "no heroes, connection or simulation worker")
	check(arena.world.vm == null and arena.phase == ArenaMatch.Phase.DEPLOY, "deployment has no campaign script or running combat")
	check(not arena.start(), "empty teams cannot start")
	check(screen._start.disabled, "start button explains empty setup")
	var wolf := prototype("wolf")
	var boar := prototype("boar")
	print("ARENA fixtures ", wolf, " / ", boar, " roster=", arena.catalog.entries.size())
	check(not wolf.is_empty() and not boar.is_empty(), "installed monster fixtures")
	if wolf.is_empty() or boar.is_empty():
		finish(data_hash, initial_speed)
		return
	check(not arena.place(wolf, 0, Vector2(-4, 4)).is_empty(), "out-of-bounds placement rejected")
	check(not arena.place(wolf, 0, Vector2(NAN, 4)).is_empty(), "non-finite placement rejected")
	check(not arena.place("__missing", 0, Vector2(5, 5)).is_empty(), "unknown prototype rejected")
	check(not arena.place(wolf, 3, Vector2(5, 5)).is_empty(), "unknown team rejected")
	var title: String = arena.catalog.by_id[wolf].family
	screen._query.text = title
	screen._query.text_changed.emit(title)
	check(screen._list.item_count > 0, "localized search finds monster")
	check(arena.catalog.search("___unmatched___").is_empty(), "empty search")
	screen._select(wolf)
	await frames()
	check(screen._preview.creature != null and screen._preview.creature._model != null, "roster shows real animated monster")
	check(screen.field.ghost != null, "placement preview uses real model")
	# Actual Godot GUI routing, not a direct call to the deployment callback.
	if rendered:
		await click(screen.field.global_position + screen.field.screen_point(Vector2(7, 11)))
	else:
		screen._place(Vector2(7, 11))
	check(arena.team_count(0) == 1, "battlefield click deploys selected creature")
	check(not arena.place(boar, 1, Vector2(7, 11)).is_empty(), "overlapping deployment rejected")
	check(not arena.start(), "one-sided battle cannot start")
	screen._choose_team(1)
	screen._select(boar)
	if rendered:
		await click(screen.field.global_position + screen.field.screen_point(Vector2(24, 11)))
	else:
		screen._place(Vector2(24, 11))
	check(arena.team_count(1) == 1 and not screen._start.disabled, "red team placement enables battle")
	var positions := arena.formation.duplicate(true)
	await frames(20)
	check(arena.world.time == 0 and arena.world.unit_rows().all(func(u): return u.hp == u.max_hp), "deployment stays paused")
	for u: GameUnit in arena.world.unit_rows():
		check(u.controller == -1 and u.mode == "aggression", "both sides are AI controlled")
		check(u.uid < 1000000000, "ordinary monster identity preserves AI spell eligibility")
	check(arena.world.is_enemy(arena.world.unit_rows()[0], arena.world.unit_rows()[1]), "teams are mutually hostile")
	await shot("deployment")
	check(arena.start(), "battle starts")
	arena.set_speed(2)
	check(Engine.time_scale == 2, "double speed applies")
	# Exercise the normal frame clock before the faster bounded tick driver.
	# Direct _advance calls alone could hide a disabled production world.
	await get_tree().create_timer(0.6, true, false, true).timeout
	check(arena.world.time > 0, "live frame clock advances battle without a test driver")
	check(arena.world.unit_rows().any(func(u): return u.pos != u.get_meta("arena_placement").point), "live AI moves creatures without player orders")
	arena.toggle_pause()
	var paused_at := arena.world.time
	await frames(20)
	check(arena.world.time == paused_at, "pause freezes world")
	check(not arena.place(wolf, 0, Vector2(10, 20)).is_empty(), "cannot place during a battle")
	arena.toggle_pause()
	# Bounded deterministic tick driver uses the production simulation; no
	# damage or stats are changed to force the outcome.
	arena.world.set_process(false)
	arena.world.set_physics_process(false)
	var damage_before := int(events.get("hitnum", 0))
	for i in 4000:
		if arena.phase != ArenaMatch.Phase.FIGHT: break
		arena.world._advance(GameUnit.TICK)
		arena._process(0)
		if i == 180: await shot("battle")
		if i % 50 == 0: await frames(1)
	print("ARENA combat time=", arena.world.time, " phase=", arena.phase, " winner=", arena.winner, " events=", events)
	check(int(events.get("hitnum", 0)) > int(damage_before), "real AI closes distance and inflicts damage")
	check(arena.phase == ArenaMatch.Phase.FINISHED and arena.winner in [0, 1], "AI battle produces a winner")
	await shot("result")
	arena.reset()
	check(arena.formation == positions and arena.world.time == 0, "reset preserves authored formation")
	check(arena.world.unit_rows().all(func(u): return not u.dead and u.hp == u.max_hp and u.order.is_empty()), "reset restores health and clears old orders")
	check(Engine.time_scale == initial_speed, "edit restores global speed")
	arena.rematch()
	check(arena.phase == ArenaMatch.Phase.FIGHT and arena.formation == positions, "rematch restores then starts")
	arena.reset()
	arena.undo()
	check(arena.formation.size() == 1 and arena.team_count(1) == 0, "undo removes last placement")
	arena.clear_team(0)
	check(arena.world.unit_rows().is_empty() and arena.formation.is_empty(), "clear team removes its creatures")
	await magic_checks(wolf)
	await ranged_checks(wolf)
	await outcome_checks(wolf)
	await capacity_checks(wolf)
	await layout_checks(wolf, boar)
	finish(data_hash, initial_speed)


func magic_checks(wolf: String) -> void:
	var caster := prototype("troll", true)
	if caster.is_empty(): caster = prototype("", true)
	check(not caster.is_empty(), "installed spellcaster fixture")
	if caster.is_empty(): return
	print("ARENA caster ", caster, " ", arena.catalog.by_id[caster].row.get("spells"))
	check(arena.place(caster, 0, Vector2(10, 16)).is_empty(), "caster deploys with authored spells")
	check(arena.place(wolf, 1, Vector2(20, 16)).is_empty(), "caster opponent deploys")
	var before := int(events.get("castfx", 0))
	arena.start()
	arena.world.set_process(false)
	arena.world.set_physics_process(false)
	for i in 1600:
		if arena.phase != ArenaMatch.Phase.FIGHT: break
		arena.world._advance(GameUnit.TICK)
		arena._process(0)
		if i % 50 == 0: await frames(1)
	check(int(events.get("castfx", 0)) > before, "monster AI casts authored spells with visual events")
	arena.reset()
	arena.clear_team(0)
	arena.clear_team(1)


func outcome_checks(wolf: String) -> void:
	arena.place(wolf, 0, Vector2(8, 16))
	arena.place(wolf, 1, Vector2(24, 16))
	arena.start()
	for u: GameUnit in arena.world.unit_rows(): u.take_damage(u.max_hp * 10, null)
	arena._process(0)
	check(arena.phase == ArenaMatch.Phase.FINISHED and arena.winner == -1, "simultaneous elimination is a draw")
	arena.reset()
	arena.start()
	arena.world.time = ArenaMatch.TIME_LIMIT
	arena._process(0)
	check(arena.phase == ArenaMatch.Phase.FINISHED and arena.winner == -1, "time limit resolves stalled battles")
	arena.reset()
	arena.clear_team(0)
	arena.clear_team(1)
	await frames()


func ranged_checks(wolf: String) -> void:
	var archer := ""
	for entry: Dictionary in arena.catalog.entries:
		if int(entry.row.get("weapon_type_id", -1)) != 8: continue
		var weapons := CampaignState.proto_weapons(entry.row)
		if weapons.is_empty(): continue
		if String(Items.info(weapons[0]).row.get("type", "")).to_lower() in ["bow", "crossbow"]:
			archer = entry.id
			break
	check(not archer.is_empty(), "installed archer fixture")
	if archer.is_empty(): return
	check(arena.place(archer, 0, Vector2(9, 16)).is_empty(), "archer deploys with authored weapon")
	check(arena.place(wolf, 1, Vector2(22, 16)).is_empty(), "archer opponent deploys")
	var before := int(events.get("arrow", 0))
	arena.start()
	arena.world.set_process(false)
	arena.world.set_physics_process(false)
	for i in 600:
		if arena.phase != ArenaMatch.Phase.FIGHT: break
		arena.world._advance(GameUnit.TICK)
		# Physical missiles are independent child physics nodes, unlike spell
		# callbacks. Advance those production nodes with the same test clock.
		for child: Node in arena.world.get_children():
			if child is Projectile and not child.is_queued_for_deletion(): child._tick(GameUnit.TICK)
		arena._process(0)
		if i % 50 == 0: await frames(1)
	check(int(events.get("arrow", 0)) > before, "AI fires physical projectiles")
	arena.reset()
	arena.clear_team(0)
	arena.clear_team(1)
	await frames()


func layout_checks(wolf: String, boar: String) -> void:
	var troll := prototype("troll")
	var orc := prototype("orc")
	for i in 4:
		check(arena.place(troll if i == 1 and not troll.is_empty() else wolf, 0, Vector2(7, 7 + i * 5)).is_empty(), "mixed blue formation")
		check(arena.place(orc if i == 1 and not orc.is_empty() else boar, 1, Vector2(24, 7 + i * 5)).is_empty(), "mixed red formation")
	screen._query.text = ""
	screen._query.text_changed.emit("")
	screen._select(troll if not troll.is_empty() else wolf)
	screen.field.hover_point = Vector2.INF
	await shot("armies")
	for dimensions in [Vector2i(1280, 720), Vector2i(1024, 768)]:
		get_tree().root.size = dimensions
		await frames(12)
		check(screen.field.size.x >= 240 and screen.field.size.y >= 220, "battlefield remains usable at " + str(dimensions))
		check(screen._message.get_global_rect().end.y < screen.size.y, "status stays inside viewport at " + str(dimensions))
		check(screen._sidebar.get_global_rect().end.y <= screen.size.y, "roster stays inside viewport at " + str(dimensions))
		await shot(str(dimensions.x))


func capacity_checks(wolf: String) -> void:
	for y in 4:
		for x in 6:
			check(arena.place(wolf, 0, Vector2(4 + x * 4, 5 + y * 6)).is_empty(), "valid capacity placement")
	check(arena.team_count(0) == ArenaMatch.LIMIT, "team capacity reached")
	check(not arena.place(wolf, 0, Vector2(28, 28)).is_empty(), "team capacity enforced")
	arena.clear_team(0)
	check(arena.formation.is_empty(), "capacity test clears cleanly")
	await frames()


func menu_checks() -> void:
	var main := get_parent()
	# Keep the test driver alive while main.gd replaces its actual children.
	reparent(get_tree().root)
	var menu: Control = load("res://src/ui/main_menu.gd").new()
	menu.detect_graphics = false
	main.add_child(menu)
	await frames(12)
	check(not menu.campaign_pad_targets().any(func(t):return t.id == "campaign_arena"), "arena hidden from main menu")
	await shot("menu")
	main.open_arena()
	await frames(12)
	var opened := main.get_node_or_null("Arena") as ArenaScreen
	check(opened != null and opened.match_state.phase == ArenaMatch.Phase.DEPLOY, "developer entry opens arena")
	check(main.session == null and main.game == null, "arena does not create a campaign session")
	if opened:
		opened.match_state.set_speed(2)
		opened.exit_requested.emit()
		await frames(12)
		check(not is_instance_valid(opened), "exit releases arena and its world")
	var returned := false
	for child in main.get_children():
		if child.get_script() == load("res://src/ui/main_menu.gd"): returned = true
	check(returned and Engine.time_scale == 1, "main menu returns with normal clock")


func finish(data_hash: int, initial_speed: float) -> void:
	check(hash(GameData.db.tables) == data_hash, "arena leaves source databases unchanged")
	arena.set_speed(2)
	screen.queue_free()
	await frames()
	check(Engine.time_scale == initial_speed, "exit restores global clock")
	if not OS.get_cmdline_user_args().has("--arena-skip-menu"): await menu_checks()
	var runtime_errors := errors.snapshot()
	check(runtime_errors.is_empty(), "no engine or script errors")
	OS.remove_logger(errors)
	var result := {"checks": checks, "failures": failures, "errors": runtime_errors, "language": RemakeText.lang, "rendered": rendered, "events": events}
	var file := FileAccess.open("user://arena-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("ARENA_RESULT ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)

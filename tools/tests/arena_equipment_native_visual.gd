extends Node
## Real native AI combat with the equipment/alliance roster. No injected effects.
## Run once headlessly and once at each rendered speed; compare recorded results.

const Duel = preload("../benchmarks/arena_roster_matchups.gd").Duel
const Errors = preload("arena_expansion_ui.gd").Errors
const FAMILIES := [3, 5, 6, 11, 19, 21]
const ITEMS := ["fang", "echo", "storm", "thorn", "guardian", "ward"]
class VisualDuel extends Duel:
	func resolve(side: int, seconds: float, damage: Array, survivors: Array = [0, 0]) -> void:
		last_result = {"winner":side, "seconds":seconds, "damage":damage.duplicate(), "survivors":survivors.duplicate()}
		stage = "result"
var errors := Errors.new()
var checks := 0
var failures: Array[String] = []
var screen: ArenaPveScreen
var battle: ArenaPveMatch
var notices: Array[Dictionary] = []
var echo_rows: Array[Dictionary] = []
var captures: Array[String] = []
var requested_speed := 1
var first_echo_uid := 0
var tag := ""

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame

func company(run: ArenaRun) -> void:
	run.auto_save = false
	run.begin(15877)
	run.army.clear()
	run.training = 126
	for i in FAMILIES.size():
		var entry := run._recruit(FAMILIES[i], 0, 1)
		entry.deployed = true
		entry.point = [27.0, 24.0 + i * 3.0]
		run.items.append({"uid":i + 1, "kind":ITEMS[i], "unit_uid":entry.uid})
	run.next_item_uid = FAMILIES.size() + 1
	run._sync_items()

func native_event(event: Dictionary) -> void:
	if event.get("t") != "arena_proc": return
	var row := event.duplicate(true)
	row.time = battle.world.time
	notices.append(row)
	if event.effect != "spirit_echo": return
	var unit: GameUnit = battle.world.units.get(int(event.uid))
	if not is_instance_valid(unit): return
	if first_echo_uid == 0: first_echo_uid = unit.uid
	echo_rows.append({"uid":unit.uid, "name":unit.display_name, "hp":unit.hp,
		"max_hp":unit.max_hp, "visible":unit.visible, "model":unit.model != null,
		"placement":unit.get_meta("arena_placement", {}).duplicate(true)})

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "user://native-%s-%s.png" % [tag, label]
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture " + label)
	captures.append(path)
	print("CAPTURE ", path, " simulation=", battle.world.time)

func _ready() -> void:
	OS.add_logger(errors)
	var visible_run := DisplayServer.get_name() != "headless"
	var lang := "en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--native-combat-speed="): requested_speed = int(arg.get_slice("=", 1))
		if arg.begins_with("--native-combat-lang="): lang = arg.get_slice("=", 1)
	RemakeText.lang = lang
	GameData.arena_mode = 0
	GameData.arena_speed = requested_speed
	Engine.max_fps = 60
	tag = "%s-%dx" % [lang, requested_speed] if visible_run else "headless"
	var native_hash := hash(GameData.db.tables)
	var run := VisualDuel.new()
	var rival := ArenaRun.new()
	company(rival)
	if visible_run:
		await frames(24)
		GameData._window_gen += 1
		get_tree().root.mode = Window.MODE_WINDOWED
		get_tree().root.size = Vector2i(1280, 720)
		get_tree().root.position = Vector2i.ZERO
		screen = ArenaPveScreen.new()
		screen.run = run
		add_child(screen)
		await frames(15)
		company(run)
		run.opposing.assign(rival.army.duplicate(true))
		screen.landing = false
		screen._board_key = ""
		run._touch()
		battle = screen.battle
		battle.formation_motion.settle(battle.world)
		await frames(15)
	else:
		company(run)
		run.opposing.assign(rival.army.duplicate(true))
		battle = ArenaPveMatch.new()
		battle.run = run
		battle.rendered = false
		battle.drives_clock = false
		add_child(battle)
		battle.set_process(false)
		battle.set_physics_process(false)
		battle._world_parent = self
		battle.prepare()
	battle.visual_event.connect(native_event)
	check(battle.team_count(0) == 6 and battle.team_count(1) == 6, "same six equipped creatures on each side")
	check(battle.start(), "native battle starts")
	var start_ms := Time.get_ticks_msec()
	var saw_hp_change := false
	var saw_live_marker := false
	var saw_echo_marker := false
	var saw_equipment_badge := false
	var captured_effects := false
	var captured_echo := false
	var captured_inspector := false
	while battle.phase == ArenaMatch.Phase.FIGHT and Time.get_ticks_msec() - start_ms < 110000:
		if not visible_run:
			battle.simulate_tick()
			continue
		await get_tree().process_frame
		for unit: GameUnit in battle.world.unit_rows():
			if unit.dead: continue
			if unit.hp < unit.max_hp: saw_hp_change = true
			var placement: Dictionary = unit.get_meta("arena_placement", {})
			var badge: Control = screen._item_targets.get(int(placement.get("run_uid", 0)))
			if int(placement.get("team", -1)) == 0 and badge != null and badge.visible and not String(placement.get("item", "")).is_empty() and badge.kind == placement.item:
				saw_equipment_badge = true
			var marker: Control = screen.field._unit_markers.get(unit.get_instance_id())
			if marker != null and not marker.state.is_empty():
				var expected := "%d/%d" % [maxi(0, ceili(unit.hp)), ceili(unit.max_hp)]
				if marker.state[4] == expected:
					saw_live_marker = true
					if unit.get_meta("arena_placement", {}).get("echo", false): saw_echo_marker = true
		if not captured_effects and notices.size() >= 3:
			captured_effects = true
			await shot("effects")
		if not captured_echo and first_echo_uid > 0:
			captured_echo = true
			await shot("echo")
		if not captured_inspector and first_echo_uid > 0:
			var echo: GameUnit = battle.world.units.get(first_echo_uid)
			if is_instance_valid(echo) and not echo.dead:
				var rects := echo.screen_rects(screen.field.camera)
				if not rects.is_empty():
					var motion := InputEventMouseMotion.new()
					motion.position = Rect2(rects[0]).get_center()
					Input.parse_input_event(motion)
				if screen._rail.visible and screen._inspected_unit == echo:
					captured_inspector = true
					check(screen._inspect_box.get_child(0).text == RemakeText.t("Spirit echo"), "echo inspector uses its localized summon name")
					await shot("echo-inspector")
	var elapsed := float(Time.get_ticks_msec() - start_ms) / 1000.0
	var result := {"renderer":DisplayServer.get_name(), "speed":requested_speed, "seed":run.run_seed,
		"battle_seed":run.battle_seed(), "winner":battle.winner, "seconds":battle.world.time,
		"wall_seconds":elapsed, "damage":battle.damage, "survivors":[battle.team_count(0, true), battle.team_count(1, true)],
		"effects":battle.world.arena_effects.totals.duplicate(), "notices":notices, "echoes":echo_rows,
		"captures":captures, "live_markers":saw_live_marker, "echo_marker":saw_echo_marker}
	check(battle.phase == ArenaMatch.Phase.FINISHED, "native battle finishes")
	check(battle.world.time <= ArenaRules.BATTLE_SECONDS + GameUnit.TICK, "battle respects simulation time limit")
	check(notices.any(func(e): return e.effect in ITEMS), "real equipment emits named feedback")
	check(notices.any(func(e): return e.effect in ["pack", "guard", "reaction", "spirit"]), "real alliance emits named feedback")
	check(not echo_rows.is_empty(), "native Spirit death creates an echo")
	for row in echo_rows:
		check(row.name == RemakeText.t("Spirit echo") and row.hp > 0 and row.visible and row.model, "echo has localized name, health and visible model")
		check(row.placement.echo and row.placement.item.is_empty() and row.placement.family == -1, "echo has no equipment or alliance membership")
	if visible_run:
		check(saw_hp_change and saw_live_marker and saw_echo_marker, "live HP markers update for recruits and echoes")
		check(saw_equipment_badge, "native battle retains visible frozen equipment badges")
		check(captured_effects and captured_echo, "real proc and echo frames captured")
		check(captured_inspector, "actual echo hover opens the localized inspector")
		check(absf(battle.world.time / maxf(0.001, elapsed) - requested_speed) < 0.25, "native clock follows requested speed")
		await shot("finished")
		result.captures = captures
		screen.run.auto_save = false
		screen.queue_free()
	else:
		battle.world.free()
		battle.queue_free()
	await frames(8)
	check(hash(GameData.db.tables) == native_hash, "native prototype tables unchanged")
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no runtime errors: " + str(errors.messages))
	result.checks = checks
	result.failures = failures
	var file := FileAccess.open("user://native-combat-%s.json" % tag, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("ARENA_EQUIPMENT_NATIVE_VISUAL ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)

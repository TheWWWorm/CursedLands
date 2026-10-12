extends Node
## Compare actual campaign figures to the two released framing baselines.
## Pass baseline scripts extracted from git, with their class_name removed:
## --preview-original=<experimental.2 paperdoll.gd>
## --preview-large=<feedback.2 paperdoll.gd>
var checks := 0
var failures := 0
var records := []
var output := "user://preview-framing"

class NamePanel extends UnitPanel:
	var subject: GameUnit
	var zoom := 1.0
	func _pick() -> GameUnit: return subject
	func _k() -> float: return zoom

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(count := 4) -> void:
	for i in count: await get_tree().process_frame

func capture(name: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "capture " + name)

func label(value: String, pos: Vector2) -> Label:
	var node := Label.new()
	node.text = value
	node.position = pos
	node.add_theme_font_size_override("font_size", 22)
	add_child(node)
	return node

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	var paths := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview-original="): paths.original = arg.trim_prefix("--preview-original=")
		if arg.begins_with("--preview-large="): paths.large = arg.trim_prefix("--preview-large=")
	DirAccess.make_dir_recursive_absolute(output)
	check(paths.has("original") and paths.has("large"), "both released framing baselines supplied")
	if failures: get_tree().quit(1); return
	var original: Script = load(paths.original)
	var large: Script = load(paths.large)
	check(original != null and large != null, "released framing scripts load")
	if failures: get_tree().quit(1); return
	GameData.options.merge({"auto_graphics": 0, "gfx_detailed_heads": 0, "gfx_sharp_units": 0,
		"autosave": 0, "display_mode": 0, "confine_mouse": 0, "vsync": 0}, true)
	GameData.resolution_size = "1280x800"
	GameData.options.resolution = GameData.resolutions().find(Vector2i(1280, 800))
	GameData._apply_window()
	Engine.max_fps = 60
	RenderingServer.set_render_loop_enabled(true)
	await frames(8)
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280, 800)
	var backdrop := ColorRect.new()
	backdrop.color = Color("233d42")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var world := GameWorld.new()
	add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	var examples := {"BoarTutor": false, "BoarRedF1": false, "BoarDarkF6": false,
		"WolfGreyF0": false, "RatGiantF9": false, "BatDarkM12": false, "Human Hero": false,
		"TrollBlackSlowF16": true, "DragonBlueM14": true, "GolemHorizontalF20": true}
	if GameData.campaign_id == CampaignProfile.ASTRAL:
		examples = {"zone7 BoarRed1": false, "zone9 BoarDark1": false, "zone7 WolfGrey1": false,
			"zonezero Rat": false, "zone1 Bat": false, "Human Hero": false,
			"q21Oh Troll Black": true, "zone1 DragonBlue": true, "zone14 Golem Horizontal": true}
	for prototype: String in examples:
		var unit := GameUnit.new()
		world.add_child(unit)
		check(unit.setup(world, {"nid": 123, "prototype": prototype}), "load " + prototype)
		if unit.model == null: unit.free(); continue
		unit.set_process(false)
		unit.set_physics_process(false)
		unit.model.set_process(false)
		unit.model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		unit.model.player.seek(0.0, true)
		unit.model.flush_pending_pose()
		var dolls := []
		var labels := []
		for script: Script in [original, large, Paperdoll]:
			var doll = script.new()
			doll.exe_rect = UnitPanel.FIG
			doll.view_size = Vector2i(320, 440)
			doll.size = Vector2(320, 440)
			doll.position = Vector2(60 + dolls.size() * 400, 120)
			doll.follow_pose = true
			add_child(doll)
			doll.show_unit(unit)
			labels.append(label(["Experimental 2", "Feedback 2", "Current"][dolls.size()], doll.position - Vector2(0, 40)))
			dolls.append(doll)
		await frames()
		var reference: Transform3D = dolls[1 if examples[prototype] else 0]._pivot.transform
		var current: Transform3D = dolls[2]._pivot.transform
		check(current.is_equal_approx(reference), prototype + (" retains oversized framing" if examples[prototype] else " matches Experimental 2 framing"))
		records.append({"prototype": prototype, "original": str(dolls[0]._pivot.transform),
			"feedback2": str(dolls[1]._pivot.transform), "current": str(current)})
		if prototype in ["BoarTutor", "WolfGreyF0", "TrollBlackSlowF16", "zone7 BoarRed1", "zone7 WolfGrey1", "q21Oh Troll Black"]:
			await capture(prototype)
		for phase in [0.1, 0.3, 0.7]:
			unit.model.player.seek(phase * unit.model.player.current_animation_length, true)
			unit.model.flush_pending_pose()
			dolls[2].show_unit(unit)
			await frames(2)
			check(dolls[2]._pivot.transform.is_equal_approx(current), prototype + " framing stays fixed while animating " + str(phase))
		for node in dolls + labels: node.free()
		unit.free()
	# Actual unit-panel draw, including the cached fit and resize/name changes.
	var human := GameUnit.new()
	world.add_child(human)
	check(human.setup(world, {"nid": 124, "prototype": "Human Hero"}), "name panel character loads")
	var panel := NamePanel.new()
	panel.subject = human
	add_child(panel)
	for zoom in [0.75, 1.0, 1.8, 2.7, 4.8]:
		panel.zoom = zoom
		for name in ["Worm", "Кабан", "Неторопливый черный тролль", "Langsamer schwarzer Troll"]:
			human.display_name = name
			await frames(8)
			var normal := maxi(6, roundi(800.0 * Interface800.FONT_EM[0] * zoom))
			var width := Interface800.font().get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, panel._name_fit_size).x + maxf(1.0, round(zoom))
			check(panel._name_fit_size > 0 and width <= 150 * zoom, "complete name fits at " + str(zoom) + ": " + name)
			if name in ["Worm", "Кабан"]:
				check(panel._name_fit_size == normal, "short name keeps normal size at " + str(zoom))
			elif zoom == 2.7: await capture("name-" + str(name.hash()))
	panel.free()
	human.free()
	world.free()
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "figures": records}, "\t"))
	print("PREVIEW_FRAMING ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)

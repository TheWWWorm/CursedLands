extends Node
## Applying one terrain's options may immediately free later snapshot entries.
## The scan must still update other terrains and notify option listeners.
var checks := 0
var failures := 0
var notifications := 0

class Detector extends GfxDetect:
	func _ready() -> void: pass

class RebuildingTerrain extends EITerrain:
	var calls := 0
	var discard: Node
	func apply_gfx() -> void:
		calls += 1
		if is_instance_valid(discard): discard.free()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameData.options.merge({"auto_graphics":0, "confine_mouse":0, "display_mode":0}, true)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	var detector := Detector.new()
	add_child(detector)
	GameData.options_changed.connect(func(): notifications += 1)
	for remove_terrain: bool in [false, true]:
		var first := RebuildingTerrain.new()
		var removed: Node = RebuildingTerrain.new() if remove_terrain else Node3D.new()
		var last := RebuildingTerrain.new()
		first.add_child(removed)
		removed.add_child(Node3D.new())
		first.discard = removed
		add_child(first)
		add_child(last)
		var before := notifications
		detector._apply_live()
		check(not is_instance_valid(removed), "earlier terrain freed a snapshot entry")
		check(first.calls == 1 and last.calls == 1, "all remaining terrains updated")
		check(notifications == before + 1, "option notification emitted once")
		first.free()
		last.free()
	# Real map option changes cover reflection and sector-child replacement.
	# Skip only the GPU-dependent case for headless logic runs.
	if DisplayServer.get_name() != "headless":
		var menu := MenuScene.create()
		add_child(menu)
		menu.set_hour(12.0)
		detector._env = menu._env
		var base := GfxDetect.base_values()
		var expired := 0
		for tier: int in [0, 1, 2, 3, 4, 5, 0, 5]:
			var before := notifications
			var snapshot := menu.find_children("*", "", true, false)
			detector._set_values(GfxDetect.tier_values(tier, base))
			detector._apply_live()
			for node in snapshot:
				if not is_instance_valid(node): expired += 1
			check(notifications == before + 1, "menu tier %d finishes applying" % tier)
			await RenderingServer.frame_post_draw
			await get_tree().process_frame
		if EITerrain.WaterReflection.supported() or EITerrain.CloudReflectionView.supported():
			check(expired > 0, "real terrain invalidated reflection snapshot entries")
		else:
			check(expired == 0, "unsupported reflection views are absent on this renderer")
		print("GFX_DETECT_LIVE expired_menu_nodes=", expired)
		if OS.get_cmdline_user_args().has("--calibrate-startup"):
			var calibration := GfxDetect.start(false)
			var deadline := Time.get_ticks_msec() + 90000
			while is_instance_valid(calibration) and calibration.result.is_empty() and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			var completed := is_instance_valid(calibration) and not calibration.result.is_empty()
			check(completed, "complete graphics calibration returns a result")
			if completed:
				# result is assigned before the final two presented frames.
				while calibration._testing and Time.get_ticks_msec() < deadline:
					await get_tree().process_frame
				var record := GfxDetect.load_record()
				check(not record.get("testing", false) and int(record.get("tier", -1)) >= 0, "calibration saves its completed result")
				check(not calibration._overlay.visible, "calibration progress overlay closes")
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("user://source-startup-graphics.png")
			if is_instance_valid(calibration): calibration.free()
		menu.free()
	detector.free()
	print("GFX_DETECT_LIVE checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)

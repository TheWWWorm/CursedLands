extends Node
## Rendered engine regression: cancelled hover timers expire, including while
## paused, and ordinary native tooltip delay/show/hide behavior is preserved.
var checks := 0
var failures := 0

class Hover extends Control:
	var tip := "Timer regression"
	func _get_tooltip(_at: Vector2) -> String: return tip

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame

func motion(vp: Viewport, at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	vp.push_input(event)

func viewport(delay: float) -> SubViewport:
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", delay)
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 480)
	vp.gui_embed_subwindows = true
	vp.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(vp)
	vp.notify_mouse_entered()
	return vp

func popups(control: Control) -> Array[Node]:
	return control.find_children("*", "PopupPanel", false, false)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await frames(30)
	var old_delay: float = ProjectSettings.get_setting("gui/timers/tooltip_delay_sec")
	var vp := viewport(1000000.0)
	var hover := Hover.new(); hover.size = Vector2(400, 400); vp.add_child(hover)
	motion(vp, Vector2(100,100)); await frames()
	var baseline := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for batch in 10:
		get_tree().paused = batch % 2 == 1
		Engine.time_scale = [0.0, 1.0, 2.0][batch % 3]
		for slice in 20:
			for i in 500: motion(vp, Vector2(100 + (i % 2) * 100, 100))
			await frames(1)
		await frames()
		var retained := int(Performance.get_monitor(Performance.OBJECT_COUNT)) - baseline
		print("TOOLTIP_RETAINED ", (batch + 1) * 10000, " events: ", retained)
		check(retained < 32, "hover objects remain bounded after batch %d" % batch)
	check(popups(hover).is_empty(), "long native delay remains suppressed")
	vp.notify_mouse_exited(); hover.queue_free(); vp.queue_free(); await frames()
	check(Performance.get_monitor(Performance.OBJECT_COUNT) < baseline + 32, "leaving a viewport releases pending timers")
	get_tree().paused = false; Engine.time_scale = 1.0
	vp = viewport(0.25)
	hover = Hover.new(); hover.size = Vector2(400,400); vp.add_child(hover)
	motion(vp, Vector2(100,100)); await frames(1)
	check(popups(hover).is_empty(), "ordinary tooltip respects its delay")
	await get_tree().create_timer(0.35, true, false, true).timeout
	check(popups(hover).size() == 1, "ordinary tooltip still appears")
	hover.tip = "Changed tooltip"
	motion(vp, Vector2(200,100)); await frames()
	check(popups(hover).is_empty(), "changed tooltip dismisses old content")
	await get_tree().create_timer(0.35, true, false, true).timeout
	check(popups(hover).size() == 1, "changed tooltip appears after its new delay")
	hover.hide(); await frames()
	check(popups(hover).is_empty(), "hiding the control dismisses the tooltip")
	vp.queue_free(); await frames()
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", old_delay)
	print("TOOLTIP_TIMER_RETENTION ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)

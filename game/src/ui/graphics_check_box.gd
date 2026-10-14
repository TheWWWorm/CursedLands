class_name GraphicsCheckBox
extends MessageBox
## Explicit choice before a test that can exercise unsupported driver paths.
const WARNING := "Run a graphics check now? In case of a crash, reopen the game: it will use Original graphics."

func _init() -> void:
	title = RemakeText.t("Graphics check")
	message = RemakeText.t(WARNING)

func _rects() -> Dictionary:
	var r := super()
	r.ok = Rect2(215, r.bottom + 26, 175, 48)
	r.cancel = Rect2(410, r.bottom + 26, 175, 48)
	return r

func _action(_ui: Texture2D, r: Rect2, yes: bool) -> void:
	panel(r)
	text_vc(r, RemakeText.t("Run check" if yes else "Skip"), 2, TEXT, HORIZONTAL_ALIGNMENT_CENTER)

func _get_tooltip(at: Vector2) -> String:
	var r := _rects()
	var p := to800(at)
	if (r.ok as Rect2).has_point(p): return RemakeText.t("Run check")
	if (r.cancel as Rect2).has_point(p): return RemakeText.t("Skip")
	return ""

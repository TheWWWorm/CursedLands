class_name CrashReportBox
extends MessageBox
## Remake: the message box (MessageBox's layout: panel, saveload frame, title
## and message centred, ✓ under it) that offers a report (CrashReport):
## - before movies and the main menu after a session that ended unexpectedly ("The game
##   closed unexpectedly last time.", `offer`);
## - from Options › Remake › "Export log…" at any time.
## Report actions in the panel, highlighted with the selection bar: "Save report"
## (a text file in a folder the player can open; its path is shown) and "Copy
## to clipboard" (the system information and the log's last lines). ✓ / Esc
## close it. Keys: Up / Down choose a row, Enter uses it; the gamepad snaps to
## the rows and ✓ (PadUI pad_targets). Startup failures also offer basic
## graphics and an explicit staged rendering check before the menu loads.

const ROWS := [
	["Save report", "Saves the report as a text file in a folder you can open: Download on Android, Downloads on a computer. The box shows where."],
	["Copy to clipboard", "Copies the system information and the log's last lines, to paste into a message or a bug report."],
]
const RECOVERY_ROWS := [
	["Use basic graphics", "Turns off enhanced graphics and automatic detection, then continues startup."],
	["Test startup graphics", "Checks the loading picture and menu parts separately. If the game closes, reopen it and save the report."],
]
const ROW_H := 30.0

## The previous session's info (CrashReport.previous); {} = Export log.
var prev := {}
var _sel := 0
var _status := ""
var startup_recovery := false
var _probing := false

func _row_defs() -> Array:
	return ROWS + RECOVERY_ROWS if startup_recovery else ROWS


## The box over `parent` when the previous session ended unexpectedly (once).
static func offer(parent: Node, startup := false) -> CrashReportBox:
	var cr := CrashReport.instance
	if cr == null or cr.previous.is_empty():
		return null
	var b := open(parent, cr.previous, startup)
	cr.previous = {}
	return b


static func open(parent: Node, previous: Dictionary, startup := false) -> CrashReportBox:
	var b := CrashReportBox.new()
	b.prev = previous
	b.startup_recovery = startup and not previous.is_empty() and String(previous.get("zone", "(menu)")) == "(menu)"
	b.name = "CrashReportBox"
	b.ok_only = true
	b.esc_closes = true
	if previous.is_empty():
		b.title = RemakeText.t("Export log")
		b.message = RemakeText.t("Save the game's log with the system information, or copy it, to send it with a bug report.")
	else:
		b.title = RemakeText.t("The game closed unexpectedly last time.")
		b.message = RemakeText.t("A report with the log of that session helps to find the cause. Save it or copy it, to send it with a bug report.")
	parent.add_child(b)
	return b


func _ready() -> void:
	super()
	add_to_group("pad_panel")


## A long path broken at its separators so each line fits the panel.
func _fit(s: String, font_i: int) -> String:
	var out := PackedStringArray()
	for w in s.split(" "):
		while w.length() > 1 and text_width(w, font_i) > 360.0:
			var cut := w.length() - 1
			while cut > 1 and text_width(w.substr(0, cut), font_i) > 360.0:
				cut -= 1
			var sep := maxi(w.rfind("/", cut - 1), w.rfind("\\", cut - 1))
			if sep > 0:
				cut = sep + 1
			out.append(w.substr(0, cut) + "\n")
			w = w.substr(cut)
		out.append(w)
	return " ".join(out)


func _rects() -> Dictionary:
	var t: float = wrap_text(title, 370, 2).size() * line_h(2)
	var m: float = wrap_text(message, 370, 2).size() * line_h(2)
	var st: float = 0.0
	if _status != "":
		st = wrap_text(_fit(_status, 1), 370, 1).size() * line_h(1) + 10.0
	var h := t + m + st + 45.0 + _row_defs().size() * ROW_H + 15.0
	var top := floorf((550.0 - h) / 2.0)
	var y0 := top + t + 30.0 + m + st + 15.0
	var rows := []
	for i in _row_defs().size():
		rows.append(Rect2(230, y0 + i * ROW_H, 340, ROW_H - 4.0))
	return {"t": t, "m": m, "top": top, "bottom": top + h, "rows": rows,
		"ok": Rect2(363, top + h + 26, 74, 48), "cancel": Rect2()}


func _draw() -> void:
	var r := _rects()
	panel(Rect2(200, r.top, 400, r.bottom - r.top))
	text_block(Rect2(215, r.top + 15, 370, 200), title, 2, Interface800.colorref(0x31b3ff), HORIZONTAL_ALIGNMENT_CENTER)
	text_block(Rect2(215, r.top + r.t + 30, 370, 400), message, 2, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	if _status != "":
		text_block(Rect2(215, r.top + r.t + 30 + r.m + 10, 370, 400), _fit(_status, 1), 1, GREY, HORIZONTAL_ALIGNMENT_CENTER)
	for i in _row_defs().size():
		var rr: Rect2 = r.rows[i]
		if i == _sel:
			draw_rect(r8(rr), BAR)
		text_vc(rr, RemakeText.t(_row_defs()[i][0]), 2, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	sprite(tex("saveload"), r.ok, [81, 2, 155, 50])


func _row_at(p: Vector2) -> int:
	var rows: Array = _rects().rows
	for i in rows.size():
		if (rows[i] as Rect2).has_point(p):
			return i
	return -1


func _get_tooltip(at: Vector2) -> String:
	var p := to800(at)
	if (_rects().ok as Rect2).has_point(p):
		return RemakeText.t("Close")
	var i := _row_at(p)
	return RemakeText.t(_row_defs()[i][1]) if i >= 0 else ""


## Uses row `i`: the report saved (the box shows where) or copied.
func act(i: int) -> void:
	if _probing or i < 0 or i >= _row_defs().size():
		return
	sound("messbox\\ok")
	var cr := CrashReport.instance
	if cr == null:
		return
	if i == 2:
		var values := GfxDetect.tier_values(GfxDetect.ORIGINAL, GfxDetect.base_values())
		values.merge({"auto_graphics":0, "q_aa":0, "fps_limit":1,
			"render_scale":mini(GameData.option("render_scale"),2), "graphics_preset":GfxPresets.CUSTOM}, true)
		GameData.set_options(values)
		GameData.trace("startup recovery: basic graphics selected")
		_answer(true)
		return
	if i == 3:
		_probing = true
		visible = false
		var probe := StartupGraphicsProbe.new()
		probe.finished.connect(func(ok: bool):
			_probing = false
			prev = {}
			title = RemakeText.t("Startup graphics check")
			message = RemakeText.t("The graphics check finished. Save the report before continuing." if ok else
				"The graphics check found an error. Save the report before continuing.")
			_status = ""
			visible = true
			queue_redraw())
		get_parent().add_child(probe)
		return
	if i == 0:
		var path := cr.save_report(prev)
		_status = RemakeText.t("Report saved:") + " " + path if path != "" else RemakeText.t("The report could not be saved.")
		var testing := Array(OS.get_cmdline_user_args()).any(func(a): return String(a).begins_with("--tool="))
		if path != "" and not testing and not Portability.constrained():
			OS.shell_show_in_file_manager(path)
	else:
		cr.copy_report(prev)
		_status = RemakeText.t("Copied to the clipboard.")
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var i := _row_at(to800(e.position))
		if i >= 0 and i != _sel:
			_sel = i
			queue_redraw()
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		var p := to800(e.position)
		var i := _row_at(p)
		if i >= 0:
			_sel = i
			act(i)
		elif (_rects().ok as Rect2).has_point(p):
			_answer(true)
	if e is InputEventMouseButton:
		accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if _probing or not is_visible_in_tree() or not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_UP, KEY_DOWN:
			_sel = posmod(_sel + (1 if e.keycode == KEY_DOWN else -1), _row_defs().size())
			queue_redraw()
		KEY_ENTER, KEY_KP_ENTER:
			act(_sel)
		KEY_ESCAPE:
			_answer(true)
		_: return
	get_viewport().set_input_as_handled()


## Remake (gamepad, PadUI): the rows and ✓.
func pad_targets() -> Array:
	var r := _rects()
	var out: Array = []
	for i in _row_defs().size():
		out.append({"rect": pad_rect(r.rows[i]), "id": "row%d" % i})
	out.append({"rect": pad_rect(r.ok), "id": "ok"})
	return out

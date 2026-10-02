class_name NotifyLine
extends Interface800
## The save / load notice (quick save
##  quick load and the Save / Load screens
## ): texts.res «string notify_saving» / «string notify_loading»
## (looks up "string " + the id the callers pass
## "notify_saving"; the remake once asked for "notify saving", which is not in
## texts.res, so the line stayed empty), font 2, green
## (COLORREF), centred in (0,280)-(800,320) of the 800x600 screen.
## The original draws it once and saves or loads while it stands; the remake
## saves at once, so it stays HOLD seconds (remake choice) and fades.

const RECT := Rect2(0, 280, 800, 40)
const GREEN := Color8(0x00, 0xff, 0x00)
const HOLD := 1.2
const FADE := 0.4

var _text := ""
var _t := 0.0
var _last := 0


func _ready() -> void:
	# Offsets too: anchors alone left it 0×0 under the safe root, so kv() was
	# 0 and the notice was drawn at zero size (invisible).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


## key: "string notify_saving" or "string notify_loading".
func notify(key: String) -> void:
	_text = GameData.text(key).strip_edges()
	_t = HOLD + FADE
	_last = Time.get_ticks_msec()
	modulate.a = 1.0
	queue_redraw()


## Real time, not game time: the same length at 2x speed and in pause.
func _process(_dt: float) -> void:
	if _t <= 0.0:
		return
	var now := Time.get_ticks_msec()
	_t -= (now - _last) / 1000.0
	_last = now
	modulate.a = clampf(_t / FADE, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if _t <= 0.0 or _text.is_empty():
		return
	text_block(RECT, _text, 2, GREEN, HORIZONTAL_ALIGNMENT_CENTER)

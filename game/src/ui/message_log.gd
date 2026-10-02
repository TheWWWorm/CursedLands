class_name MessageLog
extends Control
## The message log at the top centre (the original, widget
## built by CInterface3D), 180..620 × 0..100 of the
## 800×600 layout, kept centred and scaled by the window height:
## - text background over (180,20)-(620,95), a strip
##   over (180,0)-(620,20), a bronze frame (180,−5)-(620,100) 5 wide
##   (battle00 strip UV 4,55-90,60)
## - buttons: Open/Close (385,0)-(415,20), tip 10200; tab "Messages"
##   (185,0)-(215,20), tip 10201, battle00 UV 2,128-32,148; tab "Collected
##   items" (215,0)-(245,20), tip 10202, UV 2,150-32,170. The active tab is
##   drawn at full colour, the other at 0.5.
## - a click plays buttons\battle\click.wav: Open/Close slides
##   the window up by 95 px (= 0x5f) or back, a tab picks the
##   mode (: 0 messages, 1 collected items).
## - keyboard.ini L "w_text1" (key action 50) and K "w_text2" (51) run
##    via the CInterface3D key switch: a
##   closed window opens in that mode; an open one in the other mode switches
##   (no sound); the same mode closes it. Opening / closing plays
##   buttons\battle\sling.wav.
## - the "Collected items" text is built once when the
##   interface is built (a zone load): "string format_money" with the party's
##   money when > 0, then the party's items, equal ones merged with their
##   counts added, one per line ("format_item1" / "format_item2" with the count
##   when > 1).
## - the text is a ScrollText (the dialog box's class: font 1
##   CInterface3D, Times New Roman 15 px at 800 wide, 1 px
##   shadow) placed at (190,25)-(610,89), moving with the
##   slide; the slide takes 0.3 s (: dt / 0.3).
## - ScrollText builds on the scroll bar class (speed 20.0) and
##   narrows its text by 14 px (0xe); the bar is the dialog box's one
##   (DialogPanel.Bar: "Scrollbar" sprites in the right 10 px, drawn only when
##   the text overflows; thumb drag, arrows scroll while held
## ). Each text (messages / items) keeps its own position; new
##   messages keep the view at the end when it was there.
## Item lines: Items.log_text (: the type line and the quoted name).
## Slide (slot): p += real dt · dir
## 0.3, offset = trunc(95 · e) with e = 2p² below 0.5, else 1 − 2(1 − p)²;
##  shifts the sprites and every hit area but the first (the
## Open/Close spot (385,0)-(415,20) stays). Its "in25arrow" figure
## (HudDial.arrow, scale 0.8, unshifted) flips when a slide starts: opening /
## open turned π at (400, −52) — pointing up —, closing / closed unturned at
## (400, 83) — pointing down. Start state: open on Messages (UI manager
##  = 0, reset and by the main menu's
## the build reads them back, so they last across zones).

const BUTTONS := {"toggle": [Rect2(385, 0, 30, 20), Rect2(), 10200],
	"messages": [Rect2(185, 0, 30, 20), Rect2(2, 128, 30, 20), 10201],
	"items": [Rect2(215, 0, 30, 20), Rect2(2, 150, 30, 20), 10202]}
const SLIDE := 95.0
const SLIDE_SECS := 0.3
const TEXT := Rect2(190, 25, 420, 64)

var messages: RichTextLabel
var listing: RichTextLabel
var mode := 0
var open := true
var _slide := 0.0   # 0 open .. 1 closed
var _laid := []     # [rect, font size, slide, open, mode] last laid out
var _atlas: Texture2D
var _clip: Control
var _bars: Array[DialogPanel.Bar] = [DialogPanel.Bar.new(TEXT, 20.0), DialogPanel.Bar.new(TEXT, 20.0)]
var _content_h := [-1.0, -1.0]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var img := GameData.load_image("battle00") if GameData.is_open() else null
	if img:
		img.flip_y()
		_atlas = ImageTexture.create_from_image(img)
	if DialogPanel._sb == null and GameData.is_open():
		DialogPanel._sb = DialogPanel._flipped("Scrollbar")
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	messages = _text_box()
	listing = _text_box()
	_show_mode()


func _text_box() -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.scroll_active = false
	t.fit_content = true
	t.add_theme_font_override("normal_font", DialogPanel.font())
	t.add_theme_color_override("default_color", DialogPanel.TEXT_COLOR)
	t.add_theme_color_override("font_shadow_color", DialogPanel.SHADOW_COLOR)
	t.add_theme_constant_override("shadow_offset_x", 1)
	t.add_theme_constant_override("shadow_offset_y", 1)
	_clip.add_child(t)
	return t


func _k() -> float:
	return Interface800.canvas_size(self).y / 600.0


func _off() -> float:
	var e := 2.0 * _slide * _slide if _slide < 0.5 else 1.0 - 2.0 * (1.0 - _slide) * (1.0 - _slide)
	return -floorf(SLIDE * e)


## 800×600 point (window part, slid) -> local.
func _p(v: Vector2) -> Vector2:
	var k := _k()
	return Vector2((v.x - 400.0) * k + Interface800.canvas_size(self).x * 0.5, (v.y + _off()) * k)


func _r(r: Rect2) -> Rect2:
	return Rect2(_p(r.position), r.size * _k())


func _button_at(local: Vector2) -> String:
	for b in BUTTONS:
		var r := _toggle_rect() if b == "toggle" else _r(BUTTONS[b][0])
		if r.has_point(local):
			return b
	return ""


## The Open/Close spot stays on screen when the window is slid up.
func _toggle_rect() -> Rect2:
	var k := _k()
	var r: Rect2 = BUTTONS.toggle[0]
	var top := maxf(0.0, (r.position.y - SLIDE * _slide))
	return Rect2(Vector2((r.position.x - 400.0) * k + Interface800.canvas_size(self).x * 0.5, top * k), r.size * k)


func _has_point(p: Vector2) -> bool:
	if _button_at(p) != "":
		return true
	var b := _bars[mode]
	return _slide < 1.0 and b.max_pos > 0.0 and _r(Rect2(TEXT.end.x - 10, TEXT.position.y, 10, TEXT.size.y)).has_point(p)


## Local -> 800×600 (unslid window part).
func _to800(local: Vector2) -> Vector2:
	var k := _k()
	return Vector2((local.x - Interface800.canvas_size(self).x * 0.5) / k + 400.0, local.y / k - _off())


func _gui_input(e: InputEvent) -> void:
	var bar := _bars[mode]
	if e is InputEventMouseMotion and bar.held == 1:
		bar.drag(_to800(e.position))
		_place_text()
		accept_event()
		return
	if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		bar.held = 0
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if _slide < 1.0 and bar.max_pos > 0.0 and bar.press(_to800(e.position)):
		accept_event()
		return
	var b := _button_at(e.position)
	if b.is_empty():
		return
	accept_event()
	match b:
		"toggle":
			open = not open
			_sound("buttons\\battle\\sling.wav")
		"messages": mode = 0
		"items": mode = 1
	_sound("buttons\\battle\\click.wav")
	_show_mode()


func _get_tooltip(at: Vector2) -> String:
	var b := _button_at(at)
	# hotkeys w_text1 / w_text2 (0x32 / 0x33) on the two tabs.
	return GameData.tip_key(GameData.text("tip %d" % BUTTONS[b][2]).strip_edges(),
			{"messages": 50, "items": 51}.get(b, 0)) if b else ""


## the L / K keys (mode 0 / 1).
func key_mode(m: int) -> void:
	if not open:
		open = true
		mode = m
		_sound("buttons\\battle\\sling.wav")
	elif mode != m:
		mode = m
	else:
		open = false
		_sound("buttons\\battle\\sling.wav")
	_show_mode()


func _show_mode() -> void:
	messages.visible = mode == 0
	listing.visible = mode == 1
	if mode == 1:
		_bars[1].set_pos(0.0)
	_place_text()


## the "Collected items" text from the party's money and items.
func build_listing(money: int, items: Array) -> void:
	var text := ""
	if money > 0:
		text += GameData.text("string format_money").replace("%d", str(money))
		if not text.ends_with("\n"):
			text += "\n"
	var order: Array[String] = []
	var counts := {}
	for id in items:
		var s := String(id)
		if not counts.has(s):
			order.append(s)
		counts[s] = int(counts.get(s, 0)) + 1
	for id in order:
		var n: int = counts[id]
		text += Items.log_text(id, n) + "\n"
	listing.clear()
	listing.add_text(text)
	_bars[1].set_pos(0.0)
	_place_text()


func _sound(path: String) -> void:
	if GameSound.instance:
		GameSound.instance.ui(path)


func _process(dt: float) -> void:
	var target := 0.0 if open else 1.0
	_slide = move_toward(_slide, target, dt / SLIDE_SECS)
	var bar := _bars[mode]
	if bar.held >= 2 and bar.hold(dt):
		_place_text()
	# The texts' heights: a new message keeps an at-end view at the end.
	var changed := false
	for i in 2:
		var t: RichTextLabel = [messages, listing][i]
		var h := float(t.get_content_height())
		if h != _content_h[i]:
			var b := _bars[i]
			var at_end := b.pos >= b.max_pos
			_content_h[i] = h
			b.max_pos = maxf(0.0, h - TEXT.size.y * _k())
			if i == 0 and at_end:
				b.set_pos(b.max_pos)
			else:
				b.set_pos(b.pos)
			changed = true
	var r := _r(TEXT)
	var fs := maxi(8, int(round(DialogPanel.FONT_EM * _k())))
	# Only on a change: a theme override relayouts the RichTextLabels.
	var key := [r, fs, _slide, open, mode]
	if key == _laid and not changed:
		return
	_laid = key
	_clip.position = r.position
	_clip.size = r.size
	for i in 2:
		_bars[i].unit = 1.0 / _k()
	for t: RichTextLabel in [messages, listing]:
		t.size = Vector2(r.size.x - 14.0 * _k(), 0.0)
		if t.get_theme_font_size("normal_font_size") != fs:
			t.add_theme_font_size_override("normal_font_size", fs)
	_place_text()


## Scrolls the shown text to its bar's position (px).
func _place_text() -> void:
	messages.position = Vector2(0.0, -floorf(_bars[0].pos))
	listing.position = Vector2(0.0, -floorf(_bars[1].pos))
	queue_redraw()


func _strip(from: Vector2, to: Vector2, width: float, uv: Rect2) -> void:
	if _atlas == null:
		draw_line(_p(from), _p(to), Color(0.6, 0.45, 0.25), width * _k())
		return
	var d := (to - from).normalized().orthogonal() * width * 0.5
	var pts := PackedVector2Array([_p(from - d), _p(to - d), _p(to + d), _p(from + d)])
	var s := _atlas.get_size()
	var uvs := PackedVector2Array([uv.position / s, Vector2(uv.end.x, uv.position.y) / s, uv.end / s,
		Vector2(uv.position.x, uv.end.y) / s])
	draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, _atlas)


func _draw() -> void:
	var k := _k()
	if _slide < 1.0:
		draw_rect(_r(Rect2(180, 20, 440, 75)), Color(0, 0, 0, 0x50 / 255.0))
	draw_rect(_r(Rect2(180, 0, 440, 20)), Color(0, 0, 0, 0xb4 / 255.0))
	for b in ["messages", "items"]:
		var uv: Rect2 = BUTTONS[b][1]
		var lit: bool = (mode == 0) == (b == "messages")
		if _atlas:
			draw_texture_rect_region(_atlas, _r(BUTTONS[b][0]), uv, Color.WHITE if lit else Color(0.5, 0.5, 0.5))
	# Frame: (180,−5)-(620,100), 5 wide.
	var uvf := Rect2(4, 55, 86, 5)
	_strip(Vector2(180, -2.5), Vector2(620, -2.5), 5.0, uvf)
	_strip(Vector2(180, 97.5), Vector2(620, 97.5), 5.0, uvf)
	_strip(Vector2(182.5, -5), Vector2(182.5, 100), 5.0, uvf)
	_strip(Vector2(617.5, -5), Vector2(617.5, 100), 5.0, uvf)
	if _slide < 1.0:
		_draw_bar(_bars[mode])
	# Open / Close spot (in25arrow: a triangle pointing up when open). Only
	# the figure stays on screen: slides every sprite (the bar
	# under it too), so a closed log leaves no black square behind the arrow.
	if _atlas:
		var pts := HudDial.arrow(400, -52, PI, 0.8) if open else HudDial.arrow(400, 83, 0.0, 0.8)
		var uvs := PackedVector2Array()
		for i in 3:
			pts[i] = Vector2((pts[i].x - 400.0) * k + Interface800.canvas_size(self).x * 0.5, pts[i].y * k)
			uvs.append(Vector2(HudDial.ARROW_UV[i].x, 256.0 - HudDial.ARROW_UV[i].y) / 256.0)   # flipped atlas
		draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]), uvs, _atlas)


## The dialog box's scroll bar drawing (DialogPanel._draw_bar).
func _draw_bar(b: DialogPanel.Bar) -> void:
	if b.max_pos <= 0.0:
		return
	var sb := DialogPanel._sb
	if sb == null:
		draw_rect(_r(b.track_rect()), Color(0.45, 0.32, 0.15))
		draw_rect(_r(b.thumb_rect()), Color(0.9, 0.6, 0.2))
		return
	var q := sb.get_size().x / 256.0
	draw_texture_rect_region(sb, _r(b.track_rect()), Rect2(Vector2(8, 4) * q, Vector2(24, 248) * q))
	var up := _r(b.up_rect())
	draw_texture_rect_region(sb, Rect2(up.position, Vector2(up.size.x, -up.size.y)), Rect2(Vector2(40, 128) * q, Vector2(40, 48) * q))
	draw_texture_rect_region(sb, _r(b.down_rect()), Rect2(Vector2(40, 128) * q, Vector2(40, 48) * q))
	draw_texture_rect_region(sb, _r(b.thumb_rect()), Rect2(Vector2(40, 8) * q, Vector2(40, 112) * q))

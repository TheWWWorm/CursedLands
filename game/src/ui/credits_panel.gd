class_name CreditsPanel
extends Control
## Main menu "Authors" board: res/outro.res "credits.scr" is "#scroll 25
## outro.rtf", so the RTF is scrolled up over the music.reg "Credits" track.
## Click or Esc closes it. The original (init) puts the RTF in a RichEdit
## control at 800×600 (10,150)-(790,450); (speed)
## starts its offset at −(box height) in twips and adds
## (now − last) · speed per frame, "now" in 55 ms game ticks
## so "#scroll 25" is 25 twips a tick = 454.5 twips/s = 30.3 px/s at 96 DPI;
## the scroll ends when the offset passes the text's end + 1000
## twips + the box height. **Approx.**: twips → pixels at 96 DPI (15 twips a
## pixel, the original asks GetDeviceCaps), in 800×600 pixels scaled with the
## window like the remake's text (the original's RTF is not scaled). Per frame the
## offset (int twips) becomes __ftol(offset + (now − last) · speed)
## (: truncated toward zero, so it creeps while negative and loses the
## fraction once positive — about 28 px/s at 60 fps), last = now.
## the original credits screens (init, update) are named
## "Titles" (the main menu board) or "Crdt" (screen 8, the end
## the campaign): opening plays config/movie.ini ["<name>fin"], the scroll runs
## over Movies\<name>.bik looping, and when it has ended
## ["<name>fout"] plays before the screen closes.

signal closed

var screen_name := "Titles"
var _bg: MoviePlayer
var _closing := false

const BOX := Rect2(10, 150, 780, 300)   # 800×600
const TWIPS_PX := 15.0                  # 1440 twips / 96 DPI
var _text: RichTextLabel
var _clip: Control
var _speed := 25.0   # twips per 55 ms tick
var _y := 0.0
var _off := 0       # scroll offset in twips
var _started := false
var _music: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# outro.rtf's font table names only Times New Roman (f0, f30..f37).
	for f in ["normal_font", "bold_font", "italics_font", "bold_italics_font"]:
		_text.add_theme_font_override(f, Interface800.font())
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_clip.add_child(_text)
	var arc := EIResArchive.open_path(GameData.res_path("outro.res"))
	var file := "outro.rtf"
	if arc and arc.has("credits.scr"):
		var scr := EIText.ansi(arc.read("credits.scr")).strip_edges().split(" ", false)
		if scr.size() >= 3 and scr[0] == "#scroll":
			_speed = float(scr[1])
			file = scr[2]
	_text.text = rtf_to_bbcode(arc.read(file)) if arc and arc.has(file) else ""
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	var track := String(EIAudio.music_table().get("common", {}).get("Credits", ""))
	_music.stream = EIAudio.music(track) if track else null
	add_child(_music)
	resized.connect(_layout)
	_text.visible = false
	set_process(false)
	var fin := MovieSequence.start(self, MoviePlayer.ini_movies(screen_name + "fin"))
	await fin.done
	_bg = MoviePlayer.new()
	_bg.loop = true
	_bg.silent = true
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	move_child(_bg, 1)   # above the black backdrop, under the text
	_bg.play(screen_name)
	_text.visible = true
	set_process(true)
	if _music.stream:
		_music.play()


func _layout() -> void:
	var k := size.y / 600.0
	_clip.position = Vector2(size.x * 0.5 + (BOX.position.x - 400.0) * k, BOX.position.y * k)
	_clip.size = BOX.size * k
	_text.size.x = _clip.size.x
	_text.position.x = 0.0


func _process(dt: float) -> void:
	var h := _text.get_content_height()
	if size.y <= 0.0 or h <= 0:
		return   # wait for the layout
	if not _started:
		_started = true
		_layout()
		# offset −(box height): the text starts below the box
		_off = -int(BOX.size.y * TWIPS_PX)
	var k := size.y / 600.0
	_off = int(float(_off) + dt / GameUnit.TICK * _speed)   # int(): toward zero, as __ftol
	_y = -float(_off) / TWIPS_PX * k
	_text.position.y = _y
	if _y < -h - (1000.0 / TWIPS_PX) * k - _clip.size.y:
		_close()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and is_processing():
		_close()


func _unhandled_key_input(e: InputEvent) -> void:
	if e.is_pressed() and is_processing():
		_close()


func _close() -> void:
	if _closing:
		return
	_closing = true
	set_process(false)
	_text.visible = false
	_music.stop()
	if _bg:
		_bg.stop()
	var fout := MovieSequence.start(self, MoviePlayer.ini_movies(screen_name + "fout"))
	await fout.done
	closed.emit()
	queue_free()


## Minimal RTF reader for outro.rtf: paragraphs, bold, font size, centring and
## the colour table; font tables, styles and info groups are skipped.
static func rtf_to_bbcode(data: PackedByteArray) -> String:
	var src := EIText.ansi(data)
	var out := ""
	var colors: Array[Color] = []
	var skip_depth := -1
	var depth := 0
	var stack: Array[Dictionary] = []
	var st := {"b": false, "fs": 24, "cf": 0}
	var line := ""
	var line_fmt := {}
	var i := 0
	var n := src.length()
	# Colour table.
	var ct := src.find("{\\colortbl")
	if ct >= 0:
		var end := src.find("}", ct)
		for entry in src.substr(ct + 10, end - ct - 10).split(";"):
			var r := _num(entry, "\\red")
			var g := _num(entry, "\\green")
			var bl := _num(entry, "\\blue")
			colors.append(Color8(r, g, bl) if entry.contains("\\red") else Color.WHITE)
	while i < n:
		var ch := src[i]
		if ch == "{":
			depth += 1
			stack.append(st.duplicate())
			var rest := src.substr(i + 1, 12)
			if skip_depth < 0 and (rest.begins_with("\\*") or rest.begins_with("\\fonttbl") or rest.begins_with("\\colortbl")
					or rest.begins_with("\\stylesheet") or rest.begins_with("\\info")):
				skip_depth = depth
			i += 1
		elif ch == "}":
			if skip_depth == depth:
				skip_depth = -1
			depth -= 1
			if not stack.is_empty():
				st = stack.pop_back()
			i += 1
		elif ch == "\\":
			i += 1
			if i >= n:
				break
			var c2 := src[i]
			if c2 == "'":
				if skip_depth < 0:
					var code := src.substr(i + 1, 2).hex_to_int()
					line += EIText.ansi(PackedByteArray([code]))
				i += 3
				continue
			if not (c2.to_lower() >= "a" and c2.to_lower() <= "z"):
				if skip_depth < 0 and c2 in ["\\", "{", "}"]:
					line += c2
				i += 1
				continue
			var j := i
			while j < n and src[j].to_lower() >= "a" and src[j].to_lower() <= "z":
				j += 1
			var word := src.substr(i, j - i)
			var k := j
			if k < n and (src[k] == "-" or src[k].is_valid_int()):
				k += 1
				while k < n and src[k].is_valid_int():
					k += 1
			var arg := src.substr(j, k - j)
			if k < n and src[k] == " ":
				k += 1
			i = k
			if skip_depth >= 0:
				continue
			match word:
				"par":
					out += _line_bb(line, line_fmt)
					line = ""
					line_fmt = {}
				"b": st.b = arg != "0"
				"fs": st.fs = int(arg)
				"cf": st.cf = int(arg)
				"plain": st = {"b": false, "fs": 24, "cf": 0}
				"tab": line += " "
			continue
		elif ch == "\n" or ch == "\r":
			i += 1
		else:
			if skip_depth < 0:
				if String(line).strip_edges().is_empty():
					line_fmt = {"b": st.b, "fs": st.fs,
						"color": colors[st.cf] if st.cf > 0 and st.cf < colors.size() else Color(0.85, 0.85, 0.8)}
				line += ch
			i += 1
	out += _line_bb(line, line_fmt)
	return out


static func _line_bb(line: String, fmt: Dictionary) -> String:
	var t := line.strip_edges()
	if t:
		var fs := int(fmt.get("fs", 24))
		var c: Color = fmt.get("color", Color(0.85, 0.85, 0.8))
		t = t.replace("[", "[lb]")
		if fmt.get("b", false):
			t = "[b]%s[/b]" % t
		t = "[font_size=%d][color=#%s]%s[/color][/font_size]" % [maxi(12, fs * 3 / 4 + 4), c.to_html(false), t]
	return "[center]%s[/center]\n" % t


static func _num(s: String, key: String) -> int:
	var p := s.find(key)
	if p < 0:
		return 0
	p += key.length()
	var e := p
	while e < s.length() and s[e].is_valid_int():
		e += 1
	return s.substr(p, e - p).to_int()
